#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/assert.sh"
ARCHIVE="${CX26_SOURCE_ARCHIVE:-$ROOT/tools/archives/crossover-sources-26.3.0.tar.gz}"
SOCK_PATCH="$ROOT/patches/cyder-wineserver-sock-reselect-pseudo-fd.patch"
FD_PATCH="$ROOT/patches/cyder-wineserver-poll-slot-guard.patch"
DIAG_PATCH="$ROOT/patches/cyder-wineserver-exit-diagnostics.patch"
RESELECT_PATCH="$ROOT/patches/cyder-wineserver-fd-reselect-async-null-ops.patch"

if [[ ! -f "$ARCHIVE" ]]; then
  echo "SKIP wineserver fd-reselect-async null-ops: source archive not found at $ARCHIVE"
  exit 0
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cyder-ws-fd-reselect.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

tar -xzf "$ARCHIVE" -C "$TMP_DIR" \
  sources/wine/server/fd.c \
  sources/wine/server/sock.c \
  sources/wine/server/signal.c \
  sources/wine/server/main.c \
  sources/wine/server/process.c \
  sources/wine/server/process.h
SOURCE="$TMP_DIR/sources/wine"
FD_FILE="$SOURCE/server/fd.c"

# Same order as build-wine.sh: sock → poll-slot → exit-diagnostics → this guard.
patch --forward --batch -s -p1 -d "$SOURCE" < "$SOCK_PATCH"
patch --forward --batch -s -p1 -d "$SOURCE" < "$FD_PATCH"
patch --forward --batch -s -p1 -d "$SOURCE" < "$DIAG_PATCH"

# Upstream (post prior patches) must still call through the vtable unguarded.
rg -Uq 'void fd_reselect_async\( struct fd \*fd, struct async_queue \*queue \)\n\{\n    fd->fd_ops->reselect_async\( fd, queue \);' "$FD_FILE"

FD_SHA="$(shasum -a 256 "$FD_FILE" | awk '{print $1}')"
patch --forward --batch -s -p1 -d "$SOURCE" < "$RESELECT_PATCH"

# Guard must null-check ops and log via the exit-diagnostics helper.
rg -Fq '!fd->fd_ops || !fd->fd_ops->reselect_async' "$FD_FILE"
rg -Fq 'fd_reselect_async: missing ops' "$FD_FILE"
rg -Fq 'wineserver_diag_printf' "$FD_FILE"
# Must still invoke the vtable when ops are present.
rg -Fq 'fd->fd_ops->reselect_async( fd, queue );' "$FD_FILE"

# Round-trip this patch alone (prior patches stay applied).
patch --reverse --batch -s -p1 -d "$SOURCE" < "$RESELECT_PATCH"
assert_eq "$(shasum -a 256 "$FD_FILE" | awk '{print $1}')" "$FD_SHA" \
  "fd.c fd-reselect-async null-ops patch round-trip should restore the prior tree"
if rg -Fq 'fd_reselect_async: missing ops' "$FD_FILE"; then
  echo "FAIL: missing-ops diagnostic remained after reversing null-ops patch" >&2
  exit 1
fi

patch --forward --batch -s -p1 -d "$SOURCE" < "$RESELECT_PATCH"
rg -Fq 'fd_reselect_async: missing ops' "$FD_FILE"

echo "PASS wineserver fd-reselect-async null-ops patch round-trip"
