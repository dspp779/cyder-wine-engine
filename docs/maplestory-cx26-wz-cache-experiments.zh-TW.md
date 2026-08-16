# MapleStory CX26 WZ userspace cache／mmap 實驗紀錄

> 更新日期：2026-08-16  
> 範圍：CX26／Cyder011 engine、MapleStory WZ 讀取、第一次攻擊卡頓  
> 狀態：診斷實驗；userspace cache 與 mmap fill 尚未是 release recommendation

本文件集中整理 2026-08-15～2026-08-16 針對「重新登入後第一次攻擊怪物會卡頓」
所做的 WZ 讀取、userspace read-ahead、cache slot、mmap 與低干擾 log 實驗。
D3DMetal surface／黑畫面等較早的 renderer A/B 仍記錄在
[`maplestory-cx26-worklog.zh-TW.md`](maplestory-cx26-worklog.zh-TW.md)。

文件中的 OTP、ServiceAccountID 與完整登入參數均不保存；log 路徑只列出本機
暫存位置，未將原始登入資訊寫入專案文件。

## 1. 問題定義與使用者觀察

固定重現條件是：重新開啟遊戲並登入後，第一次對怪物造成傷害時明顯卡頓；之後
同類攻擊通常順暢。觀察到的細節如下：

- 重新啟動、登入後第一次攻擊會卡；換地圖後第一次攻擊通常不再卡。
- 從選角畫面重新進入遊戲時仍可能卡，但比完全重啟輕。
- 某些特效第一次出現也會卡，例如升級、爆擊、攻擊無效被動技。
- 攻擊與爆擊會卡；單純被怪物攻擊通常不會卡。
- 先被攻擊，再第一次攻擊怪物，仍可能卡。
- 對空氣攻擊、施放沒有命中怪物的技能，通常不會卡。
- 空中衝刺第一次使用可能卡；先使用攻擊技能再使用空中衝刺時，卡頓較小，
  但先使用空中衝刺再攻擊仍可能卡。
- 傷害數字不能隱藏；MapleStory 傷害字型是固定圖檔，因此不能以關閉 HUD
  或隱藏傷害文字排除資源第一次載入。
- d3dmetal、dxmt、dxvk 都曾觀察到類似卡頓；關閉音效或 HUD 沒有明顯改善。

這組現象比較符合「特定遊戲事件第一次觸發時，才解析／讀取一批資源」，而不是
單純 GPU frame rendering 或音效輸出問題。

## 2. 固定測試條件

| 項目 | 實際條件 |
|---|---|
| 遊戲 | `/Users/jjc/games/tms/MapleStory.exe` |
| 遊戲目錄 | `/Users/jjc/games/tms` |
| Engine install | `/Users/jjc/cyder-wine-engine/install/wine-cx26-x86_64` |
| Engine source | `/Users/jjc/cyder-wine-engine/build/cx26/sources/wine` |
| Wine prefix | `/Users/jjc/Library/Application Support/Cyder-MapleStory-CX26/bottles/shared` |
| Graphics | D3DMetal；由 CompatDB 強制選擇 |
| GPTK | `/Users/jjc/.cyder/runtime/Engines/maplestory-oem25/lib64/apple_gptk` |
| CompatDB | `/Users/jjc/ogom/compatdb/compiled/compatdb.cdb` |
| CPU／Wine | x86_64 Wine，透過 `arch -x86_64` 執行 |
| 語系 | `zh_TW.UTF-8` |
| Prefix 清理 | 每次由 launcher 對同一 prefix 執行 wineserver cleanup |
| 測試位置 | 安全、低等怪物地圖；arm 後只攻擊一次 |

所有正式比較都應明確指定 install tree、prefix、GPTK、CompatDB 與 log root。
`/private/tmp` 只放 prefix state、arm file 與一次性 log，不代表 engine 被安裝
到 `/tmp`。

## 3. WZ 讀取模式的初步判斷

WZ 讀取不像單純把一個大型檔案從頭讀到尾，而更接近「索引定位後讀取 payload」：

1. 先以很多 1～4 KiB 的小讀取查詢 header、offset、型別與資源索引。
2. 小讀取的 offset 可能跳躍，但大量請求彼此 nearby、forward 或短距離連續。
3. 找到資源後再讀取圖片、音效、地圖或技能 payload；這些讀取可達數十 KiB
   到數百 MiB。
4. 同一個 WZ 檔案會在短時間內被大量重複查詢，適合以「檔案／offset／window」
   做 userspace cache，而不是只依賴單次 `pread`。

最後一輪低干擾測試可見的代表性資源：

| 資源 | 讀取事件 | NT bytes | cache fill／cache bytes（部分代表值） | 判讀 |
|---|---:|---:|---:|---|
| `Data/UI/UI_000.wz` | 116,371～117,353 | 約 218～220 KiB | 約 231～238 fills、約 2.3 MiB | 大量小索引讀取，cache 命中價值高 |
| `Data/Sound/Sound_029.wz` | 44,534 | 124,695 bytes | 4,037 fills、約 33.5 MiB | 大量小查詢與 read-ahead，可能產生同步 fill 成本 |
| `Data/Item/Consume/Consume_000.wz` | 29,177 | 87,163 bytes | 253 fills、約 2.17 MiB | 高重複小讀取 |
| `Data/Item/Etc/_Canvas/_Canvas_000.wz` | 7,850 | 約 23.8 KiB | 218 fills、約 1.81 MiB | 小讀取密度很高 |
| `Data/Packs/Skill_00000.ms` | 2 | 約 56 KiB | cache bypass | 大讀取不應污染小型 WZ metadata cache |
| `Data/Map/Map/Map9/Map9_000.wz` | 767 | 約 100 MiB | 主要為 bypass | 大 payload 仍走正常讀取路徑 |

這些數字支持「資料庫／索引＋payload」的直覺，但不代表 WZ parser 本身使用
database API；它只是說存取局部性適合 index-aware window cache。

## 4. 已加入的診斷與 cache 行為

目前 CX26 patch stack 中相關項目為：

- `maplestory-cx26-file-cache-adaptive.patch`
  - 只針對 read-only `.wz`。
  - 小於等於 4 KiB 的請求才進入 cache；較大的請求保留 Wine 原本路徑。
  - 初始以 8 KiB aligned window 讀取；觀察到連續讀取後升級到 32 KiB。
  - cache slot 由初始 64 逐步測到 256、512；目前 source／generated patch 為
    512，但功能仍由 `CYDER_MAPLESTORY_FILE_CACHE=1` opt-in。
- `maplestory-cx26-io-ring.patch` 與 `maplestory-cx26-io-ring-arm.patch`
  - 將 bounded read event 留在記憶體中。
  - 以不存在的 arm file 啟動；在測試動作前 `touch` 該檔案，清除並開始記錄。
- `maplestory-cx26-io-summary.patch`
  - 以 path aggregate 取代逐筆 log。
- `maplestory-cx26-io-timeline.patch`
  - 以 100 ms bucket 對齊登入、地圖載入與第一次攻擊。
- `maplestory-cx26-io-cache-stats.patch`
  - arm 後統計 cache attempts、hits、fills、fill bytes、bypass 與決策 skip。
  - 目前已區分 `skipped_needs_close`、`skipped_no_entry`、`skipped_no_offset`。
- `maplestory-cx26-section-map-summary.patch`
  - 另外統計 section／mapped-file 行為；不改變讀取路徑。
  - 本輪尚未取得足以判斷 WZ parser 是否使用 section mapping 的完整結果。

目前 cache 預設關閉。mmap fill 另由 `CYDER_MAPLESTORY_FILE_CACHE_MMAP=1`
啟用，預設關閉且不應直接視為產品修正。

## 5. Cache slot 實驗

### 5.1 64 slots：容量不足，handle eviction 使 cache 幾乎失效

實驗 log：

- `/private/tmp/cyder-cx26-cache-stats-attack.7vqeI8/maplestory-cx26-d3dmetal-20260816-181523-12834.log`
- `/private/tmp/cyder-cx26-cache-skip.vbSk05/maplestory-cx26-d3dmetal-20260816-182728-15242.log`

在加入決策 counters 後，main process 觀察到：

```text
attempts=228875
skipped_needs_close=0
skipped_no_entry=228324
skipped_no_offset=0
```

約 99.8% 的 cache attempt 找不到 entry，並非 `needs_close` 或 offset 不合法。
只有少數 WZ path 真的形成 cache window，約有 476 hits、12 fills。這表示 64
slots 的主要問題不是 read-ahead 規則，而是同時開啟的 WZ handle 太多，舊 entry
很快被淘汰。

在加入 decision counters 前的同類 64-slot run，arm timestamp 為
`t=33064353507`，post-arm main timeline 約為 `ntread=209803`、`host=209803`、
`hostbytes=1207819`、`hostdur_us=38579`，且沒有可用的 cache path aggregate；
這與後續 `skipped_no_entry` 約 99.8% 的結果一致。

### 5.2 256 slots：handle coverage 明顯改善

實驗 log：
`/private/tmp/cyder-cx26-cache-256.qfKtbN/maplestory-cx26-d3dmetal-20260816-184326-19019.log`

arm timestamp：`t=34025758850`

```text
attempts=219354
skipped_needs_close=0
skipped_no_entry=173922
skipped_no_offset=0
```

相較 64 slots，cache path aggregate 約有 45,418 hits、4,173 fills。arm 後 timeline
為約 219,354 次 NT read、173,936 次 host read、1,084,549 bytes、38,421 µs
host duration。使用者體感回報「好像有」改善，但仍不是穩定消除卡頓。

### 5.3 512 slots：handle coverage 大幅改善，但同步 fill 代價變得可見

實驗 log：
`/private/tmp/cyder-cx26-cache-512.0LsxOS/maplestory-cx26-d3dmetal-20260816-185007-21193.log`

arm timestamp：`t=34424741899`

```text
attempts=219780
skipped_needs_close=0
skipped_no_entry=5991
skipped_no_offset=0
```

cache aggregate 約有 213,769 hits、6,433 fills、53,977,088 bytes fill，累計
fill duration 約 549,097 µs。timeline 的一般 host read 則降到約 6,011 次、
670,175 bytes、1,091 µs。這證明 512 slots 很有效地攔截了正常讀取，但不代表
總成本消失：read-ahead fill 本身是同步在第一次 miss 上執行，且可能一次讀入
大量未立即使用的 window。

使用者仍回報第一次攻擊有卡頓，因此「增加 cache 容量」不是完整解法。

### 5.4 No-cache control：host I/O 很多，但體感未必最差

實驗 log：
`/private/tmp/cyder-cx26-cache-control.Rqe78Q/maplestory-cx26-d3dmetal-20260816-190105-22831.log`

設定 `CYDER_MAPLESTORY_FILE_CACHE=0` 後，arm-scoped main timeline：

```text
events=471608
ntread=235804
host=235804
hostbytes=4115206
hostdur_us=65907
```

使用者回報「好像沒很卡」。這不是 cache 無效的證明，因為本 probe 對 cache fill
內部的直接 `pread`／mmap 成本沒有完整放入 host-read aggregate；它只說明同步
read-ahead 的額外成本可能比更多次較小的正常 read 更容易形成可感知 hitch。

### 5.5 Slot 實驗總結

| 變體 | 主要結果 | 結論 |
|---|---|---|
| 64 slots | `skipped_no_entry` 約 99.8% | 容量太小，handle eviction 使 cache 幾乎失效 |
| 256 slots | hit／fill 大幅增加，體感略改善 | 容量方向正確，但仍有同步 fill 問題 |
| 512 slots | `skipped_no_entry` 降至約 2.7%，一般 host read 顯著下降 | coverage 足夠，但 fill 可能造成第一次操作尖峰 |
| cache off | host read 次數／bytes 增加，體感一次測試反而較順 | 不能只以 aggregate bandwidth 判斷；要測單次 stall 與 fill latency |

## 6. mmap fill 實驗與黑畫面排除

### 6.1 實作內容

在 `file.c` 增加了：

- `CYDER_MAPLESTORY_FILE_CACHE_MMAP=1` 環境變數。
- page-aligned `mmap(PROT_READ, MAP_PRIVATE)` window。
- cache entry 保留 mapping，直到 clear／invalidate／下一次 fill。
- mmap 失敗時回退到原本 `pread`。
- cache fill log 的 `source=mmap|pread` 欄位。

啟動器後來補上該環境變數的 export、dry-run 顯示、兩個直接 launch 分支，並
加入 launcher regression assertion。相關 shell／patch tests 均通過。

### 6.2 無效或不可比較的 mmap 測試

第一輪 mmap 啟動時，launcher 尚未把新環境變數傳入 Wine；雖然外部 shell 設定
了 mmap，實際 Wine 使用的仍是 `source=pread`。該輪黑畫面不能用來判斷 mmap。

修正 launcher 後的高 trace 測試：

- `/private/tmp/cyder-cx26-cache-mmap.ZMZD43/maplestory-cx26-d3dmetal-20260816-191636-26227.log`
- launcher 顯示 `CYDER_MAPLESTORY_FILE_CACHE_MMAP=1`。
- log 出現約 9,729 筆 `source=pread`，沒有 `source=mmap`。
- binary 已連結 `_mmap`／`_munmap` symbol，但這只能證明程式包含 mmap code，
  不能證明 runtime fill 成功。

因此目前最保守的結論是：mmap code 已編譯且環境變數已能傳入，但實際 WZ
window fill 仍全部或幾乎全部回退 pread；回退原因尚未被記錄。

### 6.3 GPTK 32-bit fallback

高 trace log 也反覆出現：

```text
backend lacks d3d11.dll, dxgi.dll for i386-windows
graphics backend=d3dmetal rejected; ... fallback=wined3d
```

目前 GPTK root 具備 x86_64 D3DMetal DLL，但沒有 GPTK 自己的 i386 DLL；這是
32-bit helper 的 fallback。主程序仍能選到 x86_64 D3DMetal，後續低干擾測試也能
顯示畫面，因此不能把這一條 warning 單獨當成主畫面黑屏的根因。

### 6.4 Log 輸出本身造成的干擾

直接將 `+cyderio` 逐筆輸出到終端時，Wine 會同時產生大量 `fixme/dbghelp` 與
WZ I/O 訊息；程序曾長時間停在黑畫面，且 log 輸出量非常大。後來改為：

```text
WINEDEBUG=-all,+timestamp,+pid,+winediag,+cyderio
CYDER_MAPLESTORY_IO_TRACE=1
CYDER_MAPLESTORY_IO_PROFILE=1
CYDER_MAPLESTORY_IO_PROFILE_TIMING=0
CYDER_MAPLESTORY_IO_SUMMARY=1
CYDER_MAPLESTORY_IO_TIMELINE=1
CYDER_MAPLESTORY_IO_CACHE_STATS=1
```

並把 launcher stdout／stderr 完全導向檔案。之後使用者確認窗口能成功出現
遊戲畫面。這表示「診斷輸出干擾初始化」至少是黑畫面觀察中的一個混入因素，
但不代表已排除所有 D3DMetal surface 問題。

## 7. 低干擾、實際攻擊測試

### 7.1 第一輪：使用者未注意到卡頓

log：
`/private/tmp/cyder-cx26-cache-mmap-quiet-final.UPYbt2/launcher.out`

arm timestamp：`36388603807`

cache decision：

```text
attempts=218474
skipped_needs_close=0
skipped_no_entry=2801
skipped_no_offset=0
```

arm 後第一個 100 ms bucket：

```text
events=12342
ntread=9702
ntbytes=418155
host=2640
hostbytes=395013
hostdur_us=5161
```

所有 19 個非空 bucket 合計：

```text
events=221290
ntread=218474
ntbytes=1017483
host=2816
hostbytes=459635
hostdur_us=5766
```

這輪使用者後來表示當下沒有注意到卡頓，因此只可視為「低干擾下畫面正常、
cache 有效攔截大量 host read」的觀察，不是嚴格的無卡頓驗收。

### 7.2 第二輪：使用者明確確認卡頓

log：
`/private/tmp/cyder-cx26-cache-mmap-repeat.m5fQu4/launcher.out`

arm timestamp：`36748574211`

cache decision：

```text
attempts=207603
skipped_needs_close=0
skipped_no_entry=3731
skipped_no_offset=0
```

arm 後第一個 100 ms bucket：

```text
events=12107
ntread=8519
ntbytes=593812
host=3588
hostbytes=576285
hostdur_us=7767
```

所有 15 個非空 bucket 合計：

```text
events=211354
ntread=207603
ntbytes=1165942
host=3751
hostbytes=645291
hostdur_us=9104
```

使用者明確回報「卡頓」。和第一輪相比，第一個 100 ms 的 host I/O 約增加：

- host call：2,640 → 3,588，約增加 36%。
- host bytes：395,013 → 576,285，約增加 46%。
- host duration：5.16 ms → 7.77 ms，約增加 50%。

這兩輪都使用低干擾模式與 mmap opt-in，但為避免逐筆 log，
`IO_PROFILE_TIMING=0` 使 `source=mmap|pread` 沒有輸出；因此可以確認 cache／
timeline 行為，不能確認 fill source。

### 7.3 兩輪實際攻擊測試的判讀

重做後仍能穩定觀察到卡頓，問題不是只有「log 太大」或「畫面尚未完成載入」。
同時，第一個 100 ms 內的資料量只有數百 KiB，不像 SSD 頻寬不足；比較可疑的是：

1. 數千次小型 host／Unix I/O 邊界切換。
2. WZ parser 在第一次命中資源時的同步索引解析。
3. cache fill 直接 `pread`／mmap 的成本未被目前 host aggregate 完整計入。
4. 讀取事件、解壓／解析、遊戲主執行緒與 rendering／resource upload 的同步點
   可能落在同一個第一次攻擊 frame。

因此目前不能用「host duration 只有 7.8 ms」否定讀取造成卡頓；它是現有 probe
量到的下界，並不含所有 cache fill 與 parser／解壓工作。

## 8. 目前已證實與尚未證實的事項

### 已證實

- WZ 存取包含大量重複的小讀取，且集中在 UI、Sound、Item、Canvas 等資源。
- 64 slots 會因 handle eviction 使 cache 幾乎找不到 entry。
- 256／512 slots 能大幅提升 cache coverage，512 的 `skipped_no_entry` 已降至
  約 2.7%。
- userspace cache 能顯著降低正常 host read 次數與 bytes。
- synchronous read-ahead 的 fill bytes 可達數十 MiB，不能只看 SSD 傳輸速度。
- cache off 的一次 control run 體感較順，說明「更多一般讀取」不一定比
  「集中式同步 fill」更容易被使用者感知。
- 低干擾、輸出導向檔案後，黑畫面／初始化干擾明顯減少，且能進入遊戲畫面。
- 低干擾模式下，第二次實際攻擊仍由使用者確認卡頓。

### 尚未證實

- WZ parser 是否真的使用 `NtMapViewOfSection` 或 host `mmap`。
- `CYDER_MAPLESTORY_FILE_CACHE_MMAP=1` 的 runtime fill 是否成功；目前高 trace
  輪看到的是 `source=pread`，但沒有記錄 mmap 失敗原因。
- 卡頓 frame 中真正佔用時間的是 cache fill、WZ 解壓／解析、資源 upload，還是
  renderer／主執行緒同步。
- Windows Cache Manager 的實際 MapleStory 行為與目前 userspace probe 的一一
  對應關係；目前只能做架構類比，不能宣稱已重現 Windows 的 section cache。
- i386 helper 的 wined3d fallback 是否會影響某一個特定攻擊／特效；目前只能確定
  警告存在，不能把它當成主程序根因。

## 9. 目前結論

最合理的工作假說是：

> 第一次攻擊觸發一批此前尚未 materialize 的 WZ 資源。parser 以大量小 offset
> 查詢讀取索引，接著同步填入一批 8／32 KiB window，並可能同時進行解壓、圖片／
> 字型／特效建立與 GPU resource upload。Rosetta 下 x86_64 Wine 反覆跨 Unix I/O
> 路徑的成本，使「數千次小讀取」比現代 SSD 的總傳輸量更容易形成可見 hitch。

userspace cache 的方向是對的，但目前的同步 read-ahead 仍可能把許多小成本集中
成一次較大的 first-use pause。增加 slots 解決了 coverage，沒有解決 fill timing；
因此 512 slots 不應直接視為最終設定，更不應在未完成 A/B 前預設開啟。

## 10. 下一步建議

### 10.1 先補齊低干擾 source／fill aggregate

不要恢復逐筆 log；在 `CYDER_IO cache_stats` 增加：

- `mmap_attempts`、`mmap_fills`、`pread_fallback_fills`。
- `fstat_failures`、`mmap_failures` 與 errno 分類。
- mmap／pread 各自的 fill bytes、總時間、最大值與 p50／p95 bucket。
- cache fill 是否在 arm 後發生，以及 fill 所屬 WZ path。

這樣一輪實驗即可回答 mmap 是否真的成功，不必再產生數 GB raw log。

### 10.2 固定四組 A/B

同一 prefix、同一安全地圖、同一攻擊、每組至少三次：

1. cache off。
2. 512 slots + pread。
3. 512 slots + mmap。
4. 預熱／非同步 fill 方案。

每輪都以不存在的 arm file 啟動，進入安全地圖後才 arm；只做一次攻擊，並記錄
使用者體感與 aggregate。若要比較 cold／warm，必須明確重新啟動遊戲，不要只換
地圖後把結果當成 cold start。

### 10.3 產品化方向

如果後續證明 mmap 有效，較安全的設計順序是：

- 保留 512 或可調的 LRU handle table，但以穩定 file identity／path 管理 entry，
  避免只靠有限 handle slot 造成 eviction。
- 只對連續、短距離、重複的小讀取做 read-ahead；隨機 offset 不要盲目升級 32 KiB。
- 大 payload 仍走 normal path，不把整個 WZ 或大資源塞進 metadata cache。
- 在登入／地圖 loading 的非互動階段預熱，而不是在第一次攻擊的主執行緒同步填充。
- 預熱必須有 bounded queue、取消機制與記憶體上限；不要因預讀拖慢畫面初始化。
- mmap mapping 應可重用並在 close／invalidate 正確解除，且所有失敗要安全回退。

在這些條件完成前，正式 runtime 仍應保持：

```text
CYDER_MAPLESTORY_FILE_CACHE=0
CYDER_MAPLESTORY_FILE_CACHE_MMAP=0
```

實驗功能可以由 launcher／偏好設定提供，但不應把尚未驗證的 mmap 或同步
read-ahead 當成預設最佳化。

## 11. 測試操作與低干擾記錄規範

建議使用以下模式，不要把逐筆輸出直接送到終端：

```text
CYDER_MAPLESTORY_FILE_CACHE=1
CYDER_MAPLESTORY_FILE_CACHE_MMAP=1       # 只在 mmap A/B 使用
CYDER_MAPLESTORY_IO_TRACE=1
CYDER_MAPLESTORY_IO_PROFILE=1
CYDER_MAPLESTORY_IO_PROFILE_TIMING=0     # 低干擾；source counter 完成後維持
CYDER_MAPLESTORY_IO_SUMMARY=1
CYDER_MAPLESTORY_IO_TIMELINE=1
CYDER_MAPLESTORY_IO_CACHE_STATS=1
CYDER_MAPLESTORY_IO_RING_ARM_FILE=/private/tmp/.../arm
WINEDEBUG=-all,+timestamp,+pid,+winediag,+cyderio
```

啟動器 stdout／stderr 應導向每輪自己的 log root；遊戲關閉後只保留：

- compact aggregate／timeline／cache stats。
- 必要的 launcher preamble 與錯誤。
- 如需 raw log，立即 gzip，並確認不含登入參數。

不要把大量 `+cyderio` 逐筆 log 當成遊戲效能結果；log writer 本身可能改變
首次載入與畫面初始化時序。

## 12. 相關 log 索引

以下是本輪仍可在本機暫存目錄找到的代表性 log；它們不是 release artifact，
清理前應先保留 compact summary：

- 64-slot／decision：
  `/private/tmp/cyder-cx26-cache-skip.vbSk05/`、
  `/private/tmp/cyder-cx26-cache-decision.MZrOgk/`
- 256 slots：
  `/private/tmp/cyder-cx26-cache-256.qfKtbN/`
- 512 slots：
  `/private/tmp/cyder-cx26-cache-512.0LsxOS/`
- no-cache control：
  `/private/tmp/cyder-cx26-cache-control.Rqe78Q/`
- mmap 傳遞錯誤／高 trace：
  `/private/tmp/cyder-cx26-cache-mmap.RvGLcp/`
- mmap launcher 修正後、高 trace：
  `/private/tmp/cyder-cx26-cache-mmap.ZMZD43/`
- 低干擾第一輪：
  `/private/tmp/cyder-cx26-cache-mmap-quiet-final.UPYbt2/`
- 低干擾第二輪、使用者確認卡頓：
  `/private/tmp/cyder-cx26-cache-mmap-repeat.m5fQu4/`

完整引擎建置、D3DMetal、prefix、window surface 與 renderer A/B 的歷史紀錄，
請回到 [`maplestory-cx26-worklog.zh-TW.md`](maplestory-cx26-worklog.zh-TW.md)。
