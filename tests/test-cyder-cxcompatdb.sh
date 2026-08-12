#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/assert.sh"

source_text="$(cat "$ROOT/runtime/cxcompatdb/cxcompatdb.c")"
build_text="$(cat "$ROOT/scripts/build-wine.sh")"
pack_text="$(cat "$ROOT/scripts/pack-engine-artifact.sh")"

assert_contains "$source_text" 'CYDER_GRAPHICS_BACKEND_PATH' \
  "cxcompatdb should accept a direct graphics backend directory"
assert_contains "$source_text" 'Wine builtin DLL' \
  "cxcompatdb should validate the Wine builtin PE signature"
assert_contains "$source_text" 'get_u16( header + pe + 4 ) == expected' \
  "cxcompatdb should validate the PE machine"
assert_contains "$source_text" 'require_winemetal' \
  "cxcompatdb should require DXMT's winemetal builtin PE"
assert_contains "$source_text" 'graphics backend=%s machine=%s path=%s' \
  "cxcompatdb should log the activated backend path"
assert_contains "$source_text" 'appended current-process argument' \
  "cxcompatdb should own current-process CompatDB arguments"
if [[ "$build_text" == *"cyder-compatdb-runtime.patch"* ]]; then
  echo "ASSERT failed: Wine builds should leave the original CrossOver ntdll unchanged" >&2
  exit 1
fi
assert_contains "$build_text" 'build-cyder-cxcompatdb.sh' \
  "Wine builds should build the standalone cxcompatdb"
assert_contains "$pack_text" 'Missing Cyder cxcompatdb' \
  "engine packing should require the standalone cxcompatdb"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/cyder-cxcompatdb-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
CYDER_CXCOMPATDB_OUTPUT="$tmp/cxcompatdb.so" \
  bash "$ROOT/scripts/build-cyder-cxcompatdb.sh" >/dev/null
file "$tmp/cxcompatdb.so" | grep -Fq 'Mach-O 64-bit'
nm -u "$tmp/cxcompatdb.so" | grep -Fq '_prepend_dll_path'
nm -u "$tmp/cxcompatdb.so" | grep -Fq '_add_load_order_override'
nm -u "$tmp/cxcompatdb.so" | grep -Fq '_NtCurrentTeb'
otool -l "$tmp/cxcompatdb.so" | grep -A3 LC_BUILD_VERSION | grep -Fq 'minos 10.15'

echo "PASS test-cyder-cxcompatdb"
