#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/assert.sh"
STRIP="$ROOT/scripts/strip-wine-install.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/include/wine" "$TMP/share/man/man1" "$TMP/bin" \
  "$TMP/lib/wine/x86_64-windows" "$TMP/lib/wine/i386-windows" "$TMP/toolchain"
printf '%s\n' 'fake' >"$TMP/include/wine/windows.h"
printf '%s\n' 'fake' >"$TMP/share/man/man1/wine.1"
printf '%s\n' '#!/bin/sh' >"$TMP/bin/wine"
printf '%s\n' '#!/bin/sh' >"$TMP/bin/wineserver"
printf '%s\n' '#!/bin/sh' >"$TMP/bin/winegcc"
chmod +x "$TMP/bin/wine" "$TMP/bin/wineserver" "$TMP/bin/winegcc"
printf '%s\n' 'lib' >"$TMP/lib/wine/x86_64-windows/libfoo.a"
printf '%s\n' 'lib' >"$TMP/lib/wine/i386-windows/libbar.a"
printf '%s\n' 'fake PE with debug data' >"$TMP/lib/wine/x86_64-windows/debugged.dll"
printf '%s\n' '#!/bin/sh' 'echo "  7 .debug_info 00000100"' >"$TMP/toolchain/llvm-objdump"
printf '%s\n' '#!/bin/sh' 'printf "%s\n" stripped >>"$2"' >"$TMP/toolchain/llvm-strip"
chmod +x "$TMP/toolchain/llvm-objdump" "$TMP/toolchain/llvm-strip"

CYDER_LLVM_STRIP="$TMP/toolchain/llvm-strip" bash "$STRIP" "$TMP"

[[ ! -d "$TMP/include" ]] || {
  echo "include/ should be removed" >&2
  exit 1
}
[[ ! -d "$TMP/share/man" ]] || {
  echo "share/man/ should be removed" >&2
  exit 1
}
[[ ! -f "$TMP/bin/winegcc" ]] || {
  echo "winegcc should be removed" >&2
  exit 1
}
[[ -x "$TMP/bin/wine" ]] || {
  echo "wine must remain" >&2
  exit 1
}
[[ -x "$TMP/bin/wineserver" ]] || {
  echo "wineserver must remain" >&2
  exit 1
}
find "$TMP/lib" -name '*.a' | grep -q . && {
  echo "*.a files should be removed" >&2
  exit 1
}
assert_contains "$(cat "$TMP/lib/wine/x86_64-windows/debugged.dll")" "stripped" \
  "release cleanup should strip PE DWARF sections"

output="$(CYDER_SKIP_ENGINE_STRIP=1 bash "$STRIP" "$TMP" 2>&1)"
assert_contains "$output" "skipping strip" "CYDER_SKIP_ENGINE_STRIP should no-op"

echo "PASS test-strip-wine-install"
