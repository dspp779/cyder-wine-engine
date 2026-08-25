#!/usr/bin/env bash
# MoltenVK 1.4.2 minOS exemption in pack-minos-scan.py.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/assert.sh"

MOD="$ROOT/scripts/pack-minos-scan.py"

unit_out="$(python3 - "$MOD" <<'PY'
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("pack_minos_scan", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

floor = mod.parse_version("10.15")
assert mod.is_moltenvk_142_exempt_path("lib/wine/x86_64-unix/libMoltenVK-1.4.2.dylib")
assert not mod.is_moltenvk_142_exempt_path("lib/wine/x86_64-unix/libMoltenVK-1.2.10.dylib")
assert not mod.is_moltenvk_142_exempt_path("lib/wine/x86_64-unix/libMoltenVK.dylib")
assert mod.minos_limit_for("lib/wine/x86_64-unix/libMoltenVK-1.4.2.dylib", floor) == (12, 0, 0)
assert mod.minos_limit_for("lib/wine/x86_64-unix/libMoltenVK-1.2.10.dylib", floor) == floor
print("UNIT_OK")
PY
)"
assert_contains "$unit_out" "UNIT_OK" "1.4.2 basename must be exempt to 12.0; 1.2.10 stays at floor"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-pack-minos-mvk.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
sdk="$(xcrun --sdk macosx --show-sdk-path)"
unix="$tmp/engine/lib/wine/x86_64-unix"
mkdir -p "$unix"
echo 'int p=1;' >"$tmp/p.c"

arch -x86_64 clang -arch x86_64 -mmacosx-version-min=12.0 -isysroot "$sdk" \
  -dynamiclib -o "$unix/libMoltenVK-1.4.2.dylib" "$tmp/p.c"
arch -x86_64 clang -arch x86_64 -mmacosx-version-min=10.15 -isysroot "$sdk" \
  -dynamiclib -o "$unix/libMoltenVK-1.2.10.dylib" "$tmp/p.c"

python3 "$MOD" "$tmp/engine" 10.15
assert_eq "$?" "0" "scan must allow 1.4.2 at minos 12.0"

arch -x86_64 clang -arch x86_64 -mmacosx-version-min=14.0 -isysroot "$sdk" \
  -dynamiclib -o "$unix/libMoltenVK-1.2.10.dylib" "$tmp/p.c"
if python3 "$MOD" "$tmp/engine" 10.15; then
  echo "expected high-minos 1.2.10 to fail" >&2
  exit 1
fi

echo "PASS pack-minos-scan MoltenVK 1.4.2 exemption"
