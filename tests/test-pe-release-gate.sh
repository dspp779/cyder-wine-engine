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
