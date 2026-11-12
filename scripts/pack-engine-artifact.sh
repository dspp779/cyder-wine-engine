#!/usr/bin/env bash
# Build reusable Wine engine artifact (strip + compressed tar) for Cyder / CyderBits apps.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=engine-common.sh
source "$SCRIPT_DIR/engine-common.sh"
MEDIA_PROFILE="${CYDER_ENGINE_MEDIA_PROFILE:-full-video}"
MEDIA_INSTALL_WAS_EXPLICIT="${MEDIA_INSTALL+x}"
source "$SCRIPT_DIR/env-x86_64.sh"

FORCE=0
DRY_RUN=0
FORMAT="${CYDER_ENGINE_FORMAT:-xz}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --format)
      FORMAT="${2:-}"
      if [[ -z "$FORMAT" ]]; then
        echo "Missing value for --format" >&2
        exit 1
      fi
      shift 2
      ;;
    --zst | --zstd)
      FORMAT="zst"
      shift
      ;;
    --xz)
      FORMAT="xz"
      shift
      ;;
    --media-profile)
      MEDIA_PROFILE="${2:-}"
      if [[ -z "$MEDIA_PROFILE" ]]; then
        echo "Missing value for --media-profile" >&2
        exit 1
      fi
      shift 2
      ;;
    -h | --help)
      cat <<EOF
Usage: $(basename "$0") [--force] [--dry-run] [--zstd] [--format zstd|xz]
       [--media-profile full-video|minimal]

Build a compressed engine artifact from install/wine-cx26-x86_64 (or WINE_INSTALL).
  xz:   dist/artifacts/engine-wine-x86_64-<CX26-winever>.tar.xz (default, xz -9e)
  zstd: dist/artifacts/engine-<CX26-winever>.tar.zst (--zstd)
The default label comes from config/engine-version.txt.
Set CYDER_ENGINE_VERSION_LABEL to override it for an explicit candidate pack.
Set CYDER_ENGINE_FORMAT=zstd or pass --zstd to build with zstd -22 --ultra.
PE Authenticode is optional: CYDER_PE_SIGNING=off (default), or required to
sign reviewed PE and enforce the independent Authenticode release gate.
Apple Developer ID signing remains controlled by SIGN_IDENTITY.
The default media profile is full-video; use --media-profile minimal only for
an explicitly reduced/non-video engine build.
EOF
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

case "$FORMAT" in
  zstd) FORMAT="zst" ;;
esac

case "$MEDIA_PROFILE" in
  full-video)
    if [[ -z "$MEDIA_INSTALL_WAS_EXPLICIT" ]]; then
      MEDIA_INSTALL="$OGOM/install/media-cx${CX_VERSION}-full-video-x86_64"
    fi
    [[ -d "$MEDIA_INSTALL/lib/gstreamer-1.0" ]] || {
      echo "Missing full-video GStreamer plugins at $MEDIA_INSTALL" >&2
      echo "Build them with: bash scripts/build-media-stack.sh --cx $CX_VERSION --full-video" >&2
      exit 1
    }
    [[ -x "$MEDIA_INSTALL/libexec/gstreamer-1.0/gst-plugin-scanner" ]] || {
      echo "Missing full-video GStreamer plugin scanner at $MEDIA_INSTALL" >&2
      echo "Rebuild the media stack with: bash scripts/build-media-stack.sh --cx $CX_VERSION --full-video" >&2
      exit 1
    }
    ;;
  minimal)
    if [[ -z "$MEDIA_INSTALL_WAS_EXPLICIT" ]]; then
      MEDIA_INSTALL="$OGOM/install/media-cx${CX_VERSION}-x86_64"
    fi
    ;;
  *)
    echo "Unknown media profile: $MEDIA_PROFILE (expected full-video or minimal)" >&2
    exit 1
    ;;
esac
export MEDIA_INSTALL

case "$FORMAT" in
  zst | xz) ;;
  *)
    echo "Unknown format: $FORMAT (expected zstd or xz)" >&2
    exit 1
    ;;
esac

[[ -x "$WINE_INSTALL/bin/wine" ]] || {
  echo "Missing Wine at $WINE_INSTALL — build it first." >&2
  exit 1
}
CXCOMPATDB="$WINE_INSTALL/lib/wine/x86_64-unix/cxcompatdb.so"
[[ -f "$CXCOMPATDB" ]] || {
  echo "Missing Cyder cxcompatdb at $CXCOMPATDB — run scripts/build-cyder-cxcompatdb.sh." >&2
  exit 1
}
if [[ "$FORMAT" == "zst" ]]; then
  ZSTD_BIN="$(cyder_find_zstd 2>/dev/null || true)"
  [[ -x "$ZSTD_BIN" ]] || {
    echo "Missing zstd — rebuild the bundled tool with scripts/build-universal-zstd.sh" >&2
    exit 1
  }
else
  command -v xz >/dev/null 2>&1 || {
    echo "Missing xz — install with: brew install xz" >&2
    exit 1
  }
fi

ENGINE_VERSION_LABEL="${CYDER_ENGINE_VERSION_LABEL:-}"
if [[ -z "$ENGINE_VERSION_LABEL" ]]; then
  ENGINE_VERSION_LABEL="$(head -n 1 "$OGOM/config/engine-version.txt" 2>/dev/null || true)"
fi
if [[ -z "$ENGINE_VERSION_LABEL" ]]; then
  ENGINE_VERSION_LABEL="$(cyder_detect_engine_version_label "$WINE_INSTALL/bin/wine")" || {
    echo "Could not detect engine version from config or wine --version" >&2
    exit 1
  }
fi
ENGINE_VERSION_SLUG="$(cyder_engine_version_slug_from_label "$ENGINE_VERSION_LABEL")"
ENGINE_VERSION="$ENGINE_VERSION_SLUG"
ARTIFACTS_DIR="$(cyder_engine_artifacts_dir)"
ARCHIVE="$(cyder_engine_archive_path_for_format "$ENGINE_VERSION" "$ARTIFACTS_DIR" "$FORMAT")"
VERSION_FILE="$ARTIFACTS_DIR/engine-version.txt"
STAMP_FILE="$ARTIFACTS_DIR/.pack-stamp"

# PE Authenticode is an explicit opt-in, independent of Apple Developer ID.
PE_SIGNING_ENABLED=0
PE_PROVENANCE_SHA256=""
case "${CYDER_PE_SIGNING:-off}" in
  off) ;;
  required) PE_SIGNING_ENABLED=1 ;;
  *) echo "Invalid CYDER_PE_SIGNING (expected off or required)" >&2; exit 1 ;;
esac
if [[ "$PE_SIGNING_ENABLED" -eq 1 ]]; then
  : "${CYDER_PE_SIGNING_POLICY:?Set a reviewed PE signing policy when CYDER_PE_SIGNING=required}"
  python3 "$SCRIPT_DIR/pe-signing.py" preflight --policy "$CYDER_PE_SIGNING_POLICY"
  if [[ -e "$ARCHIVE" && "$DRY_RUN" -ne 1 ]]; then
    echo "Refusing to reuse/overwrite a PE-signed engine archive; choose a new engine version label." >&2
    exit 1
  fi
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "DRY RUN: would pack separate DXVK/DXMT graphics payloads"
else
  graphics_pack_args=(--engine "$WINE_INSTALL")
  if [[ "${SIGN_IDENTITY:-}" == 'Developer ID Application: '* ]]; then
    graphics_pack_args+=(--channel release --revision "${CYDER_GRAPHICS_PACKAGE_REVISION:?Set a new graphics revision cyder.N}")
  fi
  if [[ "$FORCE" -eq 1 ]]; then
    graphics_pack_args+=(--force)
  fi
  bash "$SCRIPT_DIR/pack-graphics-payloads.sh" "${graphics_pack_args[@]}"
fi

if [[ -f "$ARCHIVE" && "$FORCE" -ne 1 ]]; then
  echo "Engine artifact present: $ARCHIVE"
  echo "Use --force to rebuild."
  exit 0
fi

# Hold one publisher per artifact, and never expose an unverified candidate
# at the final archive path (where the next invocation would reuse it as cache).
STAGING=""
CANDIDATE_ROOT=""
PACK_LOCK=""
cleanup() {
  [[ -z "$STAGING" ]] || rm -rf "$STAGING"
  [[ -z "$CANDIDATE_ROOT" ]] || rm -rf "$CANDIDATE_ROOT"
  [[ -z "$PACK_LOCK" ]] || rmdir "$PACK_LOCK" 2>/dev/null || true
}
trap cleanup EXIT
mkdir -p "$ARTIFACTS_DIR"
lock_path="${ARCHIVE}.pack-lock"
if ! mkdir "$lock_path" 2>/dev/null; then
  echo "Engine artifact is being packed, or an interrupted pack lock needs inspection: $lock_path" >&2
  exit 1
fi
PACK_LOCK="$lock_path"
# A concurrent pack may have published between our first cache check and lock.
if [[ -e "$ARCHIVE" ]]; then
  if [[ "$PE_SIGNING_ENABLED" -eq 1 ]]; then
    echo "Refusing to reuse/overwrite a PE-signed engine archive; choose a new engine version label." >&2
    exit 1
  elif [[ "$FORCE" -ne 1 ]]; then
    echo "Engine artifact present: $ARCHIVE"
    exit 0
  fi
fi
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/cyder-engine-pack.XXXXXX")"
ENGINE_TREE="$STAGING/wine-x86_64"

echo "==> Staging engine tree ($ENGINE_VERSION_LABEL)"
echo "==> Embedding GStreamer media profile $MEDIA_PROFILE from $MEDIA_INSTALL"
# Fail closed: never ship Apple GPTK inside a redistributable engine artifact.
rsync -a --delete \
  --exclude 'lib64/apple_gptk' \
  --exclude 'apple_gptk' \
  --exclude '/cyder-pe-provenance.json' \
  --exclude 'lib/dxvk' \
  --exclude 'lib/dxvk2' \
  --exclude 'lib/dxmt' \
  --exclude 'lib/*.bak-*' \
  "$WINE_INSTALL/" "$ENGINE_TREE/"
find "$ENGINE_TREE" -name '.DS_Store' -delete 2>/dev/null || true
if [[ -e "$ENGINE_TREE/lib64/apple_gptk" ]] ||
   find "$ENGINE_TREE" -type d -name 'apple_gptk' -print -quit | grep -q .; then
  echo "Refusing to pack engine that contains apple_gptk (GPTK must not be redistributed)" >&2
  exit 1
fi
cyder_write_engine_version_file "$ENGINE_TREE" "$ENGINE_VERSION_LABEL"

bash "$SCRIPT_DIR/strip-wine-install.sh" "$ENGINE_TREE"
# Preserve MoltenVK already in the install tree (VULKAN_SOURCE=existing only
# seeds it when VULKAN_MODE=with; default without would orphan-delete it).
VULKAN_MODE="${VULKAN_MODE:-with}" VULKAN_SOURCE=existing \
  bash "$SCRIPT_DIR/bundle-wine-dylibs.sh" "$ENGINE_TREE"

# Cyder012+ dual-variant MoltenVK: two versioned reals + wait-poll shim + .real symlink.
# Cyder008/009 kept the older single-real + shim pair without versioned siblings.
cyder_validate_moltenvk_dual_layout() {
  local dir="$1"
  local shim="$dir/libMoltenVK.dylib"
  local real_link="$dir/libMoltenVK.real.dylib"
  local v142="$dir/libMoltenVK-1.4.2.dylib"
  local v1210="$dir/libMoltenVK-1.2.10.dylib"
  local target

  [[ -f "$v142" && -f "$v1210" ]] || {
    echo "Refusing to pack: missing versioned MoltenVK reals (need libMoltenVK-1.4.2.dylib and libMoltenVK-1.2.10.dylib)" >&2
    return 1
  }
  [[ -L "$real_link" || -f "$real_link" ]] || {
    echo "Refusing to pack: missing libMoltenVK.real.dylib" >&2
    return 1
  }
  [[ -f "$shim" ]] || {
    echo "Refusing to pack: missing libMoltenVK.dylib shim" >&2
    return 1
  }
  target="$(readlink "$real_link" 2>/dev/null || true)"
  if [[ -z "$target" ]]; then
    # Non-symlink .real is only acceptable if it is not itself a shim (legacy).
    target="$(basename "$real_link")"
  fi
  case "$target" in
    libMoltenVK-1.4.2.dylib | libMoltenVK-1.2.10.dylib | */libMoltenVK-1.4.2.dylib | */libMoltenVK-1.2.10.dylib) ;;
    *)
      if [[ -L "$real_link" ]]; then
        echo "Refusing to pack: libMoltenVK.real.dylib must point at a versioned real (got $target)" >&2
        return 1
      fi
      ;;
  esac
  strings "$shim" | grep -Fq 'cyder-moltenvk-timeline-wait-poll' || {
    echo "Refusing to pack: libMoltenVK.dylib is not the wait-poll shim" >&2
    return 1
  }
  otool -L "$shim" | grep -Fq '@loader_path/libMoltenVK.real.dylib' || {
    echo "Refusing to pack: MoltenVK shim does not re-export libMoltenVK.real.dylib" >&2
    return 1
  }
  nm -gj "$shim" | grep -Fxq '_vkWaitSemaphores' || {
    echo "Refusing to pack: MoltenVK shim does not export vkWaitSemaphores" >&2
    return 1
  }
  if otool -L "$v142" | tail -n +3 | grep -Fq 'libMoltenVK.real.dylib'; then
    echo "Refusing to pack: libMoltenVK-1.4.2.dylib looks like a shim" >&2
    return 1
  fi
  if otool -L "$v1210" | tail -n +3 | grep -Fq 'libMoltenVK.real.dylib'; then
    echo "Refusing to pack: libMoltenVK-1.2.10.dylib looks like a shim" >&2
    return 1
  fi
  echo "OK: MoltenVK dual-variant wait-poll layout"
}

if [[ "$ENGINE_VERSION_LABEL" == *Cyder008* || "$ENGINE_VERSION_LABEL" == *Cyder009* ]]; then
  MOLTENVK_DIR="$ENGINE_TREE/lib/wine/x86_64-unix"
  MOLTENVK_SHIM="$MOLTENVK_DIR/libMoltenVK.dylib"
  MOLTENVK_REAL="$MOLTENVK_DIR/libMoltenVK.real.dylib"
  [[ -f "$MOLTENVK_SHIM" && -f "$MOLTENVK_REAL" ]] || {
    echo "Refusing to pack $ENGINE_VERSION_LABEL without the MoltenVK wait-poll shim pair" >&2
    exit 1
  }
  otool -L "$MOLTENVK_SHIM" | grep -Fq '@loader_path/libMoltenVK.real.dylib' || {
    echo "Refusing to pack: MoltenVK shim does not re-export libMoltenVK.real.dylib" >&2
    exit 1
  }
  nm -gj "$MOLTENVK_SHIM" | grep -Fxq '_vkWaitSemaphores' || {
    echo "Refusing to pack: MoltenVK shim does not export vkWaitSemaphores" >&2
    exit 1
  }
  if otool -L "$MOLTENVK_REAL" | tail -n +3 | grep -Fq 'libMoltenVK.real.dylib'; then
    echo "Refusing to pack: MoltenVK.real.dylib is itself a shim" >&2
    exit 1
  fi
  echo "OK: MoltenVK wait-poll shim pair ($ENGINE_VERSION_LABEL)"
elif [[ "$ENGINE_VERSION_LABEL" == *Cyder012* || "$ENGINE_VERSION_LABEL" == *Cyder01[3-9]* || "$ENGINE_VERSION_LABEL" == *Cyder0[2-9]* ]]; then
  cyder_validate_moltenvk_dual_layout "$ENGINE_TREE/lib/wine/x86_64-unix" || exit 1
fi
# Strip/bundle first, then PE-sign staging only, before final hashes/manifests.
if [[ "$PE_SIGNING_ENABLED" -eq 1 && "$DRY_RUN" -ne 1 ]]; then
  python3 "$SCRIPT_DIR/pe-signing.py" prepare --root "$ENGINE_TREE" --policy "$CYDER_PE_SIGNING_POLICY"
  PE_PROVENANCE_SHA256="$(shasum -a 256 "$ENGINE_TREE/cyder-pe-provenance.json" | awk '{print $1}')"
fi
bash "$SCRIPT_DIR/sign-wine.sh" --root "$ENGINE_TREE" --entitlements "$ENTITLEMENTS_PLIST"

PACKED_CXCOMPATDB="$ENGINE_TREE/lib/wine/x86_64-unix/cxcompatdb.so"
[[ -f "$PACKED_CXCOMPATDB" ]] || {
  echo "Refusing to pack without Cyder cxcompatdb.so" >&2
  exit 1
}
strings -a "$PACKED_CXCOMPATDB" | grep -Fq 'CYDER_GRAPHICS_BACKEND_PATH' || {
  echo "Refusing to pack an incompatible cxcompatdb.so" >&2
  exit 1
}

# Fail closed: every host Mach-O must stay at/below the product minOS floor.
python3 "$SCRIPT_DIR/pack-minos-scan.py" "$ENGINE_TREE" "${MACOSX_DEPLOYMENT_TARGET:-10.15}"
NTDLL="$ENGINE_TREE/lib/wine/x86_64-windows/ntdll.dll"
[[ -f "$NTDLL" ]] || {
  echo "Missing packaged NTDLL: $NTDLL" >&2
  exit 1
}
NTDLL_SHA256="$(shasum -a 256 "$NTDLL" | awk '{print $1}')"
bash "$SCRIPT_DIR/write-engine-manifest.sh" \
  --output "$ENGINE_TREE/engine-manifest.json" \
  --version "$ENGINE_VERSION_LABEL" \
  --ntdll-sha256 "$NTDLL_SHA256" \
  --pe-provenance-sha256 "$PE_PROVENANCE_SHA256"

mkdir -p "$ARTIFACTS_DIR"
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "DRY RUN: would create $ARCHIVE from $ENGINE_TREE"
  exit 0
fi

# Candidates live on the destination filesystem so the final archive rename is atomic.
CANDIDATE_ROOT="$(mktemp -d "$ARTIFACTS_DIR/.cyder-engine-publish.XXXXXX")"
CANDIDATE_ARCHIVE="$CANDIDATE_ROOT/$(basename "$ARCHIVE")"

case "$FORMAT" in
  zst)
    echo "==> Compressing with zstd (-22 --ultra)"
    (
      cd "$STAGING"
      zstd_args=(-22 --ultra -T0)
      if [[ "$FORCE" -eq 1 ]]; then zstd_args+=(--force); fi
      tar -cf - wine-x86_64 | "$ZSTD_BIN" "${zstd_args[@]}" -o "$CANDIDATE_ARCHIVE"
    )
    ;;
  xz)
    echo "==> Compressing with xz (-9e -T0)"
    (
      cd "$STAGING"
      tar -cf - wine-x86_64 | xz -9e -T0 -c >"$CANDIDATE_ARCHIVE"
    )
    ;;
esac

# Verify the archive itself, not only the staging tree. This catches signatures
# whose embedded CMS data does not survive the final tar round trip.
VERIFY_ROOT="$STAGING/archive-verify"
mkdir -p "$VERIFY_ROOT"
case "$FORMAT" in
  zst)
    "$ZSTD_BIN" -dc "$CANDIDATE_ARCHIVE" | tar -xf - -C "$VERIFY_ROOT"
    ;;
  xz)
    tar -xJf "$CANDIDATE_ARCHIVE" -C "$VERIFY_ROOT"
    ;;
esac
if [[ "$PE_SIGNING_ENABLED" -eq 1 ]]; then
  test "$(shasum -a 256 "$VERIFY_ROOT/wine-x86_64/cyder-pe-provenance.json" | awk '{print $1}')" = "$PE_PROVENANCE_SHA256"
  python3 "$SCRIPT_DIR/pe-signing.py" verify --root "$VERIFY_ROOT/wine-x86_64" --policy "$CYDER_PE_SIGNING_POLICY"
fi
verified_macho=0
while IFS= read -r -d '' signed_path; do
  if file -b "$signed_path" | grep -q 'Mach-O'; then
    codesign --verify --strict "$signed_path"
    verified_macho=$((verified_macho + 1))
  fi
done < <(find "$VERIFY_ROOT/wine-x86_64" -type f -print0)
echo "==> Verified $verified_macho Mach-O signatures after archive extraction"

printf '%s\n' "$ENGINE_VERSION_LABEL" >"$CANDIDATE_ROOT/engine-version.txt"
{
  echo "version=$ENGINE_VERSION_LABEL"
  echo "slug=$ENGINE_VERSION_SLUG"
  echo "format=$FORMAT"
  echo "archive=$(basename "$ARCHIVE")"
  if [[ -n "${CYDER_ENGINE_VERSION_LABEL:-}" ]]; then
    echo "wine=$ENGINE_VERSION_LABEL"
  else
    echo "wine=$(arch -x86_64 "$WINE_INSTALL/bin/wine" --version 2>/dev/null || true)"
  fi
  echo "packed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} >"$CANDIDATE_ROOT/.pack-stamp"
ARTIFACT_SHA256="$(shasum -a 256 "$CANDIDATE_ARCHIVE" | awk '{print $1}')"
printf '%s  %s\n' "$ARTIFACT_SHA256" "$(basename "$ARCHIVE")" >"${CANDIDATE_ARCHIVE}.sha256"
bash "$SCRIPT_DIR/write-engine-manifest.sh" \
  --output "${CANDIDATE_ARCHIVE}.manifest.json" \
  --version "$ENGINE_VERSION_LABEL" \
  --ntdll-sha256 "$NTDLL_SHA256" \
  --pe-provenance-sha256 "$PE_PROVENANCE_SHA256" \
  --artifact "$(basename "$ARCHIVE")" \
  --artifact-sha256 "$ARTIFACT_SHA256"

# Sidecars are ready before publication. On interruption readers may see a
# digest mismatch, but never an unverified candidate accepted as a valid cache.
mv -f "${CANDIDATE_ARCHIVE}.sha256" "${ARCHIVE}.sha256"
mv -f "${CANDIDATE_ARCHIVE}.manifest.json" "${ARCHIVE}.manifest.json"
mv -f "$CANDIDATE_ARCHIVE" "$ARCHIVE"
mv -f "$CANDIDATE_ROOT/engine-version.txt" "$VERSION_FILE"
mv -f "$CANDIDATE_ROOT/.pack-stamp" "$STAMP_FILE"

echo "==> Created $ARCHIVE ($(du -sh "$ARCHIVE" | awk '{print $1}'))"
echo "==> Version file: $VERSION_FILE"
echo "==> Manifest: ${ARCHIVE}.manifest.json"
