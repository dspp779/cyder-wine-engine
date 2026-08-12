#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_SCRIPT="$ROOT/scripts/env-x86_64.sh"
ENSURE_SCRIPT="$ROOT/scripts/ensure-moltenvk-source.sh"
BUILD_SCRIPT="$ROOT/scripts/build-graphics-stack.sh"
REBUILD_SCRIPT="$ROOT/scripts/rebuild-moltenvk-cyder-patches.sh"
PATCH_FILE="$ROOT/patches/cyder-moltenvk-crossover-capability-hacks.patch"

assert_contains() {
  local text="$1" needle="$2" message="$3"
  if [[ "$text" != *"$needle"* ]]; then
    echo "FAIL $message: missing $needle" >&2
    exit 1
  fi
}

env_text="$(<"$ENV_SCRIPT")"
assert_contains "$env_text" 'MOLTENVK_VERSION="${MOLTENVK_VERSION:-1.4.0}"' \
  "default MoltenVK version should be 1.4.0"
assert_contains "$env_text" 'MOLTENVK_SOURCE="${MOLTENVK_SOURCE:-upstream}"' \
  "default MoltenVK source should be upstream"

patch_text="$(<"$PATCH_FILE")"
for marker in \
  '_features.geometryShader = true;' \
  '_features.pipelineStatisticsQuery = true;' \
  '_features.shaderCullDistance = true;'; do
  assert_contains "$patch_text" "$marker" "capability patch should contain $marker"
done
if [[ "$patch_text" == *"VK_EXT_transform_feedback"* || "$patch_text" == *"bitwise_not_causes_ice"* ]]; then
  echo "FAIL capability patch must not fake unsupported CrossOver-only features" >&2
  exit 1
fi

for script in "$BUILD_SCRIPT" "$REBUILD_SCRIPT"; do
  text="$(<"$script")"
  assert_contains "$text" 'cyder-moltenvk-crossover-capability-hacks.patch' \
    "$(basename "$script") should apply the capability patch"
done

ensure_text="$(<"$ENSURE_SCRIPT")"
assert_contains "$ensure_text" 'fc74aef926ee3cd473fe260a93819c09fdc939bff669271a587e9ebaa43d4306' \
  "source ensure should pin the MoltenVK 1.4.0 checksum"

dry_run="$(MOLTENVK_SOURCE=upstream MOLTENVK_VERSION=1.4.0 bash "$ENSURE_SCRIPT" --dry-run)"
assert_contains "$dry_run" 'build/moltenvk-1.4.0' \
  "source ensure dry-run should resolve the pinned MoltenVK source path"

echo "PASS MoltenVK 1.4.0 source and CrossOver capability patch checks"
