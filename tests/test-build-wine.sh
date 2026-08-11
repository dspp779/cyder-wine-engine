#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/assert.sh"

build_script="$(<"$ROOT/scripts/build-wine.sh")"
assert_contains "$build_script" "if (!func) break;" \
  "build should recognize the upstream frame-walk guard after the Cyder page-fault patch rewrites its context"

output="$(bash "$ROOT/scripts/build-wine.sh" --cx 26 --dry-run --bootstrap-brew --install-deps 2>&1 || true)"

if [[ "$output" != *"Homebrew/brew"* && "$output" != *"Homebrew already present"* ]]; then
  echo "ASSERT_CONTAINS failed: dry-run should bootstrap Homebrew or report it already present" >&2
  exit 1
fi
if [[ "$output" != *"Extracting llvm-mingw"* && "$output" != *"llvm-mingw already present"* ]]; then
  echo "ASSERT failed: dry-run should prepare llvm-mingw" >&2
  exit 1
fi
if [[ "$output" != *"crossover-sources-26.3.0.tar.gz"* && "$output" != *"CX26 sources already present"* ]]; then
  echo "ASSERT failed: dry-run should prepare CX26 sources" >&2
  exit 1
fi
assert_contains "$output" "brew_x86 install" "dry-run should install deps via project brew_x86"
assert_contains "$output" "brew_x86_install_runtime" \
  "dry-run should rebuild runtime formulae from source for the product floor"
assert_contains "$output" "PKG_CONFIG_PATH=" "dry-run configure must set PKG_CONFIG_PATH for keg-only deps"
assert_contains "$output" "require pkg-config freetype2" "dry-run should check for x86_64 freetype2"
assert_contains "$output" "ensure" "dry-run should ensure bzip2.pc exists"
assert_contains "$output" "build/cx26/sources/wine" "dry-run should use CX26 source tree"
if [[ "$output" == *"cyder-compatdb-runtime.patch"* ]]; then
  echo "ASSERT failed: build must leave the original CrossOver ntdll unchanged for CompatDB" >&2
  exit 1
fi
if [[ "$output" == *"cyder-steam-webhelper-compat.patch"* ]]; then
  echo "ASSERT failed: build must not carry the old executable-specific Steam patch" >&2
  exit 1
fi
assert_contains "$output" "$ROOT/patches/obsolete/cyder-ntdll-frame-walk-guard.patch" \
  "build should migrate an existing combined frame-walk patch"
assert_contains "$output" "superseded by: $ROOT/patches/cyder-ntdll-frame-walk-page-fault-guard.patch" \
  "build should recognize the fully migrated two-patch source state"
assert_contains "$output" "superseded by: $ROOT/patches/wine-11.1-rtlwalkframechain-null-function.patch" \
  "build should recognize a partially migrated incremental source tree"
assert_contains "$output" "$ROOT/patches/wine-11.1-rtlwalkframechain-null-function.patch" \
  "build should backport the upstream x64 null-function stop"
assert_contains "$output" "$ROOT/patches/cyder-ntdll-frame-walk-page-fault-guard.patch" \
  "build should guard x86_64 frame walking against invalid unwind metadata"
assert_contains "$output" "$ROOT/patches/cyder-wineserver-sock-reselect-pseudo-fd.patch" \
  "build should stop sock_reselect() from touching an uninitialized socket's pseudo-fd"
assert_contains "$output" "$ROOT/patches/cyder-wineserver-poll-slot-guard.patch" \
  "build should keep an inconsistent poll slot from aborting wineserver"
assert_contains "$output" "$ROOT/patches/cyder-wineserver-exit-diagnostics.patch" \
  "build should leave wineserver exit breadcrumbs for silent death diagnosis"
assert_contains "$output" "$ROOT/patches/cyder-wineserver-fd-reselect-async-null-ops.patch" \
  "build should guard fd_reselect_async against NULL fd_ops"
assert_contains "$output" "$ROOT/patches/cyder-wineserver-sock-rebind-async-fd.patch" \
  "build should rebind weak async->fd when sock fd is replaced"
assert_contains "$output" "$ROOT/patches/cyder-wineserver-free-async-queue-null-fd.patch" \
  "build should guard free_async_queue against NULL async->fd"
assert_contains "$output" "$ROOT/patches/cyder-wineserver-pipe-end-disconnect-null-fd.patch" \
  "build should guard pipe_end_disconnect against NULL fd"
assert_contains "$output" "$ROOT/patches/cyder-ntdll-qdo-optnone-NtQueryDirectoryObject.patch" \
  "build should apply NtQueryDirectoryObject optnone leave-game bandage"
assert_contains "$output" "$ROOT/patches/cyder-ntdll-query-directory-object-trace.patch" \
  "build should remove obsolete QDO TRACE before applying optnone"
# Tarball trees skip make_*; git checkouts regenerate.
if [[ -e "$ROOT/build/cx26/sources/wine/.git" ]]; then
  assert_contains "$output" "./tools/make_requests" "dry-run should rebuild Wine generated files"
else
  assert_contains "$output" "Non-git wine tree" "dry-run should skip make_* on tarball sources"
fi
assert_contains "$output" "--enable-win64" "dry-run should enable win64 host"
assert_contains "$output" "--enable-archs=i386" "dry-run must build 32-bit PE for BlueCG (PE32)"
assert_contains "$output" "x86_64" "dry-run archs should include x86_64 PE"
assert_contains "$output" "--with-mingw=llvm-mingw" "dry-run should use llvm-mingw"
assert_contains "$output" "--disable-tests" "runtime builds should skip Wine regression tests"
assert_contains "$output" "install/wine-cx26-x86_64" "dry-run should install to CX26 prefix"
assert_contains "$output" "make -j" "dry-run should show the compile step"
assert_contains "$output" "make install" "dry-run should show the install step"
assert_contains "$output" "build-cyder-cxcompatdb.sh" \
  "dry-run should build the standalone cxcompatdb after Wine install"
assert_contains "$output" "bundle-wine-dylibs.sh" "dry-run should bundle relocatable dylibs after install"
assert_contains "$output" "--without-vulkan" "default dry-run should disable Vulkan"
assert_contains "$output" "mmacosx-version-min=" \
  "configure/make must bake -mmacosx-version-min so incremental builds keep the product floor"
assert_contains "$output" "host minOS: MACOSX_DEPLOYMENT_TARGET=" \
  "dry-run should report the resolved host minOS"

output_vk_homebrew="$(bash "$ROOT/scripts/build-wine.sh" --cx 26 --dry-run --install-deps --with-vulkan --vulkan-source homebrew 2>&1 || true)"
assert_contains "$output_vk_homebrew" "molten-vk" "homebrew vulkan deps should include molten-vk"
if [[ "$output_vk_homebrew" == *"require libMoltenVK.dylib"* ]]; then
  assert_contains "$output_vk_homebrew" "require libMoltenVK.dylib" "with-vulkan homebrew should check MoltenVK when missing"
else
  assert_contains "$output_vk_homebrew" "opt/molten-vk/lib" "with-vulkan homebrew should add MoltenVK to LIBRARY_PATH when present"
fi

output_vk_crossover="$(bash "$ROOT/scripts/build-wine.sh" --cx 26 --dry-run --install-deps --with-vulkan --vulkan-source crossover 2>&1 || true)"
assert_contains "$output_vk_crossover" "cmake" "crossover vulkan deps should include cmake"
assert_contains "$output_vk_crossover" "build-graphics-stack.sh" "crossover path should reference graphics stack build"
assert_contains "$output_vk_crossover" "require" "crossover path should check graphics install"
assert_contains "$output_vk_crossover" "graphics-cx26-x86_64" "crossover path should use graphics prefix"

output_cx25="$(bash "$ROOT/scripts/build-wine.sh" --cx 25 --prepare-only --dry-run 2>&1 || true)"
if [[ "$output_cx25" != *"crossover-sources-25.1.1.tar.gz"* && "$output_cx25" != *"CX25 sources already present"* ]]; then
  echo "ASSERT failed: CX25 prepare should reference CX25 archive" >&2
  exit 1
fi
assert_contains "$output_cx25" "build/cx25" "CX25 prepare should target cx25 tree"

if [[ -d "$ROOT/build/cx26/sources/wine" ]]; then
  output_cx25_build="$(
    WINE_SRC="$ROOT/build/cx26/sources/wine" \
    WINE_INSTALL="${TMPDIR:-/tmp}/cyder-test-wine-cx25" \
      bash "$ROOT/scripts/build-wine.sh" --cx 25 --dry-run --without-vulkan 2>&1 || true
  )"
  if [[ "$output_cx25_build" == *"rtlwalkframechain-null-function.patch"* ||
        "$output_cx25_build" == *"ntdll-frame-walk-page-fault-guard.patch"* ||
        "$output_cx25_build" == *"obsolete/cyder-ntdll-frame-walk-guard.patch"* ||
        "$output_cx25_build" == *"cyder-wineserver-sock-reselect-pseudo-fd.patch"* ||
        "$output_cx25_build" == *"cyder-wineserver-poll-slot-guard.patch"* ||
        "$output_cx25_build" == *"cyder-wineserver-exit-diagnostics.patch"* ||
        "$output_cx25_build" == *"cyder-wineserver-fd-reselect-async-null-ops.patch"* ||
        "$output_cx25_build" == *"cyder-wineserver-sock-rebind-async-fd.patch"* ||
        "$output_cx25_build" == *"cyder-wineserver-free-async-queue-null-fd.patch"* ||
        "$output_cx25_build" == *"cyder-wineserver-pipe-end-disconnect-null-fd.patch"* ||
        "$output_cx25_build" == *"cyder-ntdll-query-directory-object-trace.patch"* ||
        "$output_cx25_build" == *"cyder-ntdll-qdo-optnone-NtQueryDirectoryObject.patch"* ]]; then
    echo "ASSERT failed: CX25 builds must not migrate or apply CX26-only patches" >&2
    exit 1
  fi
fi


echo "PASS test-build-wine"
