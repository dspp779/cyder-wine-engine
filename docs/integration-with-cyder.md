# Cyder integration contract

The engine project produces an immutable archive and sidecar manifest. During
phase one, Cyder continues to bundle that archive in `Cyder.app`.

The transfer is explicit:

1. Build and test the engine repository.
2. Package a Developer ID–signed engine archive.
3. Verify the archive SHA-256 and extracted Mach-O signatures.
4. Copy the selected archive and version label into the Cyder repository.
5. Update Cyder's pinned engine path/version in one commit.
6. Build, sign, notarize, and smoke-test Cyder.app.

Cyder must reject an archive when its sidecar digest, embedded manifest,
`version` file, or NTDLL SHA-256 disagree. Runtime/prefix ownership remains in
Cyder; the engine project must never mutate a user's Cyder prefix.

Cyder012+ ships a **dual-variant** MoltenVK layout: versioned reals
(`libMoltenVK-1.4.2.dylib`, `libMoltenVK-1.2.10.dylib`), a
`libMoltenVK.real.dylib` symlink selecting one of them, and a wait-poll
`libMoltenVK.dylib` shim that re-exports `.real`. Upstream 1.4.2 reals get
capability + present patches only; timeline-wait stays in the shim. See
[`patches/README.md`](../patches/README.md) (MoltenVK section) and
`scripts/install-moltenvk-dual-variant.sh`.

Cross-repository changes cannot be atomic. A Cyder commit therefore pins an
already published immutable engine release rather than a moving branch name.

## DXMT prefix discovery

Selecting/prepending a backend directory alone is insufficient on Wine 11.
Before launching DXMT in an initialized prefix, the application must prepare
its original x86_64/i386 `winemetal.dll` discovery files under system32/syswow64.
The PE loader normally requires the prefix file to exist before the Unix builtin
resolver can redirect it. CyderBits already implements this contract in
`cyder_ensure_dxmt_winemetal_prefix`; standalone test launchers must do it too.
The test-kit helper refuses unknown existing DLLs, links and external prefixes.
See [the controlled reproduction and D3D11 validation](upstream-wine-11/dxmt-prefix-discovery-fix.md).
