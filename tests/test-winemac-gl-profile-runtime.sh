#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPILER="${RUNTIME_SMOKE_LLVM_MINGW:-$ROOT/build/llvm-mingw-20260616-ucrt-macos-universal}/bin/x86_64-w64-mingw32-clang"
RUNTIME="${GL_PROFILE_WINE_RUNTIME:-${RUNTIME_SMOKE_WINE_RUNTIME:-$ROOT/install/wine-cx26-x86_64}}"
if [[ ! -x "$COMPILER" || ! -x "$RUNTIME/bin/wine" ]]; then
    echo 'SKIP GL profiling runtime control: select a built runtime and llvm-mingw'; exit 0
fi
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cyder-gl-profile-runtime.XXXXXX")"
cleanup() {
    WINEPREFIX="$TMP/prefix" arch -x86_64 "$RUNTIME/bin/wineserver" -k >/dev/null 2>&1 || true
    sleep 3
    rm -rf "$TMP"
}
trap cleanup EXIT
"$COMPILER" -O2 -Wall -Wextra -Werror "$ROOT/tests/fixtures/gl-profile-control.c" -lopengl32 -lgdi32 -luser32 -o "$TMP/control.exe"
env -u WINELOADER -u WINESERVER -u WINEDLLPATH -u WINEARCH -u DYLD_LIBRARY_PATH -u DYLD_FALLBACK_LIBRARY_PATH \
    WINEPREFIX="$TMP/prefix" CYDER_GL_PROFILE=1 WINEDEBUG=-all WINEDLLOVERRIDES=mscoree,mshtml= \
    arch -x86_64 "$RUNTIME/bin/wine" "$TMP/control.exe" > "$TMP/control.log" 2>&1 || { cat "$TMP/control.log"; exit 1; }
python3 - "$ROOT" "$TMP/control.log" <<'PY'
from pathlib import Path
import runpy,sys
root,log=Path(sys.argv[1]),Path(sys.argv[2])
text=log.read_text(errors='replace')
assert 'PASS real GL front flush and back-buffer swap control' in text
rows=runpy.run_path(str(root/'tools/gl-profile/summarize.py'))['summarize'](text)
assert sum(r['native'] for r in rows if r['phase']=='flush')==8, 'front flush was lost, duplicated or not profiled'
assert sum(r['native'] for r in rows if r['phase']=='swap')==8, 'back-buffer swap was lost, duplicated or not profiled'
assert all(r['double_buffer']==1 for r in rows)
print('PASS real hidden-window GL control: exactly 8 native front flushes and 8 native swaps (not a performance benchmark)')
PY
