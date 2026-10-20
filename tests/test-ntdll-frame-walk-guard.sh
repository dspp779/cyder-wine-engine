#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE="$ROOT/tests/fixtures/ntdll-frame-walk-guard.c"
LLVM_MINGW="${FRAME_WALK_LLVM_MINGW:-$ROOT/build/llvm-mingw-20260616-ucrt-macos-universal}"
WINE_RUNTIME="${FRAME_WALK_WINE_RUNTIME:-$ROOT/install/wine-cx26-x86_64}"
CC="$LLVM_MINGW/bin/x86_64-w64-mingw32-clang"
WINE="$WINE_RUNTIME/bin/wine"

if [[ ! -x "$CC" ]]; then
  echo "SKIP ntdll frame-walk guard: compiler not found at $CC"
  exit 0
fi
if [[ ! -x "$WINE" ]]; then
  echo "SKIP ntdll frame-walk guard: Wine runtime not found at $WINE"
  exit 0
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cyder-frame-walk.XXXXXX")"
cleanup() {
  local result=$?
  if [[ -d "$TMP_DIR/prefix" && -x "$WINE_RUNTIME/bin/wineserver" ]]; then
    # Only the disposable test prefix: let its server flush registry state
    # before deleting the directory. Never kill another Wine session.
    WINEPREFIX="$TMP_DIR/prefix" arch -x86_64 "$WINE_RUNTIME/bin/wineserver" -k >/dev/null 2>&1 || true
    sleep 3
  fi
  rm -rf "$TMP_DIR"
  return "$result"
}
trap cleanup EXIT

"$CC" -O2 -Wall -Wextra -Werror \
  "$FIXTURE" -o "$TMP_DIR/ntdll-frame-walk-guard.exe"

env \
  WINEPREFIX="$TMP_DIR/prefix" \
  WINEDEBUG=-all \
  WINEDLLOVERRIDES=mscoree,mshtml= \
  arch -x86_64 "$WINE" "$TMP_DIR/ntdll-frame-walk-guard.exe"
