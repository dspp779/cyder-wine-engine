#!/bin/bash
set -euo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$KIT/kit-config.sh"
ROOT="${CYDER_TEST_ROOT:-$HOME/.cyder-tests/$TEST_NAME}"
fail() { echo "錯誤：$*" >&2; exit 1; }
check_root() {
  [[ "$ROOT" == /* && "$ROOT" != / && "$ROOT" != "$HOME" && ! -L "$ROOT" ]] || fail '測試目錄必須是獨立的絕對路徑。'
  case "$ROOT/" in "$HOME/.cyder/"*|"$HOME/Library/Application Support/Cyder/"*) fail '不可指定正式 Cyder 資料目錄。' ;; esac
  if [[ -d "$ROOT" ]]; then ROOT="$(cd "$ROOT" && pwd -P)"; fi
  case "$ROOT/" in "$HOME/.cyder/"*|"$HOME/Library/Application Support/Cyder/"*) fail '不可指定正式 Cyder 資料目錄。' ;; esac
}
verify_tree() {
  local tree="$1" path target
  [[ -f "$tree/engine/version" && "$(cat "$tree/engine/version")" == "$TEST_VERSION" ]] || fail '引擎版本不符。'
  (cd "$tree"; /usr/bin/shasum -a 256 -c --status "$KIT/installed-files.sha256") || fail '安裝內容校驗失敗；請保留瓶子與日誌，重新解壓測試包到新目錄。'
  while IFS=$'\t' read -r path target; do
    [[ -z "$path" ]] && continue
    [[ -L "$tree/$path" && "$(readlink "$tree/$path")" == "$target" ]] || fail "連結校驗失敗：$path"
  done < "$KIT/installed-links.tsv"
  /usr/bin/codesign --verify --strict "$tree/engine/bin/wine" || fail 'Wine 簽章驗證失敗。'
  /usr/bin/codesign --verify --strict "$tree/engine/lib/wine/x86_64-unix/winemac.so" || fail 'winemac 簽章驗證失敗。'
}
check_root
