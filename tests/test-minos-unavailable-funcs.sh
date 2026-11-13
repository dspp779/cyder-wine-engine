#!/usr/bin/env bash
# scripts/minos-unavailable-funcs.py finds functions the SDK declares but the
# minOS floor lacks, and build-wine.sh turns them into configure overrides.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/assert.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cyder-minos-funcs.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
PROBE="$ROOT/scripts/minos-unavailable-funcs.py"

# Real clang: pthread_cpu_number_np is macOS 11.0+ in every supported SDK.
out="$(python3 "$PROBE" --floor 10.15 pthread_cpu_number_np read not_a_real_function)"
assert_eq "$out" "pthread_cpu_number_np	11.0" \
  "only the function newer than the floor is reported; undeclared names are left to configure"
out="$(python3 "$PROBE" --floor 11.0 pthread_cpu_number_np read)"
assert_eq "$out" "" "a function available at the floor is not reported"

# Extraction from the shapes Wine's configure.ac and GLib's meson.build use.
cat >"$TMP/configure.ac" <<'AC'
AC_CHECK_FUNCS(\
        dladdr1 \
	pipe2 \
	sched_yield
)
WINE_CHECK_LIB_FUNCS(\
        pthread_cpu_number_np,
        [$PTHREAD_LIBS])
AC_CHECK_LIB(pcap,pcap_init,[AC_SUBST(PCAP_LIBS,["-lpcap"])])
AC
cat >"$TMP/meson.build" <<'MESON'
functions = [
  'pipe2',
  'poll',
]
if host_system == 'darwin'
  functions += ['pthread_cpu_number_np']
endif
MESON
assert_eq "$(python3 "$PROBE" --floor 10.15 --configure-ac "$TMP/configure.ac")" \
  "pthread_cpu_number_np	11.0" "configure.ac checks are probed (AC_CHECK_LIB is not overridable here)"
assert_eq "$(python3 "$PROBE" --floor 10.15 --meson-build "$TMP/meson.build")" \
  "pthread_cpu_number_np	11.0" "meson functions and functions += lists are probed"

# A newer SDK (pipe2 in SDK 27) reports through the same clang message.
cat >"$TMP/fake-cc" <<'SH'
#!/bin/bash
echo "probe.c:9:12: error: 'pipe2' is only available on macOS 27.0 or newer [-Werror,-Wunguarded-availability-new]" >&2
echo "probe.c:10:12: error: use of undeclared identifier 'dladdr1'" >&2
exit 1
SH
chmod +x "$TMP/fake-cc"
assert_eq "$(python3 "$PROBE" --floor 10.15 --cc "$TMP/fake-cc" --configure-ac "$TMP/configure.ac")" \
  "pipe2	27.0" "an SDK-27 availability error marks pipe2 unavailable"

# A probe that cannot compile at all must fail closed.
printf '#!/bin/bash\necho "probe.c:1:10: fatal error: '"'"'stdio.h'"'"' file not found" >&2\nexit 1\n' >"$TMP/broken-cc"
chmod +x "$TMP/broken-cc"
if python3 "$PROBE" --floor 10.15 --cc "$TMP/broken-cc" pipe2 2>/dev/null; then
  echo "a broken probe compiler must fail the build" >&2; exit 1
fi

# build-wine.sh passes each finding to configure as ac_cv_func_<name>=no.
if [[ -f "$ROOT/build/cx26/sources/wine/configure.ac" ]]; then
  out="$(CC="$TMP/fake-cc" HOMEBREW_PREFIX="$TMP/brew" \
    bash "$ROOT/scripts/build-wine.sh" --cx 26 --dry-run --without-vulkan 2>&1)"
  assert_contains "$out" "host minOS: pipe2 needs macOS 27.0" "build-wine reports the override"
  assert_contains "$(grep '^+ .*\.\./configure ' <<<"$out")" "ac_cv_func_pipe2=no" \
    "the override reaches the configure command"
fi

# build-media-stack.sh drops the same functions from GLib's config.h.
media="$(<"$ROOT/scripts/build-media-stack.sh")"
assert_contains "$media" 'minos-unavailable-funcs.py" \' "media build probes GLib's checks"
assert_contains "$media" '--meson-build "$GLIB_SRC/meson.build"' "media build reads GLib's function list"
assert_contains "$media" 'sed -i '"''"' "/^#define $define 1\$/d" "$GLIB_CONFIG_H"' \
  "media build removes HAVE_<FUNC> before compiling GLib"

echo "PASS minos-unavailable-funcs"
