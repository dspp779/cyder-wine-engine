#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cyder-hidden-gl-view.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/dlls/winemac.drv"
# BSD patch requires a partial fixture to reach the original hunk coordinates.
python3 - "$ROOT" "$TMP" <<'PYCODE'
from pathlib import Path
import sys,re
root,tmp=map(Path,sys.argv[1:]);patch=(root/'patches/cyder-winemac-reattach-hidden-gl-client-view.patch').read_text();line=int(re.search(r'@@ -(\d+)',patch)[1]);text='\n'*line+(root/'tests/fixtures/winemac-hidden-view-context/cocoa_window.m').read_text();(tmp/'dlls/winemac.drv/cocoa_window.m').write_text(text);(tmp/'pristine.m').write_text(text)
PYCODE
patch --forward --batch --fuzz=0 -s -d "$TMP" -p1 < "$ROOT/patches/cyder-winemac-reattach-hidden-gl-client-view.patch"
cat > "$TMP/test.m" <<'M'
#import <Foundation/Foundation.h>
#include <assert.h>
@interface WineOpenGLContext : NSObject {BOOL _needsUpdate;}
@property(nonatomic) BOOL needsUpdate;
@end
@implementation WineOpenGLContext
@synthesize needsUpdate=_needsUpdate;
@end
@interface WineWindow : NSObject { @public NSInteger number; unsigned updates; }
-(NSInteger)windowNumber;
-(void)updateForGLSubviews;
@end
@implementation WineWindow
-(NSInteger)windowNumber{return number;}
-(void)updateForGLSubviews{++updates;}
@end
@interface TestView : NSObject {
@public BOOL _everHadGLContext,hidden;NSMutableArray *glContexts,*pendingGlContexts;
NSRect visible,geometry;WineWindow *owner;unsigned displays,invalidates;
}
-(WineWindow *)window;-(NSRect)visibleRect;-(NSRect)bounds;-(BOOL)isHidden;
-(void)setNeedsDisplay:(BOOL)yes;-(void)invalidateHasGLDescendant;
-(void)addGLContext:(WineOpenGLContext *)context;
@end
@implementation TestView
-(WineWindow *)window{return owner;}
-(NSRect)visibleRect{return visible;}
-(NSRect)bounds{return geometry;}
-(BOOL)isHidden{return hidden;}
-(void)setNeedsDisplay:(BOOL)yes{assert(yes);++displays;}
-(void)invalidateHasGLDescendant{++invalidates;}
#include "dlls/winemac.drv/cocoa_window.m"
@end
static void check(BOOL used,NSInteger number,BOOL hidden,BOOL visible,BOOL sized,BOOL immediate){
 TestView *v=[TestView new];WineWindow *w=[WineWindow new];WineOpenGLContext *c=[WineOpenGLContext new];
 v->_everHadGLContext=used;v->owner=w;w->number=number;v->hidden=hidden;
 v->visible=visible?NSMakeRect(0,0,100,100):NSZeroRect;
 v->geometry=sized?NSMakeRect(0,0,100,100):NSZeroRect;
 [v addGLContext:c];assert(c.needsUpdate==immediate);
 assert([v->glContexts count]==(immediate?1:0));assert([v->pendingGlContexts count]==(immediate?0:1));
 assert(v->displays==(immediate?0:1));assert(v->_everHadGLContext);assert(v->invalidates==!used);assert(w->updates==1);
 [c release];[v->glContexts release];[v->pendingGlContexts release];[w release];[v release];
}
int main(void){@autoreleasepool{
 check(YES,1,YES,NO,YES,YES); /* GDI-hidden established view: first new GL draw must have a drawable. */
 check(NO,1,YES,NO,YES,NO);  /* First-use hidden view still waits. */
 check(YES,0,YES,NO,YES,NO); /* No realized window: still waits. */
 check(YES,1,YES,NO,NO,NO);  /* Empty bounds: still waits. */
 check(YES,1,NO,NO,YES,NO);  /* Clipped/ancestor-hidden view is not the GDI-hide exception. */
 check(NO,1,NO,YES,YES,YES); /* Ordinary visible first use remains immediate. */
}return 0;}
M
if [[ "$(uname -s)" == Darwin ]]; then
"${CYDER_HOST_CLANG:-/usr/bin/clang}" -arch x86_64 -mmacosx-version-min=10.15 -Wall -Wextra -Werror -Wno-objc-root-class -I"$TMP" "$TMP/test.m" -framework Foundation -o "$TMP/test"
arch -x86_64 "$TMP/test"
echo "PASS actual Cocoa addGLContext: established hidden attaches; first-use/unrealized/empty/clipped views defer"
else
  echo "SKIP native Cocoa method execution (requires macOS Foundation); patch round-trip still checked"
fi
patch --reverse --forward --batch --fuzz=0 -s -d "$TMP" -p1 < "$ROOT/patches/cyder-winemac-reattach-hidden-gl-client-view.patch"
cmp "$TMP/dlls/winemac.drv/cocoa_window.m" "$TMP/pristine.m"
echo 'PASS hidden GL context patch round-trip'
