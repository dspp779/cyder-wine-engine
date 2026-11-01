#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PATCH="$ROOT/patches/wine-win32u-full-client-visible-rect.patch"
cp -R "$ROOT/tests/fixtures/win32u-visible-rect/." "$TMP/"
patch --forward --batch --fuzz=0 -s -d "$TMP" -p1 < "$PATCH"
patch --reverse --forward --batch --fuzz=0 --dry-run -s -d "$TMP" -p1 < "$PATCH"
if patch --forward --batch --fuzz=0 --dry-run -s -d "$TMP" -p1 < "$PATCH" >/dev/null 2>&1; then
  echo "already applied patch accepted forward" >&2; exit 1
fi
# Extract the actual patched function, rather than reimplementing its predicate.
cat > "$TMP/probe.c" <<'C'
#include <assert.h>
#include <string.h>
typedef unsigned int UINT;
typedef int BOOL;
typedef void *HWND;
typedef struct {int left, top, right, bottom;} RECT;
struct window_rects {RECT window, client;};
#define FALSE 0
#define TRACE(...) ((void)0)
static int decorated_mode=1, present=0, masks=1, adjust=1;
static RECT decoration={-5,-30,5,5};
static UINT get_dpi_for_window(HWND h){return 96;}
static UINT get_thread_dpi(void){return 96;}
static int get_present_rect(HWND h, RECT *r, UINT d){if(present)*r=(RECT){1,2,3,4};return present;}
static int IsRectEmpty(const RECT *r){return r->left>=r->right || r->top>=r->bottom;}
static int EqualRect(const RECT *a,const RECT *b){return !memcmp(a,b,sizeof(*a));}
static int style_masks(HWND h,UINT s,UINT e,UINT *sm,UINT *em){*sm=s;*em=e;return masks;}
static struct {int (*pGetWindowStyleMasks)(HWND,UINT,UINT,UINT*,UINT*);} driver={style_masks}, *user_driver=&driver;
static int NtUserAdjustWindowRect(RECT *r,UINT s,int m,UINT e,UINT dpi){*r=decoration;return adjust;}
C
cat "$TMP/dlls/win32u/window.c" >> "$TMP/probe.c"
cat >> "$TMP/probe.c" <<'C'
static void check(struct window_rects r, int shaped, RECT expected){RECT got=get_visible_rect(0,shaped,1,1,&r);assert(EqualRect(&got,&expected));}
int main(void){
  RECT window={0,0,800,600}, clipped={5,30,795,595};
  struct window_rects r={window,clipped};
  check(r,0,clipped); /* ordinary decorated window unchanged */
  for(int edge=0;edge<4;edge++){
    r.client=clipped;
    switch(edge){case 0:r.client.left--;break;case 1:r.client.top--;break;case 2:r.client.right++;break;case 3:r.client.bottom++;break;}
    check(r,0,window); /* every client edge is preserved */
  }
  r.client=clipped; check(r,1,window);
  decorated_mode=0;check(r,0,window);decorated_mode=1;
  masks=0;check(r,0,window);masks=1;
  adjust=0;check(r,0,window);adjust=1;
  r.client=window;check(r,0,window);
  r.client=clipped;present=1;check(r,0,(RECT){1,2,3,4});
  return 0;
}
C
/usr/bin/clang -std=c99 -Wall -Wextra -Wno-unused-parameter -Werror "$TMP/probe.c" -o "$TMP/probe"
"$TMP/probe"
patch --reverse --forward --batch --fuzz=0 -s -d "$TMP" -p1 < "$PATCH"
cmp "$TMP/dlls/win32u/window.c" "$ROOT/tests/fixtures/win32u-visible-rect/dlls/win32u/window.c"
# Verify both build ownership and generated manifest contents.
rg -F 'apply_cyder_patch "$OGOM/patches/wine-win32u-full-client-visible-rect.patch"' "$ROOT/scripts/build-wine.sh" >/dev/null
bash "$ROOT/scripts/write-engine-manifest.sh" --output "$TMP/manifest.json" --version test --ntdll-sha256 "$(printf '%064d' 0)" >/dev/null
python3 - "$TMP/manifest.json" <<'PY'
import json,sys
p=json.load(open(sys.argv[1]))['patches']
assert p.count('wine-win32u-full-client-visible-rect.patch') == 1
assert p.index('cyder-kernelbase-disk-free-space-fallback.patch') < p.index('wine-win32u-full-client-visible-rect.patch') < p.index('maplestory-cx26-message-wait-handoff.patch')
PY
echo 'PASS test-win32u-visible-rect'
