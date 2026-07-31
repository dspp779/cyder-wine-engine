#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/assert.sh"
ARCHIVE="${CX26_SOURCE_ARCHIVE:-$ROOT/tools/archives/crossover-sources-26.3.0.tar.gz}"
SOCK_PATCH="$ROOT/patches/cyder-wineserver-sock-reselect-pseudo-fd.patch"
FD_PATCH="$ROOT/patches/cyder-wineserver-poll-slot-guard.patch"
DIAG_PATCH="$ROOT/patches/cyder-wineserver-exit-diagnostics.patch"

if [[ ! -f "$ARCHIVE" ]]; then
  echo "SKIP wineserver exit diagnostics: source archive not found at $ARCHIVE"
  exit 0
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cyder-ws-diag.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

tar -xzf "$ARCHIVE" -C "$TMP_DIR" \
  sources/wine/server/fd.c \
  sources/wine/server/sock.c \
  sources/wine/server/signal.c \
  sources/wine/server/main.c \
  sources/wine/server/process.c \
  sources/wine/server/process.h
SOURCE="$TMP_DIR/sources/wine"

# Prerequisite containment patches first (same order as build-wine.sh).
patch --forward --batch -s -p1 -d "$SOURCE" < "$SOCK_PATCH"
patch --forward --batch -s -p1 -d "$SOURCE" < "$FD_PATCH"
patch --forward --batch -s -p1 -d "$SOURCE" < "$DIAG_PATCH"

# Signal handlers must record the sender pid before silent exit/shutdown.
rg -Fq 'wineserver: received signal' "$SOURCE/server/signal.c"
rg -Fq 'si->si_pid' "$SOURCE/server/signal.c"
rg -Fq 'SA_SIGINFO' "$SOURCE/server/signal.c"

# Early handlers (before init_signals) must also leave a breadcrumb.
rg -Fq 'wineserver: early signal' "$SOURCE/server/main.c"

# Normal main_loop return must dump poll and process counters.
rg -Fq 'wineserver: main_loop exiting' "$SOURCE/server/fd.c"
rg -Fq 'wineserver_log_exit_state' "$SOURCE/server/main.c"
rg -Fq 'wineserver_log_exit_state' "$SOURCE/server/process.c"
rg -Fq 'running_processes=' "$SOURCE/server/process.c"

# Stale poll slot must be impossible to miss in the launch log.
rg -Fq 'FATAL: set_fd_events: stale poll slot' "$SOURCE/server/fd.c"
rg -Fq 'fflush( stderr )' "$SOURCE/server/fd.c"

# Round-trip the diagnostic patch alone (poll/sock stay applied).
FD_SHA="$(shasum -a 256 "$SOURCE/server/fd.c" | awk '{print $1}')"
SIG_SHA="$(shasum -a 256 "$SOURCE/server/signal.c" | awk '{print $1}')"
MAIN_SHA="$(shasum -a 256 "$SOURCE/server/main.c" | awk '{print $1}')"
PROC_SHA="$(shasum -a 256 "$SOURCE/server/process.c" | awk '{print $1}')"
PROCH_SHA="$(shasum -a 256 "$SOURCE/server/process.h" | awk '{print $1}')"

patch --reverse --batch -s -p1 -d "$SOURCE" < "$DIAG_PATCH"
# Without diagnostics the FATAL marker must disappear again.
if rg -Fq 'FATAL: set_fd_events: stale poll slot' "$SOURCE/server/fd.c"; then
  echo "FAIL: FATAL marker remained after reversing diagnostics" >&2
  exit 1
fi
rg -Fq 'stale poll slot' "$SOURCE/server/fd.c"

patch --forward --batch -s -p1 -d "$SOURCE" < "$DIAG_PATCH"
assert_eq "$(shasum -a 256 "$SOURCE/server/fd.c" | awk '{print $1}')" "$FD_SHA" \
  "fd.c diagnostics round-trip"
assert_eq "$(shasum -a 256 "$SOURCE/server/signal.c" | awk '{print $1}')" "$SIG_SHA" \
  "signal.c diagnostics round-trip"
assert_eq "$(shasum -a 256 "$SOURCE/server/main.c" | awk '{print $1}')" "$MAIN_SHA" \
  "main.c diagnostics round-trip"
assert_eq "$(shasum -a 256 "$SOURCE/server/process.c" | awk '{print $1}')" "$PROC_SHA" \
  "process.c diagnostics round-trip"
assert_eq "$(shasum -a 256 "$SOURCE/server/process.h" | awk '{print $1}')" "$PROCH_SHA" \
  "process.h diagnostics round-trip"

echo "PASS wineserver exit diagnostics patch round-trip"
