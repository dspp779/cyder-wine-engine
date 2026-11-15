#!/usr/bin/env bash
# wake_up() must hold the object whose wait queue it walks: a wakeup can kill
# the waiting thread, and the dying process's handles may hold the object's last
# reference (issue #15: SIGSEGV in event_sync_signal after SIGTERM to a program).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/assert.sh"
ARCHIVE="${CX26_SOURCE_ARCHIVE:-$ROOT/tools/archives/crossover-sources-26.3.0.tar.gz}"
PATCH="$ROOT/patches/cyder-wineserver-wake-up-hold-object.patch"

if [[ ! -f "$ARCHIVE" ]]; then
  echo "SKIP wineserver wake_up hold: source archive not found at $ARCHIVE"
  exit 0
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cyder-ws-wake-up.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT
tar -xzf "$ARCHIVE" -C "$TMP_DIR" sources/wine/server/thread.c
SOURCE="$TMP_DIR/sources/wine"
FILE="$SOURCE/server/thread.c"

# No earlier Cyder patch touches thread.c; the patch applies to the pristine file.
if grep -Fq 'cyder: wake_up holds obj' "$FILE"; then
  echo "FAIL: wake_up hold already present before applying patch" >&2
  exit 1
fi
ORIG_SHA="$(shasum -a 256 "$FILE" | awk '{print $1}')"
patch --forward --batch --fuzz=0 -s -p1 -d "$SOURCE" < "$PATCH"

body="$(awk '/^void wake_up\( struct object \*obj, int max \)/{p=1} p{print} p && /^}/{exit}' "$FILE")"
assert_contains "$body" 'cyder: wake_up holds obj' "marker is inside wake_up"
assert_contains "$body" 'if (list_empty( &obj->wait_queue )) return;' \
  "an empty queue returns before the grab (an object being destroyed is never grabbed)"
# The grab precedes the loop and the release follows it.
order="$(printf '%s\n' "$body" | grep -nE 'grab_object\( obj \)|LIST_FOR_EACH\( ptr, &obj->wait_queue \)|release_object\( obj \)' | cut -d: -f2- | tr -d ' ')"
assert_eq "$order" "$(printf 'grab_object(obj);\nLIST_FOR_EACH(ptr,&obj->wait_queue)\nrelease_object(obj);')" \
  "obj is held for the whole wait-queue walk"

patch --reverse --batch --fuzz=0 -s -p1 -d "$SOURCE" < "$PATCH"
assert_eq "$(shasum -a 256 "$FILE" | awk '{print $1}')" "$ORIG_SHA" "patch round-trip restores thread.c"

# The build applies it and recognises it as applied.
assert_contains "$(cat "$ROOT/scripts/build-wine.sh")" \
  'apply_cyder_patch "$OGOM/patches/cyder-wineserver-wake-up-hold-object.patch"' "build-wine.sh applies the patch"
assert_contains "$(cat "$ROOT/scripts/build-wine.sh")" "grep -Fq 'cyder: wake_up holds obj'" "build-wine.sh detects it as applied"
assert_contains "$(cat "$ROOT/config/engine-release.json")" '"cyder-wineserver-wake-up-hold-object.patch"' \
  "the release manifest lists the patch"

echo "PASS wineserver wake_up holds the object it wakes"
