# grap-core `NtQueryDirectoryObject` diagnosis (`CYDER_QDO_TRACE`)

Temporary CX26 ntdll instrumentation for MapleStory Classic leave-game
`grap-core64.aes` residual / high-CPU loops.

Background analysis (Cyder app repo): `grap-core64-residual-process-analysis.md`.

A/B matrix and same-tree causal result (QDO patch prevents residual even
with TRACE off): [`grap-core-qdo-ab-findings.md`](grap-core-qdo-ab-findings.md).

## Goal

Distinguish:

| Case | Evidence in stderr |
|------|--------------------|
| A. Caller always `RestartScan=TRUE` | `restart=1`, `ctx_in` ignored, server index always 0 |
| B. Caller resets Context each time | `restart=0`, `ctx_in=0` every enter |
| C. Wine Context not advancing | `restart=0`, `ctx_in` stuck, `ctx_out` not `ctx_in+used` |
| Outer condition | Context advances / scan completes, but calls keep coming |

Do **not** open full `WINEDEBUG=+server` for this (GB-scale). Use this patch instead.

## Patch

- File: `patches/cyder-ntdll-query-directory-object-trace.patch` (also under
  `patches/experimental/`)
- **Not** in the default CX26 apply list anymore — superseded for shipping by
  `patches/cyder-ntdll-qdo-optnone-NtQueryDirectoryObject.patch` (bandage).
- Host module: `dlls/ntdll/unix/sync.c` → `ntdll.so`
- Marker: `cyder QDO`
- Default: **off**. Set `CYDER_QDO_TRACE=1` (any non-empty value enables).
- Rate limit: first 64 calls, then every 10000th (per wine process).

Apply manually when diagnosing Context (`restart` / `ctx_in` / `ctx_out`), or
use the findings doc A/B notes. Prefer optnone for leave-game residual mitigation.

## Rebuild (incremental)

```sh
cd /path/to/cyder-wine-engine
source scripts/env-x86_64.sh
# Ensure patch is applied (idempotent):
bash scripts/build-wine.sh --cx 26 --configure-only --with-vulkan --vulkan-source crossover
# Or, if sources already patched, rebuild host ntdll only:
cd build/cx26/sources/wine/build64
make -j"$(sysctl -n hw.ncpu)" dlls/ntdll/ntdll.so \
  $CYDER_MACOSX_VERSION_MIN_FLAG
make install
```

Confirm the installed `ntdll.so` is the one your bottle uses (engine prefix /
Cyder runtime), then kill any lingering wineserver for that prefix before the
repro.

## Leave-game repro

1. Use the CX26 engine build that includes this patch.
2. Launch Classic with the env var on the Wine client:

   ```sh
   export CYDER_QDO_TRACE=1
   # then your usual wine / Cyder launch of Maplestory_Classic.exe
   ```

   If launching via Cyder, inject `CYDER_QDO_TRACE=1` into the Wine environment
   (same place other `WINE*` / `CYDER_*` vars are set).

3. Play briefly, then exit from inside the game (do not Dock-force-quit NGS yet).
4. When the shell returns / main EXE is gone but CPU stays high, capture stderr
   (or the Cyder wine log that includes stderr) and grep:

   ```sh
   rg 'cyder QDO' path/to/log | head -80
   ```

5. Optional: confirm residual with `wmic process get Name,ProcessId` under Wine,
   or Activity Monitor (`grap-core` / wine / wineserver).

6. After collecting ~dozens of QDO lines, Dock-quit NGS or `wineserver -k` to
   stop the loop.

## How to read one pair

```text
cyder QDO enter h=0x… single=1 restart=0 ctx_in=0 size=… n=1
cyder QDO leave ret=00000000 ctx_out=1 used=1 ret_size=… n=1
```

- `single=1` ↔ `ReturnSingleEntry`
- `restart` ↔ `RestartScan`
- `ctx_in` / `ctx_out` ↔ Context before/after the call
- `ret=` is NTSTATUS (`00000000` = success)

If many consecutive enters show `restart=1` or `ctx_in=0` while `ctx_out`
correctly becomes `1`, Wine’s Context update is likely fine; look at GRAP’s
outer loop / HID directory contents next—not a blind `index++` patch.
