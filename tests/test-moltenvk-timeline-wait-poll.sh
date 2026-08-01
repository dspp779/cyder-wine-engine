#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATCH="$ROOT/patches/cyder-moltenvk-timeline-wait-poll.patch"
SRC_FILE="$ROOT/build/cx26/sources/moltenvk/MoltenVK/MoltenVK/GPUObjects/MVKSync.mm"

[[ -f "$PATCH" ]] || {
  echo "FAIL missing $PATCH" >&2
  exit 1
}

rg -Fq 'Cyder: each -[MTLSharedEvent notifyListener' "$PATCH"
rg -Fq 'getCounterValue()' "$PATCH"
rg -Fq 'notifyListener' "$PATCH"

# Round-trip on a stock excerpt reconstructed by reverse-applying to a copy of
# the live tree file when the Cyder marker is already present.
if [[ -f "$SRC_FILE" ]] && rg -Fq 'Cyder: each -[MTLSharedEvent notifyListener' "$SRC_FILE"; then
  TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cyder-mvk-wait-poll.XXXXXX")"
  trap 'rm -rf "$TMP_DIR"' EXIT
  mkdir -p "$TMP_DIR/MoltenVK/MoltenVK/GPUObjects"
  cp "$SRC_FILE" "$TMP_DIR/MoltenVK/MoltenVK/GPUObjects/MVKSync.mm"
  patch --reverse --batch -s -p1 -d "$TMP_DIR" < "$PATCH"
  if rg -Fq 'Cyder: each -[MTLSharedEvent notifyListener' \
    "$TMP_DIR/MoltenVK/MoltenVK/GPUObjects/MVKSync.mm"; then
    echo "FAIL reverse patch left Cyder marker" >&2
    exit 1
  fi
  rg -Fq 'registerWait(&fenceSitter' "$TMP_DIR/MoltenVK/MoltenVK/GPUObjects/MVKSync.mm"
  patch --forward --batch -s -p1 -d "$TMP_DIR" < "$PATCH"
  rg -Fq 'Cyder: each -[MTLSharedEvent notifyListener' \
    "$TMP_DIR/MoltenVK/MoltenVK/GPUObjects/MVKSync.mm"
  echo "PASS moltenvk timeline-wait-poll patch round-trip on live CX source"
  exit 0
fi

# Fallback: dry-run only against the patch contents.
echo "SKIP live round-trip (no patched CX MVKSync.mm); patch content checks OK"
echo "PASS moltenvk timeline-wait-poll patch content"
