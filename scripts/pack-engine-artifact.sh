#!/usr/bin/env bash
# Build reusable Wine engine artifact (strip + compressed tar) for Cyder / CyderBits apps.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=engine-common.sh
source "$SCRIPT_DIR/engine-common.sh"
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
    -h | --help)
      cat <<EOF
Usage: $(basename "$0") [--force] [--dry-run] [--zstd] [--format zstd|xz]

Build a compressed engine artifact from install/wine-cx26-x86_64 (or WINE_INSTALL).
  xz:   dist/artifacts/engine-wine-x86_64-<CX26-winever>.tar.xz (default, xz -9e)
  zstd: dist/artifacts/engine-<CX26-winever>.tar.zst (--zstd)
Set CYDER_ENGINE_VERSION to override the detected version label.
Set CYDER_ENGINE_FORMAT=zstd or pass --zstd to build with zstd -22 --ultra.
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

if [[ -f "$ARCHIVE" && "$FORCE" -ne 1 ]]; then
  echo "Engine artifact present: $ARCHIVE"
  echo "Use --force to rebuild."
  exit 0
fi

STAGING="$(mktemp -d "${TMPDIR:-/tmp}/cyder-engine-pack.XXXXXX")"
cleanup() {
  rm -rf "$STAGING"
}
trap cleanup EXIT
ENGINE_TREE="$STAGING/wine-x86_64"

echo "==> Staging engine tree ($ENGINE_VERSION_LABEL)"
# Fail closed: never ship Apple GPTK inside a redistributable engine artifact.
rsync -a --delete \
  --exclude 'lib64/apple_gptk' \
  --exclude 'apple_gptk' \
  "$WINE_INSTALL/" "$ENGINE_TREE/"
find "$ENGINE_TREE" -name '.DS_Store' -delete 2>/dev/null || true
if [[ -e "$ENGINE_TREE/lib64/apple_gptk" ]] ||
   find "$ENGINE_TREE" -type d -name 'apple_gptk' -print -quit | grep -q .; then
  echo "Refusing to pack engine that contains apple_gptk (GPTK must not be redistributed)" >&2
  exit 1
fi
cyder_write_engine_version_file "$ENGINE_TREE" "$ENGINE_VERSION_LABEL"

# Fail closed: DXVK is a first-class graphics backend for this engine.
for _dxvk_dll in \
  lib/dxvk/x86_64-windows/d3d11.dll \
  lib/dxvk/x86_64-windows/dxgi.dll \
  lib/dxvk/i386-windows/d3d11.dll \
  lib/dxvk/i386-windows/dxgi.dll; do
  if [[ ! -f "$ENGINE_TREE/$_dxvk_dll" ]]; then
    echo "Refusing to pack engine without $_dxvk_dll (run scripts/build-dxvk.sh or copy lib/dxvk)" >&2
    exit 1
  fi
done
unset _dxvk_dll

# Fail closed: DXMT is a first-class graphics backend for this engine.
for _dxmt_file in \
  lib/dxmt/x86_64-windows/d3d11.dll \
  lib/dxmt/x86_64-windows/dxgi.dll \
  lib/dxmt/x86_64-unix/winemetal.so; do
  if [[ ! -f "$ENGINE_TREE/$_dxmt_file" ]]; then
    echo "Refusing to pack engine without $_dxmt_file (run ogom scripts/fetch-dxmt.sh)" >&2
    exit 1
  fi
done
unset _dxmt_file

bash "$SCRIPT_DIR/strip-wine-install.sh" "$ENGINE_TREE"
# Preserve MoltenVK already in the install tree (VULKAN_SOURCE=existing only
# seeds it when VULKAN_MODE=with; default without would orphan-delete it).
VULKAN_MODE="${VULKAN_MODE:-with}" VULKAN_SOURCE=existing \
  bash "$SCRIPT_DIR/bundle-wine-dylibs.sh" "$ENGINE_TREE"

# Cyder008+ owns the MoltenVK wait-poll workaround in the engine artifact.
# Refuse to publish a plain MoltenVK or a broken shim-on-shim pair so the App
# never needs to mutate the installed engine at runtime.
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
fi
bash "$SCRIPT_DIR/sign-wine.sh" --root "$ENGINE_TREE" --entitlements "$ENTITLEMENTS_PLIST"

# Fail closed: every host Mach-O must stay at/below the product minOS floor.
python3 - "$ENGINE_TREE" "${MACOSX_DEPLOYMENT_TARGET:-10.15}" <<'PY'
import re, subprocess, sys
from pathlib import Path

root = Path(sys.argv[1])
floor_s = sys.argv[2]

def parse(v: str):
    parts = [int(x) for x in v.split(".")]
    while len(parts) < 3:
        parts.append(0)
    return tuple(parts[:3])

floor = parse(floor_s)
high = []
for p in root.rglob("*"):
    if not p.is_file() or p.is_symlink():
        continue
    try:
        f = subprocess.check_output(["file", "-b", str(p)], text=True, stderr=subprocess.DEVNULL)
    except Exception:
        continue
    if "Mach-O" not in f:
        continue
    out = subprocess.check_output(["otool", "-l", str(p)], text=True, stderr=subprocess.DEVNULL)
    m = re.search(r"\bminos\s+(\d+(?:\.\d+)*)", out)
    if not m:
        continue
    if parse(m.group(1)) > floor:
        high.append((m.group(1), str(p.relative_to(root))))
if high:
    print(f"Refusing to pack: Mach-O minos exceeds product floor {floor_s}:", file=sys.stderr)
    for ver, rel in sorted(high):
        print(f"  {ver}  {rel}", file=sys.stderr)
    sys.exit(1)
print(f"OK: staged engine Mach-O minos ≤ {floor_s}")
PY
NTDLL="$ENGINE_TREE/lib/wine/x86_64-windows/ntdll.dll"
[[ -f "$NTDLL" ]] || {
  echo "Missing packaged NTDLL: $NTDLL" >&2
  exit 1
}
NTDLL_SHA256="$(shasum -a 256 "$NTDLL" | awk '{print $1}')"
bash "$SCRIPT_DIR/write-engine-manifest.sh" \
  --output "$ENGINE_TREE/engine-manifest.json" \
  --version "$ENGINE_VERSION_LABEL" \
  --ntdll-sha256 "$NTDLL_SHA256"

mkdir -p "$ARTIFACTS_DIR"
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "DRY RUN: would create $ARCHIVE from $ENGINE_TREE"
  exit 0
fi

case "$FORMAT" in
  zst)
    echo "==> Compressing with zstd (-22 --ultra)"
    (
      cd "$STAGING"
      tar -cf - wine-x86_64 | "$ZSTD_BIN" -22 --ultra -T0 -o "$ARCHIVE"
    )
    ;;
  xz)
    echo "==> Compressing with xz (-9e -T0)"
    (
      cd "$STAGING"
      tar -cf - wine-x86_64 | xz -9e -T0 -c >"$ARCHIVE"
    )
    ;;
esac

# Verify the archive itself, not only the staging tree. This catches signatures
# whose embedded CMS data does not survive the final tar round trip.
VERIFY_ROOT="$STAGING/archive-verify"
mkdir -p "$VERIFY_ROOT"
case "$FORMAT" in
  zst)
    "$ZSTD_BIN" -dc "$ARCHIVE" | tar -xf - -C "$VERIFY_ROOT"
    ;;
  xz)
    tar -xJf "$ARCHIVE" -C "$VERIFY_ROOT"
    ;;
esac
verified_macho=0
while IFS= read -r -d '' signed_path; do
  if file -b "$signed_path" | grep -q 'Mach-O'; then
    codesign --verify --strict "$signed_path"
    verified_macho=$((verified_macho + 1))
  fi
done < <(find "$VERIFY_ROOT/wine-x86_64" -type f -print0)
echo "==> Verified $verified_macho Mach-O signatures after archive extraction"

printf '%s\n' "$ENGINE_VERSION_LABEL" >"$VERSION_FILE"
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
} >"$STAMP_FILE"
ARTIFACT_SHA256="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
printf '%s  %s\n' "$ARTIFACT_SHA256" "$(basename "$ARCHIVE")" >"${ARCHIVE}.sha256"
bash "$SCRIPT_DIR/write-engine-manifest.sh" \
  --output "${ARCHIVE}.manifest.json" \
  --version "$ENGINE_VERSION_LABEL" \
  --ntdll-sha256 "$NTDLL_SHA256" \
  --artifact "$(basename "$ARCHIVE")" \
  --artifact-sha256 "$ARTIFACT_SHA256"

echo "==> Created $ARCHIVE ($(du -sh "$ARCHIVE" | awk '{print $1}'))"
echo "==> Version file: $VERSION_FILE"
echo "==> Manifest: ${ARCHIVE}.manifest.json"
