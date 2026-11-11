#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
if [[ -e "$ROOT" ]]; then
  [[ -f "$ROOT/.cyder-test-version" && "$(cat "$ROOT/.cyder-test-version")" == "$TEST_VERSION" ]] || fail '目錄已存在；不會覆寫。請另選空目錄。'
  verify_tree "$ROOT"
  echo "已安裝且校驗通過：$ROOT"
  exit 0
fi
(cd "$KIT"; /usr/bin/shasum -a 256 -c --status package-files.sha256) || fail '測試包檔案校驗失敗。'
/usr/bin/codesign --verify --strict "$KIT/bin/zstd" || fail '解壓工具簽章驗證失敗。'
parent="$(dirname "$ROOT")"
mkdir -p "$parent"
parent="$(cd "$parent" && pwd -P)"
ROOT="$parent/$(basename "$ROOT")"
check_root
LOCK="$ROOT.install-lock"
mkdir "$LOCK" 2>/dev/null || fail '另一個安裝程序正在使用此目錄；請等待完成。'
STAGE=""
cleanup() { [[ -z "$STAGE" ]] || rm -rf "$STAGE"; rmdir "$LOCK" 2>/dev/null || true; }
trap cleanup EXIT
[[ ! -e "$ROOT" ]] || fail '目錄已存在；不會覆寫。'
STAGE="$(mktemp -d "$parent/.cyder-test-install.XXXXXX")"
/usr/bin/tar -xJf "$KIT/$ENGINE_ARCHIVE" -C "$STAGE"
mv "$STAGE/wine-x86_64" "$STAGE/engine"
for name in dxvk dxvk2 dxmt; do
  case "$name" in dxvk) archive="$DXVK_ARCHIVE" ;; dxvk2) archive="$DXVK2_ARCHIVE" ;; dxmt) archive="$DXMT_ARCHIVE" ;; esac
  "$KIT/bin/zstd" -d -c "$KIT/graphics/$archive" | /usr/bin/tar -xf - -C "$STAGE/engine/lib"
done
verify_tree "$STAGE"
printf '%s\n' "$TEST_VERSION" > "$STAGE/.cyder-test-version"
mkdir -m 700 "$STAGE/prefixes" "$STAGE/logs"
mv "$STAGE" "$ROOT"
STAGE=""
echo "安裝完成：$ROOT"
echo '接著雙擊 Run Test.command，選擇繪圖後端與遊戲 EXE。'
echo '所有測試瓶子與日誌都放在這個獨立目錄。'
