#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/assert.sh"
ARCHIVE="${CX26_SOURCE_ARCHIVE:-$ROOT/tools/archives/crossover-sources-26.3.0.tar.gz}"
SOCK_PATCH="$ROOT/patches/cyder-wineserver-sock-reselect-pseudo-fd.patch"
FD_PATCH="$ROOT/patches/cyder-wineserver-poll-slot-guard.patch"

if [[ ! -f "$ARCHIVE" ]]; then
  echo "SKIP wineserver poll-guard patches: source archive not found at $ARCHIVE"
  exit 0
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cyder-ws-patches.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

tar -xzf "$ARCHIVE" -C "$TMP_DIR" sources/wine/server/fd.c sources/wine/server/sock.c
SOURCE="$TMP_DIR/sources/wine"
SOCK_FILE="$SOURCE/server/sock.c"
FD_FILE="$SOURCE/server/fd.c"
SOCK_SHA="$(shasum -a 256 "$SOCK_FILE" | awk '{print $1}')"
FD_SHA="$(shasum -a 256 "$FD_FILE" | awk '{print $1}')"

ASSERT_LINE='assert( poll_users[user] == fd );'
count_assert() {
  rg -Fc "$ASSERT_LINE" "$FD_FILE" || true
}

# Upstream must still carry the unguarded code both patches target. If a future
# CrossOver rebase fixes either one, the patch has to be re-reviewed rather than
# silently offset onto different code.
rg -Fq 'int ev = sock_get_poll_events( sock->fd );' "$SOCK_FILE"
assert_eq "$(count_assert)" "2" \
  "upstream fd.c should assert the poll slot in both remove_poll_user and set_fd_events"

patch --forward --batch -s -p1 -d "$SOURCE" < "$SOCK_PATCH"
patch --forward --batch -s -p1 -d "$SOURCE" < "$FD_PATCH"

# sock_reselect() must bail out before touching a pseudo-fd.
rg -Fq 'if (!sock->type || !sock->fd) return;' "$SOCK_FILE"

# set_fd_events() must report and skip instead of aborting wineserver, which
# would hang every client process in the prefix.
rg -Fq 'poll_users[user] != fd' "$FD_FILE"
rg -Fq 'stale poll slot' "$FD_FILE"

# remove_poll_user() keeps its assert on purpose: skipping it would leak the
# poll slot and leave active_users non-zero, so wineserver would never exit.
assert_eq "$(count_assert)" "1" \
  "only remove_poll_user should still assert the poll slot after the guard patch"
rg -Uq 'static void remove_poll_user\( struct fd \*fd, int user \)\n\{\n    assert\( user >= 0 \);\n    assert\( poll_users\[user\] == fd \);' "$FD_FILE"

patch --reverse --batch -s -p1 -d "$SOURCE" < "$FD_PATCH"
patch --reverse --batch -s -p1 -d "$SOURCE" < "$SOCK_PATCH"
assert_eq "$(shasum -a 256 "$SOCK_FILE" | awk '{print $1}')" "$SOCK_SHA" \
  "sock.c patch round-trip should restore the original source"
assert_eq "$(shasum -a 256 "$FD_FILE" | awk '{print $1}')" "$FD_SHA" \
  "fd.c patch round-trip should restore the original source"

echo "PASS wineserver poll-guard patch round-trip"
