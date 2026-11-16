#!/usr/bin/env bash
# scripts/pack-weak-import-scan.py: weak imports from macOS need a reviewed
# guard; weak imports from bundled libraries are not checked.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/assert.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cyder-weak-import-scan.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
SCAN="$ROOT/scripts/pack-weak-import-scan.py"
CC=(clang -arch x86_64 -mmacosx-version-min=10.15 -Wno-unguarded-availability-new)

# pthread_cpu_number_np is macOS 11.0+, so at 10.15 it is a weak libSystem import.
cat >"$TMP/uses-new-api.c" <<'C'
#include <pthread.h>
int cyder_cpu(void) { size_t cpu = 0; pthread_cpu_number_np(&cpu); return (int)cpu; }
C
cat >"$TMP/bundled.c" <<'C'
int cyder_bundled(void) { return 1; }
C
cat >"$TMP/uses-bundled.c" <<'C'
extern int cyder_bundled(void) __attribute__((weak_import));
int cyder_call(void) { return cyder_bundled ? cyder_bundled() : 0; }
C

ENGINE="$TMP/engine"
UNIX="$ENGINE/lib/wine/x86_64-unix"
mkdir -p "$UNIX"
"${CC[@]}" -dynamiclib "$TMP/uses-new-api.c" -o "$UNIX/ntdll.so"
"${CC[@]}" -dynamiclib -install_name @rpath/libbundled.dylib "$TMP/bundled.c" -o "$UNIX/libbundled.dylib"
"${CC[@]}" -dynamiclib "$TMP/uses-bundled.c" -L"$UNIX" -lbundled -o "$UNIX/uses-bundled.so"
printf 'not a Mach-O\n' >"$UNIX/notes.txt"
assert_contains "$(nm -m "$UNIX/ntdll.so")" "weak external _pthread_cpu_number_np (from libSystem)" \
  "fixture must contain a weak libSystem import"

python3 "$SCAN" "$ENGINE" >"$TMP/pass.out"
assert_contains "$(<"$TMP/pass.out")" "OK: every macOS weak import is guarded" \
  "an allowlisted guard in ntdll.so and a bundled weak import both pass"

# The same import in a file the allowlist does not name must fail closed.
cp "$UNIX/ntdll.so" "$UNIX/ntdll.so.pre-qdo"
if python3 "$SCAN" "$ENGINE" >/dev/null 2>"$TMP/fail.err"; then
  echo "ASSERT failed: an unreviewed weak import must refuse the pack" >&2; exit 1
fi
assert_contains "$(<"$TMP/fail.err")" "lib/wine/x86_64-unix/ntdll.so.pre-qdo: _pthread_cpu_number_np (from libSystem)" \
  "the refusal names the file, symbol and library"
rm "$UNIX/ntdll.so.pre-qdo"

# A custom allowlist without that row also refuses ntdll.so.
printf '# empty\n' >"$TMP/empty.tsv"
if python3 "$SCAN" "$ENGINE" "$TMP/empty.tsv" >/dev/null 2>&1; then
  echo "ASSERT failed: a weak import with no allowlist row must refuse the pack" >&2; exit 1
fi

# Malformed rows are an error, not a silent allow.
printf '_pipe2\t*\n' >"$TMP/bad.tsv"
if python3 "$SCAN" "$ENGINE" "$TMP/bad.tsv" >/dev/null 2>&1; then
  echo "ASSERT failed: a row without a guard column must be rejected" >&2; exit 1
fi

# A typo or missing engine tree must never produce an all-clear result.
if python3 "$SCAN" "$TMP/missing-engine" >"$TMP/missing.out" 2>"$TMP/missing.err"; then
  echo "ASSERT failed: a missing engine tree must refuse the scan" >&2; exit 1
fi
assert_contains "$(<"$TMP/missing.err")" "not a directory" "missing input names the error"
if python3 "$SCAN" "$UNIX/notes.txt" >/dev/null 2>&1; then
  echo "ASSERT failed: a file cannot be scanned as an engine tree" >&2; exit 1
fi

# Rows must never wave through the Cyder013 crash.
if grep -E $'^(_pipe2|_strchrnul|\\*)\t' "$ROOT/config/weak-import-allowlist.tsv"; then
  echo "ASSERT failed: _pipe2/_strchrnul must be removed at build time, not allowlisted" >&2; exit 1
fi

assert_contains "$(<"$ROOT/scripts/pack-engine-artifact.sh")" 'pack-weak-import-scan.py" "$ENGINE_TREE"' \
  "engine pack runs the weak-import gate"
assert_contains "$(<"$ROOT/scripts/build-media-stack.sh")" 'pack-weak-import-scan.py" "$MEDIA_INSTALL"' \
  "media build runs the weak-import gate"

echo "PASS pack-weak-import-scan"
