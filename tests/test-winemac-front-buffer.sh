#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cyder-gl-present.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
cp -R "$ROOT/tests/fixtures/winemac-front-buffer/." "$TMP/"
PATCH="$ROOT/patches/cyder-winemac-gl-front-buffer-present.patch"
patch --forward --batch --fuzz=0 -s -d "$TMP" -p1 < "$PATCH"
if patch --forward --batch --fuzz=0 --dry-run -s -d "$TMP" -p1 < "$PATCH" >/dev/null 2>&1; then
  echo 'already applied front-buffer patch accepted forward' >&2; exit 1
fi
cat > "$TMP/probe.c" <<'C'
#include <assert.h>
#include <string.h>
typedef unsigned UINT;
typedef int BOOL;
#define TRUE 1
#define FALSE 0
#define GL_FLUSH_INTERVAL 1u
#define GL_FLUSH_UPDATED 2u
#define GL_FLUSH_PRESENT 4u
#define TRACE(...) ((void)0)
struct macdrv_client_surface { void *cocoa_view; };
struct opengl_drawable { struct macdrv_client_surface *client; int interval; };
struct macdrv_context { void *context, *cglcontext, *read_view; };
static struct { struct macdrv_context *glReserved2; } teb;
#define NtCurrentTeb() (&teb)
static char events[16];
static int pending, make_arg;
static void record(char event) { size_t n = strlen(events); assert(n + 1 < sizeof(events)); events[n] = event; events[n+1] = 0; }
static struct macdrv_client_surface *impl_from_client_surface(struct macdrv_client_surface *client) { return client; }
static void set_swap_interval(struct macdrv_context *context, int interval) { assert(context == teb.glReserved2 && interval == 2); record('I'); }
static int macdrv_opengl_context_backing_sync_pending(void *context) { assert(context); return pending; }
static void make_context_current(struct macdrv_context *context, BOOL value) { assert(context == teb.glReserved2); make_arg = value; record('M'); }
static void macdrv_flush_opengl_context(void *context) { assert(context); record('F'); }
static void client_surface_present(struct macdrv_client_surface *client) { assert(client); record('P'); }
C
cat "$TMP/dlls/winemac.drv/opengl.c" >> "$TMP/probe.c"
cat >> "$TMP/probe.c" <<'C'
int main(void)
{
    int token;
    struct macdrv_client_surface client = { &token };
    struct opengl_drawable base = { &client, 2 };
    struct macdrv_context context = { &token, &token, &token };
    /* A null context must remain safe, including the swap notification. */
    macdrv_surface_flush(&base, 7); assert(!events[0]);
    assert(macdrv_surface_swap(&base)); assert(!strcmp(events, "P"));
    teb.glReserved2 = &context;
    for (UINT flags = 0; flags < 8; ++flags)
    for (pending = 0; pending < 2; ++pending)
    for (int matching_view = 0; matching_view < 2; ++matching_view)
    {
        char expected[16] = "";
        events[0] = 0;
        context.read_view = matching_view ? client.cocoa_view : NULL;
        if (flags & GL_FLUSH_INTERVAL) strcat(expected, "I");
        if ((flags & GL_FLUSH_UPDATED) || pending) strcat(expected, "M");
        if (flags & GL_FLUSH_PRESENT) strcat(expected, "FP");
        macdrv_surface_flush(&base, flags);
        assert(!strcmp(events, expected));
        if ((flags & GL_FLUSH_UPDATED) || pending) assert(make_arg == matching_view);
    }
    for (pending = 0; pending < 2; ++pending)
    {
        events[0] = 0;
        assert(macdrv_surface_swap(&base));
        assert(!strcmp(events, pending ? "MFP" : "FP"));
        if (pending) assert(make_arg == FALSE);
    }
    return 0;
}
C
"${CYDER_HOST_CLANG:-/usr/bin/clang}" -std=c99 -Wall -Wextra -Werror "$TMP/probe.c" -o "$TMP/probe"
"$TMP/probe"
patch --reverse --forward --batch --fuzz=0 -s -d "$TMP" -p1 < "$PATCH"
cmp "$TMP/dlls/winemac.drv/opengl.c" "$ROOT/tests/fixtures/winemac-front-buffer/dlls/winemac.drv/opengl.c"
echo 'PASS winemac front-buffer present (actual functions, flag matrix, null context, A6 conditional sync, round-trip)'
