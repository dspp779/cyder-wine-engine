# Incremental Wine builds and patches

Practical guide for changing the CX26 Cyder engine without a full rebuild, and
for adding patches safely. Read this **before** running ad-hoc `make` in
`build64` or editing Wine sources under `build/cx*/sources/wine`.

Related:

- Standard end-to-end workflow: [`engine-development-test-workflow.zh-TW.md`](engine-development-test-workflow.zh-TW.md)
- MapleStory WZ cache experiment record: [`maplestory-cx26-wz-cache-experiments.zh-TW.md`](maplestory-cx26-wz-cache-experiments.zh-TW.md)
- Patch order and intent: [`patches/README.md`](../patches/README.md)
- Product minOS / `.env`: [`.env.example`](../.env.example)
- Cyder hand-off: [`integration-with-cyder.md`](integration-with-cyder.md)
- AI multi-tool setup: [`ai-agent-setup.md`](ai-agent-setup.md)
- AI entrypoint: [`../AGENTS.md`](../AGENTS.md)

## Layout (this repo owns the trees)

| Path | Role |
|------|------|
| `build/cx26/sources/wine` | Patched Wine sources |
| `build/cx26/sources/wine/build64` | Out-of-tree build (configure + objects) |
| `install/wine-cx26-x86_64` | Install prefix used for packing |
| `tools/archives/` | CrossOver / llvm-mingw inputs |
| `.brew-x86/` | Project x86_64 Homebrew |
| `dist/artifacts/` | Packed engine tarballs + manifests |

CyderBits/ogom may symlink these paths here for compatibility. Prefer building
and packing from **this** repository.

## Hard rules

1. **Run project scripts with Bash and explicitly pin the engine root.** From a
   zsh interactive shell, do not source the Bash env file into the current
   shell. Use `bash scripts/...`; for manual host commands use
   `bash -lc 'source scripts/env-x86_64.sh; ...'`. Set `OGOM` to this checkout,
   so an inherited value cannot redirect build/install work elsewhere:
   ```sh
   ENGINE_ROOT=/Users/jjc/cyder-wine-engine
   cd "$ENGINE_ROOT"
   export OGOM="$ENGINE_ROOT"
   ```

2. **Always load the project env** before host `make` / `configure`:
   ```sh
   source scripts/env-x86_64.sh
   ```
   This loads `.env` (if present) and sets `MACOSX_DEPLOYMENT_TARGET` (default
   **10.15**) plus `CYDER_MACOSX_VERSION_MIN_FLAG`.

3. **Never rely on the SDK default minOS.** On a modern macOS SDK, bare `clang`
   produces Mach-O `minos 15.0`. That breaks older hosts
   (`_os_sync_wait_on_address`, “built for macOS 15.0 which is newer than
   running OS”). Full `build-wine.sh` bakes `-mmacosx-version-min=…` into
   configure. Ad-hoc incremental builds must keep the same flag or env.

4. **Confirm `build64` prefix** before `make install`:
   ```sh
   rg '^prefix =' build/cx26/sources/wine/build64/config.status
   ```
   It must be `…/install/wine-cx26-x86_64`. A scratch prefix such as
   `/private/tmp/cyder007-install` installs to the wrong tree. Prefer
   `scripts/rebuild-wine-host-unix.sh` (overrides `prefix=`) or
   `bash scripts/build-wine.sh --cx 26 --configure-only --with-vulkan --vulkan-source crossover`
   after deleting `build64/config.cache` when CFLAGS/prefix change.

5. **Do not copy half-built binaries into `~/.cyder/runtime` and call it a
   release.** Ship via `scripts/pack-engine-artifact.sh` (DXVK + minOS +
   codesign gates), then install that archive.

6. **This tree builds CX26 only.** `--cx 25` is retired. Frame-walk and
   wineserver patches apply to the CX26 tree (`tests/test-build-wine.sh`
   asserts `--cx 25` fails with the retired message).

## When to incremental vs full rebuild

| Change | Approach |
|--------|----------|
| `server/*.c` (wineserver) | Incremental: rebuild `server/wineserver`, install |
| One unix `.so` (e.g. `ntdll.so`) | Incremental: rebuild that module + install |
| PE only (`dlls/ntdll/x86_64-windows/ntdll.dll`) | Incremental PE target; no host minOS issue |
| Many unix modules already polluted with minos 15 | `bash scripts/rebuild-wine-host-unix.sh` |
| New configure options, toolchain, or prefix | `rm build64/config.cache` + `--configure-only`, then full `make` |
| Unknown tree state / broken patches | Prefer full `build-wine.sh` path |

## Standard development/test order

For a repeatable end-to-end run, use this order:

1. Preflight `git status`, engine version, `OGOM`, and the `build64` prefix.
2. Run `build-wine.sh --dry-run`, then use the full build path when the source,
   configure, toolchain, or install state is not proven clean.
3. Validate the install tree (`version`, minOS, DXVK payloads, single
   `libMoltenVK.dylib`, and MapleStory cache markers).
4. Run narrow static tests, then `bash tests/run.sh`. A Mach service failure is
   an environment failure, not a passing graphics result; rerun in a desktop
   environment with the required service access.
5. Use the direct MapleStory D3DMetal launcher with explicit `WINE_INSTALL`,
   prefix, GPTK, CompatDB, and log root. Run `--dry-run` and `--no-otp` before
   supplying BeanFun arguments. Keep WINEDEBUG and I/O tracing low-noise unless
   the experiment needs them; for WZ summaries set both
   `CYDER_MAPLESTORY_IO_TRACE=1` and `CYDER_MAPLESTORY_IO_PROFILE=1` plus the
   `+cyderio` channel. `IO_PROFILE` alone produces no summaries. For a
   low-overhead event-correlated run, set `CYDER_MAPLESTORY_IO_RING=1`; it keeps
   the latest bounded regular-file read events in memory and emits them only during Unix
   process termination. To avoid filling the ring during login and map loading,
   also set `CYDER_MAPLESTORY_IO_RING_ARM_FILE` to a not-yet-existing temporary
   file, then create that file immediately before the action under test; the
   next regular-file read arms and clears the ring. The ring includes non-WZ
   file reads after arming. For a high-volume run, set
   `CYDER_MAPLESTORY_IO_SUMMARY=1` to aggregate by path in memory and emit
   compact `CYDER_IO aggregate` records instead of retaining every event.
   Add `CYDER_MAPLESTORY_IO_TIMELINE=1` to emit non-empty 100 ms buckets for
   aligning the I/O burst with the action under test.
   For the adaptive WZ read-ahead result, also set
   `CYDER_MAPLESTORY_IO_CACHE_STATS=1` together with
   `CYDER_MAPLESTORY_IO_SUMMARY=1`. It emits only arm-scoped `CYDER_IO cache`
   path aggregates for cache hits, fills, fill duration, failures, and
   bypasses and `needs_close` skips. A compact decision summary also separates
   cache attempts from `needs_close`, unregistered-handle, and missing-offset
   skips; the arm boundary resets counters but keeps already-filled cache
   windows warm.
   Set `CYDER_MAPLESTORY_FILE_CACHE_MMAP=1` only when comparing an mmap-backed
   window fill; it is disabled by default and remains experimental.
   Set `CYDER_MAPLESTORY_IO_SECTION_MAP=1` separately when testing whether WZ
   resources use `NtMapViewOfSection`/host `mmap`; it emits only aggregate
   section-map counters at process exit and does not alter file reads.
   Compress large logs after the game exits.
6. Pack only through `pack-engine-artifact.sh`; hand off the archive, checksum,
   and manifest rather than a raw install tree.

The full commands and the cold/warm cache A/B protocol are in
[`engine-development-test-workflow.zh-TW.md`](engine-development-test-workflow.zh-TW.md).

## Patch workflow

### Apply / refresh through the build script

```sh
# Dry-run shows order and does not compile:
bash scripts/build-wine.sh --cx 26 --dry-run --without-vulkan

# Configure only (re-applies patches idempotently, then configure):
bash scripts/build-wine.sh --cx 26 --configure-only --with-vulkan --vulkan-source crossover
```

`apply_cyder_patch` is idempotent: check a stable marker first, then try forward
apply, reverse dry-run (“Already applied”), and finally marker detection when a
later patch rewrote the same hunk (e.g. poll-slot diagnostics upgraded by
exit-diagnostics). Marker-first ordering matters because a forward dry-run can
otherwise accept an already-patched source tree and duplicate a helper/guard.

### Marker table (idempotent detection)

| Patch | Stable marker in tree |
|-------|------------------------|
| `wine-11.1-rtlwalkframechain-null-function.patch` | `if (!func) break;` in `dlls/ntdll/signal_x86_64.c` |
| `cyder-wineserver-poll-slot-guard.patch` | `stale poll slot` in `server/fd.c` |
| `cyder-wineserver-exit-diagnostics.patch` | `wineserver_diag_printf` in `server/main.c` |
| `cyder-wineserver-fd-reselect-async-null-ops.patch` | `fd_reselect_async: missing ops` in `server/fd.c` |
| `cyder-wineserver-sock-rebind-async-fd.patch` | `cyder: sock_rebind_async_fds` in `server/sock.c` |
| `cyder-wineserver-async-terminate-null-fd.patch` | `!async->fd || !is_fd_overlapped` in `server/async.c` |
| `cyder-wineserver-free-async-queue-null-fd.patch` | `!async->completion && async->fd` in `server/async.c` |
| `cyder-wineserver-pipe-end-disconnect-null-fd.patch` | `pipe_end_disconnect: null fd` in `server/named_pipe.c` |
| `cyder-wineserver-add-completion-guard.patch` | `add_completion: invalid completion` in `server/completion.c` |
| `cyder-ntdll-query-directory-object-trace.patch` | `cyder QDO` in `dlls/ntdll/unix/sync.c` (optional; not default) |
| `cyder-ntdll-qdo-optnone-NtQueryDirectoryObject.patch` | `cyder QDO optnone` in `dlls/ntdll/unix/sync.c` |
| `maplestory-cx26-no-sched-yield.patch` | `if (is_maplestory_process()) return STATUS_NO_YIELD_PERFORMED;` |
| `maplestory-cx26-file-cache-adaptive.patch` | `CYDER_MAPLESTORY_FILE_CACHE` in `dlls/ntdll/unix/file.c` |
| `maplestory-cx26-io-ring.patch` | `CYDER_MAPLESTORY_IO_RING_EVENTS` in `dlls/ntdll/unix/file.c` |
| `maplestory-cx26-io-ring-arm.patch` | `CYDER_MAPLESTORY_IO_RING_ARM_FILE` in `dlls/ntdll/unix/file.c` |
| `maplestory-cx26-io-summary.patch` | `CYDER_MAPLESTORY_IO_SUMMARY_SLOTS` in `dlls/ntdll/unix/file.c` |
| `maplestory-cx26-io-cache-stats.patch` | `CYDER_MAPLESTORY_IO_CACHE_STATS` in `dlls/ntdll/unix/file.c` |
| `maplestory-cx26-section-map-summary.patch` | `CYDER_MAPLESTORY_SECTION_MAP_PATH` in `dlls/ntdll/unix/virtual.c` |

When adding a new patch that may be rewritten by a later one, add a unique
string marker and a matching `grep -Fq` branch in `scripts/build-wine.sh`.

### Developing a new patch

1. Edit sources under `build/cx26/sources/wine` (or a clean extract for a
   fresh diff).
2. Prefer a **correctness** fix over a soft-guard when the lifecycle bug is
   known; keep soft-guards as belt-and-suspenders if useful.
3. Generate a patch with paths relative to the Wine root (`-p1`):
   ```sh
   # example: from a gitified copy or diff -u against vanilla CX26 wine
   ```
4. Drop it in `patches/`, document it in `patches/README.md`, append to the
   apply list in `scripts/build-wine.sh` (**CX26 block only** if Wine 11–specific).
5. Update `config/engine-release.json`, `scripts/write-engine-manifest.sh`, and
   add a focused test under `tests/` (see existing `test-wineserver-*.sh`).
6. Register the test in `tests/run.sh`.
7. Incremental build → verify → pack (below).

Patch **order** matters when hunks touch the same file. Keep diagnostics /
guards that rewrite messages **after** the patches they amend, or rely on
markers.

## Incremental host rebuild (cheatsheet)

```sh
cd /path/to/cyder-wine-engine
source scripts/env-x86_64.sh
cd build/cx26/sources/wine/build64

# Example: wineserver only
arch -x86_64 env \
  PATH="$LLVM_MINGW/bin:$HOMEBREW_PREFIX/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  MACOSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
  CFLAGS="${CFLAGS:--g -O2} ${CYDER_MACOSX_VERSION_MIN_FLAG}" \
  LDFLAGS="${LDFLAGS:-} ${CYDER_MACOSX_VERSION_MIN_FLAG}" \
  make -j"$(sysctl -n hw.ncpu)" server/wineserver

arch -x86_64 env MACOSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
  make install prefix="$WINE_INSTALL" server/wineserver
# or copy the binary into "$WINE_INSTALL/bin/wineserver" for a quick local try
```

If many unix `.so` files already have `minos 15.0`:

```sh
bash scripts/rebuild-wine-host-unix.sh
```

That deletes host `*.so` / wineserver products and unix objects, rebuilds with
the project minOS, installs with `prefix="$WINE_INSTALL"`, and verifies Mach-O
minos.

## Verify before packing

```sh
# minOS floor (product: every host Mach-O ≤ 10.15)
otool -l install/wine-cx26-x86_64/lib/wine/x86_64-unix/ntdll.so | rg minos
otool -l install/wine-cx26-x86_64/bin/wineserver | rg minos

# DXVK payload required for pack
ls install/wine-cx26-x86_64/lib/dxvk/x86_64-windows/d3d11.dll \
   install/wine-cx26-x86_64/lib/dxvk/i386-windows/d3d11.dll

# Narrow tests
bash tests/run.sh
```

`minos ≤ 10.15` means the binary **declares** it can run on macOS 10.15 or
newer (and must not declare a higher floor such as 15.0).

## Pack and install into Cyder runtime

```sh
# Bump label in config/engine-version.txt when cutting an rc
CYDER_ENGINE_VERSION_LABEL='CX26.3.0-W11-Cyder007-rc1' \
SIGN_IDENTITY='-' \   # or Developer ID Application: …
  bash scripts/pack-engine-artifact.sh --xz --force
```

Pack refuses to ship without `lib/dxvk`, with any Mach-O above the minOS floor,
or with broken codesign after archive round-trip.

Then extract `dist/artifacts/engine-wine-x86_64-*.tar.xz` over
`~/.cyder/runtime/Engines/wine-x86_64` (backup the previous tree first), or pin
the archive into the Cyder app per `integration-with-cyder.md`.

## Quick failure index

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `built for macOS 15.0` / missing `_os_sync_wait_on_address` | Incremental host build without minOS | `rebuild-wine-host-unix.sh` or rebuild with `.env` / flag |
| `make install` writes under `/tmp/...` | Wrong `prefix` in `config.status` | Reconfigure with correct `--prefix`, or `make install prefix="$WINE_INSTALL"` |
| `Cannot apply required Wine patch` on already-patched tree | Later patch rewrote hunk; reverse dry-run fails | Add/use marker detection; confirm marker string in tree |
| Pack fails missing `lib/dxvk` | DXVK never staged into install | Copy/build DXVK into `install/.../lib/dxvk` (see Cyder `scripts/build-dxvk.sh`) |
| Game “DXVK” but WineD3D in logs | Engine lacked `lib/dxvk` or prefix not provisioned | Pack with DXVK; check launch preamble / DLL overrides |
