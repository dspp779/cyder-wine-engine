# Cyder009 engine release

Label: `CX26.3.0-W11-Cyder009`  
Artifact: `dist/artifacts/engine-wine-x86_64-CX26-3-0-W11-Cyder009.tar.xz`

## Delta vs Cyder008

- Replaces temporary `NtQueryDirectoryObject` TRACE diagnosis with a narrow
  Clang `__attribute__((optnone))` bandage on that function only
  (`cyder-ntdll-qdo-optnone-NtQueryDirectoryObject.patch`).
- Intended to stop MapleStory Classic `grap-core64.aes` leave-game directory
  livelock / high CPU without shipping QDO fprintf diagnostics.
- Keeps Cyder008 teardown / frame-walk / A6 backing-sync / MoltenVK wait-poll
  shim pair.

Not a semantic HID / `\??` directory-object fidelity fix. See
`docs/grap-core-qdo-ab-findings.md`.

## Pack verification (2026-08-08)

- Archive `version` = `CX26.3.0-W11-Cyder009`
- `ntdll.so` contains marker `cyder QDO optnone`
- MoltenVK shim pair gate passed
- Staged Mach-O `minos ≤ 10.15`
- Post-extract codesign check passed (58 Mach-Os)

## Cyder app hand-off

Per `docs/integration-with-cyder.md`: pin this archive into the Cyder release
pipeline / extract over `~/.cyder/runtime/Engines/wine-x86_64` (backup first).
