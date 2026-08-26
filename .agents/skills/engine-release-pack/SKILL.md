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
cd /Users/jjc/cyder-wine-engine
export OGOM=/Users/jjc/ogom   # or the sibling Cyder checkout
```

2. Refuse adhoc for release packs. Require a **Developer ID Application**
   identity from the keychain (never `SIGN_IDENTITY=-`).
3. `WINE_INSTALL` must be a **real** tree — `install/wine-cx26-x86_64` or a full
   extracted engine — **never** symlink `lib/dxvk`, `lib/dxvk2`, or `lib/dxmt`.
   Symlink sources pack into stub archives; `pack-graphics-payloads.sh` refuses them.

## Commands

```bash
WINE_INSTALL="${WINE_INSTALL:-$PWD/install/wine-cx26-x86_64}"

bash scripts/pack-graphics-payloads.sh --engine "$WINE_INSTALL" --force

SIGN_IDENTITY='Developer ID Application: …' \
CYDER_ENGINE_VERSION_LABEL='CX26.3.0-W11-Cyder0NN' \
  bash scripts/pack-engine-artifact.sh --zst --force
```

## Post-checks

- Dual MoltenVK layout present in the packed archive (shim + versioned reals).
- `codesign -dv` on `bin/wine` and MoltenVK shim/reals → Developer ID.
- `dist/artifacts/graphics/dxvk-*.tar.zst` and `dxmt-*.tar.zst` each ≫ 1 MiB
  (typical ~3.5 MiB / ~12 MiB).

## Hand-off

Give the manifest path to ogom:

```bash
bash scripts/import-engine-release.sh --manifest <path> --apply
```

For the full formal Cyder release (import → notarize → verify), use ogom’s
`.agents/skills/cyder-release`.

## Related

- Daily incremental build / adhoc pack: `.agents/skills/incremental-wine-build`
- Graphics gate: `scripts/pack-graphics-payloads.sh` (rejects symlink sources)
