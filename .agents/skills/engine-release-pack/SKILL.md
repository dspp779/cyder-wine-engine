---
name: engine-release-pack
description: >-
  Pack a shipping Wine engine and its DXVK/DXMT graphics payloads with
  Developer ID signing, then hand them to CyderBits. Use when producing a
  release engine archive, repacking graphics for a release, or repairing an
  ad-hoc or broken pack. Not for daily builds (incremental-wine-build).
---

# Engine release pack

Do the steps in order; stop when one fails. Never use `SIGN_IDENTITY=-` here.
References: `docs/graphics-signing-policy.zh-TW.md`,
`docs/build-engine-from-scratch.zh-TW.md`.

## 1. Preflight

```bash
cd "$HOME/ogom/cyder-wine-engine"
export OGOM="$PWD"
export WINE_INSTALL="${WINE_INSTALL:-$PWD/install/wine-cx26-x86_64}"
git status --short
cat config/engine-version.txt "$WINE_INSTALL/version"
security find-identity -v -p codesigning | grep "Developer ID Application"
```

1. The two version lines must match. If not, the install tree is not the build
   you mean to ship: rebuild first (`incremental-wine-build`).
2. Everything meant for this engine is merged or on the branch you are
   building. Check `git stash list` and other branches; an engine was once
   packed without a patch that lived only in a scratch folder.
3. `WINE_INSTALL` is a real tree. `lib/dxvk` and `lib/dxmt` must not be
   symlinks: a symlink packs into a stub archive, and the packer refuses it.
4. `bash tests/run.sh` passes.

## 2. Pack graphics

```bash
export SIGN_IDENTITY='Developer ID Application: <name> (<team>)'
bash scripts/pack-graphics-payloads.sh --engine "$WINE_INSTALL" --channel release
```

- Existing archives are **reused**. After any DXVK source or patch change add
  `--force`, then confirm the DXVK archive is new (date and SHA-256).
- Signed DXMT is `dxmt-0.80.tar.zst`: unmodified upstream 0.80 with a Developer
  ID signature on `winemetal.so`. It is verified and reused, never overwritten,
  even with `--force`. If upstream DXMT or the signing policy changed, the
  script stops; move the old archive aside, then rerun.
- Do not sign the install tree or a user's runtime, and do not replace an
  upstream or Apple signature. Unreviewed inputs stop for policy review.
- DXVK 2 is never packed. If `dist/artifacts/graphics/` contains anything other
  than DXVK, signed DXMT and their version/checksum files, move it aside:
  CyderBits bundles every archive in that folder.

## 3. Pack the engine

```bash
CYDER_ENGINE_VERSION_LABEL="$(head -n 1 config/engine-version.txt)" bash scripts/pack-engine-artifact.sh --zst
```

`SIGN_IDENTITY` must still be exported. The script checks minOS, the MoltenVK
layout, capabilities and signatures, and fails rather than packing a bad tree.

If the bundle gate fails on `libMoltenVK.dylib` with `minos 12.0` after a
from-scratch build: run `scripts/install-moltenvk-dual-variant.sh`, then bundle
again with `VULKAN_SOURCE=existing`. The versioned MoltenVK files may be 12.0;
the unversioned shim must be 10.15.

## 4. Check the result

```bash
python3 scripts/graphics-signing.py verify-archive --archive dist/artifacts/graphics/dxmt-0.80.tar.zst --zstd "$(command -v zstd)" --package-version 0.80
```

Then, in the packed engine archive:

1. MoltenVK layout: the shim `libMoltenVK.dylib`, `libMoltenVK-1.4.2.dylib`,
   `libMoltenVK-1.2.10.dylib`, and the link `libMoltenVK.real.dylib`.
2. `otool -l <file> | grep -A3 LC_BUILD_VERSION` on both versioned files shows
   the macOS floor you intend to support. A current Xcode SDK cannot target
   below macOS 12, which silently raises the floor of a rebuilt file.
3. `codesign -dv` on `bin/wine` and the MoltenVK files shows Developer ID.
4. The DXVK archive is about 3.5 MiB and DXMT about 12 MiB. Far smaller means a
   stub.

## 5. Hand off to CyderBits

Give CyderBits the manifest path (`dist/artifacts/engine-….tar.zst.manifest.json`)
and the graphics folder (`dist/artifacts/graphics`). Importing the engine does
not copy graphics. Continue with CyderBits `.agents/skills/cyder-release`.

Report: engine label, archive SHA-256, what changed since the previous engine,
and which games were launched on it (or that none were).

## PE Authenticode (optional)

Off by default (`CYDER_PE_SIGNING=off`); an Apple Developer ID release needs no
PE signing, and unsigned PE alone is not an integrity failure. Only an explicit
`CYDER_PE_SIGNING=required` enables it. Read
`docs/pe-authenticode-release-signing.zh-TW.md` first: it needs a reviewed
policy, provider adapter and trust stores, and it stops on missing setup
instead of downgrading or using test certificates.

## Same-version DXMT changes

A DXMT archive whose signature or policy changed while the version stays 0.80
is still an update. CyderBits derives its install key from the archive SHA-256
and signing policy, and applies it only when no game is running. Never
overwrite `graphics/dxmt/0.80` by hand, force-quit games, or ad-hoc sign
installed files to get around that.
