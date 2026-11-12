# MapleStory CX26：首次命中路徑預熱設計

> 狀態：設計草案；**實作暫停**，先跑實驗矩陣確認整體狀況  
> 日期：2026-09-04  
> 依據：[`maplestory-cx26-wz-cache-experiments.zh-TW.md`](maplestory-cx26-wz-cache-experiments.zh-TW.md) §13  
> 相關：既有 host prewarm `scripts/maplestory-prewarm.sh`（僅 page-cache／WZ range）

## 1. 問題陳述

使用者可感知的「第一次打怪很卡」，在固定 D3DMetal／adaptive WZ cache 條件下：

1. **`FILE_CACHE_FAST_HIT` 無體感改善** → 再縮短 cache-hit `NtReadFile` 不是主線。
2. **冷啟動首次打怪「蠻卡」** 與 `D3DMetal.PSOCompilationQueue`／`MTLCompiler` 同時出現。
3. **對空氣先攻擊／放技能** 後，首次打怪多降為「小卡」→ 攻擊放出路徑可暖；
   **命中怪**仍有殘餘成本（命中特效、傷害字、怪物受擊／資源等）。
4. 歷史上 DXVK／DXMT 也有類似首次卡 → 不能只靠換圖形後端。

目標：在**非互動或低風險時段**，把「攻擊放出＋命中／受擊」的 first-use 成本
提前消化，使使用者第一次真正打怪接近已預熱後的「小卡」或更低。

## 2. 成功標準

| 等級 | 定義 | 驗證 |
|---|---|---|
| S0 | 文件化可重複手動預熱協議 | 同一角色／地圖，≥3 輪體感一致 |
| S1 | 跨行程後，冷啟動首次打怪 ≤「小卡」 | 與同日「對空氣後」對照；可選 `sample` |
| S2 | 無需使用者手動揮空；預設或 opt-in 自動完成 | 進圖後 N 秒內完成；可取消／有上限 |
| 硬失敗 | 觸發防作弊誤判、誤傷怪、明顯拖慢進圖、記憶體失控 | 任一出現即回退 flag |

非目標：消掉所有戰鬥中偶發卡頓、取代 adaptive WZ cache、修改 MapleStory.exe。

## 3. 方案比較

### 方案 A — 跨 session Metal／D3DMetal PSO／shader 快取持久化

**做法：** 調查 GPTK／D3DMetal 是否已寫入 disk shader／pipeline cache；確認
Cyder prefix／Application Support 路徑是否在每次重裝或清 prefix 時被丟掉；
必要時固定 cache 目錄、文件化保留策略，或在登入／loading 期間觸發無害
present／dummy draw（若 API 允許）以填充 cache。

| 優點 | 風險 |
|---|---|
| 不注入遊戲輸入；防作弊面較小 | 可能無法覆蓋「僅在命中時才 compile」的 PSO |
| 跨天／跨行程受益 | 依賴封閉 GPTK 行為；版本升級可能失效 |
| 與 DXVK pipeline cache 類比清晰 | 無法解釋 DXVK／DXMT 也曾卡的「共用資源」部分 |

**適合：** S1 的主力候選之一。

### 方案 B — 進圖後 gameplay soft-prewarm（合成攻擊／安全命中）

**做法：** 偵測「地圖就緒」（既有 present／視窗／loading 結束訊號），在短窗內：

1. 先 materialize **揮空攻擊／主要技能鍵**（對齊手動實驗）。
2. 再嘗試 **命中路徑**：僅在確認附近有怪且不會致死／不會觸發任務誤點時
   打一下；或找「可命中但不進戰鬥狀態」的替代（若遊戲無此 API 則放棄）。

實作落點可選：Wine／launcher 注入鍵盤、Cyder 側輔助、或僅開發用腳本。

| 優點 | 風險 |
|---|---|
| 直接對齊已證實有效的手動預熱 | **防作弊／ToS**；預設開啟危險 |
| 可同時暖攻擊＋部分命中 | 時機錯誤會誤傷怪、打斷 UI |
| 不需逆向完整 WZ 資源圖 | 職業／鍵位／地圖差異大 |

**適合：** 僅 **opt-in 實驗 flag** 或開發協議；產品預設需極高門檻。

### 方案 C — 擴大資源／I/O 預熱（WZ／MS range＋既有 prewarm 腳本）

**做法：** 從 hit 當下 timeline／trace 抽出 Skill／Character／Effect／數字／怪物
相關 offset，擴大 `maplestory-prewarm.sh` 與（可選）in-process prewarm；
不模擬繪製。

| 優點 | 風險 |
|---|---|
| 已有腳本與 file-cache 基建 | **消不掉 PSO 編譯**（§13 已證明） |
| 防作弊面低 | 範圍選錯浪費 I/O／記憶體 |
| 可與 A／B 疊加 | 單獨達不到 S1／S2 |

**適合：** 輔助層，不當唯一解法。

### 方案 D — Loading 期間圖形側「假繪製」暖 PSO（無遊戲邏輯）

**做法：** 在 D3DMetal／Wine 圖層，於 loading／黑屏時用近似狀態建立／編譯
常見 pipeline（若能從先前 session 或靜態清單得知）。

| 優點 | 風險 |
|---|---|
| 不碰遊戲輸入 | 需圖層 hook；清單難準 |
| 可專門打 PSO | 錯清單＝白忙；維護成本高 |

**適合：** 若方案 A 證明 cache 無法跨行程，再評估。

## 4. 建議路線（實驗前暫定；矩陣完成後可能改）

先前暫定 **A 為主、C 為輔、B 僅實驗**。§5.1 已顯示：disk Metal cache 在蠻卡當下
**早已存在**，因此 A 的產品價值存疑，**必須先跑完 §5.2** 再鎖定實作。

## 5. Phase 1 調查清單（實作前）

1. GPTK／D3DMetal 在本機寫入哪些 cache 目錄（路徑、大小、是否 per-prefix）。
2. 清掉該目錄後，冷啟動首次打怪是否回到「蠻卡」。
3. 保留該目錄、只重開遊戲，是否穩定「小卡」或更低。
4. Cyder 正式安裝／更新／清 prefix 是否誤刪該 cache。
5. 同一角色換圖後首次攻擊是否仍卡（區分 session cache vs 地圖資源）。

輸出應寫回本文件「調查結果」小節與 experiments §13 附錄。

## 5.1 非互動調查結果（2026-09-04，尚未清 cache 玩測）

### D3DMetal／GPTK API 層

`D3DMetal` binary 字串含：

- `Unsupported: CreateShaderCacheSession`
- `Unsupported: ShaderCacheControl`

→ **Windows 風格 shader cache session API 在此 GPTK 建置上標為不支援**；
不能假設「開 D3D shader cache」就能產品化。跨行程效益若存在，較可能來自
**OS Metal 函式／library disk cache**，而非 D3D API。

### 本機實際 disk cache（與今日 fasthit 玩測時間重疊）

| 身份／路徑 | 約略大小 | 今日是否更新 | 備註 |
|---|---:|---|---|
| `…/C/com.codeweavers.CrossOver.wineloader/com.apple.metal` | ~31 MiB | 是（`.list` 於 18:10、19:04） | **CX26／D3DMetal 玩測主身份** |
| `…/C/dxmt/MapleStory.exe/`（含 `shaders_320.db`＋metal） | ~1.1 MiB | 是（17:33） | DXMT 路徑；與 D3DMetal 分離 |
| `…/C/org.winehq.wine/com.apple.metal` | ~1.7 MiB | 否（7 月） | 非本次主路徑 |
| `…/C/com.nexon.maplestoryna_exe/com.apple.metal` | ~764 KiB | 否（7 月） | 原生／其他 Maple 身份 |

Cyder `Application Support/…/apple_gptk` 內**未**發現獨立 `ShaderDataDX12.bin`
runtime 產物；GPTK 目錄主要是 framework／dll。

### 對照既有 sample（cache 已存在時仍蠻卡）

同日在 **wineloader Metal cache 已有 Aug 資料、且 list 有更新** 的情況下：

| 樣本 | PSOCompilationQueue 相關命中數（粗計） | 體感 |
|---|---:|---|
| `sample-first-hit-20s-183057.txt` | ~67 | 蠻卡 |
| `sample-prewarm-then-hit-20s-190629.txt` | ~23 | 小卡 |

**暫訂解讀（E2／E3 已跑）：** disk Metal cache **無法單獨**消掉首次打怪卡頓，且
**清掉也不會明顯變糟**（E3 ≈ E2 小卡）。同 session 的 gameplay 路徑 materialize
（對空氣，E5）仍是已證實有效的體感槓桿。方案 A 產品價值低。

### 玩測進度（進行中）

| ID | 結果 | 時間 |
|---|---|---|
| E2（保留 Metal cache、不揮空、首打） | **小卡** | 2026-09-04 ~19:53 |
| E3（清 wineloader Metal cache 後首打） | **與 E2 差不多（仍小卡）** | 2026-09-04 ~19:55 |
| E4（同 session 換圖後不揮空首打） | **不再變卡** | 2026-09-04 ~19:56 |
| E1-clean（不開 `sample`、不揮空首打） | **卡頓沒那麼嚴重、稍微順一些**；HUD 確認 **GPTK 4.0b2**（非 DXMT） | 2026-09-04 ~20:28 |
| E1-clean 重複 | **小卡**（覺得沒上一輪那麼順） | 2026-09-04 ~20:33 |
| E1-clean 再重複 | **蠻卡**（仍不開 `sample`） | 2026-09-04 ~20:38 |
| E1-clean＋對空氣對照 | 不揮空首打 **小卡**；對空氣後再打 **很順** | 2026-09-04 ~20:46 |
| B1.1 手動首擊預熱 | P1 **小卡**、P2 順；後澄清＝已知「首下卡、之後順」，**未證明第一下變順**；M0 僅時機／預期 | 2026-09-04 ~21:01～21:06 |
| H1 采樣 #1 | 首打 **小卡**；exit 有 Effect canvas summary，**無 timeline** | 2026-09-04 ~21:15 |
| H1 采樣 #2 | 首打 **小卡**；待正常退出再抽完整 aggregate | 2026-09-04 ~21:20 |
| IO-A（FILE_CACHE+IO_TRACE／PROFILE，無 H2） | 首打 **小卡**；Effect canvas 有 fill；Mob 幾乎無 I/O | 2026-09-05 ~17:10 |
| Effect-verify V1（`PREWARM_PROFILE=effect-io-a`） | vs IO-A **差不多（仍小卡）** → Effect page-cache 非主槓桿 | 2026-09-05 ~17:20 |
| **DXMT A/B**（`FILE_CACHE=1`、無 prewarm） | vs D3DMetal **差不多（仍小卡）** → 後端互換非主槓桿 | 2026-09-05 ~17:30 |
| **DXMT + PREWARM=1（h1）** | vs 無 prewarm DXMT **好像差不多（仍小卡）** | 2026-09-05 ~17:36 |
| **S-air**（D3DMetal、arm 後只揮空） | 揮空 HUD 小波動、**體感無卡**；走動／見怪 HUD 較大波動仍不特別卡 | 2026-09-05 ~17:59 |
| **S-hit #1** | 不揮空首打 **小卡**；HUD 未看 | 2026-09-05 ~18:07 |
| **S-hit #2** | 小卡；卡時 HUD 停住，恢復後大→小波動。使用者補充：**先前各輪小卡多半也是 HUD 整片停**，只是以前沒細看 → 長期症狀＝整幀／Present 停滯 | 2026-09-05 ~18:12 |
| **Instruments A**（Metal System Trace，首打小卡） | Present／surface **~0.65 s 空窗**；**Frame 246→247**；encoder 近乎停；hitch 內 wine CPU **~93% 在 `AGXBuffer init…` 執行緒**（Metal buffer 配置）→ 偏 **命中首用觸發 Metal／AGX 緩衝區建立，堵住出幀提交** | 2026-09-05 ~18:21 |
| **V1 Hit1 vs Hit2** | 體感 Hit1 小卡、Hit2 不卡；Trace：**Present／Frame 空窗 ~749 ms**（Frame 323→324）；Hit1 後 8 s+ **無 ≥100 ms 空窗** → **首次 materialize＝卡頓關鍵**；同 session 第二次命中已暖 | 2026-09-05 ~18:48 |
| **V2 先付再打** | HitA（故意首打）小卡；HitB（正式第一下）**不卡** → **預先真命中 materialize 有效**（即 M0／M1 策略） | 2026-09-05 ~18:54 |


### HUD 整片停住＝什麼（2026-09-05 研究摘要）

Metal Performance HUD 掛在 **CAMetalLayer／drawable 呈現循環**上：有新幀成功 present，數字才會更新。  
**整片凍結** ≠「某一幀 GPU 稍慢但仍在出幀」；而是該段時間內 **呈現循環沒有完成**（畫面與 HUD 一起停）。

| HUD 現象 | 含義 |
|---|---|
| 持續更新＋小波動（S-air） | 幀有交出；成本低於感知或只拉長單幀 |
| **整片停住**（S-hit／歷來小卡） | 多個 vsync 內沒有成功 Present；恢復後大→小波動＝堵住的工作結束後的追趕尖峰 |

**較可能的機制（可並存，且都會造成 HUD 停）：**

1. **Present 同步等待 GPU／pipeline 就緒（高）** — 命中首用 pipeline／資源在背景編譯或首次提交；呈現執行緒卡在 `Present`／semaphore；舊 sample 方向一致（但 `sample` 會污染，只能當線索）。DXMT 同症 → 不必是 GPTK 專屬。  
2. **遊戲邏輯執行緒 first-use 堵死出幀（高）** — 命中才走的傷害字／特效／受擊狀態在 Rosetta 下首次建立；若與提交幀同線或持鎖，Present 根本叫不到 → HUD 同樣停。揮空不走這條。  
3. **I/O 同步 fill（低～邊際）** — 預熱無效／H2 僅邊際 → 不足以單獨解釋「整片停」長度。

**較不像：** 單純 HUD bug、Cocoa main-thread 編譯（舊 sample 裡 main-thread 多在 RunLoop）、音效／字型、OS Metal disk cache（E2／E3）。

精準一句：體感「小卡」＝**命中路徑第一次把出幀管道堵住**；HUD 停住是症狀標誌，不是獨立病因。

**2026-09-05 結案（Instruments A＋V1＋V2）：**  
詳見 [`maplestory-cx26-first-hit-materialize-findings.zh-TW.md`](maplestory-cx26-first-hit-materialize-findings.zh-TW.md)。  
重點：Present／Frame 空窗約 **0.65–0.75 s**；hitch 內 CPU 偏 **AGXBuffer init**；Hit2／預付後正式第一下不卡；揮空無效；隱形假暖不可行；產品緩解＝M0／M1 預付。

使用者補充（同日）：**本來就只有第一次攻擊怪物會卡，之後都順**——與 E4／E5 一致，屬 session 級 first-use，不是持續性效能問題。

進一步區分（~20:49）：**對空氣普攻／攻擊技能都順**；卡頓在 **打到怪物**、以及 **被怪物打到（機率觸發被動）**。  
→ 「攻擊放出」與「命中／受擊／被動」是不同 first-use 集合；只暖揮空不能完整覆蓋後者。

乾淨體感（不開 `sample`）同條件已見：**稍微順／小卡／蠻卡**；對空氣後再打到怪可到 **很順**（可能仍有部分共用 pipeline 被提前暖到）。`sample` 會再放大卡頓。

### 能否針對「命中／受擊／被動」優化？

**可以，而且比「泛用揮空預熱」更對症**；但引擎側做不到遊戲邏輯層的「假命中」，選項與代價不同：

| 作法 | 能暖到什麼 | 難度／風險 |
|---|---|---|
| **B1 安全真命中**（進圖後打一下低危怪／木樁類） | 命中特效、傷害字、怪物受擊 | 需怪；誤傷／任務／防作弊風險；opt-in |
| **B2 受擊／被動** | 受擊特效、被動技能 VFX | **幾乎必須真的被打到或觸發被動**；自動預熱更難、更敏感 |
| **C 資源預熱**（WZ／特效／數字／該職業常見被動相關檔） | 降低 I/O／部分建立成本 | 防作弊面低；**消不掉**專屬 PSO／首次 draw；清單依職業維護 |
| **說明／known issue** | 無 | 誠實對應「第一次打到／被打到會卡一下」 |

建議：若做優化，目標改寫成 **「第一次命中／受擊前的 materialize」**，不要再以「對空氣」當完整解。最小實驗可以是：進圖後 **刻意打一下怪**（付一次小卡）再練——產品若自動化，只做 opt-in 的 B1；B2 預設不要自動。

**B1 最小規格（草案）：**  
[`maplestory-cx26-b1-safe-first-hit-prewarm-spec.zh-TW.md`](maplestory-cx26-b1-safe-first-hit-prewarm-spec.zh-TW.md)

### 決策更新（E2／E3／E4 後）

- **E2 小卡、E3 差不多** → 跨行程保住／清掉 `wineloader` Metal disk cache，**對「不揮空首次打怪」體感無明顯槓桿**。
- 方案 A（產品化「固定／保留 Metal／GPTK cache」）**降優先**，不當主修補。
- **E4 換圖不再變卡** → 殘餘 hitch 比較像 **session／角色戰鬥路徑 first-use**，不是「每張地圖／每隻怪」都重來一輪；C 若做，應偏職業／技能／命中通用資源，而非掃全圖 WZ。
- 先前「cache 已在仍見 PSOCompilationQueue」與 E3 一致：OS Metal cache 不是首次命中 hitch 的主開關。
- 已證實有效槓桿仍是 **真命中一次（V1／V2）**；揮空**不能**可靠暖命中路徑。實作方向收斂為：
  1. 接受「每 session 第一次小卡」為 known issue + 文件說明；
  2. 或 B1／M0／M1：進圖後 opt-in／提示真命中預付（策略已驗證）；
  3. 檔案預熱（H1／H2）僅邊際，不當唯一解。

### 為何 Windows 幾乎無感：轉譯執行鏈瓶頸假說

遊戲在 Windows／Mac 多半都是「第一次用到才 materialize」的懶載入；Windows 無感，
較像是 **同一套 first-use 工作在 Mac 被多層轉譯放大到可感知**，不是 Windows 完全不做。

```text
Windows：MapleStory native → NT/Cache Manager → D3D → WDDM → GPU
Cyder：  MapleStory → Wine ntdll/Unix →（整條 x86_64 在 Rosetta）
         → D3D → D3DMetal/DXVK/DXMT → Metal PSO/MTLCompiler → GPU
```

蠻卡樣本：`Code Type: X86-64 (translated)`，堆疊大量 `Rosetta JIT`，同窗
`D3DMetal.PSOCompilationQueue`／`MTLCompiler`。

| 優先 | 機制 | 為何 Windows 較無感 | 與實驗關係 |
|---|---|---|---|
| **P0** | D3D→Metal（或 VK→Metal）**PSO／shader 首次編譯**，易與 Present／邏輯幀同步 | 原生驅動快、shader cache 成熟；D3DMetal 對 `CreateShaderCacheSession` 為 Unsupported | 蠻卡 sample 重；對空氣後 PSO 降；E2／E3 清 OS Metal 目錄體感差不多 → 主因較像「當次 pipeline 變體第一次編譯」，不是那 31 MiB `functions.data` |
| **P0** | **懶載入被放大**：技能／命中／傷害字／受擊的 CPU 建立＋GPU upload | Windows 同樣懶，但常 < 一幀 | E5 有效；E4 換圖不再卡 → session 級 first-use |
| **P1** | **Rosetta JIT 冷碼**：首次走進攻擊／粒子／解析熱路徑 | Windows 無 CPU 轉譯稅 | 與「每 session 第一次」同型；難單獨定量 |
| **P1** | **Wine 小 I/O 固定成本**（cache hit 仍走 `NtReadFile`）在 Rosetta 下累加 | Windows Cache Manager／section 極便宜 | Bin 209 成立；FAST_HIT 無體感 → 非蠻卡主旋鈕，可能叠在同一幀 |
| **P2** | 主執行緒把載入＋第一次 draw 綁死 | Windows 也同步，但總時長短 | 對空氣＝把成本挪到非關鍵時刻 |
| **P2** | 各後端 pipeline cache 不完整 | Windows 驅動 cache 通常更耐用 | DXVK／DXMT 也曾首次卡 |
| **P3** | 音效／字型／防作弊轉譯 | 原生同樣有對應物 | 證據弱於「對齊攻擊／命中」 |

精準說法：不是單一「Rosetta」或單一「GPTK」，而是懶載入 ×（Rosetta＋Wine＋圖形 API 轉譯＋PSO）擠在同一短窗。Windows 只有懶載入的原生版，常低於感知閾值。

區分兩種編譯：OS Metal disk cache（E2／E3 顯示非體感主開關）vs D3DMetal **PSOCompilationQueue** 即時編譯（與蠻卡同窗，較像主開關之一）。

### P0／P1 拆解：既有蠻卡 sample 重讀（2026-09-04）

對象：`sample-first-hit-20s-183057.txt`（使用者確認蠻卡窗；20s／1ms）。  
對照：`sample-prewarm-then-hit-20s-190629.txt`（預熱後小卡）。

**結論（先回答「主執行緒是否在等 PSO」）：**

| 執行緒 | 在等什麼 | 解讀 |
|---|---|---|
| `com.apple.main-thread`（Cocoa） | 幾乎全程 `mach_msg`／RunLoop | **不是**遊戲邏輯執行緒；**沒有**在等 PSO |
| Wine／D3D 呈現執行緒（`Thread_*` 含 `DXGISwapChain::Present1`） | **~54%** 樣本在 `Present1` → `_dispatch_semaphore_wait` | **卡在 Present 同步**，不是自己跑 `MTLCompiler` |
| `D3DMetal.PSOCompilationQueue` | 同窗僅 **1～3** 樣本／執行緒，但堆疊確有 `CreateRenderPipelineState`／`MTLCompiler` | PSO **在背景 queue 編譯**；呈現執行緒靠 semaphore **等 GPU／提交完成** |

補充：同呈現執行緒另有 **~22%** 在 `__wine_syscall_dispatcher`（Wine／I/O／等待路徑），以及大量 `Rosetta JIT` 葉節點。  
預熱後樣本：`PSOCompilationQueue`／`MTLCompiler` 行數明顯下降；semaphore 相關也變少——與體感「小卡」一致。

**對 P0／P1 的含義：**

1. **P0 成立形態**不是「主執行緒卡住編譯器」，而是 **Present 執行緒被 GPU／pipeline 就緒擋住**，同時背景在編譯新 PSO。這仍屬圖形 first-use，且會造成可見掉幀。
2. **P1（Rosetta／Wine）** 同窗存在，但是呈現執行緒上的次要份額；不足以單獨解釋 Present semaphore 那一半。
3. 若要更乾淨的時間對齊，仍建議再跑一輪 **短 sample（5s）**，在使用者按出第一下的瞬間開始，專門對 `MapleStory.exe` 且標記「開始」。

### 採樣偏差警告（2026-09-04 20:13 使用者回報）

同輪 P0／P1 首打 sample（`sample-p0p1-first-hit-20s-201139.txt`）體感 **蠻卡**，但使用者指出：

- **一開 `sample` 就明顯變卡**（不只打怪瞬間）。
- 角色不動時，**MIDI 也會斷斷續續**。

→ macOS `sample`（高頻中斷＋轉譯行程）本身會干擾音訊與幀節奏。  
因此「Present 執行緒 ~58% 在 `_dispatch_semaphore_wait`」**只能當假設線索，不能當未污染的根因證明**。先前 183057 蠻卡樣本同樣可能被放大。

**之後量測原則：**

1. 體感 A／B（對空氣 vs 不揮空、E2／E3）仍有效——那些輪次**不必**開 `sample`。
2. 需要時間線時，改用低干擾手段（擇一）：Metal／Instruments **Time Profiler 抽樣率調低**、只打 frame／Present 耗時 log、或既有 `CYDER_IO` aggregate（勿逐筆）。
3. 不再用「開著 20s `sample` 的蠻卡」當 P0 定量依據。

### DXVK／DXMT

- DXMT：已有 per-exe `shaders_320.db`＋Metal 子目錄 → 後端專屬 cache 存在。
- DXVK：本輪未掃到與 fasthit prefix 綁定的新鮮 `*.dxvk-cache`；跨後端結論仍靠玩測。

## 5.2 實驗矩陣（先確認整體狀況，再決定實作）

固定：同一角色、同一安全練功圖、`FILE_CACHE=1`、`FAST_HIT=0`、D3DMetal、
prefix `/private/tmp/cyder-cx26-fasthit-play`（或新記一輪 prefix）。  
體感只用：蠻卡／小卡／無感。可選 20s `sample`（協議同 §6）。

| ID | 操作 | 要回答的問題 |
|---|---|---|
| **E1** | 冷啟動進圖 → **不**揮空 → 首次打怪 | 基線（已知偏蠻卡） |
| **E2** | E1 後正常退出 → **不**清 Metal cache → 重開 → 不揮空 → 首次打怪 | 跨行程 OS Metal cache 有無體感幫助 |
| **E3** | 備份後移除／改名 `com.codeweavers.CrossOver.wineloader/com.apple.metal*` → 重開 → 不揮空 → 首次打怪 | disk cache 是否為必要條件；清掉是否更糟 |
| **E4** | 同 session：換一張有怪的圖 → 不揮空 → 該圖首次打怪 | 地圖／怪物資源 vs 全域 PSO |
| **E5** | 同 session：對空氣預熱 → 打怪（已做） | 攻擊路徑可暖；命中殘餘 |
| **E6**（可選） | 同一協議在 DXMT（或 DXVK）各跑 E1＋E2 | 跨後端共用 vs 後端專屬比例 |
| **E7**（可選） | E1 當下同時看 WZ timeline／低干擾 cache_stats | I/O 是否與蠻卡同窗占主導 |

**決策門檻（實驗完再選實作）：**

- 若 **E2 ≈ E1 仍蠻卡** 且 **E3 明顯更糟或差不多**：方案 A 產品價值低 → 偏向 B／C 或接受殘餘。
- 若 **E2 明顯優於 E1** 且 **E3 回到蠻卡**：方案 A（保留／固定 wineloader Metal cache、避免被清）值得做。
- 若 **E4 仍蠻卡**：地圖／怪物資源是獨立問題 → 加強 C 或 gameplay 命中預熱。
- 若 **E6 三後端 E1 都蠻卡、E5 都改善**：共用資源／gameplay 預熱優先於任何單一後端 cache。

## 6. 手動預熱協議（S0，立即可用）

進安全地圖、確認可操作後、**打第一隻怪之前**：

1. 對空氣普通攻擊 ≥3 下。
2. 對空氣主要輸出技能各 ≥1 下（技能重的職業多暖幾下）。
3. 再打第一隻怪；記錄體感：蠻卡／小卡／無感。
4. 若要採樣：先起 20s `sample`，聊天「開始」後再執行 1→3。

此協議用於回歸，不作為長期 UX。

## 7. 產品邊界（若進入 Cyder）

- 預設：**不**注入鍵盤；不承諾「零首次卡」。
- 可對使用者說明：首次進圖後短暫卡頓與特效編譯有關；之後同 session 會改善。
- 若提供進階選項「進圖戰鬥預熱」：必須 opt-in、可關閉、有逾時、文件註明風險。
- Engine flag 與 Cyder UI 分開；engine 預設全部關閉。

## 8. 與既有元件關係

| 元件 | 角色 |
|---|---|
| `CYDER_MAPLESTORY_FILE_CACHE=1` | 保留；一般 WZ 小讀 |
| `FILE_CACHE_FAST_HIT` | 保持關閉；非 hitch 主線 |
| `scripts/maplestory-prewarm.sh` | Phase 2 擴 range 的載具 |
| D3DMetal launcher | Phase 1 cache 路徑與 env 掛載點 |
| CompatDB | 僅傳遞 flag；不承擔預熱邏輯 |

## 9. 開放問題（實驗矩陣完成後再拍板）

E2／E3／E4 與乾淨體感已完成；方案 A 降優先。B1 規格見  
[`maplestory-cx26-b1-safe-first-hit-prewarm-spec.zh-TW.md`](maplestory-cx26-b1-safe-first-hit-prewarm-spec.zh-TW.md)。

待拍板（B1 §7）：

1. 產品是否先只做 M0（提示），M1 僅實驗 flag？  
2. 無可靠「有怪」偵測時是否禁止 M1 上正式產品？  
3. 預熱窗 5s、僅 1 次普攻是否作為 v1 上限？

---

**下一步：** 審閱並核准 B1 最小規格；核准前不寫注入碼。
