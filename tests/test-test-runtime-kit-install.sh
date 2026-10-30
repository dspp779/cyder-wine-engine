#!/bin/bash
set -euo pipefail
if [[ -z "${CYDER_TEST_KIT:-}" ]]; then
  echo 'SKIP actual test-kit install: set CYDER_TEST_KIT to a built kit'
  exit 0
fi
KIT="$(cd "$CYDER_TEST_KIT" && pwd -P)"
TEMP="$(mktemp -d /private/tmp/cyder-kit-transaction.XXXXXX)"
trap 'rm -rf "$TEMP"' EXIT
export CYDER_TEST_ROOT="$TEMP/install"
bash "$KIT/Install.command"
mkdir -p "$CYDER_TEST_ROOT/prefixes/existing"
printf 'preserve this test save\n' > "$CYDER_TEST_ROOT/prefixes/existing/save.txt"
bash "$KIT/Install.command"
grep -q 'preserve this test save' "$CYDER_TEST_ROOT/prefixes/existing/save.txt"
bash "$KIT/Verify.command"
# Detect installed corruption, then restore only the disposable fixture.
file="$CYDER_TEST_ROOT/engine/lib/wine/x86_64-unix/winemac.so"
cp -p "$file" "$TEMP/winemac.saved"
printf 'corruption' >> "$file"
if bash "$KIT/Verify.command" > "$TEMP/corrupt.log" 2>&1; then
  echo 'FAIL: corrupt install accepted' >&2; exit 1
fi
mv "$TEMP/winemac.saved" "$file"
bash "$KIT/Verify.command"
# No external prefix may be selected, even when supplied by the parent shell.
output="$(WINEPREFIX="$TEMP/not-owned" bash "$KIT/Run Test.command" --dry-run --bottle scoped)"
[[ "$output" == *"prefix=$CYDER_TEST_ROOT/prefixes/scoped"* ]]
[[ ! -e "$TEMP/not-owned" && ! -e "$CYDER_TEST_ROOT/prefixes/scoped" ]]
mkdir "$TEMP/foreign"
ln -s "$TEMP/foreign" "$CYDER_TEST_ROOT/prefixes/linked"
if bash "$KIT/Run Test.command" --dry-run --bottle linked > "$TEMP/link.log" 2>&1; then
  echo 'FAIL: linked external prefix accepted' >&2; exit 1
fi
[[ -z "$(ls -A "$TEMP/foreign")" ]]
echo 'PASS actual test-kit install, repeat install preserves saves, corruption detection, prefix isolation'
