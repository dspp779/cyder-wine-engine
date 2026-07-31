# Gemini / Antigravity

Follow **`AGENTS.md`** as the source of truth for this repository.

## Before Wine incremental builds or patches

1. Read `docs/incremental-build-and-patches.md`.
2. Read `patches/README.md`.
3. Use the skill `.agents/skills/incremental-wine-build/SKILL.md` when the task
   is an incremental host rebuild, patch authoring, or engine packing.

## Standing rules (summary)

- Host Mach-O minOS floor: **10.15** (`.env` / `MACOSX_DEPLOYMENT_TARGET`).
- Always `source scripts/env-x86_64.sh` before host `make` / `configure`.
- CX26-only for frame-walk and wineserver patches.
- Pack via `scripts/pack-engine-artifact.sh` (DXVK + minOS + codesign gates).
- Do not ship `apple_gptk` inside the engine artifact.
