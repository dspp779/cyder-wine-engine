#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cyder-gdi-profile.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/dlls/gdi32"
python3 "$ROOT/tests/materialize-present-fixture.py" "$ROOT/tests/fixtures/gdi-window-blit-profile/baseline.json" "$TMP/dlls/gdi32"
cp -R "$TMP/dlls/gdi32" "$TMP/baseline"
patch --forward --batch --fuzz=0 -s -d "$TMP" -p1 < "$ROOT/patches/cyder-gdi-window-blit-profile.patch"
python3 - "$TMP" <<'EXTRACT'
from pathlib import Path
import sys
p=Path(sys.argv[1]);s=(p/'dlls/gdi32/dc.c').read_text();out=''
for name in ('BOOL WINAPI DECLSPEC_HOTPATCH BitBlt(', 'BOOL WINAPI StretchBlt('):
 start=s.index(name);begin=s.index('{',start);depth=1;i=begin+1
 while depth:
  if s[i]=='{':depth+=1
  elif s[i]=='}':depth-=1
  i+=1
 out+=s[start:i]+'\n'
(p/'wrapper.inc').write_text(out)
EXTRACT
cat > "$TMP/test.c" <<'C'
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
typedef int BOOL; typedef unsigned long DWORD; typedef int INIT_ONCE; typedef int SRWLOCK; typedef intptr_t HANDLE; typedef int32_t HRESULT;
typedef struct { long left,top,right,bottom; } RECT;
typedef struct { long long QuadPart; } LARGE_INTEGER;
typedef struct { uint32_t dwLowDateTime,dwHighDateTime; } FILETIME;
typedef union { struct { uint32_t LowPart,HighPart; }; uint64_t QuadPart; } ULARGE_INTEGER;
#define CALLBACK
#define TRUE 1
#define FALSE 0
#define MAX_PATH 260
#define INIT_ONCE_STATIC_INIT 0
#define SRWLOCK_INIT 0
#define INVALID_HANDLE_VALUE ((HANDLE)-1)
#define GENERIC_WRITE 1
#define FILE_SHARE_READ 2
#define CREATE_NEW 3
#define FILE_ATTRIBUTE_NORMAL 4
#define DDSCAPS_PRIMARYSURFACE 1
#define DDRAW_SWAPPED 2
static int enabled, clocks, creates, closes, errors, short_write, create_fail;
static DWORD last_error;
static DWORD GetLastError(void) {return last_error;}
static void SetLastError(DWORD v) {last_error=v;}
static long long now_qpc=100000;
static char output[200000]; static size_t output_used;
#define ERR(...) (++errors)
static DWORD GetEnvironmentVariableA(const char *name,char *dst,DWORD cap) { assert(!strcmp(name,"CYDER_GDI_PROFILE_DIR")); if(!enabled){last_error=203;return 0;} assert(cap>5);strcpy(dst,"Z:\\x");return 4; }
static DWORD GetCurrentProcessId(void) { return 123; }
static DWORD GetCurrentThreadId(void) { return 7; }
static HANDLE CreateFileA(const char *path,DWORD access,DWORD sharing,void *security,DWORD creation,DWORD attr,void *template) { (void)security;(void)template;assert(strstr(path,"gdi-present-0000007b.csv"));assert(access==GENERIC_WRITE&&sharing==FILE_SHARE_READ&&creation==CREATE_NEW&&attr==FILE_ATTRIBUTE_NORMAL);creates++;return create_fail?INVALID_HANDLE_VALUE:1; }
static BOOL WriteFile(HANDLE file,const char *data,DWORD size,DWORD *done,void *async) { (void)async;assert(file==1);assert(output_used+size<sizeof(output));memcpy(output+output_used,data,size);output_used+=size;output[output_used]=0;*done=short_write?size-1:size;return TRUE; }
static BOOL CloseHandle(HANDLE file) { assert(file==1);closes++;return TRUE; }
static BOOL QueryPerformanceCounter(LARGE_INTEGER *v) { clocks++;v->QuadPart=now_qpc;now_qpc+=100;return TRUE; }
static BOOL QueryPerformanceFrequency(LARGE_INTEGER *v) { v->QuadPart=10000000;return TRUE; }
static void GetSystemTimePreciseAsFileTime(FILETIME *ft) { uint64_t v=116444736000000000ULL+10000000;ft->dwLowDateTime=v;ft->dwHighDateTime=v>>32; }
static BOOL InitOnceExecuteOnce(INIT_ONCE *once,BOOL (*cb)(INIT_ONCE*,void*,void**),void *arg,void **ctx) { if(!*once){assert(cb(once,arg,ctx));*once=1;}return TRUE; }
static void AcquireSRWLockExclusive(SRWLOCK *l) { assert(!*l);*l=1; }
static void ReleaseSRWLockExclusive(SRWLOCK *l) { assert(*l);*l=0; }
static void SetRect(RECT *r,int l,int t,int x,int y) { r->left=l;r->top=t;r->right=x;r->bottom=y; }

typedef void *HWND; typedef void *HDC; typedef int INT;
#define WINAPI
#define DECLSPEC_HOTPATCH
typedef struct { void *print; int emf; } DC_ATTR;
static DC_ATTR attr;
static BOOL call_success=TRUE;
static int operations;
static BOOL NtUserGetClientRect(HWND w,RECT *r,unsigned dpi) { (void)dpi;assert(w==(HWND)2);SetRect(r,0,0,961,721);last_error=777;return TRUE; }
static int GetStretchBltMode(HDC dc) { (void)dc;last_error=444;return 3; }
#include "dlls/gdi32/cyder_gdi_profile.h"
static BOOL is_meta_dc(HDC dc) {return dc==(HDC)9;}
static DC_ATTR *get_dc_attr(HDC dc) {return dc?&attr:NULL;}
static void print_call_start_page(DC_ATTR *a) {(void)a;}
static BOOL METADC_BitBlt(HDC dc,...) {(void)dc;return TRUE;}
static BOOL METADC_StretchBlt(HDC dc,...) {(void)dc;return TRUE;}
static BOOL EMFDC_BitBlt(DC_ATTR *a,...) {(void)a;return TRUE;}
static BOOL EMFDC_StretchBlt(DC_ATTR *a,...) {(void)a;return TRUE;}
static HWND NtUserWindowFromDC(HDC dc) {last_error=222;return dc==(HDC)1?(HWND)2:NULL;}
static BOOL NtGdiBitBlt(HDC dc,...) {(void)dc;operations++;if(!call_success)last_error=901;return call_success;}
static BOOL NtGdiStretchBlt(HDC dc,...) {(void)dc;operations++;if(!call_success)last_error=901;return call_success;}
#include "wrapper.inc"
static void reset(void) {cyder_gdi_profile_close();cyder_gdi_profile_once=0;cyder_gdi_profile_used=0;output_used=0;output[0]=0;clocks=creates=closes=errors=short_write=create_fail=0;operations=0;last_error=77;call_success=TRUE;}
int main(void) {
 int before,i;DWORD used;
 reset();enabled=0;assert(BitBlt((HDC)1,0,0,960,720,(HDC)3,0,0,13369376));assert(!clocks&&!creates&&!output_used&&last_error==77);
 reset();enabled=1;assert(BitBlt((HDC)1,0,0,960,720,(HDC)3,0,0,13369376));assert(creates==1&&clocks==4&&last_error==77);used=cyder_gdi_profile_used;
 assert(BitBlt((HDC)3,0,0,960,720,(HDC)3,0,0,13369376));assert(used==cyder_gdi_profile_used&&last_error==77);before=clocks;
 assert(BitBlt((HDC)1,0,0,10,10,(HDC)3,0,0,13369376));assert(clocks==before&&used==cyder_gdi_profile_used);
 assert(StretchBlt((HDC)1,0,0,1440,790,(HDC)3,0,0,960,720,13369376));assert(last_error==77);
 call_success=FALSE;assert(!BitBlt((HDC)1,0,0,960,720,(HDC)3,0,0,13369376));assert(last_error==901);before=clocks;
 assert(BitBlt((HDC)9,0,0,960,720,(HDC)3,0,0,13369376));assert(clocks==before);assert(!BitBlt(NULL,0,0,960,720,(HDC)3,0,0,13369376));assert(clocks==before);
 cyder_gdi_profile_close();assert(strstr(output,"# CYDER_GDI_PROFILE frequency=10000000"));assert(strstr(output,",0,0,960,720,961,721,0,1,960,720,3,13369376\n"));assert(strstr(output,",0,0,1440,790,961,721,0,2,960,720,3,13369376\n"));assert(strstr(output,",0,0,960,720,961,721,-1,1,"));
 reset();enabled=1;create_fail=1;assert(BitBlt((HDC)1,0,0,960,720,(HDC)3,0,0,13369376));assert(!clocks&&errors==1&&last_error==77);
 reset();enabled=1;short_write=1;assert(BitBlt((HDC)1,0,0,960,720,(HDC)3,0,0,13369376));assert(errors==1&&closes==1&&last_error==77);
 reset();enabled=1;for(i=0;i<1200;i++)assert(BitBlt((HDC)1,0,0,960,720,(HDC)3,0,0,13369376));assert(output_used>512);cyder_gdi_profile_close();assert(output[output_used-1]=='\n');assert(!errors);
 return 0;
}

C
"${CYDER_HOST_CLANG:-/usr/bin/clang}" -std=c11 -Wall -Wextra -Werror -I"$TMP" "$TMP/test.c" -o "$TMP/test"
"$TMP/test"
patch --reverse --forward --batch --fuzz=0 -s -d "$TMP" -p1 < "$ROOT/patches/cyder-gdi-window-blit-profile.patch"
cmp "$TMP/dlls/gdi32/dc.c" "$TMP/baseline/dc.c"
cmp "$TMP/dlls/gdi32/objects.c" "$TMP/baseline/objects.c"
echo 'PASS GDI window capture: actual BitBlt/StretchBlt wrappers, disabled no clock/file, HWND filtering, sizes/mode/ROP, failures/LastError, buffering/tail, patch round-trip'
