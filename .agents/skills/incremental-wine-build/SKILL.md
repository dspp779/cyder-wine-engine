---
name: incremental-wine-build
description: >-
  Incremental Wine/CX26 engine builds, Cyder patches, host minOS repair,
  MapleStory direct-engine tests, and engine packing. Use when editing
  patches/, running make in build64, rebuilding wineserver/ntdll.so, fixing
  macOS minos 15 drift, validating the direct launcher, or pack-engine-artifact.
---

# Incremental Wine build / patch skill

## Required reading

1. `docs/incremental-build-and-patches.md` (full procedure)
2. `docs/engine-development-test-workflow.zh-TW.md` (end-to-end runbook)
3. `patches/README.md` (apply order + idempotent markers)
4. `AGENTS.md` (non-negotiables)

## Checklist

1. Run scripts with `bash`, set `OGOM` to this engine checkout, and do not source
   `env-x86_64.sh` into a zsh session. Manual host commands belong in
   `bash -lc 'source ...; ...'`.
2. Confirm `build64` `prefix` is `install/wine-cx26-x86_64` (not `/tmp/...`).
3. Keep `-mmacosx-version-min` / `MACOSX_DEPLOYMENT_TARGET` on every host `make`.
4. Start with `build-wine.sh --dry-run`; use the full build when tree state is
   unknown or configure/toolchain/prefix changed.
5. After minOS pollution: `bash scripts/rebuild-wine-host-unix.sh`.
6. New patches: add to `build-wine.sh` (CX26 block if needed), README, manifest,
   and a narrow `tests/test-*.sh`.
7. Validate install `version`, minOS, payloads, and patch markers before tests.
8. Run narrow tests, then `bash tests/run.sh`; Mach service failures are
   environment failures and must not be reported as engine passes.
9. Direct MapleStory tests use the launcher with explicit engine/prefix/GPTK/
   CompatDB/log paths; do `--dry-run` and `--no-otp` before OTP acceptance. For
   WZ summaries, set both `CYDER_MAPLESTORY_IO_TRACE=1` and
   `CYDER_MAPLESTORY_IO_PROFILE=1`, and add `+cyderio` to WINEDEBUG;
   `IO_PROFILE` alone emits no summaries. For event-correlated WZ experiments,
   `CYDER_MAPLESTORY_IO_RING=1` keeps a bounded in-memory read ring and emits it
   only during Unix process termination. For a scoped run, set
   `CYDER_MAPLESTORY_IO_RING_ARM_FILE` to an absent temporary file and create it
   immediately before the action under test; arming clears the ring first.
   For high-volume captures, set `CYDER_MAPLESTORY_IO_SUMMARY=1` instead; it
   emits compact per-path aggregates without retaining every event.
   Add `CYDER_MAPLESTORY_IO_TIMELINE=1` when the read burst must be aligned to
   a first-use action in 100 ms buckets.
   Add `CYDER_MAPLESTORY_IO_CACHE_STATS=1` with
   `CYDER_MAPLESTORY_IO_SUMMARY=1` to report arm-scoped adaptive-cache hits,
   fills, fill duration, failures, bypasses, and `needs_close` skips per WZ path without per-read
   logging. Its decision summary separates attempts from `needs_close`, unregistered-handle,
   and missing-offset skips; arming resets counters but preserves warm cache windows.
   Set `CYDER_MAPLESTORY_FILE_CACHE_MMAP=1` only for the experimental mmap-backed
   window-fill comparison; leave it unset for normal runs.
   Add `CYDER_MAPLESTORY_IO_SECTION_MAP=1` for a separate mmap hypothesis
   check; it counts regular-file section mappings and reports WZ paths only at
   process exit without changing the read path.
10. Release only via `scripts/pack-engine-artifact.sh` (requires `lib/dxvk`,
   minOS ≤ floor, codesign).

## Do not

- Run bare `make` in `build64` without the project env / minOS flag.
- Apply CX26 wineserver/frame-walk patches to CX25 without ABI review.
- Copy unpackaged binaries into `~/.cyder/runtime` and call it a release
  unless the user asked to install a packed archive.
- Bundle `apple_gptk` in the engine tarball.
- Start a game test without confirming which `WINE_INSTALL`, prefix, GPTK,
  CompatDB, and log root are in use.
- Enable full offset/I/O trace or `+process,+loaddll` by default for a
  performance experiment; use a scoped log root and compress closed logs.
