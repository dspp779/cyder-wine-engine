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
  # shellcheck disable=SC1091
  source "$ROOT/scripts/env-x86_64.sh"
  assert_eq "$MACOSX_DEPLOYMENT_TARGET" "10.15" \
    "without .env, MACOSX_DEPLOYMENT_TARGET must default to 10.15"
  assert_eq "$CYDER_MACOSX_VERSION_MIN_FLAG" "-mmacosx-version-min=10.15" \
    "without .env, min flag must target 10.15"
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

echo "PASS test-cyder-minos-env"
