---
name: incremental-wine-build
description: >-
  Incremental Wine/CX26 engine builds, Cyder patches, host minOS repair, and
  engine packing. Use when editing patches/, running make in build64,
  rebuilding wineserver/ntdll.so, fixing macOS minos 15 drift, or
  pack-engine-artifact.
---

# Incremental Wine build / patch skill

## Required reading

1. `docs/incremental-build-and-patches.md` (full procedure)
2. `patches/README.md` (apply order + idempotent markers)
3. `AGENTS.md` (non-negotiables)

## Checklist

1. `source scripts/env-x86_64.sh` (loads `.env`; default minOS **10.15**).
2. Confirm `build64` `prefix` is `install/wine-cx26-x86_64` (not `/tmp/...`).
3. Keep `-mmacosx-version-min` / `MACOSX_DEPLOYMENT_TARGET` on every host `make`.
4. After minOS pollution: `bash scripts/rebuild-wine-host-unix.sh`.
5. New patches: add to `build-wine.sh` (CX26 block if needed), README, manifest,
   and a narrow `tests/test-*.sh`.
6. Release only via `scripts/pack-engine-artifact.sh` (requires `lib/dxvk`,
   minOS ≤ floor, codesign).

## Do not

- Run bare `make` in `build64` without the project env / minOS flag.
- Apply CX26 wineserver/frame-walk patches to CX25 without ABI review.
- Copy unpackaged binaries into `~/.cyder/runtime` and call it a release
  unless the user asked to install a packed archive.
- Bundle `apple_gptk` in the engine tarball.
