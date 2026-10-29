#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/assert.sh"
graphics_pack="$(cat "$ROOT/scripts/pack-graphics-payloads.sh")"
engine_pack="$(cat "$ROOT/scripts/pack-engine-artifact.sh")"
assert_contains "$graphics_pack" 'lib/dxmt' \
  "graphics pack must require the DXMT payload"
assert_contains "$graphics_pack" 'lib/dxvk2' \
  "graphics pack must require the DXVK2 payload"
assert_contains "$engine_pack" "pack-graphics-payloads.sh" \
  "engine pack must create graphics payloads before stripping the engine"
assert_contains "$engine_pack" "--exclude 'lib/dxmt'" \
  "engine archive must exclude DXMT"
assert_contains "$engine_pack" "--exclude 'lib/dxvk'" \
  "engine archive must exclude DXVK"
assert_contains "$engine_pack" 'MEDIA_PROFILE="${CYDER_ENGINE_MEDIA_PROFILE:-full-video}"' \
  "release engine packing should default to the full-video media profile"
assert_contains "$engine_pack" '--media-profile)' \
  "engine packing should expose an explicit minimal media fallback"
assert_contains "$engine_pack" 'gst-plugin-scanner' \
  "full-video engine packing should require the GStreamer plugin scanner"

graphics_pack_line="$(rg -n -F 'bash "$SCRIPT_DIR/pack-graphics-payloads.sh" "${graphics_pack_args[@]}"' \
  "$ROOT/scripts/pack-engine-artifact.sh" | cut -d: -f1)"
archive_exit_line="$(rg -n -F 'if [[ -f "$ARCHIVE" && "$FORCE" -ne 1 ]]; then' \
  "$ROOT/scripts/pack-engine-artifact.sh" | cut -d: -f1)"
[[ "$graphics_pack_line" -lt "$archive_exit_line" ]] || {
  echo "ASSERT failed: existing engine archive must not bypass graphics packing" >&2
  exit 1
}

tmp="$(mktemp -d "${TMPDIR:-/tmp}/cyder-engine-pack-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
engine="$tmp/engine"
artifacts="$tmp/artifacts"
fake_zstd="$tmp/zstd"
mkdir -p "$engine/bin" "$engine/lib/dxvk" "$engine/lib/dxvk2" "$engine/lib/dxmt" \
  "$engine/lib/wine/x86_64-unix" "$artifacts"
touch "$engine/bin/wine" "$artifacts/engine-wine-x86_64-test.tar.xz"
printf 'CYDER_GRAPHICS_BACKEND_PATH\n' >"$engine/lib/wine/x86_64-unix/cxcompatdb.so"
chmod +x "$engine/bin/wine"

python3 - "$engine/lib/dxvk/d3d11.dll" <<'PY'
import struct
import sys

contents = bytearray(128)
contents[:2] = b"MZ"
struct.pack_into("<I", contents, 60, 96)
contents[96:100] = b"PE\0\0"
open(sys.argv[1], "wb").write(contents)
PY
cp "$engine/lib/dxvk/d3d11.dll" "$engine/lib/dxvk2/d3d11.dll"
printf 'dxmt\n' >"$engine/lib/dxmt/payload"
cat >"$fake_zstd" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) output="$2"; shift 2 ;;
    *) shift ;;
  esac
done
cat >"$output"
EOF
chmod +x "$fake_zstd"

# Full-video must still fail closed without its media payload. The graphics-only
# fixture below explicitly opts into minimal instead of depending on this host.
if MEDIA_INSTALL="$tmp/missing-media" CYDER_ENGINE_ARTIFACTS_DIR="$artifacts" \
   CYDER_ENGINE_VERSION_LABEL=test CYDER_ZSTD="$fake_zstd" WINE_INSTALL="$engine" \
   bash "$ROOT/scripts/pack-engine-artifact.sh" --media-profile full-video >"$tmp/media-error" 2>&1; then
  echo 'full-video pack accepted missing media' >&2; exit 1
fi
assert_contains "$(cat "$tmp/media-error")" 'Missing full-video GStreamer plugins' \
  'full-video media requirement must remain enforced'

CYDER_ENGINE_ARTIFACTS_DIR="$artifacts" CYDER_ENGINE_VERSION_LABEL="test" \
  CYDER_ZSTD="$fake_zstd" WINE_INSTALL="$engine" \
  bash "$ROOT/scripts/pack-engine-artifact.sh" --media-profile minimal
assert test -f "$artifacts/graphics/dxvk-unknown.tar.zst"
assert test -f "$artifacts/graphics/dxmt-unknown.tar.zst"
assert test -f "$artifacts/graphics/dxvk2-unknown.tar.zst"
assert test -f "$artifacts/graphics/dxvk-version.txt"
assert test -f "$artifacts/graphics/dxmt-version.txt"
assert test -f "$artifacts/graphics/dxvk-artifact-sha256.txt"
assert test -f "$artifacts/graphics/dxmt-artifact-sha256.txt"

# Exercise the production compression branch with a real zstd binary. Existing
# tests stop at the archive-present early exit and cannot catch --force failing
# to reach the compressor's overwrite option.
source "$ROOT/scripts/engine-common.sh"
real_zstd="$(cyder_find_zstd)"
python3 - "$ROOT/scripts/pack-engine-artifact.sh" "$real_zstd" <<'PYTEST'
import io, os, pathlib, subprocess, sys, tarfile, tempfile
s = pathlib.Path(sys.argv[1]).read_text()
a = s.index('case "$FORMAT" in\n  zst)\n    echo "==> Compressing')
b = s.index('# Verify the archive itself', a)
branch = s[a:b]
with tempfile.TemporaryDirectory(prefix='cyder-engine-compress-') as tmp:
    root = pathlib.Path(tmp)
    (root / 'wine-x86_64').mkdir()
    (root / 'wine-x86_64/payload').write_text('new payload\n')
    archive = root / 'engine.tar.zst'
    archive.write_bytes(b'keep old archive')
    env = dict(os.environ, FORMAT='zst', STAGING=str(root), ARCHIVE=str(archive), ZSTD_BIN=sys.argv[2])
    def run(force):
        return subprocess.run(['bash', '-c', 'set -euo pipefail\n' + branch],
                              env=dict(env, FORCE=str(force)), stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    denied = run(0)
    assert denied.returncode != 0 and archive.read_bytes() == b'keep old archive'
    replaced = run(1)
    assert replaced.returncode == 0, replaced.stdout.decode()
    data = subprocess.check_output([sys.argv[2], '-dc', str(archive)])
    with tarfile.open(fileobj=io.BytesIO(data)) as tf:
        assert tf.extractfile('wine-x86_64/payload').read() == b'new payload\n'
print('PASS real zstd: --force replaces existing archive; default preserves it')
PYTEST

echo "PASS test-pack-engine-dxmt-gate"
