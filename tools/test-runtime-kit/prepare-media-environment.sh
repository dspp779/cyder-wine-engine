#!/bin/bash
# Source after selecting the verified task-owned engine/root. No global cache.
test_runtime_prepare_media_environment() {
  local engine="$1" root="$2"
  local plugins="$1/lib/wine/gstreamer-1.0"
  local scanner="$1/libexec/gstreamer-1.0/gst-plugin-scanner"
  # Keep intentional caller overrides (including empty paths and legacy aliases)
  # as one external stack; never combine its scanner with bundled plugins.
  if [[ "${GST_PLUGIN_PATH_1_0+x}${GST_PLUGIN_SYSTEM_PATH_1_0+x}${GST_PLUGIN_SCANNER_1_0+x}${GST_PLUGIN_SCANNER+x}${GST_PLUGIN_PATH+x}${GST_PLUGIN_SYSTEM_PATH+x}" == *x* ]]; then
    return 0
  fi
  [[ -d "$plugins" && -x "$scanner" && -f "$engine/lib/wine/x86_64-unix/libgstreamer-1.0.0.dylib" ]] || return 0
  export GST_PLUGIN_PATH_1_0="$plugins" GST_PLUGIN_SYSTEM_PATH_1_0="$plugins"
  export GST_PLUGIN_SCANNER="$scanner"
  if [[ "${GST_REGISTRY_1_0+x}${GST_REGISTRY+x}" != *x* ]]; then
    local identity
    identity="$(printf '%s\n' "$engine" | /usr/bin/cksum | awk '{print $1}')"
    mkdir -p "$root/cache/gstreamer"
    export GST_REGISTRY_1_0="$root/cache/gstreamer/registry-x86_64-$identity.bin"
  fi
}
