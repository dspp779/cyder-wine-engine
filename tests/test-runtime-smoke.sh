#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE="$ROOT/tests/fixtures/runtime-smoke.c"
LLVM_MINGW="${RUNTIME_SMOKE_LLVM_MINGW:-$ROOT/build/llvm-mingw-20260616-ucrt-macos-universal}"
WINE_RUNTIME="${RUNTIME_SMOKE_WINE_RUNTIME:-$ROOT/install/wine-cx26-x86_64}"
CC="$LLVM_MINGW/bin/x86_64-w64-mingw32-clang"
WINE="$WINE_RUNTIME/bin/wine"

if [[ ! -x "$CC" ]]; then
  echo "SKIP runtime smoke: compiler not found at $CC"
  exit 0
fi
if [[ ! -x "$WINE" ]]; then
  echo "SKIP runtime smoke: Wine runtime not found at $WINE"
  exit 0
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cyder-runtime-smoke.XXXXXX")"
cleanup() {
  local result=$?
  if [[ -d "$TMP_DIR/prefix" && -x "$WINE_RUNTIME/bin/wineserver" ]]; then
    # Only the disposable test prefix: let its server flush registry state
    # before deleting the directory. Never kill another Wine session.
    env -u DYLD_LIBRARY_PATH -u DYLD_FALLBACK_LIBRARY_PATH \
      -u WINELOADER -u WINESERVER -u WINEDLLPATH \
      WINEPREFIX="$TMP_DIR/prefix" arch -x86_64 "$WINE_RUNTIME/bin/wineserver" -k >/dev/null 2>&1 || true
    sleep 3
  fi
  rm -rf "$TMP_DIR"
  return "$result"
}
trap cleanup EXIT

# Exercise both PE architectures against the same new WoW64 prefix.
for target in x86_64 i686; do
  compiler="$LLVM_MINGW/bin/$target-w64-mingw32-clang"
  [[ -x "$compiler" ]] || { echo "Missing compiler: $compiler" >&2; exit 1; }
  "$compiler" -O2 -Wall -Wextra -Werror \
    "$FIXTURE" -lbcrypt -o "$TMP_DIR/runtime-smoke-$target.exe"
  echo "Runtime smoke architecture: $target"
  # Validate the bundled install, without Homebrew's dylib search paths or an
  # inherited loader from a different engine. The prefix is disposable.
  env -u DYLD_LIBRARY_PATH -u DYLD_FALLBACK_LIBRARY_PATH \
    -u WINELOADER -u WINESERVER -u WINEDLLPATH -u WINEARCH \
    WINEPREFIX="$TMP_DIR/prefix" \
    WINEDEBUG=-all \
    WINEDLLOVERRIDES=mscoree,mshtml= \
    arch -x86_64 "$WINE" "$TMP_DIR/runtime-smoke-$target.exe"
done
