# dms-camera-streams

**Camera Streams** is a bar plugin for **Dux Modular Shell (DMS)**. Tap the camera icon to watch a live RTSP/RTSPS stream, then tap a camera name to switch feeds.

The repository is [dheera/dms-camera-streams](https://github.com/dheera/dms-camera-streams). Dux Modular Shell is the official name since [DMS 2.1, released November 4, 2026](https://duxlabs.dev/blog/v2-1-release), and DMS remains its official abbreviation. The plugin's stable manifest ID is `cameraStreams`; its install directory uses that ID. This is an independent community plugin.

## Features

- Native video in a themed bar popout, with horizontal and vertical bar support.
- Named camera picker, previous/next controls, and remembered selection.
- Camera settings with add, edit, and remove controls and masked stream URLs.
- Mute, stop/start, reconnect, and optional standalone playback in mpv.
- Fullscreen video on the bar's display. Choose **Fullscreen** in the viewer; **Escape**, **F11**, or **Exit fullscreen** returns to the popout. Left/right switches cameras and **M** toggles audio.
- Automatic reconnection with backoff; connection and stale-video timeouts.
- Releases the stream when the popout closes and while the session is locked.

## Requirements

- Dux Modular Shell 2.1+ and Quickshell.
- **Qt Multimedia 6.10+**, with its FFmpeg backend and the codecs your cameras use, for the embedded preview. This version is needed for low-latency playback options. On Debian/Ubuntu, the QML module is usually `qml6-module-qtmultimedia`; on Arch, `qt6-multimedia` and `qt6-multimedia-ffmpeg`.
- Optional **mpv** for the “Open in mpv” button. It forces RTSP over TCP and opens a separate normal window.
- Python 3 for the installer. No build step or server is required.

## Install

From this checkout:

```sh
python3 tools/install.py
```

This copies only the plugin runtime files into `${XDG_CONFIG_HOME:-$HOME/.config}/dms/plugins/cameraStreams`. If present, `cameras.local.json` is also copied with mode `0600`. The installer preserves settings and unrelated files. Use `--without-local-cameras` to skip copying local defaults, or `--dest /some/path/cameraStreams` for a custom location.

1. Open **Settings → Plugins**, scan for plugins, and enable **Camera Streams**.
2. Add **Camera Streams** under **Settings → Bar → Widgets**.
3. Open the plugin's settings to add cameras. Tap the bar widget to view them.

To update, rerun the installer, then:

```sh
dms ipc call plugins reload cameraStreams
```

To remove it, remove its bar widget, disable it in Plugins, and delete the installed `cameraStreams` directory.

## Cameras

Use the settings editor to enter a name and a complete `rtsp://` or `rtsps://` URL. URLs are passed to the player unchanged, including authentication, stream tokens, and query flags such as `?enableSrtp`. The plugin never converts encrypted streams to plaintext.

For local defaults, copy `cameras.example.json` to `cameras.local.json` and edit the values. This file is ignored by Git. Saved camera settings take precedence over defaults, including a deliberately empty camera list.

Settings are stored by DMS in `~/.config/dms/plugin_settings.json`. Masking a URL in the editor is only a display feature: the local JSON files contain the full URL. Keep them private. Native Qt/FFmpeg diagnostics may also include stream URLs; redact them before sharing shell logs.

Only the selected camera is decoded. The embedded player stops when the popout closes. Entering fullscreen closes the popout stream before opening the fullscreen player; returning reconnects in the popout and preserves mute. Locking the session closes fullscreen and releases its stream. An explicitly opened mpv window runs independently until you close it.

## Troubleshooting

If the preview is unavailable, check Qt Multimedia and the FFmpeg backend. The picker and settings still load without that module. Retry the stream or use **Open in mpv**. For RTSPS feeds, keep the camera's exact exported URL. Cameras with unsupported transport, codecs, or TLS configuration may work differently in Qt and mpv.

The player retries after 2, 4, 8, 16, then 30 seconds and releases the failed source between attempts. Disable automatic reconnect in settings if preferred. It does not record video or create image snapshots.

## Development checks

```sh
node --test tests/stream-utils.test.mjs
python3 tools/smoke-test.py
# Optional: briefly show a fullscreen test video and check its lifecycle.
python3 tools/smoke-test.py --fullscreen
```

The smoke test uses installed DMS QML components in an isolated Quickshell session with a hidden window, private temporary settings, and generated local video. Full DMS components require a Wayland session; standalone player checks can use `--player-only --platform offscreen`. Default tests do not modify the live shell or connect to configured cameras. Use `--live-camera` to explicitly test the first entry in `cameras.local.json`, or see `--help` for other options.

Upstream: [plugin development](https://duxlabs.dev/docs/dms/plugin-development), [Dux Shell](https://github.com/duxlabs-dev/dux-shell).
