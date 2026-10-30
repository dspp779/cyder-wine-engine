#!/usr/bin/env bash
# Pack DXVK and DXMT independently from the Wine engine archive.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/engine-common.sh"
source "$SCRIPT_DIR/env-x86_64.sh"

ENGINE="${WINE_INSTALL:-}"
OUTPUT_DIR=""
FORCE=0
CHANNEL="${CYDER_GRAPHICS_CHANNEL:-test}"
REVISION="${CYDER_GRAPHICS_PACKAGE_REVISION:-}"
CANDIDATE=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [--engine PATH] [--output-dir PATH] [--force]

Package ENGINE/lib/dxvk, lib/dxvk2, and lib/dxmt as independent zstd graphics
payloads. --channel release requires SIGN_IDENTITY and --revision cyder.N;
DXMT is signed only in staging, verified after archive round-trip, and immutable.
Archives and version/checksum sidecars are written to
dist/artifacts/graphics by default.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --engine) ENGINE="${2:?Missing value for --engine}"; shift 2 ;;
    --output-dir) OUTPUT_DIR="${2:?Missing value for --output-dir}"; shift 2 ;;
    --channel) CHANNEL="${2:?Missing channel}"; shift 2 ;;
    --revision) REVISION="${2:?Missing revision}"; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

cyder_graphics_require_realpath_dir() {
  local path="$1" label="$2"
  [[ -d "$path" ]] || { echo "Missing $label: $path" >&2; return 1; }
  if [[ -L "$path" ]]; then
    echo "Refusing symlinked $label source: $path (copy a real tree; symlink packs become stub archives)" >&2
    return 1
  fi
}

[[ "$CHANNEL" == test || "$CHANNEL" == release ]] || { echo "Invalid graphics channel" >&2; exit 1; }
if [[ "$CHANNEL" == release ]]; then
  [[ "${SIGN_IDENTITY:-}" == 'Developer ID Application: '* && "$REVISION" =~ ^cyder\.[1-9][0-9]*$ ]] || {
    echo "Release graphics require Developer ID Application and a new --revision cyder.N" >&2; exit 1;
  }
fi

cyder_graphics_require_realpath_dir "$ENGINE/lib/dxvk" "DXVK"
cyder_graphics_require_realpath_dir "$ENGINE/lib/dxvk2" "DXVK2"
cyder_graphics_require_realpath_dir "$ENGINE/lib/dxmt" "DXMT"
ZSTD_BIN="$(cyder_find_zstd 2>/dev/null || true)"
[[ -x "$ZSTD_BIN" ]] || { echo "Missing bundled zstd" >&2; exit 1; }
[[ -n "$OUTPUT_DIR" ]] || OUTPUT_DIR="$(cyder_engine_artifacts_dir)/graphics"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd -P)"

payload_version() {
  local name="$1" dir="$2" version_file version="" env_name name_upper
  version_file="$dir/version"
  name_upper="$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')"
  env_name="CYDER_${name_upper}_VERSION"
  if [[ -n "${!env_name:-}" ]]; then
    version="${!env_name}"
  elif [[ -f "$version_file" ]]; then
    version="$(awk 'NR == 1 { print $2; exit }' "$version_file")"
    [[ -n "$version" ]] || version="$(head -n 1 "$version_file")"
  fi
  version="${version#v}"
  version="${version//[^A-Za-z0-9._-]/-}"
  printf '%s\n' "${version:-unknown}"
}

STAGING="$(mktemp -d "${TMPDIR:-/tmp}/cyder-graphics-pack.XXXXXX")"
trap 'rm -rf "$STAGING"; [[ -z "$CANDIDATE" ]] || rm -f "$CANDIDATE"' EXIT

pack_payload() {
  local name="$1" source="$2" version archive version_file checksum_file staged
  version="$(payload_version "$name" "$source")"
  if [[ "$name" == dxmt && "$CHANNEL" == release ]]; then
    [[ "$version" == 0.80 ]] || { echo "Unreviewed DXMT version" >&2; return 1; }
    version="$version-$REVISION"
  fi
  if [[ "$name" == dxmt && "$CHANNEL" != release && "$version" == *-cyder.* ]]; then
    echo "Cyder package revisions are reserved for release graphics" >&2; return 1
  fi
  archive="$OUTPUT_DIR/$name-$version.tar.zst"
  version_file="$OUTPUT_DIR/$name-version.txt"
  checksum_file="$OUTPUT_DIR/$name-artifact-sha256.txt"
  staged="$STAGING/$name"
  if [[ "$name" == dxmt && "$CHANNEL" == release ]]; then
    if [[ -e "$archive" ]]; then
      # Even --force never overwrites an already published release revision.
      if [[ -f "$checksum_file" ]]; then
        local recorded_digest recorded_name
        read -r recorded_digest recorded_name <"$checksum_file"
        if [[ "$recorded_name" == "$(basename "$archive")" ]]; then
          [[ "$recorded_digest" == "$(shasum -a 256 "$archive" | awk '{print $1}')" ]] || {
            echo "Existing signed archive checksum changed; use a new revision" >&2; return 1;
          }
        fi
      fi
      python3 "$SCRIPT_DIR/graphics-signing.py" verify-archive --archive "$archive" --zstd "$ZSTD_BIN" \
        --package-version "$version" --source-root "$source"
    else
      rm -rf "$staged"
      cp -R "$source" "$staged"
      python3 "$SCRIPT_DIR/graphics-signing.py" prepare --root "$staged" \
        --package-version "$version" --identity "$SIGN_IDENTITY"
      CANDIDATE="$(mktemp "$OUTPUT_DIR/.dxmt-candidate.XXXXXX")"
      rm -f "$CANDIDATE"
      (cd "$STAGING"; COPYFILE_DISABLE=1 tar -cf - dxmt | "$ZSTD_BIN" -22 --ultra -T0 -o "$CANDIDATE")
      python3 "$SCRIPT_DIR/graphics-signing.py" verify-archive --archive "$CANDIDATE" --zstd "$ZSTD_BIN" \
        --package-version "$version" --source-root "$source"
      local candidate_size candidate_min
      candidate_size="$(stat -f%z "$CANDIDATE" 2>/dev/null || stat -c%s "$CANDIDATE")"
      candidate_min="${CYDER_GRAPHICS_ARCHIVE_MIN_BYTES:-1024}"
      (( candidate_size >= candidate_min )) || { echo "Refusing undersized signed DXMT candidate" >&2; return 1; }
      ln "$CANDIDATE" "$archive" # atomic no-clobber publish on this filesystem
      rm -f "$CANDIDATE"
      CANDIDATE=""
    fi
  elif [[ -f "$archive" && "$FORCE" -ne 1 ]]; then
    echo "Graphics artifact present: $archive"
  else
    rm -rf "$staged"
    # zstd reads the staged tar stream from stdin and refuses to overwrite an
    # existing output path.  --force must therefore remove the exact payload
    # archive before starting the replacement.
    rm -f "$archive"
    cp -R "$source" "$staged"
    if [[ "$name" == dxvk || "$name" == dxvk2 ]]; then
      python3 "$SCRIPT_DIR/stamp-wine-builtin-pe.py" "$staged"
    fi
    (
      cd "$STAGING"
      tar -cf - "$name" | "$ZSTD_BIN" -22 --ultra -T0 -o "$archive"
    )
  fi
  local min_bytes="${CYDER_GRAPHICS_ARCHIVE_MIN_BYTES:-1024}"
  local sz
  sz="$(stat -f%z "$archive" 2>/dev/null || stat -c%s "$archive")"
  if (( sz < min_bytes )); then
    echo "Refusing undersized graphics archive $archive ($sz bytes < $min_bytes)" >&2
    return 1
  fi
  local pointer
  pointer="$(mktemp "$OUTPUT_DIR/.graphics-pointer.XXXXXX")"
  printf '%s  %s\n' "$(shasum -a 256 "$archive" | awk '{print $1}')" "$(basename "$archive")" >"$pointer"
  mv -f "$pointer" "$checksum_file"
  pointer="$(mktemp "$OUTPUT_DIR/.graphics-pointer.XXXXXX")"
  printf '%s\n' "$version" >"$pointer"
  mv -f "$pointer" "$version_file"
  echo "Created graphics artifact: $archive"
}

pack_payload dxvk "$ENGINE/lib/dxvk"
pack_payload dxvk2 "$ENGINE/lib/dxvk2"
pack_payload dxmt "$ENGINE/lib/dxmt"
