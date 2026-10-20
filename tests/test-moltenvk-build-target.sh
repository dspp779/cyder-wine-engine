#!/usr/bin/env bash
# Exercise the full graphics entry point offline, including nested Xcode calls.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/assert.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-moltenvk-target.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
export TEST_MVK_ROOT="$tmp"
mkdir -p "$tmp/scripts" "$tmp/bin" "$tmp/source/ExternalRevisions" \
  "$tmp/build/moltenvk-deps/SPIRV-Cross-fixture"
cp "$ROOT/scripts/build-graphics-stack.sh" "$tmp/scripts/"
printf 'fixture\n' > "$tmp/source/ExternalRevisions/SPIRV-Cross_repo_revision"
touch "$tmp/build/moltenvk-deps/SPIRV-Cross-fixture/spirv_cross.hpp"
cat > "$tmp/scripts/env-x86_64.sh" <<'SH'
export BUILD_DIR="$TEST_MVK_ROOT/build"
export MOLTENVK_SRC="$TEST_MVK_ROOT/source"
export MOLTENVK_VERSION=1.2.10
export MOLTENVK_DEPLOYMENT_TARGET="${MOLTENVK_DEPLOYMENT_TARGET:-12.0}"
export GRAPHICS_INSTALL="$TEST_MVK_ROOT/install"
export MACOSX_DEPLOYMENT_TARGET=10.15
SH
for script in prepare-build-deps.sh ensure-moltenvk-source.sh; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/scripts/$script"
done
printf 'print("1.2.10")\n' > "$tmp/scripts/pin-moltenvk-git-rev.py"
cat > "$tmp/source/fetchDependencies" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
xcodebuild dependency
SH
cat > "$tmp/bin/arch" <<'SH'
#!/usr/bin/env bash
[[ "$1" == -x86_64 ]] || exit 9
shift
exec "$@"
SH
cat > "$tmp/bin/xcodebuild" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
grep -Fx "MACOSX_DEPLOYMENT_TARGET = $TEST_MVK_TARGET" "$XCODE_XCCONFIG_FILE"
grep -Fx 'ARCHS = x86_64' "$XCODE_XCCONFIG_FILE"
grep -Fx 'ONLY_ACTIVE_ARCH = NO' "$XCODE_XCCONFIG_FILE"
grep -F '#include ' "$XCODE_XCCONFIG_FILE"
[[ "$MACOSX_DEPLOYMENT_TARGET" == 10.15 ]] # the Wine floor is untouched
printf '%s %s\n' "$1" "$TEST_MVK_TARGET" >> "$TEST_MVK_ROOT/calls"
if [[ "$1" == build ]]; then
  dest="$TEST_MVK_ROOT/source/Package/Latest/MoltenVK/dynamic/dylib/macOS"
  mkdir -p "$dest"
  printf 'fixture\n' > "$dest/libMoltenVK.dylib"
fi
SH
chmod +x "$tmp/scripts/prepare-build-deps.sh" "$tmp/source/fetchDependencies" "$tmp/bin/"*
printf 'OTHER_CFLAGS = -DKEEP_CALLER_SETTING\n' > "$tmp/caller.xcconfig"
export XCODE_XCCONFIG_FILE="$tmp/caller.xcconfig"
export PATH="$tmp/bin:$PATH"
export TEST_MVK_TARGET=12.0
unset MOLTENVK_DEPLOYMENT_TARGET
run_build() {
  bash "$tmp/scripts/build-graphics-stack.sh" --cx 26 --moltenvk-source crossover-foss
}
run_build > "$tmp/default.log"
assert_contains "$(cat "$tmp/calls")" 'dependency 12.0' 'nested dependency uses macOS 12.0'
assert_contains "$(cat "$tmp/calls")" 'build 12.0' 'real uses the same macOS 12.0 target'
assert_contains "$(cat "$tmp/install/version")" 'deployment-target 12.0' 'manifest records target'
run_build > "$tmp/repeated.log"
assert_eq "$(wc -l < "$tmp/calls" | tr -d ' ')" 2 'matching target reuses the installed result'
export MOLTENVK_DEPLOYMENT_TARGET=10.15 TEST_MVK_TARGET=10.15
run_build > "$tmp/override.log"
assert_eq "$(wc -l < "$tmp/calls" | tr -d ' ')" 4 'changed target rebuilds both stages'
assert_contains "$(cat "$tmp/install/version")" 'deployment-target 10.15' 'explicit older-toolchain target is preserved'
assert_contains "$(cat "$tmp/caller.xcconfig")" 'OTHER_CFLAGS = -DKEEP_CALLER_SETTING' 'caller config is preserved'
if MOLTENVK_DEPLOYMENT_TARGET=invalid run_build > "$tmp/invalid.log" 2>&1; then
  echo 'expected invalid deployment target to fail' >&2
  exit 1
fi
assert_eq "$(wc -l < "$tmp/calls" | tr -d ' ')" 4 'invalid target fails before build work'
echo 'PASS MoltenVK nested build target, override, cache, and caller config'
