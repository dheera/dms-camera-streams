import QtQuick

// Still-image cameras: periodically re-fetches an HTTP(S) JPEG/PNG while active.
// Exposes the same interface as CameraPlayer.qml so the viewers can swap them.
Item {
    id: root

    property string streamUrl: ""
    property bool active: false
    property bool muted: true // Unused; snapshots have no audio.
    property bool autoReconnect: true
    property int refreshInterval: 30000
    property string failure: ""
    property int retryCount: 0
    property bool hasFrame: false
    property date lastUpdated: new Date()
    // Two images alternate so the old frame stays visible while the next one loads.
    property int frontIndex: 0
    readonly property bool isSnapshot: true
    readonly property string badgeText: "SNAPSHOT"
    readonly property bool live: active && hasFrame && !failure
    readonly property bool connecting: active && !hasFrame && !failure
    readonly property bool retryPending: retryTimer.running
    readonly property string statusText: !active ? "Stopped" : failure ? (retryPending ? "Retrying…" : "Unavailable") : live ? "Updated " + Qt.formatTime(lastUpdated, "hh:mm:ss") : "Loading…"
    // Exposed for lifecycle verification, never displayed or logged.
    readonly property url currentSource: imageA.source.toString() || imageB.source.toString()

    function backImage() {
        return frontIndex === 0 ? imageB : imageA;
    }

    function release() {
        startTimer.stop();
        loadTimer.stop();
        refreshTimer.stop();
        retryTimer.stop();
        imageA.source = "";
        imageB.source = "";
        hasFrame = false;
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

    function fetch() {
        if (!active || !streamUrl)
            return;
        const image = backImage();
        // Image does not reload an unchanged source; clear it first. cache: false skips the pixmap cache.
        image.source = "";
        // Start the timeout first: a fast load can report Ready synchronously.
        loadTimer.restart();
        image.source = streamUrl;
    }

    function handleStatus(image) {
        if (image !== backImage() || !image.source.toString())
            return;
        if (image.status === Image.Ready) {
            loadTimer.stop();
            const previous = frontIndex === 0 ? imageA : imageB;
            frontIndex = image === imageA ? 0 : 1;
            previous.source = "";
            hasFrame = true;
            retryCount = 0;
            lastUpdated = new Date();
            refreshTimer.restart();
        } else if (image.status === Image.Error) {
            // Error strings can contain the URL and its credentials.
            fail("Could not load this camera's image. Check its address and that it returns a JPEG or PNG.");
        }
    }

    onStreamUrlChanged: retry()
    onActiveChanged: retry()
    onRefreshIntervalChanged: {
        if (refreshTimer.running)
            refreshTimer.restart();
    }
    onAutoReconnectChanged: {
        if (!autoReconnect)
            retryTimer.stop();
        else if (active && failure)
            retry();
    }
    Component.onCompleted: restart()
    Component.onDestruction: release()

    Image {
        id: imageA
        anchors.fill: parent
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: false
        smooth: true
        visible: root.hasFrame && root.frontIndex === 0
        onStatusChanged: root.handleStatus(imageA)
    }

    Image {
        id: imageB
        anchors.fill: parent
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: false
        smooth: true
        visible: root.hasFrame && root.frontIndex === 1
        onStatusChanged: root.handleStatus(imageB)
    }

    Timer {
        id: startTimer
        interval: 50
        onTriggered: root.fetch()
    }
    Timer {
        id: loadTimer
        interval: 15000
        onTriggered: {
            root.backImage().source = "";
            root.fail("The camera did not return an image. Retry or check its address.");
        }
    }
    Timer {
        id: refreshTimer
        interval: Math.max(1000, root.refreshInterval)
        onTriggered: root.fetch()
    }
    Timer {
        id: retryTimer
        onTriggered: root.restart()
    }
}
