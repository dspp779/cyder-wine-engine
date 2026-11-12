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
CANDIDATE=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [--engine PATH] [--output-dir PATH] [--force]

Package ENGINE/lib/dxvk and lib/dxmt as independent zstd graphics payloads.
DXVK 2 (lib/dxvk2) is not a supported Cyder payload until it passes game
testing; it is never packed, even when present in the engine tree. --channel release requires a Developer ID SIGN_IDENTITY. DXMT keeps the upstream
version (dxmt-0.80.tar.zst); Cyder only adds a Developer ID signature to
winemetal.so in staging, verifies it after the archive round-trip, and reuses an
existing verified archive unchanged. It is re-signed only when the upstream
source or signing policy changes (move the old archive aside first).
Archives and version/checksum sidecars are written to
dist/artifacts/graphics by default.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --engine) ENGINE="${2:?Missing value for --engine}"; shift 2 ;;
    --output-dir) OUTPUT_DIR="${2:?Missing value for --output-dir}"; shift 2 ;;
    --channel) CHANNEL="${2:?Missing channel}"; shift 2 ;;
    --revision) echo "--revision is retired: DXMT is packaged under its upstream version" >&2; exit 1 ;;
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
  [[ "${SIGN_IDENTITY:-}" == 'Developer ID Application: '* ]] || {
    echo "Release graphics require a Developer ID Application SIGN_IDENTITY" >&2; exit 1;
  }
fi

cyder_graphics_require_realpath_dir "$ENGINE/lib/dxvk" "DXVK"
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

dxmt_archive_is_signed_release() {
  local listing
  listing="$("$ZSTD_BIN" -dc "$1" | tar -tf -)" || return 1
  grep -q '^dxmt/cyder-graphics-provenance.json$' <<<"$listing"
}

pack_payload() {
  local name="$1" source="$2" version archive version_file checksum_file staged
  version="$(payload_version "$name" "$source")"
  if [[ "$name" == dxmt && "$CHANNEL" == release ]]; then
    [[ "$version" == 0.80 ]] || { echo "Unreviewed DXMT version" >&2; return 1; }
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
            echo "Existing signed archive checksum changed; move it aside to re-sign" >&2; return 1;
          }
        fi
      fi
      python3 "$SCRIPT_DIR/graphics-signing.py" verify-archive --archive "$archive" --zstd "$ZSTD_BIN" \
        --package-version "$version" --source-root "$source" || {
        echo "Existing $archive is not a verified signed release of the current upstream DXMT" >&2
        echo "(legacy unsigned, changed source, or changed signing policy); move it aside to re-sign." >&2
        return 1
      }
      echo "Reusing signed graphics artifact: $archive"
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
  elif [[ "$name" == dxmt && -f "$archive" ]] && dxmt_archive_is_signed_release "$archive"; then
    # A test pack must never replace (or claim) a signed release archive.
    [[ "$FORCE" -ne 1 ]] || { echo "Refusing to overwrite signed release archive $archive in the test channel" >&2; return 1; }
    echo "Graphics artifact present (signed release): $archive"
  elif [[ -f "$archive" && "$FORCE" -ne 1 ]]; then
    echo "Graphics artifact present: $archive"
  else
    rm -rf "$staged"
    # zstd reads the staged tar stream from stdin and refuses to overwrite an
    # existing output path.  --force must therefore remove the exact payload
    # archive before starting the replacement.
    rm -f "$archive"
    cp -R "$source" "$staged"
    if [[ "$name" == dxvk ]]; then
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

if [[ -e "$ENGINE/lib/dxvk2" ]]; then
  echo "Skipping unsupported DXVK 2 payload: $ENGINE/lib/dxvk2 (not shipped until game-tested)" >&2
fi

pack_payload dxvk "$ENGINE/lib/dxvk"
pack_payload dxmt "$ENGINE/lib/dxmt"
