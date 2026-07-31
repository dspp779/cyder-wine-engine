# Engine patch set

Patch order for the CX26.3 / Wine 11.0 Cyder007 engine:

1. `cyder-compatdb-runtime.patch`
2. `wine-11.1-rtlwalkframechain-null-function.patch`
3. `cyder-ntdll-frame-walk-page-fault-guard.patch`
4. `cyder-wineserver-sock-reselect-pseudo-fd.patch`
5. `cyder-wineserver-poll-slot-guard.patch`
6. `cyder-wineserver-exit-diagnostics.patch`
7. `cyder-wineserver-fd-reselect-async-null-ops.patch`
8. `cyder-wineserver-sock-rebind-async-fd.patch`
9. `cyder-wineserver-pipe-end-disconnect-null-fd.patch`

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

`cyder-wineserver-pipe-end-disconnect-null-fd.patch` guards
`pipe_end_disconnect()` when `pipe_end->fd` is NULL. Confirmed leave-game SIGSEGV
at `si_addr=0xf8` (`&fd->wait_q`) on `kill_process` → `handle_table_destroy` →
`pipe_end_destroy` → `pipe_end_disconnect` → `fd_async_wake_up`. Logs via
`wineserver_diag_printf` (rate-limited), skips `fd_async_wake_up` /
`set_fd_signaled`, and continues other disconnect cleanup. Also null-checks the
peer fd wake in `reselect_read_queue`.

`obsolete/cyder-ntdll-frame-walk-guard.patch` is retained only to migrate an
incremental Cyder006 source tree. It is removed before the two replacement
patches are applied.

`cyder-steam-webhelper-compat.patch` is likewise retained only so the build can
remove the obsolete executable-specific patch before applying the generic
CompatDB runtime.

The frame-walk and wineserver patches are intentionally CX26-only. CX25 uses a
Wine 10 base and must not receive them without a separate source and ABI review.

