#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cyder-surface-profile.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/dlls/winemac.drv"
cp "$ROOT/tests/fixtures/winemac-surface-profile/surface.c" "$TMP/dlls/winemac.drv/"
patch --forward --batch --fuzz=0 -s -d "$TMP" -p1 < "$ROOT/patches/cyder-winemac-surface-profile.patch"
cat > "$TMP/test.c" <<'C'
#include <assert.h>
#include "dlls/winemac.drv/cyder_surface_profile.h"
int main(void)
{
    unsetenv("CYDER_SURFACE_PROFILE");assert(!cyder_surface_profile_create());assert(!cyder_surface_profile_now(NULL));
    setenv("CYDER_SURFACE_PROFILE","1",1);
    struct cyder_surface_profile *p=cyder_surface_profile_create();assert(p);
    cyder_surface_profile_record(p,100,200,960,720);
    cyder_surface_profile_record(p,33333433,33333533,960,720);
    assert(p->updates==2 && p->intervals==1 && p->bins[33]==1 && p->submit_ns==200);
    cyder_surface_profile_record(p,5500000000ULL,5500000100ULL,960,720);
    assert(!p->updates && !p->intervals && p->previous==5500000000ULL);
    cyder_surface_profile_record(p,5533333333ULL,5533333433ULL,960,720);
    assert(p->intervals==1 && p->bins[33]==1);
    cyder_surface_profile_report(p,5533333500ULL,960,720,1);
    free(p);
    return 0;
}
C
"${CYDER_HOST_CLANG:-/usr/bin/clang}" -std=c99 -Wall -Wextra -Werror -I"$TMP" "$TMP/test.c" -o "$TMP/test"
"$TMP/test" 2> "$TMP/result.log"
python3 - "$TMP/result.log" <<'PY'
from pathlib import Path
import re,sys
rows=Path(sys.argv[1]).read_text().splitlines();assert len(rows)==2
assert 'updates=3 intervals=2 submit_ns=300' in rows[0] and '33:1,2000:1,' in rows[0]
assert 'final=1' in rows[1] and 'updates=1 intervals=1' in rows[1] and 'bins=33:1,' in rows[1]
PY
patch --reverse --forward --batch --fuzz=0 -s -d "$TMP" -p1 < "$ROOT/patches/cyder-winemac-surface-profile.patch"
cmp "$TMP/dlls/winemac.drv/surface.c" "$ROOT/tests/fixtures/winemac-surface-profile/surface.c"
echo 'PASS GDI surface profiling: disabled no allocation/clock; interval bins, report/reset boundary, final tail and full patch round-trip'
