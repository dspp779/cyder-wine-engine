#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
backend=wined3d
renderer=gl
renderer_explicit=0
bottle=shared-test
mode=game
gptk=""
interactive=0
[[ $# -gt 0 ]] || interactive=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --backend) backend="${2:?}"; shift 2 ;;
    --wined3d-renderer) renderer="${2:?}"; renderer_explicit=1; shift 2 ;;
    --bottle) bottle="${2:?}"; shift 2 ;;
    --gptk-root) gptk="${2:?}"; shift 2 ;;
    --smoke) mode=smoke; shift ;;
    --stop) mode=stop; shift ;;
    --dry-run) mode=dry-run; shift ;;
    --) shift; break ;;
    -*) fail "未知選項：$1" ;;
    *) break ;;
  esac
done
case "$backend" in wined3d|dxmt|dxvk|dxvk2|d3dmetal) ;; *) fail 'backend 必須是 wined3d、dxmt、dxvk、dxvk2 或 d3dmetal。' ;; esac
case "$renderer" in gl|gdi) ;; *) fail 'wined3d renderer 必須是 gl 或 gdi。' ;; esac
[[ "$renderer_explicit" == 0 || "$backend" == wined3d ]] || fail '--wined3d-renderer 僅適用於 wined3d。'
[[ "$bottle" =~ ^[A-Za-z0-9_-]{1,40}$ ]] || fail '瓶子名稱僅接受 1–40 個英文字母、數字、底線或連字號。'
[[ -f "$ROOT/.cyder-test-version" && "$(cat "$ROOT/.cyder-test-version")" == "$TEST_VERSION" ]] || fail '請先執行 Install.command。'
verify_tree "$ROOT"
if [[ "$interactive" == 1 ]]; then
  backend="$(/usr/bin/osascript -e 'choose from list {"wined3d", "dxmt", "dxvk2", "dxvk"} with prompt "選擇後端：PR #2 DirectDraw 測試請選 wined3d；CS2 請選 dxmt。" default items {"wined3d"}')" || exit 0
  [[ "$backend" != false ]] || exit 0
  exe="$(/usr/bin/osascript -e 'POSIX path of (choose file with prompt "選擇遊戲或 Steam 安裝程式 EXE")')" || exit 0
  set -- "$exe"
fi
major="$(/usr/bin/sw_vers -productVersion)"; major="${major%%.*}"
case "$backend" in dxmt) (( major >= 15 )) || fail 'DXMT 需要 macOS 15 或以上。' ;; dxvk|dxvk2) (( major >= 12 )) || fail 'Vulkan 測試需要 macOS 12 或以上。' ;; esac
ENGINE="$ROOT/engine"
PREFIX="$ROOT/prefixes/$bottle"
[[ ! -L "$ROOT/prefixes" && ! -L "$PREFIX" ]] || fail '測試瓶子不可連結至其他環境。'
if [[ -d "$PREFIX" ]]; then
  resolved="$(cd "$PREFIX" && pwd -P)"
  [[ "$resolved" == "$ROOT/prefixes/"* ]] || fail '測試瓶子超出專用目錄。'
fi
# Test identity owns every prefix below ROOT. Never inherit a production prefix,
# loader, backend override or external dylib search path from the caller.
unset WINEPREFIX WINELOADER WINESERVER WINEDLLPATH WINEARCH WINEDLLOVERRIDES
unset DYLD_LIBRARY_PATH DYLD_FALLBACK_LIBRARY_PATH WINE_D3D_CONFIG
unset CYDER_COMPATDB_PATH CYDER_GRAPHICS_BACKEND_PATH CYDER_GPTK_ROOT
unset CX_GRAPHICS_BACKEND CX_ACTIVE_GRAPHICS_BACKEND CYDER_ACTIVE_GRAPHICS_BACKEND CYDER_ACTIVE_GRAPHICS_BACKEND_PATH
export WINEPREFIX="$PREFIX" WINELOADER="$ENGINE/bin/wine" WINESERVER="$ENGINE/bin/wineserver"
export CYDER_COMPATDB=0 CYDER_GRAPHICS_BACKEND="$backend" CYDER_GRAPHICS_BACKENDS_ROOT="$ENGINE"
export WINEDEBUG=err+all,warn+seh
if [[ "$backend" == wined3d ]]; then export WINE_D3D_CONFIG="renderer=$renderer"; fi
if [[ "$backend" == d3dmetal ]]; then
  [[ -f "$gptk/wine/x86_64-windows/d3d11.dll" && -f "$gptk/external/libd3dshared.dylib" ]] || fail '請用 --gptk-root 指定自行合法安裝的 GPTK 根目錄。'
  export CYDER_GPTK_ROOT="$gptk"
fi
if [[ "$mode" == stop ]]; then
  [[ -d "$PREFIX" ]] || exit 0
  arch -x86_64 "$ENGINE/bin/wineserver" -k
  sleep 3
  exit 0
fi
if [[ "$mode" == dry-run ]]; then
  printf 'engine=%s\nprefix=%s\nbackend=%s\ncompatdb=disabled-for-controlled-test\n' "$ENGINE" "$PREFIX" "$backend"
  printf 'wine_d3d_config=%s\n' "${WINE_D3D_CONFIG:-<backend-managed>}"
  exit 0
fi
arch -x86_64 /usr/bin/true || fail 'Rosetta 2 尚不可用。'
source "$KIT/prepare-media-environment.sh"
test_runtime_prepare_media_environment "$ENGINE" "$ROOT"
mkdir -p "$ROOT/logs"
log="$ROOT/logs/$(date +%Y%m%d-%H%M%S)-$bottle-$backend-$$.log"
echo "Engine：$TEST_VERSION"
echo "瓶子：$PREFIX"
echo "後端：${backend}；日誌：${log}"
# Build the new prefix using builtin graphics before selecting an optional
# renderer. Suppress only bootstrap-time Mono/Gecko installers, not game DLLs.
if [[ ! -f "$PREFIX/.cyder-test-initialized" ]]; then
  echo '正在初始化專用 Windows 環境（builtin OpenGL）…'
  CYDER_GRAPHICS_BACKEND=wined3d WINE_D3D_CONFIG=renderer=gl WINEDLLOVERRIDES=mscoree,mshtml= \
    arch -x86_64 "$ENGINE/bin/wine" wineboot.exe -u 2>&1 | tee -a "$log"
  [[ -f "$PREFIX/system.reg" && -f "$PREFIX/user.reg" ]] || fail '測試瓶子初始化不完整；請查看日誌。'
  printf '%s\n' "$TEST_VERSION" > "$PREFIX/.cyder-test-initialized"
fi
if [[ "$backend" == dxmt ]]; then
  source "$KIT/prepare-dxmt-prefix.sh"
  test_runtime_prepare_dxmt_prefix "$ENGINE" "$PREFIX" "$ROOT" "$TEST_VERSION"
fi
if [[ "$mode" == smoke ]]; then
  export WINEDLLOVERRIDES=mscoree,mshtml=
  cleanup_smoke() { arch -x86_64 "$ENGINE/bin/wineserver" -k >/dev/null 2>&1 || true; sleep 3; }
  trap cleanup_smoke EXIT
  for machine in x86_64 i686; do
    echo "Smoke architecture: $machine"
    arch -x86_64 "$ENGINE/bin/wine" "$KIT/tests/runtime-smoke-$machine.exe" 2>&1 | tee -a "$log"
  done
else
  [[ $# -gt 0 && -f "$1" ]] || fail '請提供遊戲 EXE；或不帶參數雙擊以選取。'
  exe="$1"; shift
  case "$exe" in /*) ;; *) exe="$(cd "$(dirname "$exe")" && pwd -P)/$(basename "$exe")" ;; esac
  cd "$(dirname "$exe")"
  arch -x86_64 "$ENGINE/bin/wine" "$exe" "$@" 2>&1 | tee -a "$log"
fi
