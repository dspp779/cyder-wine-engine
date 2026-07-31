#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/assert.sh"
ARCHIVE="${CX26_SOURCE_ARCHIVE:-$ROOT/tools/archives/crossover-sources-26.3.0.tar.gz}"
SOCK_PATCH="$ROOT/patches/cyder-wineserver-sock-reselect-pseudo-fd.patch"
FD_PATCH="$ROOT/patches/cyder-wineserver-poll-slot-guard.patch"
DIAG_PATCH="$ROOT/patches/cyder-wineserver-exit-diagnostics.patch"
COMP_PATCH="$ROOT/patches/cyder-wineserver-add-completion-guard.patch"

if [[ ! -f "$ARCHIVE" ]]; then
  echo "SKIP wineserver add-completion guard: source archive not found at $ARCHIVE"
  exit 0
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cyder-ws-add-comp.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

tar -xzf "$ARCHIVE" -C "$TMP_DIR" \
  sources/wine/server/completion.c \
  sources/wine/server/fd.c \
  sources/wine/server/sock.c \
  sources/wine/server/signal.c \
  sources/wine/server/main.c \
  sources/wine/server/process.c \
  sources/wine/server/process.h
SOURCE="$TMP_DIR/sources/wine"
COMP_FILE="$SOURCE/server/completion.c"

# exit-diagnostics adds wineserver_diag_printf to process.h (needed by this guard).
patch --forward --batch -s -p1 -d "$SOURCE" < "$SOCK_PATCH"
patch --forward --batch -s -p1 -d "$SOURCE" < "$FD_PATCH"
patch --forward --batch -s -p1 -d "$SOURCE" < "$DIAG_PATCH"

rg -Fq 'struct comp_msg *msg = mem_alloc( sizeof( *msg ) );' "$COMP_FILE"
if rg -Fq 'add_completion: invalid completion' "$COMP_FILE"; then
  echo "FAIL: add_completion guard already present before applying patch" >&2
  exit 1
fi

COMP_SHA="$(shasum -a 256 "$COMP_FILE" | awk '{print $1}')"
patch --forward --batch -s -p1 -d "$SOURCE" < "$COMP_PATCH"

rg -Fq '#include "process.h"' "$COMP_FILE"
rg -Fq 'add_completion: invalid completion' "$COMP_FILE"
rg -Fq 'completion->obj.ops != &completion_ops' "$COMP_FILE"
rg -Fq 'LIST_FOR_EACH_ENTRY_SAFE( wait, wait_next, &completion->wait_queue' "$COMP_FILE"

patch --reverse --batch -s -p1 -d "$SOURCE" < "$COMP_PATCH"
assert_eq "$(shasum -a 256 "$COMP_FILE" | awk '{print $1}')" "$COMP_SHA" \
  "completion.c add-completion guard patch round-trip should restore the prior tree"

patch --forward --batch -s -p1 -d "$SOURCE" < "$COMP_PATCH"
rg -Fq 'add_completion: invalid completion' "$COMP_FILE"

echo "PASS wineserver add-completion guard patch round-trip"
