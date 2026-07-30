# Cyder Wine Engine

This repository owns the reproducible build, patch, test, signing, and packaging
pipeline for the Wine engine consumed by Cyder.

It intentionally does **not** own the Cyder app, user prefixes, game profiles,
CompatDB policy, or engine installation UI. Cyder continues to bundle a pinned
engine artifact during the first extraction phase.

## Current release target

- Engine: `CX26.3.0-W11-Cyder007`
- Base: CrossOver 26.3.0 / Wine 11.0
- Host: macOS x86_64 under Rosetta 2
- Product deployment floor: macOS 10.15
- Architectures: x86_64 host with i386 and x86_64 Windows PE support

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

```sh
bash scripts/build-wine.sh --cx 26 --prepare-only
bash scripts/build-wine.sh --cx 26 --install-deps --without-vulkan
bash scripts/build-wine.sh --cx 26 --without-vulkan
```

For the CrossOver MoltenVK path:

```sh
bash scripts/install-crossover-app-moltenvk.sh
bash scripts/build-wine.sh --cx 26 --with-vulkan --vulkan-source crossover
```

Incremental builds reuse `build/cx26/sources/wine/build64` and the install tree.
The patch application is idempotent and migrates a Cyder006 combined frame-walk
patch into the split Cyder007 patch set.

During the local phase-one migration, an existing CyderBits checkout can be
reused without copying its large ignored trees:

```sh
OGOM_ARCHIVES_DIR=/path/to/CyderBits/tools/archives \
OGOM_BUILD_DIR=/path/to/CyderBits/build \
WINE_INSTALL=/path/to/CyderBits/install/wine-cx26-x86_64 \
  bash scripts/build-wine.sh --cx 26 --without-vulkan
```

Local symlinks for `.brew-x86`, `build`, `install`, and `tools/archives` are
also safe because all four paths are ignored by this repository.

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
CYDER_ENGINE_VERSION_LABEL='CX26.3.0-W11-Cyder007' \
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
