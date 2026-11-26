import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Plugins
import "."
import "StreamUtils.js" as StreamUtils

PluginComponent {
    id: root
    layerNamespacePlugin: "camera-streams"

    property var localCameras: []
    readonly property var cameras: StreamUtils.normalizeCameras(pluginData.cameras ?? localCameras)
    property string selectedId: pluginData.selectedCameraId || ""
    readonly property var camera: StreamUtils.selectedCamera(cameras, selectedId)
    readonly property bool showLabel: pluginData.showLabel ?? true
    property bool muted: pluginData.muted ?? true
    property bool fullscreenOpen: false
    property bool returningFromFullscreen: false
    readonly property var fullscreenViewer: fullscreenView
    readonly property bool autoReconnect: pluginData.autoReconnect ?? true
    readonly property bool isSnapshot: StreamUtils.isSnapshotUrl(camera?.url)
    readonly property int snapshotInterval: StreamUtils.snapshotIntervalMs(pluginData.snapshotInterval)
    readonly property string playerSource: Qt.resolvedUrl(isSnapshot ? "./SnapshotPlayer.qml" : "./CameraPlayer.qml")
    readonly property real desiredWidth: Math.max(480, Math.min(960, Number(pluginData.previewWidth) || 640))
    popoutWidth: Math.min(desiredWidth, Math.max(320, (parentScreen?.width || 1920) - 32))

    function selectCamera(id) {
        selectedId = id;
        pluginService?.savePluginData(pluginId, "selectedCameraId", id);
    }

    function nextCamera(direction) {
        if (!camera || cameras.length < 2)
            return;
        const index = cameras.findIndex(item => item.id === camera.id);
        selectCamera(cameras[(index + direction + cameras.length) % cameras.length].id);
    }

    function openInMpv() {
        if (!camera || isSnapshot)
            return;
        Quickshell.execDetached(StreamUtils.mpvArguments(camera, muted));
        closePopout();
    }

    function enterFullscreen() {
        if (!camera || SessionService.locked)
            return;
        // This disables the popout player before opening the fullscreen stream.
        fullscreenOpen = true;
        closePopout();
    }

    function exitFullscreen(reopenPopout = true) {
        if (!fullscreenOpen)
            return;
        fullscreenOpen = false;
        if (reopenPopout && camera && !SessionService.locked) {
            returningFromFullscreen = true;
            Qt.callLater(() => {
                if (root.camera && !SessionService.locked)
                    root.triggerPopout();
                else
                    root.returningFromFullscreen = false;
            });
        }
    }

    onCameraChanged: {
        if (!camera)
            exitFullscreen(false);
    }

    Connections {
        target: SessionService
        function onLockedChanged() {
            if (SessionService.locked)
                root.exitFullscreen(false);
        }
    }

    CameraFullscreen {
        id: fullscreenView
        screen: root.parentScreen?.name ? root.parentScreen : null
        opened: root.fullscreenOpen
        locked: SessionService.locked
        cameraName: root.camera?.name || "Camera"
        streamUrl: root.camera?.url || ""
        muted: root.muted
        autoReconnect: root.autoReconnect
        isSnapshot: root.isSnapshot
        playerSource: root.playerSource
        snapshotInterval: root.snapshotInterval
        multipleCameras: root.cameras.length > 1
        onExitRequested: root.exitFullscreen()
        onMuteRequested: root.muted = !root.muted
        onCameraStepRequested: direction => root.nextCamera(direction)
    }

    FileView {
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
        }
        onLoadFailed: root.localCameras = []
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS
            DIcon {
                name: "videocam"
                size: root.iconSize
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                visible: root.showLabel
                text: root.camera?.name || "Cameras"
                textFormat: Text.PlainText
                width: Math.min(implicitWidth, 160)
                elide: Text.ElideRight
                font.pixelSize: root.textSize
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        DIcon {
            name: "videocam"
            size: root.iconSize
            color: Theme.primary
        }
    }

    popoutContent: Component {
        PopoutComponent {
            id: panel
            headerText: "Camera Streams"
            property bool stopped: false
            readonly property bool opened: parentPopout?.shouldBeVisible ?? false
            readonly property bool shouldPlay: opened && !root.fullscreenOpen && !stopped && !SessionService.locked && root.camera !== null
            readonly property var player: playerLoader.item
            // Screen height left for the picker and video after the fixed rows.
            readonly property real contentSpace: (root.parentScreen?.height || 1080) - root.barThickness - root.barSpacing
                - headerHeight - (cameraInfo.visible ? cameraInfo.height : 0) - footer.implicitHeight
                - Theme.spacingM * 4 - 64

            onOpenedChanged: {
                if (opened) {
                    stopped = false;
                    if (!root.returningFromFullscreen)
                        root.muted = root.pluginData.muted ?? true;
                    root.returningFromFullscreen = false;
                }
            }

            Connections {
                target: root
                function onCameraChanged() { panel.stopped = false; }
            }

            headerActions: Component {
                DActionButton {
                    iconName: "close"
                    tooltipText: "Close cameras"
                    onClicked: root.closePopout()
                }
            }

            Column {
                width: parent.width
                spacing: Theme.spacingM

                // Wrapping camera buttons keep small camera collections one tap away.
                Flickable {
                    id: picker
                    width: parent.width
                    // Show every camera button; scroll only if the video would drop below 180px.
                    height: Math.min(cameraButtons.implicitHeight, Math.max(100, panel.contentSpace - 180))
                    contentWidth: width
                    contentHeight: cameraButtons.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    visible: root.cameras.length > 1

                    Flow {
                        id: cameraButtons
                        width: picker.width
                        spacing: Theme.spacingS
                        Repeater {
                            model: root.cameras
                            DButton {
                                required property var modelData
                                text: modelData.name
                                maximumWidth: picker.width
                                iconName: root.camera?.id === modelData.id ? "videocam" : ""
                                variant: root.camera?.id === modelData.id ? "filled" : "tonal"
                                onClicked: root.selectCamera(modelData.id)
                            }
                        }
                    }
                }

                Rectangle {
                    id: viewport
                    width: parent.width
                    height: Math.min(width * 9 / 16, Math.max(100,
                        panel.contentSpace - (picker.visible ? picker.height : 0)))
                    color: "#090c10"
                    radius: Theme.cornerRadius
                    clip: true

                    Loader {
                        id: playerLoader
                        anchors.fill: parent
                        active: panel.opened && !root.fullscreenOpen && root.camera !== null
                        source: root.playerSource
                        onLoaded: {
                            item.streamUrl = Qt.binding(() => root.camera?.url || "");
                            if (item.isSnapshot)
                                item.refreshInterval = Qt.binding(() => root.snapshotInterval);
                            item.muted = Qt.binding(() => root.muted);
                            item.autoReconnect = Qt.binding(() => root.autoReconnect);
                            item.active = Qt.binding(() => panel.shouldPlay);
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        width: parent.width - Theme.spacingXL * 2
                        spacing: Theme.spacingM
                        visible: !panel.player?.live

                        DIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            name: !root.camera ? "videocam_off" : panel.player?.connecting ? "wifi" : "videocam_off"
                            size: 36
                            color: "#c4cbd4"
                        }
                        StyledText {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            color: "#f2f4f8"
                            font.pixelSize: Theme.fontSizeLarge
                            text: !root.camera ? "Your cameras, one tap away" : panel.stopped ? "Preview stopped" : SessionService.locked ? "Session locked" : playerLoader.status === Loader.Error ? "Video player unavailable" : panel.player?.statusText || "Connecting…"
                        }
                        StyledText {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            color: "#b4bdca"
                            font.pixelSize: Theme.fontSizeSmall
                            wrapMode: Text.WordWrap
                            text: !root.camera ? "Add a camera in Settings → Plugins → Camera Streams." : playerLoader.status === Loader.Error ? "Install Qt 6.10+ Multimedia, or use Open in mpv below." : panel.player?.failure || ""
                            visible: text.length > 0
                        }
                        DButton {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: panel.stopped ? "Start preview" : "Retry now"
                            iconName: panel.stopped ? "play_arrow" : "refresh"
                            visible: !!root.camera && (panel.stopped || !!panel.player?.failure)
                            onClicked: {
                                panel.stopped = false;
                                panel.player?.retry();
                            }
                        }
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.margins: Theme.spacingM
                        width: liveRow.implicitWidth + Theme.spacingM * 2
                        height: 26
                        radius: 13
                        color: "#bb101820"
                        visible: panel.player?.live ?? false

                        Row {
                            id: liveRow
                            anchors.centerIn: parent
                            spacing: 6
                            Rectangle {
                                width: 6
                                height: 6
                                radius: 3
                                color: "#79e8ac"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            StyledText {
                                text: panel.player?.badgeText || "LIVE"
                                color: "white"
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                font.letterSpacing: 1
                            }
                        }
                    }
                }

                Row {
                    id: cameraInfo
                    width: parent.width
                    spacing: Theme.spacingS
                    visible: root.camera !== null

                    Column {
                        width: Math.max(0, parent.width - controls.width - parent.spacing)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingXS
                        StyledText {
                            width: parent.width
                            text: root.camera?.name || ""
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                        }
                        StyledText {
                            text: panel.player?.statusText || (panel.stopped ? "Stopped" : "Ready")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }

                    Row {
                        id: controls
                        spacing: Theme.spacingXS
                        DActionButton {
                            iconName: "chevron_left"
                            tooltipText: "Previous camera"
                            visible: root.cameras.length > 1
                            onClicked: root.nextCamera(-1)
                        }
                        DActionButton {
                            iconName: "chevron_right"
                            tooltipText: "Next camera"
                            visible: root.cameras.length > 1
                            onClicked: root.nextCamera(1)
                        }
                        DActionButton {
                            iconName: root.muted ? "volume_off" : "volume_up"
                            tooltipText: root.muted ? "Unmute camera" : "Mute camera"
                            visible: !root.isSnapshot
                            onClicked: root.muted = !root.muted
                        }
                        DActionButton {
                            iconName: panel.stopped ? "play_arrow" : "stop"
                            tooltipText: panel.stopped ? "Start preview" : "Stop preview"
                            onClicked: panel.stopped = !panel.stopped
                        }
                        DActionButton {
                            iconName: "refresh"
                            tooltipText: root.isSnapshot ? "Refresh now" : "Reconnect"
                            onClicked: {
                                panel.stopped = false;
                                panel.player?.retry();
                            }
                        }
                    }
                }

                Flow {
                    id: footer
                    width: parent.width
                    spacing: Theme.spacingS
                    DButton {
                        text: "Fullscreen"
                        iconName: "fullscreen"
                        variant: "tonal"
                        visible: root.camera !== null
                        onClicked: root.enterFullscreen()
                    }
                    DButton {
                        text: "Open in mpv"
                        iconName: "open_in_new"
                        variant: "tonal"
                        visible: root.camera !== null && !root.isSnapshot
                        onClicked: root.openInMpv()
                    }
                    DButton {
                        text: "Camera settings"
                        iconName: "settings"
                        variant: "text"
                        onClicked: {
                            root.closePopout();
                            PluginService.pendingSettingsRevealPluginId = root.pluginId;
                            PopoutService.openSettingsWithTab("plugins");
                        }
                    }
                }
            }
        }
    }
}
