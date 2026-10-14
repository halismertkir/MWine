from pathlib import Path
import os
import shutil
import subprocess
import tempfile

project = Path(__file__).parents[1]
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    scripts = root / "scripts"
    scripts.mkdir()
    for name in ("steam-run", "paths.sh"):
        shutil.copy2(project / "Tests/Fixtures/hadron" / name, scripts / name)
    for name, body in (("play", "exit 23\n"), ("shortcut-icon", "exit 0\n")):
        path = scripts / name
        path.write_text("#!/bin/sh\n" + body)
        path.chmod(0o755)
    binaries = root / "dist/bin"
    binaries.mkdir(parents=True)
    for name in ("wine", "wineserver"):
        path = binaries / name
        path.write_text("#!/bin/sh\nexit 0\n")
        path.chmod(0o755)
    (root / "config").mkdir()
    prefix = root / "compat/pfx"
    prefix.mkdir(parents=True)
    for marker in ("system.reg", ".hadron-prefix-ready", ".hadron-profile-v1"):
        (prefix / marker).touch()
    (prefix / ".update-timestamp").write_text("disable\n")
    game = root / "game"
    game.mkdir()
    executable = game / "fixture.exe"
    executable.touch()
    env = {key: os.environ[key] for key in ("HOME", "USER", "PATH") if key in os.environ}
    env.update(STEAM_COMPAT_DATA_PATH=str(prefix.parent), STEAM_COMPAT_INSTALL_PATH=str(game),
               STEAM_COMPAT_APP_ID="3405340", HADRON_DATA_ROOT=str(root / "state"))
    result = subprocess.run(["sh", str(scripts / "steam-run"), "run", str(executable)], env=env,
                            capture_output=True, timeout=10)
    assert result.returncode == 23, (result.returncode, result.stderr)
    env["HADRON_PREPARE_ONLY"] = "1"
    result = subprocess.run(["sh", str(scripts / "steam-run"), "run", str(executable)], env=env,
                            capture_output=True, timeout=10)
    assert result.returncode == 0
print("Shared runner preserves game failures and prepare-only does not launch the game.")
