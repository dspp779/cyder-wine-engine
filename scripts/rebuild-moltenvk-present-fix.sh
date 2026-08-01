#!/usr/bin/env bash
# Point legacy name at the Cyder MoltenVK rebuild entrypoint.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/rebuild-moltenvk-cyder-patches.sh" "$@"
