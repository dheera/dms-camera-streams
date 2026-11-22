import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.DCommon.Widgets

PanelWindow {
    id: root

    property bool opened: false
    property bool locked: false
    property string cameraName: "Camera"
    property string streamUrl: ""
    property bool muted: true
    property bool autoReconnect: true
    property bool multipleCameras: false
    property bool stopped: false
    readonly property var player: playerLoader.item

    signal exitRequested
    signal muteRequested
    signal cameraStepRequested(int direction)

    visible: opened && !locked
    color: "#090c10"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "dms:plugins:camera-streams-fullscreen"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onVisibleChanged: {
        if (visible) {
            stopped = false;
            Qt.callLater(() => content.forceActiveFocus());
        }
    }
    onStreamUrlChanged: stopped = false

    function retry() {
        stopped = false;
        player?.retry();
    }

    Item {
        id: content
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Escape:
            case Qt.Key_F11:
                root.exitRequested();
                break;
            case Qt.Key_Left:
                root.cameraStepRequested(-1);
                break;
            case Qt.Key_Right:
                root.cameraStepRequested(1);
                break;
            case Qt.Key_M:
                root.muteRequested();
                break;
            default:
                return;
            }
            event.accepted = true;
        }

        Loader {
            id: playerLoader
            anchors.fill: parent
            active: root.visible && root.streamUrl !== ""
            source: Qt.resolvedUrl("./CameraPlayer.qml")
            onLoaded: {
                item.streamUrl = Qt.binding(() => root.streamUrl);
                item.muted = Qt.binding(() => root.muted);
                item.autoReconnect = Qt.binding(() => root.autoReconnect);
                item.active = Qt.binding(() => root.visible && !root.stopped);
            }
        }

        Column {
            anchors.centerIn: parent
            width: Math.min(parent.width - 64, 560)
            spacing: Theme.spacingL
            visible: !root.player?.live

            DIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: root.player?.connecting ? "wifi" : "videocam_off"
                size: 48
                color: "#c4cbd4"
            }
            StyledText {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Theme.fontSizeLarge
                color: "#f2f4f8"
                text: root.stopped ? "Preview stopped" : playerLoader.status === Loader.Error ? "Video player unavailable" : root.player?.statusText || "Connecting…"
            }
            StyledText {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: "#b4bdca"
                text: playerLoader.status === Loader.Error ? "Install Qt 6.10+ Multimedia, or return to the popout and open in mpv." : root.player?.failure || ""
                visible: text.length > 0
            }
            DButton {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.stopped || !!root.player?.failure
                text: root.stopped ? "Start preview" : "Retry now"
                iconName: root.stopped ? "play_arrow" : "refresh"
                onClicked: root.retry()
            }
        }

        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: toolbar.implicitHeight + Theme.spacingM * 2
            color: "#dc101820"

            Row {
                id: toolbar
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingM

                Column {
                    width: Math.max(0, parent.width - buttons.implicitWidth - parent.spacing)
                    anchors.verticalCenter: parent.verticalCenter
                    StyledText {
                        width: parent.width
                        text: root.cameraName
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.Medium
                        color: "#f2f4f8"
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                    }
                    StyledText {
                        text: root.player?.statusText || "Ready"
                        color: "#b4bdca"
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }

                Row {
                    id: buttons
                    spacing: Theme.spacingS
                    DActionButton {
                        iconName: "chevron_left"
                        iconColor: "#f2f4f8"
                        tooltipText: "Previous camera (←)"
                        visible: root.multipleCameras
                        onClicked: root.cameraStepRequested(-1)
                    }
                    DActionButton {
                        iconName: "chevron_right"
                        iconColor: "#f2f4f8"
                        tooltipText: "Next camera (→)"
                        visible: root.multipleCameras
                        onClicked: root.cameraStepRequested(1)
                    }
                    DActionButton {
                        iconName: root.muted ? "volume_off" : "volume_up"
                        iconColor: "#f2f4f8"
                        tooltipText: root.muted ? "Unmute (M)" : "Mute (M)"
                        onClicked: root.muteRequested()
                    }
                    DActionButton {
                        iconName: root.stopped ? "play_arrow" : "stop"
                        iconColor: "#f2f4f8"
                        tooltipText: root.stopped ? "Start preview" : "Stop preview"
                        onClicked: root.stopped = !root.stopped
                    }
                    DActionButton {
                        iconName: "refresh"
                        iconColor: "#f2f4f8"
                        tooltipText: "Reconnect"
                        onClicked: root.retry()
                    }
                    DButton {
                        text: "Exit fullscreen"
                        iconName: "fullscreen_exit"
                        tooltipText: "Return to the bar viewer (Esc)"
                        onClicked: root.exitRequested()
                    }
                }
            }
        }
    }
}
