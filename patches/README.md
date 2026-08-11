# Engine patch set

Patch order for the CX26.3 / Wine 11.0 Cyder engine:

1. `a6-final-same-view-backing-sync.patch`
2. `wine-11.1-rtlwalkframechain-null-function.patch`
3. `cyder-ntdll-frame-walk-page-fault-guard.patch`
4. `cyder-wineserver-sock-reselect-pseudo-fd.patch`
5. `cyder-wineserver-poll-slot-guard.patch`
6. `cyder-wineserver-exit-diagnostics.patch`
7. `cyder-wineserver-fd-reselect-async-null-ops.patch`
8. `cyder-wineserver-sock-rebind-async-fd.patch`
9. `cyder-wineserver-async-terminate-null-fd.patch`
10. `cyder-wineserver-free-async-queue-null-fd.patch`
11. `cyder-wineserver-pipe-end-disconnect-null-fd.patch`
12. `cyder-wineserver-add-completion-guard.patch`
13. `cyder-ntdll-qdo-optnone-NtQueryDirectoryObject.patch`

CompatDB policy is no longer compiled into ntdll. `runtime/cxcompatdb/cxcompatdb.c`
builds as the open `cxcompatdb.so` loaded through CrossOver's existing loader
hook. The obsolete ntdll and executable-specific Steam patches have been removed;
incremental trees carrying them must be restored from a clean CrossOver source
archive before rebuilding.

`a6-final-same-view-backing-sync.patch` finalizes Retina/backing-size changes
on the same `NSView` before OpenGL presents again. It prevents the resize,
Alt+Enter, and minimize/restore black-screen path without forcing a view swap.

`wine-11.1-rtlwalkframechain-null-function.patch` is the minimal upstream
Wine 11.1–11.14 behavior backport: stop x86_64 frame walking when no runtime
function entry exists.

`cyder-ntdll-frame-walk-page-fault-guard.patch` is the narrowly scoped Cyder
addition for non-null but unreadable or concurrently invalidated unwind
metadata.

The two `cyder-wineserver-*` patches address a wineserver `abort()` that hangs
every client process in the prefix, observed as the game freezing while
entering a map:

    wineserver: server/fd.c:1665: set_fd_events: Assertion `poll_users[user] == fd' failed.

`cyder-wineserver-sock-reselect-pseudo-fd.patch` fixes the reachable cause.
An uninitialized socket still uses a pseudo-fd, whose `poll_index` is -1, so
`set_fd_events()` indexes `poll_users[-1]`. Upstream only guards the single
`sock_reselect_async()` call site; the ~30 remaining `sock_reselect()` callers
(including the `recv_socket`, `send_socket` and `socket_get_events` request
handlers) do not. Wine 2.0.1 still had an equivalent `sock->polling` guard
inside `sock_reselect()`; it was lost in the later socket rewrite.

`cyder-wineserver-poll-slot-guard.patch` is the containment layer: any stale or
missing poll slot reports one diagnostic line and skips instead of aborting.
This also covers the unrelated use-after-free path reported upstream in 2018
(<https://wine-devel.winehq.narkive.com/E13v3OXT>), which the sock.c fix cannot
address. Both are still unfixed in Wine 11.11 and have no Bugzilla entry.

`cyder-wineserver-exit-diagnostics.patch` is temporary diagnosis for silent
wineserver exits observed after the poll-slot work: SIGTERM/SIGINT/SIGHUP/SIGQUIT
handlers print `si_pid`/`si_uid` (and sender `path=` via `proc_pidpath` on
Apple), `main_loop` return dumps `active_users` and process counters, and the
stale-poll message is upgraded to `FATAL` with an immediate `fflush`. SIGSEGV
and SIGBUS handlers are installed unconditionally (not gated on
`core_dump_disabled()` / RLIMIT_CORE) so a crash still leaves `si_addr`/`si_code`
plus a `backtrace()` frame/symbol dump in the diag log before abort — even when
core dumps are enabled. An `atexit` breadcrumb records clean exits after the
master socket is up. Every diagnostic line is also appended to
`$WINEPREFIX/cyder-wineserver-diag.log` (via `config_dir_fd`) so a killed gzip
capture pipe cannot erase the death reason. Non-SEGV/BUS behavior otherwise
stays non-aborting.

`cyder-wineserver-fd-reselect-async-null-ops.patch` guards `fd_reselect_async()`
against a NULL `fd_ops` (or missing `reselect_async`) vtable. Confirmed SIGSEGV
at offset 0x58 (`si_addr=0x58`) on the path `sock_poll_event` →
`complete_async_poll` → `async_terminate` → `async_reselect` →
`fd_reselect_async`. Logs via `wineserver_diag_printf` (rate-limited) and returns
instead of aborting. Kept as a safety net after the proper rebind fix below.

`cyder-wineserver-sock-rebind-async-fd.patch` is the correctness fix for that
crash/livelock: `queue_async()` keeps a weak `async->fd`, but sock I/O asyncs
live on sock-local queues (`read_q`/`write_q`/`accept_q`/`connect_q`/`poll_q`/
`ifchange_q`), which `free_async_queue` only clears when the sock is destroyed.
`accept_into_socket` / `init_socket` used to `release_object(old fd)` and assign
a new fd without updating those weak pointers. The patch exports
`async_queue_rebind_fd()` and calls `sock_rebind_async_fds()` before releasing
the old fd so matching weak pointers become the new fd (still weak; no
grab/release). Soft-guards stay as belt-and-suspenders.

`cyder-wineserver-async-terminate-null-fd.patch` guards `async_terminate()` when
`async->fd` is already NULL (`free_async_queue` / pipe teardown). Without it,
`is_fd_overlapped(NULL)` SIGSEGVs (`si_addr=0`) on `STATUS_PIPE_BROKEN` wakeups.
Also exports `async_clear_weak_fd()` so `named_pipe.c` can clear opaque weak
pointers before terminate.

`cyder-wineserver-free-async-queue-null-fd.patch` guards `free_async_queue()` when
queued asyncs already have a NULL weak `async->fd`. Confirmed 2026-08-02: after
`pipe_end_disconnect` logged `null fd` and called `free_async_queue(&read_q)`,
unguarded `fd_get_completion(async->fd)` still SIGSEGVd (`si_addr=0`,
`pipe_end_disconnect+161`). Matches the safe pattern already used in
`add_async_completion`.

`cyder-wineserver-pipe-end-disconnect-null-fd.patch` guards
`pipe_end_disconnect()` when `pipe_end->fd` is NULL. Confirmed leave-game SIGSEGV
at `si_addr=0xf8` (`&fd->wait_q`) on `kill_process` → `handle_table_destroy` →
`pipe_end_destroy` → `pipe_end_disconnect` → `fd_async_wake_up`. Logs via
`wineserver_diag_printf` (rate-limited), skips `fd_async_wake_up` /
`set_fd_signaled`, and when fd is NULL uses `free_async_queue` instead of
`async_wake_up(STATUS_PIPE_BROKEN)` (which still hit null/dangling `async->fd`).
Also nulls weak `message->async->fd` before terminate and null-checks the peer fd
wake in `reselect_read_queue`.

`cyder-wineserver-add-completion-guard.patch` hardens `add_completion()` for
job teardown (`release_job_process` → `add_job_completion`) when
`job->completion_port` is a dangling pointer (`si_addr=0x18` / invalid wait).
Validates `completion_ops`, skips bad `completion_wait` entries, and logs via
`wineserver_diag_printf`.

`cyder-ntdll-qdo-optnone-NtQueryDirectoryObject.patch` is a **narrow bandage**
for the MapleStory Classic `grap-core64.aes` leave-game busy-loop that hammers
`NtQueryDirectoryObject` → `get_directory_entries(index=0)` on Wine’s virtual
HID mouse symlink (`VID_845E`). It marks only that function
`__attribute__((optnone))` under Clang so host `-O2` codegen cannot form the
livelock (same class as `-O0` / dead `fprintf` heisenbug bandages). **Not** a
semantic HID / directory-object fidelity fix. Evidence:
[`docs/grap-core-qdo-ab-findings.md`](../docs/grap-core-qdo-ab-findings.md).

`cyder-ntdll-query-directory-object-trace.patch` remains for optional diagnosis
(`CYDER_QDO_TRACE=1`); copy also under `patches/experimental/`. It is **not**
in the default CX26 apply list (superseded by optnone). See
[`docs/grap-core-qdo-trace.md`](../docs/grap-core-qdo-trace.md).

### Idempotent apply markers

When a later patch rewrites an earlier hunk, `patch --reverse --dry-run` can fail
even though the feature is present. `scripts/build-wine.sh` then treats these
strings as “already applied”:

| Patch | Marker |
|-------|--------|
| `a6-final-same-view-backing-sync.patch` | `macdrv_finalize_window_backing_sync` (`cocoa_window.m`) |
| `wine-11.1-rtlwalkframechain-null-function.patch` | `if (!func) break;` (`signal_x86_64.c`) |
| `cyder-wineserver-poll-slot-guard.patch` | `stale poll slot` (`fd.c`) |
| `cyder-wineserver-exit-diagnostics.patch` | `wineserver_diag_printf` (`main.c`) |
| `cyder-wineserver-fd-reselect-async-null-ops.patch` | `fd_reselect_async: missing ops` (`fd.c`) |
| `cyder-wineserver-sock-rebind-async-fd.patch` | `cyder: sock_rebind_async_fds` (`sock.c`) |
| `cyder-wineserver-async-terminate-null-fd.patch` | `!async->fd || !is_fd_overlapped` (`async.c`) |
| `cyder-wineserver-free-async-queue-null-fd.patch` | `!async->completion && async->fd` (`async.c`) |
| `cyder-wineserver-pipe-end-disconnect-null-fd.patch` | `pipe_end_disconnect: null fd` (`named_pipe.c`) |
| `cyder-wineserver-add-completion-guard.patch` | `add_completion: invalid completion` (`completion.c`) |
| `cyder-ntdll-query-directory-object-trace.patch` | `cyder QDO` (`dlls/ntdll/unix/sync.c`) — optional / not default |
| `cyder-ntdll-qdo-optnone-NtQueryDirectoryObject.patch` | `cyder QDO optnone` (`dlls/ntdll/unix/sync.c`) |

New patches that may be amended in place should include a unique marker and a
matching detection branch. Operational steps:
[`docs/incremental-build-and-patches.md`](../docs/incremental-build-and-patches.md).

`obsolete/cyder-ntdll-frame-walk-guard.patch` is retained only to migrate an
incremental Cyder006 source tree. It is removed before the two replacement
patches are applied.

The frame-walk and wineserver patches are intentionally CX26-only. CX25 uses a
Wine 10 base and must not receive them without a separate source and ABI review.

## MoltenVK (graphics stack, not Wine patch order)

Applied under `$MOLTENVK_SRC` via
`scripts/rebuild-moltenvk-cyder-patches.sh --apply-patches`:

| Patch | Intent |
|-------|--------|
| `cyder-moltenvk-timeline-wait-poll.patch` | Host `vkWaitSemaphores` polls timeline counters instead of `MTLSharedEvent notifyListener`, which leaks Mach receive rights on finite-timeout waits (DXVK + MapleStory Classic). |
| `cyder-moltenvk-present-autoreleasepool.patch` | Drain `@autoreleasepool` on Metal present / presented-handler threads. |

Markers: `Cyder: each -[MTLSharedEvent notifyListener` (`MVKSync.mm`),
`Cyder: Metal scheduled-handler threads` (`MVKImage.mm`).

Cyder008 packages the equivalent host-wait fix as an engine-owned re-export
shim pair (`libMoltenVK.dylib` + `libMoltenVK.real.dylib`). The packer validates
the dependency and exported wait entry point, so Cyder.app no longer injects
or builds this workaround at runtime.

For local development, install the re-export shim with Apple clang:

```bash
bash tools/cyder-mvk-timeline-wait-poll/install-shim.sh --install-runtime
```

Undo with `--undo --install-runtime`. Once Xcode can rebuild
`libMoltenVK.dylib`, prefer the source patch and remove the shim.

The former App-side RC overlay is retained only as historical documentation:
[`docs/moltenvk-timeline-wait-poll-app-overlay.md`](../docs/moltenvk-timeline-wait-poll-app-overlay.md).
