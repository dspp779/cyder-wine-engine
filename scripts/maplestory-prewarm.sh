#!/usr/bin/env bash
# Low-priority host page-cache prewarm for the MapleStory first-use hitch A/B.
# This intentionally warms selected byte ranges only; it does not populate the
# Wine userspace WZ cache and is not a product default.
set -euo pipefail

BLOCK_SIZE=4096
GAME_ROOT=""
MAX_BYTES="${CYDER_MAPLESTORY_PREWARM_MAX_BYTES:-268435456}"
PROFILE="${CYDER_MAPLESTORY_PREWARM_PROFILE:-h1}"

usage() {
  cat <<EOF
Usage: $(basename "$0") --game-root PATH [--max-bytes BYTES] [--profile NAME]

Read the selected WZ/resource ranges into the host filesystem cache before
Wine starts. Missing files are skipped so this remains safe across data packs.

Profiles:
  h1              Default hit-path list (Effect + Mob + Morph)
  effect-io-a     IO-A verify: Effect_000 + _Canvas_003/053 only
EOF
}

die() { printf 'maplestory-prewarm: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --game-root)
      [[ $# -ge 2 ]] || die '--game-root requires PATH'
      GAME_ROOT="$2"
      shift
      ;;
    --max-bytes)
      [[ $# -ge 2 ]] || die '--max-bytes requires BYTES'
      MAX_BYTES="$2"
      shift
      ;;
    --profile)
      [[ $# -ge 2 ]] || die '--profile requires NAME'
      PROFILE="$2"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

[[ -n "$GAME_ROOT" ]] || die '--game-root is required'
[[ -d "$GAME_ROOT" ]] || die "game root missing: $GAME_ROOT"
[[ "$MAX_BYTES" =~ ^[0-9]+$ ]] || die "max bytes must be an integer: $MAX_BYTES"

total_bytes=0
range_count=0
skipped_count=0

report() {
  printf 'CYDER_PREWARM %s\n' "$*"
}

warm_range() {
  local relative_path="$1"
  local requested_offset="$2"
  local requested_length="$3"
  local reason="$4"
  local path file_size aligned_offset aligned_end block_count actual_length

  path="$GAME_ROOT/$relative_path"
  if [[ ! -f "$path" ]]; then
    skipped_count=$((skipped_count + 1))
    report "skip path=$relative_path reason=missing"
    return 0
  fi

  file_size="$(stat -f '%z' "$path")"
  aligned_offset=$((requested_offset / BLOCK_SIZE * BLOCK_SIZE))
  aligned_end=$(((requested_offset + requested_length + BLOCK_SIZE - 1) / BLOCK_SIZE * BLOCK_SIZE))
  if (( aligned_end > file_size )); then
    aligned_end="$file_size"
  fi
  if (( aligned_offset >= aligned_end )); then
    skipped_count=$((skipped_count + 1))
    report "skip path=$relative_path reason=empty"
    return 0
  fi

  actual_length=$((aligned_end - aligned_offset))
  if (( total_bytes + actual_length > MAX_BYTES )); then
    skipped_count=$((skipped_count + 1))
    report "skip path=$relative_path offset=$aligned_offset length=$actual_length reason=budget"
    return 0
  fi

  block_count=$((actual_length / BLOCK_SIZE))
  report "start path=$relative_path offset=$aligned_offset length=$actual_length reason=$reason"
  # macOS nice(1) and dd(1) are available in the test environment. Suppress
  # dd's progress/error chatter; the aggregate below is what the experiment
  # needs and avoids adding log I/O during the game run.
  nice -n 20 dd if="$path" of=/dev/null bs="$BLOCK_SIZE" skip="$((aligned_offset / BLOCK_SIZE))" count="$block_count" 2>/dev/null
  total_bytes=$((total_bytes + actual_length))
  range_count=$((range_count + 1))
  report "done path=$relative_path offset=$aligned_offset length=$actual_length"
}

# This only warms the host page cache. It does not fill Wine userspace WZ
# cache and is not a product default (launcher: CYDER_MAPLESTORY_PREWARM=1).
report "profile=$PROFILE"

case "$PROFILE" in
  h1)
    # Hit-path host prewarm ranges from H1 capture #2
    # (2026-09-04, arm + first mob hit, feel=小卡).
    warm_range 'Data/Effect/Effect_000.wz' 0 61727143 h1-effect-index
    warm_range 'Data/Effect/_Canvas/_Canvas_003.wz' 0 33554432 h1-effect-canvas-003
    warm_range 'Data/Effect/_Canvas/_Canvas_053.wz' 0 10485760 h1-effect-canvas-053
    warm_range 'Data/Effect/_Canvas/_Canvas_041.wz' 0 4194304 h1-effect-canvas-041
    warm_range 'Data/Effect/_Canvas/_Canvas_052.wz' 0 1048576 h1-effect-canvas-052
    warm_range 'Data/Mob/_Canvas/_Canvas_001.wz' 0 1048576 h1-mob-canvas-001
    warm_range 'Data/Mob/_Canvas/_Canvas_000.wz' 0 1048576 h1-mob-canvas-000
    warm_range 'Data/Mob/_Canvas/_Canvas_075.wz' 0 1048576 h1-mob-canvas-075
    warm_range 'Data/Mob/_Canvas/_Canvas_071.wz' 0 1048576 h1-mob-canvas-071
    warm_range 'Data/Mob/_Canvas/_Canvas_079.wz' 0 1048576 h1-mob-canvas-079-prefix
    warm_range 'Data/Mob/_Canvas/_Canvas_079.wz' 92150703 1048576 h1-mob-canvas-079-mid
    warm_range 'Data/Morph/Morph_000.wz' 0 1611186 h1-morph
    ;;
  effect-io-a)
    # IO-A exit summary: hottest Effect paths among hit-related files.
    # Verify whether warming only these reduces first-hit hitch vs IO-A (小卡).
    warm_range 'Data/Effect/Effect_000.wz' 0 61727143 io-a-effect-index
    warm_range 'Data/Effect/_Canvas/_Canvas_003.wz' 0 33554432 io-a-effect-canvas-003
    warm_range 'Data/Effect/_Canvas/_Canvas_053.wz' 0 10485760 io-a-effect-canvas-053
    ;;
  *)
    die "unknown profile: $PROFILE (expected h1 or effect-io-a)"
    ;;
esac

report "summary profile=$PROFILE ranges=$range_count bytes=$total_bytes skipped=$skipped_count max_bytes=$MAX_BYTES"
