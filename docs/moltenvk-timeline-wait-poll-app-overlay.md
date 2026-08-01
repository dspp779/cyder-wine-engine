# App 端：MoltenVK timeline-wait poll shim 注入（RC workaround）

給 **Cyder.app（ogom）** 實作參考。目標：在**不 bump 引擎版號**的前提下，
於使用者 runtime 覆寫 `libMoltenVK.dylib`，避開 DXVK + MoltenVK 的 Mach port
洩漏；等正式 MoltenVK 修補進引擎後再移除此路徑並更新引擎。

引擎 repo 內對應實作：

| 路徑 | 用途 |
|------|------|
| `tools/cyder-mvk-timeline-wait-poll/` | shim 原始碼 + 本機安裝腳本 |
| `patches/cyder-moltenvk-timeline-wait-poll.patch` | 正式修補（需 Xcode 重編 MoltenVK） |
| `patches/README.md`（MoltenVK 節） | patch／shim 摘要 |

本文件描述的是 **App 側自動注入**，不是開發者手動跑 `install-shim.sh`。

---

## 1. 背景（為何需要）

- 症狀：MapleStory Classic + **DXVK** 長時間遊玩，wine 行程 **Ports（receive rights）** 持續上升（約 80+/s），之後卡頓；重啟清除。
- 因果：MoltenVK `vkWaitSemaphores*` → `MTLSharedEvent notifyListener`；有限 timeout 的 wait 放棄後，Metal 側 pending 註冊無法取消，Mach receive right 累積。
- WineD3D／D3DMetal 不走此路徑，通常無此洩漏。
- 上游（含 MoltenVK 1.4.2）仍用同一套 `notifyListener`；升級版本**不會**自動修好。
- 正式解法：重編 MoltenVK，改 host wait 為輪詢 `getCounterValue`（見 patch）。目前缺完整 Xcode 時用 **re-export shim** 等價攔截。

產品決策（RC）：

- **引擎版號先不動**（例如維持 Cyder007）。
- **App 發版時**把 shim 注入已安裝的 engine tree。
- 正式 MoltenVK 進引擎後：拿掉注入、bump 引擎。

---

## 2. 目標目錄配置

對每個需要 DXVK／Vulkan 的 engine root（典型：
`~/.cyder/runtime/Engines/wine-x86_64`）：

```text
<engine>/lib/wine/x86_64-unix/
  libMoltenVK.dylib       ← Cyder wait-poll shim（小，re-export）
  libMoltenVK.real.dylib  ← 原廠／引擎出貨的 MoltenVK（大，CX 1.2.10 等）
```

Wine／winevulkan 仍只 dlopen `libMoltenVK.dylib`；shim 再轉發到 `.real`，
並覆寫 `vkWaitSemaphores*`／`vkGet*ProcAddr`／`vk_icdGetInstanceProcAddr`。

`install_name` 約定（與現有腳本一致）：

- shim id：`@loader_path/libMoltenVK.dylib`
- real id：`@loader_path/libMoltenVK.real.dylib`
- shim 依賴：`@loader_path/libMoltenVK.real.dylib`（re-export）

minOS：shim 必須 ≤ 產品樓層（目前 **10.15**）。

---

## 3. 建議掛點（何時注入）

在 **engine 已展開到 runtime 之後、啟動 wine 之前**，冪等執行一次，例如：

1. `ensureEngine`／首次安裝引擎完成後
2. 每次 App 啟動檢查 engine 時（成本低：比對 marker／mtime／sha）
3. 使用者切換／修復引擎後

對齊現有「App 改寫 engine tree」模式（例如 GPTK link）：**runtime 歸 App 管**，
引擎 tarball 保持不可變。

不建議：

- 只文件說明、靠使用者手動裝
- 只在「選 DXVK」時才注入又在切後端時卸除（可做，但複雜；洩漏僅 DXVK，留著 shim 對其他後端通常無害）

建議涵蓋的 engine：至少主引擎 `wine-x86_64`；若 OEM sidecar 也帶 MoltenVK 且會開 DXVK，一併注入。

---

## 4. 冪等注入演算法

對 `unix = <engine>/lib/wine/x86_64-unix`：

```
若 unix/libMoltenVK.dylib 不存在 → skip（此引擎無 Vulkan）

marker = 內嵌字串 "cyder-moltenvk-timeline-wait-poll"（見下方偵測）
bundled_shim = App Resources 內預先編好的 x86_64 shim 模板
               （見 §5：必須對「該引擎的 .real」重新 link，或使用通用建置流程）

若 unix/libMoltenVK.real.dylib 不存在：
  若 libMoltenVK.dylib 已是任一 shim（otool 依賴含 .real）但缺 .real
    → 視為損毀，abort／回報錯誤，勿繼續
  否則：
    cp libMoltenVK.dylib → libMoltenVK.real.dylib
    install_name_tool -id '@loader_path/libMoltenVK.real.dylib' .real
    codesign -f -s - .real

若 libMoltenVK.dylib 已是 wait-poll shim（含 marker）且版本符合 App 期望
  → skip（已套用）

否則（含：實驗用舊 shim、或需升級 shim）：
  以 .real 為 reexport 目標，產出／複製 shim → libMoltenVK.dylib
  chmod 755
  codesign -f -s - libMoltenVK.dylib
  （可選）寫 sidecar：unix/libMoltenVK.cyder-wait-poll
           內容：shim_version=… app_build=… applied_at=…
```

**禁止**：對已經是 shim 的 `libMoltenVK.dylib` 再當「原廠」備份成 `.real`（雙重包裝）。

### 偵測

| 狀態 | 建議判定 |
|------|----------|
| 是 wait-poll shim | `strings` 含 `cyder-moltenvk-timeline-wait-poll` |
| 是任一 re-export shim | `otool -L` 含 `libMoltenVK.real.dylib` |
| 原廠 MoltenVK | 無上述；通常數 MB，且無 `.real` |

參考實作：`tools/cyder-mvk-timeline-wait-poll/install-shim.sh` 的
`is_wait_poll_shim`／`is_any_shim`／`install_tree`。

---

## 5. Shim 如何進 App（建置與打包）

Shim **必須用 Apple clang 編 x86_64**（Wine 在 Rosetta），**不需要**完整 Xcode
（Command Line Tools + macOS SDK 即可）。**不能**用 llvm-mingw（那是 PE／DXVK）。

開發機驗證（引擎 repo）：

```bash
# 在 cyder-wine-engine
bash tools/cyder-mvk-timeline-wait-poll/install-shim.sh --install-runtime
```

App 發版建議流程：

1. **CI／本機**對「代表用」的 `libMoltenVK.real.dylib`（與出貨引擎相同的 CX MoltenVK）執行：

   ```bash
   arch -x86_64 clang -arch x86_64 \
     -mmacosx-version-min=10.15 \
     -isysroot "$(xcrun --sdk macosx --show-sdk-path)" \
     -dynamiclib \
     -o libMoltenVK.dylib \
     cyder_mvk_timeline_wait_poll.m \
     -Wl,-reexport_library,/path/to/libMoltenVK.real.dylib \
     -install_name '@loader_path/libMoltenVK.dylib'
   install_name_tool -change /path/to/libMoltenVK.real.dylib \
     '@loader_path/libMoltenVK.real.dylib' libMoltenVK.dylib
   codesign -f -s - libMoltenVK.dylib
   ```

2. 將編好的 shim（或 **原始碼 + 安裝時即時 clang**）放進 App Resources。  
   - **預編 shim**：發版簡單，但 `LC_REEXPORT` 在建置時綁過絕對路徑、需
     `install_name_tool` 改成 `@loader_path/...`（腳本已做）。換引擎 MoltenVK
     大版本時建議重編一次。  
   - **安裝時對本機 `.real` 現場 clang**：最穩（永遠對準使用者引擎裡的
     `.real`），App 需帶 `.m` 與 clang／SDK 可用性；消費者機通常有 CLT 不一定。  
   - **RC 實務建議**：App 帶**預編 x86_64 shim**；注入時只 `cp` + 確認
     `otool -L` 已是 `@loader_path/libMoltenVK.real.dylib`。引擎 MoltenVK
     仍為 CX 1.2.10 系時無需每版重編。

3. 原始碼單一真實來源：優先 **submodule／拷貝**
   `cyder-wine-engine/tools/cyder-mvk-timeline-wait-poll/cyder_mvk_timeline_wait_poll.m`
   進 ogom（避免兩份漂移）。標記字串勿刪。

正式 log：shim **不應**寫 `/tmp` 統計；保持安靜。

---

## 6. 卸載／停用條件

在以下任一情況 **還原** 並停止注入：

1. 新引擎已內建正式修補的 MoltenVK（無須 shim；或引擎 manifest 宣告已修）。
2. App 功能旗標關閉 workaround（例如 debug／企業設定）。
3. 使用者明確「修復引擎／重裝引擎」且新樹已是乾淨 MoltenVK——ensure 時勿殘留舊 `.real` 邏輯錯誤。

還原：

```
若存在 libMoltenVK.real.dylib：
  mv .real → libMoltenVK.dylib
  codesign -f -s - libMoltenVK.dylib
刪除 sidecar marker（若有）
```

之後引擎 bump 發版時：自 App 移除 Resources 內 shim 與 ensure 呼叫。

---

## 7. 驗收清單

- [ ] 乾淨引擎（僅原廠 `libMoltenVK.dylib`）→ ensure 後出現 `.real` + shim；`strings` 見 marker。
- [ ] 再跑一次 ensure → 不雙重包裝、不報錯。
- [ ] Maple + DXVK 長跑：Activity Monitor **Ports 不再以 ~80/s 持續上升**；長時間不因 port 爆掉卡死。
- [ ] D3DMetal／WineD3D 仍可啟動（回歸）。
- [ ] `otool -l` shim `minos` ≤ 10.15。
- [ ] 卸載／換「已正式修補」引擎後，目錄回到單一 `libMoltenVK.dylib`。
- [ ] RC release note 註明：此為 App 側 MoltenVK wait workaround，引擎版號未因此變更。

---

## 8. 限制與非目標

- 只修 **host** `vkWaitSemaphores*`；不改變 GPU `encodeWait`／present。
- 輪詢間隔約 100µs：成功長等待略多 CPU；換不洩漏。無限 timeout 也走輪詢。
- 不取代 `patches/cyder-moltenvk-timeline-wait-poll.patch`；有 Xcode 後應編進 MoltenVK 本體。
- `tools/cyder-mvk-autorelease/` 為診斷實驗，**不要**打包進 App（已 gitignore）。
- 引擎 tarball／`pack-engine-artifact` **不必**含此 shim（刻意；否則就該 bump 引擎）。

---

## 9. 與引擎整合契約的關係

見 `docs/integration-with-cyder.md`：引擎 archive 應保持不可變；Cyder pin 已發布
archive。本 workaround 是 **Cyder 在展開後的 runtime mutation**，類似其他
sidecar／link，**不**修改 pin 的引擎版號字串，直到正式修補進入下一顆引擎包。

建議在 App 的 engine ensure 日誌打一行（勿刷屏）：

`moltenvk-wait-poll: applied|skipped|removed engine=…`

方便區分「引擎 Cyder007」與「App overlay 已套」。
