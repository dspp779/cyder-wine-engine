#!/usr/bin/env bash
# Build MoltenVK (and optionally VKD3D) for x86_64 Wine.
#
# Phase 1 (default): MoltenVK only — enough for Wine configure / winevulkan / runtime dlopen.
# Phase 2 (--with-vkd3d): VKD3D PE build — not wired yet; see docs in this script's --help.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DRY_RUN=0
INSTALL_DEPS=0
WITH_VKD3D=0
CX_VERSION="${CX_VERSION:-26}"
ARCHS="${ARCHS:-x86_64}"

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '+'
    for arg in "$@"; do
      printf ' %q' "$arg"
    done
    printf '\n'
  else
    "$@"
  fi
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Build graphics dependencies from pinned upstream MoltenVK sources (VKD3D optional).

Installs into \$GRAPHICS_INSTALL (default: install/graphics-cx<ver>-x86_64/lib).

Options:
  --cx 25|26           CrossOver release (default: 26)
  --moltenvk-source S  upstream (default), crossover-foss, or custom
  --install-deps       Install MoltenVK build tools via .brew-x86 (cmake, python3)
  --with-vkd3d         Also build VKD3D from CX sources (not implemented yet)
  --archs ARCH         macOS arch for MoltenVK dylib (default: x86_64 for Rosetta Wine)
  --dry-run            Print commands without executing
  -h, --help           Show this help

Typical flow (after prepare-build-deps.sh / build-wine --prepare-only):

  bash scripts/build-graphics-stack.sh --cx 26 --install-deps
  bash scripts/build-graphics-stack.sh --cx 26

Then build Wine with CrossOver Vulkan:

  bash scripts/build-wine.sh --cx 26 --with-vulkan --vulkan-source crossover

Notes:
  - MoltenVK 1.4.0 is fetched and SHA-256 verified by ensure-moltenvk-source.sh.
    Set MOLTENVK_SOURCE=crossover-foss only for an explicit legacy comparison.
  - MoltenVK fetchDependencies may download upstream deps (network required).
  - Requires Xcode (xcodebuild). On Apple Silicon, MoltenVK is built under Rosetta
    as x86_64 to match the x86_64 Wine prefix.
  - VKD3D needs Wine PE toolchain integration; use --with-vkd3d only when phase 2 lands.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --install-deps) INSTALL_DEPS=1 ;;
    --with-vkd3d) WITH_VKD3D=1 ;;
    --moltenvk-source)
      [[ $# -ge 2 ]] || { echo "Missing value for --moltenvk-source" >&2; exit 1; }
      MOLTENVK_SOURCE="$2"
      shift
      ;;
    --cx)
      CX_VERSION="$2"
      shift
      ;;
    --archs)
      ARCHS="$2"
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

case "$CX_VERSION" in
  25 | 26) ;;
  *)
    echo "Unknown --cx value: $CX_VERSION (expected 25 or 26)" >&2
    exit 1
    ;;
esac

export CX_VERSION
export MOLTENVK_SOURCE="${MOLTENVK_SOURCE:-upstream}"
source "$SCRIPT_DIR/env-x86_64.sh"

PREPARE_ARGS=(--cx "$CX_VERSION")
[[ "$DRY_RUN" -eq 1 ]] && PREPARE_ARGS+=(--dry-run)
"$SCRIPT_DIR/prepare-build-deps.sh" "${PREPARE_ARGS[@]}"

if [[ "$INSTALL_DEPS" -eq 1 ]]; then
  if [[ ! -x "$HOMEBREW_PREFIX/bin/brew" && "$DRY_RUN" -eq 0 ]]; then
    echo "Missing $HOMEBREW_PREFIX/bin/brew; run: bash scripts/build-wine.sh --bootstrap-brew" >&2
    exit 1
  fi
  # MoltenVK README: cmake + python3; ninja optional.
  run brew_x86 install cmake python3
fi

require_xcode() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "+ require xcodebuild"
    return 0
  fi
  if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "xcodebuild not found; install Xcode or Command Line Tools" >&2
    exit 1
  fi
}

moltenvk_dylib_path() {
  printf '%s/Package/Latest/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib\n' "$MOLTENVK_SRC"
}

ensure_moltenvk_source() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    bash "$SCRIPT_DIR/ensure-moltenvk-source.sh" --dry-run
  else
    bash "$SCRIPT_DIR/ensure-moltenvk-source.sh"
  fi
}

apply_capability_patch() {
  local patch_file="$SCRIPT_DIR/../patches/cyder-moltenvk-crossover-capability-hacks.patch"
  local marker_file="$MOLTENVK_SRC/MoltenVK/MoltenVK/GPUObjects/MVKDevice.mm"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "+ patch -p1 -d $MOLTENVK_SRC < $patch_file"
  elif grep -Fq '_features.pipelineStatisticsQuery = true;' "$marker_file"; then
    echo "Already applied: $(basename "$patch_file")"
  else
    patch --forward --batch -p1 -d "$MOLTENVK_SRC" < "$patch_file"
    echo "Applied $(basename "$patch_file")"
  fi
}

apply_source_patch() {
  local patch_file="$1" marker="$2" source_file="$3"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "+ patch -p1 -d $MOLTENVK_SRC < $SCRIPT_DIR/../patches/$patch_file"
  elif grep -Fq "$marker" "$source_file"; then
    echo "Already applied: $patch_file"
  else
    if patch --forward --batch -p1 -d "$MOLTENVK_SRC" < "$SCRIPT_DIR/../patches/$patch_file"; then
      echo "Applied $patch_file"
    elif grep -Fq "$marker" "$source_file"; then
      echo "Applied compatible hunks of $patch_file (source variant)"
    else
      echo "Failed to apply $patch_file" >&2
      return 1
    fi
  fi
}

build_moltenvk() {
  local dylib marker
  dylib="$(moltenvk_dylib_path)"
  marker="$GRAPHICS_INSTALL/lib/libMoltenVK.dylib"

  if [[ -f "$marker" && -f "$GRAPHICS_INSTALL/version" \
      && "$(grep -F "source $MOLTENVK_SOURCE" "$GRAPHICS_INSTALL/version" 2>/dev/null || true)" == "source $MOLTENVK_SOURCE" \
      && ("$MOLTENVK_SOURCE" != "upstream" || "$(grep -F "moltenvk $MOLTENVK_VERSION" "$GRAPHICS_INSTALL/version" 2>/dev/null || true)" == "moltenvk $MOLTENVK_VERSION") \
      && "$DRY_RUN" -eq 0 ]]; then
    echo "MoltenVK already installed at $marker"
    return 0
  fi

  if [[ -f "$marker" && "$DRY_RUN" -eq 0 ]]; then
    echo "Ignoring unverified MoltenVK at $marker (missing $MOLTENVK_SOURCE/$MOLTENVK_VERSION manifest)." >&2
  fi

  ensure_moltenvk_source
  apply_capability_patch
  apply_source_patch \
    cyder-moltenvk-timeline-wait-poll.patch \
    'Cyder: each -[MTLSharedEvent notifyListener' \
    "$MOLTENVK_SRC/MoltenVK/MoltenVK/GPUObjects/MVKSync.mm"
  apply_source_patch \
    cyder-moltenvk-present-autoreleasepool.patch \
    'Cyder: Metal scheduled-handler threads' \
    "$MOLTENVK_SRC/MoltenVK/MoltenVK/GPUObjects/MVKImage.mm"

  require_xcode

  # Release archives do not vendor External/SPIRV-Cross; CrossOver FOSS
  # archives sometimes do. Cache either copy before fetchDependencies runs —
  # it does `rm -rf SPIRV-Cross` then symlinks SPIRV_CROSS_ROOT.
  local spirv_cross_vendored="$MOLTENVK_SRC/External/SPIRV-Cross"
  local spirv_cross_rev spirv_cross_cache
  if [[ "$DRY_RUN" -eq 1 && ! -f "$MOLTENVK_SRC/ExternalRevisions/SPIRV-Cross_repo_revision" ]]; then
    spirv_cross_rev="<pinned-revision>"
    echo "+ read ExternalRevisions/SPIRV-Cross_repo_revision"
  else
    spirv_cross_rev="$(
      tr -d '[:space:]' <"$MOLTENVK_SRC/ExternalRevisions/SPIRV-Cross_repo_revision"
    )"
  fi
  spirv_cross_cache="$BUILD_DIR/moltenvk-deps/SPIRV-Cross-$spirv_cross_rev"
  if [[ ! -f "$spirv_cross_cache/spirv_cross.hpp" && ! -f "$spirv_cross_cache/spirv_cross_c.cpp" \
      && ! -d "$spirv_cross_cache/include" ]]; then
    if [[ -f "$spirv_cross_vendored/spirv_cross.hpp" || -f "$spirv_cross_vendored/spirv_cross_c.cpp" \
        || -d "$spirv_cross_vendored/include" ]]; then
      echo "Caching vendored SPIRV-Cross -> $spirv_cross_cache"
      run rm -rf "$spirv_cross_cache"
      run mkdir -p "$(dirname "$spirv_cross_cache")"
      run cp -a "$spirv_cross_vendored" "$spirv_cross_cache"
    else
      echo "Caching KhronosGroup/SPIRV-Cross @$spirv_cross_rev (fallback)..."
      run rm -rf "$spirv_cross_cache"
      run mkdir -p "$(dirname "$spirv_cross_cache")"
      run git clone https://github.com/KhronosGroup/SPIRV-Cross.git "$spirv_cross_cache"
      run git -C "$spirv_cross_cache" checkout --detach "$spirv_cross_rev"
    fi
  else
    echo "Using cached SPIRV-Cross at $spirv_cross_cache"
  fi

  echo "Fetching MoltenVK external dependencies (may need network)..."
  run bash -c "cd '$MOLTENVK_SRC' && ./fetchDependencies --macos --spirv-cross-root '$spirv_cross_cache'"

  # Release archives and CX tarballs have no moltenvk .git;
  # gen_moltenvk_rev_hdr.sh would otherwise bake the parent Cyder/engine
  # commit into mvkRevString.
  local pinned_mvk=""
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "+ python3 $SCRIPT_DIR/pin-moltenvk-git-rev.py $MOLTENVK_SRC"
  else
    pinned_mvk="$(python3 "$SCRIPT_DIR/pin-moltenvk-git-rev.py" "$MOLTENVK_SRC")"
    echo "MoltenVK rev string pinned to $pinned_mvk (not parent git HEAD)"
  fi

  echo "Building MoltenVK $MOLTENVK_VERSION (arch=$ARCHS, source=$MOLTENVK_SOURCE)..."
  run arch -x86_64 env \
    DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)" \
    xcodebuild build \
      -project "$MOLTENVK_SRC/MoltenVKPackaging.xcodeproj" \
      -scheme "MoltenVK Package (macOS only)" \
      -destination "generic/platform=macOS" \
      ARCHS="$ARCHS" \
      ONLY_ACTIVE_ARCH=NO \
      -quiet

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "+ install $dylib -> $GRAPHICS_INSTALL/lib/libMoltenVK.dylib"
    return 0
  fi

  [[ -f "$dylib" ]] || {
    echo "MoltenVK build failed: missing $dylib" >&2
    exit 1
  }

  run mkdir -p "$GRAPHICS_INSTALL/lib"
  run cp -p "$dylib" "$marker"
  run chmod 755 "$marker"

  cat > "$GRAPHICS_INSTALL/version" <<EOF
graphics moltenvk-cyder
moltenvk ${pinned_mvk:-$MOLTENVK_VERSION}
arch ${ARCHS}
source ${MOLTENVK_SOURCE}
capability-patch cyder-moltenvk-crossover-capability-hacks
patch cyder-moltenvk-timeline-wait-poll
patch cyder-moltenvk-present-autoreleasepool
EOF
  echo "Installed MoltenVK -> $marker"
}

build_vkd3d_crossover() {
  echo "VKD3D build from CrossOver sources is not implemented yet (phase 2)." >&2
  echo "Wine D3D12 needs vkd3d PE DLLs installed into the Wine prefix;" >&2
  echo "see sources/vkd3d/gitlab/build-mac in the CX tarball for CI reference." >&2
  exit 1
}

build_moltenvk

if [[ "$WITH_VKD3D" -eq 1 ]]; then
  build_vkd3d_crossover
fi

echo "Graphics stack build complete: $GRAPHICS_INSTALL"
