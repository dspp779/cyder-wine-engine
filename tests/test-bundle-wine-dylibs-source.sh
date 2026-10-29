#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/assert.sh"

script="$(<"$ROOT/scripts/bundle-wine-dylibs.sh")"

assert_contains "$script" 'VULKAN_SOURCE="${VULKAN_SOURCE:-existing}"' \
  "repacking should preserve an engine's existing MoltenVK by default"
assert_contains "$script" '"crossover": (' \
  "bundler should have an explicit CrossOver MoltenVK selection path"
assert_contains "$script" '"homebrew": (' \
  "bundler should keep Homebrew as an explicit alternative"
assert_contains "$script" "macho_minos" \
  "bundler must gate Mach-O minos after copy"
assert_contains "$script" 'MACOSX_DEPLOYMENT_TARGET' \
  "minos gate must honour the product-floor deployment target"
assert_contains "$script" "remove orphan" \
  "bundler should drop leftover dylibs no longer in the seed graph"
assert_contains "$script" 'media_plugin_dir' \
  "bundler should discover GStreamer plugins from the media install"
assert_contains "$script" 'gst-plugin-scanner' \
  "bundler should include the GStreamer plugin scanner"
assert_contains "$script" 'lib/wine/gstreamer-1.0' \
  "bundler should keep plugins in the engine's internal GStreamer subtree"
assert_contains "$script" '"libexec" / "gstreamer-1.0"' \
  "bundler should keep the scanner in the engine's internal libexec subtree"

crossover_block="$(sed -n '/"crossover": (/,/),/p' "$ROOT/scripts/bundle-wine-dylibs.sh")"
first_candidate="$(printf '%s\n' "$crossover_block" | rg 'libMoltenVK\.dylib' | head -1)"
assert_contains "$first_candidate" 'graphics_lib' \
  "CrossOver mode must prefer the CrossOver graphics artifact over Homebrew"

existing_block="$(sed -n '/"existing": (/,/),/p' "$ROOT/scripts/bundle-wine-dylibs.sh")"
first_existing="$(printf '%s\n' "$existing_block" | rg 'libMoltenVK\.dylib' | head -1)"
assert_contains "$first_existing" 'unix_lib' \
  "artifact repacking must preserve the already-tested engine renderer"

# Functional gate: a synthetic high-minos dylib must fail the bundler.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-bundle-minos.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

mkdir -p "$TMP/wine/lib/wine/x86_64-unix" "$TMP/brew/lib" \
  "$TMP/empty-graphics/lib" "$TMP/empty-media/lib"
# Build a tiny x86_64 dylib with minos 14.0 (above the 10.15 floor).
echo 'int ogom_bundle_minos_probe=1;' > "$TMP/probe.c"
arch -x86_64 env "${CYDER_HOST_CLANG:-/usr/bin/clang}" -arch x86_64 -dynamiclib -mmacosx-version-min=14.0 \
  "$TMP/probe.c" -o "$TMP/brew/lib/libffi.8.dylib"
assert_eq "$(lipo -archs "$TMP/brew/lib/libffi.8.dylib")" "x86_64" \
  "the high-minos fixture must exercise the x86_64 runtime library path"
cp "$TMP/brew/lib/libffi.8.dylib" "$TMP/wine/lib/wine/x86_64-unix/libffi.8.dylib"

cat > "$TMP/run.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$1"
WINE="$2"
BREW="$3"
EMPTY_GRAPHICS="$4"
EMPTY_MEDIA="$5"
# Non-empty overrides: env-x86_64 treats "" as unset for :- defaults.
export HOMEBREW_PREFIX="$BREW"
export HOMEBREW_REPOSITORY="$BREW"
export HOMEBREW_CELLAR="$BREW/Cellar"
export GRAPHICS_INSTALL="$EMPTY_GRAPHICS"
export MEDIA_INSTALL="$EMPTY_MEDIA"
export MACOSX_DEPLOYMENT_TARGET=10.15
# shellcheck disable=SC1091
source "$ROOT/scripts/env-x86_64.sh"
bash "$ROOT/scripts/bundle-wine-dylibs.sh" "$WINE"
EOF
chmod +x "$TMP/run.sh"

set +e
out="$("$TMP/run.sh" "$ROOT" "$TMP/wine" "$TMP/brew" \
  "$TMP/empty-graphics" "$TMP/empty-media" 2>&1)"
status=$?
set -e
assert_eq "$status" "1" "bundler must fail when a dylib minos exceeds 10.15"
assert_contains "$out" "minos exceeds product floor" \
  "failure message should mention the product-floor minos gate"
assert_contains "$out" "libffi.8.dylib" \
  "failure should name the high-minos dylib"

# The same exceptions must apply during bundling and final archive scanning.
rm "$TMP/brew/lib/libffi.8.dylib" "$TMP/wine/lib/wine/x86_64-unix/libffi.8.dylib"
unix="$TMP/wine/lib/wine/x86_64-unix"
for version in 1.4.2 1.2.10; do
  /usr/bin/clang -arch x86_64 -dynamiclib -mmacosx-version-min=12.0 \
    "$TMP/probe.c" -o "$unix/libMoltenVK-$version.dylib"
done
"$TMP/run.sh" "$ROOT" "$TMP/wine" "$TMP/brew" \
  "$TMP/empty-graphics" "$TMP/empty-media" > "$TMP/reals.out" 2>&1

/usr/bin/clang -arch x86_64 -dynamiclib -mmacosx-version-min=12.1 \
  "$TMP/probe.c" -o "$unix/libMoltenVK-1.2.10.dylib"
if "$TMP/run.sh" "$ROOT" "$TMP/wine" "$TMP/brew" \
  "$TMP/empty-graphics" "$TMP/empty-media" > "$TMP/legacy-high.out" 2>&1; then
  echo 'expected legacy above macOS 12.0 to fail bundling' >&2
  exit 1
fi
assert_contains "$(cat "$TMP/legacy-high.out")" 'libMoltenVK-1.2.10.dylib minos=12.1' \
  'bundler must enforce the legacy real ceiling'
rm "$unix/libMoltenVK-1.2.10.dylib"
cp "$unix/libMoltenVK-1.4.2.dylib" "$unix/libMoltenVK.dylib"
if "$TMP/run.sh" "$ROOT" "$TMP/wine" "$TMP/brew" \
  "$TMP/empty-graphics" "$TMP/empty-media" > "$TMP/shim-high.out" 2>&1; then
  echo 'expected minos 12.0 shim to fail bundling' >&2
  exit 1
fi
assert_contains "$(cat "$TMP/shim-high.out")" 'libMoltenVK.dylib minos=12.0' \
  'unversioned MoltenVK keeps the general product floor'

# Real transitive token dependencies: a removed build RPATH must not cause
# media plugins or loader-relative runtime dependencies to be silently omitted.
fixture="$TMP/token-graph"
brew="$fixture/brew"
media="$fixture/media"
wine="$fixture/wine"
unix="$wine/lib/wine/x86_64-unix"
mkdir -p "$brew/lib" "$media/lib/gstreamer-1.0" "$unix"
compiler="${CYDER_HOST_CLANG:-/usr/bin/clang}"
printf 'int nested(void) { return 7; }\n' > "$fixture/nested.c"
printf 'extern int nested(void); int helper(void) { return nested(); }\n' > "$fixture/helper.c"
printf 'extern int helper(void); int plugin(void) { return helper(); }\n' > "$fixture/plugin.c"
"$compiler" -arch x86_64 -dynamiclib -mmacosx-version-min=10.15 \
  "$fixture/nested.c" -Wl,-install_name,@loader_path/libnested.1.dylib -o "$brew/lib/libnested.1.dylib"
"$compiler" -arch x86_64 -dynamiclib -mmacosx-version-min=10.15 \
  "$fixture/helper.c" "$brew/lib/libnested.1.dylib" \
  -Wl,-install_name,@rpath/libhelper.1.dylib -o "$media/lib/libhelper.1.dylib"
"$compiler" -arch x86_64 -dynamiclib -mmacosx-version-min=10.15 \
  "$fixture/plugin.c" "$media/lib/libhelper.1.dylib" \
  -Wl,-install_name,@rpath/libgstfixture.dylib -Wl,-rpath,/removed/build/temp \
  -o "$media/lib/gstreamer-1.0/libgstfixture.dylib"
# helper's @loader_path dependency lives beside its source, as brotli's does.
cp "$brew/lib/libnested.1.dylib" "$media/lib/libnested.1.dylib"
"$TMP/run.sh" "$ROOT" "$wine" "$brew" "$TMP/empty-graphics" "$media" > "$fixture/bundle.log" 2>&1
[[ -f "$unix/libhelper.1.dylib" && -f "$unix/libnested.1.dylib" ]] || {
  cat "$fixture/bundle.log"; echo 'transitive dylibs were not bundled' >&2; exit 1
}
plugin="$wine/lib/wine/gstreamer-1.0/libgstfixture.dylib"
assert_contains "$(otool -L "$plugin")" '@loader_path/../x86_64-unix/libhelper.1.dylib' 'plugin dependency must relocate'
# Actually load and call through the complete relocated graph.
cat > "$fixture/load.c" <<'C'
#include <dlfcn.h>
int main(int argc, char **argv) {
  if (argc != 2) return 1;
  void *lib = dlopen(argv[1], RTLD_NOW);
  if (!lib) return 2;
  int (*plugin)(void) = dlsym(lib, "plugin");
  return plugin && plugin() == 7 ? 0 : 3;
}
C
"$compiler" -arch x86_64 -mmacosx-version-min=10.15 "$fixture/load.c" -o "$fixture/load"
env -u DYLD_LIBRARY_PATH -u DYLD_FALLBACK_LIBRARY_PATH arch -x86_64 "$fixture/load" "$plugin"
# Missing loader-relative libraries must fail closed rather than report OK.
cp "$unix/libhelper.1.dylib" "$unix/libbroken.dylib"
install_name_tool -id @loader_path/libbroken.dylib \
  -change @loader_path/libnested.1.dylib @loader_path/libmissing.1.dylib "$unix/libbroken.dylib"
if "$TMP/run.sh" "$ROOT" "$wine" "$brew" "$TMP/empty-graphics" "$media" > "$fixture/missing.log" 2>&1; then
  echo 'missing transitive dependency escaped bundle validation' >&2; exit 1
fi
assert_contains "$(cat "$fixture/missing.log")" 'libmissing.1.dylib' 'missing dependency must be named'

echo "PASS test-bundle-wine-dylibs-source"
