#!/usr/bin/env bash
# cyder-ntdll-mono-gs-last-error.patch: applies after native-ddraw-path on the
# pristine CX26 loader.c, round-trips, keeps its marker and opt-out, and is
# wired into the build and release metadata.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE="${CX26_SOURCE_ARCHIVE:-$ROOT/tools/archives/crossover-sources-26.3.0.tar.gz}"
DDRAW="$ROOT/patches/cyder-ntdll-native-ddraw-path.patch"
PATCH="$ROOT/patches/cyder-ntdll-mono-gs-last-error.patch"

fail() { echo "FAIL $*" >&2; exit 1; }

# Wiring: apply order (after native-ddraw-path), README, release metadata.
build_lines="$(grep -n 'apply_cyder_patch "$OGOM/patches/cyder-ntdll-\(native-ddraw-path\|mono-gs-last-error\).patch"' "$ROOT/scripts/build-wine.sh" | cut -d: -f1 | tr '\n' ' ')"
read -r ddraw_line mono_line <<<"$build_lines"
[[ -n "${mono_line:-}" && "$mono_line" -gt "$ddraw_line" ]] || fail "build-wine.sh must apply the patch after native-ddraw-path"
grep -Fq 'cyder-ntdll-mono-gs-last-error.patch' "$ROOT/patches/README.md" || fail "patches/README.md entry missing"
grep -Fq '"cyder-ntdll-mono-gs-last-error.patch"' "$ROOT/config/engine-release.json" || fail "engine-release.json patch entry missing"
grep -Fq '"mono-gs-last-error-v1"' "$ROOT/config/engine-release.json" || fail "engine-release.json capability missing"

if [[ ! -f "$ARCHIVE" ]]; then
  echo "SKIP mono gs last-error patch round-trip: source archive not found at $ARCHIVE"
  exit 0
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cyder-mono-gs.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT
tar -xzf "$ARCHIVE" -C "$TMP_DIR" sources/wine/dlls/ntdll/loader.c
SOURCE="$TMP_DIR/sources/wine"
FILE="$SOURCE/dlls/ntdll/loader.c"

patch --forward --batch -s -p1 -d "$SOURCE" < "$DDRAW"
BEFORE_SHA="$(shasum -a 256 "$FILE" | awk '{print $1}')"
patch --forward --batch -s -p1 -d "$SOURCE" < "$PATCH"

grep -Fq 'cyder: mono gs LastErrorValue' "$FILE" || fail "marker missing"
grep -Fq 'CYDER_MONO_GS_LASTERROR' "$FILE" || fail "opt-out variable missing"
grep -Fq 'if (!is_builtin) cyder_fix_mono_last_error( *module, nt, nt_name );' "$FILE" || fail "loader hook missing"
# Thunks read through the TEB pointer at %gs:0x30, never %gs:0x68.
grep -Fq '"movq %gs:0x30,%" #reg64' "$FILE" || fail "thunk does not read the TEB pointer"
# Emitter replacement: mov r64,%gs:0x30 (65 48 8B ..) then mov r32,0x68(r64).
grep -Fq '*code++ = 0x30; *code++ = 0; *code++ = 0; *code++ = 0;' "$FILE" || fail "emitter does not load %gs:0x30"
grep -Fq '*code++ = 0x68;' "$FILE" || fail "emitter does not read offset 0x68"
# The fix must never write %gs:0x68 (macOS libc gmtime TSD slot).
if grep -Eq 'movl? [^"]*,%+gs:0x68' "$FILE"; then fail "patch writes %gs:0x68"; fi

patch --reverse --batch --dry-run -s -p1 -d "$SOURCE" < "$PATCH" || fail "reverse check (already applied) fails"
patch --reverse --batch -s -p1 -d "$SOURCE" < "$PATCH"
AFTER_SHA="$(shasum -a 256 "$FILE" | awk '{print $1}')"
[[ "$BEFORE_SHA" == "$AFTER_SHA" ]] || fail "round-trip did not restore loader.c"

echo "PASS mono gs last-error patch: wiring, apply order, markers and round-trip"
