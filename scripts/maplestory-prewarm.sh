#!/usr/bin/env bash
# Low-priority host page-cache prewarm for the MapleStory first-use hitch A/B.
# This intentionally warms selected byte ranges only; it does not populate the
# Wine userspace WZ cache and is not a product default.
set -euo pipefail

BLOCK_SIZE=4096
GAME_ROOT=""
MAX_BYTES="${CYDER_MAPLESTORY_PREWARM_MAX_BYTES:-268435456}"

usage() {
  cat <<EOF
Usage: $(basename "$0") --game-root PATH [--max-bytes BYTES]

Read the selected WZ/resource ranges into the host filesystem cache before
Wine starts. Missing files are skipped so this remains safe across data packs.
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

# These ranges come from the latest arm-scoped aggregate run:
#   Mob/_Canvas/_Canvas_079.wz  -> first attack spike
#   Effect_000.wz + Skill_00002/03/07.ms -> first passive/effect spike
# The broad Sound_029.wz range is intentionally excluded because it spans
# hundreds of MiB and is not needed for this focused first-use A/B.
warm_range 'Data/Mob/_Canvas/_Canvas_079.wz' 92150703 65536 attack-mob-canvas
warm_range 'Data/Effect/Effect_000.wz' 44087678 16777216 passive-effect
warm_range 'Data/Packs/Skill_00007.ms' 840704 43334656 passive-skill-00007
warm_range 'Data/Packs/Skill_00002.ms' 4096 71179264 passive-skill-00002
warm_range 'Data/Packs/Skill_00003.ms' 5120 36268032 passive-skill-00003

report "summary ranges=$range_count bytes=$total_bytes skipped=$skipped_count max_bytes=$MAX_BYTES"
