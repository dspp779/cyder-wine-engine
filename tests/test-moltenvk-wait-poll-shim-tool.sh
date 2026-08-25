#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/assert.sh"

assert test -f "$ROOT/tools/cyder-mvk-timeline-wait-poll/cyder_mvk_timeline_wait_poll.m"
assert test -f "$ROOT/tools/cyder-mvk-timeline-wait-poll/install-shim.sh"
assert_contains "$(cat "$ROOT/tools/cyder-mvk-timeline-wait-poll/cyder_mvk_timeline_wait_poll.m")" \
  "cyder-moltenvk-timeline-wait-poll" \
  "shim source must embed the wait-poll marker string"
assert_contains "$(cat "$ROOT/tools/cyder-mvk-timeline-wait-poll/install-shim.sh")" \
  "libMoltenVK.real.dylib" \
  "install-shim.sh must target the .real re-export layout"

echo "PASS moltenvk wait-poll shim tooling present"
