# MapleStory CX26：H2 進圖後填 Wine file-cache — 最小規格

> 狀態：**H2 失敗／資訊性**（D0＝小卡，D1＝小卡；首擊無改善；後續都順）  
> 日期：2026-09-05  
> 依據：H1 C0／C1 → 第一下仍小卡；選 **2＝試 H2**；玩測後停 H2 產品化  
> 總覽：[`maplestory-cx26-hit-path-first-use-cost-plan.zh-TW.md`](maplestory-cx26-hit-path-first-use-cost-plan.zh-TW.md)  
> Patch：`patches/maplestory-cx26-file-cache-hit-prewarm.patch`（opt-in 保留；預設關）

## 1. 目標

在 **Wine userspace adaptive file-cache** 裡，於第一次打怪前，把命中相關
`.wz`／`.ms` 的 window **提前 fill**，降低第一下同步 `NtReadFile`／fill 成本。

驗收只看 **不揮空第一下打到怪**（蠻卡／小卡／無感）。不開 `sample`。

與 H1 差異：H1 只暖 **host page-cache**；H2 填 **Wine 內 cache**（遊戲真走的路徑）。

## 2. 作法比較

| 作法 | 內容 | 優點 | 缺點 |
|---|---|---|---|
| **H2-A 擴充既有 IN_PROCESS prewarm** | 沿用 `CYDER_MAPLESTORY_FILE_CACHE_PREWARM_IN_PROCESS`＋arm／deferred／host-path；**改 target 清單**為 H1 命中檔（Effect／Mob canvas 等） | 基建已在 patch stack；改動面小 | 舊 target 是 Skill pack；要改清單與可能加長 span；無精確 offset 時仍靠檔首／粗 offset |
| **H2-B 全新 hit-prewarm flag** | 另開 `…_HIT_FILE_CACHE_PREWARM` | 與舊被動實驗隔離 | 多旗標、多測試 |
| **H2-C 僅文件不做** | 停在 known issue | 零風險 | 不嘗試壓第一下 |

**建議：H2-A** — 實驗仍用既有 flag（預設關）；把 targets 換成命中清單，必要時加大單檔 prewarm length（仍 bounded）。

## 3. 行為（H2-A）

### 3.1 開關

| 項目 | 值 |
|---|---|
| Flag | `CYDER_MAPLESTORY_FILE_CACHE_PREWARM_IN_PROCESS=1` |
| 依賴 | `CYDER_MAPLESTORY_FILE_CACHE=1`；建議搭配 arm file（進圖後再開始） |
| Host `CYDER_MAPLESTORY_PREWARM` | C1 已測；H2 A／B **預設關**，以隔離變因（可另做「H1+H2」疊加輪） |
| 預設 | **關** |

### 3.2 Target 清單（初版，對齊 H1）

相對 `Data/`（與現有 path match 後綴一致）：

| path | offset | length | 備註 |
|---|---:|---:|---|
| `Effect/Effect_000.wz` | 0 | 64 KiB×N 或至多數 MiB 分段 | 整檔大；用多 chunk／上限 byte |
| `Effect/_Canvas/_Canvas_003.wz` | 0 | 上限內 prefix | 同 H1 無精確 offset 風險 |
| `Effect/_Canvas/_Canvas_053.wz` | 0 | 同上 | |
| `Effect/_Canvas/_Canvas_041.wz` | 0 | 同上 | |
| `Mob/_Canvas/_Canvas_001.wz` 等活躍 canvas | 0 與／或舊 079 mid | 小 span | |
| `Morph/Morph_000.wz` | 0 | 小 | |

**拿掉** 現有 Skill_00000～00006 被動實驗 targets（或移到註解／第二表），避免搶 slot／時間。

總 fill **硬上限**（建議）：與現有實驗精神一致，單次 prewarm 總 bytes ≤ 數十 MiB 級（例如 32～64 MiB），可 env 調。

### 3.3 觸發

1. Flag 開 + cache 開  
2. **Arm 之後**（進圖可操作後 touch arm）才開始 fill（沿用 deferred／arm 行為）  
3. 優先對 **已打開** 的同 path handle fill；無 handle 時走 **host-path fallback**（既有 patch）  
4. 背景／非阻塞於遊戲主邏輯；失敗只 TRACE，不影響讀取正確性  

### 3.4 驗收 A／B

| 輪 | 條件 |
|---|---|
| **D0** | `FILE_CACHE=1`，`PREWARM_IN_PROCESS=0`，host PREWARM=0；不揮空首打 |
| **D1** | 同上但 `PREWARM_IN_PROCESS=1` + arm（進圖後、首打前） |

各 ≥2 次。成功：D1 第一下 **穩定優於** D0。  
失敗但有資訊：prewarm log 顯示 filled>0 但體感無差 → 瓶頸不在 file-cache fill（偏 PSO／CPU）。  
硬失敗：進圖明顯卡、OOM、崩潰 → 關 flag。

## 4. 實作分期

| 階段 | 內容 |
|---|---|
| H2.0 | 本規格核准 |
| H2.1 | 新／amend patch：替換 targets +（可選）總 byte cap；更新 README／tests |
| H2.2 | incremental rebuild `ntdll.so`；D0／D1 玩測 |

## 5. 風險

- 無精確 offset → Effect canvas 仍可能白填檔首（與 H1 相同結構性限制）  
- 進圖後 arm 前若已觸發部分命中資源，效益下降  
- Fill 與遊戲搶 I／O／CPU（Rosetta 下更明顯）→ 必須 bounded + opt-in  

## 6. 核准紀錄

2026-09-05：1 是、2 是、3 是 → 進入 H2.1／H2.2。

## 7. 玩測結果（2026-09-05）

| 輪 | 條件 | 第一下 | 後續 |
|---|---|---|---|
| **D0** | `FILE_CACHE=1`，`PREWARM_IN_PROCESS=0`，host PREWARM=0 | **小卡** | （未特別記） |
| **D1** | `PREWARM_IN_PROCESS=1` + arm（進圖後 touch；開背包觸發；等 ~20 s） | **小卡** | **都很順** |
| **D1-verify2** | 同上 + fprintf 修復；log 確認 `used_bytes≈24 MiB` 後首打 | **有小卡** | （未特別記） |

結論：D1-verify2 **未消掉**第一下小卡，但使用者回報 **「絕對比之前好很多」** → H2 有**體感邊際改善**，仍不足以當「無感首擊」主修補。剩餘瓶頸更偏 **首次 materialize／PSO／CPU**（見總覽 H3／known issue）。

（D1 當輪因 pthread＋`TRACE_` 卡住，**實際未填**；以 D1-verify2 為準。）

**2026-09-06 產品決策：** 複看 ablation／測試影片後，host prewarm 與 H2 **不納入下一版 engine**。`maplestory-cx26-file-cache-hit-prewarm.patch` 移出 `--maplestory` apply list 與 `engine-release.json`；patch 檔保留供研究。Launcher 的 `CYDER_MAPLESTORY_PREWARM` 維持實驗開關、非產品功能。
