#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cyder-native-ddraw.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/dlls/ntdll"
cp "$ROOT/tests/fixtures/native-ddraw-path/loader.c" "$TMP/dlls/ntdll/loader.c"
cp "$TMP/dlls/ntdll/loader.c" "$TMP/pristine.c"
python3 - "$ROOT" "$TMP" <<'PY'
from pathlib import Path
import sys
root,tmp=map(Path,sys.argv[1:])
s=(root/'scripts/build-wine.sh').read_text()
a=s.index('apply_cyder_patch() {');b=s.index('\nremove_obsolete_cyder_patch()',a)
(tmp/'apply.sh').write_text(s[a:b])
PY
export WINE_SRC="$TMP" OGOM="$ROOT" DRY_RUN=0
source "$TMP/apply.sh"
PATCH="$ROOT/patches/cyder-ntdll-native-ddraw-path.patch"
apply_cyder_patch "$PATCH"
cp "$TMP/dlls/ntdll/loader.c" "$TMP/once.c"
apply_cyder_patch "$PATCH"
cmp "$TMP/once.c" "$TMP/dlls/ntdll/loader.c"
python3 - "$TMP" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]);s=(p/'once.c').read_text()
a=s.index('/* CYDER_NATIVE_DDRAW_PATH_V1:');b=s.index('/***********************************************************************',a)
(p/'snapshot.c').write_text(s[a:b])
assert s.count('        init_cyder_ddraw_path();')==1
assert s.count('return find_dll_file( load_path, cyder_ddraw_path.Buffer')==1
PY
cat > "$TMP/test.c" <<'C'
#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include <stdio.h>
#define TRUE 1
#define FALSE 0
#define STATUS_VARIABLE_NOT_FOUND 1
#define STATUS_OBJECT_PATH_SYNTAX_BAD 2
typedef int NTSTATUS;
typedef int BOOL;
typedef wchar_t WCHAR;
typedef struct { unsigned short Length,MaximumLength; WCHAR *Buffer; } UNICODE_STRING;
typedef enum { RtlPathTypeRelative, RtlPathTypeDriveAbsolute, RtlPathTypeUncAbsolute } RTL_PATH_TYPE;
static const WCHAR *environment;
static unsigned queries;
#define wcsicmp wcscasecmp
static NTSTATUS get_env_var(const WCHAR *name,size_t extra,UNICODE_STRING *out) {
 (void)extra;assert(!wcscmp(name,L"CYDER_DDRAW_PATH"));++queries;
 if(!environment)return STATUS_VARIABLE_NOT_FOUND;
 out->Length=wcslen(environment)*sizeof(WCHAR);
 out->Buffer=malloc(out->Length+sizeof(WCHAR));wcscpy(out->Buffer,environment);return 0;
}
static void RtlFreeUnicodeString(UNICODE_STRING *s){free(s->Buffer);memset(s,0,sizeof(*s));}
static RTL_PATH_TYPE RtlDetermineDosPathNameType_U(const WCHAR *s) {
 if(wcslen(s)>2 && s[1]==':' && (s[2]=='\\'||s[2]=='/'))return RtlPathTypeDriveAbsolute;
 if(s[0]=='\\' && s[1]=='\\')return RtlPathTypeUncAbsolute;
 return RtlPathTypeRelative;
}
#include "snapshot.c"
static void reset(const WCHAR *value){RtlFreeUnicodeString(&cyder_ddraw_path);cyder_ddraw_path_status=0;cyder_ddraw_path_enabled=0;queries=0;environment=value;}
int main(void) {
 reset(L"Z:\\payload-A\\ddraw.dll");init_cyder_ddraw_path();environment=L"Z:\\payload-B\\ddraw.dll";
 assert(cyder_ddraw_path_enabled && !cyder_ddraw_path_status && queries==1);
 assert(!wcscmp(cyder_ddraw_path.Buffer,L"Z:\\payload-A\\ddraw.dll"));
 reset(NULL);init_cyder_ddraw_path();assert(!cyder_ddraw_path_enabled);
 reset(L"");init_cyder_ddraw_path();assert(!cyder_ddraw_path_enabled && !cyder_ddraw_path.Buffer);
 reset(L"relative\\ddraw.dll");init_cyder_ddraw_path();assert(cyder_ddraw_path_enabled && cyder_ddraw_path_status==STATUS_OBJECT_PATH_SYNTAX_BAD);
 reset(L"Z:\\payload\\renamed.dll");init_cyder_ddraw_path();assert(cyder_ddraw_path_enabled && cyder_ddraw_path_status==STATUS_OBJECT_PATH_SYNTAX_BAD);
 reset(L"\\\\server\\share\\ddraw.dll");init_cyder_ddraw_path();assert(cyder_ddraw_path_enabled && !cyder_ddraw_path_status);
 reset(NULL);puts("PASS actual startup snapshot helper: fixed selection, disabled and invalid paths");return 0;
}
C
"${CYDER_HOST_CLANG:-/usr/bin/clang}" -arch x86_64 -mmacosx-version-min=10.15 \
  -Wall -Wextra -Werror -I"$TMP" "$TMP/test.c" -o "$TMP/test"
arch -x86_64 "$TMP/test"
patch --reverse --forward --batch --fuzz=0 -s -d "$TMP" -p1 < "$PATCH"
cmp "$TMP/dlls/ntdll/loader.c" "$TMP/pristine.c"
python3 - "$ROOT" "$TMP" <<'PY'
from pathlib import Path
import json,struct,subprocess,sys
root,tmp=map(Path,sys.argv[1:]);stage=tmp/'stage';config=tmp/'config.json'
config.write_text(json.dumps({'capabilities':['unknown-future-feature','native-ddraw-path-v1']}))
script=root/'scripts/verify-native-ddraw-capability.py'
for directory,machine in [('i386-windows',0x14c),('x86_64-windows',0x8664)]:
 p=stage/'lib/wine'/directory/'ntdll.dll';p.parent.mkdir(parents=True)
 data=bytearray(512);data[:2]=b'MZ';struct.pack_into('<I',data,60,128)
 data[128:132]=b'PE\0\0';struct.pack_into('<H',data,132,machine)
 data[256:280]=b'CYDER_NATIVE_DDRAW_PATH_V1';p.write_bytes(data)
args=[sys.executable,str(script),'--root',str(stage),'--config',str(config)]
subprocess.run(args,check=True)
p=stage/'lib/wine/i386-windows/ntdll.dll';data=p.read_bytes();p.write_bytes(data.replace(b'CYDER_NATIVE_DDRAW_PATH_V1',b'OLD_____________________'))
assert subprocess.run(args,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==1
config.write_text(json.dumps({'capabilities':['unknown-future-feature']}));subprocess.run(args,check=True)
release=json.loads((root/'config/engine-release.json').read_text())
assert 'cyder-ntdll-native-ddraw-path.patch' in release['patches'] and 'native-ddraw-path-v1' in release['capabilities']
print('PASS capability gate: correct PE machines, old PE rejection, unknown feature compatibility')
PY
echo 'PASS native ddraw production apply-repeat and reverse round-trip'
