#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp -R "$ROOT/tests/fixtures/winemac-style-masks/." "$TMP/"
PATCH="$ROOT/patches/wine-winemac-initialize-style-masks.patch"
patch --forward --batch --fuzz=0 -s -d "$TMP" -p1 < "$PATCH"
patch --reverse --forward --batch --fuzz=0 --dry-run -s -d "$TMP" -p1 < "$PATCH"
if patch --forward --batch --fuzz=0 --dry-run -s -d "$TMP" -p1 < "$PATCH" >/dev/null 2>&1; then
  echo "already applied patch accepted forward" >&2; exit 1
fi
cat > "$TMP/probe.c" <<'C'
#include <assert.h>
typedef unsigned UINT;
typedef int BOOL;
typedef void *HWND;
#define FALSE 0
#define TRUE 1
#define WS_CAPTION 1u
#define WS_DLGFRAME 2u
#define WS_THICKFRAME 4u
#define WS_EX_TOOLWINDOW 8u
#define WS_EX_DLGMODALFRAME 16u
struct macdrv_window_features {int title_bar, shadow;};
static struct macdrv_window_features features;
static int quicken;
static int is_main_quicken_window(HWND h){return quicken;}
static struct macdrv_window_features get_window_features_for_style(UINT s,UINT e,int b){return features;}
C
cat "$TMP/dlls/winemac.drv/window.c" >> "$TMP/probe.c"
cat >> "$TMP/probe.c" <<'C'
int main(void){
  for(int title=0;title<2;title++)for(int shadow=0;shadow<2;shadow++){
    UINT s=~0u,e=~0u;
    features=(struct macdrv_window_features){title,shadow};
    assert(macdrv_GetWindowStyleMasks(0,123,456,&s,&e));
    assert(s==((title?WS_CAPTION:0)|(shadow?WS_DLGFRAME|WS_THICKFRAME:0)));
    assert(e==((title?WS_EX_TOOLWINDOW:0)|(shadow?WS_EX_DLGMODALFRAME:0)));
  }
  quicken=1;UINT s=123,e=456;
  assert(!macdrv_GetWindowStyleMasks(0,0,0,&s,&e));assert(s==123 && e==456);
  return 0;
}
C
/usr/bin/clang -std=c99 -Wall -Wextra -Wno-unused-parameter -Werror "$TMP/probe.c" -o "$TMP/probe"
"$TMP/probe"
patch --reverse --forward --batch --fuzz=0 -s -d "$TMP" -p1 < "$PATCH"
cmp "$TMP/dlls/winemac.drv/window.c" "$ROOT/tests/fixtures/winemac-style-masks/dlls/winemac.drv/window.c"
echo 'PASS test-winemac-style-masks'
