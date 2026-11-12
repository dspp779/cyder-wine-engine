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

## Optional PE Authenticode

Read `docs/pe-authenticode-release-signing.zh-TW.md` when PE signing is requested.
`CYDER_PE_SIGNING=off` is the default: Apple Developer ID release packs do not
require an Authenticode purchase, policy, signer or PE verifier. Keep the normal
Apple signing/notarization and graphics release checks; preserve upstream PE
signatures unchanged, including while stripping debug data. Unsigned PE alone
is not an integrity failure, and prefix integrity diagnostics remain necessary.

Only explicit `CYDER_PE_SIGNING=required` enables PE signing. It then requires
a reviewed policy, provider adapter, osslsigncode and code-signing/TSA trust
stores. Missing configuration or failed verification stops that opt-in pack;
never silently downgrade or substitute test certificates. Credentials/provider
adapter are not provisioned and are not required for the default workflow.

When opted in, sign reviewed Cyder-built PE in staging after stripping, generate
final hashes/provenance and verify the extracted archive. Existing archives are
not reused/overwritten in this mode even with `--force`; use an unused label.
Default off retains existing cache/force behavior without a PE verification claim.

## Commands

```bash
export WINE_INSTALL="${WINE_INSTALL:-$PWD/install/wine-cx26-x86_64}"

export SIGN_IDENTITY='Developer ID Application: …'
# Unchanged upstream DXMT reuses the existing signed dxmt-0.80.tar.zst.
bash scripts/pack-graphics-payloads.sh --engine "$WINE_INSTALL" --channel release

CYDER_ENGINE_VERSION_LABEL="$(head -n 1 config/engine-version.txt)" \
  bash scripts/pack-engine-artifact.sh --zst
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
- The signed package keeps the upstream version: `dxmt-0.80.tar.zst`, identifier
  `local.cyder.dxmt.0.80.winemetal`. Cyder only adds a Developer ID signature.
  Even `--force` verifies/reuses the existing signed archive; changed upstream
  inputs, signing policy, damaged caches or signature failures stop until the old
  archive is moved aside. `--revision` / `cyder.N` naming is retired.
- `SIGN_IDENTITY` must be exported for **both** graphics and engine commands.
  The engine pack propagates release mode for Developer ID. Existing archives
  are not proof of signing (the legacy unsigned archive has the same name).

## Upstream version and installation identity

DXMT's displayed, packaged and upstream version is **0.80**. Older artifacts named
`0.80-cyder.N` remain verifiable for installed copies, but that naming is retired
and is not the runtime update predicate. The Cyder manifest generator
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
  dist/artifacts/graphics/dxmt-0.80.tar.zst --zstd <zstd-path>
  --package-version 0.80` (as one command). This is read-only and must
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
