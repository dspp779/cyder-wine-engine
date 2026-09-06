# MapleStory × Wine：可突破方向分析

> 更新：2026-09-06  
> 範圍：Cyder CX26、MapleStory、Wine/CrossOver、D3DMetal/DXMT、first-use hitch  
> 目的：整理目前已經收斂的證據，辨識下一批真正值得投入的 compatibility / performance 突破點。

## 一句話結論

目前已經不是「Wine 能不能跑新楓之谷」的問題。

CX26 已經找出並修正登入前的 `win32u/message.c` message-wait handoff gate，實際通過 `HybridCore64.dll -> jypc.dll` 並取得登入畫面；後續研究也已進入可打怪、可量 first-hit hitch 的階段。

因此下一階段應從：

```text
繼續堆 MapleStory-specific patch
```

轉成：

```text
辨識 MapleStory 真正依賴的 Windows observable contract
        +
對照 Nexon / CodeWeavers / GE-Proton 的新實作
        +
刪除不再必要的 patch / upstream 可泛化修正
        +
重新驗證新版 renderer 是否降低 first-use materialization cost
```

---

## 1. 目前已經確立的基線

### 1.1 CX26 啟動 gate 已經不是 renderer 黑畫面問題

早期 CX26 曾停在 DwarfAxe 後，沒有 `HybridCore64.dll` / `jypc.dll`，且反覆在：

```text
NtUserMsgWaitForMultipleObjectsEx
  -> wait_objects
  -> wait_message
  -> NtWaitForMultipleObjects
```

處理包含 invalid / NULL handle 與 server queue 的 wait set，最後反覆得到 `0xc0000008`。

真正有效的修正是窄化 `message-wait handoff`：

- 保留 upstream driver-event retry 架構；
- 第一次 `process_driver_events()` 已表示 queue ready 時，直接保留該結果；
- 不再把該組無效 handle 送入不必要的 wait；
- 不全域吞掉 `STATUS_INVALID_HANDLE`。

正式候選之後能依序載入：

```text
MapleStory.exe
BlackXchg.aes
BlackCipher64.aes
DwarfAxe.exe
HybridCore64.dll
jypc.dll
```

並實際確認登入畫面。

現有詳細紀錄：

- [`maplestory-cx26-worklog.zh-TW.md`](maplestory-cx26-worklog.zh-TW.md)

> 注意：worklog 前段仍保留歷史「黑畫面」敘述；判讀現況時應以後段 message-wait handoff 成功驗證為準。

### 1.2 first-hit hitch 已經從 WZ I/O 問題收斂成 first-use materialization 問題

目前證據顯示：

- 冷 session 第一次「真的打到怪」才會出現主要 hitch；
- 揮空、只放技能、不命中，暖不到完整 hit-result path；
- 同 session 第二次命中通常不再出現同級 hitch；
- D3DMetal 與 DXMT 都可重現；
- WZ/userspace cache、FAST_HIT、host/in-process prewarm 都無法消除主要 stall。

低干擾 Metal trace 的代表性現象：

```text
normal Present median   ~13 ms
first-hit Present gap   ~655-750 ms
surface swap gap        ~640 ms
hitch CPU sample        mostly AGXBuffer initImplWithHeap
```

目前最合理的機制是：

```text
first real hit
  -> hit-result resources first materialize
  -> D3D resource / Metal buffer allocation & initialization
  -> render submission critical path stalls
  -> Present stops for hundreds of milliseconds
  -> resources become resident/ready
  -> later hits are smooth
```

因此 WZ cache 仍可能對平均 I/O 有價值，但不應再當 first-hit 主修補。

---

## 2. P0：把 GE-Proton 2026 MapleStory fixes 當成第二組 reverse oracle

這是目前最值得利用的新外部訊號之一。

2026 年 Linux / GE-Proton 社群已經有新的 MapleStory compatibility work，重點並不是停用 NGS/BlackCipher，而是補 Wine 與 Windows observable behavior 的差異。

目前公開討論／實作至少出現過以下類型：

```text
kernelbase
  CharPrevA / CharPrevExA edge semantics

win32u / user32 behavior
  SPI_SETSTICKYKEYS
  SPI_SETFILTERKEYS

runtime / bottle policy
  VC runtime dependencies
  Windows-version behavior
  DirectInput / focus / launcher protocol policy
```

這些項目不應直接照搬到 TMS；真正價值是建立一個獨立於 CX25 OEM 的 compatibility delta。

### 建議建立 cross-source matrix

```text
                                   Cyder CX26   Wine 11   GE-Proton   GMS macOS
message-wait handoff                   yes         ?          ?           ?
NtYieldExecution Maple guard           yes         ?          ?           ?
CharPrevA / CharPrevExA edge fix         ?         ?         yes          ?
SPI_SETSTICKYKEYS/FILTERKEYS             ?         ?         yes          ?
.tmp/.msf module-name behavior         yes         ?          ?           ?
BlackXchg-specific behavior            yes         ?          ?           ?
D3D shared-resource fixes              yes         ?          ?           ?
media/GStreamer completeness           yes         ?          ?           ?
```

### 驗收目標

不是「新增更多 patch」，而是把每個差異分成：

1. **MapleStory 共通 Windows contract**：應考慮 upstream / generic compatibility fix；
2. **TMS launcher / BeanFun 特有**：留在 profile / launcher；
3. **舊 CX25 OEM 遺產**：若新版官方 runtime 已不需要，優先刪除；
4. **renderer/backend-specific**：不要混進 generic Wine compatibility layer。

外部參考：

- GE-Proton MapleStory community work: <https://github.com/oldschoola/linux_maplestory>
- Proton-GE-Custom: <https://github.com/GloriousEggroll/proton-ge-custom>
- WineHQ bug tracker / mailing lists: <https://bugs.winehq.org/>

---

## 3. P0：最新 GMS macOS runtime 應取代 CX25 OEM，成為新的 golden oracle

CX25 OEM 對 2026 年的 Cyder 仍然有歷史價值，但它不應再是唯一 reference。

Nexon 已正式提供 MapleStory macOS 路徑，而社群也已觀察到該 macOS bundle 使用 Wine/CrossOver 類 runtime；這代表現在存在一份由 Nexon / CodeWeavers 持續維護、針對 MapleStory 實際出貨的現代 reference stack。

### 最值得比對的項目

```text
runtime identity
  wine --version
  CrossOver build/version markers

core binaries
  win32u
  ntdll
  kernelbase
  kernel32
  user32
  winemac

renderer payload
  D3DMetal version
  DXMT presence/version
  Metal/GPTK payload

bottle policy
  Windows version
  DLL overrides
  registry deltas
  MSync / ESync
  HID / DirectInput behavior
  focus/window policy

MapleStory-specific behavior
  BlackCipher / BlackXchg
  DwarfAxe
  module-name compatibility
  scheduler / yield semantics
  shared-resource behavior
```

### 建議方法

建立 machine-readable manifest，而不是人工看幾個檔案：

```text
GMS-mac-runtime-manifest.json
Cyder-CX26-manifest.json
GE-Proton-maplestory-manifest.json
```

每個 binary 至少保存：

```text
path
size
sha256
Mach-O / PE architecture
version/string markers
linked dylibs / imports
```

再做 source / binary / registry 三層 diff。

### 高價值結果

如果最新官方 runtime 已經不需要某一個 CX25-derived patch：

> 優先研究為什麼可以刪，而不是繼續把舊 patch 帶進下一版 Wine。

這條線最可能直接降低 Cyder 的 patch debt。

外部參考：

- Nexon MapleStory macOS support: <https://support-maplestory.nexon.com/hc/en-us/articles/23610205021460-Can-I-play-MapleStory-on-a-Mac>

---

## 4. P1：重新 benchmark 現代 D3DMetal / GPTK / DXMT，而不是再測「換 backend 名字」

既有資料已證明：

```text
old D3DMetal first hit -> hitch
old DXMT first hit     -> hitch
```

因此單純切換 backend 不是解法。

但現在真正值得重測的是**新一代 backend implementation 是否改變 allocation/materialization latency**。

應固定遊戲側所有條件，只替換 renderer generation：

```text
same MapleStory build
same character
same map
same real first hit
same prefix preparation protocol
FILE_CACHE baseline fixed
FAST_HIT=0
H2=0
no manual air prewarm
```

比較：

```text
current Cyder/OEM D3DMetal
newer D3DMetal
newer GPTK evaluation environment
newer DXMT
```

只量硬指標：

```text
Present gap
frame/encoder gap
AGXBuffer allocation count
AGXBuffer allocation duration
allocation size distribution
PSO compile overlap
CPU thread occupancy
```

### 建議驗收門檻

```text
< 100 ms    breakthrough；值得產品化
100-250 ms  明顯改善；有產品價值
250-500 ms  邊際改善；視複雜度決定
> 500 ms    停止投入 backend-only 路線
```

如果新版 backend 仍維持約 650-750 ms，則現階段應接受：

```text
真命中 materialization 是 unavoidable first-use payment
```

產品層只處理「何時付」而不是幻想 file prewarm 可以讓它消失。

外部參考：

- CrossOver changelog: <https://www.codeweavers.com/crossover/changelog>
- Apple Game Porting Toolkit: <https://developer.apple.com/games/game-porting-toolkit/>

---

## 5. P1：把 message-wait handoff 從 MapleStory patch 升級成 Windows conformance experiment

目前的 message-wait patch 是整個 CX26 port 最值得泛化的成果之一。

它不是粗暴的：

```text
if MapleStory:
    ignore STATUS_INVALID_HANDLE
```

而是修正 driver queue 已 ready 時的控制流。

因此下一步應回答：

> Windows 在同一組 message queue + handles 條件下，observable behavior 到底是什麼？

### 建議製作最小 reproducer

```text
MsgWaitForMultipleObjectsEx / NtUserMsgWaitForMultipleObjectsEx
+ queued driver/window event
+ supplied handles
+ queue handle ready
+ MapleStory 曾踩到的 invalid/NULL arrangement
```

比較：

```text
Windows 11
stock Wine 11
CX26 unpatched
CX26 patched
```

記錄：

```text
return value
GetLastError / NTSTATUS
which object wakes first
whether queue-ready state is preserved
whether invalid handle is evaluated before/after queue state
```

如果 Windows 的行為支持目前 narrow patch，應嘗試把它改寫成：

```text
Wine correctness fix
```

而不是永久保留：

```text
maplestory-cx26-message-wait-handoff.patch
```

這是降低長期 rebase cost 的高價值方向。

---

## 6. P2：ARM64 Wine + FEX 是中長期架構突破，不是現在的 production fix

目前 Apple Silicon 上的典型 Cyder 路徑仍近似：

```text
x86-64 MapleStory
  -> x86-64 Wine
  -> Rosetta-hosted execution
  -> D3DMetal / DXMT
  -> Metal
```

CrossOver 已公開展示原生 ARM64 Wine + FEX 的 Mac 路線。這條架構未來可能把 Wine host 本身從 Rosetta execution path 移出，並搭配 ARM64 graphics backend。

這可能對：

- CPU transition overhead；
- thread scheduling；
- syscall-heavy Wine paths；
- shader/resource materialization critical path；

產生比 WZ micro-optimization 更大的結構性影響。

但目前應只建立 experimental branch，不應取代 CX26 production：

```text
Cyder ARM64 experimental
  -> ARM64 Wine
  -> FEX x86-64 guest execution
  -> ARM64 DXMT / future D3DMetal
```

### 驗收先看 compatibility，不先看 FPS

1. MapleStory process 是否正常進入；
2. BlackCipher / DwarfAxe lifecycle 是否正常；
3. message-wait / scheduler compatibility patch 是否仍需要；
4. 能否登入 / 進世界；
5. first-hit Present gap 是否有結構性下降。

外部參考：

- CodeWeavers ARM64/FEX preview: <https://www.codeweavers.com/blog/mjohnson/2026/7/31/crossover-preview-the-right-to-bear-arm64-on-mac>

---

## 7. 明確不應再投入的方向

除非研究問題本身改變，以下項目不應重新當作 first-hit 主線：

- 繼續擴大 WZ host page-cache prewarm；
- 再加深 FAST_HIT；
- 再增加 H2 in-process file prewarm 範圍；
- Effect-only file prewarm；
- 只清 / 保留 Metal disk cache 做主修補；
- 期待單純 D3DMetal <-> DXMT 切換消除 hitch；
- 在封閉 GPTK 上繼續做無可靠 drawing context 的 fake-hit PSO warmup；
- 只靠 buff / passive trigger 代替真正 hit-result materialization。

WZ adaptive cache 若保留，其定位應是：

```text
一般 I/O / metadata access optimization
```

而不是：

```text
first-hit hitch fix
```

---

## 8. 建議立即執行的三個實驗

### Experiment A — GMS macOS runtime manifest + diff

**最高優先。**

輸出：

```text
docs/maplestory-gms-macos-runtime-diff.zh-TW.md
artifacts/gms-macos-runtime-manifest.json
```

目標：找出現代官方 runtime 已經吸收、替換或移除的 CX25/CX26 compatibility behavior。

### Experiment B — GE-Proton MapleStory patch cross-diff

輸出：

```text
docs/maplestory-ge-proton-compatibility-delta.zh-TW.md
```

逐項回答：

```text
patch exists in CX26?
TMS can trigger it?
Windows observable behavior?
generic Wine fix or game-specific policy?
```

### Experiment C — modern renderer first-hit benchmark

輸出：

```text
docs/maplestory-first-hit-renderer-generation-benchmark.zh-TW.md
```

一次只換 renderer generation，主 metric 固定為：

```text
first real-hit Present gap
```

不要再以「好像比較順」作主要判定。

---

## 9. 優先順序

| 優先 | 方向 | 預期價值 | 主要成果 |
|---|---|---:|---|
| P0 | GMS macOS runtime reverse-diff | 很高 | 刪 patch、更新 golden oracle |
| P0 | GE-Proton MapleStory fixes cross-diff | 很高 | 找共通 Windows contract |
| P1 | modern renderer first-hit benchmark | 高 | 判定 materialization 是否已被新版 backend 改善 |
| P1 | message-wait Windows conformance | 高 | upstream / generic correctness fix 可能性 |
| P2 | ARM64 Wine + FEX | 中長期很高 | 移除 Rosetta-hosted Wine 架構的可能性 |
| Stop | 再深化 WZ/FAST_HIT/H2 當 first-hit 主修補 | 低 | 已有足夠負面證據 |

---

## 10. 研究策略調整

下一階段最重要的變化不是再找一個神奇 flag，而是把研究方法從：

```text
MapleStory 壞了
  -> 猜 Wine subsystem
  -> 做一個 patch
  -> A/B
```

提升成：

```text
已知正常的現代官方 runtime
        +
另一個獨立成功的 GE-Proton runtime
        +
Windows native observable behavior
        +
Cyder CX26
        -> cross-diff
        -> identify contract
        -> minimal patch
        -> regression/conformance test
        -> upstream or delete custom patch
```

如果這條路走通，Cyder 的 MapleStory 支援會從「一組能玩的特殊 patch」進一步變成：

> **可解釋、可驗證、可隨 Wine 升版維護的 MapleStory compatibility profile。**
