#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/assert.sh"

PATCH="$ROOT/patches/a6-final-same-view-backing-sync.patch"
SRC="$ROOT/build/cx26/sources/wine"

assert test -f "$PATCH"
assert_contains "$(cat "$PATCH")" "macdrv_finalize_window_backing_sync" \
  "A6 patch should carry the final backing-sync marker"
assert_contains "$(cat "$ROOT/scripts/build-wine.sh")" \
  'apply_cyder_patch "$OGOM/patches/a6-final-same-view-backing-sync.patch"' \
  "CX26 build should apply A6"

if [[ -d "$SRC/dlls/winemac.drv" ]]; then
  patch --reverse --batch --dry-run -s -d "$SRC" -p1 <"$PATCH"
  echo "PASS A6 patch round-trip on live CX26 source"
else
  echo "SKIP A6 live-source round-trip: $SRC is absent"
fi

echo "PASS test-winemac-a6-patch"
