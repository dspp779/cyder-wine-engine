# grap-core residual A/B findings (QDO / ntdll)

Date: 2026-08-07  
Repos: `cyder-wine-engine` (Wine) + MapleStory Classic on Cyder bottle  
Related: `docs/grap-core-qdo-trace.md`, Cyder app
`grap-core64-residual-process-analysis.md`

## Symptom

After exiting MapleStory Classic in-game, `grap-core64.aes` (NGS) often
remains and busy-loops. Host power ~17–18W with:

- `grap-core*` ~50–55% CPU
- `wineserver` ~45–50% CPU

`sample(1)` on residual wineserver shows a hot path through
`req_get_directory_entries` (`directory.c`). grap’s hot thread sits in
`__wine_syscall_dispatcher` (Rosetta; PE frames unresolved). Classic EXE is
gone.

## Method notes (avoid false negatives)

Earlier “clean exit” runs were sometimes invalid (wrong live binary, maple
wineserver assert/teardown, or incomplete wait after prefix cleanup).

Reliable protocol used for the matrix below:

1. Kill grap / Classic / `wineserver -k`; wait until `pgrep` is empty.
2. Install the intended `ntdll.so` + `wineserver` on disk.
3. Launch; verify **live** mapped sizes / markers (`lsof` / `strings`).
4. Fully enter the game world, then exit in-game.
5. Measure power + whether grap+wineserver remain.

Rosetta AOT can fail after swapping Mach-O (`Attachment of code signature
supplement failed`); clear bad AOT and/or ad-hoc `codesign` then relaunch.

## Patch under test

`patches/cyder-ntdll-query-directory-object-trace.patch`  
Marker: `cyder QDO`. Opt-in log via `CYDER_QDO_TRACE=1`.

When the env var is **unset**, the compiled helper still runs once
(`getenv`), then returns 0 every call — **no** `fprintf`.

## Empirical matrix

Bottle: `~/Library/Application Support/Cyder/bottles/shared`  
Runtime under test: `ogom/tools/runtime/wine-cx26-maple-patched`  
Game: `Maplestory_Classic.exe` (TMS Classic).

| ntdll | wineserver | `CYDER_QDO_TRACE` | Result |
|-------|------------|-------------------|--------|
| maple original (~726144) | maple (~861984) | n/a | Residual ~17–18W |
| maple | Cyder poll-guard (~842408) | n/a | Residual ~17W |
| Cyder **no QDO** (~713544) | Cyder | n/a | Residual ~17W |
| Cyder **with QDO** (~713672) | Cyder | `1` | Clean ~5–6W |
| Cyder **with QDO** (~713672) | Cyder | unset | Clean ~5–7W (×3) |
| same-tree **WITH-qdo** (713672) | Cyder | unset | Clean ~5–6W |
| same-tree **NO-qdo** (713544) | Cyder | unset | Residual ~17W |

### Same-tree control (causal)

Both binaries built 2026-08-07 from the same CX26 tree with identical make
flags (`-g -O2 -mmacosx-version-min=10.15`), toggling **only** the QDO
patch:

| Artifact | Size | SHA-1 (abbrev) |
|----------|------|----------------|
| `logs/ntdll-same-tree-with-qdo.so` | 713672 | `ee6f0ecf…` |
| `logs/ntdll-same-tree-no-qdo.so` | 713544 | `fe6b5d7d…` |

Unique strings differ **only** by QDO / `CYDER_QDO_TRACE` literals. Byte-level
`cmp` still shows large relocation drift (expected when one `.o` grows).

**Conclusion:** the QDO patch itself is necessary and sufficient (in this
pairing) to flip residual → clean, **even with tracing disabled**. Not
explained by wineserver choice alone, nor by `fprintf` I/O.

## What this is *not*

- Not proof that Wine’s `Context` advancement is broken. Early QDO capture
  (trace on) showed `restart=0`, advancing `ctx_in`/`ctx_out`, and normal
  `STATUS_NO_MORE_ENTRIES` (`8000001a`) for short scans — weakens “stuck
  Context” (case C).
- Not a semantic fix for directory-object / HID fidelity. With TRACE off,
  control flow is nearly identical to stock; extras are a helper call,
  locals, and a tiny `STATUS_BUFFER_TOO_SMALL` temp rewrite.
- Shipping the diagnostic patch as a “fix” would be a **workaround /
  heisenbug bandage** until the minimal effective hunk is known.

## Residual forensics snapshot

Dir: `logs/residual-forensics-20260807-215654/` (maple ntdll + maple WS
baseline residual). See `SUMMARY.md` there.

## Next: minimal-hunk bisect

Goal: find the smallest source change that still prevents residual.

Planned variants (artifacts under `logs/ntdll-bisect-*.so`):

1. **v1 — helper only:** `cyder_qdo_should_trace()` + call at entry;
   discard result; no `fprintf`; no other logic edits.
2. **v2 — `need` temp only:** only the `STATUS_BUFFER_TOO_SMALL` /
   `ULONG need` rewrite from the full patch.
3. Further splits (empty `noinline` barrier, `getenv` alone, etc.) as
   results dictate.

Play order: install variant + Cyder WS, checklist launch, full enter/exit.

## Launch cheat-sheet

```sh
RT=…/ogom/tools/runtime/wine-cx26-maple-patched
# after clean wineserver/grap:
cp -f logs/ntdll-same-tree-with-qdo.so "$RT/lib/wine/x86_64-unix/ntdll.so"
cp -f install/wine-cx26-x86_64/bin/wineserver "$RT/bin/wineserver"
# unset CYDER_QDO_TRACE; use run-maplestory-classic-debug.sh
```

## Bisect artifacts (built)

| Variant | File | Size | SHA-1 (abbrev) | Intent |
|---------|------|------|----------------|--------|
| v1 | `logs/ntdll-bisect-v1-helper-only.so` | 713672 | `674b6f97…` | `should_trace` + call only (no fprintf) |
| v2 | `logs/ntdll-bisect-v2-need-temp-only.so` | 713544 | `e65b2006…` | `ULONG need` rewrite only |
| v3 | `logs/ntdll-bisect-v3-structure-no-fprintf.so` | 713672 | `82aafe40…` | helper+ctx_in+need, no fprintf |
| v4 | `logs/ntdll-bisect-v4-fprintf-no-need.so` | 713672 | `3b30256d…` | fprintf paths, no need rewrite |
| v5 | `logs/ntdll-bisect-v5-noinline-sink.so` | 713672 | `c05c010b…` | if(diag) noinline sink, no fprintf strings |
| v10 | `logs/ntdll-bisect-v10-sink6.so` | 713672 | `3c8b108e…` | 6-arg noinline sink (not fprintf) |
| v9 | `logs/ntdll-bisect-v9-short-format.so` | 713672 | `de702f94…` | one full-arity fprintf, short fmt |
| v8 | `logs/ntdll-bisect-v8-one-fprintf.so` | 713672 | `174b521f…` | single full-arity enter log |
| v7 | `logs/ntdll-bisect-v7-minimal-fprintf.so` | 713672 | `0f0d3458…` | if(diag) fprintf(stderr,"x\\n") only |
| v6 | `logs/ntdll-bisect-v6-format-strings-only.so` | 713864 | `06d24b79…` | format strings (`used`) + helper only |

Experimental patches:
`patches/experimental/cyder-ntdll-qdo-bisect-v{1,2}-*.patch`


### Bisect play results

| Variant | Result |
|---------|--------|
| v1 helper-only | Residual ~17W |
| v2 need-temp-only | *not required* (v4 already drops need) |
| v3 structure no fprintf | Residual ~17W |
| v4 fprintf without need | **Clean ~6–7W** |
| v5 noinline sink | Residual ~17W |
| v6 format strings only | Residual ~17W |
| v7 minimal fprintf | Residual ~17W |
| v8 one full-arity fprintf | **Clean ~6–7W** |
| v9 short format | **Clean ~6–7W** |
| v10 sink6 | Residual ~16–17W |

| Piece | Needed to suppress residual? |
|-------|------------------------------|
| `should_trace` / `getenv` alone (v1) | No |
| `ctx_in` + `ULONG need` without fprintf (v3) | No |
| `if (diag)` + noinline sink (v5) | No |
| format strings alone (v6) | No |
| `if (diag) fprintf(stderr, "x\\n")` (v7) | No |
| one full-arity `fprintf` + long fmt (v8) | Yes |
| one full-arity `fprintf` + short fmt (v9) | **Yes** |
| 6-arg noinline sink (v10) | **No** |
| five rich `fprintf` sites (v4) | Yes (superseded) |
| `ULONG need` rewrite | No |

With `CYDER_QDO_TRACE` unset, `diag` stays 0 after the first `getenv`, so
the entry call **never runs**. Clean exit requires a **dead multi-argument
`fprintf` to libc** in `NtQueryDirectoryObject` (v8/v9)—same arity via a
local noinline sink (v10) is **not** enough. Remains a **codegen / layout
heisenbug bandage**, not a semantic fix. Do not ship dead-`fprintf` as the
product fix.

Bisect can stop here for the “what code shape works” question; next work
should target real root cause (directory/HID / NGS lifecycle) or session
PID cleanup.

### Interpretation after v3/v10

v1–v3 / v5–v7 / **v10** residual; **v8/v9** (one dead full-arity enter
`fprintf`, long or short format) and v4 / full QDO (TRACE off) clean.
**Libc `fprintf` codegen matters**; a local 6-arg noinline sink with the
same argument pattern does not. Minimal effective bandage: helper +
`ctx_in` + a never-taken `fprintf(stderr, "%p %u %u %lu %lu %ld\\n", …)`
at `NtQueryDirectoryObject` entry.

## Next bisect after v4

- **v5**: same `if (diag)` call-site pattern, but `cyder_qdo_sink` (noinline)
  instead of `fprintf` — tests call-site/codegen without format strings / libc.
- **v6**: keep the QDO format string literals (+ helper), no `if (diag)` bodies —
  tests string-data / size alone.

Play **v5 first**.

## Orphan Wine PE without wineserver

After clean NGS exit (v8), Activity Monitor can still show
`services.exe` / `plugplay.exe` / `rpcss.exe` with **no** `wineserver` and
**no** grap. Host `ps`/`pgrep` is enough; **`wmic` is not useful** here
(no wineserver to serve the query). Kill those PIDs before the next A/B.

## Root-cause probes

### A — timing (`usleep(100)` in stock `NtQueryDirectoryObject`)

Artifact: `logs/ntdll-timing-probe-usleep100.so` (no QDO; `-O2`).

**Result (2026-08-07):** Still **NGS residual**. Host power ~10–11W;
busy-loop power felt lower (~6–7W vs prior ~12–13W / classic ~17W),
consistent with rate-limiting each QDO via `usleep`, **not** with a clean
NGS exit.

**Interpretation:** A fixed 100µs delay does **not** reproduce the clean
exit of dead-`fprintf` (v8/v9). Pure “any slowdown lets NGS finish” is
weakened; residual path still taken, just slower. Layout/codegen races
remain possible, but simple sleep ≠ heisenbug bandage.

### B — compiler (`-O0` vs `-O2`, same stock source)

| Build | Artifact | Result |
|-------|----------|--------|
| stock `-O2` (same-tree NO-qdo) | `logs/ntdll-same-tree-no-qdo.so` (~713544) | Residual ~17W (established) |
| stock `-O0` (manual sync.o) | `logs/ntdll-compiler-probe-O0.so` (~724936) | **Clean ~6W** (2026-08-07) |

Note: `make CFLAGS=…` does **not** override Wine’s embedded `-O2` in
this tree; `-O0` required compiling `dlls/ntdll/unix/sync.o` by hand then
relinking `ntdll.so`.

**Interpretation:** Optimization level alone flips residual → clean on
**identical source**. Together with dead multi-arg `fprintf` (v8/v9)
working and `usleep(100)` (probe A) **not** cleaning, the heisenbug is
strongly tied to **`-O2` codegen / layout of `NtQueryDirectoryObject`**
(and/or its Rosetta translation), not to a deliberate semantic fix and
not to a simple fixed delay.

Shipping `-O0` for all of ntdll is not a product answer; use it as
evidence while hunting the real NGS/directory condition, or consider a
narrow `__attribute__((optnone))` on that one function as a *temporary*
engineering probe—not an upstream fix.
## Parallel tracks (optnone bandage + residual GDE capture)

### Track 1 — `__attribute__((optnone))` on `NtQueryDirectoryObject`

- Patch: `patches/cyder-ntdll-qdo-optnone-NtQueryDirectoryObject.patch` (**default CX26**)
- Artifact: `logs/ntdll-optnone-NtQueryDirectoryObject.so` (built with tree `-O2`,
  function marked optnone)
- **Result: Clean ~6–7W, no NGS residual** (2026-08-07). Narrow no-opt bandage
  confirmed (still not a semantic fix).
- **Shipped into apply list 2026-08-08** (replaces QDO TRACE in `build-wine.sh`).

### Track 2 — wineserver `get_directory_entries` trace (does not change ntdll)

- Patch: `patches/experimental/cyder-wineserver-gde-trace.patch` (in tree)
- Artifact: `logs/wineserver-gde-trace`
- Pair with **stock `-O2` ntdll** (same-tree NO-qdo) + `CYDER_GDE_TRACE=1`
- Logs to stderr and `$WINEPREFIX/cyder-wineserver-diag.log` (`cyder GDE …`)
- Capture on residual without ntdll heisenbug bandage

See also `logs/residual-capture-howto.txt`.

#### Residual capture result (2026-08-07 ~23:29)

Capture dir: `logs/residual-gde-capture-20260807-232908/`  
Live: grap `7864` (~56% CPU) + wineserver `7679` (~47% CPU); Classic gone; power ~12W.

| Field | Residual steady-state (last 500 GDE headers) |
|-------|-----------------------------------------------|
| handle | **always `0x168`** |
| index | **always `0`** |
| max | **always `1`** |
| count | **always `1`** |
| err | **always `00000000`** |
| entry | **one** `SymbolicLink` |

**Entry name (100% of residual hits on `0x168` / also `0x664`):**

```
HID#VID_845E&PID_0001#0&0000&0&0&0#{378de44c-56ef-11d1-bc8c-00a0c91405dd}
```

GUID `{378de44c-…}` = `GUID_DEVINTERFACE_HID`. `VID_845E` is Wine’s virtual HID
vendor id (not a physical device).

Earlier in the same session, handles `0x3d4` / `0x110` walked a normal
multi-entry `\\??`-style listing (NetDev GUIDs, `PIPE`, volumes, `C:`, …) with
advancing indices. Residual phase never advances: NGS ↔ wineserver hammer
**the same single HID symlink from index 0 forever**.

`sample` confirms wineserver hot path = `req_get_directory_entries`; grap hot
path = `NtQueryDirectoryObject` → `wine_server_call`.

**Interpretation:** livelock payload is HID-device-interface directory
enumeration stuck at restart-from-zero (not an empty directory, not a
STATUS_BUFFER_TOO_SMALL storm). Still compatible with the ntdll `-O2`
heisenbug (Context / restart index not advancing on the PE side) *or* NGS
intentionally re-querying index 0 when it dislikes the entry.

**HID identity:** `VID_845E` / `PID_0001` is Wine’s virtual mouse from
`dlls/winebus.sys/unixlib.c` (`mouse_device_desc`), not a physical device.
`PID_0002` is the virtual keyboard. Interface GUID `{378de44c-…}` =
`GUID_DEVINTERFACE_HID`.

### Track 3 — Context in/out A/B (in progress)

| Build | Artifact | How to read |
|-------|----------|-------------|
| Residual observe | `logs/ntdll-qdo-context-ring.so` | `CYDER_QDO_RING=1`; auto-flush every 512 records to `$CYDER_QDO_RING_PATH`. **Never** `SIGUSR1` (Wine uses it for thread suspend — first ring build stole it and hung login). |
| Clean observe | `logs/ntdll-optnone-with-qdo-trace.so` | `CYDER_QDO_TRACE=1`; stderr `cyder QDO enter/leave` with `restart` / `ctx_in` / `ctx_out`. |

Distinguish:

- Case A: `restart=1` every enter → NGS RestartScan loop
- Case B: `restart=0`, `ctx_in=0` every enter while leave writes `ctx_out=1` → caller drops Context
- Case C: `ctx_in` stuck / `ctx_out` not advancing under `-O2` only → ntdll marshalling heisenbug

Patch: `patches/experimental/cyder-ntdll-qdo-context-ring.patch`

#### Track 3 clean-path Context (ring+flush bandage, 2026-08-08)

- `logs/ntdll-qdo-context-ring.so` with periodic `write` flush → **Clean ~6W, no residual**
  (I/O / codegen bandage again; not usable for residual Context capture).
- Ring dump `logs/cyder-qdo-ring-residual-20260808-002011.txt` (seq=5120):
  - `restart=1` almost never (2 / 2046 enters)
  - On leave-game handle **`0x168`**, Context **advances** (`ctx_in` 0→1→2…, `ctx_out=ctx_in+1`)
  - Contrasts residual GDE (same `0x168`, forever `index=0` on Wine HID mouse symlink)

**Conclusion so far:** when the heisenbug is “off”, NGS is **not** a RestartScan storm;
it walks Context normally. Residual livelock is specifically stuck `index=0` on that
HID directory handle under stock `-O2` without bandage.

#### Track 3 memonly residual (2026-08-08)

- `logs/ntdll-qdo-context-ring-memonly.so` + GDE → **Residual** (~55% grap / ~47% WS).
- GDE: handle `0x124`, forever `index=0`, Wine HID mouse
  `HID#VID_845E&PID_0001…#{378de44c-…}` (same payload as earlier `0x168`).
- **Ring stores DCE’d**: `_cyder_qdo_ring_push` → only `lock incl seq; ret` (array never
  read). Cannot dump Context from that build.
- Capture: `logs/residual-memonly-20260808-002534/`

#### Track 3 stuck one-shot (ready)

- Artifact: `logs/ntdll-qdo-stuck-oneshot.so`
- `CYDER_QDO_STUCK=1` — after 50000 consecutive `index==0` enters, **one** stderr line
  with `restart`/`ctx_in` (`cyder QDO STUCK …`). Init-only getenv (v2).


#### Track 3 stuck one-shot result (2026-08-08)

- `logs/ntdll-qdo-stuck-oneshot.so` + `CYDER_QDO_STUCK=1` → **Clean ~6–7W, no residual**
- No `cyder QDO STUCK` line (livelock never formed → counter kept resetting).
- Same class as v8/fprintf/flush/optnone: **any meaningful QDO codegen change
  bandages**; cannot observe residual-side `restart`/`ctx_in` this way.

### Track 3 verdict (Context A/B)

| Evidence | Result |
|----------|--------|
| Residual GDE (stock `-O2` / memonly) | Server `index=0` forever on Wine HID mouse symlink |
| Clean ring+flush Context dump | `restart≈0`, Context **advances** on same handle class |
| All ntdll observe builds that touch QDO enough | Prevent residual (heisenbug) |

**Cannot** empirically split Case A (`restart=1`) vs B (`ctx_in=0`) on a true
residual process without an observe method that preserves stock `-O2` QDO
codegen (lldb attach failed here; memonly ring stores were DCE’d).

**Working model:** livelock payload is enumeration of Wine virtual HID
(`VID_845E` mouse, `GUID_DEVINTERFACE_HID`). When QDO is “perturbed”
(optnone/`-O0`/fprintf/I/O), NGS walks Context and exits; stock `-O2` stays
pinned at index 0.

### Recommended real next steps (pick one)

1. **Product session cleanup** — kill grap/wineserver when Classic session ends
   (last-resort but reliable UX).
2. **Narrow engine bandage** — ship `__attribute__((optnone))` on
   `NtQueryDirectoryObject` only (already proven clean). **Done 2026-08-08** —
   default CX26 patch `cyder-ntdll-qdo-optnone-NtQueryDirectoryObject.patch`
   (replaces QDO TRACE in `build-wine.sh`). Installed into
   `install/wine-cx26-x86_64` + maple debug runtime; marker `cyder QDO optnone`.
3. **Semantic HID / directory fidelity** — compare this `\??` / device-interface
   listing to Windows; experiment hiding or reshaping the `VID_845E` HID
   symlink NGS sticks on (root-cause track).
