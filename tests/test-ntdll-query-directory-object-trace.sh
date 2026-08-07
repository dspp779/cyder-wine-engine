#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE="${CX26_SOURCE_ARCHIVE:-$ROOT/tools/archives/crossover-sources-26.3.0.tar.gz}"
PATCH="$ROOT/patches/cyder-ntdll-query-directory-object-trace.patch"

if [[ ! -f "$ARCHIVE" ]]; then
  echo "SKIP ntdll QDO trace patch: source archive not found at $ARCHIVE"
  exit 0
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cyder-qdo-trace.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

tar -xzf "$ARCHIVE" -C "$TMP_DIR" sources/wine/dlls/ntdll/unix/sync.c
SOURCE="$TMP_DIR/sources/wine"
FILE="$SOURCE/dlls/ntdll/unix/sync.c"
ORIGINAL_SHA="$(shasum -a 256 "$FILE" | awk '{print $1}')"

patch --forward --batch -s -p1 -d "$SOURCE" < "$PATCH"
rg -Fq 'cyder QDO' "$FILE"
rg -Fq 'CYDER_QDO_TRACE' "$FILE"
rg -Fq 'cyder_qdo_should_trace' "$FILE"

patch --reverse --batch -s -p1 -d "$SOURCE" < "$PATCH"
RESTORED_SHA="$(shasum -a 256 "$FILE" | awk '{print $1}')"
if [[ "$ORIGINAL_SHA" != "$RESTORED_SHA" ]]; then
  echo "FAIL QDO trace patch round-trip did not restore the original source" >&2
  exit 1
fi

echo "PASS ntdll QueryDirectoryObject trace patch round-trip"
