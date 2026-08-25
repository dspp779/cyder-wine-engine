# Cyder011 → Cyder012 變更摘要

打包來源：本地 `main` @ `89dbfde`（含 dual MoltenVK + GameSir merge）。  
打包樹：`.worktrees/pack-cyder012`（乾淨 worktree，避免 dirty gamesir checkout）。  
Wine install：自既有 `install/wine-cx26-x86_64` rsync，**未**全量重建 Wine；僅 overlay dual MoltenVK 後 `pack-engine-artifact.sh --force`。

基線 git：`9dc0ace`（`chore(engine): align Cyder011 release metadata`）→ `89dbfde`。

## 1. Artifact 大小 / SHA256

| | Cyder011 | Cyder012 |
|---|---|---|
| 檔名 | `engine-wine-x86_64-CX26-3-0-W11-Cyder011.tar.xz` | `engine-wine-x86_64-CX26-3-0-W11-Cyder012.tar.xz` |
| 壓縮大小 | 54.3 MiB（56948064 bytes） | 55.6 MiB（約 56M on disk） |
| 未壓縮 | 419.2 MiB | 426.5 MiB |
| SHA256 | `b44fa66d7195ce2ccf8be9eba668c0f657ba5f6104163ba1c67825258a2d37f9` | `c55f144c01cf2b1a2c22c59033939fdc85a38d05aa7efc0193eabeaef4dbd2eb` |

體積略增主要來自 dual MoltenVK 多兩顆 versioned real（約 +7–8 MiB 未壓縮量級）。

路徑（pack tree 與 main checkout 皆有副本）：

- `.worktrees/pack-cyder012/dist/artifacts/engine-wine-x86_64-CX26-3-0-W11-Cyder012.tar.xz`
- `/Users/jjc/cyder-wine-engine/dist/artifacts/engine-wine-x86_64-CX26-3-0-W11-Cyder012.tar.xz`

## 2. MoltenVK layout / 版本 / minOS

| | Cyder011 | Cyder012 |
|---|---|---|
| Layout | 單一 `libMoltenVK.dylib` | dual-variant：`libMoltenVK.dylib`（wait-poll shim）+ `libMoltenVK.real.dylib` → versioned real + `libMoltenVK-1.4.2.dylib` + `libMoltenVK-1.2.10.dylib` |
| 預設 real | （即單一 dylib） | `libMoltenVK.real.dylib` → `libMoltenVK-1.4.2.dylib` |
| 版本字串 | 1.4.0（timeline-wait 等 patch 打在 real） | real 1.4.2 / 1.2.10；timeline-wait 由 shim 擁有（字串 `cyder-moltenvk-timeline-wait-poll`） |
| minOS | 單一 dylib：10.15 | shim 10.15；1.2.10：10.15；**1.4.2：12.0**（pack gate 豁免至 12.0） |

## 3. 檔案清單差異（archive 路徑）

僅 Cyder012 新增（3）：

- `wine-x86_64/lib/wine/x86_64-unix/libMoltenVK-1.2.10.dylib`
- `wine-x86_64/lib/wine/x86_64-unix/libMoltenVK-1.4.2.dylib`
- `wine-x86_64/lib/wine/x86_64-unix/libMoltenVK.real.dylib`

僅 Cyder011：無。  
路徑總數：011 = 1829，012 = 1832。

## 4. Git / patch list / `engine-release.json`

### 重點 commits（`9dc0ace..89dbfde`，節錄）

- Dual MoltenVK：`63b2256`…`37ac956`（pin 1.4.2、dual installer/pack gate、minos 12 豁免、Cyder012 label）
- GameSir 平台 patch 進樹：`cd576da`；merge 進 main：`89dbfde` / `ad83c29`
- 其他：CX25 retire、MapleStory 512-slot cache capacity 進 release metadata、docs

### `config/engine-release.json` patch 差異（相對 Cyder011 metadata）

新增：

- `cyder-wineserver-macos-timezone-bias.patch`
- `cyder-wineserver-registry-fsync.patch`
- `cyder-winemac-hide-ime-only-klid.patch`
- `cyder-kernelbase-disk-free-space-fallback.patch`
- `maplestory-cx26-file-cache-capacity.patch`

自 release 清單移除（改為開發診斷、不進 release notes 所稱堆疊）：

- `maplestory-cx26-io-ring.patch` / `-arm` / `-summary` / `-timeline` / `-cache-stats` / `section-map-summary`

Notes：由「單一 MoltenVK 1.4.0 + timeline-wait in real」改為 dual-variant + shim-owned timeline-wait；並註明 MapleStory release 僅保留 adaptive cache + capacity。

### 二進位 vs metadata 注意

本次 **未 rebuild Wine**。打包產物中：

- `ntdll.so` / `wineserver` / `kernelbase.dll` / `winemac.so` 與 Cyder011 artifact **SHA256 相同**
- 因此 GameSir 四個 patch **已寫進 release metadata / 原始碼樹，但尚未編譯進此顆 Cyder012 引擎二進位**
- 實際行為差異以 **MoltenVK dual-variant overlay** 為主；若要讓 GameSir patch 生效需後續對對應模組做 incremental rebuild 後再 pack

## 5. ntdllSHA256

Manifest 欄位 `ntdllSHA256`：**未變**

- Cyder011 / Cyder012 皆為 `a361cf85184066b07d50f3bc2095ce61650b48ded781a6468bf16f1334ac81fc`
- 封裝後 `ntdll.so` 內容 SHA256（兩版 artifact 相同）：`fe4df0ab9024002631b4b944744ae39ce0bdf5728a97746715dbc89ddd459873`

與「未重建 Wine、只換 MoltenVK layout」一致。
