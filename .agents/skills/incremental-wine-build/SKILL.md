---
name: incremental-wine-build
description: >-
  Build and patch the CX26 Cyder Wine engine, rebuild ntdll or wineserver,
  diagnose macOS minOS and Mach/sandbox failures, run direct MapleStory tests,
  collect low-noise WZ I/O data, and pack an engine. Use when changing
  patches/, build64, install/wine-cx26-x86_64, wineserver, ntdll, or the direct
  MapleStory launcher.
---

# Incremental Wine build and test

Use only in `/Users/jjc/cyder-wine-engine`. Do not use Cyder.app for engine tests.

## Read first

Read `AGENTS.md`, `docs/incremental-build-and-patches.md`,
`docs/engine-development-test-workflow.zh-TW.md`, and `patches/README.md` before
changing or building Wine. For WZ work also read
`docs/maplestory-cx26-wz-cache-experiments.zh-TW.md` and
`docs/maplestory-cx26-small-read-fast-path-plan.zh-TW.md`.

## Non-negotiable rules

- Set `OGOM=/Users/jjc/cyder-wine-engine`; run project scripts with `bash`.
- Do not source `scripts/env-x86_64.sh` into interactive zsh.
- Run manual host builds inside `bash -lc 'source scripts/env-x86_64.sh; ...'`.
- Prefix manual host builds with `arch -x86_64`.
- Preserve `MACOSX_DEPLOYMENT_TARGET` and `CYDER_MACOSX_VERSION_MIN_FLAG`.
- Apply patches through `scripts/build-wine.sh`; never edit an install tree.
- Keep CX26-only patches out of CX25 without ABI review.
- Do not mix source/build/install trees, prefixes, or wineservers in one test.
- Do not use destructive git cleanup or overwrite unrelated dirty files.

## 1. Identify the target

Run before every change:

```bash
ENGINE_ROOT=/Users/jjc/cyder-wine-engine
cd "$ENGINE_ROOT"
export OGOM="$ENGINE_ROOT"
git status --short
cat config/engine-version.txt
rg '^prefix =' build/cx26/sources/wine/build64/config.status
```

The prefix must be `/Users/jjc/cyder-wine-engine/install/wine-cx26-x86_64`.
Use `build/cx26/sources/wine` for source, `build64` for objects, `install/...`
for the engine, and `/private/tmp/...` only for disposable test state. If the
prefix is wrong, stop and reconfigure or run the full build.

## 2. Patch and build

For every patch, update the patch file, stable marker/apply list in
`scripts/build-wine.sh`, `patches/README.md`, relevant release metadata, and the
narrowest relevant test. Then run:

```bash
OGOM=/Users/jjc/cyder-wine-engine \
  bash scripts/build-wine.sh --cx 26 --maplestory --dry-run
```

Use the full build when patch order, configure, toolchain, prefix, or source
state is uncertain:

```bash
OGOM=/Users/jjc/cyder-wine-engine MACOSX_DEPLOYMENT_TARGET=10.15 \
  bash scripts/build-wine.sh --cx 26 --maplestory \
  --with-vulkan --vulkan-source crossover --jobs 8
```

For a proven single host module:

```bash
bash -lc 'cd /Users/jjc/cyder-wine-engine; export OGOM=/Users/jjc/cyder-wine-engine;
source scripts/env-x86_64.sh; arch -x86_64 make -j4 dlls/ntdll/ntdll.so'
```

If a host binary reports `minos 15.0`, `built for macOS 15.0`, or
`_os_sync_wait_on_address`, stop and run `bash scripts/rebuild-wine-host-unix.sh`.
Do not repair only one object after possible arm64/minOS contamination.

When changing `wineserver` or the ntdll/server protocol, rebuild and install
matching components from the same source/build/install identity. Restart the
exact prefix before testing. Never mix a new wineserver with an old ntdll.

## 3. Verify the install

Before a game test, confirm the version, architecture, minOS, patch markers, and
payloads:

```bash
ENGINE=/Users/jjc/cyder-wine-engine/install/wine-cx26-x86_64
cat "$ENGINE/version"
file "$ENGINE/bin/wineserver" "$ENGINE/lib/wine/x86_64-unix/ntdll.so"
otool -l "$ENGINE/bin/wineserver" | rg minos
otool -l "$ENGINE/lib/wine/x86_64-unix/ntdll.so" | rg minos
strings "$ENGINE/lib/wine/x86_64-unix/ntdll.so" | rg 'CYDER_MAPLESTORY|CYDER_IO'
test -f "$ENGINE/lib/dxvk/x86_64-windows/d3d11.dll"
test -f "$ENGINE/lib/dxvk2/x86_64-windows/d3d11.dll"
test -f "$ENGINE/lib/dxmt/x86_64-unix/winemetal.so"
test -f "$ENGINE/lib/wine/x86_64-unix/libMoltenVK.dylib"
test ! -e "$ENGINE/lib/wine/x86_64-unix/libMoltenVK.real.dylib"
```

Product host binaries must declare minOS ≤ 10.15; DXMT is the documented
macOS 15+ exception. Do not test an install whose version or markers do not
match the source change.

## 4. Handle Mach and sandbox failures

Treat `server_mach_port`, `Can't check in server_mach_port`, pre-initialization
hangs, and sandbox-blocked GUI/Mach access as environment failures. Record the
first error and exact engine, prefix, and wineserver; do not change Wine code or
timing flags. Rerun the same command in a Mach-capable desktop environment with
the required execution permission.

Before each direct launch, terminate only the test prefix server:

```bash
WINEPREFIX="$PREFIX" WINESERVER="$ENGINE/bin/wineserver" \
  arch -x86_64 "$ENGINE/bin/wineserver" -k || true
sleep 3
```

Do not use `wineserver -w` when no server is alive; it can create a fresh Mach
port and break the next client. Do not kill Wine processes system-wide.

## 5. Launch MapleStory directly

Use `scripts/run-maplestory-cx26-d3dmetal.sh`, never an implicit runtime:

```bash
ENGINE=/Users/jjc/cyder-wine-engine/install/wine-cx26-x86_64
EXE=/Users/jjc/games/tms/MapleStory.exe
PREFIX=/private/tmp/cyder-cx26-test-prefix
LOG_ROOT=/private/tmp/cyder-cx26-test-logs
GPTK='/Users/jjc/Library/Application Support/Cyder-maplestory-oem25/runtime/apple_gptk'
COMPATDB=/Users/jjc/ogom/compatdb/compiled/compatdb.cdb

bash scripts/run-maplestory-cx26-d3dmetal.sh \
  --launch-exe "$EXE" --wine-install "$ENGINE" \
  --wineprefix "$PREFIX" --gptk-root "$GPTK" \
  --compatdb "$COMPATDB" --log-root "$LOG_ROOT" \
  --no-otp --dry-run
```

Run the same command without `--dry-run` and with `--no-otp` before acceptance.
The launcher validates the engine, GPTK, CompatDB, GStreamer, prefix, locale,
and D3DMetal files.

For OTP acceptance, arguments after `--` must be exactly:

```text
tw.login.maplestory.beanfun.com 8484 BeanFun T9_SERVICE_ACCOUNT_ID OTP
```

`--no-otp` takes no game arguments. Keep OTP out of files, history, logs,
screenshots, reports, and commits; pass it only to the live process and redact
it in output. Prefer the launcher over bare `wine`; if raw Wine is required,
record the exact `WINEPREFIX`, `WINELOADER`, `WINESERVER`, GPTK, CompatDB, locale,
and `DYLD_FALLBACK_LIBRARY_PATH` first.

## 6. Run one controlled experiment

- Change one variable per run.
- Use a safe map and an explicit prefix/log root.
- Record engine version, resolved install, prefix, backend, flags, action, and
  close method.
- Do not combine engine, backend, cache, HUD, audio, `msync`, prefix, and trace
  changes in one A/B cell.

For first-use WZ or prewarm tests:

1. Start with an absent, unique arm path.
2. Reach a safe map and wait for a stable screen.
3. Create the arm file immediately before a harmless I/O trigger, such as opening
   the backpack.
4. Require `CYDER_IO prewarm done`; discard the run if it is absent or skips
   targets.
5. Perform exactly one attack or passive-skill trigger.
6. Close through the game's normal confirmation flow.

Mark a run invalid if the user changes map, triggers an unintended action, or
force-kills the game. Forced close can lose the ring and exit summary.

## 7. Collect low-noise I/O data

| Question | Settings |
|---|---|
| Path summary | `CYDER_MAPLESTORY_IO_TRACE=1`, `CYDER_MAPLESTORY_IO_PROFILE=1`, `CYDER_MAPLESTORY_IO_SUMMARY=1`, `+cyderio` |
| Action-correlated events | Above plus `CYDER_MAPLESTORY_IO_RING=1` and absent `CYDER_MAPLESTORY_IO_RING_ARM_FILE` |
| First action only | Create the arm file immediately before the action |
| 100 ms bins | `CYDER_MAPLESTORY_IO_TIMELINE=1` |
| Cache stats | `CYDER_MAPLESTORY_IO_CACHE_STATS=1` with summary |
| mmap A/B | `CYDER_MAPLESTORY_FILE_CACHE_MMAP=1` only in that A/B cell |
| Section observation | `CYDER_MAPLESTORY_IO_SECTION_MAP=1`; observation only |

`IO_PROFILE` alone is insufficient. Do not enable `+process`, `+loaddll`, full
offsets, or per-read timing by default. The ring emits at process termination;
close normally. After each run, check space and compress large logs:

```bash
du -sh "$LOG_ROOT"
find "$LOG_ROOT" -type f -name '*.log' -size +50M -exec gzip -9 -- {} +
du -sh "$LOG_ROOT"
```

Stop before another launch if disk space is low. Keep summaries and only the
raw trace needed for the current question.

## 8. Test and classify

Run narrow tests, then the full suite:

```bash
bash tests/test-build-wine.sh
bash tests/test-maplestory-patch-stack.sh
bash tests/test-maplestory-file-cache-patch.sh
bash tests/test-maplestory-d3dmetal-launcher.sh
bash tests/test-engine-manifest.sh
bash tests/test-pack-minos-scan.sh
bash tests/run.sh
```

Classify before changing code:

- Wrong version/marker: fix `WINE_INSTALL`; discard the result.
- Wrong prefix/server: terminate that prefix; rerun.
- arm64/minOS: rebuild host Unix modules; rerun.
- Mach/sandbox: rerun with desktop Mach access; do not patch.
- No window/log: verify GPTK, prefix, server, and permissions.
- Empty ring after forced close: repeat with normal close.
- Game reaches map and hitches: retain and analyze the run.

Never report `tests/run.sh` as passing when it stopped on a Mach service error.
Never compare a run whose engine, prefix, or wineserver is unknown.

## 9. Pack and finish

After install verification and required tests, pack only with:

```bash
CYDER_ENGINE_VERSION_LABEL="$(head -n 1 config/engine-version.txt)" \
SIGN_IDENTITY=- bash scripts/pack-engine-artifact.sh --xz --force
```

Deliver the archive, checksum, and manifest. Do not call a raw install tree a
release. Stage or commit only the requested files.

## References

- `docs/incremental-build-and-patches.md`
- `docs/engine-development-test-workflow.zh-TW.md`
- `docs/maplestory-cx26-wz-cache-experiments.zh-TW.md`
- `docs/maplestory-cx26-small-read-fast-path-plan.zh-TW.md`
- `patches/README.md`
