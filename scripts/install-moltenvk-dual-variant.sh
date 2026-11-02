#!/usr/bin/env bash
# Stage MoltenVK dual-variant layout for Cyder engines:
#   libMoltenVK-1.4.2.dylib / libMoltenVK-1.2.10.dylib  (reals)
#   libMoltenVK.real.dylib -> selected real
#   libMoltenVK.dylib      (wait-poll shim re-exporting .real)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=env-x86_64.sh
source "$SCRIPT_DIR/env-x86_64.sh"

UNIX_LIB=""
V142=""
V1210=""
DEFAULT_VARIANT="1.4.2"
SKIP_SHIM=0

usage() {
  cat <<EOF
Usage: $(basename "$0") --unix-lib DIR --v142 PATH --v1210 PATH [--default 1.4.2|1.2.10] [--skip-shim]

Copies versioned MoltenVK reals into DIR, points libMoltenVK.real.dylib at the
default variant, then builds the wait-poll shim as libMoltenVK.dylib.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --unix-lib) UNIX_LIB="${2:?}"; shift 2 ;;
    --v142) V142="${2:?}"; shift 2 ;;
    --v1210) V1210="${2:?}"; shift 2 ;;
    --default) DEFAULT_VARIANT="${2:?}"; shift 2 ;;
    --skip-shim) SKIP_SHIM=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

[[ -n "$UNIX_LIB" && -n "$V142" && -n "$V1210" ]] || {
  usage >&2
  exit 1
}
case "$DEFAULT_VARIANT" in
  1.4.2 | 1.2.10) ;;
  *) echo "Invalid --default: $DEFAULT_VARIANT (expected 1.4.2 or 1.2.10)" >&2; exit 1 ;;
esac
[[ -f "$V142" ]] || { echo "Missing 1.4.2 real: $V142" >&2; exit 1; }
[[ -f "$V1210" ]] || { echo "Missing 1.2.10 real: $V1210" >&2; exit 1; }

mkdir -p "$UNIX_LIB"
cp -p "$V142" "$UNIX_LIB/libMoltenVK-1.4.2.dylib"
cp -p "$V1210" "$UNIX_LIB/libMoltenVK-1.2.10.dylib"
chmod 755 "$UNIX_LIB/libMoltenVK-1.4.2.dylib" "$UNIX_LIB/libMoltenVK-1.2.10.dylib"

# Prefer versioned install names so dlopen via .real stays unambiguous.
install_name_tool -id '@loader_path/libMoltenVK-1.4.2.dylib' \
  "$UNIX_LIB/libMoltenVK-1.4.2.dylib" 2>/dev/null || true
install_name_tool -id '@loader_path/libMoltenVK-1.2.10.dylib' \
  "$UNIX_LIB/libMoltenVK-1.2.10.dylib" 2>/dev/null || true

ln -sfn "libMoltenVK-${DEFAULT_VARIANT}.dylib" "$UNIX_LIB/libMoltenVK.real.dylib"

if (( SKIP_SHIM )); then
  echo "Staged dual MoltenVK reals in $UNIX_LIB (shim skipped)"
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
local_shim="$STAGE/libMoltenVK-dual-$$.dylib"

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
codesign --force -s - "$UNIX_LIB/libMoltenVK-1.2.10.dylib" >/dev/null 2>&1 || true

strings "$UNIX_LIB/libMoltenVK.dylib" | grep -Fq 'cyder-moltenvk-timeline-wait-poll' || {
  echo "Installed shim missing wait-poll marker" >&2
  exit 1
}
otool -L "$UNIX_LIB/libMoltenVK.dylib" | grep -Fq '@loader_path/libMoltenVK.real.dylib' || {
  echo "Installed shim does not re-export libMoltenVK.real.dylib" >&2
  exit 1
}

echo "Staged dual MoltenVK layout in $UNIX_LIB"
echo "  real -> libMoltenVK-${DEFAULT_VARIANT}.dylib"
echo "  shim -> libMoltenVK.dylib"
