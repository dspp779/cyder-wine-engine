# Agent instructions (cyder-wine-engine)

This repo builds, patches, signs and packs the Wine engine that runs Windows
`.exe` files for Cyder. The app, bottles, CompatDB and UI are in
[CyderBits](https://github.com/dspp779/CyderBits) (`~/ogom/Cyderbits`), not here.
This checkout is `~/ogom/cyder-wine-engine`.

## Read before building or patching

1. [`docs/incremental-build-and-patches.md`](docs/incremental-build-and-patches.md)
2. [`docs/engine-development-test-workflow.zh-TW.md`](docs/engine-development-test-workflow.zh-TW.md)
3. [`patches/README.md`](patches/README.md) (apply order and intent)
4. The skill for the task (Claude Code does not load skills automatically):

| Work | Skill |
|---|---|
| Build, patch, rebuild ntdll or wineserver, direct engine tests | `.agents/skills/incremental-wine-build/SKILL.md` |
| Developer ID engine and graphics pack for a release | `.agents/skills/engine-release-pack/SKILL.md` |

## Rules

1. **Use the project environment for every host build.** Set
   `OGOM` to this checkout and run project scripts with `bash`. For a manual
   `make`, use `bash -lc 'source scripts/env-x86_64.sh; arch -x86_64 make …'`.
   A build without it targets arm64 or a newer macOS and has to be redone.
2. **Host binaries must run on macOS 10.15** (`minos` ≤ 10.15 for `wine`,
   `wineserver`, `*.so`, bundled dylibs). Exceptions, checked by
   `scripts/pack-minos-scan.py`: DXMT under `lib/dxmt/` (up to 15.0) and the
   versioned MoltenVK files `libMoltenVK-1.4.2.dylib` and
   `libMoltenVK-1.2.10.dylib` (up to 12.0). The unversioned MoltenVK shim stays
   at 10.15. `minos` is not enough: a function the SDK has and the floor lacks
   is a weak import that is NULL on older macOS. `scripts/pack-weak-import-scan.py`
   refuses any macOS weak import without a reviewed row in
   `config/weak-import-allowlist.tsv`.
3. **Patches are applied by `scripts/build-wine.sh`**, never by editing an
   install tree. A new patch needs: the patch file, its entry and marker in
   `build-wine.sh`, `patches/README.md`, `config/engine-release.json`, and a test.
4. **A release is what `scripts/pack-engine-artifact.sh` produces.** A raw
   copy into `~/.cyder/runtime` is not a release. Never put `apple_gptk` in the
   archive. DXVK 2 is not packed until it passes game testing.
5. **CrossOver 26 only.** `--cx 25` is retired.
6. **Commit on a branch and only when asked** (Conventional Commits). Merge,
   push and delete only what the user named.
7. **Unmerged work lives on a branch**, never only in an ignored folder: a lost
   scratch folder once cost a patch that had to be reconstructed. Before
   deleting or pruning, check `git status`, `git stash list`,
   `git worktree list` and the folder's contents.
8. **Say what was not tested.** A passing suite or a packed archive is not a
   game test.

## Where to change what

| Task | Touch |
|---|---|
| New engine behaviour | `patches/*.patch`, apply list in `scripts/build-wine.sh`, tests |
| Patch docs | `patches/README.md`, `config/engine-release.json`, `scripts/write-engine-manifest.sh` |
| Build, minOS, pack gates | `scripts/env-x86_64.sh`, `scripts/build-wine.sh`, `scripts/pack-engine-artifact.sh` |
| App, bottles, settings UI | CyderBits, not here |

## Tests

```sh
bash tests/run.sh
```

Add or extend the narrowest `tests/test-*.sh` when changing patch order, minOS
wiring or pack gates.

Docs are tested too: `tests/test-release-contract.py` fails when a current doc,
skill or example names an engine label other than the one in
`config/engine-version.txt`, or a MoltenVK version other than the two shipped.
Write "the previous engine" instead of an older label, and run that test after
editing any doc or skill.

## Traps that have cost time before

| Symptom | Cause | Do |
|---|---|---|
| Engine crashes at startup on older macOS (`server_pipe` jumps to 0) though `minos` is 10.15 | A newer SDK declares a function (`pipe2`, SDK 27) so configure enables it; it is a NULL weak import below that macOS | `scripts/minos-unavailable-funcs.py` turns these off in Wine and GLib; anything else: guard the call or override the check, never allowlist an unguarded call |
| Host binary reports `minos 15.0` or arm64 | Build ran without the project environment | `bash scripts/rebuild-wine-host-unix.sh`; do not patch single objects |
| `server_mach_port` errors, hang before a window | No Mach/desktop access (sandbox) | Rerun in a desktop session; do not change Wine code |
| Test result does not match the change | Wrong engine, prefix or wineserver was used | Record all three before each run; discard runs where any is unknown |
| Pack reused an old DXVK archive | Graphics packer keeps existing archives | Repack with `--force` after a DXVK change |
| A command works in bash and fails here | The shell is zsh | Wrap bash syntax in `bash -c '…'`; never source `env-x86_64.sh` into zsh |
| Chained script cannot find its sibling | `dirname $0` is relative | Call scripts by absolute path |
| Fresh-machine build errors (Python, `distutils`, glslang, stale media prefix, MoltenVK bundle order) | See 常見問題 in [`docs/build-engine-from-scratch.zh-TW.md`](docs/build-engine-from-scratch.zh-TW.md) | Follow the row for that symptom |
| Long build hangs with no output | Checkout under `~/Documents`, `~/Desktop` or `~/Downloads` | Keep checkouts under `~/ogom` |

`AGENTS.md` is the only instruction file; `CLAUDE.md` is a one-line
`@AGENTS.md` import. See [`docs/ai-agent-setup.md`](docs/ai-agent-setup.md).
Testing an engine through Cyder.app or with a game is described in CyderBits
`docs/development-testing.md`.
