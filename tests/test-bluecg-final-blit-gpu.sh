#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cyder-bluecg-gpu.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/dlls/gdi32"
python3 "$ROOT/tests/materialize-present-fixture.py" "$ROOT/tests/fixtures/gdi-window-blit-profile/baseline.json" "$TMP/dlls/gdi32"
patch --forward --batch --fuzz=0 -s -d "$TMP" -p1 < "$ROOT/patches/cyder-gdi-window-blit-profile.patch"

patch --forward --batch --fuzz=0 -s -d "$TMP" -p1 < "$ROOT/patches/cyder-bluecg-final-blit-halftone.patch"
cp "$TMP/dlls/gdi32/dc.c" "$TMP/baseline.c"
patch --forward --batch --fuzz=0 -s -d "$TMP" -p1 < "$ROOT/patches/cyder-bluecg-final-blit-gpu.patch"
python3 - "$TMP" <<'EXTRACT'
from pathlib import Path
import sys
p=Path(sys.argv[1]);s=(p/'dlls/gdi32/dc.c').read_text();a=s.index('/* Experimental final-window filter;');b=s.index('BOOL WINAPI StretchBlt(',a);brace=s.index('{',b);i=brace+1;depth=1
while depth:
 if s[i]=='{':depth+=1
 if s[i]=='}':depth-=1
 i+=1
(p/'wrapper.inc').write_text(s[a:i])
EXTRACT
cat > "$TMP/test.c" <<'C'
#include <assert.h>
#include <stdint.h>
#include <string.h>
#include <wchar.h>
#include <wctype.h>
typedef void *HMODULE; typedef int BOOL; typedef uint32_t DWORD; typedef uintptr_t DWORD_PTR; typedef int INT; typedef wchar_t WCHAR; typedef int INIT_ONCE; typedef intptr_t HDC; typedef void *HWND;
typedef struct { int x,y; } POINT;
typedef struct { int left,top,right,bottom; } RECT;
typedef struct { int print,emf; } DC_ATTR;
#define WINAPI
#define CALLBACK
#define TRUE 1
#define FALSE 0
#define MAX_PATH 260
#define INIT_ONCE_STATIC_INIT 0
#define SRCCOPY 0xcc0020
#define HALFTONE 4
#define ARRAY_SIZE(a) (sizeof(a)/sizeof((a)[0]))
#define WindowProcess 0
#define LOAD_LIBRARY_SEARCH_SYSTEM32 0x800
#define MM_TEXT 1
#define GM_COMPATIBLE 1
static int loads,draws,hides,gpu_success=1,library_available=1,operations,profile_api,mapping_bad;
static DWORD error; static int enabled=1, right_exe=1, owner=7, width=1100, height=791, mode=3, applied, success=1, profile_mode, profile_on=1;
static POINT origin={17,23}; static DC_ATTR attr;
static DWORD GetLastError(void){return error;} static void SetLastError(DWORD v){error=v;}
static DWORD GetEnvironmentVariableA(const char *n,char *v,DWORD cap){assert(!strcmp(n,"CYDER_BLUECG_BLIT_FILTER"));assert(cap>9);error=203;if(!enabled)return 0;strcpy(v,enabled==1?"gpu-linear":enabled==2?"gpu-nearest":"unknown!");return enabled==1?10:enabled==2?11:8;}
static DWORD GetModuleFileNameW(void *m,WCHAR *v,DWORD cap){(void)m;assert(cap>=30);wcscpy(v,right_exe?L"C:\\game\\bluecg.exe":L"C:\\other.exe");return wcslen(v);}
static int wcsicmp(const WCHAR *a,const WCHAR *b){while(*a && towlower(*a)==towlower(*b)){a++;b++;}return towlower(*a)-towlower(*b);}
static BOOL InitOnceExecuteOnce(INIT_ONCE *o,BOOL (*cb)(INIT_ONCE*,void*,void**),void *p,void **c){if(!*o){cb(o,p,c);*o=1;}return TRUE;}
static DWORD GetCurrentProcessId(void){return 7;}
static DWORD GetCurrentThreadId(void){return 7;}
static DWORD GetWindowThreadProcessId(HWND w,DWORD *pid){(void)w;(void)pid;return 7;}
static HWND NtUserWindowFromDC(HDC dc){error=321;return dc==1?(HWND)2:NULL;}
static void *NtUserQueryWindow(HWND w,int q){(void)w;(void)q;return (void*)(uintptr_t)owner;}
static BOOL NtUserGetClientRect(HWND w,RECT *r,int dpi){(void)w;(void)dpi;*r=(RECT){0,0,width,height};error=432;return TRUE;}
static BOOL GetBrushOrgEx(HDC dc,POINT *p){(void)dc;*p=origin;error=543;return TRUE;}
static int SetStretchBltMode(HDC dc,int v){int old=mode;(void)dc;mode=v;error=654;return old;}
static BOOL SetBrushOrgEx(HDC dc,int x,int y,POINT *old){(void)dc;if(old)*old=origin;origin=(POINT){x,y};error=765;return TRUE;}
static BOOL is_meta_dc(HDC dc){return dc==9;}
static DC_ATTR *get_dc_attr(HDC dc){return dc?&attr:NULL;}
static void print_call_start_page(DC_ATTR *a){(void)a;}
static BOOL METADC_StretchBlt(HDC dc,...){(void)dc;return TRUE;}
static BOOL EMFDC_StretchBlt(DC_ATTR *a,...){(void)a;return TRUE;}
static uint64_t cyder_gdi_profile_begin(void){return profile_on?1:0;}
static void cyder_gdi_profile_record(HWND w,HDC dc,int x,int y,int a,int b,int c,int d,DWORD r,int api,uint64_t begin,BOOL ok){(void)w;(void)dc;(void)x;(void)y;(void)a;(void)b;(void)c;(void)d;(void)r;profile_api=api;(void)begin;(void)ok;profile_mode=mode;error=987;}
static BOOL NtGdiStretchBlt(HDC dc,int x,int y,int a,int b,HDC src,int sx,int sy,int sw,int sh,DWORD r,int flags){(void)dc;(void)x;(void)y;(void)a;(void)b;(void)src;(void)sx;(void)sy;(void)sw;(void)sh;(void)r;(void)flags;operations++;if(mode==4){assert(origin.x==0&&origin.y==0);applied++;}if(!success)error=901;return success;}
static BOOL fake_draw(HWND w,HDC src,int sw,int sh,int dw,int dh,int linear){assert(w==(HWND)2&&src==3&&sw==961&&sh==721&&dw==1100&&dh==791);assert(linear==(enabled==1));draws++;error=888;return gpu_success;}
static void fake_hide(HWND w){assert(w==(HWND)2);hides++;error=889;}
static HMODULE LoadLibraryExW(const WCHAR *s,void *file,DWORD flags){assert(!wcscmp(s,L"cyder_bluecg_gpu.dll")&&!file&&flags==0x800);loads++;error=999;return library_available?(HMODULE)1:NULL;}
static void *GetProcAddress(HMODULE m,const char *s){assert(m==(HMODULE)1);return !strcmp(s,"bluecg_gpu_present")?(void*)fake_draw:(void*)fake_hide;}
static int GetMapMode(HDC dc){(void)dc;return mapping_bad?2:MM_TEXT;}
static int GetGraphicsMode(HDC dc){(void)dc;return GM_COMPATIBLE;}
static DWORD GetLayout(HDC dc){(void)dc;return 0;}
static BOOL GetViewportOrgEx(HDC dc,POINT *p){(void)dc;*p=(POINT){0,0};return TRUE;}
static BOOL GetWindowOrgEx(HDC dc,POINT *p){(void)dc;*p=(POINT){0,0};return TRUE;}
#include "dlls/gdi32/cyder_bluecg_gpu.h"
#include "wrapper.inc"
static void reset(void){bluecg_gpu_once=0;bluecg_gpu_load_once=0;bluecg_gpu_mode=0;bluecg_gpu_module=NULL;bluecg_gpu_draw=NULL;bluecg_gpu_hide_window=NULL;loads=draws=hides=operations=profile_api=mapping_bad=0;gpu_success=library_available=1;bluecg_filter_once=0;bluecg_filter_enabled=0;enabled=right_exe=1;owner=7;width=1100;height=791;mode=3;origin=(POINT){17,23};attr=(DC_ATTR){0,0};applied=profile_mode=0;success=profile_on=1;error=77;}
static void call(HDC dc,int x,int w,int sw,DWORD rop){assert(StretchBlt(dc,x,0,w,791,3,0,0,sw,721,rop)==success);assert(error==(success?77:901));assert(mode==3&&origin.x==17&&origin.y==23);}
int main(void){
 reset();call(1,0,1100,961,SRCCOPY);assert(draws==1&&loads==1&&!operations&&profile_api==3);
 reset();enabled=2;call(1,0,1100,961,SRCCOPY);assert(draws==1&&profile_api==3);
 reset();gpu_success=0;call(1,0,1100,961,SRCCOPY);assert(draws==1&&operations==1&&profile_api==2&&hides==1);
 reset();gpu_success=0;success=0;call(1,0,1100,961,SRCCOPY);assert(operations==1&&error==901);
 reset();library_available=0;call(1,0,1100,961,SRCCOPY);assert(loads==1&&!draws&&operations==1&&profile_api==2);
 reset();enabled=0;call(1,0,1100,961,SRCCOPY);assert(!loads&&!draws&&operations==1);
 reset();enabled=3;call(1,0,1100,961,SRCCOPY);assert(!loads);
 reset();right_exe=0;call(1,0,1100,961,SRCCOPY);assert(!loads);
 reset();owner=8;call(1,0,1100,961,SRCCOPY);assert(!loads);
 reset();mapping_bad=1;call(1,0,1100,961,SRCCOPY);assert(!loads);
 reset();call(3,0,1100,961,SRCCOPY);assert(!loads);
 reset();call(1,1,1100,961,SRCCOPY);assert(!loads);
 reset();call(1,0,1099,961,SRCCOPY);assert(!loads);
 reset();call(1,0,1100,960,SRCCOPY);assert(!loads);
 reset();call(1,0,1100,961,0);assert(!loads);
 reset();attr.emf=1;call(1,0,1100,961,SRCCOPY);assert(!loads);
 reset();attr.print=1;call(1,0,1100,961,SRCCOPY);assert(!loads);
 return 0;
}
C
"${CYDER_HOST_CLANG:-/usr/bin/clang}" -std=c11 -Wall -Wextra -Werror -Wno-unused-parameter -I"$TMP" "$TMP/test.c" -o "$TMP/test"
"$TMP/test"
python3 - "$ROOT" "$TMP" <<'IDEMPOTENCE'
from pathlib import Path
import os,subprocess,sys
root,tmp=map(Path,sys.argv[1:]);source=(root/'scripts/build-wine.sh').read_text();a=source.index('apply_cyder_patch() {');b=source.index('\n}\n',a)+3
before=(tmp/'dlls/gdi32/dc.c').read_bytes();env=os.environ.copy();env.update(WINE_SRC=str(tmp),DRY_RUN='0')
script=source[a:b]+'\n'
for name in ['cyder-bluecg-final-blit-halftone.patch','cyder-bluecg-final-blit-gpu.patch']*2:
 subprocess.run(['/bin/bash','-c',script+'apply_cyder_patch "$1"','patch-test',str(root/'patches'/name)],env=env,check=True)
assert (tmp/'dlls/gdi32/dc.c').read_bytes()==before
IDEMPOTENCE
patch --reverse --forward --batch --fuzz=0 -s -d "$TMP" -p1 < "$ROOT/patches/cyder-bluecg-final-blit-gpu.patch"
cmp "$TMP/dlls/gdi32/dc.c" "$TMP/baseline.c"
echo 'PASS BlueCG GPU hook: opt-in/exe/owner/geometry/mapping guards, lazy system32 load, hardware submission marker, fallback, LastError and reversible patch'
