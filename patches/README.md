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
14. `maplestory-cx26-message-wait-handoff.patch`
15. `maplestory-cx26-core.patch`
16. `maplestory-cx26-window-resizable-flag.patch`
17. `maplestory-cx26-tmp-module-name.patch`
18. `maplestory-cx26-dbghelp-dwarf-guard.patch`
19. `maplestory-cx26-d3d11-shared-texture-test.patch`
20. `maplestory-cx26-d3dmetal-legacy-surface.patch`
21. `maplestory-cx26-plain-metal-layer.patch`
22. `maplestory-cx26-d3d11-full-clear.patch`
23. `maplestory-cx26-dxgi-shared-handle.patch`
24. `maplestory-cx26-texture-user-memory-reload.patch`
25. `maplestory-cx26-blackxchg-foreground.patch`
26. `maplestory-cx26-fullscreen-restore.patch`
27. `maplestory-cx26-no-sched-yield.patch`
28. `maplestory-cx26-file-cache-adaptive.patch`
29. `maplestory-cx26-io-ring.patch`
30. `maplestory-cx26-io-ring-arm.patch`
31. `maplestory-cx26-io-summary.patch`
32. `maplestory-cx26-io-timeline.patch`
33. `maplestory-cx26-io-cache-stats.patch`
34. `maplestory-cx26-section-map-summary.patch`

`w1-win32u-vulkan-soname.patch` is not part of the default patch set. It is a
special-case build-only fallback for CX26 source trees where `win32u/vulkan.c`
still compiles while `SONAME_LIBVULKAN` is absent from `config.h`; request it
explicitly with `--vulkan-soname-fallback`. It does not make D3DMetal load Vulkan
at runtime.

The `win32u` message-wait handoff is enabled for every CX26 build. The remaining
MapleStory entries are enabled by `scripts/build-wine.sh --maplestory`; the
`no-sched-yield` patch itself only changes behavior for `MapleStory.exe` and
leaves other process images on the normal scheduler path. These are compatibility
changes in the Wine/D3D11/macOS paths and do not select a graphics backend. The
primary target is D3DMetal, matching the CX25 OEM runtime; MoltenVK capability /
feature-level checks belong only to a separate DXVK validation run. The
shared-texture and ClearView entries remain one functional group because the
CX25 bisect showed that splitting them produces a partially rendered in-world
state.

`maplestory-cx26-file-cache-adaptive.patch` is the MapleStory-only WZ
read-ahead path for the first-use hitch observed under macOS translation. It
targets read-only `.wz` files, keeps requests larger than 4 KiB on
Wine's normal path, and adapts between 8 KiB and 32 KiB aligned windows after
observing sequential reads. The engine flag remains opt-in for raw Wine; the
Cyder app enables it by default only for MapleStory and exposes an Advanced
preference to disable it. The `CYDER_MAPLESTORY_IO_*` variables remain
diagnostic-only and are disabled in normal launches.
`maplestory-cx26-file-cache-capacity.patch` raises the adaptive cache table to
512 per-process entries without enabling any diagnostic counters. Measured
slot-capacity, no-cache control, and mmap A/B results are recorded in
[`docs/maplestory-cx26-wz-cache-experiments.zh-TW.md`](../docs/maplestory-cx26-wz-cache-experiments.zh-TW.md).

The following patches are development-only diagnostics and are not in the
release patch stack: `maplestory-cx26-io-ring.patch`,
`maplestory-cx26-io-ring-arm.patch`, `maplestory-cx26-io-summary.patch`,
`maplestory-cx26-io-timeline.patch`, `maplestory-cx26-io-cache-stats.patch`,
`maplestory-cx26-section-map-summary.patch`, and the prewarm probes.

`maplestory-cx26-io-ring.patch` adds a separate, opt-in diagnostic ring buffer.
With `CYDER_MAPLESTORY_IO_RING=1`, it retains the latest 8192 regular-file
`NtReadFile`/host-read events in memory, including monotonic timestamps, offsets,
lengths, return values, durations, and paths. It emits the ring only through the
`+cyderio` channel during the Unix process termination path, so it does not write
one log line per read. The probe is intended for event-correlated experiments
and is disabled by default.

`maplestory-cx26-io-ring-arm.patch` adds a lower-noise phase control for that
probe. When `CYDER_MAPLESTORY_IO_RING_ARM_FILE` points to a file that does not
exist at startup, the ring stays disarmed and checks the file on the next
regular-file read. Creating the file arms and clears the ring, emitting a single
`CYDER_IO ring armed` marker per Wine process; after arming, the hot read path does not stat the
control file. With no arm-file variable, the original always-on ring behavior
is preserved. This lets a test load into a map first and capture WZ, graphics,
and other regular-file reads around a first attack without adding a background
thread to Wine.

`maplestory-cx26-io-summary.patch` adds a compact alternative for high-volume
captures. Set `CYDER_MAPLESTORY_IO_SUMMARY=1` (and optionally the same arm file)
to aggregate regular-file reads in memory by path instead of retaining every
event. At process termination it emits counts, bytes, host-read duration,
failure count, length buckets, offset range, sequential/nearby movement, and
first/last timestamps. The fixed 128-path table and summary output avoid the
ring-overflow and per-event log volume seen during the first-attack probe; raw
`CYDER_MAPLESTORY_IO_RING=1` remains available when exact tail events are needed.

`maplestory-cx26-io-timeline.patch` adds an optional 100 ms timeline to summary
mode. Set `CYDER_MAPLESTORY_IO_TIMELINE=1` to emit only non-empty buckets with
read counts, bytes, host duration, and failures. The timeline has 512 buckets
(about 51 seconds) and is reset by the arm file, so a first-attack run can show
the exact I/O burst without writing one line per read.

`maplestory-cx26-io-cache-stats.patch` adds an opt-in, arm-scoped view of the
adaptive WZ cache. Set `CYDER_MAPLESTORY_IO_CACHE_STATS=1` together with
`CYDER_MAPLESTORY_IO_SUMMARY=1`; it reports compact `CYDER_IO cache` lines with
cache hits, read-ahead fills, fill bytes, fill duration, fill failures, and
bypassed requests and `needs_close` skips per WZ path. Its compact decision
summary also separates cache attempts from `needs_close`, unregistered-handle,
and missing-offset skips. When an arm file is used, the telemetry counters
are reset at the arm boundary while already-filled cache windows remain warm,
so the result measures only the action under test without invalidating the
experiment. The mode is disabled unless summary mode is also enabled.

Set `CYDER_MAPLESTORY_FILE_CACHE_MMAP=1` only for the mmap-backed fill
experiment. It keeps the same cache/index behavior but sources each window from
an optional read-only mapping; it is disabled by default and is not a release
recommendation until the first-use hitch is re-tested.

`maplestory-cx26-section-map-summary.patch` is a low-overhead proof probe for
the mmap hypothesis. Set `CYDER_MAPLESTORY_IO_SECTION_MAP=1` to count regular
file section mappings and record whether the mapped file is a `.wz` resource.
It emits one aggregate line and one line per WZ path at process exit through
`+cyderio`; it does not log individual mappings or change the mapping path.

`maplestory-cx26-file-cache-prewarm.patch` adds a separate, opt-in Wine-process
prewarm probe. Set `CYDER_MAPLESTORY_FILE_CACHE_PREWARM_IN_PROCESS=1` together
with the adaptive cache and arm file. At the arm transition, or when a later
resource handle is registered, it finds the same already-open `.wz`/`.ms`
handles used by the game and visits bounded spans at previously observed
first-use offsets, causing the existing per-handle 8 KiB / 32 KiB window to
fill before the action. The current experiment targets the five skill packs
seen at the first attack (`Skill_00001/00/06/05/04.ms`) and limits each span to
32–64 KiB. It never opens a second handle or scans a whole pack.
The follow-up patch also makes arm-file create/remove/re-create transitions
observable. The host-path follow-up can perform one bounded aligned 8 KiB
`pread()` against the game working directory when no target handle is open.
The deferred-start follow-up records the request while the I/O mutex is held,
then releases the mutex before running the bounded probe synchronously inside
the Wine process. This avoids both I/O-lock reentrancy and `pthread_create()`
from the Wine file-registration critical path. The log reports each matched
handle, fill, host-path read, and skipped target; the option is disabled by
default and is a diagnostic experiment, not a release default.
The host-path follow-up adds bounded aligned 8 KiB `pread()` reads inside the
Wine ntdll worker when the game has not opened the target handle yet; it uses
the game's working directory and does not scan or retain a second handle.

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
| `maplestory-cx26-message-wait-handoff.patch` | `MapleStoryPort: preserve one driver wait result` (`dlls/win32u/message.c`) |
| `maplestory-cx26-no-sched-yield.patch` | `if (is_maplestory_process()) return STATUS_NO_YIELD_PERFORMED;` (`dlls/ntdll/unix/sync.c`) |
| `maplestory-cx26-file-cache-adaptive.patch` | `CYDER_MAPLESTORY_FILE_CACHE_MIN_WINDOW` (`dlls/ntdll/unix/file.c`) |
| `maplestory-cx26-file-cache-capacity.patch` | `CYDER_MAPLESTORY_FILE_CACHE_SLOTS 512` (`dlls/ntdll/unix/file.c`) |
| `maplestory-cx26-io-cache-stats.patch` | `CYDER_MAPLESTORY_IO_CACHE_STATS` (`dlls/ntdll/unix/file.c`) |
| `maplestory-cx26-section-map-summary.patch` | `CYDER_MAPLESTORY_SECTION_MAP_PATH` (`dlls/ntdll/unix/virtual.c`) |
| `maplestory-cx26-file-cache-prewarm.patch` | `CYDER_MAPLESTORY_FILE_CACHE_PREWARM_IN_PROCESS` (`dlls/ntdll/unix/file.c`) |
| `maplestory-cx26-file-cache-prewarm-followup.patch` | `CYDER_IO ring disarmed` (`dlls/ntdll/unix/file.c`) |
| `maplestory-cx26-file-cache-prewarm-host-path.patch` | `CYDER_IO prewarm item mode=host-path` (`dlls/ntdll/unix/file.c`) |
| `maplestory-cx26-file-cache-prewarm-deferred-start.patch` | `cyder_maplestory_file_cache_prewarm_requested` (`dlls/ntdll/unix/file.c`) |

New patches that may be amended in place should include a unique marker and a
matching detection branch. Operational steps:
[`docs/incremental-build-and-patches.md`](../docs/incremental-build-and-patches.md).

`obsolete/cyder-ntdll-frame-walk-guard.patch` is retained only to migrate an
incremental Cyder006 source tree. It is removed before the two replacement
patches are applied.

The frame-walk and wineserver patches apply to this CX26-only tree. CX25
source builds are retired.

## MoltenVK (graphics stack, not Wine patch order)

Applied under `$MOLTENVK_SRC` via
`scripts/rebuild-moltenvk-cyder-patches.sh --apply-patches`:

| Patch | Intent |
|-------|--------|
| `cyder-moltenvk-crossover-capability-hacks.patch` | Port the three CrossOver DXVK compatibility advertisements (`geometryShader`, `pipelineStatisticsQuery`, `shaderCullDistance`) required for the D3D10/11 feature-level probe to reach 10_x/11_1. It deliberately does not fake `VK_EXT_transform_feedback` or the AMD bitwise-not compiler workaround. |
| `cyder-moltenvk-timeline-wait-poll.patch` | Host `vkWaitSemaphores` polls timeline counters instead of `MTLSharedEvent notifyListener`, which leaks Mach receive rights on finite-timeout waits (DXVK + MapleStory Classic). |
| `cyder-moltenvk-present-autoreleasepool.patch` | Drain `@autoreleasepool` on Metal present / presented-handler threads. |

The default graphics build is pinned to upstream MoltenVK **1.4.0** by
`scripts/ensure-moltenvk-source.sh` (SHA-256 is checked before extraction), with
the minimum host floor remaining macOS 10.15. Set `MOLTENVK_SOURCE=crossover-foss`
only for an explicit legacy comparison; `custom` requires an explicit
`MOLTENVK_SRC`.

CrossOver's other capability changes were reviewed but are not silently copied
into the 1.4.0 tree:

- The AMD `bitwiseNotCausesICE` flag is coupled to a CrossOver-only
  SPIRV-Cross `bitwise_not_causes_ice` option. Upstream MoltenVK 1.4.0 and its
  pinned SPIRV-Cross revision do not define that option, so porting only the
  flag would not change generated MSL. It needs a separate SPIRV-Cross patch
  and AMD shader regression tests.
- CrossOver's `VK_EXT_transform_feedback` advertisement and no-op/stub entry
  points are not ported. They would advertise incomplete behavior and are not
  part of DXVK 2.7.1's required feature set.
- The ANGLE engine ID/synchronization path, texel-alignment emulation, and
  macOS 26 AMD concurrent-compilation guard are separate CrossOver behavior;
  they are not needed to solve the DXVK feature-level failure. The latter is
  already present in upstream MoltenVK 1.4.0, and the AMD counter-sampling
  guard is also upstream.

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
