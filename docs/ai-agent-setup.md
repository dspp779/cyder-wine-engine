# AI agent setup (multi-tool)

This repo keeps **one** canonical rule file and thin adapters so Codex, Cursor,
Claude Code, and Antigravity/Gemini stay aligned.

## Source of truth

| File | Role |
|------|------|
| [`AGENTS.md`](../AGENTS.md) | Shared agent instructions (edit here) |
| [`docs/incremental-build-and-patches.md`](incremental-build-and-patches.md) | Full incremental / patch / pack guide |
| [`docs/engine-development-test-workflow.zh-TW.md`](engine-development-test-workflow.zh-TW.md) | End-to-end build, direct-engine test, and pack hand-off runbook |

## Per-tool adapters

| Tool | Files | Notes |
|------|--------|------|
| **Codex** | `AGENTS.md` | Native. Optional personal overrides: gitignored `AGENTS.override.md`. |
| **Cursor** | `AGENTS.md` + `.cursor/rules/incremental-build-and-patches.mdc` | Rule is `alwaysApply` and points at the guide. |
| **Claude Code** | `CLAUDE.md` | Imports `@AGENTS.md`; add Claude-only notes under that import. |
| **Antigravity / Gemini** | `GEMINI.md` + `AGENTS.md` + `.agents/skills/incremental-wine-build/` | Both root md files are read; the skill activates for build/patch/pack tasks. |

Do **not** duplicate long checklists into every stub. Change `AGENTS.md` and the
incremental guide; stubs only import or summarize.

## Cyder app repo (ogom)

Engine work belongs here. The Cyder (ogom) checkout has a Cursor rule (and
matching stubs if present) that redirects Wine-engine tasks to this repository.
Open **this** workspace when doing incremental Wine builds or engine patches.

## Optional local overrides (not committed)

| File | Use |
|------|-----|
| `AGENTS.override.md` | Codex personal overrides |
| `CLAUDE.local.md` | Claude Code personal overrides |

Keep machine paths, signing identities, and secrets out of committed agent
files. Use `.env` for `MACOSX_DEPLOYMENT_TARGET` (see `.env.example`).
