# MapleStory CX26：降低「第一次打到怪」first-use 成本 — 實驗方向

> 狀態：H1／H2／預熱／換後端皆未消掉首打幅度；**V1＋V2 證明**首次命中 materialize＝關鍵，**提前真命中可讓「正式第一下」不卡**；剩 **產品 M0±M1／quirk**  
> 日期：2026-09-05  
> 前提：M0／M1 **不**降低「付費那一下」的幅度，但可把卡挪出認真練功時刻；隱形假暖命中資源目前不可行  
> 相關：[`maplestory-cx26-b1-safe-first-hit-prewarm-spec.zh-TW.md`](maplestory-cx26-b1-safe-first-hit-prewarm-spec.zh-TW.md)、[`maplestory-cx26-first-hit-prewarm-design.zh-TW.md`](maplestory-cx26-first-hit-prewarm-design.zh-TW.md)、[`maplestory-cx26-first-hit-materialize-findings.zh-TW.md`](maplestory-cx26-first-hit-materialize-findings.zh-TW.md)、[`maplestory-cx26-h2-file-cache-prewarm-spec.zh-TW.md`](maplestory-cx26-h2-file-cache-prewarm-spec.zh-TW.md)、[`maplestory-cx26-h3-pso-prewarm-spike-spec.zh-TW.md`](maplestory-cx26-h3-pso-prewarm-spike-spec.zh-TW.md)

## 1. 目標

讓 **冷啟動後、不揮空、第一次打到怪物** 的體感，從「蠻卡／小卡」往「小卡／無感」移動。  
驗收只看 **第一下**；「之後順」不計分。

非目標：受擊／被動（可另開）、自動注入攻擊、再開高干擾 `sample`、加深 `FAST_HIT`。

## 2. 作法比較

| 作法 | 內容 | 可能壓到什麼 | 壓不到什麼 | 風險 |
|---|---|---|---|---|
| **H1 命中相關 host／in-process 檔案預熱** | 從「第一下命中」當下的低干擾 I/O timeline 抽出 Mob／Effect／Skill／數字等 range，擴大 `maplestory-prewarm.sh` 與可選 in-process prewarm；A／B 體感 | 磁碟／page-cache／部分同步 fill | Metal PSO、Rosetta 冷碼、物件建立 | 低；清單錯就白忙 |
| **H2 進圖後非同步填命中 window** | 地圖就緒後背景 `pread` 已知命中 range 進 file-cache（bounded） | 第一下同步 fill | 同上 PSO／邏輯 | 中；拖進圖、記憶體 |
| **H3 圖形側暖命中 PSO** | 無真命中下強制相近 pipeline | PSO | 遊戲邏輯／WZ 解析 | 高；難準、維護重 |

**建議順序：先 H1 實驗 → 有體感再考慮 H2 → H3 最後。**

### 2.1 H1 prewarm 清單進度（2026-09-04）

- 采樣：arm + 不揮空首打，兩輪皆 **小卡**；`timeline` 未輸出，靠 exit `CYDER_IO summary`。
- 已更新 `scripts/maplestory-prewarm.sh`：以 `Effect_000`＋`Effect/_Canvas/_Canvas_003/053/041/052` 為主，輔以活躍 `Mob/_Canvas` 與 `Morph_000`；拿掉舊版被動 `Skill_*.ms` 大段。
- Canvas 檔遠大於 cache fill，**無精確 offset 時採檔首 prefix**（003 約 32 MiB）；C0／C1 若無差，可能是 offset 未命中或瓶頸不在 page-cache。
- 啟動 C1：`CYDER_MAPLESTORY_PREWARM=1`（launcher 會跑該腳本）。

| 輪 | 結果 | 時間 |
|---|---|---|
| **C0**（PREWARM=0） | **小卡** | 2026-09-04 ~21:28 |
| **C1**（PREWARM=1） | **小卡**，但「有更順的感覺」 | 2026-09-04 ~21:32 |

**判定（暫）：** H1 host page-cache prewarm **未消掉第一下小卡**；可能有邊際改善（體感、非穩定定量）。  
不足以當「第一下命中」主修補 → 記錄後可停 H1 產品化，或再評估 **H2**（進圖後填 Wine file-cache）／接受 known issue。Canvas **檔首 prefix** 也可能沒暖到真正 hit offset。

## 3. 最小實驗（H1）

### 3.1 采樣（不開 `sample`）

1. `FILE_CACHE=1`、`FAST_HIT=0`、低干擾：`IO_TIMELINE`＋`IO_CACHE_STATS`＋`IO_SUMMARY`，stdout 導檔。  
2. arm 時機：進圖可操作後、**打第一下之前** arm。  
3. **不揮空**，打到一隻怪一次即停（或停手幾秒），結束行程。  
4. 從 arm 後 timeline 取出 top path／offset（Mob canvas、Effect、Skill、String／數字等）。

### 3.2 預熱 A／B（體感只看第一下）

| 輪 | 條件 |
|---|---|
| C0 | 不跑命中 prewarm；冷啟動不揮空首打 |
| C1 | 啟動前跑更新後的 `maplestory-prewarm.sh`（僅新命中 range）；其餘同 C0 |

各 ≥2 次。判定：C1 第一下是否 **穩定優於** C0（例如蠻卡→小卡，或小卡→近無感）。若無差 → H1 單獨不夠，記錄後評估 H2 或接受 known issue。

### 3.3 成功／失敗

- **成功：** 第一下體感可重複改善（同角色同圖）。  
- **失敗但有資訊：** I/O 變少但體感無差 → 瓶頸在 PSO／CPU materialize，H1 停。  
- **硬失敗：** 進圖變慢、OOM、預熱超過 byte cap。

## 4. 實作邊界（核准後）

- 先改 **腳本 range 清單＋文件＋launcher 可選 `CYDER_MAPLESTORY_PREWARM=1`**（若尚未接好命中清單）。  
- 不預設對所有使用者開；實驗 flag。  
- 職業／地圖相關 range 可能只對「本次測的角／圖」有效——文件註明。

## 5. 下一步與結案

| 階段 | 結果 |
|---|---|
| H1 host prewarm | C0／C1 皆小卡（C1 略有「更順」感覺）；不足當主修補 |
| **H2** in-process hit-prewarm | verify2 確認已填 ~24 MiB；首擊仍記 **小卡**，但體感 **比未填好很多** → 邊際有效、非主修補；停預設開（flag 保留） |
| **IO-A** 命中窗 summary | top hostdur 多為 Map／Etc／UI 載入噪訊；命中側可見 `Effect_000`／`_Canvas_003`（~111 ms fill）／`_Canvas_053`；**Mob canvas 幾乎無 I/O** → 單一 Mob 檔故事弱 |
| **Effect-verify V1** | host `PREWARM_PROFILE=effect-io-a`（僅上述三檔，~101 MiB，`skipped=0`）vs IO-A：首打體感 **差不多（仍小卡）** → Effect 檔 page-cache **不是**主槓桿 |
| **DXMT A/B** | 同 prefix、`FILE_CACHE=1`、無 prewarm；`cxcompatdb` 確認 `lib/dxmt`；首打 vs D3DMetal **差不多（仍小卡）** → **後端互換不是**主槓桿 |
| **DXMT + H1 prewarm** | `PREWARM=1` profile=`h1`（12 ranges、~119 MiB）；vs 無 prewarm DXMT **好像差不多** → 與 D3DMetal 上 H1 結論一致 |
| **S-air vs S-hit**（低干擾 HUD） | S-air：揮空無感、HUD 小波動。S-hit：小卡、卡時 HUD 停。使用者澄清先前小卡**多半也是 HUD 整片停** → 首打症狀＝**整幀／Present 停滯**（非新現象）；與揮空輕尖峰不同型 |
| **Instruments A** | `Metal System Trace`＋體感小卡：Present／display **~0.65 s 空窗**；hitch 窗 **encoder≈停**、CPU 偏 `AGXBuffer init` → **偏命中 first-use 建 Metal buffer 堵出幀** |
| **V1** | Hit1 小卡／~749 ms Present＋Frame 空窗；Hit2 不卡／無第二段大空窗 → **首次 materialize 為關鍵**；預熱＝真命中一次（M0／M1） |
| **V2** | 先進圖故意打怪（小卡）再打「正式第一下」**不卡** → **M0／M1 預付策略驗證通過** |
| H3／known issue | 第一下更像 **遊戲邏輯／GPU materialize**（跨 D3DMetal／DXMT）；H3-B 不可行。**另：**進圖後**第一次左右**常無效一次＝走路／鏡頭 first-use |

### 5.0 結案證據（詳細）

完整敘事、Instruments 數字、V1／V2 協議與產品含義：  
**[`maplestory-cx26-first-hit-materialize-findings.zh-TW.md`](maplestory-cx26-first-hit-materialize-findings.zh-TW.md)**

### 5.1 建議的後續選項（擇一）

| 選項 | 內容 | 何時選 |
|---|---|---|
| **A. H3-A／產品（推薦）** | M0：說明「進圖後先走一下、先打一下」；可選 M1 實驗 flag | 接受第一下仍會卡，只改付款時機／預期 |
| **B. 低干擾定性** | 進圖後「第一次左右」當下只記 Metal／D3D 是否卡 Present；與首打分開記 | 要確認走路 vs 命中是否同一瓶頸 |
| **C. H3-B（已結）** | 圖形側假暖 PSO | **S1：不可行**（見下） |
| **D. 停手** | 記 known quirk；H1／H2／`effect-io-a` 維持 opt-in | 投入／報酬不足 |

已走過：**H3-B spike** → S1 **不可行**（封閉 GPTK；不進 S2）。規格：[`maplestory-cx26-h3-pso-prewarm-spike-spec.zh-TW.md`](maplestory-cx26-h3-pso-prewarm-spike-spec.zh-TW.md)。

**目前待拍板：** 產品層要做到哪一層？

1. **只 M0**（文件／UI 提示進圖先打一下）  
2. **M0 + M1 實驗 flag**（可選自動普攻一次；預設關）  
3. **接受 known quirk**（不寫產品文案、不做 M1）
