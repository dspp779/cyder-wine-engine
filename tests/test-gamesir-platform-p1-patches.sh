#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/assert.sh"
ARCHIVE="${CX26_SOURCE_ARCHIVE:-$ROOT/tools/archives/crossover-sources-26.3.0.tar.gz}"
BUILD_SCRIPT="$(<"$ROOT/scripts/build-wine.sh")"
RELEASE_MANIFEST="$(<"$ROOT/config/engine-release.json")"

patches=(
  cyder-wineserver-macos-timezone-bias.patch
  cyder-wineserver-registry-fsync.patch
  cyder-winemac-hide-ime-only-klid.patch
  cyder-kernelbase-disk-free-space-fallback.patch
)

for patch_name in "${patches[@]}"; do
  patch_file="$ROOT/patches/$patch_name"
  assert test -f "$patch_file"
  assert_contains "$BUILD_SCRIPT" "apply_cyder_patch \"\$OGOM/patches/$patch_name\"" \
    "CX26 build should apply $patch_name"
  assert_contains "$RELEASE_MANIFEST" "$patch_name" \
    "release manifest should record $patch_name"
done

assert_contains "$(<"$ROOT/patches/cyder-wineserver-macos-timezone-bias.patch")" "get_timezone_bias" \
  "timezone patch should add get_timezone_bias"
assert_contains "$(<"$ROOT/patches/cyder-wineserver-macos-timezone-bias.patch")" "tz_minuteswest" \
  "timezone patch should use gettimeofday tz_minuteswest on Apple"
if [[ "$(<"$ROOT/patches/cyder-wineserver-macos-timezone-bias.patch")" == *"timezone_bias_initialized"* ]]; then
  echo "ASSERT failed: timezone patch must not use a process-lifetime DST cache" >&2
  exit 1
fi
assert_contains "$(<"$ROOT/patches/cyder-wineserver-registry-fsync.patch")" "fsync( fileno( f ) )" \
  "registry patch should fsync before close"
assert_contains "$(<"$ROOT/patches/cyder-winemac-hide-ime-only-klid.patch")" "leaks IME-only HKLs" \
  "IME patch should carry the KLID marker"
if [[ "$(<"$ROOT/patches/cyder-winemac-hide-ime-only-klid.patch")" != *"if (!CFEqual(type, kTISTypeKeyboardLayout)) lcid |= 0xe0000000"* ]]; then
  echo "ASSERT failed: IME patch should remove the 0xe0000000 IME-only KLID" >&2
  exit 1
fi
assert_contains "$(<"$ROOT/patches/cyder-kernelbase-disk-free-space-fallback.patch")" "retry a real mapped volume instead of inventing free space" \
  "disk-free patch should retry a real mapped volume"
if [[ "$(<"$ROOT/patches/cyder-kernelbase-disk-free-space-fallback.patch")" == *"200ull"* ]]; then
  echo "ASSERT failed: disk-free patch must not invent a fixed free-space size" >&2
  exit 1
fi

if [[ ! -f "$ARCHIVE" ]]; then
  echo "SKIP gamesir P1 patch round-trip: source archive not found at $ARCHIVE"
  exit 0
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cyder-gamesir-p1.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

tar -xzf "$ARCHIVE" -C "$TMP_DIR" \
  sources/wine/server/fd.c \
  sources/wine/server/registry.c \
  sources/wine/dlls/winemac.drv/keyboard.c \
  sources/wine/dlls/kernelbase/volume.c
SOURCE="$TMP_DIR/sources/wine"

fd_sha="$(shasum -a 256 "$SOURCE/server/fd.c" | awk '{print $1}')"
reg_sha="$(shasum -a 256 "$SOURCE/server/registry.c" | awk '{print $1}')"
kb_sha="$(shasum -a 256 "$SOURCE/dlls/winemac.drv/keyboard.c" | awk '{print $1}')"
vol_sha="$(shasum -a 256 "$SOURCE/dlls/kernelbase/volume.c" | awk '{print $1}')"

for patch_name in "${patches[@]}"; do
  patch --forward --batch -s -p1 -d "$SOURCE" < "$ROOT/patches/$patch_name"
done

rg -Fq 'get_timezone_bias' "$SOURCE/server/fd.c"
if rg -Fq 'tm = gmtime( &now );' "$SOURCE/server/fd.c"; then
  :
else
  echo "FAIL: non-Apple timezone path should still call gmtime" >&2
  exit 1
fi
rg -Fq 'fsync( fileno( f ) )' "$SOURCE/server/registry.c"
rg -Fq 'leaks IME-only HKLs' "$SOURCE/dlls/winemac.drv/keyboard.c"
if rg -Fq 'if (!CFEqual(type, kTISTypeKeyboardLayout)) lcid |= 0xe0000000' "$SOURCE/dlls/winemac.drv/keyboard.c"; then
  echo "FAIL: IME-only KLID encoding still present" >&2
  exit 1
fi
rg -Fq 'retry a real mapped volume instead of inventing free space' "$SOURCE/dlls/kernelbase/volume.c"
rg -Fq 'dos_drive_root_from_device_path' "$SOURCE/dlls/kernelbase/volume.c"
if rg -Fq '200ull' "$SOURCE/dlls/kernelbase/volume.c"; then
  echo "FAIL: invented disk-free constants still present" >&2
  exit 1
fi

# Reverse in apply order without relying on GNU tac.
for ((i = ${#patches[@]} - 1; i >= 0; i--)); do
  patch --reverse --batch -s -p1 -d "$SOURCE" < "$ROOT/patches/${patches[i]}"
done

assert_eq "$(shasum -a 256 "$SOURCE/server/fd.c" | awk '{print $1}')" "$fd_sha" \
  "timezone patch round-trip should restore fd.c"
assert_eq "$(shasum -a 256 "$SOURCE/server/registry.c" | awk '{print $1}')" "$reg_sha" \
  "registry patch round-trip should restore registry.c"
assert_eq "$(shasum -a 256 "$SOURCE/dlls/winemac.drv/keyboard.c" | awk '{print $1}')" "$kb_sha" \
  "IME patch round-trip should restore keyboard.c"
assert_eq "$(shasum -a 256 "$SOURCE/dlls/kernelbase/volume.c" | awk '{print $1}')" "$vol_sha" \
  "disk-free patch round-trip should restore volume.c"

echo "PASS gamesir platform P1 patch round-trip"
