#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/assert.sh"

build_script="$(<"$ROOT/scripts/build-wine.sh")"
release_manifest="$(<"$ROOT/config/engine-release.json")"
assert_contains "$build_script" "--maplestory" \
  "build should expose the MapleStory production patch option"
assert_contains "$build_script" "D3DMetal-neutral" \
  "build contract should keep MapleStory independent of MoltenVK"

patches=(
  a6-final-same-view-backing-sync.patch
  maplestory-cx26-message-wait-handoff.patch
  maplestory-cx26-core.patch
  maplestory-cx26-window-resizable-flag.patch
  maplestory-cx26-tmp-module-name.patch
  maplestory-cx26-dbghelp-dwarf-guard.patch
  maplestory-cx26-d3d11-shared-texture-test.patch
  maplestory-cx26-d3dmetal-legacy-surface.patch
  maplestory-cx26-plain-metal-layer.patch
  maplestory-cx26-d3d11-full-clear.patch
  maplestory-cx26-dxgi-shared-handle.patch
  maplestory-cx26-texture-user-memory-reload.patch
  maplestory-cx26-blackxchg-foreground.patch
  maplestory-cx26-fullscreen-restore.patch
  maplestory-cx26-no-sched-yield.patch
  maplestory-cx26-file-cache-adaptive.patch
  maplestory-cx26-file-cache-capacity.patch
)

for patch_name in "${patches[@]}"; do
  [[ -f "$ROOT/patches/$patch_name" ]] || {
    echo "ASSERT failed: missing MapleStory patch $patch_name" >&2
    exit 1
  }
  assert_contains "$release_manifest" "$patch_name" \
    "release manifest should record $patch_name"
done

dry_run="$(bash "$ROOT/scripts/build-wine.sh" --cx 26 --maplestory --dry-run --without-vulkan 2>&1 || true)"
assert_contains "$dry_run" "gstreamer-1.0" \
  "MapleStory build should require the isolated media stack"
assert_contains "$dry_run" "maplestory-cx26-d3d11-full-clear.patch" \
  "MapleStory build should apply the full ClearView stack"
assert_contains "$dry_run" "--without-vulkan" \
  "D3DMetal-first MapleStory build should work without Vulkan"
no_sched_patch="$(<"$ROOT/patches/maplestory-cx26-no-sched-yield.patch")"
assert_contains "$no_sched_patch" "is_maplestory_process" \
  "the scheduler compatibility patch should guard on MapleStory.exe"
assert_contains "$no_sched_patch" "STATUS_NO_YIELD_PERFORMED" \
  "the scheduler compatibility patch should keep the MapleStory no-yield result"
if [[ "$dry_run" == *"libMoltenVK.dylib"* ]]; then
  echo "ASSERT failed: D3DMetal-first MapleStory build must not require MoltenVK" >&2
  exit 1
fi

if cx25_output="$(bash "$ROOT/scripts/build-wine.sh" --cx 25 --maplestory --dry-run --without-vulkan 2>&1)"; then
  echo "ASSERT failed: --cx 25 must be rejected" >&2
  exit 1
else
  assert_contains "$cx25_output" "CX25 support was retired; this tree only builds CrossOver 26." \
    "CX25 source builds must be retired"
fi

archive="$ROOT/tools/archives/crossover-sources-26.3.0.tar.gz"
if [[ -f "$archive" ]]; then
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/cyder-maplestory-patches.XXXXXX")"
  trap 'rm -rf "$tmp"' EXIT
  tar -xzf "$archive" -C "$tmp"
  wine_src="$tmp/sources/wine"
  for patch_name in "${patches[@]}"; do
    patch --forward --batch -s -p1 -d "$wine_src" < "$ROOT/patches/$patch_name"
  done
  echo "PASS: clean CX26.3.0 source accepts the MapleStory patch stack"
else
  echo "SKIP: CX26.3.0 source archive is not available"
fi

echo "PASS test-maplestory-patch-stack"
