#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/assert.sh"
ARCHIVE="${CX26_SOURCE_ARCHIVE:-$ROOT/tools/archives/crossover-sources-26.3.0.tar.gz}"
PATCH_NAME="cyder-wined3d-gl-sm5-feature-level-11.patch"
PATCH_FILE="$ROOT/patches/$PATCH_NAME"
PATCH_TEXT="$(<"$PATCH_FILE")"
BUILD_SCRIPT="$(<"$ROOT/scripts/build-wine.sh")"

assert_contains "$BUILD_SCRIPT" "apply_cyder_patch \"\$OGOM/patches/$PATCH_NAME\"" \
  "CX26 build should apply $PATCH_NAME"
assert_contains "$BUILD_SCRIPT" "grep -Fq 'CyderGLShaderModel5' \"\$WINE_SRC/dlls/wined3d/wined3d_main.c\"" \
  "build should detect the wined3d SM5 marker"
assert_contains "$(<"$ROOT/config/engine-release.json")" "$PATCH_NAME" \
  "release manifest should record $PATCH_NAME"
assert_contains "$PATCH_TEXT" "\"CyderGLShaderModel5\"" \
  "patch should read the opt-in CyderGLShaderModel5 setting"
assert_contains "$PATCH_TEXT" "wined3d_settings.cyder_gl_sm5" \
  "SM5 and FL11_0 must stay behind the opt-in setting"
assert_contains "$PATCH_TEXT" "gl_info->supported[ARB_GPU_SHADER5]" \
  "SM5 should still require ARB_gpu_shader5"
assert_contains "$PATCH_TEXT" "return WINED3D_FEATURE_LEVEL_11;" \
  "GL adapter should report FL11_0 when the option is set"
assert_contains "$PATCH_TEXT" "if (!priv->gl_info->supported[EXT_SHADER_INTEGER_MIX])" \
  "ftoi/ftou should avoid integer mix() when EXT_shader_integer_mix is missing"
assert_contains "$PATCH_TEXT" "2147483520.0" \
  "ftoi fallback should clamp to the largest float below 2^31"
assert_contains "$PATCH_TEXT" "4294967040.0" \
  "ftou fallback should clamp to the largest float below 2^32"
assert_contains "$PATCH_TEXT" "if (!priv->gl_info->supported[ARB_DERIVATIVE_CONTROL])" \
  "coarse/fine derivatives should fall back to dFdx/dFdy without ARB_derivative_control"

# The patch must apply before the MapleStory wined3d patches.
kernelbase_line="$(grep -n 'cyder-kernelbase-disk-free-space-fallback.patch"$' "$ROOT/scripts/build-wine.sh" | tail -1 | cut -d: -f1)"
sm5_line="$(grep -n "$PATCH_NAME\"\$" "$ROOT/scripts/build-wine.sh" | tail -1 | cut -d: -f1)"
core_line="$(grep -n '"maplestory-cx26-core.patch"' "$ROOT/scripts/build-wine.sh" | head -1 | cut -d: -f1)"
if (( kernelbase_line >= sm5_line || sm5_line >= core_line )); then
  echo "ASSERT failed: $PATCH_NAME should apply after kernelbase and before maplestory-cx26-core" >&2
  exit 1
fi

if [[ ! -f "$ARCHIVE" ]]; then
  echo "SKIP wined3d SM5 patch round-trip: source archive not found at $ARCHIVE"
  exit 0
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cyder-wined3d-sm5.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

tar -xzf "$ARCHIVE" -C "$TMP_DIR" sources/wine/dlls/wined3d
SOURCE="$TMP_DIR/sources/wine"

patch --forward --batch -s -p1 -d "$SOURCE" < "$PATCH_FILE"
grep -Fq 'CyderGLShaderModel5' "$SOURCE/dlls/wined3d/wined3d_main.c"
grep -Fq 'unsigned int cyder_gl_sm5;' "$SOURCE/dlls/wined3d/wined3d_private.h"
grep -Fq 'wined3d_settings.cyder_gl_sm5' "$SOURCE/dlls/wined3d/glsl_shader.c"
grep -Fq 'wined3d_settings.cyder_gl_sm5' "$SOURCE/dlls/wined3d/adapter_gl.c"
[[ "$(grep -Fc 'supported[EXT_SHADER_INTEGER_MIX])' "$SOURCE/dlls/wined3d/glsl_shader.c")" -ge 2 ]]
patch --reverse --batch -s -p1 -d "$SOURCE" < "$PATCH_FILE"

echo "PASS wined3d GL SM5 patch"
