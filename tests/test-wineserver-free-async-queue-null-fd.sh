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
FREE_PATCH="$ROOT/patches/cyder-wineserver-free-async-queue-null-fd.patch"

if [[ ! -f "$ARCHIVE" ]]; then
  echo "SKIP wineserver free-async-queue null-fd: source archive not found at $ARCHIVE"
  exit 0
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cyder-ws-free-async.XXXXXX")"
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

patch --forward --batch -s -p1 -d "$SOURCE" < "$SOCK_PATCH"
patch --forward --batch -s -p1 -d "$SOURCE" < "$FD_PATCH"
patch --forward --batch -s -p1 -d "$SOURCE" < "$DIAG_PATCH"
patch --forward --batch -s -p1 -d "$SOURCE" < "$RESELECT_PATCH"
patch --forward --batch -s -p1 -d "$SOURCE" < "$REBIND_PATCH"
patch --forward --batch -s -p1 -d "$SOURCE" < "$ASYNC_PATCH"

# Prior patches leave unguarded fd_get_completion in free_async_queue.
rg -Fq 'if (!async->completion) async->completion = fd_get_completion( async->fd, &async->comp_key );' "$ASYNC_FILE"
if rg -Fq 'if (!async->completion && async->fd) async->completion = fd_get_completion' "$ASYNC_FILE"; then
  echo "FAIL: free_async_queue null-fd guard already present before applying patch" >&2
  exit 1
fi

ASYNC_SHA="$(shasum -a 256 "$ASYNC_FILE" | awk '{print $1}')"
patch --forward --batch -s -p1 -d "$SOURCE" < "$FREE_PATCH"

rg -Fq 'if (!async->completion && async->fd) async->completion = fd_get_completion( async->fd, &async->comp_key );' "$ASYNC_FILE"
# Must not leave the unguarded form in free_async_queue.
if rg -Fq 'if (!async->completion) async->completion = fd_get_completion( async->fd, &async->comp_key );' "$ASYNC_FILE"; then
  echo "FAIL: unguarded free_async_queue fd_get_completion remained after patch" >&2
  exit 1
fi

patch --reverse --batch -s -p1 -d "$SOURCE" < "$FREE_PATCH"
assert_eq "$(shasum -a 256 "$ASYNC_FILE" | awk '{print $1}')" "$ASYNC_SHA" \
  "async.c free-async-queue null-fd patch round-trip should restore the prior tree"

patch --forward --batch -s -p1 -d "$SOURCE" < "$FREE_PATCH"
rg -Fq 'if (!async->completion && async->fd) async->completion = fd_get_completion' "$ASYNC_FILE"

echo "PASS wineserver free-async-queue null-fd patch round-trip"
