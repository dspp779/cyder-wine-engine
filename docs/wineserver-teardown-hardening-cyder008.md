# Wineserver leave/teardown hardening → Cyder008

Date: 2026-07-31  
Status: **queued for next engine pack** (`CX26.3.0-W11-Cyder008`)  
Shipped GA remains: `CX26.3.0-W11-Cyder007` (Cyder 0.9.0)

## Why

Classic MapleStory leave-game / forced `wineserver -k` paths could SIGSEGV the
server after soft-guards already logged a null `pipe_end->fd`. Separately,
`release_job_process` → `add_completion` could fault on a dangling job
completion port (`si_addr=0x18`).

Hang capture: Cyder app repo
`debug/hang-20260731-182944-leave-game/` (and related leave livelock notes).
The **livelock** (grap `NtQueryDirectoryObject` storm) is a different bug; these
patches only harden **teardown** so session cleanup is less likely to kill
wineserver.

## Playtest note (2026-07-31 evening)

One real play session after installing the rebuilt wineserver into
`~/.cyder/runtime` did **not** hang on leave. Leave hangs were already
intermittent, so this is **not** proof the livelock is gone — only that
teardown guards are in the local runtime and did not regress that session.

**Later the same evening (~20:05):** leave-game livelock **reproduced** on
**MSync + DXVK** while the **running** wineserver still had every Cyder008
teardown marker (`pipe_end_disconnect: null fd`, `add_completion: invalid`,
`async_clear_weak_fd`, etc.). Capture:
`ogom/debug/hang-20260731-200537/analysis.txt`.

Conclusion: these patches address force-kill SIGSEGV only; they do **not**
stop the grap `NtQueryDirectoryObject` ↔ `req_get_directory_entries` livelock.

## Patches (apply order after sock-rebind)

| Patch | Role |
|-------|------|
| `cyder-wineserver-async-terminate-null-fd.patch` | `!async->fd` before `is_fd_overlapped`; export `async_clear_weak_fd()` |
| `cyder-wineserver-pipe-end-disconnect-null-fd.patch` | null-fd: diag + `free_async_queue`; clear weak message async fds; peer fd null-check |
| `cyder-wineserver-add-completion-guard.patch` | reject invalid `completion` / wait entries in `add_completion` |

Diag strings (for `cyder-wineserver-diag.log`):

- `pipe_end_disconnect: null fd for pipe_end %p`
- `add_completion: invalid completion %p`

## Tests

```bash
bash tests/test-wineserver-async-terminate-null-fd.sh
bash tests/test-wineserver-pipe-end-disconnect-null-fd.sh
bash tests/test-wineserver-add-completion-guard.sh
```

Registered in `tests/run.sh`.

## Pack checklist (when cutting Cyder008)

1. Confirm `config/engine-version.txt` / `config/engine-release.json` say
   `CX26.3.0-W11-Cyder008` and list all three patches above.
2. `source scripts/env-x86_64.sh` → incremental or full host rebuild as needed.
3. `bash scripts/pack-engine-artifact.sh` (DXVK + minOS ≤ 10.15 + codesign).
4. Pin the new archive into the Cyder app repo (`config/cyder-engine-*`).
5. Smoke: Classic leave + Cyder “stop Wine” / `wineserver -k`; read
   `$WINEPREFIX/cyder-wineserver-diag.log` for soft-guard lines without SIGSEGV
   abort when possible.

## Still open (not Cyder008 scope unless revisited)

- grap-core `NtQueryDirectoryObject` leave livelock (product session cleanup).
- Whether BlackCat.sys absence worsens user-mode scan loops.
