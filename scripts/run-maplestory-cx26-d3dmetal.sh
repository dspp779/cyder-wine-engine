#!/usr/bin/env bash
# Launch MapleStory with the single CX26 engine.
# Default backend is D3DMetal/GPTK. Pass --graphics-backend dxmt for DXMT A/B.
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
GRAPHICS_BACKEND="${MAPLESTORY_CX26_GRAPHICS_BACKEND:-d3dmetal}"
MEDIA_INSTALL="${MEDIA_INSTALL:-}"
MEDIA_INSTALL_EXPLICIT=0
[[ -n "$MEDIA_INSTALL" ]] && MEDIA_INSTALL_EXPLICIT=1
MEDIA_SOURCE=""
MEDIA_LIB=""
GST_PLUGIN_DIR=""
GST_SCANNER=""
LOG_ROOT="${MAPLESTORY_CX26_LOG_ROOT:-$HOME/Library/Application Support/Cyder-MapleStory-CX26/Logs}"
DEBUG_CHANNELS="${MAPLESTORY_CX26_WINEDEBUG:-+timestamp,+pid,+process,+loaddll,+seh,+winediag,+d3d11,+dxgi,+wined3d,+macdrv}"
PREFIX_EXPLICIT=0

usage() {
  cat <<EOF
Usage: $(basename "$0") --launch-exe PATH [options] [-- HOST PORT BeanFun SERVICE_ACCOUNT_ID OTP]
       $(basename "$0") --launch-exe PATH [options] --no-otp

Launch MapleStory with the production CX26 engine.
Default graphics backend is D3DMetal/GPTK; use --graphics-backend dxmt for DXMT.
MoltenVK is intentionally not part of this path.

Options:
  --launch-exe PATH     MapleStory.exe (required; may be outside the prefix)
  --wine-install PATH   CX26 Wine install (default: local install or Cyder runtime)
  --wineprefix PATH     Wine prefix (default: infer from .../drive_c/... when possible)
  --graphics-backend B  d3dmetal (default) or dxmt
  --gptk-root PATH      Apple GPTK root containing wine/ and external/ (d3dmetal)
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
  MAPLESTORY_CX26_GRAPHICS_BACKEND,
  MEDIA_INSTALL, MAPLESTORY_CX26_LOG_ROOT, MAPLESTORY_CX26_WINEDEBUG,
  CYDER_MSYNC, CYDER_ESYNC, CYDER_WINE_DIAGNOSTICS, MTL_HUD_ENABLED,
  CYDER_MAPLESTORY_PREWARM, CYDER_MAPLESTORY_PREWARM_MAX_BYTES,
  CYDER_MAPLESTORY_FILE_CACHE, CYDER_MAPLESTORY_IO_TRACE, CYDER_MAPLESTORY_IO_PROFILE,
  CYDER_MAPLESTORY_FILE_CACHE_MMAP, CYDER_MAPLESTORY_FILE_CACHE_PREWARM_IN_PROCESS,
  CYDER_MAPLESTORY_FILE_CACHE_PREWARM_MAX_BYTES,
  CYDER_MAPLESTORY_FILE_CACHE_FAST_HIT, CYDER_MAPLESTORY_IO_CACHE_TIMING,
  CYDER_MAPLESTORY_IO_PROFILE_TIMING, CYDER_MAPLESTORY_IO_PROFILE_FULL_OFFSETS,
  CYDER_MAPLESTORY_IO_PROFILE_SIMULATE, CYDER_MAPLESTORY_IO_RING,
  CYDER_MAPLESTORY_IO_RING_ARM_FILE, CYDER_MAPLESTORY_IO_SUMMARY,
  CYDER_MAPLESTORY_IO_TIMELINE, CYDER_MAPLESTORY_IO_CACHE_STATS,
  CYDER_MAPLESTORY_IO_SECTION_MAP
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

# Wine only loads prepended builtins after a matching PE exists in the prefix.
# DXMT's d3d11/dxgi import winemetal.dll, which wineboot never places there.
ensure_dxmt_winemetal_prefix() {
  local prefix="$1" engine="$2"
  local arch source destination temporary

  for arch in x86_64 i386; do
    source="$engine/lib/dxmt/${arch}-windows/winemetal.dll"
    [[ -f "$source" ]] || die "DXMT payload missing $arch winemetal.dll: $source"
  done
  for arch in x86_64 i386; do
    source="$engine/lib/dxmt/${arch}-windows/winemetal.dll"
    if [[ "$arch" == x86_64 ]]; then
      destination="$prefix/drive_c/windows/system32/winemetal.dll"
    else
      destination="$prefix/drive_c/windows/syswow64/winemetal.dll"
    fi
    mkdir -p "$(dirname "$destination")"
    temporary="$(mktemp "$(dirname "$destination")/.winemetal.dll.XXXXXX")"
    cp "$source" "$temporary"
    chmod 0644 "$temporary"
    mv -f "$temporary" "$destination"
  done
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
      MEDIA_INSTALL_EXPLICIT=1
      shift
      ;;
    --log-root)
      [[ $# -ge 2 ]] || die '--log-root requires PATH'
      LOG_ROOT="$2"
      shift
      ;;
    --graphics-backend)
      [[ $# -ge 2 ]] || die '--graphics-backend requires d3dmetal|dxmt'
      GRAPHICS_BACKEND="$2"
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
case "$GRAPHICS_BACKEND" in
  d3dmetal|dxmt) ;;
  *) die "unsupported --graphics-backend: $GRAPHICS_BACKEND (expected d3dmetal|dxmt)" ;;
esac
resolve_wine_install
if [[ "$GRAPHICS_BACKEND" == d3dmetal ]]; then
  resolve_gptk_root
fi

resolve_media_runtime() {
  if [[ "$MEDIA_INSTALL_EXPLICIT" -eq 1 ]]; then
    MEDIA_SOURCE=external
    MEDIA_LIB="$MEDIA_INSTALL/lib"
    GST_PLUGIN_DIR="$MEDIA_INSTALL/lib/gstreamer-1.0"
    GST_SCANNER="$MEDIA_INSTALL/libexec/gstreamer-1.0/gst-plugin-scanner"
  elif [[ -d "$WINE_INSTALL/lib/wine/gstreamer-1.0" ]]; then
    # Packed engines keep the media stack inside the engine artifact. The core
    # dylibs live beside the Unix Wine modules; plugins/scanner retain their
    # GStreamer subtrees below the engine root.
    MEDIA_SOURCE=bundled
    MEDIA_INSTALL="$WINE_INSTALL"
    MEDIA_LIB="$WINE_INSTALL/lib/wine/x86_64-unix"
    GST_PLUGIN_DIR="$WINE_INSTALL/lib/wine/gstreamer-1.0"
    GST_SCANNER="$WINE_INSTALL/libexec/gstreamer-1.0/gst-plugin-scanner"
  else
    MEDIA_SOURCE=external
    if [[ -d "$ROOT/install/media-cx26-full-video-x86_64/lib/gstreamer-1.0" ]]; then
      MEDIA_INSTALL="$ROOT/install/media-cx26-full-video-x86_64"
    else
      MEDIA_INSTALL="$ROOT/install/media-cx26-x86_64"
    fi
    MEDIA_LIB="$MEDIA_INSTALL/lib"
    GST_PLUGIN_DIR="$MEDIA_INSTALL/lib/gstreamer-1.0"
    GST_SCANNER="$MEDIA_INSTALL/libexec/gstreamer-1.0/gst-plugin-scanner"
  fi

  [[ -d "$MEDIA_LIB" ]] || die "GStreamer library directory missing: $MEDIA_LIB"
  [[ -d "$GST_PLUGIN_DIR" ]] || die "GStreamer plugin directory missing: $GST_PLUGIN_DIR"
}

resolve_media_runtime

[[ -n "$EXE_PATH" ]] || die '--launch-exe PATH is required'
[[ -x "$WINE_INSTALL/bin/wine" ]] || die "wine missing: $WINE_INSTALL/bin/wine"
[[ -x "$WINE_INSTALL/bin/wineserver" ]] || die "wineserver missing: $WINE_INSTALL/bin/wineserver"
[[ -f "$WINE_INSTALL/lib/wine/x86_64-unix/cxcompatdb.so" ]] || \
  die "cxcompatdb.so missing: build the CX26 engine before running this test"
[[ -n "$COMPATDB_PATH" ]] || \
  die 'CompatDB .cdb path is required; pass --compatdb PATH or MAPLESTORY_CX26_COMPATDB_PATH'
[[ -f "$COMPATDB_PATH" ]] || die "CompatDB database missing: $COMPATDB_PATH"
[[ -f "$EXE_PATH" ]] || die "MapleStory.exe missing: $EXE_PATH"

if [[ "$GRAPHICS_BACKEND" == d3dmetal ]]; then
  [[ -n "$GPTK_ROOT" ]] || die 'D3DMetal GPTK root not found; pass --gptk-root PATH'
  [[ -f "$GPTK_ROOT/external/libd3dshared.dylib" ]] || \
    die "GPTK host library missing: $GPTK_ROOT/external/libd3dshared.dylib"
  [[ -f "$GPTK_ROOT/wine/x86_64-windows/d3d11.dll" ]] || \
    die "GPTK d3d11.dll missing: $GPTK_ROOT/wine/x86_64-windows"
  [[ -f "$GPTK_ROOT/wine/x86_64-windows/dxgi.dll" ]] || \
    die "GPTK dxgi.dll missing: $GPTK_ROOT/wine/x86_64-windows"
else
  [[ -f "$WINE_INSTALL/lib/dxmt/x86_64-windows/d3d11.dll" ]] || \
    die "DXMT d3d11.dll missing: $WINE_INSTALL/lib/dxmt/x86_64-windows"
  [[ -f "$WINE_INSTALL/lib/dxmt/x86_64-windows/dxgi.dll" ]] || \
    die "DXMT dxgi.dll missing: $WINE_INSTALL/lib/dxmt/x86_64-windows"
  [[ -f "$WINE_INSTALL/lib/dxmt/x86_64-windows/winemetal.dll" ]] || \
    die "DXMT winemetal.dll missing: $WINE_INSTALL/lib/dxmt/x86_64-windows"
  [[ -f "$WINE_INSTALL/lib/dxmt/x86_64-unix/winemetal.so" ]] || \
    die "DXMT winemetal.so missing: $WINE_INSTALL/lib/dxmt/x86_64-unix"
fi

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
gptk_host=""
if [[ "$GRAPHICS_BACKEND" == d3dmetal ]]; then
  gptk_host="$GPTK_ROOT/external/libd3dshared.dylib"
fi
timestamp="$(date '+%Y%m%d-%H%M%S')"
log_file="$LOG_ROOT/maplestory-cx26-$GRAPHICS_BACKEND-$timestamp-$$.log"
redacted_args='(none --no-otp)'
if [[ "$NO_OTP" -eq 0 ]]; then
  redacted_args="${game_args[0]} ${game_args[1]} ${game_args[2]} ${game_args[3]} <OTP-redacted>"
fi

export WINEPREFIX="$WINEPREFIX_PATH"
export WINELOADER="$wine_bin"
export WINESERVER="$wineserver_bin"
export LANG=zh_TW.UTF-8 LC_ALL=zh_TW.UTF-8 LC_CTYPE=zh_TW.UTF-8
export RAW_AUDIO_PARSE=1
export CYDER_GRAPHICS_BACKEND="$GRAPHICS_BACKEND"
export CX_GRAPHICS_BACKEND="$GRAPHICS_BACKEND"
export CYDER_GRAPHICS_BACKENDS_ROOT="$WINE_INSTALL"
export CYDER_COMPATDB_PATH="$COMPATDB_PATH"
export CYDER_MSYNC="${CYDER_MSYNC:-1}"
export CYDER_ESYNC="${CYDER_ESYNC:-0}"
export CYDER_WINE_DIAGNOSTICS="${CYDER_WINE_DIAGNOSTICS:-quiet}"
export MTL_HUD_ENABLED="${MTL_HUD_ENABLED:-1}"
export CYDER_MAPLESTORY_PREWARM="${CYDER_MAPLESTORY_PREWARM:-0}"
export CYDER_MAPLESTORY_PREWARM_MAX_BYTES="${CYDER_MAPLESTORY_PREWARM_MAX_BYTES:-268435456}"
export CYDER_MAPLESTORY_PREWARM_PROFILE="${CYDER_MAPLESTORY_PREWARM_PROFILE:-h1}"
export CYDER_MAPLESTORY_FILE_CACHE="${CYDER_MAPLESTORY_FILE_CACHE:-0}"
export CYDER_MAPLESTORY_FILE_CACHE_MMAP="${CYDER_MAPLESTORY_FILE_CACHE_MMAP:-0}"
export CYDER_MAPLESTORY_FILE_CACHE_PREWARM_IN_PROCESS="${CYDER_MAPLESTORY_FILE_CACHE_PREWARM_IN_PROCESS:-0}"
export CYDER_MAPLESTORY_FILE_CACHE_PREWARM_MAX_BYTES="${CYDER_MAPLESTORY_FILE_CACHE_PREWARM_MAX_BYTES:-33554432}"
export CYDER_MAPLESTORY_FILE_CACHE_FAST_HIT="${CYDER_MAPLESTORY_FILE_CACHE_FAST_HIT:-0}"
export CYDER_MAPLESTORY_IO_CACHE_TIMING="${CYDER_MAPLESTORY_IO_CACHE_TIMING:-0}"
export CYDER_MAPLESTORY_IO_TRACE="${CYDER_MAPLESTORY_IO_TRACE:-0}"
export CYDER_MAPLESTORY_IO_PROFILE="${CYDER_MAPLESTORY_IO_PROFILE:-0}"
export CYDER_MAPLESTORY_IO_PROFILE_TIMING="${CYDER_MAPLESTORY_IO_PROFILE_TIMING:-0}"
export CYDER_MAPLESTORY_IO_PROFILE_FULL_OFFSETS="${CYDER_MAPLESTORY_IO_PROFILE_FULL_OFFSETS:-0}"
export CYDER_MAPLESTORY_IO_PROFILE_SIMULATE="${CYDER_MAPLESTORY_IO_PROFILE_SIMULATE:-0}"
export CYDER_MAPLESTORY_IO_RING="${CYDER_MAPLESTORY_IO_RING:-0}"
export CYDER_MAPLESTORY_IO_RING_ARM_FILE="${CYDER_MAPLESTORY_IO_RING_ARM_FILE:-}"
export CYDER_MAPLESTORY_IO_SUMMARY="${CYDER_MAPLESTORY_IO_SUMMARY:-0}"
export CYDER_MAPLESTORY_IO_TIMELINE="${CYDER_MAPLESTORY_IO_TIMELINE:-0}"
export CYDER_MAPLESTORY_IO_CACHE_STATS="${CYDER_MAPLESTORY_IO_CACHE_STATS:-0}"
export CYDER_MAPLESTORY_IO_SECTION_MAP="${CYDER_MAPLESTORY_IO_SECTION_MAP:-0}"
export WINEDEBUG="$DEBUG_CHANNELS"
dyld_fallback="$WINE_INSTALL/lib:$WINE_INSTALL/lib/wine/x86_64-unix:$MEDIA_LIB"
if [[ "$GRAPHICS_BACKEND" == d3dmetal ]]; then
  export CYDER_GPTK_ROOT="$GPTK_ROOT"
  export CX_APPLEGPTK_LIBD3DSHARED_PATH="$gptk_host"
  dyld_fallback="$dyld_fallback:$GPTK_ROOT/external"
else
  unset CYDER_GPTK_ROOT CX_APPLEGPTK_LIBD3DSHARED_PATH || true
  dyld_fallback="$dyld_fallback:$WINE_INSTALL/lib/dxmt/x86_64-unix"
fi
export DYLD_FALLBACK_LIBRARY_PATH="$dyld_fallback${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}"
export GST_PLUGIN_SYSTEM_PATH_1_0="$GST_PLUGIN_DIR"
export GST_PLUGIN_PATH_1_0="$GST_PLUGIN_DIR"
gst_env=(
  "GST_PLUGIN_SYSTEM_PATH_1_0=$GST_PLUGIN_SYSTEM_PATH_1_0"
  "GST_PLUGIN_PATH_1_0=$GST_PLUGIN_PATH_1_0"
)
if [[ -f "$GST_SCANNER" ]]; then
  gst_env+=("GST_PLUGIN_SCANNER=$GST_SCANNER")
fi

{
  echo "CX26 MapleStory $GRAPHICS_BACKEND launch"
  echo "  WINE_INSTALL=$WINE_INSTALL"
  echo "  WINESERVER=$WINESERVER"
  echo "  WINEPREFIX=$WINEPREFIX_PATH"
  echo "  EXE=$EXE_PATH"
  echo "  GPTK_ROOT=${GPTK_ROOT:-}"
  echo "  COMPATDB_PATH=$COMPATDB_PATH"
  echo "  MEDIA_SOURCE=$MEDIA_SOURCE"
  echo "  MEDIA_INSTALL=$MEDIA_INSTALL"
  echo "  MEDIA_LIB=$MEDIA_LIB"
  echo "  GST_PLUGIN_DIR=$GST_PLUGIN_DIR"
  echo "  GST_PLUGIN_SCANNER=$GST_SCANNER"
  echo "  CYDER_GRAPHICS_BACKEND=$GRAPHICS_BACKEND"
  echo "  CYDER_MSYNC=$CYDER_MSYNC"
  echo "  CYDER_ESYNC=$CYDER_ESYNC"
  echo "  CYDER_WINE_DIAGNOSTICS=$CYDER_WINE_DIAGNOSTICS"
  echo "  MTL_HUD_ENABLED=$MTL_HUD_ENABLED"
  echo "  CYDER_MAPLESTORY_PREWARM=$CYDER_MAPLESTORY_PREWARM"
  echo "  CYDER_MAPLESTORY_PREWARM_MAX_BYTES=$CYDER_MAPLESTORY_PREWARM_MAX_BYTES"
  echo "  CYDER_MAPLESTORY_PREWARM_PROFILE=$CYDER_MAPLESTORY_PREWARM_PROFILE"
  echo "  CYDER_MAPLESTORY_FILE_CACHE=$CYDER_MAPLESTORY_FILE_CACHE"
  echo "  CYDER_MAPLESTORY_FILE_CACHE_MMAP=$CYDER_MAPLESTORY_FILE_CACHE_MMAP"
  echo "  CYDER_MAPLESTORY_FILE_CACHE_PREWARM_IN_PROCESS=$CYDER_MAPLESTORY_FILE_CACHE_PREWARM_IN_PROCESS"
  echo "  CYDER_MAPLESTORY_FILE_CACHE_PREWARM_MAX_BYTES=$CYDER_MAPLESTORY_FILE_CACHE_PREWARM_MAX_BYTES"
  echo "  CYDER_MAPLESTORY_FILE_CACHE_FAST_HIT=$CYDER_MAPLESTORY_FILE_CACHE_FAST_HIT"
  echo "  CYDER_MAPLESTORY_IO_CACHE_TIMING=$CYDER_MAPLESTORY_IO_CACHE_TIMING"
  echo "  CYDER_MAPLESTORY_IO_TRACE=$CYDER_MAPLESTORY_IO_TRACE"
  echo "  CYDER_MAPLESTORY_IO_PROFILE=$CYDER_MAPLESTORY_IO_PROFILE"
  echo "  CYDER_MAPLESTORY_IO_PROFILE_TIMING=$CYDER_MAPLESTORY_IO_PROFILE_TIMING"
  echo "  CYDER_MAPLESTORY_IO_PROFILE_FULL_OFFSETS=$CYDER_MAPLESTORY_IO_PROFILE_FULL_OFFSETS"
  echo "  CYDER_MAPLESTORY_IO_PROFILE_SIMULATE=$CYDER_MAPLESTORY_IO_PROFILE_SIMULATE"
  echo "  CYDER_MAPLESTORY_IO_RING=$CYDER_MAPLESTORY_IO_RING"
  echo "  CYDER_MAPLESTORY_IO_RING_ARM_FILE=$CYDER_MAPLESTORY_IO_RING_ARM_FILE"
  echo "  CYDER_MAPLESTORY_IO_SUMMARY=$CYDER_MAPLESTORY_IO_SUMMARY"
  echo "  CYDER_MAPLESTORY_IO_TIMELINE=$CYDER_MAPLESTORY_IO_TIMELINE"
  echo "  CYDER_MAPLESTORY_IO_CACHE_STATS=$CYDER_MAPLESTORY_IO_CACHE_STATS"
  echo "  CYDER_MAPLESTORY_IO_SECTION_MAP=$CYDER_MAPLESTORY_IO_SECTION_MAP"
  echo "  WINEDEBUG=$DEBUG_CHANNELS"
  echo "  argv=$redacted_args"
  echo "  log=$log_file"
}

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "+ cd $(dirname "$EXE_PATH")"
  if [[ "$GRAPHICS_BACKEND" == dxmt ]]; then
    echo "+ ensure_dxmt_winemetal_prefix $WINEPREFIX_PATH $WINE_INSTALL"
  fi
  if [[ "$NO_OTP" -eq 1 ]]; then
    echo "+ arch -x86_64 env ... $wine_bin $EXE_PATH"
  else
    echo "+ arch -x86_64 env ... $wine_bin $EXE_PATH ${game_args[*]}"
  fi
  if [[ "$CYDER_MAPLESTORY_PREWARM" == "1" || "$CYDER_MAPLESTORY_PREWARM" == "true" ]]; then
    echo "+ $ROOT/scripts/maplestory-prewarm.sh --game-root $(dirname "$EXE_PATH") --max-bytes $CYDER_MAPLESTORY_PREWARM_MAX_BYTES"
  fi
  exit 0
fi

mkdir -p "$LOG_ROOT" "$WINEPREFIX_PATH"
chmod 0700 "$LOG_ROOT" 2>/dev/null || true
clean_prefix_session
if [[ "$GRAPHICS_BACKEND" == dxmt ]]; then
  ensure_dxmt_winemetal_prefix "$WINEPREFIX_PATH" "$WINE_INSTALL"
fi
cd "$(dirname "$EXE_PATH")"
if [[ "$CYDER_MAPLESTORY_PREWARM" == "1" || "$CYDER_MAPLESTORY_PREWARM" == "true" ]]; then
  [[ -x "$ROOT/scripts/maplestory-prewarm.sh" ]] || \
    die "MapleStory prewarm helper missing or not executable: $ROOT/scripts/maplestory-prewarm.sh"
  "$ROOT/scripts/maplestory-prewarm.sh" \
    --game-root "$(dirname "$EXE_PATH")" \
    --max-bytes "$CYDER_MAPLESTORY_PREWARM_MAX_BYTES" \
    --profile "$CYDER_MAPLESTORY_PREWARM_PROFILE" | tee -a "$log_file"
fi

launch_env=(
  WINELOADER="$wine_bin" WINEPREFIX="$WINEPREFIX_PATH" WINEDEBUG="$DEBUG_CHANNELS"
  CYDER_GRAPHICS_BACKEND="$GRAPHICS_BACKEND" CX_GRAPHICS_BACKEND="$GRAPHICS_BACKEND"
  CYDER_GRAPHICS_BACKENDS_ROOT="$WINE_INSTALL"
  CYDER_COMPATDB_PATH="$COMPATDB_PATH"
  RAW_AUDIO_PARSE=1
  CYDER_MSYNC="$CYDER_MSYNC" CYDER_ESYNC="$CYDER_ESYNC"
  CYDER_WINE_DIAGNOSTICS="$CYDER_WINE_DIAGNOSTICS" MTL_HUD_ENABLED="$MTL_HUD_ENABLED"
  CYDER_MAPLESTORY_FILE_CACHE="$CYDER_MAPLESTORY_FILE_CACHE"
  CYDER_MAPLESTORY_FILE_CACHE_MMAP="$CYDER_MAPLESTORY_FILE_CACHE_MMAP"
  CYDER_MAPLESTORY_FILE_CACHE_PREWARM_IN_PROCESS="$CYDER_MAPLESTORY_FILE_CACHE_PREWARM_IN_PROCESS"
  CYDER_MAPLESTORY_FILE_CACHE_PREWARM_MAX_BYTES="$CYDER_MAPLESTORY_FILE_CACHE_PREWARM_MAX_BYTES"
  CYDER_MAPLESTORY_IO_TRACE="$CYDER_MAPLESTORY_IO_TRACE"
  CYDER_MAPLESTORY_IO_PROFILE="$CYDER_MAPLESTORY_IO_PROFILE"
  CYDER_MAPLESTORY_IO_PROFILE_TIMING="$CYDER_MAPLESTORY_IO_PROFILE_TIMING"
  CYDER_MAPLESTORY_IO_PROFILE_FULL_OFFSETS="$CYDER_MAPLESTORY_IO_PROFILE_FULL_OFFSETS"
  CYDER_MAPLESTORY_IO_PROFILE_SIMULATE="$CYDER_MAPLESTORY_IO_PROFILE_SIMULATE"
  CYDER_MAPLESTORY_IO_RING="$CYDER_MAPLESTORY_IO_RING"
  CYDER_MAPLESTORY_IO_RING_ARM_FILE="$CYDER_MAPLESTORY_IO_RING_ARM_FILE"
  CYDER_MAPLESTORY_IO_SUMMARY="$CYDER_MAPLESTORY_IO_SUMMARY"
  CYDER_MAPLESTORY_IO_TIMELINE="$CYDER_MAPLESTORY_IO_TIMELINE"
  CYDER_MAPLESTORY_IO_CACHE_STATS="$CYDER_MAPLESTORY_IO_CACHE_STATS"
  CYDER_MAPLESTORY_IO_SECTION_MAP="$CYDER_MAPLESTORY_IO_SECTION_MAP"
  DYLD_FALLBACK_LIBRARY_PATH="$DYLD_FALLBACK_LIBRARY_PATH"
  LANG=zh_TW.UTF-8 LC_ALL=zh_TW.UTF-8 LC_CTYPE=zh_TW.UTF-8
)
if [[ "$GRAPHICS_BACKEND" == d3dmetal ]]; then
  launch_env+=(
    CYDER_GPTK_ROOT="$GPTK_ROOT"
    CX_APPLEGPTK_LIBD3DSHARED_PATH="$gptk_host"
  )
fi

if [[ "$NO_OTP" -eq 1 ]]; then
  arch -x86_64 env \
    "${launch_env[@]}" \
    "${gst_env[@]}" \
    "$wine_bin" "$EXE_PATH" 2>&1 | tee -a "$log_file"
else
  arch -x86_64 env \
    "${launch_env[@]}" \
    "${gst_env[@]}" \
    "$wine_bin" "$EXE_PATH" "${game_args[@]}" 2>&1 | tee -a "$log_file"
fi
