# Cyder011 → Cyder012 變更摘要

打包來源：本地 `main` @ `2ec5729`（含 dual MoltenVK + GameSir merge metadata）。  
打包樹：`.worktrees/pack-cyder012`（乾淨 worktree；主 checkout 的 gamesir WIP 未動）。  
Wine 建置樹：`/Users/jjc/cyder-wine-engine/build/cx26/sources/wine`（prefix → 主樹 `install/wine-cx26-x86_64`），增量重建後同步二進位到 pack tree。

基線 git：`9dc0ace`（Cyder011 metadata）→ GameSir/dual-MVK merge → 本包。

## 1. Artifact 大小 / SHA256

| | Cyder011 | Cyder012（含 GameSir 二進位） |
|---|---|---|
| 檔名 | `engine-wine-x86_64-CX26-3-0-W11-Cyder011.tar.xz` | `engine-wine-x86_64-CX26-3-0-W11-Cyder012.tar.xz` |
| 壓縮大小 | 54.3 MiB（56948064 bytes） | 55.6 MiB（58301716 bytes） |
| 未壓縮 | 419.2 MiB | 426.5 MiB |
| SHA256 | `b44fa66d7195ce2ccf8be9eba668c0f657ba5f6104163ba1c67825258a2d37f9` | `85fca2bd2df49b177c1681f5a1bc06dc9569df5e0462d08d27383df2be21284f` |

路徑：

- `.worktrees/pack-cyder012/dist/artifacts/engine-wine-x86_64-CX26-3-0-W11-Cyder012.tar.xz`
- `/Users/jjc/cyder-wine-engine/dist/artifacts/engine-wine-x86_64-CX26-3-0-W11-Cyder012.tar.xz`

## 2. MoltenVK layout / 版本 / minOS

| | Cyder011 | Cyder012 |
|---|---|---|
| Layout | 單一 `libMoltenVK.dylib` | dual-variant：shim `libMoltenVK.dylib` + `libMoltenVK.real.dylib` → `libMoltenVK-1.4.2.dylib` + `libMoltenVK-1.2.10.dylib` |
| 預設 real | （單一 dylib） | `libMoltenVK.real.dylib` → `1.4.2` |
| minOS | 10.15 | shim / 1.2.10：10.15；**1.4.2：12.0**（pack gate 豁免） |

Dual MoltenVK 仍在本包中（archive 內四個路徑齊全）。

## 3. 本次 incremental rebuild（GameSir / capacity → 二進位）

先前一版 Cyder012 只 overlay MoltenVK、**未**編譯 GameSir patch。本次已對下列模組做 minOS-safe 增量重建並裝回 install，再 pack：

| Patch | 模組 |
|---|---|
| `cyder-wineserver-macos-timezone-bias.patch` | `bin/wineserver`（`server/fd.c`） |
| `cyder-wineserver-registry-fsync.patch` | `bin/wineserver`（`server/registry.c`） |
| `cyder-winemac-hide-ime-only-klid.patch` | `lib/wine/x86_64-unix/winemac.so` |
| `cyder-kernelbase-disk-free-space-fallback.patch` | `kernelbase.dll`（PE x64/i386） |
| `maplestory-cx26-file-cache-capacity.patch` | `lib/wine/x86_64-unix/ntdll.so`（unix `file.c`；512 slots） |

Host minOS 驗證：`wineserver` / `ntdll.so` / `winemac.so` 皆 **minos 10.15**。  
標記抽樣：`kernelbase` 含 `failed to open device root`；`ntdll.so` 含 `CYDER_MAPLESTORY_FILE_CACHE`；`wineserver` 匯出 `_fsync` 且有 `last_timezone_update`。

## 4. 相對 Cyder011 的二進位 SHA256（archive 內檔案）

| 檔案 | Cyder011 | Cyder012 | 變更 |
|---|---|---|---|
| `bin/wineserver` | `a5e54bf8…793fbc` | `4f171090…2fda7c` | 是 |
| `lib/wine/x86_64-unix/ntdll.so` | `fe4df0ab…459873` | `ff91198d…a5eeae` | 是 |
| `lib/wine/x86_64-unix/winemac.so` | `8c09d09c…1f2f445b` | `952c828b…ad1504b2` | 是 |
| `lib/wine/x86_64-windows/kernelbase.dll` | `d50fc4c9…902c40` | `a6efa08d…1d5e8b` | 是 |

完整雜湊：

- wineserver 011 `a5e54bf8d5504abc1b327b08d6771cdecdfc19c9cafe13cab7fd8a6144793fbc` → 012 `4f171090bb9ee6ee6bb1e659a10522a24d0c5a0195f67b3409a80bca6e2fda7c`
- ntdll.so 011 `fe4df0ab9024002631b4b944744ae39ce0bdf5728a97746715dbc89ddd459873` → 012 `ff91198da1f00dfeff2e59002572276a2d2059716f6ee44d4fa848a45ca5eeae`
- winemac.so 011 `8c09d09c48745df0d53d59eae14cc52b476f47ac83c801802fd09a1c1f2f445b` → 012 `952c828b0d9d9c2988c8743be0799645669c8729c40fa7e889a656f5ad1504b2`
- kernelbase.dll 011 `d50fc4c9767cb92c3de6d71dcd2c254aecafed22c438246425643fd6bd902c40` → 012 `a6efa08dae456661199dda66386dc12e46436e6fbceab9c7cdc8a628131d5e8b`

## 5. Manifest `ntdllSHA256`

欄位雜湊的是 **PE** `lib/wine/x86_64-windows/ntdll.dll`（pack 後 strip），不是 unix `ntdll.so`。  
512-slot capacity 只改 unix `file.c`，故 **manifest `ntdllSHA256` 仍為** `a361cf85184066b07d50f3bc2095ce61650b48ded781a6468bf16f1334ac81fc`（與 Cyder011 相同）；unix `ntdll.so` 內容雜湊已變（見上表）。

## 6. `engine-release.json` / patch 清單

與先前 Cyder012 metadata 相同：新增 GameSir 四 patch + `maplestory-cx26-file-cache-capacity.patch`；開發用 IO ring/summary 等不進 release。  
**現在 metadata 與二進位已對齊**（GameSir + capacity 已進包）。

## 7. 打包注意

pack worktree 需能解析 `build/llvm-mingw-…/bin/llvm-strip`（可 symlink 自主 checkout），否則 PE 未 strip 會使產物體積膨脹至 ~160 MiB+。本次最終包已確認 strip 正常（~55.6 MiB）。
