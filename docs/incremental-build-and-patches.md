# Incremental Wine builds and patches

Practical guide for changing the CX26 Cyder engine without a full rebuild, and
for adding patches safely. Read this **before** running ad-hoc `make` in
`build64` or editing Wine sources under `build/cx*/sources/wine`.

Related:

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

1. **Always load the project env** before host `make` / `configure`:
   ```sh
   source scripts/env-x86_64.sh
   ```
   This loads `.env` (if present) and sets `MACOSX_DEPLOYMENT_TARGET` (default
   **10.15**) plus `CYDER_MACOSX_VERSION_MIN_FLAG`.

2. **Never rely on the SDK default minOS.** On a modern macOS SDK, bare `clang`
   produces Mach-O `minos 15.0`. That breaks older hosts
   (`_os_sync_wait_on_address`, “built for macOS 15.0 which is newer than
   running OS”). Full `build-wine.sh` bakes `-mmacosx-version-min=…` into
   configure. Ad-hoc incremental builds must keep the same flag or env.

3. **Confirm `build64` prefix** before `make install`:
   ```sh
   rg '^prefix =' build/cx26/sources/wine/build64/config.status
   ```
   It must be `…/install/wine-cx26-x86_64`. A scratch prefix such as
   `/private/tmp/cyder007-install` installs to the wrong tree. Prefer
   `scripts/rebuild-wine-host-unix.sh` (overrides `prefix=`) or
   `bash scripts/build-wine.sh --cx 26 --configure-only --with-vulkan --vulkan-source crossover`
   after deleting `build64/config.cache` when CFLAGS/prefix change.

4. **Do not copy half-built binaries into `~/.cyder/runtime` and call it a
   release.** Ship via `scripts/pack-engine-artifact.sh` (DXVK + minOS +
   codesign gates), then install that archive.

5. **CX26-only for frame-walk and wineserver patches.** CX25 (Wine 10) must not
   receive them without a separate ABI review (`tests/test-build-wine.sh`
   enforces this).

## When to incremental vs full rebuild

| Change | Approach |
|--------|----------|
| `server/*.c` (wineserver) | Incremental: rebuild `server/wineserver`, install |
| One unix `.so` (e.g. `ntdll.so`) | Incremental: rebuild that module + install |
| PE only (`dlls/ntdll/x86_64-windows/ntdll.dll`) | Incremental PE target; no host minOS issue |
| Many unix modules already polluted with minos 15 | `bash scripts/rebuild-wine-host-unix.sh` |
| New configure options, toolchain, or prefix | `rm build64/config.cache` + `--configure-only`, then full `make` |
| Unknown tree state / broken patches | Prefer full `build-wine.sh` path |

## Patch workflow

### Apply / refresh through the build script

```sh
# Dry-run shows order and does not compile:
bash scripts/build-wine.sh --cx 26 --dry-run --without-vulkan

# Configure only (re-applies patches idempotently, then configure):
bash scripts/build-wine.sh --cx 26 --configure-only --with-vulkan --vulkan-source crossover
```

`apply_cyder_patch` is idempotent: forward apply, else reverse dry-run
(“Already applied”), else **marker detection** when a later patch rewrote the
same hunk (e.g. poll-slot diagnostics upgraded by exit-diagnostics).

### Marker table (idempotent detection)

| Patch | Stable marker in tree |
|-------|------------------------|
| `wine-11.1-rtlwalkframechain-null-function.patch` | `if (!func) break;` in `dlls/ntdll/signal_x86_64.c` |
| `cyder-wineserver-poll-slot-guard.patch` | `stale poll slot` in `server/fd.c` |
| `cyder-wineserver-exit-diagnostics.patch` | `wineserver_diag_printf` in `server/main.c` |
| `cyder-wineserver-fd-reselect-async-null-ops.patch` | `fd_reselect_async: missing ops` in `server/fd.c` |
| `cyder-wineserver-sock-rebind-async-fd.patch` | `cyder: sock_rebind_async_fds` in `server/sock.c` |
| `cyder-wineserver-async-terminate-null-fd.patch` | `!async->fd || !is_fd_overlapped` in `server/async.c` |
| `cyder-wineserver-pipe-end-disconnect-null-fd.patch` | `pipe_end_disconnect: null fd` in `server/named_pipe.c` |
| `cyder-wineserver-add-completion-guard.patch` | `add_completion: invalid completion` in `server/completion.c` |

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
