#!/usr/bin/env bash
# Fetch and verify the pinned upstream MoltenVK source used by Cyder.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env-x86_64.sh
source "$SCRIPT_DIR/env-x86_64.sh"

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
  shift
fi
[[ $# -eq 0 ]] || { echo "Usage: $(basename "$0") [--dry-run]" >&2; exit 1; }

MOLTENVK_URL="${MOLTENVK_URL:-https://github.com/KhronosGroup/MoltenVK/archive/refs/tags/v${MOLTENVK_VERSION}.tar.gz}"
case "$MOLTENVK_VERSION" in
  1.4.0)
    MOLTENVK_SHA256="${MOLTENVK_SHA256:-fc74aef926ee3cd473fe260a93819c09fdc939bff669271a587e9ebaa43d4306}"
    ;;
  *)
    echo "No pinned MoltenVK SHA-256 for version $MOLTENVK_VERSION; set MOLTENVK_SHA256 explicitly." >&2
    exit 1
    ;;
esac

if [[ "$MOLTENVK_SOURCE" != "upstream" ]]; then
  [[ -d "$MOLTENVK_SRC" ]] || {
    echo "MOLTENVK_SOURCE=$MOLTENVK_SOURCE requires an existing source tree: $MOLTENVK_SRC" >&2
    exit 1
  }
  printf '%s\n' "$MOLTENVK_SRC"
  exit 0
fi

[[ "$MOLTENVK_SRC" == "$BUILD_DIR/moltenvk-$MOLTENVK_VERSION" ]] || {
  echo "upstream MoltenVK source must use the pinned path $BUILD_DIR/moltenvk-$MOLTENVK_VERSION (got $MOLTENVK_SRC)" >&2
  echo "Use MOLTENVK_SOURCE=custom for a nonstandard source path." >&2
  exit 1
}

marker="$MOLTENVK_SRC/MoltenVK/MoltenVK/API/mvk_private_api.h"
if [[ -f "$marker" ]] && rg -q '^#define[[:space:]]+MVK_VERSION_MAJOR[[:space:]]+1([[:space:]]|$)' "$marker" \
    && rg -q '^#define[[:space:]]+MVK_VERSION_MINOR[[:space:]]+4([[:space:]]|$)' "$marker" \
    && rg -q '^#define[[:space:]]+MVK_VERSION_PATCH[[:space:]]+0([[:space:]]|$)' "$marker"; then
  printf '%s\n' "$MOLTENVK_SRC"
  exit 0
fi

if (( DRY_RUN )); then
  echo "+ curl --fail --location $MOLTENVK_URL -o $BUILD_DIR/moltenvk-$MOLTENVK_VERSION.tar.gz"
  echo "+ verify SHA-256 $MOLTENVK_SHA256"
  echo "+ extract MoltenVK-$MOLTENVK_VERSION -> $MOLTENVK_SRC"
  exit 0
fi

command -v curl >/dev/null 2>&1 || { echo "curl is required to fetch MoltenVK $MOLTENVK_VERSION" >&2; exit 1; }
command -v tar >/dev/null 2>&1 || { echo "tar is required to extract MoltenVK $MOLTENVK_VERSION" >&2; exit 1; }
command -v shasum >/dev/null 2>&1 || { echo "shasum is required to verify MoltenVK $MOLTENVK_VERSION" >&2; exit 1; }

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/cyder-moltenvk-source.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
archive="$tmp_dir/moltenvk-$MOLTENVK_VERSION.tar.gz"

echo "Fetching MoltenVK $MOLTENVK_VERSION from $MOLTENVK_URL..." >&2
curl --fail --location --retry 3 --silent --show-error "$MOLTENVK_URL" -o "$archive"
printf '%s  %s\n' "$MOLTENVK_SHA256" "$archive" | shasum -a 256 -c -

mkdir -p "$BUILD_DIR"
tar -xzf "$archive" -C "$tmp_dir"
extracted="$tmp_dir/MoltenVK-$MOLTENVK_VERSION"
[[ -f "$extracted/MoltenVK/MoltenVK/API/mvk_private_api.h" ]] || {
  echo "MoltenVK archive has an unexpected layout: $extracted" >&2
  exit 1
}
if [[ -e "$MOLTENVK_SRC" ]]; then
  echo "Refusing to replace non-MoltenVK path: $MOLTENVK_SRC" >&2
  exit 1
fi
mv "$extracted" "$MOLTENVK_SRC"
printf '%s\n' "$MOLTENVK_SRC"
