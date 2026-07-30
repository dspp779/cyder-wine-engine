#!/usr/bin/env bash
set -euo pipefail

ENGINE_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_PROJECT_ROOT="$(cd "$ENGINE_COMMON_DIR/.." && pwd)"

cyder_engine_artifacts_dir() {
  printf '%s\n' "${CYDER_ENGINE_ARTIFACTS_DIR:-$ENGINE_PROJECT_ROOT/dist/artifacts}"
}

cyder_crossover_version() {
  printf '%s\n' "${CYDER_CROSSOVER_VERSION:-26.3.0}"
}

cyder_engine_version_label_trim() {
  local ver="$1"
  ver="${ver//$'\r'/}"
  ver="${ver#"${ver%%[![:space:]]*}"}"
  ver="${ver%"${ver##*[![:space:]]}"}"
  printf '%s\n' "$ver"
}

cyder_format_engine_version_from_wine() {
  local wine_bin="${1:-}"
  local wine_raw wine_ver cx_ver
  if [[ -n "${CYDER_ENGINE_VERSION_LABEL:-}" ]]; then
    cyder_engine_version_label_trim "$CYDER_ENGINE_VERSION_LABEL"
    return 0
  fi
  if [[ -z "$wine_bin" && -n "${WINE_INSTALL:-}" ]]; then
    wine_bin="$WINE_INSTALL/bin/wine"
  fi
  [[ -x "$wine_bin" ]] || return 1
  wine_raw="$(arch -x86_64 "$wine_bin" --version 2>/dev/null || true)"
  wine_ver="${wine_raw#wine-}"
  cx_ver="$(cyder_crossover_version)"
  printf 'wine crossover %s (wine %s)\n' "$cx_ver" "$wine_ver"
}

cyder_detect_engine_version_label() {
  cyder_format_engine_version_from_wine "${1:-}"
}

cyder_engine_version_slug_from_label() {
  local label="$1"
  local slug cx wine_ver tail
  label="$(cyder_engine_version_label_trim "$label")"
  if [[ "$label" == wine\ crossover\ * ]]; then
    cx="${label#wine crossover }"
    cx="${cx%% (wine *)}"
    wine_ver="${label#* (wine }"
    wine_ver="${wine_ver%)}"
    slug="crossover-${cx}-wine-${wine_ver}"
    slug="${slug// /-}"
    printf '%s\n' "$slug"
    return 0
  fi
  if [[ "$label" == wine\ sikarugir\ * || "$label" == wine\ Sikarugir\ * ]]; then
    tail="${label#wine sikarugir }"
    if [[ "$tail" == "$label" ]]; then
      tail="${label#wine Sikarugir }"
    fi
    slug="sikarugir-${tail}"
    slug="$(printf '%s' "$slug" | tr ' .()/' '-' | tr -s '-')"
    slug="${slug#-}"
    slug="${slug%-}"
    printf '%s\n' "$slug"
    return 0
  fi
  slug="$label"
  slug="$(printf '%s' "$slug" | tr ' .()/' '-' | tr -s '-')"
  slug="${slug#-}"
  slug="${slug%-}"
  printf '%s\n' "$slug"
}

cyder_engine_versions_equal() {
  local left right left_slug right_slug
  left="$(cyder_engine_version_label_trim "${1:-}")"
  right="$(cyder_engine_version_label_trim "${2:-}")"
  [[ -n "$left" && -n "$right" ]] || return 1
  [[ "$left" == "$right" ]] && return 0
  left_slug="$(cyder_engine_version_slug_from_label "$left")"
  right_slug="$(cyder_engine_version_slug_from_label "$right")"
  [[ "$left_slug" == "$right" || "$left" == "$right_slug" || "$left_slug" == "$right_slug" ]]
}

cyder_read_engine_version_file() {
  local engine_root="$1"
  local ver
  [[ -f "$engine_root/version" ]] || return 1
  ver="$(cyder_engine_version_label_trim "$(cat "$engine_root/version")")"
  [[ -n "$ver" ]] || return 1
  printf '%s\n' "$ver"
}

cyder_write_engine_version_file() {
  local engine_root="$1"
  local ver="$2"
  ver="$(cyder_engine_version_label_trim "$ver")"
  [[ -n "$ver" ]] || return 1
  printf '%s\n' "$ver" >"$engine_root/version"
}

cyder_engine_version_from_tarball() {
  local tarball="$1"
  local ver
  ver="$(tar -xOf "$tarball" wine-x86_64/version 2>/dev/null | head -1 || true)"
  ver="$(cyder_engine_version_label_trim "$ver")"
  [[ -n "$ver" ]] || return 1
  printf '%s\n' "$ver"
}

cyder_engine_archive_path_for_format() {
  local ver="$1"
  local dir="${2:-$(cyder_engine_artifacts_dir)}"
  local format="${3:-xz}"
  case "$format" in
    zst | zstd) printf '%s/engine-%s.tar.zst\n' "$dir" "$ver" ;;
    xz) printf '%s/engine-wine-x86_64-%s.tar.xz\n' "$dir" "$ver" ;;
    *)
      echo "Unknown engine archive format: $format" >&2
      return 1
      ;;
  esac
}

cyder_find_zstd() {
  local candidate
  for candidate in \
    "${CYDER_ZSTD:-}" \
    "$ENGINE_PROJECT_ROOT/tools/zstd/zstd" \
    "$(command -v zstd 2>/dev/null || true)"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      printf '%s/%s\n' "$(cd "$(dirname "$candidate")" && pwd -P)" "$(basename "$candidate")"
      return 0
    fi
  done
  return 1
}
