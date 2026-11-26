#!/usr/bin/env python3
"""Load the plugin against real DMS in a hidden window and exercise video playback.

The live shell is untouched: QML is copied into a temporary config with empty
camera defaults, private XDG directories, and no DMS backend connection.
The full test needs Wayland; --player-only can use the offscreen QPA backend.
Use --fullscreen to briefly show a local test video fullscreen and check its lifecycle.
"""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


QML = r'''
import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Plugins
import "plugin"

ShellRoot {
    id: test
    property var objects: []
    property var player: null
    property var widget: null
    property var popup: null
    property int phase: 0
    property bool failed: false
    property string firstSource: __FIRST_SOURCE__
    property string secondSource: __SECOND_SOURCE__

    function fail(message) {
        failed = true;
        console.error("CAMERA_SMOKE_FAIL: " + message);
        Qt.quit();
    }

    function finish() {
        console.warn("CAMERA_SMOKE_PASS: components, settings, sizing, video, switching, retry, and cleanup");
        Qt.quit();
    }

    function startFullscreenChecks() {
        if (!Quickshell.screens.length) {
            fail("No screen is available for fullscreen verification");
            return;
        }
        widget.parentScreen = Quickshell.screens[0];
        widget.pluginData = {cameras: [{id: "fullscreen-test", name: "Fullscreen test", url: "rtsp://127.0.0.1:8554/test"}]};
        widget.fullscreenViewer.streamUrl = __FULLSCREEN_SOURCE__;
        widget.fullscreenViewer.autoReconnect = false;
        popupState.shouldBeVisible = true;
        Qt.callLater(function() {
            if (!test.popup.player) {
                test.fail("Popout player did not load before fullscreen");
                return;
            }
            // Override before the player's delayed start; no RTSP connection is made.
            test.popup.player.streamUrl = __FULLSCREEN_SOURCE__;
            test.phase = 4;
        });
    }

    function instantiate(file, properties) {
        const component = Qt.createComponent("plugin/" + file);
        if (component.status !== Component.Ready) {
            fail(file + ": " + component.errorString());
            return null;
        }
        const object = component.createObject(host, properties || {});
        if (!object) {
            fail(file + ": " + component.errorString());
            return null;
        }
        objects.push(object);
        return object;
    }

    QtObject {
        id: service
        property var availablePlugins: ({cameraStreams: {permissions: ["settings_read", "settings_write"]}})
        property var saved: ({cameras: []})
        signal pluginDataChanged(string pluginId)
        signal pluginStateChanged(string pluginId)
        function getPluginVariants(pluginId) { return []; }
        function loadPluginData(pluginId, key, fallback) { return saved[key] === undefined ? fallback : saved[key]; }
        function savePluginData(pluginId, key, value) {
            saved[key] = value;
            pluginDataChanged(pluginId);
        }
        function loadPluginState(pluginId, key, fallback) { return fallback; }
        function savePluginState(pluginId, key, value) {}
    }

    QtObject {
        id: popupState
        property bool shouldBeVisible: false
    }

    // A window drives incubation and the render loop even on the offscreen QPA.
    FloatingWindow {
        visible: false
        implicitWidth: 960
        implicitHeight: 720
        color: "#111111"
        Item {
            id: host
            anchors.fill: parent
        }

        Timer {
            interval: 100
            running: true
            onTriggered: {
                if (!__PLAYER_ONLY__) {
                    const widget = test.instantiate("CameraWidget.qml", {pluginId: "cameraStreams", pluginService: service});
                    if (!widget) return;
                    widget.pluginData = {cameras: []};
                    if (!widget.popoutContent) {
                        test.fail("CameraWidget has no popout component");
                        return;
                    }
                    const popup = widget.popoutContent.createObject(host, {width: 640, parentPopout: popupState});
                    if (!popup) {
                        test.fail("Could not instantiate the camera popout");
                        return;
                    }
                    test.objects.push(popup);
                    test.widget = widget;
                    test.popup = popup;
                    const settings = test.instantiate("CameraSettings.qml", {width: 640, pluginService: service});
                    if (!settings) return;
                    settings.openEditor({id: "", name: "Test camera", url: "rtsp://127.0.0.1:8554/example"});
                    settings.saveCamera();
                    if (settings.cameras.length !== 1 || service.saved.cameras.length !== 1) {
                        test.fail("Could not add and persist a camera");
                        return;
                    }
                    const id = settings.cameras[0].id;
                    settings.openEditor({id: id, name: "Renamed camera", url: "rtsps://127.0.0.1:7441/example?enableSrtp"});
                    settings.saveCamera();
                    if (settings.cameras.length !== 1 || settings.cameras[0].name !== "Renamed camera") {
                        test.fail("Editing a camera failed");
                        return;
                    }
                    settings.openEditor({id: "", name: "Invalid", url: "file:///tmp/example.mp4"});
                    settings.saveCamera();
                    if (!settings.validationMessage || settings.cameras.length !== 1) {
                        test.fail("Unsupported camera URL was accepted");
                        return;
                    }
                    settings.closeEditor();
                    settings.removeCamera(id);
                    if (settings.cameras.length !== 0 || service.saved.cameras.length !== 0) {
                        test.fail("Removing the last camera failed");
                        return;
                    }
                    widget.parentScreen = {width: 1920, height: 720};
                    widget.pluginData = {cameras: Array.from({length: 20}, function(_, index) {
                        return {id: "layout-" + index, name: "Camera " + index + " south entrance", url: "rtsp://127.0.0.1:8554/example"};
                    }), previewWidth: 960};
                    popup.width = 960;
                    console.warn("CAMERA_SMOKE_COMPONENTS_OK");
                }
                test.player = test.instantiate("CameraPlayer.qml", {
                    width: 320, height: 180, active: true,
                    streamUrl: test.firstSource, autoReconnect: false
                });
                checks.start();
            }
        }

        Timer {
            id: checks
            interval: 100
            repeat: true
            onTriggered: {
                if (!test.player || test.failed) return;
                const player = test.player;
                if (test.phase < 4 && test.popup && test.popup.implicitHeight > 720 - test.widget.barThickness - test.widget.barSpacing) {
                    test.fail("Camera picker overflows a 720px screen: " + test.popup.implicitHeight);
                    return;
                }
                if (player.failure && test.phase < 3) {
                    test.fail("Video playback: " + player.failure);
                    return;
                }
                if (test.phase === 0 && player.live) {
                    player.active = false;
                    if (player.currentSource.toString() !== "" || player.live) {
                        test.fail("Closing the viewer did not release its source");
                        return;
                    }
                    player.streamUrl = test.firstSource;
                    if (player.currentSource.toString() !== "") {
                        test.fail("A hidden viewer opened a stream");
                        return;
                    }
                    player.active = true;
                    test.phase = 1;
                } else if (test.phase === 1 && player.live) {
                    player.streamUrl = test.secondSource;
                    test.phase = 2;
                } else if (test.phase === 2 && player.live) {
                    if (player.currentSource.toString() !== test.secondSource) {
                        test.fail("Camera switching retained the old source");
                        return;
                    }
                    player.autoReconnect = true;
                    player.streamUrl = Qt.resolvedUrl("missing-file.mp4").toString();
                    test.phase = 3;
                } else if (test.phase === 3 && player.failure) {
                    if (!player.retryPending || player.currentSource.toString() !== "" || player.live) {
                        test.fail("Failed playback did not release the source and schedule reconnection");
                        return;
                    }
                    player.autoReconnect = false;
                    if (player.retryPending) {
                        test.fail("Disabling reconnection left a retry scheduled");
                        return;
                    }
                    player.active = false;
                    if (__FULLSCREEN__) {
                        test.phase = 4;
                        test.startFullscreenChecks();
                    } else {
                        test.finish();
                    }
                } else if (test.phase === 4 && test.popup.player?.live) {
                    test.widget.enterFullscreen();
                    if (!test.widget.fullscreenOpen || (test.popup.player && test.popup.player.active)) {
                        test.fail("Entering fullscreen left the popup player active");
                        return;
                    }
                    popupState.shouldBeVisible = false;
                    test.phase = 5;
                } else if (test.phase === 5 && test.widget.fullscreenViewer.player?.live) {
                    const viewer = test.widget.fullscreenViewer;
                    const screen = test.widget.parentScreen;
                    if (!viewer.visible || viewer.width !== screen.width || viewer.height !== screen.height) {
                        test.fail("Fullscreen viewer does not fill the selected screen");
                        return;
                    }
                    test.widget.exitFullscreen(false);
                    if (test.widget.fullscreenOpen || viewer.visible || viewer.player) {
                        test.fail("Exiting fullscreen did not hide it and release playback");
                        return;
                    }
                    test.widget.enterFullscreen();
                    test.phase = 6;
                } else if (test.phase === 6 && test.widget.fullscreenViewer.player?.live) {
                    SessionService.locked = true;
                    const viewer = test.widget.fullscreenViewer;
                    if (test.widget.fullscreenOpen || viewer.visible || viewer.player) {
                        test.fail("Locking did not close fullscreen and release playback");
                        return;
                    }
                    SessionService.locked = false;
                    if (viewer.visible || viewer.player) {
                        test.fail("Unlocking unexpectedly reopened fullscreen");
                        return;
                    }
                    console.warn("CAMERA_SMOKE_FULLSCREEN_OK: dimensions, single player, exit, and lock cleanup");
                    test.finish();
                }
            }
        }

        Timer {
            interval: 35000
            running: true
            onTriggered: test.fail("Timed out waiting for a decoded video frame")
        }
    }
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dms-root", type=Path, default=Path("/usr/share/quickshell/dms/quickshell"))
    parser.add_argument("--player-only", action="store_true")
    parser.add_argument("--fullscreen", action="store_true", help="briefly show generated video fullscreen to test screen sizing, exit, and lock cleanup")
    parser.add_argument("--live-camera", action="store_true", help="opt in to testing the first camera in cameras.local.json")
    parser.add_argument("--platform", choices=("offscreen", "wayland", "xcb"), default=None)
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    platform = args.platform or ("wayland" if os.environ.get("WAYLAND_DISPLAY") and not args.player_only else "offscreen")
    if args.fullscreen and (args.player_only or platform != "wayland"):
        parser.error("--fullscreen requires the full Wayland test, without --player-only")
    secret_url = ""
    if args.live_camera:
        try:
            secret_url = json.loads((project / "cameras.local.json").read_text())[0]["url"]
        except (OSError, ValueError, IndexError, KeyError, TypeError):
            parser.error("--live-camera needs a camera in cameras.local.json")
    quickshell = shutil.which("quickshell") or shutil.which("qs")
    ffmpeg = shutil.which("ffmpeg")
    if not quickshell or not ffmpeg:
        parser.error("quickshell and ffmpeg are required")
    if not args.dms_root.is_dir():
        parser.error("DMS source directory not found; pass --dms-root")

    with tempfile.TemporaryDirectory(prefix="dms-camera-smoke-") as temporary:
        root = Path(temporary)
        plugin = root / "plugin"
        plugin.mkdir()
        for pattern in ("*.qml", "*.js", "plugin.json"):
            for path in project.glob(pattern):
                shutil.copy2(path, plugin / path.name)
        (plugin / "cameras.local.json").write_text("[]\n")
        for name in ("Common", "DCommon", "Services", "Widgets", "Modules", "Modals", "assets", "translations", "Shaders"):
            source = args.dms_root / name
            if source.exists():
                # Quickshell's virtual import scanner does not traverse directory symlinks.
                shutil.copytree(source, root / name)
        source = QML.replace("__PLAYER_ONLY__", str(args.player_only).lower())
        source = source.replace("__FULLSCREEN__", str(args.fullscreen).lower())
        source = source.replace("__FULLSCREEN_SOURCE__", json.dumps((root / "first.mp4").as_uri()))
        if args.player_only:
            source = re.sub(r"^import qs\..*\n", "", source, flags=re.MULTILINE)
            source = source.replace('import "plugin"\n', '')
        source = source.replace("__FIRST_SOURCE__", json.dumps(secret_url or (root / "first.mp4").as_uri()))
        source = source.replace("__SECOND_SOURCE__", json.dumps(secret_url or (root / "second.mp4").as_uri()))
        (root / "shell.qml").write_text(source)
        for name, color in (("first", "red"), ("second", "blue")):
            subprocess.run([
                ffmpeg, "-hide_banner", "-loglevel", "error", "-f", "lavfi",
                "-i", f"color=c={color}:s=320x180:r=15", "-t", "12",
                "-an", "-c:v", "mpeg4", "-pix_fmt", "yuv420p", str(root / f"{name}.mp4"),
            ], check=True, timeout=15)

        env = os.environ.copy()
        wayland_display = env.get("WAYLAND_DISPLAY", "")
        if wayland_display and not wayland_display.startswith("/"):
            wayland_display = str(Path(env.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / wayland_display)
        for key in ("WAYLAND_DISPLAY", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "NIRI_SOCKET", "QT_LOGGING_RULES"):
            env.pop(key, None)
        for key in ("XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME", "XDG_DATA_HOME", "XDG_RUNTIME_DIR"):
            path = root / key.lower()
            path.mkdir(mode=0o700)
            env[key] = str(path)
        env.update({
            "QT_QPA_PLATFORM": platform, "QT_QPA_PLATFORMTHEME": "",
            "QT_QUICK_CONTROLS_STYLE": "Basic", "QT_STYLE_OVERRIDE": "Fusion",
            "QSG_RHI_BACKEND": "software", "QT_QUICK_BACKEND": "software",
            "DMS_SOCKET": "", "DMS_DISABLE_MATUGEN": "1", "XDG_CURRENT_DESKTOP": "",
            "DBUS_SESSION_BUS_ADDRESS": "unix:path=/nonexistent-dms-camera-test-bus",
            "QT_AUDIO_BACKEND": "pipewire",
        })
        if platform == "wayland":
            env["WAYLAND_DISPLAY"] = wayland_display
        elif platform == "xcb":
            env["DISPLAY"] = os.environ.get("DISPLAY", ":0")

        def sanitize(output):
            if secret_url:
                output = output.replace(secret_url, "[camera URL]")
            return re.sub(r"(?:rtsps?|https?)://[^\s\"']+", "[camera URL]", output)
        try:
            result = subprocess.run(
                [quickshell, "-p", str(root), "--no-color"], env=env,
                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45,
            )
        except subprocess.TimeoutExpired as error:
            print("FAIL: QML smoke test timed out", file=sys.stderr)
            if error.stdout:
                print(sanitize(error.stdout.decode() if isinstance(error.stdout, bytes) else error.stdout))
            return 1
        output = sanitize(result.stdout)
        plugin_errors = [line for line in output.splitlines() if re.search(
            r"(?:Camera(?:Widget|Settings|Player|Fullscreen)\.qml|SnapshotPlayer\.qml|StreamUtils\.js).*"
            r"(?:Error|Cannot|Unable|Binding loop|not defined)", line)]
        passed = result.returncode == 0 and "CAMERA_SMOKE_PASS:" in output and not plugin_errors and "CAMERA_SMOKE_FAIL:" not in output
        if args.verbose or not passed:
            print(output)
        if passed:
            print("PASS: QML components, settings, sizing, decoded video, switching, retry, and cleanup")
        else:
            print("FAIL: QML smoke test", file=sys.stderr)
        return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
