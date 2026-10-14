#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Restore preserved game data into a new prefix without replacing current saves."""
from pathlib import Path
import shutil
import sys


def restore(project: Path, app_id: str, prefix: Path, user: str = "steamuser") -> int:
    if app_id != "5165210":
        return 0
    if not user or Path(user).name != user or user in (".", ".."):
        raise ValueError("Invalid Windows profile name")
    destination = prefix / f"drive_c/users/{user}/AppData/Roaming/Godot/app_userdata/Haystack Incremental"
    copied = 0
    # Newest backup wins when older snapshots contain the same names.
    snapshots = sorted((project / "preserved-data").glob("*"), reverse=True)
    for snapshot in snapshots:
        sources = snapshot.glob("bottles/*/drive_c/users/*/AppData/Roaming/Godot/app_userdata/Haystack Incremental")
        for source in sources:
            for item in source.rglob("*"):
                if item.is_symlink() or not item.is_file():
                    continue
                relative = item.relative_to(source)
                if relative.parts[0] not in ("saves", "settings.cfg", "profile.cfg"):
                    continue
                target = destination / relative
                # Existing current saves, including symlinks, always take priority.
                if target.exists() or target.is_symlink():
                    continue
                if not target.resolve().is_relative_to(prefix.resolve()):
                    raise ValueError("Save destination escapes the selected prefix")
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(item, target)
                copied += 1
    return copied


if __name__ == "__main__":
    if len(sys.argv) not in (4, 5) or not sys.argv[2].isdigit():
        raise SystemExit("Expected project, app ID and prefix")
    count = restore(Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3]), sys.argv[4] if len(sys.argv) == 5 else "steamuser")
    print(f"Preserved game data restored: {count} files; existing saves retained.")
