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
  # Later patches overlap A6. Unwind them only in a disposable copy, then
  # reverse/reapply A6 and compare the resulting files with the live source.
  TMP="$(mktemp -d "${TMPDIR:-/tmp}/cyder-a6-roundtrip.XXXXXX")"
  trap 'rm -rf "$TMP"' EXIT
  mkdir -p "$TMP/dlls"
  cp -R "$SRC/dlls/winemac.drv" "$TMP/dlls/"
  FRONT_BUFFER="$ROOT/patches/cyder-winemac-gl-front-buffer-present.patch"
  NO_SWAP="$ROOT/patches/obsolete/cyder-winemac-gl-flush-no-buffer-swap.patch"
  has_no_swap=0
  if grep -Fq 'GL_FLUSH_PRESENT is not a buffer-swap request' "$TMP/dlls/winemac.drv/opengl.c"; then
    has_no_swap=1
    patch --reverse --batch -s -d "$TMP" -p1 <"$NO_SWAP"
  fi
  has_front_buffer=0
  if grep -Fq 'if (flags & GL_FLUSH_PRESENT)' "$TMP/dlls/winemac.drv/opengl.c"; then
    has_front_buffer=1
    patch --reverse --batch -s -d "$TMP" -p1 <"$FRONT_BUFFER"
  fi
  patch --reverse --batch -s -d "$TMP" -p1 <"$PATCH"
  patch --forward --batch -s -d "$TMP" -p1 <"$PATCH"
  if [[ "$has_front_buffer" -eq 1 ]]; then
    patch --forward --batch -s -d "$TMP" -p1 <"$FRONT_BUFFER"
  fi
  if [[ "$has_no_swap" -eq 1 ]]; then
    patch --forward --batch -s -d "$TMP" -p1 <"$NO_SWAP"
  fi
  for file in $(sed -n 's|^+++ b/||p' "$PATCH" "$FRONT_BUFFER" | sort -u); do
    cmp "$TMP/$file" "$SRC/$file"
  done
  echo "PASS A6 patch round-trip on copied CX26 source (including later GL presentation patch)"
else
  echo "SKIP A6 live-source round-trip: $SRC is absent"
fi

echo "PASS test-winemac-a6-patch"
