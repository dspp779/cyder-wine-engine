#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cyder-kit-media.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
source "$ROOT/tools/test-runtime-kit/prepare-media-environment.sh"
unset GST_PLUGIN_PATH_1_0 GST_PLUGIN_SYSTEM_PATH_1_0 GST_PLUGIN_SCANNER_1_0 GST_PLUGIN_SCANNER GST_PLUGIN_PATH GST_PLUGIN_SYSTEM_PATH GST_REGISTRY_1_0 GST_REGISTRY
engine="$TMP/engine with spaces"
mkdir -p "$engine/lib/wine/gstreamer-1.0" "$engine/lib/wine/x86_64-unix" "$engine/libexec/gstreamer-1.0"
: > "$engine/lib/wine/x86_64-unix/libgstreamer-1.0.0.dylib"
printf '#!/bin/sh\nexit 0\n' > "$engine/libexec/gstreamer-1.0/gst-plugin-scanner"
chmod +x "$engine/libexec/gstreamer-1.0/gst-plugin-scanner"
test_runtime_prepare_media_environment "$engine" "$TMP/test-root"
[[ "$GST_PLUGIN_PATH_1_0" == "$engine/lib/wine/gstreamer-1.0" && "$GST_PLUGIN_SYSTEM_PATH_1_0" == "$GST_PLUGIN_PATH_1_0" ]]
[[ "$GST_PLUGIN_SCANNER" == "$engine/libexec/gstreamer-1.0/gst-plugin-scanner" ]]
[[ "$GST_REGISTRY_1_0" == "$TMP/test-root/cache/gstreamer/registry-x86_64-"*.bin ]]
unset GST_PLUGIN_PATH_1_0 GST_PLUGIN_SYSTEM_PATH_1_0 GST_PLUGIN_SCANNER GST_REGISTRY_1_0
GST_PLUGIN_PATH='';export GST_PLUGIN_PATH
test_runtime_prepare_media_environment "$engine" "$TMP/test-root"
[[ ! ${GST_PLUGIN_SCANNER+x} && ! ${GST_PLUGIN_PATH_1_0+x} ]]
unset GST_PLUGIN_PATH
export GST_PLUGIN_SCANNER_1_0=/external/scanner
test_runtime_prepare_media_environment "$engine" "$TMP/test-root"
[[ ! ${GST_PLUGIN_SCANNER+x} && ! ${GST_PLUGIN_PATH_1_0+x} ]]
unset GST_PLUGIN_SCANNER_1_0
export GST_REGISTRY=/external/registry
test_runtime_prepare_media_environment "$engine" "$TMP/test-root"
[[ ! ${GST_REGISTRY_1_0+x} && "$GST_REGISTRY" == /external/registry ]]
unset GST_PLUGIN_PATH_1_0 GST_PLUGIN_SYSTEM_PATH_1_0 GST_PLUGIN_SCANNER
rm -f "$engine/libexec/gstreamer-1.0/gst-plugin-scanner"
test_runtime_prepare_media_environment "$engine" "$TMP/test-root"
[[ ! ${GST_PLUGIN_SCANNER+x} && ! ${GST_PLUGIN_PATH_1_0+x} ]]
echo 'PASS test-runtime media: bundled stack, task-local cache, spaces, external/empty overrides and incomplete runtime'
