#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/assert.sh"

help="$(bash "$ROOT/scripts/pack-graphics-payloads.sh" --help)"
assert_contains "$help" "dxvk" "graphics pack help must list DXVK"
assert_contains "$help" "dxvk2" "graphics pack help must list DXVK2"
assert_contains "$help" "dxmt" "graphics pack help must list DXMT"

pack="$(<"$ROOT/scripts/pack-graphics-payloads.sh")"
assert_contains "$pack" "stamp-wine-builtin-pe.py" \
  "graphics pack must stamp staged DXVK DLLs as Wine builtins"
assert_contains "$pack" 'artifact-sha256.txt' \
  "graphics pack must write artifact checksum sidecars"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/cyder-graphics-pack-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
engine="$tmp/engine"
output_dir="$tmp/relative-output"
fake_zstd="$tmp/zstd"
mkdir -p "$engine/lib/dxvk" "$engine/lib/dxvk2" "$engine/lib/dxmt"

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

(
  cd "$tmp"
  CYDER_ZSTD="$fake_zstd" bash "$ROOT/scripts/pack-graphics-payloads.sh" \
    --engine "$engine" --output-dir "$(basename "$output_dir")"
)
assert test -f "$output_dir/dxvk-unknown.tar.zst"
assert test -f "$output_dir/dxvk2-unknown.tar.zst"
assert test -f "$output_dir/dxmt-unknown.tar.zst"
assert test -f "$output_dir/dxvk-version.txt"
assert test -f "$output_dir/dxvk2-version.txt"
assert test -f "$output_dir/dxmt-version.txt"
assert test -f "$output_dir/dxvk-artifact-sha256.txt"
assert test -f "$output_dir/dxvk2-artifact-sha256.txt"
assert test -f "$output_dir/dxmt-artifact-sha256.txt"

# --force must replace existing archives instead of leaving zstd to fail on
# its protected output path.
(
  cd "$tmp"
  CYDER_ZSTD="$fake_zstd" bash "$ROOT/scripts/pack-graphics-payloads.sh" \
    --engine "$engine" --output-dir "$(basename "$output_dir")" --force
)
assert test -f "$output_dir/dxvk-unknown.tar.zst"
assert test -f "$output_dir/dxvk2-unknown.tar.zst"
assert test -f "$output_dir/dxmt-unknown.tar.zst"

# Symlink payload source must be rejected
sym_engine="$tmp/sym-engine"
mkdir -p "$sym_engine/lib" "$tmp/real-dxvk" "$tmp/real-dxvk2" "$tmp/real-dxmt"
printf 'x\n' >"$tmp/real-dxvk/f"
printf 'x\n' >"$tmp/real-dxvk2/f"
printf 'x\n' >"$tmp/real-dxmt/f"
ln -s "$tmp/real-dxvk" "$sym_engine/lib/dxvk"
ln -s "$tmp/real-dxvk2" "$sym_engine/lib/dxvk2"
ln -s "$tmp/real-dxmt" "$sym_engine/lib/dxmt"
set +e
sym_out="$(
  CYDER_ZSTD="$fake_zstd" bash "$ROOT/scripts/pack-graphics-payloads.sh" \
    --engine "$sym_engine" --output-dir "$tmp/sym-out" --force 2>&1
)"
sym_status=$?
set -e
if [[ "$sym_status" -eq 0 ]]; then
  echo "ASSERT failed: symlink dxvk/dxmt sources must fail" >&2
  exit 1
fi
assert_contains "$sym_out" "Refusing symlinked" \
  "pack must refuse symlink graphics sources with a clear message"

echo "PASS test-pack-graphics-payloads"
