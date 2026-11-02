#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cyder-context-bind.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
cp -R "$ROOT/tests/fixtures/win32u-context-bind/." "$TMP/"
PATCH="$ROOT/patches/wine-win32u-no-present-on-context-bind.patch"
patch --forward --batch --fuzz=0 -s -d "$TMP" -p1 < "$PATCH"
if patch --forward --batch --fuzz=0 --dry-run -s -d "$TMP" -p1 < "$PATCH" >/dev/null 2>&1; then
  echo 'already applied context-bind patch accepted forward' >&2; exit 1
fi
cat > "$TMP/probe.c" <<'C'
#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
typedef int BOOL;
typedef uintptr_t HDC;
#define TRUE 1
#define FALSE 0
#define GL_FLUSH_PRESENT 8u
#define TRACE(...) ((void)0)
#define WARN(...) ((void)0)
struct client_surface { void *hwnd; };
struct opengl_drawable { struct client_surface *client; int interval; };
struct wgl_context { struct opengl_drawable *draw, *read; int format; void *driver_private; };
static struct { struct wgl_context *glContext; } teb;
#define NtCurrentTeb() (&teb)
static struct opengl_drawable draw, read;
static int flushes, bindings, succeed;
static struct opengl_drawable *get_updated_drawable(HDC dc, int format, struct opengl_drawable *old)
{ (void)format; return dc ? (dc == 1 ? &draw : &read) : old; }
static void opengl_drawable_add_ref(struct opengl_drawable *d) { assert(d); }
static void opengl_drawable_release(struct opengl_drawable *d) { assert(d); }
static void opengl_drawable_set_context(struct opengl_drawable *d, struct wgl_context *c) { (void)d; (void)c; }
static void set_window_opengl_drawable(void *hwnd, struct opengl_drawable *d, BOOL current)
{ (void)hwnd; assert(d); (void)current; }
static void context_exchange_drawables(struct wgl_context *c, struct opengl_drawable **d, struct opengl_drawable **r)
{ struct opengl_drawable *old_d=c->draw,*old_r=c->read; c->draw=*d; c->read=*r; *d=old_d; *r=old_r; }
static void opengl_drawable_flush(struct opengl_drawable *d, int interval, unsigned flags)
{ assert(d && d->interval == interval); assert(!(flags & GL_FLUSH_PRESENT)); assert(flags == 0); ++flushes; }
static BOOL make_current(struct opengl_drawable *d, struct opengl_drawable *r, void *private)
{ assert(d && r); (void)private; ++bindings; return succeed; }
static const struct { BOOL (*p_make_current)(struct opengl_drawable *, struct opengl_drawable *, void *); } driver = {make_current};
#define driver_funcs (&driver)
C
cat "$TMP/dlls/win32u/opengl.c" >> "$TMP/probe.c"
cat >> "$TMP/probe.c" <<'C'
int main(void)
{
    struct client_surface client = {(void *)1};
    draw.client = read.client = &client;
    draw.interval = 1; read.interval = 2;
    for (int split=0; split<2; ++split)
    {
        struct wgl_context context = {0};
        teb.glContext=NULL; flushes=bindings=0; succeed=1;
        assert(context_sync_drawables(&context,1,split ? 2 : 1));
        assert(bindings==1 && flushes==2); /* sync both drawables, never present */
        assert(teb.glContext==&context && context.draw==&draw && context.read==(split ? &read : &draw));
        flushes=bindings=0;
        assert(context_sync_drawables(&context,0,0));
        assert(bindings==0 && flushes==0); /* already-current fast path */
    }
    struct wgl_context failed = {0};
    teb.glContext=NULL; flushes=bindings=0; succeed=0;
    assert(!context_sync_drawables(&failed,1,1));
    assert(bindings==1 && flushes==0 && !teb.glContext); /* failed binding never presents */
    puts("PASS context bind syncs without presenting (same/split drawables, reuse, failure)");
}
C
"${CYDER_HOST_CLANG:-/usr/bin/clang}" -std=c99 -Wall -Wextra -Werror "$TMP/probe.c" -o "$TMP/probe"
"$TMP/probe"
patch --reverse --forward --batch --fuzz=0 -s -d "$TMP" -p1 < "$PATCH"
cmp "$TMP/dlls/win32u/opengl.c" "$ROOT/tests/fixtures/win32u-context-bind/dlls/win32u/opengl.c"
# Also validate migration of the previous workaround without touching live Wine.
mkdir -p "$TMP/migrate/dlls/winemac.drv"
cp "$ROOT/tests/fixtures/winemac-front-buffer/dlls/winemac.drv/opengl.c" "$TMP/migrate/dlls/winemac.drv/"
PRESENT="$ROOT/patches/cyder-winemac-gl-front-buffer-present.patch"
OBSOLETE="$ROOT/patches/obsolete/cyder-winemac-gl-flush-no-buffer-swap.patch"
patch --forward --batch -s -d "$TMP/migrate" -p1 < "$PRESENT"
cp "$TMP/migrate/dlls/winemac.drv/opengl.c" "$TMP/upstream-present.c"
patch --forward --batch -s -d "$TMP/migrate" -p1 < "$OBSOLETE"
patch --reverse --forward --batch -s -d "$TMP/migrate" -p1 < "$OBSOLETE"
cmp "$TMP/migrate/dlls/winemac.drv/opengl.c" "$TMP/upstream-present.c"
echo 'PASS legacy no-buffer-swap migration restores upstream presentation'
