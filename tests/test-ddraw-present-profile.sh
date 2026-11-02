#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cyder-ddraw-profile.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/dlls/ddraw"
python3 "$ROOT/tests/materialize-present-fixture.py" "$ROOT/tests/fixtures/ddraw-present-profile/baseline.json" "$TMP/dlls/ddraw"
cp -R "$TMP/dlls/ddraw" "$TMP/baseline"
patch --forward --batch --fuzz=0 -s -d "$TMP" -p1 < "$ROOT/patches/cyder-ddraw-present-profile.patch"
python3 - "$TMP" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]);s=(p/'dlls/ddraw/surface.c').read_text();start=s.index('HRESULT ddraw_surface_update_frontbuffer(');end=s.index('\nstatic HRESULT cyder_ddraw_update_frontbuffer_impl(',start)
(p/'wrapper.inc').write_text(s[start:end])
PY
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
static DWORD GetEnvironmentVariableA(const char *name,char *dst,DWORD cap) { assert(!strcmp(name,"CYDER_DDRAW_PROFILE_DIR")); if(!enabled){last_error=203;return 0;} assert(cap>5);strcpy(dst,"Z:\\x");return 4; }
static DWORD GetCurrentProcessId(void) { return 123; }
static DWORD GetCurrentThreadId(void) { return 7; }
static HANDLE CreateFileA(const char *path,DWORD access,DWORD sharing,void *security,DWORD creation,DWORD attr,void *template) { (void)security;(void)template;assert(strstr(path,"ddraw-present-0000007b.csv"));assert(access==GENERIC_WRITE&&sharing==FILE_SHARE_READ&&creation==CREATE_NEW&&attr==FILE_ATTRIBUTE_NORMAL);creates++;return create_fail?INVALID_HANDLE_VALUE:1; }
static BOOL WriteFile(HANDLE file,const char *data,DWORD size,DWORD *done,void *async) { (void)async;assert(file==1);assert(output_used+size<sizeof(output));memcpy(output+output_used,data,size);output_used+=size;output[output_used]=0;*done=short_write?size-1:size;return TRUE; }
static BOOL CloseHandle(HANDLE file) { assert(file==1);closes++;return TRUE; }
static BOOL QueryPerformanceCounter(LARGE_INTEGER *v) { clocks++;v->QuadPart=now_qpc;now_qpc+=100;return TRUE; }
static BOOL QueryPerformanceFrequency(LARGE_INTEGER *v) { v->QuadPart=10000000;return TRUE; }
static void GetSystemTimePreciseAsFileTime(FILETIME *ft) { uint64_t v=116444736000000000ULL+10000000;ft->dwLowDateTime=v;ft->dwHighDateTime=v>>32; }
static BOOL InitOnceExecuteOnce(INIT_ONCE *once,BOOL (*cb)(INIT_ONCE*,void*,void**),void *arg,void **ctx) { if(!*once){assert(cb(once,arg,ctx));*once=1;}return TRUE; }
static void AcquireSRWLockExclusive(SRWLOCK *l) { assert(!*l);*l=1; }
static void ReleaseSRWLockExclusive(SRWLOCK *l) { assert(*l);*l=0; }
static void SetRect(RECT *r,int l,int t,int x,int y) { r->left=l;r->top=t;r->right=x;r->bottom=y; }
static BOOL IsRectEmpty(const RECT *r) { return r->right<=r->left||r->bottom<=r->top; }
struct ddraw { unsigned flags; };
struct ddraw_surface { struct { DWORD dwWidth,dwHeight; struct {DWORD dwCaps;} ddsCaps; } surface_desc; struct ddraw *ddraw; };
#include "dlls/ddraw/cyder_ddraw_profile.h"
static HRESULT result;
static HRESULT cyder_ddraw_update_frontbuffer_impl(struct ddraw_surface *surface,const RECT *rect,BOOL read,unsigned interval) { (void)rect;(void)interval;if(!read)surface->ddraw->flags&=~DDRAW_SWAPPED;return result; }
#include "wrapper.inc"
static void reset(void) { cyder_ddraw_profile_close();cyder_ddraw_profile_once=0;cyder_ddraw_profile_used=0;output_used=0;output[0]=0;clocks=creates=closes=errors=short_write=create_fail=0; }
int main(void) {
 struct ddraw d={0};struct ddraw_surface s={{1680,945,{DDSCAPS_PRIMARYSURFACE}},&d};RECT r={32,64,992,784},empty={0,0,0,0};int before,i;
 last_error=77;enabled=0;assert(!ddraw_surface_update_frontbuffer(&s,&r,FALSE,0));assert(!clocks&&!creates&&!output_used&&last_error==77);
 reset();enabled=1;assert(!ddraw_surface_update_frontbuffer(&s,&r,FALSE,0));assert(creates==1&&clocks==4);before=clocks;
 assert(!ddraw_surface_update_frontbuffer(&s,&r,TRUE,0));s.surface_desc.ddsCaps.dwCaps=0;assert(!ddraw_surface_update_frontbuffer(&s,&r,FALSE,0));assert(clocks==before);s.surface_desc.ddsCaps.dwCaps=DDSCAPS_PRIMARYSURFACE;
 assert(!ddraw_surface_update_frontbuffer(&s,&empty,FALSE,0));
 result=(HRESULT)0x80004005;assert(ddraw_surface_update_frontbuffer(&s,&r,FALSE,0)==result);result=0;
 d.flags=DDRAW_SWAPPED;assert(!ddraw_surface_update_frontbuffer(&s,&r,FALSE,0));
 cyder_ddraw_profile_close();assert(strstr(output,"frequency=10000000"));assert(strstr(output,"anchor_epoch_ns=1000000000"));assert(strstr(output,",32,64,960,720,1680,945,0\n"));assert(strstr(output,",1680,945,-2147467259\n"));assert(strstr(output,",0,0,1680,945,1680,945,0\n"));assert(closes==1);
 reset();enabled=1;create_fail=1;assert(!cyder_ddraw_profile_begin());assert(!clocks&&errors==1);
 reset();enabled=1;short_write=1;assert(!cyder_ddraw_profile_begin());assert(errors==1&&closes==1&&cyder_ddraw_profile_file==INVALID_HANDLE_VALUE);
 reset();enabled=1;for(i=0;i<1200;i++)assert(!ddraw_surface_update_frontbuffer(&s,&r,FALSE,0));assert(output_used>512);cyder_ddraw_profile_close();assert(output[output_used-1]=='\n');assert(!errors);
 return 0;
}
C
"${CYDER_HOST_CLANG:-/usr/bin/clang}" -std=c11 -Wall -Wextra -Werror -I"$TMP" "$TMP/test.c" -o "$TMP/test"
"$TMP/test"
patch --reverse --forward --batch --fuzz=0 -s -d "$TMP" -p1 < "$ROOT/patches/cyder-ddraw-present-profile.patch"
cmp "$TMP/dlls/ddraw/surface.c" "$TMP/baseline/surface.c"
cmp "$TMP/dlls/ddraw/main.c" "$TMP/baseline/main.c"
echo 'PASS DirectDraw timestamps: disabled no clock/file, primary-only writes, reads/empty skips, failed status, clock anchor, exclusive output, buffering/tail, error invalidation, patch round-trip'
