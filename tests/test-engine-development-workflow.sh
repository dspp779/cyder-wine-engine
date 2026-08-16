#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/assert.sh"

workflow="$(<"$ROOT/docs/engine-development-test-workflow.zh-TW.md")"
incremental="$(<"$ROOT/docs/incremental-build-and-patches.md")"
skill="$(<"$ROOT/.agents/skills/incremental-wine-build/SKILL.md")"
agents="$(<"$ROOT/AGENTS.md")"
build_script="$(<"$ROOT/scripts/build-wine.sh")"

assert_contains "$workflow" 'export OGOM="$ENGINE_ROOT"' \
  'workflow pins OGOM to the engine checkout'
assert_contains "$workflow" '--cx 26 --maplestory --with-vulkan --vulkan-source crossover' \
  'workflow contains the canonical CX26 build path'
assert_contains "$workflow" '--dry-run' \
  'workflow requires a build or launcher dry-run'
assert_contains "$workflow" 'bash tests/run.sh' \
  'workflow requires the full regression suite'
assert_contains "$workflow" '--no-otp' \
  'workflow requires a no-OTP smoke test before acceptance'
assert_contains "$workflow" 'CYDER_MAPLESTORY_IO_TRACE=1' \
  'workflow enables the WZ trace gate for I/O profiling'
assert_contains "$workflow" 'WINEDEBUG' \
  'workflow documents the cyderio debug channel for I/O profiling'
assert_contains "$workflow" 'gzip -9' \
  'workflow contains bounded log archival guidance'
assert_contains "$incremental" 'engine-development-test-workflow.zh-TW.md' \
  'incremental guide links to the end-to-end workflow'
assert_contains "$skill" 'engine-development-test-workflow.zh-TW.md' \
  'skill links to the end-to-end workflow'
assert_contains "$agents" 'engine-development-test-workflow.zh-TW.md' \
  'agent instructions require the end-to-end workflow'
assert_contains "$build_script" 'if (is_maplestory_process()) return STATUS_NO_YIELD_PERFORMED;' \
  'build script keeps the stable no-yield marker'
assert_contains "$build_script" 'printf '\''%s\n'\'' "$ENGINE_VERSION_LABEL"' \
  'build script synchronizes the installed engine version'
assert_contains "$build_script" '>"$WINE_INSTALL/version"' \
  'build script writes the installed engine version file'

echo 'PASS: engine development workflow contract'
