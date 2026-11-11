# macOS game soak measurements

Run a task-owned engine and independent prefixes. Set `CYDER_GL_PROFILE=1` and
`CYDER_SURFACE_PROFILE=1` before launching games. Preserve renderer, game mode,
DPI and window size across a renderer A/B/A; restart every client at each change.
`renderer=gdi` and `renderer=no3d` select the same WineD3D no3d implementation.
The game's `3Ddevice:0` is a separate setting.

```sh
python3 tools/game-soak/monitor.py --engine /absolute/test-engine \
  --output /private/tmp/phase.jsonl --seconds 1800 --phase triple-gl
python3 tools/game-soak/summarize.py /private/tmp/phase.jsonl \
  --phase-metadata /private/tmp/phase.json
```

The read-only sampler needs macOS, libproc and the CLT SDK `sys/resource.h`.
It records task-engine processes once a second: PID, role wine/wineserver, CPU
(100% = one core), RSS and physical footprint. CPU rusage Mach ticks are converted
using the machine's actual timebase. Footprint includes memory charges that RSS
alone does not show; the two must not be added together. CPU samples use deltas
and reject a reused PID's first interval. The first CPU sample has no delta.

IOAccelerator utilization is sampled every five samples. It is **whole-device
GPU utilization**, including WindowServer and other apps, never per-game GPU time.
The summary counts each GPU observation once, ignoring cached repeat samples.
Close other games, avoid builds/heavy diagnostics during a measured phase and
record desktop captures or other measurement disturbances. No metrics collector
reads accounts, game memory, chat messages or command-line arguments.

Optional phase metadata, saved alongside the private logs, has this shape:

```json
{
  "pids": [12345, 12346, 12347],
  "profile_start_offsets": {"game-1.log": 1000},
  "profile_end_offsets": {"game-1.log": 9000}
}
```

Offsets are byte positions observed at the phase boundaries. Without an end
offset, the current end of that log is used. The first GDI report of every
surface lifetime is discarded because it may straddle the phase start. The
last incomplete five-second window can remain unreported until destruction.
Keep normal-exit tails separate from steady-state measurements.

GDI summaries stay separate by PID **and surface dimensions**. A small cursor
or auxiliary surface can remain idle for seconds; mixing it with the main game
surface creates fictitious game stalls. Identify the main dimensions from the
log and verify them against the actual game window. Intervals are histogrammed
in 1 ms bins; reported percentiles are exclusive upper bounds. The >=2000 ms
overflow has no finite percentile bound. Long-interval counts include actual
loads, map transitions and window pauses unless the protocol excludes them.

GDI submission wall time covers image creation and submission to winemac. It
excludes earlier DirectDraw/WineD3D Blt work, asynchronous display/GPU completion
and the game's logical frame boundary. Neither these intervals nor native GL
callback counts alone are FPS or total Blt cost. A zero native flush count is
meaningful only after a real GL control verifies that instrumentation works.

Keep raw logs/screenshots local: other game messages can contain account names,
character names and network identifiers. Publish only reviewed aggregates and
explicit scope/limitations. A soak with intermittent walking/UI/idle is not a
continuous combat benchmark. Report connection loss, PID disappearance, freezes,
visual defects and crash logs as well as the surviving sample duration.
