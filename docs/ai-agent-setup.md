# AI agent setup

This repo keeps **one** rule file for every coding agent.

## Source of truth

| File | Role |
|------|------|
| [`AGENTS.md`](../AGENTS.md) | Shared agent instructions (edit here) |
| [`docs/incremental-build-and-patches.md`](incremental-build-and-patches.md) | Full incremental / patch / pack guide |
| [`docs/engine-development-test-workflow.zh-TW.md`](engine-development-test-workflow.zh-TW.md) | End-to-end build, direct-engine test, and pack hand-off runbook |
| `.agents/skills/` | `incremental-wine-build` for daily build/patch; `engine-release-pack` for Developer ID shipping artifacts |

## Entry files

| Tool | File | Notes |
|------|------|-------|
| Codex and other AGENTS.md-aware tools | `AGENTS.md` | Read natively. |
| Claude Code | `CLAUDE.md` | A one-line `@AGENTS.md` import. Claude Code reads `CLAUDE.md`, not `AGENTS.md`, so this stub must stay. |

There are no other per-tool files (the Gemini and Cursor stubs were removed).
A tool that does not read `AGENTS.md` by default should be pointed at it in
that tool's own settings rather than by adding another stub here.

## Cyder app repo (CyderBits)

Engine work belongs here. The CyderBits checkout's `AGENTS.md` and its
`cyder-wine-engine-redirect` skill send Wine-engine tasks to this repository.
Open **this** workspace when doing incremental Wine builds or engine patches.

## Optional local overrides (not committed)

| File | Use |
|------|-----|
| `AGENTS.override.md` | Codex personal overrides |
| `CLAUDE.local.md` | Claude Code personal overrides |

Keep machine paths, signing identities, and secrets out of committed agent
files. Use `.env` for `MACOSX_DEPLOYMENT_TARGET` (see `.env.example`).
