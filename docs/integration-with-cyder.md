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

Cyder008 owns the MoltenVK wait-poll shim inside the immutable engine archive.
The packer rejects an archive without a valid shim/real pair; Cyder.app must not
build or inject a second copy. The former RC overlay contract is retained as
historical documentation in
[`docs/moltenvk-timeline-wait-poll-app-overlay.md`](moltenvk-timeline-wait-poll-app-overlay.md).

Cross-repository changes cannot be atomic. A Cyder commit therefore pins an
already published immutable engine release rather than a moving branch name.
