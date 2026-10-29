#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/assert.sh"
source "$ROOT/scripts/media-toolchain.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/cyder-media-toolchain.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
export MEDIA_BUILD="$tmp/media"
export MIN_FLAG=-mmacosx-version-min=10.15
unset CC CXX OBJC OBJCXX
media_prepare_native_file
native="$(cat "$MEDIA_BUILD/cyder-native.ini")"
assert_contains "$native" "c = ['/usr/bin/clang', '-arch', 'x86_64']" 'C defaults must pin Apple x86_64'
assert_contains "$native" "cpp = ['/usr/bin/clang++', '-arch', 'x86_64']" 'C++ defaults must pin Apple x86_64'
assert_contains "$native" "objc = ['/usr/bin/clang', '-arch', 'x86_64']" 'Objective-C defaults must pin Apple x86_64'
assert_contains "$native" "objcpp = ['/usr/bin/clang++', '-arch', 'x86_64']" 'Objective-C++ defaults must pin Apple x86_64'

# Meson cannot change compilers through --reconfigure. Fail before touching an
# existing unverified build; preserve it and tell the caller to use a new tree.
mkdir -p "$MEDIA_BUILD/glib-build"
printf 'keep\n' > "$MEDIA_BUILD/glib-build/build.ninja"
media_prepare_native_file
saved="$(cat "$MEDIA_BUILD/cyder-native.ini")"
if out="$(CC='/custom/compiler -arch x86_64' media_prepare_native_file 2>&1)"; then
  echo 'expected a changed cached compiler to fail' >&2; exit 1
fi
assert_contains "$out" 'fresh OGOM_BUILD_DIR' 'cache failure should explain how to recover'
assert_eq "$(cat "$MEDIA_BUILD/cyder-native.ini")" "$saved" 'cached native file must be preserved'
assert_eq "$(cat "$MEDIA_BUILD/glib-build/build.ninja")" keep 'existing build must be preserved'
if MIN_FLAG=-mmacosx-version-min=11.0 media_prepare_native_file 2>/dev/null; then
  echo 'expected a changed cached deployment target to fail' >&2; exit 1
fi
mv "$MEDIA_BUILD/cyder-native.ini" "$tmp/native.saved"
if media_prepare_native_file 2>/dev/null; then
  echo 'expected an unverified legacy Meson cache to fail' >&2; exit 1
fi

MEDIA_BUILD="$tmp/custom"
CC='/custom/clang -arch x86_64' CXX='/custom/clang++ -arch x86_64' \
OBJC='/custom/objc -arch x86_64' OBJCXX='/custom/objcpp -arch x86_64' media_prepare_native_file
assert_contains "$(cat "$MEDIA_BUILD/cyder-native.ini")" "c = ['/custom/clang', '-arch', 'x86_64']" 'preserve caller compilers'

# Build real Mach-O outputs through the production MESON_CMD and native file,
# not a mock compiler: this catches Rosetta's arm64 default on macOS 27.
export OGOM="$ROOT"
source "$ROOT/scripts/env-x86_64.sh"
MESON="$HOMEBREW_PREFIX/bin/meson"
if [[ ! -x "$MESON" ]]; then
  echo 'SKIP media Meson integration: install project meson first'
  exit 0
fi
MESON_PACKAGE="$(find "$HOMEBREW_PREFIX/lib" -type d -path '*/site-packages/mesonbuild' -print -quit)"
export PYTHON_SITE="${MESON_PACKAGE%/mesonbuild}"
export MEDIA_BUILD="$tmp/real"
export MEDIA_INSTALL="$tmp/install"
export SYSTEM_PYTHON="${CYDER_HOST_PYTHON:-/usr/bin/python3}"
if [[ -n "${CYDER_HOST_CLANG:-}" ]]; then
  export CC="$CYDER_HOST_CLANG -arch x86_64" OBJC="$CYDER_HOST_CLANG -arch x86_64"
  export CXX="${CYDER_HOST_CLANGXX:-${CYDER_HOST_CLANG}++} -arch x86_64"
  export OBJCXX="$CXX"
fi
export MESON
export MIN_FLAG=-mmacosx-version-min=10.15
export MACOSX_DEPLOYMENT_TARGET=10.15
media_prepare_native_file
mkdir -p "$tmp/source" "$MEDIA_INSTALL/include" "$MEDIA_INSTALL/lib"
# A non-pkg-config dependency in the media prefix must be discoverable too.
printf '#ifdef __cplusplus\nextern "C" {\n#endif\nint media_dependency(void);\n#ifdef __cplusplus\n}\n#endif\n' > "$MEDIA_INSTALL/include/media_dependency.h"
printf 'int media_dependency(void) { return 0; }\n' > "$tmp/dependency.c"
"${CYDER_HOST_CLANG:-/usr/bin/clang}" -arch x86_64 -dynamiclib "$MIN_FLAG" \
  "$tmp/dependency.c" -o "$MEDIA_INSTALL/lib/libmedia_dependency.dylib"
cat > "$tmp/source/meson.build" <<'MESON'
project('media-compiler-contract', 'c', 'cpp', 'objc', 'objcpp')
dependency = meson.get_compiler('c').find_library('media_dependency', required: true)
foreach item : [['c', 'c'], ['cpp', 'cpp'], ['objc', 'm'], ['objcpp', 'mm']]
  executable('probe-' + item[0], 'probe.' + item[1], dependencies: dependency)
endforeach
MESON
for ext in c cpp m mm; do
  printf '#include <media_dependency.h>\nint main(void) { return media_dependency(); }\n' > "$tmp/source/probe.$ext"
done
# Extract the production command array without running the media build itself.
python3 - "$ROOT/scripts/build-media-stack.sh" "$tmp/meson-env.sh" <<'PY'
import pathlib, sys
s = pathlib.Path(sys.argv[1]).read_text()
a = s.index('HOST_TOOLS=')
b = s.index('\nmedia_prepare_native_file', a)
pathlib.Path(sys.argv[2]).write_text(s[a:b])
PY
source "$tmp/meson-env.sh"
"${MESON_CMD[@]}" setup "$tmp/real-build" "$tmp/source" --native-file "$MEDIA_BUILD/cyder-native.ini" >"$tmp/setup.log" 2>&1 || { cat "$tmp/setup.log"; exit 1; }
"${MESON_CMD[@]}" compile -C "$tmp/real-build" >/dev/null
media_verify_x86_64 "$tmp/real-build"
python3 "$ROOT/scripts/pack-minos-scan.py" "$tmp/real-build" 10.15 >/dev/null
# Reject wrong architecture even when compile succeeds.
mkdir -p "$tmp/arm-only"
printf 'int p = 1;\n' > "$tmp/arm.c"
/usr/bin/clang -arch arm64 -mmacosx-version-min=11.0 -dynamiclib "$tmp/arm.c" -o "$tmp/arm-only/libbad.dylib"
if out="$(media_verify_x86_64 "$tmp/arm-only" 2>&1)"; then
  echo 'expected arm64 output validation to fail' >&2; exit 1
fi
assert_contains "$out" 'expected thin x86_64' 'wrong-architecture output should be diagnosed'
echo 'PASS media toolchain (cache safety, overrides and real four-language x86_64/minOS probes)'
