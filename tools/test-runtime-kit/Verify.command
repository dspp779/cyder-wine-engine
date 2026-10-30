#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
[[ -f "$ROOT/.cyder-test-version" && "$(cat "$ROOT/.cyder-test-version")" == "$TEST_VERSION" ]] || fail '請先執行 Install.command。'
verify_tree "$ROOT"
echo "PASS：測試 runtime 的版本、檔案、連結與核心簽章通過：$ROOT"
