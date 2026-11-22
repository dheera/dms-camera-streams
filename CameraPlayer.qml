import QtQuick
import QtMultimedia

// Kept behind a Loader so the picker still works without Qt Multimedia installed.
Item {
    id: root

    property string streamUrl: ""
    property bool active: false
    property bool muted: true
    property bool autoReconnect: true
    property string failure: ""
    property int retryCount: 0
    property bool hasFrame: false
    readonly property bool live: active && hasFrame && !failure
    readonly property bool connecting: active && !hasFrame && !failure
    readonly property bool retryPending: retryTimer.running
    readonly property string statusText: !active ? "Stopped" : failure ? (retryPending ? "Reconnecting…" : "Unavailable") : live ? "Live" : "Connecting…"
    // Exposed for lifecycle verification, never displayed or logged.
    readonly property url currentSource: player.source

    function release() {
        connectTimer.stop();
        staleTimer.stop();
        retryTimer.stop();
        startTimer.stop();
        player.stop();
        player.source = "";
        hasFrame = false;
        video.clearOutput();
    }

    function restart() {
        release();
        failure = "";
        if (active && streamUrl)
            startTimer.start();
    }

    function retry() {
        retryCount = 0;
        restart();
    }

    function fail(message) {
        if (!active || !streamUrl || failure)
            return;
        failure = message;
        release();
        if (autoReconnect) {
            retryTimer.interval = Math.min(30000, 2000 * Math.pow(2, Math.min(retryCount, 4)));
            retryCount++;
            retryTimer.start();
        }
    }

    onStreamUrlChanged: retry()
    onActiveChanged: retry()
    onAutoReconnectChanged: {
        if (!autoReconnect)
            retryTimer.stop();
        else if (active && failure)
            retry();
    }
    Component.onCompleted: restart()
    Component.onDestruction: release()

    VideoOutput {
        id: video
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectFit
    }

    MediaPlayer {
        id: player
        videoOutput: video
        audioOutput: AudioOutput { muted: root.muted }
        // Qt 6.10+: bounded network waits and a smaller live-stream buffer.
        playbackOptions.playbackIntent: PlaybackOptions.LowLatencyStreaming
        playbackOptions.networkTimeoutMs: 10000
        onErrorOccurred: (error, errorString) => {
            // Backend error strings can contain camera passwords/tokens.
            root.fail("Could not play this camera. Check its address and connection, or open it in mpv.");
        }
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.EndOfMedia)
                root.fail("The camera disconnected.");
        }
    }

    Connections {
        target: video.videoSink
        function onVideoFrameChanged() {
            if (!root.active || player.playbackState !== MediaPlayer.PlayingState
                    || video.videoSink.videoSize.width <= 0 || video.videoSink.videoSize.height <= 0)
                return;
            root.hasFrame = true;
            root.retryCount = 0;
            connectTimer.stop();
            staleTimer.restart();
        }
    }

    Timer {
        id: startTimer
        interval: 50
        onTriggered: {
            if (!root.active || !root.streamUrl)
                return;
            player.source = root.streamUrl;
            player.play();
            connectTimer.start();
        }
    }
    Timer {
        id: connectTimer
        interval: 15000
        onTriggered: root.fail("The camera did not send video. Retry or open it in mpv.")
    }
    Timer {
        id: staleTimer
        interval: 15000
        onTriggered: root.fail("The camera stopped sending video.")
    }
    Timer {
        id: retryTimer
        onTriggered: root.restart()
    }
}
