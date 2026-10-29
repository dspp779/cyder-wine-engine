#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/assert.sh"

env_script="$(<"$ROOT/scripts/env-x86_64.sh")"
assert_contains "$env_script" '_cyder_load_dotenv' \
  "env must load project .env for minOS"
assert_contains "$env_script" 'CYDER_MACOSX_VERSION_MIN_FLAG' \
  "env must export an explicit -mmacosx-version-min flag"

assert test -f "$ROOT/.env.example"
assert_contains "$(<"$ROOT/.env.example")" 'MACOSX_DEPLOYMENT_TARGET=10.15' \
  ".env.example must document the 10.15 product floor"

# Missing .env → default 10.15
TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-cyder-minos.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT
# env-x86_64 resolves OGOM from SCRIPT_DIR; point a fake root with only the script copy.
mkdir -p "$TMP/scripts"
cp "$ROOT/scripts/env-x86_64.sh" "$TMP/scripts/env-x86_64.sh"
# Minimal stubs so sourcing does not require brew trees for this assertion path.
# The script only needs OGOM; avoid sourcing full brew graph by extracting the dotenv + default.
(
  set -euo pipefail
  OGOM="$TMP"
  unset MOLTENVK_DEPLOYMENT_TARGET
  # shellcheck disable=SC1091
  source "$ROOT/scripts/env-x86_64.sh"
  assert_eq "$MACOSX_DEPLOYMENT_TARGET" "10.15" \
    "without .env, MACOSX_DEPLOYMENT_TARGET must default to 10.15"
  assert_eq "$CYDER_MACOSX_VERSION_MIN_FLAG" "-mmacosx-version-min=10.15" \
    "without .env, min flag must target 10.15"
  assert_eq "$MOLTENVK_DEPLOYMENT_TARGET" "12.0" \
    "MoltenVK target must default separately to macOS 12.0"
)

mkdir -p "$TMP/with-env"
printf 'MACOSX_DEPLOYMENT_TARGET=11.0\n' >"$TMP/with-env/.env"
mkdir -p "$TMP/with-env/scripts"
(
  set -euo pipefail
  export OGOM="$TMP/with-env"
  unset MACOSX_DEPLOYMENT_TARGET || true
  # shellcheck disable=SC1091
  source "$ROOT/scripts/env-x86_64.sh"
  assert_eq "$MACOSX_DEPLOYMENT_TARGET" "11.0" \
    ".env MACOSX_DEPLOYMENT_TARGET must be applied when unset in the environment"
)

# Explicit compiler paths must survive spaces while preserving the product floor.
fixture_compiler="${CYDER_HOST_CLANG:-/usr/bin/clang}"
(
  export OGOM="$TMP/compiler-fixture" HOMEBREW_PREFIX="$TMP/compiler-fixture/brew"
  export HOMEBREW_REPOSITORY="$HOMEBREW_PREFIX" HOMEBREW_CELLAR="$HOMEBREW_PREFIX/Cellar"
  export CYDER_HOST_CLANG="$TMP/compiler with spaces" CYDER_HOST_CLANGXX="$TMP/compiler with spaces"
  export COMPILER_CALLS="$TMP/compiler-arguments"
  export HOMEBREW_TEMP="$TMP/short-homebrew-temp"
  mkdir -p "$HOMEBREW_PREFIX/opt/zlib/lib"
  cat > "$CYDER_HOST_CLANG" <<'COMPILER'
#!/bin/bash
printf '%s\n' "$@" > "$COMPILER_CALLS"
COMPILER
  chmod +x "$CYDER_HOST_CLANG"
  source "$ROOT/scripts/env-x86_64.sh"
  assert_eq "$HOMEBREW_TEMP" "$TMP/short-homebrew-temp" "explicit short Homebrew temp must survive env loading"
  brew_x86_validate_install() { return 0; }
  brew_x86() { return 0; }
  # A failed graph query must not be silently interpreted as no dependencies.
  brew_x86() { return 23; }
  if brew_x86_install_runtime zlib 2>"$TMP/graph-error"; then
    echo 'dependency graph failure was ignored' >&2; exit 1
  fi
  assert_contains "$(cat "$TMP/graph-error")" 'Cannot resolve runtime dependency graph' 'graph failure must fail closed'
  brew_x86() { return 0; }
  brew_x86_install_runtime zlib
  "$HOMEBREW_PREFIX/opt/llvm/bin/clang" -mmacosx-version-min=27.0 -c fixture.c
  actual="$(cat "$COMPILER_CALLS")"
  assert_contains "$actual" '-arch' 'runtime wrapper pins architecture'
  assert_contains "$actual" 'x86_64' 'runtime wrapper targets Intel'
  assert_contains "$actual" '-mmacosx-version-min=10.15' 'runtime wrapper preserves product floor'
  if [[ "$actual" == *27.0* ]]; then echo 'higher minOS leaked into compiler args' >&2; exit 1; fi
  "$HOMEBREW_PREFIX/opt/llvm/bin/clang++" -c fixture.cc
  # A newly introduced bottled dependency must be caught by the post-install scan.
  mkdir -p "$HOMEBREW_PREFIX/opt/new-bottle/lib"
  printf 'int probe = 1;\n' > "$TMP/above-floor.c"
  "$fixture_compiler" -arch x86_64 -dynamiclib -mmacosx-version-min=14.0 \
    "$TMP/above-floor.c" -o "$HOMEBREW_PREFIX/opt/new-bottle/lib/libprobe.1.dylib"
  printf '0\n' > "$TMP/graph-count"
  brew_x86() {
    if [[ "$1" == deps ]]; then
      count="$(cat "$TMP/graph-count")"
      printf '%s\n' "$((count+1))" > "$TMP/graph-count"
      [[ "$count" == 0 ]] || printf 'new-bottle\n'
    fi
    return 0
  }
  if brew_x86_install_runtime zlib 2>"$TMP/post-error"; then
    echo 'new high-minOS dependency escaped the post-install gate' >&2; exit 1
  fi
  assert_contains "$(cat "$TMP/post-error")" 'new-bottle still exceeds minOS 10.15' 'new indirect dependencies must be checked'
)

echo "PASS test-cyder-minos-env"
