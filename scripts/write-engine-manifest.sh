#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

OUTPUT=""
VERSION_LABEL=""
NTDLL_SHA256=""
ARTIFACT=""
ARTIFACT_SHA256=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) OUTPUT="$2"; shift 2 ;;
    --version) VERSION_LABEL="$2"; shift 2 ;;
    --ntdll-sha256) NTDLL_SHA256="$2"; shift 2 ;;
    --artifact) ARTIFACT="$2"; shift 2 ;;
    --artifact-sha256) ARTIFACT_SHA256="$2"; shift 2 ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

[[ -n "$OUTPUT" && -n "$VERSION_LABEL" && -n "$NTDLL_SHA256" ]] || {
  echo "Usage: $(basename "$0") --output FILE --version LABEL --ntdll-sha256 HEX [--artifact NAME --artifact-sha256 HEX]" >&2
  exit 1
}
[[ "$VERSION_LABEL" =~ ^[A-Za-z0-9._()[:space:]-]+$ ]] || {
  echo "Unsafe engine version label: $VERSION_LABEL" >&2
  exit 1
}
[[ "$NTDLL_SHA256" =~ ^[0-9a-f]{64}$ ]] || {
  echo "Invalid NTDLL SHA-256" >&2
  exit 1
}
if [[ -n "$ARTIFACT_SHA256" && ! "$ARTIFACT_SHA256" =~ ^[0-9a-f]{64}$ ]]; then
  echo "Invalid artifact SHA-256" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT")"
cat >"$OUTPUT" <<EOF
{
  "schemaVersion": 1,
  "engineId": "cx26.3-w11-cyder007",
  "versionLabel": "$VERSION_LABEL",
  "base": {
    "crossover": "26.3.0",
    "wine": "11.0"
  },
  "hostArchitecture": "x86_64",
  "windowsArchitectures": ["i386", "x86_64"],
  "minimumCyderVersion": "0.8.3",
  "ntdllSHA256": "$NTDLL_SHA256",
  "artifact": $(if [[ -n "$ARTIFACT" ]]; then printf '"%s"' "$ARTIFACT"; else printf 'null'; fi),
  "artifactSHA256": $(if [[ -n "$ARTIFACT_SHA256" ]]; then printf '"%s"' "$ARTIFACT_SHA256"; else printf 'null'; fi),
  "patches": [
    "cyder-compatdb-runtime.patch",
    "wine-11.1-rtlwalkframechain-null-function.patch",
    "cyder-ntdll-frame-walk-page-fault-guard.patch",
    "cyder-wineserver-sock-reselect-pseudo-fd.patch",
    "cyder-wineserver-poll-slot-guard.patch"
  ]
}
EOF

plutil -convert json -o /dev/null -- "$OUTPUT"
echo "Wrote engine manifest: $OUTPUT"
