# Cyder Wine Engine

This repository owns the reproducible build, patch, test, signing, and packaging
pipeline for the Wine engine consumed by Cyder.

It intentionally does **not** own the Cyder app, user prefixes, game profiles,
CompatDB policy, or engine installation UI. Cyder continues to bundle a pinned
engine artifact during the first extraction phase.

## Current release target

- Engine: `CX26.3.0-W11-Cyder010`
- Base: CrossOver 26.3.0 / Wine 11.0
- Host: macOS x86_64 under Rosetta 2
- Product deployment floor: macOS 10.15 (`.env` / `MACOSX_DEPLOYMENT_TARGET`, default 10.15)
- Architectures: x86_64 host with i386 and x86_64 Windows PE support
- Graphics: MoltenVK 1.4.0, DXVK 1.10.3, DXVK2 2.7.1, DXMT 0.80

The ordered patch set is recorded in
[`config/engine-release.json`](config/engine-release.json). Built artifacts also
contain an `engine-manifest.json`, while the distribution directory receives a
sidecar manifest with the final archive SHA-256.

## Local inputs

Source and toolchain archives are deliberately excluded from Git. Place:

```text
tools/archives/crossover-sources-26.3.0.tar.gz
tools/archives/llvm-mingw-20260616-ucrt-macos-universal.tar.xz
```

Only use source archives and binaries you are licensed to use and redistribute.
This repository tracks original build automation and patch files; it does not
publish the CrossOver source archive.

## Build

完整的首次建置流程（包括 Xcode、MoltenVK、Wine、graphics payload、測試及封裝）請看
[`docs/build-engine-from-scratch.zh-TW.md`](docs/build-engine-from-scratch.zh-TW.md)。

```sh
bash scripts/build-wine.sh --cx 26 --prepare-only
bash scripts/build-wine.sh --cx 26 --bootstrap-brew --install-deps \
  --configure-only --without-vulkan
```

上面是只準備 source、Homebrew 與基礎依賴的最小流程；完整 engine 請依照上方的
從零建置文件接續執行。

For the Cyder MoltenVK path (upstream 1.4.0 with Cyder patches):

```sh
bash scripts/build-graphics-stack.sh --cx 26 --install-deps --moltenvk-source upstream
bash scripts/build-graphics-stack.sh --cx 26 --moltenvk-source upstream
bash scripts/build-wine.sh --cx 26 --with-vulkan --vulkan-source crossover
```

Incremental builds reuse `build/cx26/sources/wine/build64` and the install tree.
See **[`docs/incremental-build-and-patches.md`](docs/incremental-build-and-patches.md)**
for env/minOS rules, patch markers, cheatsheets, and pack gates. Agents
(Codex, Cursor, Claude, Antigravity): start from [`AGENTS.md`](AGENTS.md) and
[`docs/ai-agent-setup.md`](docs/ai-agent-setup.md).

The patch application is idempotent and can migrate a Cyder006 combined
frame-walk patch into the current split patch set.

Large ignored trees live in this repo (not CyderBits/ogom):

- `.brew-x86`
- `build`
- `install`
- `tools/archives`

A CyderBits/ogom checkout may keep compatibility symlinks pointing here so old
scripts still resolve the same paths. Prefer building and packing from this
repository.

Host minOS comes from `.env` (`MACOSX_DEPLOYMENT_TARGET`, see `.env.example`)
or defaults to `10.15`. `build-wine.sh` bakes `-mmacosx-version-min=…` into
configure/make. After a bad incremental build, repair with:

```sh
bash scripts/rebuild-wine-host-unix.sh
```

## Test

```sh
bash tests/run.sh
```

The runtime frame-walk test is skipped when no local engine exists. To test a
specific candidate:

```sh
FRAME_WALK_WINE_RUNTIME=/path/to/wine-x86_64 \
  bash tests/test-ntdll-frame-walk-guard.sh
```

## Package

```sh
CYDER_ENGINE_VERSION_LABEL='CX26.3.0-W11-Cyder010' \
SIGN_IDENTITY='Developer ID Application: …' \
  bash scripts/pack-engine-artifact.sh --xz --force
```

Outputs are placed in `dist/artifacts/`:

- compressed engine archive;
- archive `.sha256`;
- embedded engine manifest;
- archive sidecar `.manifest.json`;
- `engine-version.txt` for the Cyder integration step.

Cyder must consume a specific archive and verify its sidecar manifest. It must
not download an unversioned “latest” engine.
