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
  # Later front-buffer hunks overlap A6. Verify in reverse dependency order
  # on a disposable copy; never unpatch the developer's source tree.
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  mkdir -p "$TMP/dlls/winemac.drv"
  for name in cocoa_opengl.h macdrv_cocoa.h cocoa_opengl.m cocoa_window.m window.c opengl.c; do
    cp "$SRC/dlls/winemac.drv/$name" "$TMP/dlls/winemac.drv/$name"
  done
  FRONT="$ROOT/patches/cyder-winemac-gl-front-buffer-present.patch"
  if grep -Fq 'if (flags & GL_FLUSH_PRESENT)' "$TMP/dlls/winemac.drv/opengl.c"; then
    patch --reverse --forward --batch --fuzz=0 -s -d "$TMP" -p1 <"$FRONT"
  fi
  patch --reverse --forward --batch --dry-run -s -d "$TMP" -p1 <"$PATCH"
  echo "PASS A6 patch round-trip on live CX26 source"
else
  echo "SKIP A6 live-source round-trip: $SRC is absent"
fi

echo "PASS test-winemac-a6-patch"
