#!/usr/bin/env bash
# Stage the MoltenVK layout for Cyder engines (one real; the file name is kept
# from the earlier two-real layout):
#   libMoltenVK-1.4.2.dylib  (real)
#   libMoltenVK.real.dylib -> libMoltenVK-1.4.2.dylib
#   libMoltenVK.dylib        (wait-poll shim re-exporting .real)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=env-x86_64.sh
source "$SCRIPT_DIR/env-x86_64.sh"

UNIX_LIB=""
V142=""
DEFAULT_VARIANT="1.4.2"
SKIP_SHIM=0

usage() {
  cat <<EOF
Usage: $(basename "$0") --unix-lib DIR --v142 PATH [--skip-shim]

Copies the versioned MoltenVK real into DIR, removes any other versioned real
left by an older layout, points libMoltenVK.real.dylib at it, then builds the
wait-poll shim as libMoltenVK.dylib.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --unix-lib) UNIX_LIB="${2:?}"; shift 2 ;;
    --v142) V142="${2:?}"; shift 2 ;;
    --skip-shim) SKIP_SHIM=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

[[ -n "$UNIX_LIB" && -n "$V142" ]] || {
  usage >&2
  exit 1
}
[[ -f "$V142" ]] || { echo "Missing 1.4.2 real: $V142" >&2; exit 1; }

mkdir -p "$UNIX_LIB"
# An older two-real layout may still be in the tree; only one real ships.
for stale in "$UNIX_LIB"/libMoltenVK-*.dylib; do
  [[ -e "$stale" && "$(basename "$stale")" != "libMoltenVK-${DEFAULT_VARIANT}.dylib" ]] || continue
  echo "Removing stale MoltenVK real $(basename "$stale")"
  rm -f "$stale"
done
cp -p "$V142" "$UNIX_LIB/libMoltenVK-1.4.2.dylib"
chmod 755 "$UNIX_LIB/libMoltenVK-1.4.2.dylib"

# Prefer a versioned install name so dlopen via .real stays unambiguous.
install_name_tool -id '@loader_path/libMoltenVK-1.4.2.dylib' \
  "$UNIX_LIB/libMoltenVK-1.4.2.dylib" 2>/dev/null || true

ln -sfn "libMoltenVK-${DEFAULT_VARIANT}.dylib" "$UNIX_LIB/libMoltenVK.real.dylib"

if (( SKIP_SHIM )); then
  echo "Staged MoltenVK real in $UNIX_LIB (shim skipped)"
  exit 0
fi

SRC="$ROOT/tools/cyder-mvk-timeline-wait-poll/cyder_mvk_timeline_wait_poll.m"
[[ -f "$SRC" ]] || {
  echo "Missing wait-poll shim source: $SRC" >&2
  exit 1
}

STAGE="$ROOT/build/cyder-mvk-timeline-wait-poll"
mkdir -p "$STAGE"
sdk="$(xcrun --sdk macosx --show-sdk-path)"
real="$UNIX_LIB/libMoltenVK.real.dylib"
# Resolve symlink for -reexport_library (clang needs a real Mach-O path).
real_file="$(cd "$UNIX_LIB" && /usr/bin/python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$real")"
local_shim="$STAGE/libMoltenVK-shim-$$.dylib"

arch -x86_64 env "${CYDER_HOST_CLANG:-/usr/bin/clang}" -arch x86_64 \
  -mmacosx-version-min="${MACOSX_DEPLOYMENT_TARGET}" \
  -isysroot "$sdk" \
  -dynamiclib \
  -o "$local_shim" \
  "$SRC" \
  -Wl,-reexport_library,"$real_file" \
  -install_name '@loader_path/libMoltenVK.dylib'
# clang records the reexport using the real's install_name (versioned), not the
# absolute path passed to -reexport_library. Rewrite to the stable .real name.
reexport_from="$(otool -L "$local_shim" | awk '/reexport/{print $1; exit}')"
[[ -n "$reexport_from" ]] || {
  echo "Built shim has no reexport dependency" >&2
  exit 1
}
if [[ "$reexport_from" != "@loader_path/libMoltenVK.real.dylib" ]]; then
  install_name_tool -change "$reexport_from" '@loader_path/libMoltenVK.real.dylib' "$local_shim"
fi
codesign --force -s - "$local_shim" >/dev/null 2>&1 || true

cp -p "$local_shim" "$UNIX_LIB/libMoltenVK.dylib"
chmod 755 "$UNIX_LIB/libMoltenVK.dylib"
codesign --force -s - "$UNIX_LIB/libMoltenVK.dylib" >/dev/null 2>&1 || true
codesign --force -s - "$UNIX_LIB/libMoltenVK-1.4.2.dylib" >/dev/null 2>&1 || true

strings "$UNIX_LIB/libMoltenVK.dylib" | grep -Fq 'cyder-moltenvk-timeline-wait-poll' || {
  echo "Installed shim missing wait-poll marker" >&2
  exit 1
}
otool -L "$UNIX_LIB/libMoltenVK.dylib" | grep -Fq '@loader_path/libMoltenVK.real.dylib' || {
  echo "Installed shim does not re-export libMoltenVK.real.dylib" >&2
  exit 1
}

echo "Staged MoltenVK layout in $UNIX_LIB"
echo "  real -> libMoltenVK-${DEFAULT_VARIANT}.dylib"
echo "  shim -> libMoltenVK.dylib"
