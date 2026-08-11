#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/env-x86_64.sh"

WINE_SRC="${WINE_SRC:-$ROOT/build/cx26/sources/wine}"
WINE_INSTALL="${WINE_INSTALL:-$ROOT/install/wine-cx26-x86_64}"
SOURCE="$ROOT/runtime/cxcompatdb/cxcompatdb.c"
OUTPUT="${CYDER_CXCOMPATDB_OUTPUT:-$WINE_INSTALL/lib/wine/x86_64-unix/cxcompatdb.so}"
TARGET="${MACOSX_DEPLOYMENT_TARGET:-10.15}"

[[ -f "$WINE_SRC/include/winternl.h" && -f "$WINE_SRC/include/config.h.in" ]] || {
  echo "Missing configured CrossOver Wine source: $WINE_SRC" >&2
  exit 1
}
[[ -f "$WINE_SRC/build64/include/config.h" ]] || {
  echo "Missing configured Wine header: $WINE_SRC/build64/include/config.h" >&2
  exit 1
}

mkdir -p "$(dirname "$OUTPUT")"
arch -x86_64 /usr/bin/clang -dynamiclib -O2 -Wall -Wextra -Werror \
  -mmacosx-version-min="$TARGET" \
  -DWINE_UNIX_LIB \
  -I"$WINE_SRC/build64/include" -I"$WINE_SRC/include" \
  -Wl,-undefined,dynamic_lookup \
  -Wl,-install_name,@loader_path/cxcompatdb.so \
  -o "$OUTPUT" "$SOURCE"

echo "Built Cyder cxcompatdb: $OUTPUT"
otool -l "$OUTPUT" | awk '/minos/{print "  " $0; exit}'
