#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/assert.sh"

PATCH_FILE="$ROOT/patches/maplestory-cx26-file-cache-adaptive.patch"
CAPACITY_PATCH_FILE="$ROOT/patches/maplestory-cx26-file-cache-capacity.patch"
BUILD_SCRIPT="$(<"$ROOT/scripts/build-wine.sh")"

[[ -f "$PATCH_FILE" ]] || {
  echo "ASSERT failed: missing adaptive MapleStory file-cache patch" >&2
  exit 1
}
assert_contains "$BUILD_SCRIPT" "maplestory-cx26-file-cache-adaptive.patch" \
  "MapleStory builds should apply the adaptive file-cache patch"
assert_contains "$(<"$PATCH_FILE")" "CYDER_MAPLESTORY_FILE_CACHE_MIN_WINDOW" \
  "adaptive patch should contain its idempotence marker"
[[ -f "$CAPACITY_PATCH_FILE" ]] || {
  echo "ASSERT failed: missing production cache-capacity patch" >&2
  exit 1
}
assert_contains "$BUILD_SCRIPT" "maplestory-cx26-file-cache-capacity.patch" \
  "MapleStory builds should apply the production cache-capacity patch"
assert_contains "$(<"$CAPACITY_PATCH_FILE")" "CYDER_MAPLESTORY_FILE_CACHE_SLOTS 512" \
  "production cache-capacity patch should select 512 slots"
for diagnostic_patch in \
  maplestory-cx26-io-ring.patch \
  maplestory-cx26-io-ring-arm.patch \
  maplestory-cx26-io-summary.patch \
  maplestory-cx26-io-timeline.patch \
  maplestory-cx26-io-cache-stats.patch \
  maplestory-cx26-section-map-summary.patch \
  maplestory-cx26-file-cache-prewarm.patch; do
  if [[ "$BUILD_SCRIPT" == *"$diagnostic_patch"* ]]; then
    echo "ASSERT failed: $diagnostic_patch must remain outside the production patch stack" >&2
    exit 1
  fi
done

archive="$ROOT/tools/archives/crossover-sources-26.3.0.tar.gz"
if [[ -f "$archive" ]]; then
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/cyder-maplestory-file-cache.XXXXXX")"
  trap 'rm -rf "$tmp"' EXIT
  tar -xzf "$archive" -C "$tmp"
  for prerequisite in \
    maplestory-cx26-file-cache-adaptive.patch \
    maplestory-cx26-file-cache-capacity.patch; do
    patch --forward --batch -s -p1 -d "$tmp/sources/wine" < "$ROOT/patches/$prerequisite"
  done
  echo "PASS: MapleStory production file-cache patches apply to CX26.3.0"
else
  echo "SKIP: CX26.3.0 source archive is not available"
fi

echo "PASS test-maplestory-file-cache-patch"
