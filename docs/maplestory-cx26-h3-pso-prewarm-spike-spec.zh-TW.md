# MapleStory CX26：H3-B 圖形 PSO 預熱 — 可行性 Spike 規格

> 狀態：草案已核准；**S1 完成 → H3-B 不可行**（不進入 S2）  
> 日期：2026-09-05  
> 選擇：H3 方向＝**C**；首打優先；作法＝H3-B spike → **掛點在封閉 GPTK**  
> 總覽：[`maplestory-cx26-hit-path-first-use-cost-plan.zh-TW.md`](maplestory-cx26-hit-path-first-use-cost-plan.zh-TW.md)  
> 背景：[`maplestory-cx26-first-hit-prewarm-design.zh-TW.md`](maplestory-cx26-first-hit-prewarm-design.zh-TW.md)（P0／E2／E3／方案 D）

## 1. 目標

回答一個 **是／否**：

在 **不修改 GPTK／D3DMetal binary、不注入遊戲鍵盤** 的前提下，能否在
「進圖可操作後、第一次打到怪之前」，用 Wine／引擎側 **opt-in probe** 提前觸發
與命中路徑相近的 **D3DMetal／Metal PSO 編譯**，使 **不揮空第一下打怪** 體感
穩定優於對照。

### 1.1 非目標

- 自動打怪／B1 M1 鍵注入（H3-A；本 spike 不做）
- 消掉「第一次左右無效」
- 產品預設開啟任何圖形預熱
- 依賴高干擾 `sample` 當唯一根因證明（可用低干擾輔助）
- 假設 `CreateShaderCacheSession`／`ShaderCacheControl` 可用（已標 Unsupported）

## 2. 已知約束（不可再踩）

| 事實 | 含義 |
|---|---|
| E2／E3：清／留 `wineloader` Metal disk cache 體感差不多 | 方案 A（只保 OS Metal cache）**不是**本 spike 主路徑 |
| D3DMetal：`CreateShaderCacheSession`／`ShaderCacheControl`＝Unsupported | 不能做成「開 D3D shader cache API」 |
| H1／H2：I／O 預熱邊際；H2 填 ~24 MiB 後首打仍小卡但「好很多」 | Spike 成功必須 **優於「僅 H2」**，否則算資訊性失敗 |
| 蠻卡窗曾見 `PSOCompilationQueue`／`MTLCompiler`；Present 執行緒等 GPU | P0 仍是首打假說；假繪製必須真的碰到相近 pipeline |

## 3. Spike 分期

| 階段 | 內容 | 產出 |
|---|---|---|
| **S0** | 本規格核准 | 本文件 |
| **S1** | 只讀盤點掛點 | 短筆記：可／不可掛的 API 與檔案路徑 |
| **S2** | 最小 opt-in probe（若 S1 通過） | patch／flag（預設關）＋如何開關 |
| **S3** | A／B 玩測 | 首打體感表＋是否繼續 H3-B |

**S1 失敗 → 直接結案不可行**，不進入 S2。

## 4. S1 — 掛點盤點（只讀）

檢查範圍（文件＋必要時對 install／來源的字串／符號，**不改 GPTK**）：

1. Wine 樹內與 D3DMetal 交接：`dlls/winemac.drv/d3dmetal*`、`d3d11`／`dxgi` 是否有可攔截的 create／draw 邊界  
2. 既有 Cyder MapleStory patches 是否已有可复用的 opt-in 鉤子  
3. 若唯一可靠點在 GPTK 封閉 binary 內 → **判定不可行**

S1 通過條件：寫得出「在哪個 translation unit、用哪個 env、對什麼物件做一次安全 no-op／dummy 呼叫」的 **具體提案**，且不需改 GPTK。

## 5. S2 — 最小 probe（僅 S1 通過後）

### 5.1 開關

| 項目 | 值 |
|---|---|
| Flag（暫定） | `CYDER_MAPLESTORY_PSO_PREWARM_PROBE=1` |
| 預設 | **關** |
| 依賴 | D3DMetal 路徑；建議玩測時可疊 H2 或單獨測（文件註明） |

### 5.2 行為候選

| 候選 | 做法 | 採用條件 |
|---|---|---|
| **B1 dummy draw** | 在已有 D3D11／Metal 裝置上，對近期／靜態清單做一次 offscreen 或最小 draw，逼 pipeline create | S1 證明狀態可取得且可安全還原 |
| **B2 僅記錄** | 掛點只能 log 首次 pipeline create，無法主動暖 | 不算 H3-B 成功；可當觀測工具後停 |

失敗只 TRACE／stderr；不得拖垮進圖；必須可關 flag 立即無行為。

### 5.3 明確不做

- 掃描全部 shader 盲編譯  
- 背景無限重試  
- 與遊戲 Present 搶同一 critical path 而無 bound

## 6. S3 — 驗收 A／B

固定：同角、同安全圖、D3DMetal、`FILE_CACHE=1`、不開 `sample`、不揮空首打。

| 輪 | 條件 |
|---|---|
| **G0** | probe **關**（可開或關 H2；兩輪要一致） |
| **G1** | probe **開**；進圖後、首打前完成 probe（log 有開始／結束） |

各 ≥2 次。只評 **第一下打到怪**（蠻卡／小卡／幾乎無／「比 G0 好很多」）。

| 結果 | 判定 |
|---|---|
| G1 穩定優於 G0 | **硬成功** → 再寫產品化／縮小範圍計畫 |
| probe 有跑、PSO 有動，體感無差 | **資訊性失敗** → 停 H3-B；瓶頸不在可預熱 PSO 或清單不對 |
| 無穩定掛點／不改 GPTK 做不到 | **不可行** → 停 H3-B；改 H3-A（M0／M1）或 known issue |
| 進圖明顯卡、崩潰、畫面壞 | **硬失敗** → 關 flag、rollback |

## 7. 風險與 rollback

- 假繪製弄髒 D3D／Metal 狀態 → 花屏／黑屏  
- 進圖變慢或搶 CPU／GPU  
- 誤判「compile 了」但其實不是命中變體  

Rollback：預設關 flag；必要時 revert probe patch；玩測用 disposable prefix。

## 8. 與其他工作的關係

| 項目 | 關係 |
|---|---|
| H2 hit-prewarm | 可並行為「I／O 邊際」；H3-B 成功須證明 **額外**圖形收益 |
| H3-A（M0／M1） | Spike 失敗或不可行時的預設退路 |
| 左右 first-use | 本規格不驗收 |

## 9. 核准紀錄

| 日期 | 決定 |
|---|---|
| 2026-09-05 | 使用者選 H3 → 首打優先 → **先做 H3-B spike** → 核准本 spike 設計寫入文件 |

**下一步（待你確認本文件無誤後）：** 進入 S1 掛點盤點（仍不實作 probe，除非再核准 S2）。

## 10. S1 盤點結果（2026-09-05）

### 10.1 執行期圖形棧（D3DMetal 玩測路徑）

| 元件 | 位置 | 我們能否改 |
|---|---|---|
| `d3d11.dll`（遊戲實際載入） | GPTK `apple_gptk/wine/x86_64-windows/d3d11.dll`（~136 KiB stub） | **否**（封閉；非 engine 建置產物） |
| `d3d11.so` | symlink → `external/libd3dshared.dylib` | **否** |
| `D3DMetal.framework` | `apple_gptk/external/`；含 `PSOCompilationQueue`、`Unsupported: CreateShaderCacheSession` | **否**（規格禁止改 GPTK binary） |
| Engine `install/.../d3d11.dll` | Wine／wined3d 大 PE（~3 MiB） | 可改，但 **D3DMetal backend 下不是熱路徑** |
| `winemac.drv/d3dmetal.c` | 僅 Cocoa view／client surface／Present 橋 | 可改；**沒有** Draw／Create*Shader／Create*Pipeline |

Launcher 固定 `CYDER_GRAPHICS_BACKEND=d3dmetal` 並掛 GPTK；CompatDB／runtime prepend 讓遊戲走 GPTK D3D11，而非我們 patch 的 Wine `dlls/d3d11`。

### 10.2 既有 MapleStory 圖形相關 patch

| Patch | 作用 | 對 H3-B dummy draw |
|---|---|---|
| `maplestory-cx26-d3dmetal-*.patch` | view／surface／present 行為 | **不能**用來建立命中 PSO |
| `maplestory-cx26-d3d11-full-clear.patch` 等 | Wine `dlls/d3d11` | **不在** D3DMetal 熱路徑上，掛 dummy draw **暖不到** GPTK PSO |

### 10.3 候選與判定

| 候選 | S1 判定 |
|---|---|
| **B1** 在 Wine `d3d11` 做 offscreen／dummy draw | **不可行**（錯 DLL） |
| **B1′** 在 `winemac.drv` Present 前後假繪製 | **不可行**（無 pipeline／shader 狀態；無法逼命中變體） |
| **B1″** 改 GPTK／D3DMetal 內部預熱 | **規格禁止** |
| **B2** 僅 Metal／D3D interpose log（觀測） | **可做但非預熱**；不滿足 spike「體感變好」目標 |
| **B3** 改走 DXMT 實驗其 `shaders_*.db` | **另一產品後端**；不回答「D3DMetal 上 H3-B」 |

### 10.4 S1 結論

**H3-B（不改 GPTK 的主動 PSO 預熱）→ 不可行。**  
不進入 S2 probe 實作。

建議退路（擇一，需另核准）：

1. **H3-A**：M0 說明 ± 可選 M1「進圖真實打一下」（**V1／V2 已驗證策略有效**；見 findings）  
2. **Known quirk**：接受首打小卡；H2 維持 opt-in 邊際  
3. **（高風險）Metal interpose 實驗**：僅研究用，不承諾產品化  

結案證據：[`maplestory-cx26-first-hit-materialize-findings.zh-TW.md`](maplestory-cx26-first-hit-materialize-findings.zh-TW.md)。  
H1／H2／總覽：[`maplestory-cx26-hit-path-first-use-cost-plan.zh-TW.md`](maplestory-cx26-hit-path-first-use-cost-plan.zh-TW.md)。
