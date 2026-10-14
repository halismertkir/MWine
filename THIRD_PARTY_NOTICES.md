# Third-party notices

MWine's own launcher, installers and documentation are Apache-2.0 except
where a file states otherwise. This license does not relicense dependencies.

## Hadron

https://github.com/Broyojo/hadron/tree/v0.1.1

The downstream patch and the modified shell fixtures are derived from
Hadron scripts, BSD-3-Clause. See `Patches/hadron/LICENSE.hadron` and
`Tests/Fixtures/hadron/LICENSE`. MWine modifies isolation, log handling,
prepare-only behavior and exit-status propagation. These derived files
remain BSD-3-Clause. MWine does not modify or redistribute the entitled
Wine loader. The downloaded runtime contains its own `licenses/` directory.

Hadron includes Wine (LGPL), FEX (MIT), DXMT (LGPL-2.1-or-later), Mesa (MIT and other
file-specific terms), mtld3d (zlib), vkd3d-proton (LGPL),
DXVK (zlib) and other components. The pinned upstream repository and
runtime notices are authoritative for each component's exact terms.
The runtime is downloaded separately from the upstream release; it is
not included in this repository or in MWine.app. Runtime distributors
must comply with all component license and corresponding-source duties.

## Legacy CEF workaround

`Sources/steamwebhelper-launcher.c` is informed by
https://github.com/notpop/steam-on-m1-wine. Preserve the following notice
when distributing that file or a substantial derivative:

MIT License

Copyright (c) 2026 notpop

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Optional legacy engines

Wine Staging binaries: https://github.com/Gcenx/macOS_Wine_builds
DXMT fork: https://github.com/ramiabih/play-windows-steam-on-mac
See `DXMT-NOTICE.md` for provenance. These are not shipped in MWine.app.

## Valve Steam

Steam, games and Valve client DLLs are proprietary and belong to their
respective owners. Installers fetch Valve files from Valve's servers when
needed, subject to Valve's terms and the user's account entitlements.
Neither Valve binaries, games nor account data are distributed here.
MWine is independent of Valve, Apple and the upstream engine projects.
