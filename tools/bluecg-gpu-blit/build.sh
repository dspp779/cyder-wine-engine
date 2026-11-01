#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
[[ $# -eq 1 ]] || { echo 'usage: build.sh OUTPUT_DIRECTORY' >&2; exit 2; }
export OGOM="$ROOT"
source "$ROOT/scripts/env-x86_64.sh"
mkdir -p "$1"
OUTPUT="$(cd "$1" && pwd)"
for name in i386 x86_64; do
  [[ ! -e "$OUTPUT/cyder_bluecg_gpu-$name.dll" ]] || { echo "refusing existing output: $name" >&2; exit 3; }
done
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cyder-bluecg-gpu-build.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
for name in i386 x86_64; do
  target="$name"
  [[ "$name" != i386 ]] || target=i686
  "$LLVM_MINGW/bin/$target-w64-mingw32-clang" -O2 -Wall -Wextra -Werror -shared \
    "$ROOT/tools/bluecg-gpu-blit/bluecg-gpu-blit.c" \
    -o "$TMP/cyder_bluecg_gpu-$name.dll" -lopengl32 -lgdi32 -luser32
done
for name in i386 x86_64; do mv "$TMP/cyder_bluecg_gpu-$name.dll" "$OUTPUT/"; done
