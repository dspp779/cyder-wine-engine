#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tests=(
  test-build-wine.sh
  test-maplestory-patch-stack.sh
  test-maplestory-file-cache-patch.sh
  test-maplestory-d3dmetal-launcher.sh
  test-cyder-cxcompatdb.sh
  test-cyder-minos-env.sh
  test-ntdll-frame-walk-patches.sh
  test-strip-wine-install.sh
  test-sign-wine.sh
  test-sign-wine-preserve-developer-id.sh
  test-bundle-wine-dylibs-source.sh
  test-cyder-engine-version.sh
  test-engine-manifest.sh
  test-winemac-a6-patch.sh
  test-ntdll-frame-walk-guard.sh
  test-wineserver-poll-guard-patches.sh
  test-wineserver-exit-diagnostics.sh
  test-wineserver-fd-reselect-async-null-ops.sh
  test-wineserver-sock-rebind-async-fd.sh
  test-wineserver-async-terminate-null-fd.sh
  test-wineserver-free-async-queue-null-fd.sh
  test-wineserver-pipe-end-disconnect-null-fd.sh
  test-wineserver-add-completion-guard.sh
  test-ntdll-query-directory-object-trace.sh
  test-moltenvk-timeline-wait-poll.sh
  test-moltenvk-1-4-source-and-capabilities.sh
  test-pack-graphics-payloads.sh
  test-pack-engine-dxmt-gate.sh
  test-pack-minos-scan.sh
)

for test_file in "${tests[@]}"; do
  echo "==> $test_file"
  bash "$ROOT/tests/$test_file"
done
