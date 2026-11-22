.pragma library

function validateCamera(name, url) {
    if (typeof name !== "string" || !name.trim())
        return "Give this camera a name.";
    if (typeof url !== "string" || !url.trim())
        return "Enter an RTSP or RTSPS stream URL.";
    // Require a host; reject whitespace/control characters without rewriting tokens.
    if (!/^rtsps?:\/\/(?:[^\s\/@]+@)?(?:\[[0-9a-fA-F:]+\]|[^\s\/:?#@]+)(?::[0-9]+)?(?:[\/?#][^\s]*)?$/i.test(url.trim()))
        return "Use a complete rtsp:// or rtsps:// URL. Encode spaces as %20.";
    return "";
}

function normalizeCameras(value) {
    if (!Array.isArray(value))
        return [];
    var seen = Object.create(null);
    return value.filter(function(camera) {
        return camera && !validateCamera(camera.name, camera.url);
    }).map(function(camera, index) {
        var id = typeof camera.id === "string" && camera.id ? camera.id : "camera-" + index;
        while (Object.prototype.hasOwnProperty.call(seen, id))
            id += "-" + index;
        seen[id] = true;
        return { id: id, name: camera.name.trim(), url: camera.url.trim() };
    });
}

function createCameraId() {
    return "camera-" + Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 10);
}

function selectedCamera(cameras, id) {
    return cameras.find(function(camera) { return camera.id === id; }) || cameras[0] || null;
}

function mpvArguments(camera, muted) {
    return ["mpv", "--no-config", "--profile=low-latency", "--rtsp-transport=tcp",
            "--force-window=immediate", "--no-terminal", "--title=" + camera.name,
            "--mute=" + (muted ? "yes" : "no"), "--", camera.url];
}
