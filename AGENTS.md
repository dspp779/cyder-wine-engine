# Agent instructions (cyder-wine-engine)

Canonical instructions for every coding agent. `CLAUDE.md` is a one-line
`@AGENTS.md` import (Claude Code reads `CLAUDE.md`, not this file); there are
no other per-tool files. Skills are under `.agents/skills/`.

This repository is the Wine engine that actually runs Windows `.exe` files. It
builds, patches, signs, and packs the engine consumed by Cyder. The application
layer lives in [CyderBits](https://github.com/dspp779/CyderBits); this tree does
**not** own bottles, CompatDB policy, or the Cyder.app UI.

## Before incremental builds or new Wine patches

**Read first (required):**

1. [`docs/incremental-build-and-patches.md`](docs/incremental-build-and-patches.md)
2. [`docs/engine-development-test-workflow.zh-TW.md`](docs/engine-development-test-workflow.zh-TW.md)
   (end-to-end build, test, and direct-engine hand-off)
3. [`patches/README.md`](patches/README.md) (apply order and intent)

Then follow that guide. Do not invent ad-hoc `make` invocations that omit
the project Bash environment, `MACOSX_DEPLOYMENT_TARGET`, or
`-mmacosx-version-min`; see the workflow for the safe `bash -lc` form when a
manual host command needs to source `scripts/env-x86_64.sh`.

## Non-negotiables

- Product host minOS floor is **10.15** (`.env` / default). Mach-O `minos` must
  not exceed 10.15 on shipped host binaries (`wine`, `wineserver`, `*.so`,
  bundled dylibs) — **except**:
  - bundled DXMT under `lib/dxmt/**` (minos up to **15.0**);
  - versioned MoltenVK reals `libMoltenVK-1.4.2.dylib` and
    `libMoltenVK-1.2.10.dylib` (minos up to **12.0**; Vulkan requires macOS 12+).
    The unversioned wait-poll shim still must not exceed 10.15.
  See `scripts/pack-minos-scan.py`.
- Prefer `scripts/rebuild-wine-host-unix.sh` after a contaminated incremental
  host build.
- This tree builds **CrossOver 26 only**. `--cx 25` is retired.
- Release artifacts go through `scripts/pack-engine-artifact.sh` (DXVK + minOS +
  codesign). Do not treat a raw copy into `~/.cyder/runtime` as a release
  unless the user explicitly asks to install a packed archive.
- Do not redistribute `apple_gptk` inside the engine tarball.
- Prefer Conventional Commits when the user asks for a commit; do not commit
  unless asked.

## Where to change what

| Task | Touch |
|------|--------|
| New engine behavior | `patches/*.patch` + `scripts/build-wine.sh` apply list + tests |
| Patch docs | `patches/README.md`, `config/engine-release.json`, `write-engine-manifest.sh` |
| Build / minOS / pack gates | `scripts/env-x86_64.sh`, `build-wine.sh`, `pack-engine-artifact.sh` |
| Cyder app / bottles | The Cyder (ogom) repo, not here |

## Tests

```sh
bash tests/run.sh
```

Add or extend the narrowest `tests/test-*.sh` when changing patch apply order,
minOS wiring, or pack gates.

Docs are part of the suite: `tests/test-release-contract.py` fails when a
current (non-historical) doc, skill or example names an engine label other than
the one in `config/engine-version.txt`. Write "the previous engine" instead of
an older label, and run that test after editing docs.

Fresh-machine build failures (host Python, `distutils`, glslang, stale media
prefixes, MoltenVK bundle order) are listed under 常見問題 in
[`docs/build-engine-from-scratch.zh-TW.md`](docs/build-engine-from-scratch.zh-TW.md).
Keep the checkout outside `~/Documents`, `~/Desktop` and `~/Downloads`
(currently `~/ogom/cyder-wine-engine`, next to `~/ogom/Cyderbits`); unmerged
work must live on a branch, not in ignored scratch folders. Game-level testing
through Cyder.app is described in CyderBits `docs/development-testing.md`.

## Skills and docs to read

- Read `docs/incremental-build-and-patches.md` before any incremental Wine
  `make` or new `patches/*.patch`.
- Skills are not loaded automatically by every tool. Read
  `.agents/skills/incremental-wine-build/SKILL.md` before building or patching,
  and `.agents/skills/engine-release-pack/SKILL.md` before a Developer ID pack.
- Keep engine work in this repo; Cyder.app / bottles belong in the sibling
  CyderBits checkout.

See [`docs/ai-agent-setup.md`](docs/ai-agent-setup.md).
