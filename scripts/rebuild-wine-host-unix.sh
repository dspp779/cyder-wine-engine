#!/usr/bin/env bash
# Rebuild Wine host unix modules (*.so, wineserver, …) with the project minOS.
# Use after incremental builds drifted to the SDK default (e.g. macOS 15.0).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env-x86_64.sh
source "$SCRIPT_DIR/env-x86_64.sh"

JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}"
TARGET="${MACOSX_DEPLOYMENT_TARGET}"
MIN_FLAG="${CYDER_MACOSX_VERSION_MIN_FLAG:--mmacosx-version-min=${TARGET}}"
BUILD64="${WINE_SRC}/build64"
LOG_DIR="${OGOM}/logs"
LOG="${LOG_DIR}/rebuild-host-unix-$(date +%Y%m%d-%H%M%S).log"

[[ -d "$BUILD64" ]] || {
  echo "Missing build tree: $BUILD64" >&2
  exit 1
}
[[ -x "$WINE_INSTALL/bin/wine" ]] || {
  echo "Missing install tree: $WINE_INSTALL" >&2
  exit 1
}

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG") 2>&1

echo "==> Host minOS rebuild"
echo "    MACOSX_DEPLOYMENT_TARGET=$TARGET"
echo "    flag=$MIN_FLAG"
echo "    build64=$BUILD64"
echo "    install=$WINE_INSTALL"
echo "    log=$LOG"

HOST_CFLAGS="${CFLAGS:--g -O2} ${MIN_FLAG}"
HOST_OBJCFLAGS="${OBJCFLAGS:--g -O2} ${MIN_FLAG}"
HOST_LDFLAGS="${LDFLAGS:-} ${MIN_FLAG}"

BUILD_PATH="$LLVM_MINGW/bin:$HOMEBREW_PREFIX/bin:/usr/bin:/bin:/usr/sbin:/sbin"
VULKAN_PKG_PC_PATH="${PKG_CONFIG_PATH:-}"

echo "==> Removing host unix products so they relink/recompile at minOS $TARGET"
find "$BUILD64" \( -name '*.so' -o -name 'wineserver' -o -name 'wine' -o -name 'wine64' \) \
  ! -path '*/.*' -type f -print -delete
# Force recompile of unix objects (availability / deployment target is compile-time).
find "$BUILD64" -type d -name unix | while read -r unix_dir; do
  find "$unix_dir" \( -name '*.o' -o -name '*.d' \) -type f -delete
done
# Top-level server/loader objects that feed host binaries.
find "$BUILD64/server" "$BUILD64/loader" \( -name '*.o' -o -name '*.d' \) -type f -delete 2>/dev/null || true

echo "==> make -j$JOBS (host minOS $TARGET)"
# Guard against a build64 that was configured into a scratch prefix.
CONFIGURED_PREFIX="$(
  sed -n 's/^prefix='\''\(.*\)'\''$/\1/p; s/^prefix=\(.*\)$/\1/p' "$BUILD64/config.status" 2>/dev/null | head -1
)"
CONFIGURED_PREFIX="${CONFIGURED_PREFIX//\$\{prefix\}/$WINE_INSTALL}"
if [[ -n "$CONFIGURED_PREFIX" && "$CONFIGURED_PREFIX" != "$WINE_INSTALL" ]]; then
  echo "NOTE: build64 prefix is '$CONFIGURED_PREFIX' (expected '$WINE_INSTALL')"
  echo "      make install will override prefix= to the project install tree."
fi

arch -x86_64 env \
  PATH="$BUILD_PATH" \
  PKG_CONFIG_PATH="$VULKAN_PKG_PC_PATH" \
  LIBRARY_PATH="${LIBRARY_PATH:-}" \
  MACOSX_DEPLOYMENT_TARGET="$TARGET" \
  CFLAGS="$HOST_CFLAGS" \
  OBJCFLAGS="$HOST_OBJCFLAGS" \
  LDFLAGS="$HOST_LDFLAGS" \
  make -C "$BUILD64" -j"$JOBS"

echo "==> make install prefix=$WINE_INSTALL"
arch -x86_64 env \
  PATH="$BUILD_PATH" \
  PKG_CONFIG_PATH="$VULKAN_PKG_PC_PATH" \
  LIBRARY_PATH="${LIBRARY_PATH:-}" \
  MACOSX_DEPLOYMENT_TARGET="$TARGET" \
  CFLAGS="$HOST_CFLAGS" \
  OBJCFLAGS="$HOST_OBJCFLAGS" \
  LDFLAGS="$HOST_LDFLAGS" \
  make -C "$BUILD64" install prefix="$WINE_INSTALL"

echo "==> Verifying install Mach-O minos ≤ $TARGET"
python3 - "$WINE_INSTALL" "$TARGET" <<'PY'
import re, subprocess, sys
from pathlib import Path

root = Path(sys.argv[1])
floor_s = sys.argv[2]

def parse(v):
    parts = [int(x) for x in v.split(".")]
    while len(parts) < 3:
        parts.append(0)
    return tuple(parts[:3])

floor = parse(floor_s)
high = []
checked = 0
for p in root.rglob("*"):
    if not p.is_file() or p.is_symlink():
        continue
    try:
        f = subprocess.check_output(["file", "-b", str(p)], text=True, stderr=subprocess.DEVNULL)
    except Exception:
        continue
    if "Mach-O" not in f:
        continue
    checked += 1
    out = subprocess.check_output(["otool", "-l", str(p)], text=True, stderr=subprocess.DEVNULL)
    m = re.search(r"\bminos\s+(\d+(?:\.\d+)*)", out)
    if not m:
        m = re.search(
            r"LC_VERSION_MIN_MACOSX.*?^\s+version\s+(\d+(?:\.\d+)*)",
            out,
            re.M | re.S,
        )
    if not m:
        continue
    if parse(m.group(1)) > floor:
        high.append((m.group(1), str(p.relative_to(root))))

print(f"checked={checked} high={len(high)} floor={floor_s}")
for ver, rel in sorted(high):
    print(f"  FAIL {ver}  {rel}")
if high:
    sys.exit(1)
print(f"OK: all Mach-O minos ≤ {floor_s}")
PY

echo "==> Done. Log: $LOG"
