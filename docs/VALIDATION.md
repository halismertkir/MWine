# Validation scope — 0.5.0

The offline test runner checks:

- Steam metadata selection, numeric argument validation, generic App ID / store
  URL import, multi-depot planning, platform filtering and unsafe EXE paths.
- Fresh completion messages, manifest/app/depot matching, partial CRLF input,
  Steam failure handling and log rotation detection.
- x86/x64 PE headers, rejection of other architectures, depot merge contents,
  conflicting-file rollback and symlink rejection.
- Critical-pressure termination targets only the owned prefix; unrelated prefix
  paths are rejected without invoking wineserver.
- Runtime host architecture, clean environment and per-game cache/prefix plans.
- Bounded pipe output, final buffered bytes and retained-writer handling.
- Save restoration without overwriting existing files or following symlinks.
- Hadron runner game exit propagation and prepare-only behavior, using offline
  BSD-licensed shell fixtures rather than an untracked source clone.

Build checks: SwiftUI launcher, download CLI, Metal probe, embedded scripts and
notices, and ad hoc bundle signature. A relocated app must start without the
source checkout. No game or runtime package is downloaded by tests/build.

## Earlier runtime evidence (not reclassified as game compatibility)

On Apple M4 / macOS 27.2, the pinned ARM64 runtime ran an x64 D3D11 fixture:
feature level 11.0, Apple M4 adapter, exit 0. The original native-game Steam
runner path was also exercised with that fixture; it does not call Steam API,
so this does not prove online Steam integration. The renderer emitted an
OpenGL unsupported-operation message; OpenGL conformance was not established.

Find The Needle Demo was visually confirmed by the user on the earlier
Rosetta/Wine/Vulkan path. That historical result does not verify the new native
renderer path, multiplayer, DRM, Cloud or achievements. No general game matrix
or measured FPS improvement is currently claimed.

The Metal compute probe validates output against a CPU reference and records
CPU encoding / GPU elapsed time. Its output deliberately has `gameFPS: null`.

Before declaring a game supported, test launch, menus, rendering, controls,
audio, save/load, exit, required Steam APIs and repeatable cold/warm frame times.

The new standalone `native-exe` path was exercised locally with that x64 D3D11
fixture on macOS 27.2. It created a fresh isolated prefix, reported feature level
11.0 / Apple M4 and exited 0 without a running Steam client. The temporary
fixture prefix was removed after the check. This remains a device-creation
probe, not a rendering/game benchmark.
