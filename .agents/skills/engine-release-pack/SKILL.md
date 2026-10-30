---
name: engine-release-pack
description: >-
  Pack a shipping Wine engine with Developer ID signing, dual-variant MoltenVK
  gates, and real DXVK/DXMT graphics payloads (never symlink sources). Use when
  producing Cyder012+ release tarballs or repairing adhoc/broken graphics packs
  for release.
---

# Engine release pack

Formal shipping artifacts for Cyder. Do **not** use `SIGN_IDENTITY=-` here.

## Preconditions

1. Work in the engine repo:

```bash
cd /path/to/cyder-wine-engine  # locate the sibling checkout; do not run in CyderBits
export OGOM="$PWD"   # config and build/install paths belong to the engine repo
```

2. Refuse adhoc for release packs. Require a **Developer ID Application**
   identity from the keychain (never `SIGN_IDENTITY=-`).
3. `WINE_INSTALL` must be a **real** tree — `install/wine-cx26-x86_64` or a full
   extracted engine — **never** symlink `lib/dxvk`, `lib/dxvk2`, or `lib/dxmt`.
   Symlink sources pack into stub archives; `pack-graphics-payloads.sh` refuses them.

## Commands

```bash
export WINE_INSTALL="${WINE_INSTALL:-$PWD/install/wine-cx26-x86_64}"

export SIGN_IDENTITY='Developer ID Application: …'
# Inspect existing graphics packages and choose an unused revision for changed contents.
export CYDER_GRAPHICS_PACKAGE_REVISION=cyder.1
bash scripts/pack-graphics-payloads.sh --engine "$WINE_INSTALL" \
  --channel release --revision "$CYDER_GRAPHICS_PACKAGE_REVISION"

CYDER_ENGINE_VERSION_LABEL="$(head -n 1 config/engine-version.txt)" \
  bash scripts/pack-engine-artifact.sh --zst --force
```

## DXMT source and signature policy

Read `docs/graphics-signing-policy.zh-TW.md` for the reviewed upstream pin and
regression commands. The current native policy covers DXMT upstream v0.80 only.
`graphics-signing.py` checks every upstream payload digest, signs only the
reviewed unsigned `winemetal.so` in staging, requires Cyder Developer ID plus a
secure timestamp, records original/final hashes, and verifies the archive round
trip. No loader entitlement set is copied onto the library.

- Do not sign the source/install tree or end-user runtime. Do not use ad-hoc as a
  release fallback. Previously signed/unreviewed inputs stop for policy review;
  never force-replace an upstream/Apple signature.
- Signed package names are `dxmt-0.80-cyder.N.tar.zst`; retain upstream v0.80 in
  provenance. Even `--force` verifies/reuses an existing valid DXMT revision;
  changed inputs, damaged caches or signature failures require a new revision.
- `SIGN_IDENTITY` must be exported for **both** graphics and engine commands.
  The engine pack propagates release mode for Developer ID and requires
  `CYDER_GRAPHICS_PACKAGE_REVISION`. Existing archives are not proof of signing.

## Upstream version and installation identity

DXMT's displayed/upstream version remains **0.80**. `cyder.N` in existing artifact
filenames, provenance and signing identifiers is a private build trace, not an
upstream version or the runtime update predicate. The Cyder manifest generator
computes `installKey` from archive SHA-256 **and** signature policy. A same-version
signature/content/policy change must be tested as an update, not skipped because
`.cyder-graphics-version` still says 0.80.

Runtime application belongs to CyderBits: it validates the signed publisher,
materializes a new immutable digest object, and switches only under its global
executor barrier with complete idle process evidence. Busy/unknown, unverified
source or incomplete transactions defer without replacing the selected runtime.
Do not manually overwrite `graphics/dxmt/0.80`, force-kill games, or ad-hoc-sign
installed files to bypass these guards.

## Post-checks

- Run `python3 scripts/graphics-signing.py verify-archive --archive
  dist/artifacts/graphics/dxmt-0.80-cyder.N.tar.zst --zstd <zstd-path>
  --package-version 0.80-cyder.N` (as one command). This is read-only and must
  pass before handing the package to Cyder.
- Dual MoltenVK layout present in the packed archive (shim + versioned reals).
- `codesign -dv` on `bin/wine` and MoltenVK shim/reals → Developer ID.
- `dist/artifacts/graphics/dxvk-*.tar.zst` and `dxmt-*.tar.zst` each ≫ 1 MiB
  (typical ~3.5 MiB / ~12 MiB).

## Hand-off

Give the engine manifest path **and** graphics artifacts directory to ogom.
Engine import does not automatically copy the separate graphics packages:

```bash
export CYDER_GRAPHICS_ARTIFACTS_DIR="$PWD/dist/artifacts/graphics"
```

Then:

```bash
bash scripts/import-engine-release.sh --manifest <path> --apply
```

For the full formal Cyder release (import → notarize → verify), use ogom’s
`.agents/skills/cyder-release`.

## Related

- Daily incremental build / adhoc pack: `.agents/skills/incremental-wine-build`
- Graphics gate: `scripts/pack-graphics-payloads.sh` (rejects symlink sources)
