#!/usr/bin/env bash
# Versioned MoltenVK real minOS exemptions in pack-minos-scan.py.
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
assert mod.is_moltenvk_real_exempt_path("lib/wine/x86_64-unix/libMoltenVK-1.4.2.dylib")
assert mod.is_moltenvk_real_exempt_path("lib/wine/x86_64-unix/libMoltenVK-1.2.10.dylib")
assert not mod.is_moltenvk_real_exempt_path("lib/wine/x86_64-unix/libMoltenVK.dylib")
assert mod.minos_limit_for("lib/wine/x86_64-unix/libMoltenVK-1.4.2.dylib", floor) == (12, 0, 0)
assert mod.minos_limit_for("lib/wine/x86_64-unix/libMoltenVK-1.2.10.dylib", floor) == (12, 0, 0)
assert mod.minos_limit_for("lib/wine/x86_64-unix/libMoltenVK.dylib", floor) == floor
assert mod.minos_limit_for("lib/wine/x86_64-unix/libMoltenVK-1.3.0.dylib", floor) == floor
print("UNIT_OK")
PY
)"
assert_contains "$unit_out" "UNIT_OK" "only the two versioned reals may reach 12.0"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-pack-minos-mvk.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
sdk="$(xcrun --sdk macosx --show-sdk-path)"
unix="$tmp/engine/lib/wine/x86_64-unix"
mkdir -p "$unix"
echo 'int p=1;' >"$tmp/p.c"

arch -x86_64 env "${CYDER_HOST_CLANG:-/usr/bin/clang}" -arch x86_64 -mmacosx-version-min=12.0 -isysroot "$sdk" \
  -dynamiclib -o "$unix/libMoltenVK-1.4.2.dylib" "$tmp/p.c"
arch -x86_64 env "${CYDER_HOST_CLANG:-/usr/bin/clang}" -arch x86_64 -mmacosx-version-min=12.0 -isysroot "$sdk" \
  -dynamiclib -o "$unix/libMoltenVK-1.2.10.dylib" "$tmp/p.c"

python3 "$MOD" "$tmp/engine" 10.15
assert_eq "$?" "0" "scan must allow both reals at minos 12.0"

arch -x86_64 env "${CYDER_HOST_CLANG:-/usr/bin/clang}" -arch x86_64 -mmacosx-version-min=12.1 -isysroot "$sdk" \
  -dynamiclib -o "$unix/libMoltenVK-1.2.10.dylib" "$tmp/p.c"
if python3 "$MOD" "$tmp/engine" 10.15; then
  echo "expected high-minos 1.2.10 to fail" >&2
  exit 1
fi

# The unversioned shim receives no exemption, even with an allowed real beside it.
rm "$unix/libMoltenVK-1.2.10.dylib"
cp "$unix/libMoltenVK-1.4.2.dylib" "$unix/libMoltenVK.dylib"
if python3 "$MOD" "$tmp/engine" 10.15; then
  echo "expected minos 12.0 shim to fail" >&2
  exit 1
fi

echo "PASS pack-minos-scan versioned MoltenVK exemptions"
