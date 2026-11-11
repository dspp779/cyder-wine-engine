#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cyder-flush-flags.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
cp -R "$ROOT/tests/fixtures/win32u-flush-flags/." "$TMP/"
PATCH="$ROOT/patches/wine-win32u-preserve-flush-flags.patch"
patch --forward --batch --fuzz=0 -s -d "$TMP" -p1 < "$PATCH"
if patch --forward --batch --fuzz=0 --dry-run -s -d "$TMP" -p1 < "$PATCH" >/dev/null 2>&1; then
    echo 'already applied interval patch accepted forward' >&2; exit 1
fi
cat > "$TMP/probe.c" <<'C'
#include <assert.h>
#include <stdio.h>
typedef unsigned UINT;
#define GL_FLUSH_FINISHED 1u
#define GL_FLUSH_INTERVAL 2u
#define GL_FLUSH_UPDATED 4u
#define GL_FLUSH_PRESENT 8u
#define GL_FLUSH_FORCE_SWAP 16u
struct client_surface { int updated, window; };
struct opengl_drawable;
struct funcs { void (*flush)(struct opengl_drawable *, UINT); };
struct opengl_drawable { struct client_surface *client; int interval; const struct funcs *funcs; };
static UINT received;
static int calls;
static int is_client_surface_window(struct client_surface *client, int unused)
{ (void)unused; return client->window; }
static int InterlockedCompareExchange(int *p, int value, int expected)
{ int old=*p; if (old==expected) *p=value; return old; }
static void record(struct opengl_drawable *d, UINT flags)
{ assert(d->interval==7); ++calls; received=flags; }
C
cat "$TMP/dlls/win32u/opengl.c" >> "$TMP/probe.c"
cat >> "$TMP/probe.c" <<'C'
int main(void)
{
    const struct funcs funcs={record};
    for (UINT flags=0; flags<32; ++flags)
    for (int changed=0; changed<2; ++changed)
    for (int updated=0; updated<2; ++updated)
    for (int window=0; window<2; ++window)
    {
        struct client_surface client={updated,window};
        struct opengl_drawable d={&client,changed ? 0 : 7,&funcs};
        UINT expected=flags | (changed ? GL_FLUSH_INTERVAL : 0) | (updated ? GL_FLUSH_UPDATED : 0);
        calls=0; received=0;
        opengl_drawable_flush(&d,7,flags);
        if (!window) { assert(!calls && client.updated==updated && d.interval==(changed ? 0 : 7)); continue; }
        assert(client.updated==0 && d.interval==7);
        assert(calls==!!expected && received==expected);
        calls=0; received=0;
        opengl_drawable_flush(&d,7,flags); /* reuse must not re-add INTERVAL/UPDATED */
        assert(calls==!!flags && received==flags);
    }
    puts("PASS flush flags: 256 cases plus reuse, interval changes preserve PRESENT/UPDATED/FINISHED/FORCE_SWAP");
}
C
"${CYDER_HOST_CLANG:-/usr/bin/clang}" -std=c99 -Wall -Wextra -Werror "$TMP/probe.c" -o "$TMP/probe"
"$TMP/probe"
patch --reverse --forward --batch --fuzz=0 -s -d "$TMP" -p1 < "$PATCH"
cmp "$TMP/dlls/win32u/opengl.c" "$ROOT/tests/fixtures/win32u-flush-flags/dlls/win32u/opengl.c"
echo 'PASS interval patch idempotence and round-trip'
