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

if [[ ! -f "$ARCHIVE" ]]; then
  echo "SKIP wineserver sock-rebind-async-fd: source archive not found at $ARCHIVE"
  exit 0
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cyder-ws-sock-rebind.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

tar -xzf "$ARCHIVE" -C "$TMP_DIR" \
  sources/wine/server/sock.c \
  sources/wine/server/async.c \
  sources/wine/server/file.h \
  sources/wine/server/fd.c \
  sources/wine/server/signal.c \
  sources/wine/server/main.c \
  sources/wine/server/process.c \
  sources/wine/server/process.h
SOURCE="$TMP_DIR/sources/wine"
SOCK_FILE="$SOURCE/server/sock.c"
ASYNC_FILE="$SOURCE/server/async.c"
FILE_H="$SOURCE/server/file.h"

# Same order as build-wine.sh through the soft-guards before this proper fix.
patch --forward --batch -s -p1 -d "$SOURCE" < "$SOCK_PATCH"
patch --forward --batch -s -p1 -d "$SOURCE" < "$FD_PATCH"
patch --forward --batch -s -p1 -d "$SOURCE" < "$DIAG_PATCH"
patch --forward --batch -s -p1 -d "$SOURCE" < "$RESELECT_PATCH"

# Upstream (post prior patches) must still release without rebind.
if rg -Fq 'sock_rebind_async_fds' "$SOCK_FILE"; then
  echo "FAIL: sock_rebind_async_fds already present before applying rebind patch" >&2
  exit 1
fi
if rg -Fq 'async_queue_rebind_fd' "$ASYNC_FILE"; then
  echo "FAIL: async_queue_rebind_fd already present before applying rebind patch" >&2
  exit 1
fi
rg -Fq 'release_object( acceptsock->fd );' "$SOCK_FILE"
rg -Fq 'release_object( sock->fd );' "$SOCK_FILE"

SOCK_SHA="$(shasum -a 256 "$SOCK_FILE" | awk '{print $1}')"
ASYNC_SHA="$(shasum -a 256 "$ASYNC_FILE" | awk '{print $1}')"
FILE_SHA="$(shasum -a 256 "$FILE_H" | awk '{print $1}')"
patch --forward --batch -s -p1 -d "$SOURCE" < "$REBIND_PATCH"

# Helper + export present.
rg -Fq 'sock_rebind_async_fds' "$SOCK_FILE"
rg -Fq 'cyder: sock_rebind_async_fds' "$SOCK_FILE"
rg -Fq 'async_queue_rebind_fd' "$ASYNC_FILE"
rg -Fq 'async_queue_rebind_fd' "$FILE_H"

# Call sites: rebind before release in accept_into_socket and init_socket.
python3 - "$SOCK_FILE" <<'PY'
import pathlib, sys, re
text = pathlib.Path(sys.argv[1]).read_text()

def assert_rebind_before_release(sig: str, release_needle: str) -> None:
    # Match the function definition (prototype line followed by '{'), not forward decls.
    m = re.search(re.escape(sig) + r"\n\{", text)
    assert m, f"missing definition for {sig}"
    body = text[m.start(): m.start() + 6000]
    r = body.find("sock_rebind_async_fds")
    rel = body.find(release_needle)
    assert r >= 0, f"{sig}: missing sock_rebind_async_fds"
    assert rel >= 0, f"{sig}: missing {release_needle}"
    assert r < rel, f"{sig}: rebind must come before {release_needle}"

assert_rebind_before_release(
    "static int accept_into_socket( struct sock *sock, struct sock *acceptsock )",
    "release_object( acceptsock->fd )",
)
assert_rebind_before_release(
    "static int init_socket( struct sock *sock, int family, int type, int protocol )",
    "release_object( old_fd )",
)
print("call-site order ok")
PY

# Round-trip this patch alone (prior patches stay applied).
patch --reverse --batch -s -p1 -d "$SOURCE" < "$REBIND_PATCH"
assert_eq "$(shasum -a 256 "$SOCK_FILE" | awk '{print $1}')" "$SOCK_SHA" \
  "sock.c sock-rebind-async-fd patch round-trip should restore the prior tree"
assert_eq "$(shasum -a 256 "$ASYNC_FILE" | awk '{print $1}')" "$ASYNC_SHA" \
  "async.c sock-rebind-async-fd patch round-trip should restore the prior tree"
assert_eq "$(shasum -a 256 "$FILE_H" | awk '{print $1}')" "$FILE_SHA" \
  "file.h sock-rebind-async-fd patch round-trip should restore the prior tree"
if rg -Fq 'sock_rebind_async_fds' "$SOCK_FILE"; then
  echo "FAIL: sock_rebind_async_fds remained after reversing rebind patch" >&2
  exit 1
fi

patch --forward --batch -s -p1 -d "$SOURCE" < "$REBIND_PATCH"
rg -Fq 'sock_rebind_async_fds' "$SOCK_FILE"
rg -Fq 'async_queue_rebind_fd' "$ASYNC_FILE"

echo "PASS wineserver sock-rebind-async-fd patch round-trip"
