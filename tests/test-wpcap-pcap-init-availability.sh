#!/usr/bin/env bash
# cyder-wpcap-pcap-init-availability.patch: wpcap must not call pcap_init()
# (macOS 12.1+) unguarded on the 10.15 floor.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/assert.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cyder-wpcap-pcap-init.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
PATCH="$ROOT/patches/cyder-wpcap-pcap-init-availability.patch"
SRC="$ROOT/build/cx26/sources/wine"
FLAGS=(-arch x86_64 -mmacosx-version-min=10.15
  -Werror=unguarded-availability -Werror=unguarded-availability-new)

cp -R "$ROOT/tests/fixtures/wpcap-pcap-init/." "$TMP/"
if clang "${FLAGS[@]}" -c "$TMP/dlls/wpcap/unixlib.c" -o "$TMP/before.o" 2>"$TMP/before.err"; then
  echo "fixture must reproduce the unguarded pcap_init call at the 10.15 floor" >&2; exit 1
fi
assert_contains "$(<"$TMP/before.err")" "pcap_init" "the floor error must name pcap_init"

patch --forward --batch --fuzz=0 -s -d "$TMP" -p1 <"$PATCH"
clang "${FLAGS[@]}" -c "$TMP/dlls/wpcap/unixlib.c" -o "$TMP/after.o"
assert_contains "$(nm -m "$TMP/after.o")" "weak external _pcap_init" \
  "the guarded call must stay a weak import that is skipped below 12.1"
assert_contains "$(<"$TMP/dlls/wpcap/unixlib.c")" "pcap_init() is macOS 12.1+" \
  "build-wine.sh detects the patch by this marker"

# The patch must still fit the CrossOver source when it is present.
if [[ -f "$SRC/dlls/wpcap/unixlib.c" ]] && ! grep -Fq "pcap_init() is macOS 12.1+" "$SRC/dlls/wpcap/unixlib.c"; then
  patch --forward --batch --fuzz=0 --dry-run -s -d "$SRC" -p1 <"$PATCH"
fi

echo "PASS wpcap pcap_init availability guard"
