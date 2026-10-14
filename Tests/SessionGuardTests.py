from pathlib import Path
import os
import shutil
import subprocess
import tempfile

project = Path(__file__).parents[1]
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    (root / 'scripts').mkdir()
    guard = root / 'scripts/session-watchdog'
    shutil.copy2(project / 'scripts/session-watchdog', guard)
    helpers = root / 'helpers'
    helpers.mkdir()
    calls = root / 'calls'
    server = helpers / 'server'
    server.write_text('#!/bin/sh\nprintf "%s\\n" "$WINEPREFIX" >> "$GUARD_CALLS"\n')
    server.chmod(0o755)
    sysctl = helpers / 'sysctl'
    sysctl.write_text('#!/bin/sh\ncase "$2" in\nvm.swapusage) echo "total = 0M used = 0.00M free = 0M" ;;\n*) echo 4 ;;\nesac\n')
    sysctl.chmod(0o755)
    env = dict(os.environ, PATH=str(helpers) + ':/usr/bin:/bin:/usr/sbin:/sbin', GUARD_CALLS=str(calls))
    prefix = root / 'bottles/native-arm64/42/pfx'
    result = subprocess.run([str(guard), str(prefix), str(os.getpid()), str(server)], env=env, capture_output=True, timeout=5)
    assert result.returncode == 1, result.stderr
    assert calls.read_text().splitlines() == [str(prefix)]
    calls.unlink()
    result = subprocess.run([str(guard), '/another/wine/pfx', str(os.getpid()), str(server)], env=env, capture_output=True, timeout=5)
    assert result.returncode == 2 and not calls.exists()
print('Critical-pressure shutdown stays scoped to the owned game prefix.')
