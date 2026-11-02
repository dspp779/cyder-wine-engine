#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cyder-gdi-client-view.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/dlls/winemac.drv"
cp "$ROOT/tests/fixtures/winemac-surface-profile/surface.c" "$TMP/dlls/winemac.drv/"
patch --forward --batch --fuzz=0 -s -d "$TMP" -p1 < "$ROOT/patches/wine-winemac-hide-client-view-on-gdi-flush.patch"
python3 - "$TMP" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]);s=(p/'dlls/winemac.drv/surface.c').read_text();start=s.index('static BOOL macdrv_surface_flush(');end=s.index('/***********************************************************************\n *              macdrv_surface_destroy',start);(p/'actual.h').write_text(s[start:end])
PY
cat > "$TMP/test.c" <<'C'
#include <assert.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
typedef int BOOL;typedef unsigned UINT;typedef unsigned char BYTE;
#define TRUE 1
#define NULL_VIEW ((void *)(uintptr_t)42)
typedef struct {int left,top,right,bottom;} RECT;
typedef struct {struct {int biWidth,biHeight;unsigned biSizeImage;} bmiHeader;} BITMAPINFO;
typedef int CGImageAlphaInfo;typedef void *CGColorSpaceRef;typedef void *CGImageRef;typedef void *CGDataProviderRef;
enum {kCGImageAlphaPremultipliedFirst=1,kCGImageAlphaNoneSkipFirst,kCGBitmapByteOrder32Little,kCGRenderingIntentDefault,kCGColorSpaceSRGB};
struct window_surface {int alpha_mask;void *hwnd;};
struct macdrv_window_surface {struct window_surface header;void *window,*provider;};
struct macdrv_win_data {void *client_view;};
static struct macdrv_win_data data;static int available,hidden,released,colored,shaped,retina_on;
static struct macdrv_window_surface *get_mac_surface(struct window_surface *s){return (void *)s;}
static struct macdrv_win_data *get_win_data(void *h){assert(h==(void *)1);assert(colored);return available?&data:NULL;}
static void release_win_data(struct macdrv_win_data *d){assert(d==&data);++released;}
static void macdrv_set_view_hidden(void *view,BOOL yes){assert(view==NULL_VIEW && yes);assert(colored);++hidden;}
static void *CGColorSpaceCreateWithName(int n){return (void *)(uintptr_t)n;}
static void CGColorSpaceRelease(void *v){}
static void *CGImageCreate(int w,int h,int a,int b,int stride,void *cs,int flags,void *p,void *decode,int interpolate,int intent){return (void *)2;}
static int cgrect_from_rect(RECT r){return r.right;}
static void macdrv_window_set_color_image(void *w,void *i,int r,int d){++colored;}
static void CGImageRelease(void *v){}
static void macdrv_window_set_shape_image(void *w,void *i){++shaped;}
static unsigned char shape[16];
static void *data_provider_create(unsigned size,void **bits){assert(size<=sizeof(shape));*bits=shape;return (void *)3;}
static void *CGImageMaskCreate(int w,int h,int a,int b,int stride,void *p,void *decode,int interpolate){return (void *)4;}
static void CGDataProviderRelease(void *v){}
#include "actual.h"
int main(void){
 struct macdrv_window_surface s={.header={.hwnd=(void *)1}};RECT r={0,0,10,10};BITMAPINFO info={{10,10,16}};unsigned char bits[16]={0};
 for(int present=0;present<2;present++)for(int view=0;view<2;view++)for(int shape_mode=0;shape_mode<3;shape_mode++){
  available=present;data.client_view=view?NULL_VIEW:NULL;hidden=released=colored=shaped=0;
  assert(macdrv_surface_flush(&s.header,&r,&r,&info,bits,shape_mode!=0,&info,shape_mode==2?bits:NULL));
  assert(colored==1 && shaped==(shape_mode!=0));assert(hidden==(present&&view));assert(released==present);
  if(present)assert(!data.client_view);else assert(data.client_view==(view?NULL_VIEW:NULL));
 }
 return 0;
}
C
"${CYDER_HOST_CLANG:-/usr/bin/clang}" -std=c99 -Wall -Wextra -Werror -Wno-unused-parameter -I"$TMP" "$TMP/test.c" -o "$TMP/test"
"$TMP/test"
# Both independent patch orders remain reversible; build uses hide then profile.
patch --forward --batch --fuzz=0 -s -d "$TMP" -p1 < "$ROOT/patches/cyder-winemac-surface-profile.patch"
patch --reverse --forward --batch --fuzz=0 -s -d "$TMP" -p1 < "$ROOT/patches/cyder-winemac-surface-profile.patch"
patch --reverse --forward --batch --fuzz=0 -s -d "$TMP" -p1 < "$ROOT/patches/wine-winemac-hide-client-view-on-gdi-flush.patch"
cmp "$TMP/dlls/winemac.drv/surface.c" "$ROOT/tests/fixtures/winemac-surface-profile/surface.c"
patch --forward --batch --fuzz=0 -s -d "$TMP" -p1 < "$ROOT/patches/cyder-winemac-surface-profile.patch"
patch --forward --batch --fuzz=0 -s -d "$TMP" -p1 < "$ROOT/patches/wine-winemac-hide-client-view-on-gdi-flush.patch"
patch --reverse --forward --batch --fuzz=0 -s -d "$TMP" -p1 < "$ROOT/patches/wine-winemac-hide-client-view-on-gdi-flush.patch"
patch --reverse --forward --batch --fuzz=0 -s -d "$TMP" -p1 < "$ROOT/patches/cyder-winemac-surface-profile.patch"
cmp "$TMP/dlls/winemac.drv/surface.c" "$ROOT/tests/fixtures/winemac-surface-profile/surface.c"
echo 'PASS actual GDI flush: missing data/view, stale-view hide, shape updates and independent profiler patch round-trip'
