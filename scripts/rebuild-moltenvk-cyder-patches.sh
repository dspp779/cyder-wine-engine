#!/usr/bin/env bash
# Rebuild MoltenVK with Cyder patches (timeline wait poll + present autoreleasepool).
# Does not pack a release artifact. Installs into GRAPHICS_INSTALL + WINE_INSTALL.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=env-x86_64.sh
source "$SCRIPT_DIR/env-x86_64.sh"

FORCE=0
INSTALL_RUNTIME=0
APPLY_PATCHES=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    --install-runtime) INSTALL_RUNTIME=1; shift ;;
    --apply-patches) APPLY_PATCHES=1; shift ;;
    -h | --help)
      cat <<EOF
Usage: $(basename "$0") [--force] [--install-runtime] [--apply-patches]

Rebuild MoltenVK from \$MOLTENVK_SRC after Cyder source patches, install into
GRAPHICS_INSTALL and WINE_INSTALL (minOS floor from .env).

  --force            Remove prior Package/Latest output and rebuild
  --install-runtime  Also copy into ~/.cyder/runtime and Application Support engines
  --apply-patches    Apply missing Cyder MoltenVK patches under patches/
EOF
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ -f "$MOLTENVK_SRC/MoltenVK/MoltenVK/GPUObjects/MVKSync.mm" ]] || {
  echo "Missing MoltenVK sources at $MOLTENVK_SRC" >&2
  exit 1
}

apply_one() {
  local patch="$1"
  local marker="$2"
  local file="$3"
  if grep -Fq "$marker" "$file"; then
    echo "Already applied: $(basename "$patch")"
    return 0
  fi
  if (( APPLY_PATCHES )); then
    echo "Applying $(basename "$patch")..."
    patch --forward --batch -p1 -d "$MOLTENVK_SRC" < "$patch"
  else
    echo "Source lacks marker for $(basename "$patch")." >&2
    echo "  marker: $marker" >&2
    echo "Apply with: $0 --apply-patches" >&2
    echo "  or: patch -p1 -d \$MOLTENVK_SRC < $patch" >&2
    exit 1
  fi
}

apply_one \
  "$ROOT/patches/cyder-moltenvk-timeline-wait-poll.patch" \
  'Cyder: each -[MTLSharedEvent notifyListener' \
  "$MOLTENVK_SRC/MoltenVK/MoltenVK/GPUObjects/MVKSync.mm"

apply_one \
  "$ROOT/patches/cyder-moltenvk-present-autoreleasepool.patch" \
  'Cyder: Metal scheduled-handler threads' \
  "$MOLTENVK_SRC/MoltenVK/MoltenVK/GPUObjects/MVKImage.mm"

dylib_out="$MOLTENVK_SRC/Package/Latest/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib"
if (( FORCE )); then
  echo "Removing previous Package output..."
  rm -rf "$MOLTENVK_SRC/Package/Latest"
fi

echo "Building MoltenVK (arch=x86_64, MACOSX_DEPLOYMENT_TARGET=$MACOSX_DEPLOYMENT_TARGET)..."
arch -x86_64 env \
  DEVELOPER_DIR="$(xcode-select -p)" \
  MACOSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
  xcodebuild build \
    -project "$MOLTENVK_SRC/MoltenVKPackaging.xcodeproj" \
    -scheme "MoltenVK Package (macOS only)" \
    -destination "generic/platform=macOS" \
    ARCHS=x86_64 \
    ONLY_ACTIVE_ARCH=NO \
    MACOSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
    -quiet

[[ -f "$dylib_out" ]] || {
  echo "Build failed: missing $dylib_out" >&2
  exit 1
}

minos="$(otool -l "$dylib_out" | awk '/minos/{print $2; exit}')"
echo "Built $dylib_out (minos=${minos:-unknown})"
if [[ -n "${minos:-}" ]]; then
  python3 - "$minos" "$MACOSX_DEPLOYMENT_TARGET" <<'PY'
import sys
built, floor = sys.argv[1], sys.argv[2]
def parts(v):
    return tuple(int(x) for x in v.split("."))
if parts(built) > parts(floor):
    raise SystemExit(f"Refusing install: minos {built} > floor {floor}")
PY
fi

mkdir -p "$GRAPHICS_INSTALL/lib"
cp -p "$dylib_out" "$GRAPHICS_INSTALL/lib/libMoltenVK.dylib"
chmod 755 "$GRAPHICS_INSTALL/lib/libMoltenVK.dylib"
cat >"$GRAPHICS_INSTALL/version" <<EOF
graphics crossover-foss+cyder-moltenvk-patches
moltenvk cyder-timeline-wait-poll+present-autoreleasepool
arch x86_64
source crossover-foss
minos ${minos:-unknown}
patch cyder-moltenvk-timeline-wait-poll
patch cyder-moltenvk-present-autoreleasepool
EOF

unix_dest="$WINE_INSTALL/lib/wine/x86_64-unix/libMoltenVK.dylib"
mkdir -p "$(dirname "$unix_dest")"
# Drop diagnostic re-export shim if present beside the install target.
if [[ -f "$(dirname "$unix_dest")/libMoltenVK.real.dylib" ]]; then
  rm -f "$(dirname "$unix_dest")/libMoltenVK.real.dylib"
fi
cp -p "$dylib_out" "$unix_dest"
chmod 755 "$unix_dest"
echo "Installed -> $GRAPHICS_INSTALL/lib/libMoltenVK.dylib"
echo "Installed -> $unix_dest"

install_into_tree() {
  local tree="$1"
  local dir="$tree/lib/wine/x86_64-unix"
  local dest="$dir/libMoltenVK.dylib"
  [[ -d "$dir" ]] || return 0
  # Undo cyder-mvk-autorelease experiment shim if present.
  if [[ -f "$dir/libMoltenVK.real.dylib" ]]; then
    rm -f "$dir/libMoltenVK.real.dylib"
    echo "Removed diagnostic shim -> $dir/libMoltenVK.real.dylib"
  fi
  cp -p "$dylib_out" "$dest"
  chmod 755 "$dest"
  codesign --force -s - "$dest" >/dev/null 2>&1 || true
  echo "Installed runtime -> $dest"
}

if (( INSTALL_RUNTIME )); then
  shopt -s nullglob
  for tree in \
    "$HOME/.cyder/runtime"/*/ \
    "$HOME/.cyder/runtime/Engines"/*/ \
    "$HOME/Library/Application Support/Cyder/runtime"/*/ \
    "$HOME/Library/Application Support/Cyder/engines"/*/ ; do
    install_into_tree "${tree%/}"
  done
  shopt -u nullglob
fi

echo "Done. Restart Cyder / the game, select DXVK, confirm Ports stay flat."
