#!/usr/bin/env bash
# Build/install the MoltenVK timeline-wait poll shim (no Xcode required).
set -euo pipefail

TOOL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$TOOL_DIR/../.." && pwd)"
# shellcheck source=../../scripts/env-x86_64.sh
source "$ROOT/scripts/env-x86_64.sh"

SRC="$TOOL_DIR/cyder_mvk_timeline_wait_poll.m"
STAGE="$ROOT/build/cyder-mvk-timeline-wait-poll"
INSTALL_RUNTIME=0
UNDO=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-runtime) INSTALL_RUNTIME=1; shift ;;
    --undo) UNDO=1; shift ;;
    -h | --help)
      cat <<EOF
Usage: $(basename "$0") [--install-runtime] [--undo]

Builds an x86_64 re-export shim that polls vkGetSemaphoreCounterValue* for
vkWaitSemaphores* (avoids MTLSharedEvent notifyListener Mach-port leak).

  libMoltenVK.dylib       -> shim
  libMoltenVK.real.dylib  -> original MoltenVK

  --install-runtime  Also patch ~/.cyder/runtime/Engines/* and friends
  --undo             Restore libMoltenVK.real.dylib back to libMoltenVK.dylib
EOF
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

unix_lib() {
  printf '%s/lib/wine/x86_64-unix\n' "$1"
}

is_wait_poll_shim() {
  # Marker string embedded in the shim binary (see source comment header path).
  strings "$1" 2>/dev/null | grep -q 'cyder-moltenvk-timeline-wait-poll'
}

is_any_shim() {
  # Prior experiment shim or this wait-poll shim (re-exports .real).
  otool -L "$1" 2>/dev/null | grep -q 'libMoltenVK.real.dylib' ||
    strings "$1" 2>/dev/null | grep -Eq 'cyder-mvk-(wait-poll|autorelease):|cyder-moltenvk-timeline-wait-poll'
}

undo_tree() {
  local tree="$1"
  local dir real shim
  dir="$(unix_lib "$tree")"
  real="$dir/libMoltenVK.real.dylib"
  shim="$dir/libMoltenVK.dylib"
  [[ -d "$dir" ]] || return 0
  if [[ -f "$real" ]]; then
    mv -f "$real" "$shim"
    codesign --force -s - "$shim" >/dev/null 2>&1 || true
    echo "Restored $shim"
  else
    echo "No real dylib to restore in $dir" >&2
  fi
}

install_tree() {
  local tree="$1"
  local dir real tree_id local_shim sdk
  dir="$(unix_lib "$tree")"
  [[ -d "$dir" ]] || return 0
  real="$dir/libMoltenVK.real.dylib"

  if [[ ! -f "$real" ]]; then
    [[ -f "$dir/libMoltenVK.dylib" ]] || {
      echo "Skipping $tree (no libMoltenVK.dylib)" >&2
      return 0
    }
    if is_any_shim "$dir/libMoltenVK.dylib"; then
      echo "Shim present but missing $real in $dir; abort" >&2
      return 1
    fi
    cp -p "$dir/libMoltenVK.dylib" "$real"
    install_name_tool -id '@loader_path/libMoltenVK.real.dylib' "$real"
    codesign --force -s - "$real" >/dev/null 2>&1 || true
  elif is_any_shim "$dir/libMoltenVK.dylib" && ! is_wait_poll_shim "$dir/libMoltenVK.dylib"; then
    # Replace experiment shim; keep the same .real backup.
    echo "Replacing prior MoltenVK shim in $dir"
  fi

  mkdir -p "$STAGE"
  tree_id="$(printf '%s' "$tree" | shasum -a 256 | awk '{print substr($1,1,12)}')"
  local_shim="$STAGE/libMoltenVK-$tree_id.dylib"
  sdk="$(xcrun --sdk macosx --show-sdk-path)"
  arch -x86_64 clang -arch x86_64 \
    -mmacosx-version-min="${MACOSX_DEPLOYMENT_TARGET}" \
    -isysroot "$sdk" \
    -dynamiclib \
    -o "$local_shim" \
    "$SRC" \
    -Wl,-reexport_library,"$real" \
    -install_name '@loader_path/libMoltenVK.dylib'
  install_name_tool -change "$real" '@loader_path/libMoltenVK.real.dylib' "$local_shim"
  codesign --force -s - "$local_shim" >/dev/null 2>&1 || true

  cp -p "$local_shim" "$dir/libMoltenVK.dylib"
  chmod 755 "$dir/libMoltenVK.dylib" "$real"
  codesign --force -s - "$dir/libMoltenVK.dylib" >/dev/null 2>&1 || true
  echo "Installed wait-poll shim -> $dir/libMoltenVK.dylib"
  echo "  real backup             -> $real"
  otool -l "$dir/libMoltenVK.dylib" | awk '/minos/{print "  shim minos "$2; exit}'
  nm -gU "$dir/libMoltenVK.dylib" | rg 'WaitSemaphores|GetDeviceProcAddr' | head -8 || true
}

if (( UNDO )); then
  undo_tree "$WINE_INSTALL"
  if (( INSTALL_RUNTIME )); then
    shopt -s nullglob
    for tree in \
      "$HOME/.cyder/runtime/Engines"/*/ \
      "$HOME/.cyder/runtime"/*/ \
      "$HOME/Library/Application Support/Cyder/runtime"/*/ \
      "$HOME/Library/Application Support/Cyder/engines"/*/ ; do
      undo_tree "${tree%/}"
    done
    shopt -u nullglob
  fi
  exit 0
fi

install_tree "$WINE_INSTALL"
if (( INSTALL_RUNTIME )); then
  shopt -s nullglob
  for tree in \
    "$HOME/.cyder/runtime/Engines"/*/ \
    "$HOME/.cyder/runtime"/*/ \
    "$HOME/Library/Application Support/Cyder/runtime"/*/ \
    "$HOME/Library/Application Support/Cyder/engines"/*/ ; do
    install_tree "${tree%/}"
  done
  shopt -u nullglob
fi

echo "Done. Restart Cyder / game with DXVK; Ports should stay flat."
