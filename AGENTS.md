# Agent instructions (cyder-wine-engine)

Canonical instructions for **Codex, Cursor, Claude Code, Antigravity/Gemini**,
and any other AGENTS.md-aware tool. Tool-specific stubs (`CLAUDE.md`,
`GEMINI.md`, `.cursor/rules/`, `.agents/skills/`) point here—do not fork rules.

This repository builds, patches, signs, and packs the Wine engine consumed by
Cyder. It does **not** own bottles, CompatDB policy, or the Cyder.app UI.

## Before incremental builds or new Wine patches

**Read first (required):**

1. [`docs/incremental-build-and-patches.md`](docs/incremental-build-and-patches.md)
2. [`patches/README.md`](patches/README.md) (apply order and intent)

Then follow that guide. Do not invent ad-hoc `make` invocations that omit
`source scripts/env-x86_64.sh` / `MACOSX_DEPLOYMENT_TARGET` /
`-mmacosx-version-min`.

## Non-negotiables

- Product host minOS floor is **10.15** (`.env` / default). Mach-O `minos` must
  not exceed 10.15 on shipped host binaries (`wine`, `wineserver`, `*.so`,
  bundled dylibs) — **except** bundled DXMT under `lib/dxmt/**`
  (e.g. `lib/dxmt/x86_64-unix/winemetal.so`), which may declare minos up to
  **15.0**. That exemption is intentional: it is pinned upstream DXMT v0.80,
  which Cyder does not rebuild, and Cyder only offers DXMT as a selectable
  graphics backend on **macOS 15+** in the first place, so the exemption
  cannot regress the effective floor. See `scripts/pack-minos-scan.py`.
- Prefer `scripts/rebuild-wine-host-unix.sh` after a contaminated incremental
  host build.
- Frame-walk and wineserver patches are **CX26-only**.
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

## Multi-tool entrypoints

| Tool | Loads |
|------|--------|
| Codex / Cursor / many agents | `AGENTS.md` (this file) |
| Claude Code | `CLAUDE.md` → imports this file |
| Antigravity / Gemini | `GEMINI.md` + this file; skill under `.agents/skills/` |
| Cursor (extra) | `.cursor/rules/incremental-build-and-patches.mdc` |

See [`docs/ai-agent-setup.md`](docs/ai-agent-setup.md).
