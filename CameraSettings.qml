import QtQuick
import Quickshell.Io
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins
import "StreamUtils.js" as StreamUtils

PluginSettings {
    id: root
    pluginId: "cameraStreams"

    property var cameras: []
    property var localCameras: []
    property string editingId: ""
    property bool editorOpen: false
    property string validationMessage: ""
    property string pendingDeleteId: ""

    function openEditor(camera) {
        editingId = camera ? camera.id : "";
        nameField.text = camera ? camera.name : "";
        urlField.text = camera ? camera.url : "";
        urlField.passwordVisible = false;
        validationMessage = "";
        pendingDeleteId = "";
        editorOpen = true;
        Qt.callLater(function () {
            root.ensureItemVisible(editorCard);
            nameField.forceActiveFocus();
        });
    }

    function closeEditor() {
        editorOpen = false;
        editingId = "";
        nameField.text = "";
        urlField.text = "";
        urlField.passwordVisible = false;
        validationMessage = "";
    }

    function saveCamera() {
        validationMessage = StreamUtils.validateCamera(nameField.text, urlField.text);
        if (validationMessage)
            return;
        if (!pluginService) {
            validationMessage = "Settings are not ready yet. Try again in a moment.";
            return;
        }
        const updated = cameras.slice();
        const camera = {
            id: editingId || StreamUtils.createCameraId(),
            name: nameField.text.trim(),
            url: urlField.text.trim()
        };
        if (editingId) {
            const index = updated.findIndex(item => item.id === editingId);
            if (index < 0) {
                validationMessage = "This camera was removed. Cancel and add it again.";
                return;
            }
            updated[index] = camera;
        } else {
            updated.push(camera);
        }
        root.saveValue("cameras", updated);
        cameras = updated;
        closeEditor();
    }

    function removeCamera(cameraId) {
        if (!pluginService)
            return;
        const updated = cameras.filter(camera => camera.id !== cameraId);
        root.saveValue("cameras", updated);
        cameras = updated;
        pendingDeleteId = "";
        if (editingId === cameraId)
            closeEditor();
    }

    FileView {
        id: localDefaults
        printErrors: false
        path: decodeURIComponent(Qt.resolvedUrl("./cameras.local.json").toString().replace(/^file:\/\//, ""))
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.localCameras = StreamUtils.normalizeCameras(JSON.parse(text()));
            } catch (error) {
                root.localCameras = [];
            }
            camerasSection.loadValue();
        }
        onLoadFailed: {
            root.localCameras = [];
            camerasSection.loadValue();
        }
    }

    Column {
        id: camerasSection
        width: parent.width
        spacing: Theme.spacingM

        // PluginSettings calls this on service injection and settings changes.
        function loadValue() {
            const saved = root.loadValue("cameras", null);
            root.cameras = StreamUtils.normalizeCameras(saved === null ? root.localCameras : saved);
        }

        Component.onCompleted: Qt.callLater(loadValue)

        StyledText {
            width: parent.width
            text: "Camera Streams"
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.Bold
            color: Theme.surfaceText
        }

        StyledText {
            width: parent.width
            text: "Add your cameras, then tap the camera icon in the bar to watch and switch between them."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }

        StyledRect {
            width: parent.width
            height: emptyLabel.implicitHeight + Theme.spacingL * 2
            visible: root.cameras.length === 0
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            StyledText {
                id: emptyLabel
                anchors.centerIn: parent
                width: parent.width - Theme.spacingL * 2
                text: "No cameras yet. Add a name and an RTSP stream or HTTP snapshot URL below."
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }
        }

        Repeater {
            model: root.cameras

            StyledRect {
                id: cameraCard
                required property var modelData
                readonly property bool confirmingDelete: root.pendingDeleteId === modelData.id
                width: camerasSection.width
                height: cameraRow.height + Theme.spacingM * 2 + (confirmingDelete ? deletionRow.height + Theme.spacingS : 0)
                radius: Theme.cornerRadius
                color: Theme.surfaceContainerHigh

                Row {
                    id: cameraRow
                    x: Theme.spacingM
                    y: Theme.spacingM
                    width: parent.width - Theme.spacingM * 2
                    spacing: Theme.spacingS

                    DIcon {
                        name: "videocam"
                        size: Theme.iconSize
                        color: Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                        width: parent.width - Theme.iconSize - editButton.width - deleteButton.width - parent.spacing * 3
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingXS

                        StyledText {
                            width: parent.width
                            text: cameraCard.modelData.name
                            textFormat: Text.PlainText
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                            elide: Text.ElideRight
                        }

                        StyledText {
                            width: parent.width
                            text: StreamUtils.cameraKindLabel(cameraCard.modelData.url)
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }

                    DActionButton {
                        id: editButton
                        anchors.verticalCenter: parent.verticalCenter
                        iconName: "edit"
                        tooltipText: "Edit " + cameraCard.modelData.name
                        onClicked: root.openEditor(cameraCard.modelData)
                    }

                    DActionButton {
                        id: deleteButton
                        anchors.verticalCenter: parent.verticalCenter
                        iconName: "delete"
                        tooltipText: "Remove " + cameraCard.modelData.name
                        onClicked: root.pendingDeleteId = cameraCard.confirmingDelete ? "" : cameraCard.modelData.id
                    }
                }

                Row {
                    id: deletionRow
                    x: Theme.spacingM
                    y: cameraRow.y + cameraRow.height + Theme.spacingS
                    visible: cameraCard.confirmingDelete
                    spacing: Theme.spacingS

                    DButton {
                        text: "Remove camera"
                        danger: true
                        onClicked: root.removeCamera(cameraCard.modelData.id)
                    }

                    DButton {
                        text: "Cancel"
                        variant: "text"
                        onClicked: root.pendingDeleteId = ""
                    }
                }
            }
        }

        DButton {
            text: "Add camera"
            iconName: "add"
            variant: "tonal"
            visible: !root.editorOpen
            onClicked: root.openEditor(null)
        }

        StyledRect {
            id: editorCard
            width: parent.width
            height: editorContents.implicitHeight + Theme.spacingL * 2
            visible: root.editorOpen
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            Column {
                id: editorContents
                x: Theme.spacingL
                y: Theme.spacingL
                width: parent.width - Theme.spacingL * 2
                spacing: Theme.spacingS

                StyledText {
                    text: root.editingId ? "Edit camera" : "New camera"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                }

                StyledText {
                    text: "Name"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }

                DTextField {
                    id: nameField
                    width: parent.width
                    Accessible.name: "Camera name"
                    placeholderText: "Driveway"
                    maximumLength: 80
                    onAccepted: urlField.forceActiveFocus()
                }

                StyledText {
                    text: "Stream or image URL"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }

                DTextField {
                    id: urlField
                    width: parent.width
                    Accessible.name: "Camera stream URL"
                    placeholderText: "rtsp://, rtsps://, http:// or https://"
                    echoMode: TextInput.Password
                    showPasswordToggle: true
                    maximumLength: 8192
                    onAccepted: root.saveCamera()
                }

                StyledText {
                    width: parent.width
                    text: "Paste the complete URL, including any query parameters. RTSP URLs play live video; HTTP(S) URLs must return a JPEG or PNG, refreshed while the viewer is open. URLs are saved locally in DMS plugin settings."
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }

                StyledText {
                    width: parent.width
                    text: root.validationMessage
                    textFormat: Text.PlainText
                    visible: text.length > 0
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.error
                    wrapMode: Text.WordWrap
                }

                Row {
                    spacing: Theme.spacingS

                    DButton {
                        text: "Save camera"
                        iconName: "check"
                        onClicked: root.saveCamera()
                    }

                    DButton {
                        text: "Cancel"
                        variant: "text"
                        onClicked: root.closeEditor()
                    }
                }
            }
        }
    }

    ToggleSetting {
        settingKey: "showLabel"
        label: "Show camera name in the bar"
        description: "Turn off for a compact camera icon."
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "muted"
        label: "Start muted"
        description: "Camera audio is muted each time you open the viewer."
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "autoReconnect"
        label: "Reconnect automatically"
        description: "Retry interrupted streams while the viewer is open."
        defaultValue: true
    }

    SliderSetting {
        settingKey: "previewWidth"
        label: "Viewer width"
        description: "The viewer adapts to the available screen space."
        minimum: 480
        maximum: 960
        defaultValue: 640
        unit: "px"
    }

    SliderSetting {
        settingKey: "snapshotInterval"
        label: "Snapshot refresh interval"
        description: "How often HTTP(S) image cameras reload while the viewer is open."
        minimum: 5
        maximum: 300
        defaultValue: 30
        unit: "s"
    }
}
