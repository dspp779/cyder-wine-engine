#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/assert.sh"

builder="$ROOT_DIR/scripts/build-media-stack.sh"
assert bash -n "$builder"

help_output="$(bash "$builder" --help)"
assert_contains "$help_output" "--profile minimal|full-video" \
  "media builder should expose explicit profiles"
assert_contains "$help_output" "--full-video" \
  "media builder should expose the full-video shortcut"
assert_contains "$help_output" "--media-install PATH" \
  "media builder should allow isolated profile installs"

builder_text="$(<"$builder")"
assert_contains "$builder_text" "MEDIA_PROFILE=minimal" \
  "minimal media profile should remain the default"
assert_contains "$builder_text" "-Dgst-plugins-bad:applemedia=enabled" \
  "full-video profile should include Apple media"
assert_contains "$builder_text" "-Dgst-plugins-bad:gl=enabled" \
  "Apple media should link against GStreamer OpenGL support"
assert_contains "$builder_text" "-Dgst-plugins-ugly:asfdemux=enabled" \
  "full-video profile should include ASF demuxing"
assert_contains "$builder_text" "-Dgst-plugins-good:isomp4=enabled" \
  "full-video profile should include ISO MP4"
assert_contains "$builder_text" "-Dgst-plugins-bad:videoparsers=enabled" \
  "full-video profile should include video parsers"
assert_contains "$builder_text" "-Dlibav=disabled" \
  "full-video profile should remain independent of an FFmpeg build"
assert_contains "$builder_text" "libgstapplemedia.dylib" \
  "full-video validation should check installed plugins"
assert_contains "$builder_text" "-Dtools=enabled" \
  "full-video profile should include the GStreamer plugin scanner"
assert_contains "$builder_text" "gst-plugin-scanner" \
  "full-video validation should check the plugin scanner"

echo "test-build-media-stack: PASS"
