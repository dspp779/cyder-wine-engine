#!/usr/bin/env bash
# Unit test for the DXMT minOS exemption in scripts/pack-minos-scan.py.
# Exercises the pure classification helpers directly (no real Mach-O
# binaries needed) plus an end-to-end scan() over a synthetic tree using a
# stubbed `file`/`otool` PATH shim.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/assert.sh"

MOD="$ROOT/scripts/pack-minos-scan.py"
assert test -f "$MOD"

unit_out="$(python3 - "$MOD" <<'PY'
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("pack_minos_scan", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

assert mod.is_dxmt_exempt_path("lib/dxmt/x86_64-unix/winemetal.so")
assert mod.is_dxmt_exempt_path("lib/dxmt/x86_64-windows/d3d11.dll")
assert not mod.is_dxmt_exempt_path("lib/wine/x86_64-unix/ntdll.so")
assert not mod.is_dxmt_exempt_path("bin/wine")
assert not mod.is_dxmt_exempt_path("lib/dxvk/x86_64-windows/d3d11.dll")

floor = mod.parse_version("10.15")
assert mod.minos_limit_for("lib/dxmt/x86_64-unix/winemetal.so", floor) == (15, 0, 0)
assert mod.minos_limit_for("lib/wine/x86_64-unix/ntdll.so", floor) == floor
assert mod.parse_version("15.0") == (15, 0, 0)
assert mod.parse_version("10.15") == (10, 15, 0)

print("UNIT_OK")
PY
)"
assert_contains "$unit_out" "UNIT_OK" \
  "pack-minos-scan must expose is_dxmt_exempt_path/minos_limit_for helpers with the 15.0 DXMT ceiling"

# End-to-end scan() over a synthetic tree, with `file`/`otool` stubbed so no
# real Mach-O binaries are required. Only *.fake-macho files are "seen" as
# Mach-O; their declared minos comes from an adjacent *.minos sidecar file.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-pack-minos-scan.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

STUB_BIN="$TMP/stubbin"
mkdir -p "$STUB_BIN"
cat >"$STUB_BIN/file" <<'SH'
#!/usr/bin/env bash
path="${@: -1}"
if [[ "$path" == *.fake-macho ]]; then
  echo "Mach-O 64-bit executable x86_64"
else
  echo "ASCII text"
fi
SH
cat >"$STUB_BIN/otool" <<'SH'
#!/usr/bin/env bash
path="${@: -1}"
minos="$(cat "${path}.minos" 2>/dev/null || echo 10.15)"
echo "  cmd LC_BUILD_VERSION"
echo "   platform 1"
echo "      minos $minos"
SH
chmod +x "$STUB_BIN/file" "$STUB_BIN/otool"

ENGINE_TREE="$TMP/wine-x86_64"
mkdir -p "$ENGINE_TREE/lib/wine/x86_64-unix" "$ENGINE_TREE/lib/dxmt/x86_64-unix"
printf 'stub\n' >"$ENGINE_TREE/lib/wine/x86_64-unix/ntdll.so.fake-macho"
printf '10.15\n' >"$ENGINE_TREE/lib/wine/x86_64-unix/ntdll.so.fake-macho.minos"
printf 'stub\n' >"$ENGINE_TREE/lib/dxmt/x86_64-unix/winemetal.so.fake-macho"
printf '15.0\n' >"$ENGINE_TREE/lib/dxmt/x86_64-unix/winemetal.so.fake-macho.minos"

PATH="$STUB_BIN:$PATH" python3 "$MOD" "$ENGINE_TREE" "10.15" >"$TMP/pass.out" 2>"$TMP/pass.err"
assert_contains "$(cat "$TMP/pass.out")" "OK: staged engine Mach-O minos" \
  "scan must pass when only lib/dxmt/** exceeds the floor (within its 15.0 ceiling)"

# A non-DXMT file above the floor must still fail closed.
printf '15.0\n' >"$ENGINE_TREE/lib/wine/x86_64-unix/ntdll.so.fake-macho.minos"
if PATH="$STUB_BIN:$PATH" python3 "$MOD" "$ENGINE_TREE" "10.15" >"$TMP/fail.out" 2>"$TMP/fail.err"; then
  echo "ASSERT failed: scan must reject non-DXMT Mach-O above the product floor" >&2
  cat "$TMP/fail.out" "$TMP/fail.err" >&2
  exit 1
fi
assert_contains "$(cat "$TMP/fail.err")" "ntdll.so.fake-macho" \
  "scan failure must name the offending non-DXMT binary"
assert_contains "$(cat "$TMP/fail.err")" "lib/dxmt/" \
  "scan failure message must document the lib/dxmt exemption"

# DXMT itself must still fail closed above its 15.0 ceiling.
printf '10.15\n' >"$ENGINE_TREE/lib/wine/x86_64-unix/ntdll.so.fake-macho.minos"
printf '15.1\n' >"$ENGINE_TREE/lib/dxmt/x86_64-unix/winemetal.so.fake-macho.minos"
if PATH="$STUB_BIN:$PATH" python3 "$MOD" "$ENGINE_TREE" "10.15" >"$TMP/dxmt-high.out" 2>"$TMP/dxmt-high.err"; then
  echo "ASSERT failed: scan must reject DXMT Mach-O above its own 15.0 ceiling" >&2
  cat "$TMP/dxmt-high.out" "$TMP/dxmt-high.err" >&2
  exit 1
fi
assert_contains "$(cat "$TMP/dxmt-high.err")" "winemetal.so.fake-macho" \
  "scan failure must name the offending DXMT binary when it exceeds its own ceiling"

echo "PASS test-pack-minos-scan"
