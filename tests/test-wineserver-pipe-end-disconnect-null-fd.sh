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
PIPE_PATCH="$ROOT/patches/cyder-wineserver-pipe-end-disconnect-null-fd.patch"

if [[ ! -f "$ARCHIVE" ]]; then
  echo "SKIP wineserver pipe-end-disconnect null-fd: source archive not found at $ARCHIVE"
  exit 0
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cyder-ws-pipe-end.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

tar -xzf "$ARCHIVE" -C "$TMP_DIR" \
  sources/wine/server/named_pipe.c \
  sources/wine/server/fd.c \
  sources/wine/server/sock.c \
  sources/wine/server/async.c \
  sources/wine/server/file.h \
  sources/wine/server/signal.c \
  sources/wine/server/main.c \
  sources/wine/server/process.c \
  sources/wine/server/process.h
SOURCE="$TMP_DIR/sources/wine"
PIPE_FILE="$SOURCE/server/named_pipe.c"

# Same order as build-wine.sh through this guard (named_pipe itself is untouched
# by prior patches; still apply them so process.h gains wineserver_diag_printf).
patch --forward --batch -s -p1 -d "$SOURCE" < "$SOCK_PATCH"
patch --forward --batch -s -p1 -d "$SOURCE" < "$FD_PATCH"
patch --forward --batch -s -p1 -d "$SOURCE" < "$DIAG_PATCH"
patch --forward --batch -s -p1 -d "$SOURCE" < "$RESELECT_PATCH"
patch --forward --batch -s -p1 -d "$SOURCE" < "$REBIND_PATCH"
patch --forward --batch -s -p1 -d "$SOURCE" < "$ASYNC_PATCH"

# Upstream (post prior patches) must still call unguarded.
rg -Fq 'fd_async_wake_up( pipe_end->fd, ASYNC_TYPE_WAIT, status );' "$PIPE_FILE"
rg -Fq 'async_wake_up( &pipe_end->read_q, status );' "$PIPE_FILE"
rg -Fq 'if (status == STATUS_PIPE_DISCONNECTED) set_fd_signaled( pipe_end->fd, 0 );' "$PIPE_FILE"
if rg -Fq 'pipe_end_disconnect: null fd' "$PIPE_FILE"; then
  echo "FAIL: null-fd diagnostic already present before applying pipe-end patch" >&2
  exit 1
fi

PIPE_SHA="$(shasum -a 256 "$PIPE_FILE" | awk '{print $1}')"
patch --forward --batch -s -p1 -d "$SOURCE" < "$PIPE_PATCH"

# Guard must null-check fd, free queue when null, and log via exit-diagnostics helper.
rg -Fq '!pipe_end->fd' "$PIPE_FILE"
rg -Fq 'pipe_end_disconnect: null fd' "$PIPE_FILE"
rg -Fq 'wineserver_diag_printf' "$PIPE_FILE"
rg -Fq 'free_async_queue( &pipe_end->read_q );' "$PIPE_FILE"
rg -Fq 'if (!pipe_end->fd) async_clear_weak_fd( async );' "$PIPE_FILE"
rg -Fq 'if (status == STATUS_PIPE_DISCONNECTED && pipe_end->fd) set_fd_signaled( pipe_end->fd, 0 );' "$PIPE_FILE"
# Must still wake when fd is present.
rg -Fq 'fd_async_wake_up( pipe_end->fd, ASYNC_TYPE_WAIT, status );' "$PIPE_FILE"
# Peer wake in reselect_read_queue also null-checks.
rg -Fq 'if (pipe_end->connection->fd)' "$PIPE_FILE"

# Round-trip this patch alone (prior patches stay applied).
patch --reverse --batch -s -p1 -d "$SOURCE" < "$PIPE_PATCH"
assert_eq "$(shasum -a 256 "$PIPE_FILE" | awk '{print $1}')" "$PIPE_SHA" \
  "named_pipe.c pipe-end-disconnect null-fd patch round-trip should restore the prior tree"
if rg -Fq 'pipe_end_disconnect: null fd' "$PIPE_FILE"; then
  echo "FAIL: null-fd diagnostic remained after reversing pipe-end patch" >&2
  exit 1
fi

patch --forward --batch -s -p1 -d "$SOURCE" < "$PIPE_PATCH"
rg -Fq 'pipe_end_disconnect: null fd' "$PIPE_FILE"

echo "PASS wineserver pipe-end-disconnect null-fd patch round-trip"
