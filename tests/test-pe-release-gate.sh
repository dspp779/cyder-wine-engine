#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d /private/tmp/cyder-pe-release-gate.XXXXXX)"
trap 'rm -rf "$TEMP"' EXIT
mkdir -p "$TEMP/engine/bin" "$TEMP/engine/lib/wine/x86_64-unix" "$TEMP/media" "$TEMP/artifacts"
printf '#!/bin/sh\nexit 0\n' >"$TEMP/engine/bin/wine"
chmod +x "$TEMP/engine/bin/wine"
printf 'CYDER_GRAPHICS_BACKEND_PATH\n' >"$TEMP/engine/lib/wine/x86_64-unix/cxcompatdb.so"
# Stub only graphics packaging in an isolated copy; never invoke real signing.
mkdir -p "$TEMP/project/scripts"
cp "$ROOT/scripts/pack-engine-artifact.sh" "$ROOT/scripts/engine-common.sh" \
  "$ROOT/scripts/env-x86_64.sh" "$ROOT/scripts/pe-signing.py" "$TEMP/project/scripts/"
cat >"$TEMP/project/scripts/pack-graphics-payloads.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" >>"$CYDER_TEST_GRAPHICS_CALLS"
STUB
printf 'existing archive\n' >"$TEMP/artifacts/engine-wine-x86_64-fixture.tar.xz"
run_pack() {
  env -u CYDER_PE_SIGNING_POLICY -u CYDER_PE_SIGNER -u CYDER_PE_VERIFY_TOOL \
    SIGN_IDENTITY='Developer ID Application: Fixture' CYDER_GRAPHICS_PACKAGE_REVISION=cyder.1 \
    OGOM="$TEMP/project" WINE_INSTALL="$TEMP/engine" MEDIA_INSTALL="$TEMP/media" \
    CYDER_ENGINE_MEDIA_PROFILE=minimal CYDER_ENGINE_VERSION_LABEL=fixture \
    CYDER_ENGINE_ARTIFACTS_DIR="$TEMP/artifacts" CYDER_TEST_GRAPHICS_CALLS="$TEMP/graphics-calls" \
    "$@" bash "$TEMP/project/scripts/pack-engine-artifact.sh"
}
# Default/off Apple Developer ID packs must reach the existing graphics release path
# without ANY PE certificate settings. No producer bytes are modified by this fixture.
run_pack env -u CYDER_PE_SIGNING >"$TEMP/default.log" 2>&1
rg -q 'Engine artifact present' "$TEMP/default.log"
rg -q '^release$' "$TEMP/graphics-calls"
rm "$TEMP/graphics-calls"
# Stale/bogus policy variables alone never opt in or trigger signing.
run_pack env CYDER_PE_SIGNING=off CYDER_PE_SIGNING_POLICY=/missing/policy >"$TEMP/off.log" 2>&1
rg -q 'Engine artifact present' "$TEMP/off.log"
rm "$TEMP/graphics-calls"
# Explicit opt-in must fail before graphics packing or archive reuse when unconfigured.
if run_pack env CYDER_PE_SIGNING=required >"$TEMP/required.log" 2>&1; then
  echo 'FAIL: explicit PE signing accepted missing configuration' >&2; exit 1
fi
rg -q 'reviewed PE signing policy' "$TEMP/required.log"
test ! -e "$TEMP/graphics-calls"
if run_pack env CYDER_PE_SIGNING=typo >"$TEMP/invalid.log" 2>&1; then
  echo 'FAIL: invalid PE mode accepted' >&2; exit 1
fi
rg -q 'Invalid CYDER_PE_SIGNING' "$TEMP/invalid.log"
test ! -e "$TEMP/graphics-calls"
test "$(cat "$TEMP/artifacts/engine-wine-x86_64-fixture.tar.xz")" = 'existing archive'
# Full pack fixture with Apple/graphics operations stubbed; real tar/xz and manifest.
mkdir -p "$TEMP/project/config" "$TEMP/engine/lib/wine/x86_64-windows"
cp "$ROOT/config/engine-release.json" "$TEMP/project/config/"
cp "$ROOT/scripts/write-engine-manifest.sh" "$TEMP/project/scripts/"
for helper in strip-wine-install.sh bundle-wine-dylibs.sh sign-wine.sh; do
  printf '#!/usr/bin/env bash\nexit 0\n' >"$TEMP/project/scripts/$helper"
done
printf 'import sys\nsys.exit(0)\n' >"$TEMP/project/scripts/pack-minos-scan.py"
printf 'fixture ntdll\n' >"$TEMP/engine/lib/wine/x86_64-windows/ntdll.dll"
printf 'preserve upstream bytes\n' >"$TEMP/engine/lib/wine/x86_64-windows/upstream.dll"
printf '{"status":"stale-unverified-input"}\n' >"$TEMP/engine/cyder-pe-provenance.json"
run_pack env -u CYDER_PE_SIGNING CYDER_ENGINE_VERSION_LABEL=fixture-new >"$TEMP/full.log" 2>&1
mkdir "$TEMP/unpacked"
tar -xJf "$TEMP/artifacts/engine-wine-x86_64-fixture-new.tar.xz" -C "$TEMP/unpacked"
test ! -e "$TEMP/unpacked/wine-x86_64/cyder-pe-provenance.json"
cmp "$TEMP/engine/lib/wine/x86_64-windows/upstream.dll" "$TEMP/unpacked/wine-x86_64/lib/wine/x86_64-windows/upstream.dll"
test "$(cat "$TEMP/engine/cyder-pe-provenance.json")" = '{"status":"stale-unverified-input"}'
python3 - "$TEMP" <<'PYTEST'
import json,pathlib,sys
root=pathlib.Path(sys.argv[1])
for p in [root/'unpacked/wine-x86_64/engine-manifest.json',root/'artifacts/engine-wine-x86_64-fixture-new.tar.xz.manifest.json']:
    assert 'peAuthenticode' not in json.loads(p.read_text())
PYTEST
# A failed PE round-trip must not leave a final-path artifact for later cache reuse.
cat >"$TEMP/project/scripts/pe-signing.py" <<'STUB'
import pathlib,sys
if sys.argv[1] == 'prepare':
    root=pathlib.Path(sys.argv[sys.argv.index('--root')+1])
    (root/'cyder-pe-provenance.json').write_text('{}')
if sys.argv[1] == 'verify':
    sys.exit(1)
STUB
if run_pack env CYDER_PE_SIGNING=required CYDER_PE_SIGNING_POLICY="$TEMP/policy.json" \
  CYDER_ENGINE_VERSION_LABEL=fixture-rejected >"$TEMP/rejected.log" 2>&1; then
  echo 'FAIL: injected PE round-trip rejection accepted' >&2; exit 1
fi
test ! -e "$TEMP/artifacts/engine-wine-x86_64-fixture-rejected.tar.xz"
test ! -e "$TEMP/artifacts/engine-wine-x86_64-fixture-rejected.tar.xz.sha256"
# A failed --force pack must retain the previous verified archive and sidecars.
python3 - "$TEMP" <<'PYTEST'
import hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1]);artifacts=root/'artifacts'
paths=['engine-wine-x86_64-fixture-new.tar.xz'+suffix for suffix in ['', '.sha256', '.manifest.json']]+['engine-version.txt','.pack-stamp']
json.dump({n:hashlib.sha256((artifacts/n).read_bytes()).hexdigest() for n in paths},open(root/'before-force.json','w'))
PYTEST
printf 'new candidate content\n' >"$TEMP/engine/lib/wine/x86_64-windows/upstream.dll"
mkdir -p "$TEMP/reject-tools"
printf '#!/bin/sh\necho Mach-O\n' >"$TEMP/reject-tools/file"
printf '#!/bin/sh\nexit 1\n' >"$TEMP/reject-tools/codesign"
chmod +x "$TEMP/reject-tools/file" "$TEMP/reject-tools/codesign"
if env -u CYDER_PE_SIGNING SIGN_IDENTITY='Developer ID Application: Fixture' \
  OGOM="$TEMP/project" WINE_INSTALL="$TEMP/engine" MEDIA_INSTALL="$TEMP/media" \
  CYDER_ENGINE_MEDIA_PROFILE=minimal CYDER_ENGINE_VERSION_LABEL=fixture-new \
  CYDER_ENGINE_ARTIFACTS_DIR="$TEMP/artifacts" CYDER_GRAPHICS_PACKAGE_REVISION=cyder.1 \
  CYDER_TEST_GRAPHICS_CALLS="$TEMP/graphics-calls" PATH="$TEMP/reject-tools:$PATH" \
  bash "$TEMP/project/scripts/pack-engine-artifact.sh" --force >"$TEMP/force-rejected.log" 2>&1; then
  echo 'FAIL: injected Mach-O round-trip rejection accepted' >&2; exit 1
fi
python3 - "$TEMP" <<'PYTEST'
import hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1]);before=json.load(open(root/'before-force.json'))
for n,sha in before.items():
    assert hashlib.sha256((root/'artifacts'/n).read_bytes()).hexdigest()==sha, n+' changed despite rejected candidate'
assert not list((root/'artifacts').glob('.cyder-engine-publish.*'))
PYTEST
# A lock owned by another pack must remain intact and block publication.
mkdir "$TEMP/artifacts/engine-wine-x86_64-fixture-locked.tar.xz.pack-lock"
if run_pack env -u CYDER_PE_SIGNING CYDER_ENGINE_VERSION_LABEL=fixture-locked >"$TEMP/locked.log" 2>&1; then
  echo 'FAIL: concurrent publisher was not blocked' >&2; exit 1
fi
rg -q 'pack lock needs inspection' "$TEMP/locked.log"
test -d "$TEMP/artifacts/engine-wine-x86_64-fixture-locked.tar.xz.pack-lock"
test ! -e "$TEMP/artifacts/engine-wine-x86_64-fixture-locked.tar.xz"
rmdir "$TEMP/artifacts/engine-wine-x86_64-fixture-locked.tar.xz.pack-lock"
# A successful --force can publish the changed candidate, with matching sidecars.
env -u CYDER_PE_SIGNING SIGN_IDENTITY='Developer ID Application: Fixture' \
  OGOM="$TEMP/project" WINE_INSTALL="$TEMP/engine" MEDIA_INSTALL="$TEMP/media" \
  CYDER_ENGINE_MEDIA_PROFILE=minimal CYDER_ENGINE_VERSION_LABEL=fixture-new \
  CYDER_ENGINE_ARTIFACTS_DIR="$TEMP/artifacts" CYDER_GRAPHICS_PACKAGE_REVISION=cyder.1 \
  CYDER_TEST_GRAPHICS_CALLS="$TEMP/graphics-calls" \
  bash "$TEMP/project/scripts/pack-engine-artifact.sh" --force >"$TEMP/force-success.log" 2>&1
python3 - "$TEMP" <<'PYTEST'
import hashlib,json,pathlib,sys,tarfile
root=pathlib.Path(sys.argv[1]);archive=root/'artifacts/engine-wine-x86_64-fixture-new.tar.xz'
sha=hashlib.sha256(archive.read_bytes()).hexdigest()
assert sha!=json.load(open(root/'before-force.json'))[archive.name]
assert sha==archive.with_name(archive.name+'.sha256').read_text().split()[0]
assert sha==json.load(open(str(archive)+'.manifest.json'))['artifactSHA256']
with tarfile.open(archive) as tar:
    assert tar.extractfile('wine-x86_64/lib/wine/x86_64-windows/upstream.dll').read()==b'new candidate content\n'
assert not list((root/'artifacts').glob('*.pack-lock'))
assert not list((root/'artifacts').glob('.cyder-engine-publish.*'))
PYTEST
# Check the stage/round-trip ordering at the actual production call sites.
python3 - "$ROOT" <<'PY'
import pathlib,sys
root=pathlib.Path(sys.argv[1]);text=(root/'scripts/pack-engine-artifact.sh').read_text()
strip=text.index('bash "$SCRIPT_DIR/strip-wine-install.sh"')
pe=text.index('pe-signing.py" prepare')
ntdll=text.index('NTDLL_SHA256="$(shasum')
manifest=text.index('bash "$SCRIPT_DIR/write-engine-manifest.sh"')
compress=text.index('echo "==> Compressing')
roundtrip=text.index('pe-signing.py" verify')
sidecar=text.index('ARTIFACT_SHA256="$(shasum')
assert strip < pe < ntdll < manifest < compress < roundtrip < sidecar
assert text.count('--pe-provenance-sha256 "$PE_PROVENANCE_SHA256"') == 2
assert 'Refusing to reuse/overwrite a PE-signed engine archive' in text
PY
# Disabled mode excludes old PE provenance from the copied source tree.
rg -q -- "--exclude '/cyder-pe-provenance.json'" "$ROOT/scripts/pack-engine-artifact.sh"
# Manifest records only actual verified provenance, never a static release claim.
sha="$(printf 'a%.0s' {1..64})"
bash "$ROOT/scripts/write-engine-manifest.sh" --output "$TEMP/manifest.json" --version fixture \
  --ntdll-sha256 "$sha" --pe-provenance-sha256 "$sha" >/dev/null
python3 - "$TEMP/manifest.json" "$sha" <<'PY'
import json,sys
m=json.load(open(sys.argv[1]));assert m['peAuthenticode']['sha256']==sys.argv[2]
PY
# A default/unsigned pack must not inherit a signing claim from release config.
python3 - "$ROOT/config/engine-release.json" "$TEMP/config.json" <<'PYTEST'
import json,sys
m=json.load(open(sys.argv[1]));m['peAuthenticode']={'status':'verified','sha256':'stale'}
json.dump(m,open(sys.argv[2],'w'))
PYTEST
bash "$ROOT/scripts/write-engine-manifest.sh" --output "$TEMP/default-manifest.json" \
  --version fixture --config "$TEMP/config.json" --ntdll-sha256 "$sha" --pe-provenance-sha256 '' >/dev/null
python3 - "$TEMP/default-manifest.json" <<'PYTEST'
import json,sys
assert 'peAuthenticode' not in json.load(open(sys.argv[1]))
PYTEST
if bash "$ROOT/scripts/write-engine-manifest.sh" --output "$TEMP/bad.json" --version fixture \
  --ntdll-sha256 "$sha" --pe-provenance-sha256 bad >"$TEMP/bad.log" 2>&1; then
  echo 'FAIL: invalid PE provenance digest accepted' >&2;exit 1
fi
test ! -e "$TEMP/bad.json"
echo 'PASS: optional PE mode, Developer ID default without PE credentials, fail-closed opt-in and manifest binding'
