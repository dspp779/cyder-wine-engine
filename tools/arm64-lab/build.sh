#!/usr/bin/env bash
# CX26 ARM64 compile experiment, not a shipping engine or an x86 game runtime.
set -euo pipefail
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export OGOM="$(cd "$LAB_DIR/../.." && pwd)"
EXPERIMENT="$OGOM/build/arm64-experimental-cx26"
ARCHIVE="$OGOM/tools/archives/crossover-sources-26.3.0.tar.gz"
ARCHIVE_SHA256=ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872
MODE="${1:---help}"
case "$MODE" in
 prepare|configure|build|install|all) ;;
 --help|-h)
  echo "Usage: bash tools/arm64-lab/build.sh {prepare|configure|build [make-target ...]|install|all}"
  echo "Requires existing CX26.3 archive, llvm-mingw, native Homebrew bison/pkgconf/freetype."
  echo "Outputs only to build/arm64-experimental-cx26 and install/wine-cx26-arm64-experimental."
  exit 0 ;;
 *) echo "Unknown mode: $MODE" >&2; exit 2 ;;
esac
shift
cd "$OGOM"
[[ "$(uname -m)" == arm64 ]] || { echo 'Run this script in an ARM64 shell.' >&2; exit 1; }
export CX_VERSION=26
export MACOSX_DEPLOYMENT_TARGET=11.0
# Read the project environment, then explicitly replace its x86 build defaults.
source scripts/env-x86_64.sh
export ARCH_CMD='arch -arm64'
export WINE_SRC="$EXPERIMENT/source/sources/wine"
export WINE_INSTALL="$OGOM/install/wine-cx26-arm64-experimental"
export PATH="$LLVM_MINGW/bin:/opt/homebrew/opt/bison/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
unset DYLD_LIBRARY_PATH DYLD_FALLBACK_LIBRARY_PATH LIBRARY_PATH CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH
export PKG_CONFIG=/opt/homebrew/bin/pkg-config
export PKG_CONFIG_PATH=/opt/homebrew/lib/pkgconfig:/opt/homebrew/opt/freetype/lib/pkgconfig:/opt/homebrew/opt/gnutls/lib/pkgconfig
MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
export PKG_CONFIG_LIBDIR="$PKG_CONFIG_PATH:/opt/homebrew/share/pkgconfig:/opt/homebrew/Library/Homebrew/os/mac/pkgconfig/$MACOS_MAJOR:$(xcrun --show-sdk-path)/usr/lib/pkgconfig"
export CC='/usr/bin/clang -arch arm64'
export CXX='/usr/bin/clang++ -arch arm64'
export CFLAGS="-O2 -g $CYDER_MACOSX_VERSION_MIN_FLAG"
export OBJCFLAGS="$CFLAGS"
export LDFLAGS="$CYDER_MACOSX_VERSION_MIN_FLAG"
export BISON=/opt/homebrew/opt/bison/bin/bison
JOBS="${ARM64LAB_JOBS:-6}"
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || { echo 'Invalid ARM64LAB_JOBS' >&2; exit 2; }
mkdir -p "$EXPERIMENT/logs" "$EXPERIMENT/build"
apply_patch_once() {
 local patch_file="$1"
 if patch --dry-run --forward -d "$WINE_SRC" -p1 < "$patch_file" >/dev/null 2>&1; then
  patch --forward -d "$WINE_SRC" -p1 < "$patch_file"
 elif patch --dry-run -R -d "$WINE_SRC" -p1 < "$patch_file" >/dev/null 2>&1; then
  echo "Already applied: $patch_file"
 else
  echo "Patch does not match experimental source: $patch_file" >&2; exit 1
 fi
}
prepare() {
 [[ -f "$ARCHIVE" ]] || { echo "Missing $ARCHIVE" >&2; exit 1; }
 [[ "$(shasum -a 256 "$ARCHIVE" | cut -d' ' -f1)" == "$ARCHIVE_SHA256" ]] || {
  echo 'Unexpected source archive SHA256' >&2; exit 1;
 }
 if [[ ! -d "$WINE_SRC" ]]; then
  mkdir -p "$EXPERIMENT/source"
  tar -xzf "$ARCHIVE" -C "$EXPERIMENT/source" sources/wine
 fi
 shasum -a 256 "$ARCHIVE" > "$EXPERIMENT/logs/source.sha256"
 apply_patch_once "$LAB_DIR/cx26-arm64-d3dmetal-build-guards.patch"
 apply_patch_once "$OGOM/patches/w1-win32u-vulkan-soname.patch"
}
run_logged() {
 local stage="$1"; shift
 local logfile="$EXPERIMENT/logs/$stage.log"
 [[ ! -f "$logfile" ]] || cp "$logfile" "$logfile.previous"
 echo "$stage: $logfile"
 (cd "$EXPERIMENT/build"; "$@") > "$logfile" 2>&1 || {
  tail -50 "$logfile" >&2; return 1;
 }
}
configure() {
 prepare
 run_logged configure arch -arm64 "$WINE_SRC/configure" \
  --prefix="$WINE_INSTALL" --enable-win64 --enable-archs=aarch64 \
  --with-mingw --disable-tests --without-x --without-vulkan \
  --without-opengl --without-gstreamer
}
check_build_identity() {
 /usr/bin/grep -Fxq "prefix = $WINE_INSTALL" "$EXPERIMENT/build/Makefile"
 /usr/bin/grep -Fxq 'HOST_ARCH = aarch64' "$EXPERIMENT/build/Makefile"
}
build() { check_build_identity; run_logged build arch -arm64 make -j"$JOBS" "$@"; }
install() { check_build_identity; run_logged install arch -arm64 make install; }
case "$MODE" in
 prepare) prepare ;;
 configure) configure ;;
 build) build "$@" ;;
 install) install ;;
 all) configure; build; install ;;
esac
