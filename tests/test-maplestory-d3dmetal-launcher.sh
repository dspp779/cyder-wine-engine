#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/assert.sh"
LAUNCHER="$ROOT/scripts/run-maplestory-cx26-d3dmetal.sh"

bash -n "$LAUNCHER"
source_text="$(cat "$LAUNCHER")"
assert_contains "$source_text" 'CYDER_GRAPHICS_BACKEND=' \
  "MapleStory launcher must set CYDER_GRAPHICS_BACKEND"
assert_contains "$source_text" '--graphics-backend' \
  "MapleStory launcher must accept --graphics-backend"
assert_contains "$source_text" 'ensure_dxmt_winemetal_prefix' \
  "MapleStory launcher must provision DXMT winemetal.dll into the prefix"
assert_contains "$source_text" 'CYDER_GPTK_ROOT' \
  "MapleStory launcher must pass the host GPTK root for D3DMetal"
assert_contains "$source_text" 'CYDER_COMPATDB_PATH' \
  "MapleStory launcher must pass the app-supplied CompatDB database"
assert_contains "$source_text" 'RAW_AUDIO_PARSE=1' \
  "MapleStory launcher must preserve the raw audio contract"
assert_contains "$source_text" 'clean_prefix_session' \
  "MapleStory launcher must clean the exact prefix before launch"
assert_contains "$source_text" 'CYDER_MAPLESTORY_IO_RING_ARM_FILE' \
  "MapleStory launcher must pass the scoped I/O ring control file"
assert_contains "$source_text" 'CYDER_MAPLESTORY_IO_SUMMARY' \
  "MapleStory launcher must pass the compact I/O summary mode"
assert_contains "$source_text" 'CYDER_MAPLESTORY_IO_TIMELINE' \
  "MapleStory launcher must pass the I/O timeline mode"
assert_contains "$source_text" 'CYDER_MAPLESTORY_IO_CACHE_STATS' \
  "MapleStory launcher must pass the arm-scoped cache statistics mode"
assert_contains "$source_text" 'CYDER_MAPLESTORY_IO_SECTION_MAP' \
  "MapleStory launcher must pass the section-map diagnostic mode"
assert_contains "$source_text" 'CYDER_MAPLESTORY_FILE_CACHE_MMAP' \
  "MapleStory launcher must pass the experimental mmap cache mode"
assert_contains "$source_text" 'CYDER_MAPLESTORY_FILE_CACHE_PREWARM_IN_PROCESS' \
  "MapleStory launcher must pass the in-process cache prewarm mode"
assert_contains "$source_text" 'CYDER_MAPLESTORY_FILE_CACHE_PREWARM_MAX_BYTES' \
  "MapleStory launcher must pass the in-process prewarm byte budget"
assert_contains "$source_text" 'CYDER_MAPLESTORY_FILE_CACHE_FAST_HIT' \
  "MapleStory launcher must pass the Stage 1 TLS／unlocked-fill fast-hit mode"
assert_contains "$source_text" 'CYDER_MAPLESTORY_IO_CACHE_TIMING' \
  "MapleStory launcher must pass the Stage 0 cache timing mode"
assert_contains "$source_text" 'CYDER_MAPLESTORY_PREWARM' \
  "MapleStory launcher must expose the focused prewarm experiment"
assert_contains "$source_text" 'maplestory-prewarm.sh' \
  "MapleStory launcher must invoke the prewarm helper"
[[ -x "$ROOT/scripts/maplestory-prewarm.sh" ]] || {
  echo "ASSERT failed: missing executable MapleStory prewarm helper" >&2
  exit 1
}
if ! bash -n "$ROOT/scripts/maplestory-prewarm.sh"; then
  echo "ASSERT failed: MapleStory prewarm helper has shell syntax errors" >&2
  exit 1
fi
assert_contains "$source_text" 'wineserver" -k' \
  "MapleStory launcher must stop stale Wine processes before launch"
if [[ "$source_text" == *"copy-oem-moltenvk.sh"* ]]; then
  echo "ASSERT failed: launcher must not depend on copy-oem-moltenvk.sh" >&2
  exit 1
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/cyder-maplestory-d3dmetal.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/wine/bin" "$tmp/wine/lib/wine/x86_64-unix" \
  "$tmp/wine/lib/dxmt/x86_64-windows" "$tmp/wine/lib/dxmt/i386-windows" \
  "$tmp/wine/lib/dxmt/x86_64-unix" \
  "$tmp/gptk/wine/x86_64-windows" "$tmp/gptk/external" \
  "$tmp/media/lib/gstreamer-1.0" "$tmp/media/libexec/gstreamer-1.0" \
  "$tmp/prefix/drive_c/windows/system32" "$tmp/prefix/drive_c/windows/syswow64"
printf '#!/bin/sh\nexit 0\n' >"$tmp/wine/bin/wine"
printf '#!/bin/sh\nexit 0\n' >"$tmp/wine/bin/wineserver"
chmod +x "$tmp/wine/bin/wine"
chmod +x "$tmp/wine/bin/wineserver"
touch "$tmp/wine/lib/wine/x86_64-unix/cxcompatdb.so" \
  "$tmp/compatdb.cdb" \
  "$tmp/gptk/wine/x86_64-windows/d3d11.dll" \
  "$tmp/gptk/wine/x86_64-windows/dxgi.dll" \
  "$tmp/gptk/external/libd3dshared.dylib" "$tmp/MapleStory.exe" \
  "$tmp/wine/lib/dxmt/x86_64-windows/d3d11.dll" \
  "$tmp/wine/lib/dxmt/x86_64-windows/dxgi.dll" \
  "$tmp/wine/lib/dxmt/x86_64-windows/winemetal.dll" \
  "$tmp/wine/lib/dxmt/i386-windows/winemetal.dll" \
  "$tmp/wine/lib/dxmt/x86_64-unix/winemetal.so"

output="$(bash "$LAUNCHER" \
  --launch-exe "$tmp/MapleStory.exe" \
  --wine-install "$tmp/wine" \
  --gptk-root "$tmp/gptk" \
  --compatdb "$tmp/compatdb.cdb" \
  --media-install "$tmp/media" \
  --no-otp --dry-run 2>&1)"
assert_contains "$output" 'CYDER_GRAPHICS_BACKEND=d3dmetal' \
  "dry-run should default to the D3DMetal backend"
assert_contains "$output" 'GPTK_ROOT=' \
  "dry-run should show the GPTK root"
assert_contains "$output" 'GST_PLUGIN_DIR=' \
  "dry-run should show the selected GStreamer plugin directory"
if [[ "$output" == *"MoltenVK"* || "$output" == *"moltenvk"* ]]; then
  echo "ASSERT failed: D3DMetal dry-run must not mention MoltenVK" >&2
  exit 1
fi

dxmt_output="$(bash "$LAUNCHER" \
  --launch-exe "$tmp/MapleStory.exe" \
  --wine-install "$tmp/wine" \
  --wineprefix "$tmp/prefix" \
  --graphics-backend dxmt \
  --compatdb "$tmp/compatdb.cdb" \
  --media-install "$tmp/media" \
  --no-otp --dry-run 2>&1)"
assert_contains "$dxmt_output" 'CYDER_GRAPHICS_BACKEND=dxmt' \
  "dry-run should show the DXMT backend when requested"
assert_contains "$dxmt_output" 'ensure_dxmt_winemetal_prefix' \
  "DXMT dry-run should plan winemetal prefix provision"

mkdir -p "$tmp/wine/lib/wine/gstreamer-1.0"
bundled_output="$(bash "$LAUNCHER" \
  --launch-exe "$tmp/MapleStory.exe" \
  --wine-install "$tmp/wine" \
  --gptk-root "$tmp/gptk" \
  --compatdb "$tmp/compatdb.cdb" \
  --no-otp --dry-run 2>&1)"
assert_contains "$bundled_output" 'MEDIA_SOURCE=bundled' \
  "launcher should prefer the engine-internal GStreamer stack"
assert_contains "$bundled_output" "$tmp/wine/lib/wine/gstreamer-1.0" \
  "launcher should select the internal plugin directory"

echo "PASS test-maplestory-d3dmetal-launcher"
