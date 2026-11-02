#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/assert.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-moltenvk-dual.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

unix="$tmp/lib/wine/x86_64-unix"
mkdir -p "$unix" "$tmp/reals"

# Tiny x86_64 dylibs stand in for MoltenVK reals (no Xcode MoltenVK build needed).
sdk="$(xcrun --sdk macosx --show-sdk-path)"
cat >"$tmp/probe.c" <<'EOF'
int cyder_moltenvk_dual_probe = 1;
EOF
for ver in 1.4.2 1.2.10; do
  arch -x86_64 env "${CYDER_HOST_CLANG:-/usr/bin/clang}" -arch x86_64 \
    -mmacosx-version-min=10.15 \
    -isysroot "$sdk" \
    -dynamiclib \
    -o "$tmp/reals/libMoltenVK-$ver.dylib" \
    "$tmp/probe.c" \
    -install_name "@loader_path/libMoltenVK-$ver.dylib"
done

# env-x86_64 prepends llvm-mingw to PATH. A host shim must still use Apple
# clang, even when a cross compiler is first on that PATH.
mkdir -p "$tmp/fake-llvm/bin"
printf '#!/bin/sh\nexit 97\n' > "$tmp/fake-llvm/bin/clang"
chmod +x "$tmp/fake-llvm/bin/clang"
LLVM_MINGW="$tmp/fake-llvm" bash "$ROOT/scripts/install-moltenvk-dual-variant.sh" \
  --unix-lib "$unix" \
  --v142 "$tmp/reals/libMoltenVK-1.4.2.dylib" \
  --v1210 "$tmp/reals/libMoltenVK-1.2.10.dylib" \
  --default 1.4.2

assert test -f "$unix/libMoltenVK-1.4.2.dylib"
assert test -f "$unix/libMoltenVK-1.2.10.dylib"
assert test -L "$unix/libMoltenVK.real.dylib"
assert_eq "$(readlink "$unix/libMoltenVK.real.dylib")" "libMoltenVK-1.4.2.dylib" \
  ".real must default to 1.4.2"
assert test -f "$unix/libMoltenVK.dylib"
assert_eq "$(lipo -archs "$unix/libMoltenVK.dylib")" x86_64 "shim must remain thin x86_64"
assert_contains "$(otool -l "$unix/libMoltenVK.dylib")" 'minos 10.15' "shim must retain the product floor"
assert_contains "$(strings "$unix/libMoltenVK.dylib")" "cyder-moltenvk-timeline-wait-poll" \
  "shim must embed wait-poll marker"
assert_contains "$(otool -L "$unix/libMoltenVK.dylib")" "@loader_path/libMoltenVK.real.dylib" \
  "shim must re-export .real"

# Missing real must fail closed.
rm -rf "$unix"
mkdir -p "$unix"
if bash "$ROOT/scripts/install-moltenvk-dual-variant.sh" \
  --unix-lib "$unix" \
  --v142 "$tmp/reals/libMoltenVK-1.4.2.dylib" \
  --v1210 "$tmp/missing.dylib" \
  --default 1.4.2 2>"$tmp/err"; then
  echo "expected missing 1.2.10 to fail" >&2
  exit 1
fi
assert_contains "$(cat "$tmp/err")" "Missing 1.2.10 real" "error should name missing 1.2.10"

echo "PASS moltenvk dual-variant layout installer"
