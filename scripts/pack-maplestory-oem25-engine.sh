#!/usr/bin/env bash
# Repack the MapleStory OEM25 engine for Cyder's external graphics runtime.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OGOM_ROOT="${CYDER_OGOM_ROOT:-$ROOT/../ogom}"
ARTIFACTS_DIR="${CYDER_OEM_ARTIFACTS_DIR:-$OGOM_ROOT/dist/artifacts/maplestory-oem25}"
BASE_ARCHIVE="${CYDER_OEM_BASE_ARCHIVE:-$ARTIFACTS_DIR/engine-maplestory-oem25.0.1.38865.tar.xz}"
OEM_SOURCE="${CYDER_OEM_WINE_SRC:-$ROOT/build/maplestory-oem25/sources/wine}"
MOLTENVK_SOURCE="${CYDER_OEM_MOLTENVK_SRC:-$ROOT/install/wine-cx26-x86_64/lib/wine/x86_64-unix/libMoltenVK.dylib}"
VERSION_LABEL="${CYDER_ENGINE_VERSION_LABEL:-CX25.0.1.38865-OEM25-Cyder010}"
ARCHIVE_FORMAT="${CYDER_ENGINE_FORMAT:-xz}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
ENTITLEMENTS="${ENTITLEMENTS_PLIST:-$ROOT/config/entitlements.plist}"
FORCE=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Repack the pinned MapleStory OEM25 CrossOver archive for Cyder's runtime.

Options:
  --base-archive PATH   OEM archive to use as the unmodified base
  --wine-source PATH    OEM Wine source tree used for cxcompatdb headers
  --moltenvk PATH       Cyder MoltenVK 1.4.0 binary to install
  --output-dir PATH     Artifact output directory
  --version LABEL       Engine version label
  --force               Replace an existing archive
  --zstd                Write .tar.zst instead of .tar.xz
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-archive) BASE_ARCHIVE="$2"; shift 2 ;;
    --wine-source) OEM_SOURCE="$2"; shift 2 ;;
    --moltenvk) MOLTENVK_SOURCE="$2"; shift 2 ;;
    --output-dir) ARTIFACTS_DIR="$2"; shift 2 ;;
    --version) VERSION_LABEL="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --zstd|--zst) ARCHIVE_FORMAT=zst; shift ;;
    --xz) ARCHIVE_FORMAT=xz; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

case "$ARCHIVE_FORMAT" in
  xz|zst) ;;
  *) echo "Unsupported archive format: $ARCHIVE_FORMAT" >&2; exit 1 ;;
esac

[[ "$VERSION_LABEL" =~ ^[A-Za-z0-9._-]+$ ]] || {
  echo "Unsafe OEM engine version label: $VERSION_LABEL" >&2
  exit 1
}
[[ -f "$BASE_ARCHIVE" ]] || { echo "Missing OEM base archive: $BASE_ARCHIVE" >&2; exit 1; }
[[ -f "$OEM_SOURCE/include/winternl.h" && -f "$OEM_SOURCE/include/config.h.in" ]] || {
  echo "Missing OEM Wine headers: $OEM_SOURCE" >&2
  exit 1
}
[[ -f "$OEM_SOURCE/dlls/ntdll/unix/loader.c" ]] || {
  echo "Missing OEM ntdll loader source: $OEM_SOURCE/dlls/ntdll/unix/loader.c" >&2
  exit 1
}
[[ -f "$MOLTENVK_SOURCE" ]] || { echo "Missing MoltenVK source: $MOLTENVK_SOURCE" >&2; exit 1; }
[[ -f "$ENTITLEMENTS" ]] || { echo "Missing entitlements: $ENTITLEMENTS" >&2; exit 1; }

mkdir -p "$ARTIFACTS_DIR"
version_suffix="${VERSION_LABEL##*-OEM25-}"
[[ "$version_suffix" != "$VERSION_LABEL" && -n "$version_suffix" ]] || {
  echo "OEM engine version must contain -OEM25-: $VERSION_LABEL" >&2
  exit 1
}
case "$ARCHIVE_FORMAT" in
  xz) ARCHIVE="$ARTIFACTS_DIR/engine-maplestory-oem25.0.1.38865-OEM25-${version_suffix}.tar.xz" ;;
  zst) ARCHIVE="$ARTIFACTS_DIR/engine-maplestory-oem25.0.1.38865-OEM25-${version_suffix}.tar.zst" ;;
esac
if [[ -f "$ARCHIVE" && "$FORCE" -ne 1 ]]; then
  echo "Artifact exists: $ARCHIVE (use --force to rebuild)" >&2
  exit 1
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cyder-oem25-pack.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

strings -a "$MOLTENVK_SOURCE" >"$TMP/moltenvk.strings"
grep -Eq '(^|[^0-9])1\.4\.0([^0-9]|$)' "$TMP/moltenvk.strings" || {
  echo "MoltenVK source is not 1.4.0: $MOLTENVK_SOURCE" >&2
  exit 1
}

echo "==> Extracting OEM base archive"
tar -xJf "$BASE_ARCHIVE" -C "$TMP"
ENGINE_TREE="$TMP/wine-x86_64"
NTDLL_SO="$ENGINE_TREE/lib/wine/x86_64-unix/ntdll.so"
CXCOMPATDB="$ENGINE_TREE/lib/wine/x86_64-unix/cxcompatdb.so"
OEM_MOLTENVK="$ENGINE_TREE/lib64/libMoltenVK.dylib"
[[ -x "$ENGINE_TREE/bin/wine" ]] || { echo "OEM archive lacks bin/wine" >&2; exit 1; }
[[ -f "$NTDLL_SO" && -f "$CXCOMPATDB" && -f "$OEM_MOLTENVK" ]] || {
  echo "OEM archive lacks required ntdll/cxcompatdb/MoltenVK files" >&2
  exit 1
}

ntdll_sha_before="$(shasum -a 256 "$NTDLL_SO" | awk '{print $1}')"
if ! nm -gU "$NTDLL_SO" | grep -Fq '_prepend_dll_path' ||
   ! nm -gU "$NTDLL_SO" | grep -Fq '_add_load_order_override' ||
   ! nm -gU "$NTDLL_SO" | grep -Fq '_NtCurrentTeb'; then
  echo "OEM ntdll does not expose the cxcompatdb loader ABI" >&2
  exit 1
fi

echo "==> Building Cyder cxcompatdb against OEM headers"
CONFIG_DIR="$TMP/cxcompatdb-config"
mkdir -p "$CONFIG_DIR"
cp "$OEM_SOURCE/include/config.h.in" "$CONFIG_DIR/config.h"
WINE_SRC="$OEM_SOURCE" \
  CYDER_CXCOMPATDB_CONFIG_DIR="$CONFIG_DIR" \
  CYDER_CXCOMPATDB_EXTRA_CFLAGS='-Wno-pragma-pack' \
  CYDER_CXCOMPATDB_OUTPUT="$CXCOMPATDB" \
  bash "$SCRIPT_DIR/build-cyder-cxcompatdb.sh"

echo "==> Installing MoltenVK 1.4.0"
cp "$MOLTENVK_SOURCE" "$OEM_MOLTENVK"
chmod +x "$OEM_MOLTENVK"

# Graphics PE are distributed as Cyder Resources/graphics sidecars. Never
# leave a physical copy in the OEM engine, even if the base archive changes.
rm -rf "$ENGINE_TREE/lib/dxvk" "$ENGINE_TREE/lib/dxvk2" "$ENGINE_TREE/lib/dxmt"

printf '%s\n' "$VERSION_LABEL" >"$ENGINE_TREE/version"
ntdll_sha_after="$(shasum -a 256 "$NTDLL_SO" | awk '{print $1}')"
[[ "$ntdll_sha_before" == "$ntdll_sha_after" ]] || {
  echo "OEM ntdll changed during repack" >&2
  exit 1
}

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  TIMESTAMP_FLAG='--timestamp=none'
else
  TIMESTAMP_FLAG='--timestamp'
fi
sign_replaced() {
  local path="$1"
  codesign --force --options runtime "$TIMESTAMP_FLAG" \
    --entitlements "$ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$path"
  codesign --verify --strict "$path"
}
echo "==> Signing replaced engine components (${SIGN_IDENTITY})"
sign_replaced "$CXCOMPATDB"
sign_replaced "$OEM_MOLTENVK"

if find "$ENGINE_TREE/lib" -maxdepth 1 -type d \( -name dxvk -o -name dxvk2 -o -name dxmt \) -print -quit | grep -q .; then
  echo "Graphics payload remained in OEM engine" >&2
  exit 1
fi
strings -a "$CXCOMPATDB" >"$TMP/cxcompatdb.strings"
grep -Fq 'CYDER_GRAPHICS_BACKEND_PATH' "$TMP/cxcompatdb.strings" || {
  echo "Repacked cxcompatdb lacks current Cyder graphics path support" >&2
  exit 1
}
strings -a "$OEM_MOLTENVK" >"$TMP/repacked-moltenvk.strings"
grep -Eq '(^|[^0-9])1\.4\.0([^0-9]|$)' "$TMP/repacked-moltenvk.strings" || {
  echo "Repacked MoltenVK is not 1.4.0" >&2
  exit 1
}

MANIFEST="$TMP/engine-manifest.json"
bash "$SCRIPT_DIR/write-engine-manifest.sh" \
  --config "$ROOT/config/engine-release-maplestory-oem25.json" \
  --output "$MANIFEST" \
  --version "$VERSION_LABEL" \
  --ntdll-sha256 "$ntdll_sha_after"
cp "$MANIFEST" "$ENGINE_TREE/engine-manifest.json"

echo "==> Compressing $ARCHIVE"
case "$ARCHIVE_FORMAT" in
  xz)
    (cd "$TMP" && tar -cf - wine-x86_64 | xz -9e -T0 -c >"$ARCHIVE")
    ;;
  zst)
    ZSTD_BIN="${CYDER_ZSTD_BIN:-$OGOM_ROOT/tools/zstd/zstd}"
    [[ -x "$ZSTD_BIN" ]] || { echo "Missing zstd: $ZSTD_BIN" >&2; exit 1; }
    (cd "$TMP" && tar -cf - wine-x86_64 | "$ZSTD_BIN" -22 --ultra -T0 -o "$ARCHIVE")
    ;;
esac

VERIFY="$TMP/verify"
mkdir -p "$VERIFY"
case "$ARCHIVE_FORMAT" in
  xz) tar -xJf "$ARCHIVE" -C "$VERIFY" ;;
  zst) "$ZSTD_BIN" -dc "$ARCHIVE" | tar -xf - -C "$VERIFY" ;;
esac
VERIFY_ENGINE="$VERIFY/wine-x86_64"
[[ "$(cat "$VERIFY_ENGINE/version")" == "$VERSION_LABEL" ]] || { echo "Version round-trip failed" >&2; exit 1; }
[[ ! -e "$VERIFY_ENGINE/lib/dxvk" && ! -e "$VERIFY_ENGINE/lib/dxvk2" && ! -e "$VERIFY_ENGINE/lib/dxmt" ]] || {
  echo "Graphics tree round-trip gate failed" >&2
  exit 1
}
codesign --verify --strict "$VERIFY_ENGINE/lib/wine/x86_64-unix/cxcompatdb.so"
codesign --verify --strict "$VERIFY_ENGINE/lib64/libMoltenVK.dylib"
[[ "$(shasum -a 256 "$VERIFY_ENGINE/lib/wine/x86_64-unix/ntdll.so" | awk '{print $1}')" == "$ntdll_sha_before" ]] || {
  echo "ntdll round-trip hash changed" >&2
  exit 1
}

ARTIFACT_SHA="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
printf '%s  %s\n' "$ARTIFACT_SHA" "$(basename "$ARCHIVE")" >"$ARCHIVE.sha256"
bash "$SCRIPT_DIR/write-engine-manifest.sh" \
  --config "$ROOT/config/engine-release-maplestory-oem25.json" \
  --output "$ARCHIVE.manifest.json" \
  --version "$VERSION_LABEL" \
  --ntdll-sha256 "$ntdll_sha_after" \
  --artifact "$(basename "$ARCHIVE")" \
  --artifact-sha256 "$ARTIFACT_SHA"
printf '%s\n' "$VERSION_LABEL" >"$ARTIFACTS_DIR/engine-maplestory-oem25-version.txt"

echo "==> Created $ARCHIVE ($(du -h "$ARCHIVE" | awk '{print $1}'))"
echo "==> SHA-256: $ARTIFACT_SHA"
