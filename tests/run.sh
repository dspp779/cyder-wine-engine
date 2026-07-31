#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tests=(
  test-build-wine.sh
  test-ntdll-frame-walk-patches.sh
  test-strip-wine-install.sh
  test-sign-wine.sh
  test-sign-wine-preserve-developer-id.sh
  test-bundle-wine-dylibs-source.sh
  test-cyder-engine-version.sh
  test-engine-manifest.sh
  test-ntdll-frame-walk-guard.sh
  test-wineserver-poll-guard-patches.sh
  test-wineserver-exit-diagnostics.sh
  test-wineserver-fd-reselect-async-null-ops.sh
)

for test_file in "${tests[@]}"; do
  echo "==> $test_file"
  bash "$ROOT/tests/$test_file"
done

