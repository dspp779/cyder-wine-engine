#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cyder-order-anchor.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/dlls/winemac.drv"
PATCH="$ROOT/patches/cyder-winemac-missing-order-anchor.patch"
python3 - "$ROOT" "$TMP" <<'PY'
import re,sys
from pathlib import Path
root,tmp=map(Path,sys.argv[1:]);p=(root/'patches/cyder-winemac-missing-order-anchor.patch').read_text();fixture=(root/'tests/fixtures/winemac-missing-order-anchor/cocoa_window.m').read_text();m=re.search(r'@@ -(\d+),\d+ \+\d+,\d+ @@\n',p);first=p[m.end():].splitlines()[0][1:];i=fixture.splitlines().index(first);text='\n'*(int(m[1])-1-i)+fixture;(tmp/'dlls/winemac.drv/cocoa_window.m').write_text(text);(tmp/'pristine.m').write_text(text)
PY
cat > "$TMP/test.m" <<'M'
#import <AppKit/AppKit.h>
#include <assert.h>
static NSArray *snapshot;
@interface WineWindow : NSObject { @public NSInteger number; NSArray *kids; }
+(NSArray *)windowNumbersWithOptions:(NSWindowNumberListOptions)options;
-(NSInteger)windowNumber;
-(NSArray *)childWineWindows;
-(void)setChildWineWindows:(NSArray *)children;
-(void)order:(NSWindowOrderingMode)mode childWindow:(WineWindow *)child relativeTo:(WineWindow *)other;
@end
@implementation WineWindow
+(NSArray *)windowNumbersWithOptions:(NSWindowNumberListOptions)options{(void)options;return snapshot;}
-(NSInteger)windowNumber{return number;}
-(NSArray *)childWineWindows{return kids;}
-(void)setChildWineWindows:(NSArray *)children{[kids autorelease];kids=[children copy];}
#include "dlls/winemac.drv/cocoa_window.m"
@end
static void check(WineWindow *parent,NSArray *before,NSArray *numbers,WineWindow *child,WineWindow *other,NSWindowOrderingMode mode,NSArray *expected){
 [parent setChildWineWindows:before];snapshot=numbers;[parent order:mode childWindow:child relativeTo:other];assert([parent->kids isEqual:expected]);
}
int main(int argc,char **argv){(void)argv;@autoreleasepool{
 WineWindow *p=[WineWindow new],*a=[WineWindow new],*b=[WineWindow new],*c=[WineWindow new],*unknown=[WineWindow new];
 p->number=10;a->number=1;b->number=2;c->number=3;unknown->number=9;
 NSArray *abc=@[a,b,c],*numbers=@[@3,@2,@1,@10];
 /* Ordinary window-server path, including nil reference, remains unchanged. */
 check(p,abc,numbers,a,b,NSWindowAbove,@[b,a,c]);
 check(p,abc,numbers,c,b,NSWindowBelow,@[a,c,b]);
 check(p,abc,numbers,a,nil,NSWindowAbove,@[b,c,a]);
 check(p,abc,numbers,c,nil,NSWindowBelow,@[c,a,b]);
 @try {
  /* b is a real sibling but absent from a transient server snapshot. */
  check(p,abc,@[@3,@1],a,b,NSWindowAbove,@[b,a,c]);
  check(p,abc,@[@3,@1],c,b,NSWindowBelow,@[a,c,b]);
  check(p,abc,@[],a,b,NSWindowAbove,@[b,a,c]);
  check(p,abc,@[],c,b,NSWindowBelow,@[a,c,b]);
  /* Self/unknown anchors and unknown children do not attach or reorder. */
  check(p,abc,@[],a,a,NSWindowAbove,abc);
  check(p,abc,@[],a,unknown,NSWindowBelow,abc);
  check(p,abc,@[],unknown,b,NSWindowAbove,abc);
 } @catch(NSException *e) {
  if(argc>1 && [e.name isEqual:NSRangeException]){puts("PASS original actual method reproduces NSRangeException for missing anchor");return 0;}
  fprintf(stderr,"Unexpected exception: %s\n",e.name.UTF8String);return 2;
 }
 assert(argc==1);[p->kids release];[p release];[a release];[b release];[c release];[unknown release];
 puts("PASS actual Cocoa ordering: normal, missing, empty, self and unknown anchor cases");
 }return 0;
}
M
build_run(){
 "${CYDER_HOST_CLANG:-/usr/bin/clang}" -arch x86_64 -mmacosx-version-min=10.15 -Wall -Wextra -Werror -I"$TMP" "$TMP/test.m" -framework AppKit -o "$TMP/test"
 arch -x86_64 "$TMP/test" "$@"
}
if [[ "$(uname -s)" == Darwin ]]; then build_run baseline; fi
patch --forward --batch --fuzz=0 -s -d "$TMP" -p1 < "$PATCH"
if [[ "$(uname -s)" == Darwin ]]; then build_run; else echo 'SKIP native Cocoa execution (requires macOS)'; fi
patch --reverse --forward --batch --fuzz=0 --dry-run -s -d "$TMP" -p1 < "$PATCH"
if patch --forward --batch --fuzz=0 --dry-run -s -d "$TMP" -p1 < "$PATCH" >/dev/null 2>&1; then echo 'Duplicate forward application accepted' >&2;exit 1;fi
patch --reverse --forward --batch --fuzz=0 -s -d "$TMP" -p1 < "$PATCH"
cmp "$TMP/dlls/winemac.drv/cocoa_window.m" "$TMP/pristine.m"
echo 'PASS missing ordering anchor patch round-trip'
