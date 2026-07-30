#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/assert.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ntdll_sha="$(printf 'a%.0s' {1..64})"
artifact_sha="$(printf 'b%.0s' {1..64})"
bash "$ROOT/scripts/write-engine-manifest.sh" \
  --output "$TMP/engine-manifest.json" \
  --version "CX26.3.0-W11-Cyder007" \
  --ntdll-sha256 "$ntdll_sha" \
  --artifact "engine-test.tar.xz" \
  --artifact-sha256 "$artifact_sha"

plutil -convert json -o /dev/null -- "$TMP/engine-manifest.json"
assert_contains "$(cat "$TMP/engine-manifest.json")" "\"ntdllSHA256\": \"$ntdll_sha\"" \
  "manifest should pin the built NTDLL"
assert_contains "$(cat "$TMP/engine-manifest.json")" "\"artifactSHA256\": \"$artifact_sha\"" \
  "sidecar manifest should pin the archive"
assert_contains "$(cat "$TMP/engine-manifest.json")" "rtlwalkframechain-null-function" \
  "manifest should record the ordered frame-walk patch set"

echo "PASS test-engine-manifest"
