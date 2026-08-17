#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/assert.sh"

PATCH_FILE="$ROOT/patches/maplestory-cx26-io-ring.patch"
ARM_PATCH_FILE="$ROOT/patches/maplestory-cx26-io-ring-arm.patch"
SUMMARY_PATCH_FILE="$ROOT/patches/maplestory-cx26-io-summary.patch"
TIMELINE_PATCH_FILE="$ROOT/patches/maplestory-cx26-io-timeline.patch"
CACHE_STATS_PATCH_FILE="$ROOT/patches/maplestory-cx26-io-cache-stats.patch"
SECTION_MAP_PATCH_FILE="$ROOT/patches/maplestory-cx26-section-map-summary.patch"
BUILD_SCRIPT="$(<"$ROOT/scripts/build-wine.sh")"

[[ -f "$PATCH_FILE" ]] || {
  echo "ASSERT failed: missing MapleStory I/O ring patch" >&2
  exit 1
}
for diagnostic_patch in \
  maplestory-cx26-io-ring.patch \
  maplestory-cx26-io-ring-arm.patch \
  maplestory-cx26-io-summary.patch \
  maplestory-cx26-io-timeline.patch \
  maplestory-cx26-io-cache-stats.patch; do
  if [[ "$BUILD_SCRIPT" == *"$diagnostic_patch"* ]]; then
    echo "ASSERT failed: $diagnostic_patch must remain development-only" >&2
    exit 1
  fi
done
assert_contains "$(<"$PATCH_FILE")" "CYDER_MAPLESTORY_IO_RING_EVENTS" \
  "I/O ring patch should contain its idempotence marker"
assert_contains "$(<"$PATCH_FILE")" "CYDER_IO ring count" \
  "I/O ring patch should emit a bounded ring summary"
assert_contains "$(<"$PATCH_FILE")" "ring_capture" \
  "I/O ring patch should capture generic file reads after arming"
assert_contains "$(<"$PATCH_FILE")" "F_GETPATH" \
  "I/O ring patch should resolve generic host-read paths on macOS"
assert_contains "$(<"$PATCH_FILE")" "dlls/ntdll/unix/thread.c" \
  "I/O ring patch should hook the Unix process exit path"
assert_contains "$(<"$PATCH_FILE")" "cyder_maplestory_io_ring_dump" \
  "I/O ring patch should dump the ring during process termination"
[[ -f "$ARM_PATCH_FILE" ]] || {
  echo "ASSERT failed: missing MapleStory I/O ring arm patch" >&2
  exit 1
}
assert_contains "$(<"$ARM_PATCH_FILE")" "CYDER_MAPLESTORY_IO_RING_ARM_FILE" \
  "I/O ring arm patch should support a control file"
assert_contains "$(<"$ARM_PATCH_FILE")" "CYDER_IO ring armed" \
  "I/O ring arm patch should emit an arm marker"
[[ -f "$SUMMARY_PATCH_FILE" ]] || {
  echo "ASSERT failed: missing MapleStory I/O summary patch" >&2
  exit 1
}
assert_contains "$(<"$SUMMARY_PATCH_FILE")" "CYDER_MAPLESTORY_IO_SUMMARY_SLOTS" \
  "I/O summary patch should contain its idempotence marker"
assert_contains "$(<"$SUMMARY_PATCH_FILE")" "CYDER_MAPLESTORY_IO_SUMMARY" \
  "I/O summary patch should expose an opt-in summary mode"
assert_contains "$(<"$SUMMARY_PATCH_FILE")" "CYDER_IO aggregate" \
  "I/O summary patch should emit compact aggregate records"
[[ -f "$TIMELINE_PATCH_FILE" ]] || {
  echo "ASSERT failed: missing MapleStory I/O timeline patch" >&2
  exit 1
}
assert_contains "$(<"$TIMELINE_PATCH_FILE")" "CYDER_MAPLESTORY_IO_TIMELINE_BUCKETS" \
  "I/O timeline patch should contain its idempotence marker"
assert_contains "$(<"$TIMELINE_PATCH_FILE")" "CYDER_IO timeline" \
  "I/O timeline patch should emit compact time buckets"
[[ -f "$CACHE_STATS_PATCH_FILE" ]] || {
  echo "ASSERT failed: missing MapleStory cache statistics patch" >&2
  exit 1
}
assert_contains "$(<"$CACHE_STATS_PATCH_FILE")" "CYDER_MAPLESTORY_IO_CACHE_STATS" \
  "cache statistics patch should contain its idempotence marker and opt-in"
assert_contains "$(<"$CACHE_STATS_PATCH_FILE")" "CYDER_IO cache path" \
  "cache statistics patch should emit per-path cache aggregates"
assert_contains "$(<"$CACHE_STATS_PATCH_FILE")" "skipped_needs_close" \
  "cache statistics patch should identify the needs_close skip path"
assert_contains "$(<"$CACHE_STATS_PATCH_FILE")" "skipped_no_entry" \
  "cache statistics patch should identify unregistered cache handles"
assert_contains "$(<"$CACHE_STATS_PATCH_FILE")" "skipped_no_offset" \
  "cache statistics patch should identify reads without a cache offset"
assert_contains "$(<"$CACHE_STATS_PATCH_FILE")" "CYDER_MAPLESTORY_FILE_CACHE_MMAP" \
  "cache statistics patch should expose the mmap fill experiment"
[[ -f "$SECTION_MAP_PATCH_FILE" ]] || {
  echo "ASSERT failed: missing MapleStory section-map summary patch" >&2
  exit 1
}
if [[ "$BUILD_SCRIPT" == *"maplestory-cx26-section-map-summary.patch"* ]]; then
  echo "ASSERT failed: section-map summary must remain development-only" >&2
  exit 1
fi
assert_contains "$(<"$SECTION_MAP_PATCH_FILE")" "CYDER_MAPLESTORY_SECTION_MAP_PATH" \
  "section-map patch should contain its idempotence marker"
assert_contains "$(<"$SECTION_MAP_PATCH_FILE")" "CYDER_MAPLESTORY_IO_SECTION_MAP" \
  "section-map patch should expose an opt-in diagnostic"
assert_contains "$(<"$SECTION_MAP_PATCH_FILE")" "CYDER_IO section_map" \
  "section-map patch should emit one aggregate mapping summary"

archive="$ROOT/tools/archives/crossover-sources-26.3.0.tar.gz"
if [[ -f "$archive" ]]; then
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/cyder-maplestory-io-ring.XXXXXX")"
  trap 'rm -rf "$tmp"' EXIT
  tar -xzf "$archive" -C "$tmp"
  patch --forward --batch -s -p1 -d "$tmp/sources/wine" \
    < "$ROOT/patches/maplestory-cx26-file-cache-adaptive.patch"
  patch --forward --batch -s -p1 -d "$tmp/sources/wine" < "$PATCH_FILE"
  patch --forward --batch -s -p1 -d "$tmp/sources/wine" < "$ARM_PATCH_FILE"
  patch --forward --batch -s -p1 -d "$tmp/sources/wine" < "$SUMMARY_PATCH_FILE"
  patch --forward --batch -s -p1 -d "$tmp/sources/wine" < "$TIMELINE_PATCH_FILE"
  patch --forward --batch --dry-run -s -p1 -d "$tmp/sources/wine" < "$CACHE_STATS_PATCH_FILE"
  patch --forward --batch --dry-run -s -p1 -d "$tmp/sources/wine" < "$SECTION_MAP_PATCH_FILE"
  echo "PASS: I/O ring patches apply after the adaptive file-cache patch"
else
  echo "SKIP: CX26.3.0 source archive is not available"
fi

echo "PASS test-maplestory-io-ring-patch"
