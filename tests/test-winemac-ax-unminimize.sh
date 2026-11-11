#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cyder-ax-unminimize.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
PATCH="$ROOT/patches/cyder-winemac-ax-unminimize.patch"
mkdir -p "$TMP/dlls/winemac.drv"
python3 - "$ROOT" "$TMP" <<'PY'
from pathlib import Path
import re,sys
root,tmp=map(Path,sys.argv[1:])
patch=(root/'patches/cyder-winemac-ax-unminimize.patch').read_text()
fixture=(root/'tests/fixtures/winemac-ax-unminimize/cocoa_window.m').read_text()
hunk=re.search(r'@@ -(\d+),\d+ \+\d+,\d+ @@\n',patch)
first=patch[hunk.end():].splitlines()[0][1:]
offset=fixture.splitlines().index(first)
source='\n'*(int(hunk[1])-1-offset)+fixture
(tmp/'dlls/winemac.drv/cocoa_window.m').write_text(source)
(tmp/'pristine.m').write_text(source)
script=(root/'scripts/build-wine.sh').read_text()
a=script.index('apply_cyder_patch() {')
b=script.index('\nremove_obsolete_cyder_patch()',a)
(tmp/'apply.sh').write_text(script[a:b])
PY
# Use the production apply helper: this insertion patch needs its marker guard
# before a second forward application can duplicate the new method.
export WINE_SRC="$TMP" OGOM="$ROOT" DRY_RUN=0
source "$TMP/apply.sh"
apply_cyder_patch "$PATCH"
cp "$TMP/dlls/winemac.drv/cocoa_window.m" "$TMP/once.m"
apply_cyder_patch "$PATCH"
cmp "$TMP/once.m" "$TMP/dlls/winemac.drv/cocoa_window.m"
python3 - "$TMP" <<'PY'
from pathlib import Path
import sys
tmp=Path(sys.argv[1]);text=(tmp/'once.m').read_text()
a=text.index('    - (void) setAccessibilityMinimized:')
b=text.index('    - (void) miniaturize:',a)
assert text.count('setAccessibilityMinimized:(BOOL)')==1
(tmp/'method.m').write_text(text[a:b])
PY
cat > "$TMP/test.m" <<'M'
#import <Foundation/Foundation.h>
#include <assert.h>
@interface ParentWindow : NSObject {
@public BOOL iconic, allowMinimize, hidden;
unsigned superCalls, nativeRestores;
}
-(BOOL)isMiniaturized;
-(void)deminiaturize:(id)sender;
-(void)setAccessibilityMinimized:(BOOL)value;
@end
@implementation ParentWindow
-(BOOL)isMiniaturized {return iconic;}
-(void)deminiaturize:(id)sender {(void)sender;++nativeRestores;iconic=NO;}
-(void)setAccessibilityMinimized:(BOOL)value {
 ++superCalls;
 if(value && allowMinimize) iconic=YES;
 /* The inherited false path can be a no-op after iconic styles are removed. */
}
@end
@interface WineWindow : ParentWindow
@end
@implementation WineWindow
#include "method.m"
@end
int main(void) {@autoreleasepool {
 WineWindow *w=[WineWindow new];
 w->iconic=YES;
 [w setAccessibilityMinimized:NO];
 assert(!w->iconic && w->nativeRestores==1 && w->superCalls==0);
 [w setAccessibilityMinimized:NO];
 assert(w->nativeRestores==1 && w->superCalls==1);
 /* Preserve AppKit policy for allowed and denied minimize requests. */
 w->allowMinimize=YES;[w setAccessibilityMinimized:YES];
 assert(w->iconic && w->superCalls==2 && w->nativeRestores==1);
 [w setAccessibilityMinimized:NO];
 w->allowMinimize=NO;[w setAccessibilityMinimized:YES];
 assert(!w->iconic && w->superCalls==3 && w->nativeRestores==2);
 /* AX false on a hidden but non-miniaturized window must not reveal it. */
 w->hidden=YES;[w setAccessibilityMinimized:NO];
 assert(w->hidden && w->nativeRestores==2 && w->superCalls==4);
 [w release];
 } puts("PASS actual AX method: restore, idempotence, AppKit minimize policy and hidden-window delegation");return 0;}
M
if [[ "$(uname -s)" == Darwin ]]; then
  "${CYDER_HOST_CLANG:-/usr/bin/clang}" -arch x86_64 -mmacosx-version-min=10.15 \
    -Wall -Wextra -Werror -I"$TMP" "$TMP/test.m" -framework Foundation -o "$TMP/test"
  arch -x86_64 "$TMP/test"
else
  echo 'SKIP native Objective-C execution (requires macOS Foundation)'
fi
patch --reverse --forward --batch --fuzz=0 -s -d "$TMP" -p1 < "$PATCH"
cmp "$TMP/dlls/winemac.drv/cocoa_window.m" "$TMP/pristine.m"
echo 'PASS AX unminimize production apply idempotence and patch round-trip'
