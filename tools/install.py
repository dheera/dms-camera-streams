#!/usr/bin/env python3
"""Install this checkout as a local Dux Modular Shell plugin."""
import argparse
import json
import os
from pathlib import Path
import tempfile

SOURCE = Path(__file__).resolve().parent.parent
FILES = ("plugin.json", "CameraWidget.qml", "CameraPlayer.qml", "CameraFullscreen.qml", "SnapshotPlayer.qml", "CameraSettings.qml", "StreamUtils.js")


def install(destination, include_local=True):
    destination = Path(destination).expanduser().absolute()
    if destination.resolve() == SOURCE:
        raise ValueError("Choose an install directory outside the source checkout.")
    if destination.exists():
        manifest = destination / "plugin.json"
        if not manifest.is_file() or json.loads(manifest.read_text()).get("id") != "cameraStreams":
            raise ValueError("Destination already exists and is not the cameraStreams plugin.")
    destination.mkdir(parents=True, mode=0o700, exist_ok=True)
    names = list(FILES)
    if include_local and (SOURCE / "cameras.local.json").exists():
        # Fail before writing anything if the private config is malformed.
        value = json.loads((SOURCE / "cameras.local.json").read_text())
        if not isinstance(value, list):
            raise ValueError("cameras.local.json must contain a JSON array.")
        names.append("cameras.local.json")
    for name in names:
        fd, temporary = tempfile.mkstemp(prefix=".camera-streams-", dir=destination)
        try:
            with os.fdopen(fd, "wb") as stream:
                stream.write((SOURCE / name).read_bytes())
            os.chmod(temporary, 0o600 if name.endswith(".local.json") else 0o644)
            os.replace(temporary, destination / name)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    default = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "dms/plugins/cameraStreams"
    parser.add_argument("--dest", type=Path, default=default)
    parser.add_argument("--without-local-cameras", action="store_true", help="Do not copy private local camera defaults")
    args = parser.parse_args()
    try:
        destination = install(args.dest, not args.without_local_cameras)
    except (OSError, ValueError) as error:
        parser.exit(1, f"Install failed: {error}\n")
    print(f"Installed Camera Streams to {destination}")
    print("DMS Settings → Plugins → Scan for Plugins → enable Camera Streams.")
    print("Then Settings → Bar → Widgets → add Camera Streams.")
    print("After updating an enabled plugin: dms ipc call plugins reload cameraStreams")


if __name__ == "__main__":
    main()
