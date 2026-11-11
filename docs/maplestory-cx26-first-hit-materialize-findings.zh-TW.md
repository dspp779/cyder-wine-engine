# MapleStory CX26：首次打到怪卡頓 — materialize 證據與結論

> 狀態：**結案證據已齊**（2026-09-05）  
> 總覽：[`maplestory-cx26-hit-path-first-use-cost-plan.zh-TW.md`](maplestory-cx26-hit-path-first-use-cost-plan.zh-TW.md)  
> 產品緩解規格：[`maplestory-cx26-b1-safe-first-hit-prewarm-spec.zh-TW.md`](maplestory-cx26-b1-safe-first-hit-prewarm-spec.zh-TW.md)  
> 背景設計：[`maplestory-cx26-first-hit-prewarm-design.zh-TW.md`](maplestory-cx26-first-hit-prewarm-design.zh-TW.md)  
> H3-B（假暖 PSO）：[`maplestory-cx26-h3-pso-prewarm-spike-spec.zh-TW.md`](maplestory-cx26-h3-pso-prewarm-spike-spec.zh-TW.md)（**不可行**）

## 1. 一句話結論

冷啟動後**第一次打到怪物**的小卡，是 **命中路徑首次 materialize** 把 **Metal 出幀提交堵住約 0.65–0.75 s**；  
**揮空暖不到**這條路。同 session **再打一次就不卡**。  
引擎側無法隱形假暖（H3-B 不可行；檔案／後端預熱無效）。  
**已驗證有效的緩解**：進圖後先**真的打到怪一次**（M0 提示／可選 M1），把卡挪到「試刀」，正式練功第一下就不卡。  
**付費那一下的幅度不會變短**——只改時機與預期。

## 2. 現象定義（已穩定）

| 項目 | 觀察 |
|---|---|
| 觸發 | 冷啟動（或新 session）後，**不揮空、第一次打到怪物** |
| 體感 | 小卡～蠻卡；整屏像凍住 |
| Metal HUD | **整片停止更新**（非僅小尖峰）；恢復後常見大波動再小波動 |
| 揮空普攻／技能放出 | 通常**無感**或僅 HUD 小波動（見 §2.1 影片） |
| 同 session 之後再打怪 | **順**（換圖後通常也不再同樣卡） |
| 後端 | D3DMetal 與 DXMT **都有** |
| Windows | 同懶載入結構，但通常低於感知閾值 |

### 兩條不同的 first-use（再細分為多包）

| 路徑 | 典型內容 | 揮空／未命中會不會暖到 |
|---|---|---|
| 攻擊放出 | 揮擊動畫、主動技放出、一般出幀 | 會（或部分） |
| **命中結果** | 傷害字、命中特效、怪物受擊相關圖形資源 | **不會** |
| Buff／被動表現 | 自我增強、被動觸發光效等（見 §2.2） | 與命中**不同包**；互不保證暖到 |

因此：「先揮空再打怪」**不能**可靠代替「先真的打到怪一次」。  
「先開 buff／觸發被動」也**不能**代替真命中（§2.2）。

規則收斂（2026-09-06 劍豪確認）：

- 主動技第一次**只放出、沒打到怪** → 通常**不卡**（先前誤讀成「有些技能命中也不卡」）。
- **只要第一次打到怪**（普攻或任何招）→ **一定會卡**（阻塞 HUD 那種）。
- 同 session 命中路徑暖過後再打 → 通常不卡（V1／V2）。

### 2.1 影片時間軸觀察（2026-09-06 ablation 玩測）

錄影複看（同 session 多輪；`MTL_HUD=1`）補上肉眼／體感不易分開的細節：

| # | 操作 | FPS／HUD | 畫面體感 |
|---|---|---|---|
| 1 | **打開背包** | HUD 極短暫停一下 | **極度輕微**小頓；沒錄影幾乎注意不到 |
| 2 | **朝空氣攻擊** | **兩段** FPS 波動（先大再小）；HUD **不停** | **不卡** |
| 2b | 揮空後再**真命中** | **一段**大 FPS 波動；HUD **停** | **小卡**（與結案現象同） |
| 3 | **不揮空、直接真命中** | ① 先一大段 FPS 波但畫面／HUD **尚未卡** → 歸平 → ② 畫面＋HUD **一起卡** → 再一大段波動 | ② 才是可感「小卡」 |

解讀（與 §4 Instruments 對齊）：

- 揮空只付到**非阻塞／半路徑** first-use（FPS 有波、Present 仍在交）。
- 真命中才付到**阻塞 Present** 的 materialize（HUD 整片停 ≈ §4.1）。
- 直接真命中的「先大波不卡 → 再卡」＝至少兩段：可與出幀並行的尖峰，加上之後堵住出幀的那段；錄影把兩者分開了。
- 開背包的極輕微頓屬**另一條**小 first-use（H2 用開背包觸發 arm 時也會碰到）。

### 2.2 劍豪技能分桶（2026-09-06 體感）

職業：劍豪。用來區分「技能名差」vs「有沒有打到怪」vs「buff／被動」。

| 包 | 技能 | 類型 | 第一次行為 | 互暖 |
|---|---|---|---|---|
| **放出** | 霧斬、掠斬、驅散烏雲、逆流斬、殘影斬 | 主動攻擊技 | 第一次**未打到怪**時**不卡** | — |
| **Buff／被動表現** | **無心**、**偏離** | 無心＝主動自我增強；偏離＝被動 | 任一個第一次觸發**會卡** | 暖過其中一個後，另一個**不卡** |
| **真命中** | 普攻（及任何打到怪） | 命中結果 | **只要打到怪就一定卡**（該 session 尚未暖過時） | Buff／被動包**暖不到**；無心／偏離之後，第一次普攻真命中**仍卡** |

含義：

1. 「霧斬等第一次不卡」＝**只放出、沒命中**，不是招式白名單，也與 WZ file-cache 無關。  
2. 無心 ↔ 偏離＝**同一包**角色狀態／buff／被動表現 materialize（B2 附近），**≠** 真命中包（B1）。  
3. 產品預熱若目標是「正式開打第一下不卡」，必須付 **真命中**；只開無心或觸發偏離不夠。  
4. 技能之間的體感差，主因是踩到**哪一包尚未建立的 first-use**，不是 FAST_HIT／H2 有沒有 cache 到。

## 3. 已排除的槓桿

| 實驗 | 結果 | 含義 |
|---|---|---|
| H1 host page-cache prewarm | C0／C1 皆小卡 | 磁碟 page-cache 非主因 |
| Effect-only prewarm（`effect-io-a`） | vs IO-A **差不多** | Effect 大檔預熱非主因 |
| H2 in-process file-cache prewarm | 填 ~24 MiB 後仍小卡（可有邊際）；§5.3 A2／A3 再確認 | userspace WZ fill 非主修補 |
| E2／E3 Metal disk cache | 保留≈清掉，體感差不多 | OS Metal disk cache 非主開關 |
| DXMT vs D3DMetal | 首打都小卡 | 非 GPTK／D3DMetal 專屬 |
| DXMT + H1 prewarm | 好像差不多 | 同上 |
| H3-B 假暖 PSO | S1：**不可行**（封閉 GPTK） | 引擎無法安全假繪製命中 pipeline |
| FAST_HIT | 無首打體感改善；§5.3 A1／A3 再確認 | 非此卡頓主旋鈕 |

原始玩測表見 [`maplestory-cx26-first-hit-prewarm-design.zh-TW.md`](maplestory-cx26-first-hit-prewarm-design.zh-TW.md)。

## 4. 機制：出幀停滯 ≈ 首次 materialize

### 4.1 HUD 整片停＝什麼

Metal Performance HUD 掛在 **CAMetalLayer／drawable 呈現循環**上。  
數字不跳＝該段時間**沒有成功 Present 新幀**（畫面與 HUD 一起凍）。

| HUD | 含義 |
|---|---|
| 持續跳＋小波動（揮空） | 幀有交出 |
| **整片停**（首打） | 多個 vsync 無 Present；恢復後追趕尖峰 |

使用者澄清（2026-09-05）：先前各輪「小卡」多半也是 HUD 整片停，只是以前沒細看。

### 4.2 Instruments A（單次首打，~18:21）

- 模板：`Metal System Trace`，attach `wine`／MapleStory，約 15–16 s  
- Trace：`/private/tmp/cyder-cx26-fasthit-play-logs/instruments/s-hit-metal-20260905-182113.trace`  
- 體感：一樣小卡  

| 指標 | hitch 窗（約 t=4.10–4.76 s） | 對照 |
|---|---|---|
| Present 間隔 | **~655 ms 空窗** | 平常中位 ~13 ms |
| Surface swap | **~640 ms 空窗** | 鄰窗約 40–50 次 swap |
| Metal encoder | **12** | 前 615／後 685 |
| Frame 邊界 | **246 → 247** | 中間幾乎無 encode |
| GPU points | 變稀，仍有；最長 GPU 空檔 ~89 ms | ≪ Present 空窗 |
| CPU time-sample | hitch 內 Running；**~93%** 在名為 `-[AGXBuffer initImplWithHeap:…]` 的執行緒 | Main／一般 wine／dispatch 出幀 worker 變少 |

**解讀：**  
不是「CPU 閒著只等 PSO」；而是命中首用觸發 **Metal／AGX buffer 配置／初始化**，卡在關鍵路徑上，**幾乎停止提交新幀**。

因果鏈：

```text
第一次打到怪
  → 命中專用內容首次 materialize
     （傷害字／命中特效／怪物受擊相關 → D3D 資源）
  → D3DMetal（或 DXMT）第一次大量建 Metal buffer（AGXBuffer init…）
  → encode／Present 停住 ~0.65s
  → 畫面 + HUD 凍住
  → 資源就緒 → 下一 Frame → 恢復 + 追趕波動
```

PSO／shader 編譯可能夾帶發生，但**本輪低干擾 Trace 的主證據是 buffer／出幀提交停滯**，不是「solely PSO wait」。

### 4.3 為何 Mac 上特別明顯

```text
Windows：MapleStory → D3D → 驅動 → GPU（原生，首用常 < 感知）
Cyder：  MapleStory → Rosetta → Wine → D3D → D3DMetal/DXMT → Metal/AGX
```

同一套懶載入，在轉譯鏈上被放大到 **數百 ms 級**，又堵在出幀路徑，故整屏可感。

## 5. 驗證實驗

### 5.1 V1：Hit1 vs Hit2（同 session，Instruments）

**目的：** 證明大空窗只發生在**第一次**命中 materialize，第二次已暖。

| 項目 | 內容 |
|---|---|
| 日期 | 2026-09-05 ~18:48 |
| 條件 | D3DMetal、`FILE_CACHE=1`、無 prewarm／H2、`MTL_HUD=1` |
| Trace | `…/instruments/v1-hit1-hit2-20260905-184828.trace`（~26 s） |
| 協議 | arm → record → **Hit1**（不揮空打到怪）→ 等 2–3 s → **Hit2** |

| | Hit1 | Hit2 |
|---|---|---|
| 體感 | **小卡** | **不卡** |
| Present／Frame | **~749 ms 空窗**（Frame **323→324**，t≈5.062→5.811 s） | Hit1 後 ≥8 s **無第二段 ≥100 ms 大空窗**（恢復尖峰最大 ~89 ms） |

**判定：通過。** 首次 materialize＝卡頓關鍵；同 session 第二次命中已暖。

分析摘要：`…/instruments/export-v1/v1-analysis.txt`

### 5.2 V2：先付再打（產品策略驗收）

**目的：** 證明「預先真命中 materialize」後，**正式第一下**不卡。  
（「預先 materialize」在現有手段下＝**真的打到怪一次**；無法隱形假暖。）

| 項目 | 內容 |
|---|---|
| 日期 | 2026-09-05 ~18:54 |
| 條件 | 同 V1 玩測條件；以體感為主（不強制 Trace） |
| 協議 | 進圖 → **HitA** 故意打到怪（付費）→ 等 ~2 s → **HitB** 當正式第一下 |

| | HitA | HitB |
|---|---|---|
| 角色 | 預付 materialize | 「認真練」的第一下 |
| 體感 | **小卡** | **不卡** |

**判定：通過。** 即 B1／M0／M1「提前付一次」策略有效。

筆記：`…/v2-feel.txt`

### 5.3 FAST_HIT／H2 ablation（2026-09-06）

**目的：** 在結案後再做一次 2×2，確認 file-cache 兩支 opt-in 對「真命中 HUD 卡」無穩定增益；並用錄影補時間軸（§2.1）。

| 項目 | 內容 |
|---|---|
| Engine | `install/wine-cx26-x86_64`（含 FAST_HIT／hit-prewarm markers；label 仍 `CX26.3.0-W11-Cyder012`） |
| Prefix／log | `/private/tmp/cyder-cx26-ablation-prefix`、`…/cyder-cx26-ablation-logs` |
| 固定 | D3DMetal、`FILE_CACHE=1`、host `PREWARM=0`、同角色／安全圖、**不揮空**評第一下真命中 |
| H2 協議 | 進圖 → touch `CYDER_MAPLESTORY_IO_RING_ARM_FILE` → 開背包 → 等 ~20 s → 首打 |

| 輪 | FAST_HIT | H2（`PREWARM_IN_PROCESS`） | 第一下體感 | 備註 |
|---|---:|---:|---|---|
| **A0** | 0 | 0 | **小卡** | 第二下不卡（與 V1／V2 一致） |
| **A1** | 1 | 0 | **小卡** | 與 A0 無明顯差異 |
| **A2** | 0 | 1 + arm | **小卡** | log：`prewarm done`、`used_bytes≈24 MiB`（有效 fill） |
| **A3** | 1 | 1 + arm | **小卡** | 同上，fill 有效；疊加無增益 |

**判定：** FAST_HIT／H2（單獨或疊加）**皆不能**消掉真命中阻塞卡；與 §1／§3 一致。影片細節見 §2.1。

**產品決策（2026-09-06）：** 複看測試影片後，host prewarm 與 H2 **不納入下一版 engine** release stack。同日評估 FAST_HIT 效益／副作用後，**FAST_HIT 一併移出** production apply list（patch 檔保留供研究）。正式路徑仍靠 adaptive＋512-slot cache；first-hit 緩解走 M0／M1。

## 6. 產品含義

| 目標 | 是否可達成 | 作法 |
|---|---|---|
| 讓「付費那一下」本身變短／無感 | **目前引擎範圍內無已驗證辦法** | 需改 GPTK／更深掛點等長線，不保證 |
| 讓「正式開打第一下」不卡 | **可以（已用 V2 證明）** | 進圖後先真打到怪一次 |
| 只開 buff／觸發被動就當預熱 | **不夠** | 劍豪：無心／偏離互暖，仍暖不到第一次普攻真命中（§2.2） |
| 零成本自動、隱形、不打怪 | **目前不可行** | H3-B 否決；揮空／未命中無效 |

### 建議產品選項（待拍板）

1. **只 M0** — Cyder／說明：「進圖後先打一下怪，第一次可能頓一下」  
2. **M0 + M1 實驗 flag** — 可選自動普攻一次；預設關；**無可靠「有怪」偵測不得上正式版**  
3. **Known quirk** — 僅文件記錄，不做提示／注入  

規格細節：[`maplestory-cx26-b1-safe-first-hit-prewarm-spec.zh-TW.md`](maplestory-cx26-b1-safe-first-hit-prewarm-spec.zh-TW.md)

### 明確不應再投入（除非目標改為長線研究）

- 再加深 WZ／Effect host prewarm 當首打主修補  
- 再試 D3DMetal 側假暖 PSO（已不可行）  
- 預期「換 DXMT／清 Metal cache」消首打  
- 再做 FAST_HIT／H2 當首打主修補（§5.3 已否決）  

## 7. 工件與路徑索引

| 工件 | 路徑 |
|---|---|
| Instruments A trace | `/private/tmp/cyder-cx26-fasthit-play-logs/instruments/s-hit-metal-20260905-182113.trace` |
| Instruments A 分析 | `…/instruments/export/analysis-hitch-window.txt`、`analysis-what-ran-in-hitch.txt` |
| V1 trace | `…/instruments/v1-hit1-hit2-20260905-184828.trace` |
| V1 分析 | `…/instruments/export-v1/v1-analysis.txt` |
| V2 體感 | `…/v2-feel.txt` |
| Ablation logs（A0–A3） | `/private/tmp/cyder-cx26-ablation-logs/` |
| Launcher DXMT 支援 | `scripts/run-maplestory-cx26-d3dmetal.sh`（`--graphics-backend dxmt\|d3dmetal`） |

## 8. 修訂紀錄

| 日期 | 內容 |
|---|---|
| 2026-09-05 | 彙整 H1／H2／IO／DXMT／S-air／S-hit／Instruments A／V1／V2；結案「materialize＋M0／M1 預付」 |
| 2026-09-06 | §5.3 FAST_HIT／H2 2×2 ablation（皆小卡）；§2.1 錄影時間軸（背包／揮空兩段波／直接命中兩段式） |
| 2026-09-06 | §2.2 劍豪分桶：放出不卡；無心（主動 buff）↔ 偏離（被動）互暖；只要打到怪必卡且 buff 暖不到普攻命中 |
| 2026-09-06 | 產品：host prewarm／H2／FAST_HIT **不進**下一版 engine；移出 release apply list |
