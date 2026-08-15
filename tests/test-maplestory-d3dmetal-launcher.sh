#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/assert.sh"
LAUNCHER="$ROOT/scripts/run-maplestory-cx26-d3dmetal.sh"

bash -n "$LAUNCHER"
source_text="$(cat "$LAUNCHER")"
assert_contains "$source_text" 'CYDER_GRAPHICS_BACKEND=d3dmetal' \
  "MapleStory launcher must force the D3DMetal backend"
assert_contains "$source_text" 'CYDER_GPTK_ROOT' \
  "MapleStory launcher must pass the host GPTK root"
assert_contains "$source_text" 'CYDER_COMPATDB_PATH' \
  "MapleStory launcher must pass the app-supplied CompatDB database"
assert_contains "$source_text" 'RAW_AUDIO_PARSE=1' \
  "MapleStory launcher must preserve the raw audio contract"
assert_contains "$source_text" 'clean_prefix_session' \
  "MapleStory launcher must clean the exact prefix before launch"
assert_contains "$source_text" 'wineserver" -k' \
  "MapleStory launcher must stop stale Wine processes before launch"
if [[ "$source_text" == *"copy-oem-moltenvk.sh"* || "$source_text" == *"libMoltenVK.dylib"* ]]; then
  echo "ASSERT failed: D3DMetal launcher must not depend on MoltenVK" >&2
  exit 1
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/cyder-maplestory-d3dmetal.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/wine/bin" "$tmp/wine/lib/wine/x86_64-unix" \
  "$tmp/gptk/wine/x86_64-windows" "$tmp/gptk/external" "$tmp/media"
printf '#!/bin/sh\nexit 0\n' >"$tmp/wine/bin/wine"
printf '#!/bin/sh\nexit 0\n' >"$tmp/wine/bin/wineserver"
chmod +x "$tmp/wine/bin/wine"
chmod +x "$tmp/wine/bin/wineserver"
touch "$tmp/wine/lib/wine/x86_64-unix/cxcompatdb.so" \
  "$tmp/compatdb.cdb" \
  "$tmp/gptk/wine/x86_64-windows/d3d11.dll" \
  "$tmp/gptk/wine/x86_64-windows/dxgi.dll" \
  "$tmp/gptk/external/libd3dshared.dylib" "$tmp/MapleStory.exe"

output="$(bash "$LAUNCHER" \
  --launch-exe "$tmp/MapleStory.exe" \
  --wine-install "$tmp/wine" \
  --gptk-root "$tmp/gptk" \
  --compatdb "$tmp/compatdb.cdb" \
  --media-install "$tmp/media" \
  --no-otp --dry-run 2>&1)"
assert_contains "$output" 'CYDER_GRAPHICS_BACKEND=d3dmetal' \
  "dry-run should show the forced D3DMetal backend"
assert_contains "$output" 'GPTK_ROOT=' \
  "dry-run should show the GPTK root"
if [[ "$output" == *"MoltenVK"* || "$output" == *"moltenvk"* ]]; then
  echo "ASSERT failed: D3DMetal dry-run must not mention MoltenVK" >&2
  exit 1
fi

echo "PASS test-maplestory-d3dmetal-launcher"
