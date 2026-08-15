#!/usr/bin/env bash
# Launch MapleStory with the single CX26 engine and the host's D3DMetal/GPTK.
# This path deliberately does not mount or validate MoltenVK; DXVK validation
# is a separate test path.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DRY_RUN=0
NO_OTP=0
WINE_INSTALL="${MAPLESTORY_CX26_WINE_INSTALL:-}"
WINEPREFIX_PATH="${MAPLESTORY_CX26_WINEPREFIX:-}"
EXE_PATH="${MAPLESTORY_CX26_EXE:-}"
GPTK_ROOT="${CYDER_GPTK_ROOT:-${MAPLESTORY_CX26_GPTK_ROOT:-}}"
COMPATDB_PATH="${MAPLESTORY_CX26_COMPATDB_PATH:-${CYDER_COMPATDB_PATH:-}}"
MEDIA_INSTALL="${MEDIA_INSTALL:-$ROOT/install/media-cx26-x86_64}"
LOG_ROOT="${MAPLESTORY_CX26_LOG_ROOT:-$HOME/Library/Application Support/Cyder-MapleStory-CX26/Logs}"
DEBUG_CHANNELS="${MAPLESTORY_CX26_WINEDEBUG:-+timestamp,+pid,+process,+loaddll,+seh,+winediag,+d3d11,+dxgi,+wined3d,+macdrv}"
PREFIX_EXPLICIT=0

usage() {
  cat <<EOF
Usage: $(basename "$0") --launch-exe PATH [options] [-- HOST PORT BeanFun SERVICE_ACCOUNT_ID OTP]
       $(basename "$0") --launch-exe PATH [options] --no-otp

Launch MapleStory with the production CX26 engine and D3DMetal/GPTK.
MoltenVK is intentionally not part of this path.

Options:
  --launch-exe PATH     MapleStory.exe (required; may be outside the prefix)
  --wine-install PATH   CX26 Wine install (default: local install or Cyder runtime)
  --wineprefix PATH     Wine prefix (default: infer from .../drive_c/... when possible)
  --gptk-root PATH      Apple GPTK root containing wine/ and external/
  --compatdb PATH       CompatDB policy database (.cdb) supplied by the app
  --media-install PATH  Isolated GLib/GStreamer install
  --log-root PATH       Session log directory
  --no-otp              Launch without BeanFun arguments for lifecycle smoke testing
  --dry-run             Validate the runtime contract and print the launch plan
  -h, --help

Environment overrides:
  MAPLESTORY_CX26_WINE_INSTALL, MAPLESTORY_CX26_WINEPREFIX,
  MAPLESTORY_CX26_EXE, CYDER_GPTK_ROOT, MAPLESTORY_CX26_GPTK_ROOT,
  MAPLESTORY_CX26_COMPATDB_PATH, CYDER_COMPATDB_PATH,
  MEDIA_INSTALL, MAPLESTORY_CX26_LOG_ROOT, MAPLESTORY_CX26_WINEDEBUG,
  CYDER_MSYNC, CYDER_ESYNC, CYDER_WINE_DIAGNOSTICS, MTL_HUD_ENABLED
EOF
}

die() { printf 'run-maplestory-cx26-d3dmetal: %s\n' "$*" >&2; exit 1; }

clean_prefix_session() {
  local wineserver="$WINE_INSTALL/bin/wineserver"

  [[ -x "$wineserver" ]] || die "wineserver missing: $wineserver"

  # A forced game close can leave BlackCipher/Nexon helpers detached from the
  # launcher.  Kill and reap this exact prefix before every real launch so an
  # A/B run never shares a wineserver session with an earlier attempt.
  WINEPREFIX="$WINEPREFIX_PATH" WINESERVER="$wineserver" \
    arch -x86_64 "$wineserver" -k >/dev/null 2>&1 || true
  # `wineserver -w` is unsafe for a prefix that has no live server: on macOS
  # it can create/check in a fresh Mach port and make the subsequent Wine
  # client fail with "Can't check in server_mach_port".  -k terminates the
  # existing prefix session; allow its clients a short reap window instead.
  sleep 3
}

resolve_wine_install() {
  [[ -n "$WINE_INSTALL" ]] && return 0
  local candidate
  for candidate in \
    "$ROOT/install/wine-cx26-x86_64" \
    "$HOME/.cyder/runtime/Engines/wine-x86_64"; do
    if [[ -x "$candidate/bin/wine" ]]; then
      WINE_INSTALL="$candidate"
      return 0
    fi
  done
  WINE_INSTALL="$ROOT/install/wine-cx26-x86_64"
}

resolve_gptk_root() {
  [[ -n "$GPTK_ROOT" ]] && return 0
  local candidate
  for candidate in \
    "$WINE_INSTALL/lib64/apple_gptk" \
    "$HOME/.cyder/runtime/Engines/maplestory-oem25/lib64/apple_gptk" \
    "$HOME/Library/Application Support/Cyder-maplestory-oem25/runtime/apple_gptk" \
    "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib64/apple_gptk"; do
    if [[ -f "$candidate/external/libd3dshared.dylib" ]]; then
      GPTK_ROOT="$candidate"
      return 0
    fi
  done
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --launch-exe)
      [[ $# -ge 2 ]] || die '--launch-exe requires PATH'
      EXE_PATH="$2"
      shift
      ;;
    --wine-install)
      [[ $# -ge 2 ]] || die '--wine-install requires PATH'
      WINE_INSTALL="$2"
      shift
      ;;
    --wineprefix)
      [[ $# -ge 2 ]] || die '--wineprefix requires PATH'
      WINEPREFIX_PATH="$2"
      PREFIX_EXPLICIT=1
      shift
      ;;
    --gptk-root)
      [[ $# -ge 2 ]] || die '--gptk-root requires PATH'
      GPTK_ROOT="$2"
      shift
      ;;
    --compatdb)
      [[ $# -ge 2 ]] || die '--compatdb requires PATH'
      COMPATDB_PATH="$2"
      shift
      ;;
    --media-install)
      [[ $# -ge 2 ]] || die '--media-install requires PATH'
      MEDIA_INSTALL="$2"
      shift
      ;;
    --log-root)
      [[ $# -ge 2 ]] || die '--log-root requires PATH'
      LOG_ROOT="$2"
      shift
      ;;
    --no-otp) NO_OTP=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --) shift; break ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

game_args=("$@")
resolve_wine_install
resolve_gptk_root

[[ -n "$EXE_PATH" ]] || die '--launch-exe PATH is required'
[[ -x "$WINE_INSTALL/bin/wine" ]] || die "wine missing: $WINE_INSTALL/bin/wine"
[[ -x "$WINE_INSTALL/bin/wineserver" ]] || die "wineserver missing: $WINE_INSTALL/bin/wineserver"
[[ -f "$WINE_INSTALL/lib/wine/x86_64-unix/cxcompatdb.so" ]] || \
  die "cxcompatdb.so missing: build the CX26 engine before running this test"
[[ -n "$COMPATDB_PATH" ]] || \
  die 'CompatDB .cdb path is required; pass --compatdb PATH or MAPLESTORY_CX26_COMPATDB_PATH'
[[ -f "$COMPATDB_PATH" ]] || die "CompatDB database missing: $COMPATDB_PATH"
[[ -n "$GPTK_ROOT" ]] || die 'D3DMetal GPTK root not found; pass --gptk-root PATH'
[[ -f "$GPTK_ROOT/external/libd3dshared.dylib" ]] || \
  die "GPTK host library missing: $GPTK_ROOT/external/libd3dshared.dylib"
[[ -f "$GPTK_ROOT/wine/x86_64-windows/d3d11.dll" ]] || \
  die "GPTK d3d11.dll missing: $GPTK_ROOT/wine/x86_64-windows"
[[ -f "$GPTK_ROOT/wine/x86_64-windows/dxgi.dll" ]] || \
  die "GPTK dxgi.dll missing: $GPTK_ROOT/wine/x86_64-windows"
[[ -f "$EXE_PATH" ]] || die "MapleStory.exe missing: $EXE_PATH"

if [[ "$PREFIX_EXPLICIT" -eq 0 && "$EXE_PATH" == */drive_c/* ]]; then
  WINEPREFIX_PATH="${EXE_PATH%%/drive_c/*}"
fi
WINEPREFIX_PATH="${WINEPREFIX_PATH:-$HOME/Library/Application Support/Cyder-MapleStory-CX26/bottles/shared}"

if [[ "$NO_OTP" -eq 1 ]]; then
  [[ ${#game_args[@]} -eq 0 ]] || die '--no-otp does not take game args'
else
  [[ ${#game_args[@]} -eq 5 ]] || die 'expected HOST PORT BeanFun SERVICE_ACCOUNT_ID OTP'
  [[ "${game_args[0]}" == 'tw.login.maplestory.beanfun.com' ]] || die 'unexpected MapleStory login host'
  [[ "${game_args[1]}" == '8484' ]] || die 'unexpected MapleStory login port'
  [[ "${game_args[2]}" == 'BeanFun' ]] || die 'login mode must be BeanFun'
  [[ "${game_args[3]}" == T9* ]] || die 'ServiceAccountID must begin with T9'
  [[ -n "${game_args[4]}" ]] || die 'OTP must not be empty'
fi

wine_bin="$WINE_INSTALL/bin/wine"
wineserver_bin="$WINE_INSTALL/bin/wineserver"
cxcompatdb="$WINE_INSTALL/lib/wine/x86_64-unix/cxcompatdb.so"
gptk_host="$GPTK_ROOT/external/libd3dshared.dylib"
timestamp="$(date '+%Y%m%d-%H%M%S')"
log_file="$LOG_ROOT/maplestory-cx26-d3dmetal-$timestamp-$$.log"
redacted_args='(none --no-otp)'
if [[ "$NO_OTP" -eq 0 ]]; then
  redacted_args="${game_args[0]} ${game_args[1]} ${game_args[2]} ${game_args[3]} <OTP-redacted>"
fi

export WINEPREFIX="$WINEPREFIX_PATH"
export WINELOADER="$wine_bin"
export WINESERVER="$wineserver_bin"
export LANG=zh_TW.UTF-8 LC_ALL=zh_TW.UTF-8 LC_CTYPE=zh_TW.UTF-8
export RAW_AUDIO_PARSE=1
export CYDER_GRAPHICS_BACKEND=d3dmetal
export CYDER_GRAPHICS_BACKENDS_ROOT="$WINE_INSTALL"
export CYDER_GPTK_ROOT="$GPTK_ROOT"
export CYDER_COMPATDB_PATH="$COMPATDB_PATH"
export CX_APPLEGPTK_LIBD3DSHARED_PATH="$gptk_host"
export CYDER_MSYNC="${CYDER_MSYNC:-1}"
export CYDER_ESYNC="${CYDER_ESYNC:-0}"
export CYDER_WINE_DIAGNOSTICS="${CYDER_WINE_DIAGNOSTICS:-quiet}"
export MTL_HUD_ENABLED="${MTL_HUD_ENABLED:-1}"
export WINEDEBUG="$DEBUG_CHANNELS"
export DYLD_FALLBACK_LIBRARY_PATH="$WINE_INSTALL/lib:$WINE_INSTALL/lib/wine/x86_64-unix:$MEDIA_INSTALL/lib:$GPTK_ROOT/external${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}"
export GST_PLUGIN_SYSTEM_PATH_1_0="$MEDIA_INSTALL/lib/gstreamer-1.0"
export GST_PLUGIN_PATH_1_0="$MEDIA_INSTALL/lib/gstreamer-1.0"

{
  echo "CX26 MapleStory D3DMetal launch"
  echo "  WINE_INSTALL=$WINE_INSTALL"
  echo "  WINESERVER=$WINESERVER"
  echo "  WINEPREFIX=$WINEPREFIX_PATH"
  echo "  EXE=$EXE_PATH"
  echo "  GPTK_ROOT=$GPTK_ROOT"
  echo "  COMPATDB_PATH=$COMPATDB_PATH"
  echo "  MEDIA_INSTALL=$MEDIA_INSTALL"
  echo "  CYDER_GRAPHICS_BACKEND=d3dmetal"
  echo "  CYDER_MSYNC=$CYDER_MSYNC"
  echo "  CYDER_ESYNC=$CYDER_ESYNC"
  echo "  CYDER_WINE_DIAGNOSTICS=$CYDER_WINE_DIAGNOSTICS"
  echo "  MTL_HUD_ENABLED=$MTL_HUD_ENABLED"
  echo "  WINEDEBUG=$DEBUG_CHANNELS"
  echo "  argv=$redacted_args"
  echo "  log=$log_file"
}

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "+ cd $(dirname "$EXE_PATH")"
  if [[ "$NO_OTP" -eq 1 ]]; then
    echo "+ arch -x86_64 env ... $wine_bin $EXE_PATH"
  else
    echo "+ arch -x86_64 env ... $wine_bin $EXE_PATH ${game_args[*]}"
  fi
  exit 0
fi

mkdir -p "$LOG_ROOT" "$WINEPREFIX_PATH"
chmod 0700 "$LOG_ROOT" 2>/dev/null || true
clean_prefix_session
cd "$(dirname "$EXE_PATH")"
if [[ "$NO_OTP" -eq 1 ]]; then
  arch -x86_64 env \
    WINELOADER="$wine_bin" WINEPREFIX="$WINEPREFIX_PATH" WINEDEBUG="$DEBUG_CHANNELS" \
    CYDER_GRAPHICS_BACKEND=d3dmetal CYDER_GRAPHICS_BACKENDS_ROOT="$WINE_INSTALL" \
    CYDER_GPTK_ROOT="$GPTK_ROOT" CYDER_COMPATDB_PATH="$COMPATDB_PATH" \
    CX_APPLEGPTK_LIBD3DSHARED_PATH="$gptk_host" RAW_AUDIO_PARSE=1 \
    CYDER_MSYNC="$CYDER_MSYNC" CYDER_ESYNC="$CYDER_ESYNC" \
    CYDER_WINE_DIAGNOSTICS="$CYDER_WINE_DIAGNOSTICS" MTL_HUD_ENABLED="$MTL_HUD_ENABLED" \
    DYLD_FALLBACK_LIBRARY_PATH="$DYLD_FALLBACK_LIBRARY_PATH" \
    GST_PLUGIN_SYSTEM_PATH_1_0="$GST_PLUGIN_SYSTEM_PATH_1_0" \
    GST_PLUGIN_PATH_1_0="$GST_PLUGIN_PATH_1_0" \
    LANG=zh_TW.UTF-8 LC_ALL=zh_TW.UTF-8 LC_CTYPE=zh_TW.UTF-8 \
    "$wine_bin" "$EXE_PATH" 2>&1 | tee -a "$log_file"
else
  arch -x86_64 env \
    WINELOADER="$wine_bin" WINEPREFIX="$WINEPREFIX_PATH" WINEDEBUG="$DEBUG_CHANNELS" \
    CYDER_GRAPHICS_BACKEND=d3dmetal CYDER_GRAPHICS_BACKENDS_ROOT="$WINE_INSTALL" \
    CYDER_GPTK_ROOT="$GPTK_ROOT" CYDER_COMPATDB_PATH="$COMPATDB_PATH" \
    CX_APPLEGPTK_LIBD3DSHARED_PATH="$gptk_host" RAW_AUDIO_PARSE=1 \
    CYDER_MSYNC="$CYDER_MSYNC" CYDER_ESYNC="$CYDER_ESYNC" \
    CYDER_WINE_DIAGNOSTICS="$CYDER_WINE_DIAGNOSTICS" MTL_HUD_ENABLED="$MTL_HUD_ENABLED" \
    DYLD_FALLBACK_LIBRARY_PATH="$DYLD_FALLBACK_LIBRARY_PATH" \
    GST_PLUGIN_SYSTEM_PATH_1_0="$GST_PLUGIN_SYSTEM_PATH_1_0" \
    GST_PLUGIN_PATH_1_0="$GST_PLUGIN_PATH_1_0" \
    LANG=zh_TW.UTF-8 LC_ALL=zh_TW.UTF-8 LC_CTYPE=zh_TW.UTF-8 \
    "$wine_bin" "$EXE_PATH" "${game_args[@]}" 2>&1 | tee -a "$log_file"
fi
