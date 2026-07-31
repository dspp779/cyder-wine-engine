#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/assert.sh"
ARCHIVE="${CX26_SOURCE_ARCHIVE:-$ROOT/tools/archives/crossover-sources-26.3.0.tar.gz}"
SOCK_PATCH="$ROOT/patches/cyder-wineserver-sock-reselect-pseudo-fd.patch"
FD_PATCH="$ROOT/patches/cyder-wineserver-poll-slot-guard.patch"
DIAG_PATCH="$ROOT/patches/cyder-wineserver-exit-diagnostics.patch"
RESELECT_PATCH="$ROOT/patches/cyder-wineserver-fd-reselect-async-null-ops.patch"
REBIND_PATCH="$ROOT/patches/cyder-wineserver-sock-rebind-async-fd.patch"
ASYNC_PATCH="$ROOT/patches/cyder-wineserver-async-terminate-null-fd.patch"

if [[ ! -f "$ARCHIVE" ]]; then
  echo "SKIP wineserver async-terminate null-fd: source archive not found at $ARCHIVE"
  exit 0
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cyder-ws-async-term.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

tar -xzf "$ARCHIVE" -C "$TMP_DIR" \
  sources/wine/server/async.c \
  sources/wine/server/fd.c \
  sources/wine/server/sock.c \
  sources/wine/server/file.h \
  sources/wine/server/signal.c \
  sources/wine/server/main.c \
  sources/wine/server/process.c \
  sources/wine/server/process.h
SOURCE="$TMP_DIR/sources/wine"
ASYNC_FILE="$SOURCE/server/async.c"
FILE_H="$SOURCE/server/file.h"

patch --forward --batch -s -p1 -d "$SOURCE" < "$SOCK_PATCH"
patch --forward --batch -s -p1 -d "$SOURCE" < "$FD_PATCH"
patch --forward --batch -s -p1 -d "$SOURCE" < "$DIAG_PATCH"
patch --forward --batch -s -p1 -d "$SOURCE" < "$RESELECT_PATCH"
patch --forward --batch -s -p1 -d "$SOURCE" < "$REBIND_PATCH"

rg -Fq 'if (NT_ERROR( status ) && (!is_fd_overlapped( async->fd ) || !async->pending))' "$ASYNC_FILE"
if rg -Fq '!async->fd || !is_fd_overlapped' "$ASYNC_FILE"; then
  echo "FAIL: null-fd guard already present before applying async-terminate patch" >&2
  exit 1
fi
if rg -Fq 'async_clear_weak_fd' "$ASYNC_FILE"; then
  echo "FAIL: async_clear_weak_fd already present before applying async-terminate patch" >&2
  exit 1
fi

ASYNC_SHA="$(shasum -a 256 "$ASYNC_FILE" | awk '{print $1}')"
FILE_H_SHA="$(shasum -a 256 "$FILE_H" | awk '{print $1}')"
patch --forward --batch -s -p1 -d "$SOURCE" < "$ASYNC_PATCH"

rg -Fq '!async->fd || !is_fd_overlapped( async->fd )' "$ASYNC_FILE"
rg -Fq 'void async_clear_weak_fd( struct async *async )' "$ASYNC_FILE"
rg -Fq 'extern void async_clear_weak_fd( struct async *async );' "$FILE_H"

patch --reverse --batch -s -p1 -d "$SOURCE" < "$ASYNC_PATCH"
assert_eq "$(shasum -a 256 "$ASYNC_FILE" | awk '{print $1}')" "$ASYNC_SHA" \
  "async.c async-terminate null-fd patch round-trip should restore the prior tree"
assert_eq "$(shasum -a 256 "$FILE_H" | awk '{print $1}')" "$FILE_H_SHA" \
  "file.h async-terminate null-fd patch round-trip should restore the prior tree"

patch --forward --batch -s -p1 -d "$SOURCE" < "$ASYNC_PATCH"
rg -Fq 'async_clear_weak_fd' "$ASYNC_FILE"
rg -Fq 'async_clear_weak_fd' "$FILE_H"

echo "PASS wineserver async-terminate null-fd patch round-trip"
