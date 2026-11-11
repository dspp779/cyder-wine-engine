#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d /private/tmp/graphics-release-pack.XXXXXX)"
trap 'rm -rf "$TEMP"' EXIT
mkdir -p "$TEMP/bin" "$TEMP/engine/lib/dxmt/x86_64-unix" "$TEMP/engine/lib/dxvk" "$TEMP/engine/lib/dxvk2"
export FIXTURE_ENGINE="$TEMP/engine" FIXTURE_SIGN_COUNT="$TEMP/sign-count"
printf 'dxmt v0.80\n' >"$TEMP/engine/lib/dxmt/version"
printf 'dxvk v1\n' >"$TEMP/engine/lib/dxvk/version"
printf 'dxvk v2\n' >"$TEMP/engine/lib/dxvk2/version"
/usr/bin/python3 - "$TEMP/engine/lib/dxmt/x86_64-unix/winemetal.so" <<'PY'
import struct,sys
open(sys.argv[1],'wb').write(struct.pack('<8I',0xfeedfacf,0x01000007,3,6,0,0,0,0)+b'fixture')
PY
/usr/bin/python3 - "$TEMP/engine" <<'PYFIX'
import pathlib,struct,sys
root=pathlib.Path(sys.argv[1]); data=bytearray(128);data[:2]=b'MZ';struct.pack_into('<I',data,60,96);data[96:100]=b'PE\0\0'
for name in ['dxvk','dxvk2']:(root/'lib'/name/'d3d11.dll').write_bytes(data)
PYFIX
cat >"$TEMP/bin/python3" <<'PY'
#!/usr/bin/python3
# Isolated test interpreter seam; production helper has no mock environment switch.
import copy,hashlib,importlib.util,os,pathlib,subprocess,sys
if not sys.argv[1].endswith('/graphics-signing.py'):
 os.execv('/usr/bin/python3',['/usr/bin/python3']+sys.argv[1:])
spec=importlib.util.spec_from_file_location('graphics',sys.argv[1]); g=importlib.util.module_from_spec(spec); spec.loader.exec_module(g)
original=pathlib.Path(os.environ['FIXTURE_ENGINE'])/'lib/dxmt'
# This suite uses a single reviewed fixture native; data/PE cases live in the unit suite.
raw=(__import__('struct').pack('<8I',0xfeedfacf,0x01000007,3,6,0,0,0,0)+b'fixture')
g.UPSTREAM=dict(g.UPSTREAM,fileSHA256=hashlib.sha256(raw).hexdigest())
g.UPSTREAM_FILES={g.NATIVE:hashlib.sha256(raw).hexdigest()}
def command(args):
 p=pathlib.Path(args[-1]); data=p.read_bytes()
 if '--force' in args:
  p.write_bytes(data+b'SIGNED')
  with open(os.environ['FIXTURE_SIGN_COUNT'],'a') as f:f.write('signed\n')
  return subprocess.CompletedProcess(args,0,'')
 if '-R' in args:return subprocess.CompletedProcess(args,0 if data.endswith(b'SIGNED') else 1,'')
 return subprocess.CompletedProcess(args,0,'Timestamp=fixture\n')
g.command=command
sys.argv=sys.argv[1:];g.main()
PY
cat >"$TEMP/bin/zstd" <<'SH2'
#!/bin/bash
set -euo pipefail
if [[ "$1" == -dc ]]; then exec /bin/cat "$2"; fi
while [[ $# -gt 0 ]]; do
 if [[ "$1" == -o ]]; then out="$2"; shift 2; else shift; fi
done
cat >"$out"
SH2
chmod +x "$TEMP/bin/python3" "$TEMP/bin/zstd"
# env-x86_64 prepends the project Homebrew bin directory. Isolate its
# coordinates so an installed Python cannot shadow this test-only interpreter.
export HOMEBREW_PREFIX="$TEMP/empty-brew"
export HOMEBREW_REPOSITORY="$HOMEBREW_PREFIX" HOMEBREW_CELLAR="$HOMEBREW_PREFIX/Cellar"
export PATH="$TEMP/bin:$PATH" OGOM="$ROOT" CYDER_ZSTD="$TEMP/bin/zstd"
export SIGN_IDENTITY='Developer ID Application: Fixture' CYDER_GRAPHICS_CHANNEL=release CYDER_GRAPHICS_PACKAGE_REVISION=cyder.1
pack() { bash "$ROOT/scripts/pack-graphics-payloads.sh" --engine "$TEMP/engine" --output-dir "$TEMP/artifacts" "$@"; }
pack
archive="$TEMP/artifacts/dxmt-0.80-cyder.1.tar.zst"
first="$(shasum -a 256 "$archive")"
test "$(cat "$TEMP/artifacts/dxmt-version.txt")" == '0.80-cyder.1'
test "$(wc -l <"$TEMP/sign-count" | tr -d ' ')" == 1
pack --force
test "$first" == "$(shasum -a 256 "$archive")"
test "$(wc -l <"$TEMP/sign-count" | tr -d ' ')" == 1
if CYDER_GRAPHICS_CHANNEL=test CYDER_DXMT_VERSION=0.80-cyder.1 pack --force; then
  echo 'FAIL: test channel overwrote release namespace' >&2; exit 1
fi
test "$first" == "$(shasum -a 256 "$archive")"
printf 'changed source\n' >>"$TEMP/engine/lib/dxmt/version"
if pack --force; then echo 'FAIL: cached source change accepted' >&2; exit 1; fi
test "$first" == "$(shasum -a 256 "$archive")"
if SIGN_IDENTITY=- pack; then echo 'FAIL: release ad-hoc accepted' >&2; exit 1; fi
echo 'PASS: staged sign before archive, roundtrip, immutable cache even --force, changed source and ad-hoc fail closed'
