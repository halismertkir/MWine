# Contributing to MWine

Run `./scripts/test` and `./scripts/build-app` on an Apple Silicon Mac before
submitting a change. Stage the intended files and run `./scripts/check-secrets`
before publication; it also checks Git history. CI exercises the offline source build, not macOS 27's
entitled game runtime. Keep downloaded engines, games, account files, save
games, personal paths and diagnostic captures out of commits.

Contributions to MWine-owned files use Apache-2.0. Preserve NOTICE attribution.
Hadron-derived scripts and patches retain BSD-3-Clause. Do not change dependency
licenses or redistribute binaries without their corresponding-source notices.

Use general fixes. Never bypass game ownership, DRM or anti-cheat. Respect each
upstream project's contribution policy, including restrictions on AI-authored
submissions. A local downstream patch does not authorize an upstream submission.

Performance claims require comparable scenes/settings and both cold/warm runs;
report frame-time percentiles and stalls along with mean FPS. Separate a
synthetic probe from a game benchmark. Do not label a graphics failure a Metal
bug without verifying the relevant API contracts and an independent review.

Bug reports should include MWine version, macOS version, Apple chip, game App ID,
launcher arguments and a redacted session-log excerpt. Exclude account tokens,
passwords, email addresses and personal save data.
