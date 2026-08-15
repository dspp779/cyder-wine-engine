#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/assert.sh"

PATCH_FILE="$ROOT/patches/maplestory-cx26-file-cache-adaptive.patch"
BUILD_SCRIPT="$(<"$ROOT/scripts/build-wine.sh")"

[[ -f "$PATCH_FILE" ]] || {
  echo "ASSERT failed: missing adaptive MapleStory file-cache patch" >&2
  exit 1
}
assert_contains "$BUILD_SCRIPT" "maplestory-cx26-file-cache-adaptive.patch" \
  "MapleStory builds should apply the adaptive file-cache patch"
assert_contains "$(<"$PATCH_FILE")" "CYDER_MAPLESTORY_FILE_CACHE_MIN_WINDOW" \
  "adaptive patch should contain its idempotence marker"

archive="$ROOT/tools/archives/crossover-sources-26.3.0.tar.gz"
if [[ -f "$archive" ]]; then
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/cyder-maplestory-file-cache.XXXXXX")"
  trap 'rm -rf "$tmp"' EXIT
  tar -xzf "$archive" -C "$tmp"
  patch --forward --batch --dry-run -s -p1 -d "$tmp/sources/wine" < "$PATCH_FILE"
  echo "PASS: adaptive MapleStory file-cache patch applies to CX26.3.0"
else
  echo "SKIP: CX26.3.0 source archive is not available"
fi

echo "PASS test-maplestory-file-cache-patch"
