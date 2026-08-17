# MapleStory CX26：WZ 小讀取 Fast Path 與共享區段快取開發計畫

狀態：下一階段開發設計（尚未啟用於正式 runtime）  
適用範圍：CX26、x86_64 Wine、MapleStory 專用實驗  
最後更新：2026-08-17

## 1. 目的

本文件定義下一階段如何降低 MapleStory 第一次攻擊與第一次特效出現時的
卡頓，重點是大量 WZ 小讀取在 Wine／Rosetta 路徑上的固定成本。

目前的證據不支持「SSD 傳輸速度不足」是唯一原因。真正需要處理的是：

```text
WZ parser
  → 大量 1～數百 bytes 的 NtReadFile
  → Wine ntdll Unix file path
  → cache lookup / mutex / memcpy
  → parser、資源建立與 rendering 同步
```

因此，本階段不以掃描整個 WZ 或繼續擴大 prewarm 為主要方向，而是要讓
已在 cache 中的資料以更低成本被重複使用，並讓相同 WZ 檔案的多個 Windows
handle 共用區段快取。

## 2. 目前實驗基線

最近一輪有明確的三個 100 ms bin：

| Bin | 事件 | host read | host bytes | host duration | 主要內容 |
|---|---:|---:|---:|---:|---|
| 207 | 599 | 272 | 164 KiB | 1,257 µs | `Skill_00001.ms`、`Skill_00000.ms` 開始讀取，以及 String／Afterimage 索引 |
| 208 | 6,872 | 3,312 | 423 KiB | 3,592 µs | 其餘 Skill pack payload、Character／Hair／Afterimage 關聯資料 |
| 209 | 7,930 | 20 | 32 bytes | 13 µs | 約 7,850 次 `Item/Etc/_Canvas/_Canvas_000.wz` 小型讀取 |

Bin 209 特別重要：host 幾乎沒有資料傳輸，但仍有大量 `NtReadFile` 事件。
這表示 cache 已經能降低磁碟讀取，卻沒有消除每次小讀取進入 Wine／Unix
路徑的成本。

目前 adaptive cache 的限制如下：

1. 每次 cache hit 仍然會進入 `NtReadFile`。
2. cache lookup 使用全域 `pthread_mutex`。
3. cache entry 以 Windows handle 管理，不能自然地跨 handle 共用。
4. 大於 4 KiB 的請求直接 bypass metadata cache。
5. 4 KiB／32 KiB read-ahead 能改善 host read，但不能減少 parser 發出的
   小型 `NtReadFile` 數量。

因此，prewarm 不是本階段的核心解法。它仍可作為輔助，但不能用來驗證
Bin 209 的問題是否已解決。

## 3. 目標與非目標

### 3.1 目標

- 降低 WZ cache hit 的單次 `NtReadFile` end-to-end 成本。
- 降低全域鎖競爭與 handle 重複建立 cache window 的成本。
- 讓同一個 immutable WZ／MS 檔案的多個 handle 共用資料區段。
- 保留原始 Wine read path 作為所有失敗情況的 fallback。
- 以低干擾、可重複的 aggregate／timeline 量測驗證每個改動。
- 在正式 runtime 啟用前，維持明確的 feature flag 與可回退行為。

### 3.2 非目標

- 不在本階段實作完整 Windows Cache Manager。
- 不掃描或常駐載入整個 WZ／MS 檔案。
- 不修改 MapleStory.exe，也不假設能修改其 WZ parser。
- 不把所有一般 Windows 程序的讀取都套用 MapleStory 特化 cache。
- 不以增加記憶體使用量換取未量測的「可能順暢」。

## 4. 目標架構

第一階段先維持 `NtReadFile` 語意，只縮短 cache hit 路徑：

```text
NtReadFile
  │
  ├─ MapleStory／WZ eligibility check
  │
  ├─ TLS hot window lookup
  │     └─ hit：直接 copy，避免全域鎖
  │
  ├─ shared file-region lookup
  │     └─ hit：取得分片鎖或使用 immutable generation
  │
  ├─ miss：bounded pread 或 mmap fill
  │
  └─ 原始 Wine read path fallback
```

### 4.1 Shared file identity

共享 cache 不應只用 Windows handle 作為 key。初步 key 建議包含：

```text
device + inode/file-id + file-size + mtime + normalized path
```

在 macOS／Wine path 取得不到完整 file-id 時，至少要使用 normalized host path
與檔案大小，並在 `fstat` 變化時 invalidate。

### 4.2 Region entry

每個 immutable region 至少需要：

```text
file identity
region offset
valid bytes
generation
reference count
last-use age
state: filling / ready / invalid
```

建議先分成兩種 pool：

- metadata pool：8 KiB／32 KiB，服務大量小型 WZ 查詢。
- payload pool：64 KiB～256 KiB，只服務明確的 `.ms`／WZ 大型首次讀取。

兩者不能共用同一個無上限 LRU，避免一次大型 payload 驅逐大量 metadata
region。

## 5. 開發階段

### Stage 0：補齊低干擾量測

先不改讀取結果，只增加 arm-scoped 的時間欄位：

- `ntread_total_us`：從進入 `NtReadFile` 到返回的總時間。
- `cache_lock_wait_us`：等待 cache lock 的時間。
- `cache_lookup_us`：entry／region lookup 時間。
- `cache_copy_us`：將 cache data copy 到呼叫端 buffer 的時間。
- `host_read_us`：目前已有的 host read 時間。
- `cache_fill_us`：cache fill 總時間，區分 `pread`／`mmap`。
- `path`、`bin index`、`length bucket`。

輸出採 aggregate，不恢復逐筆永久 log。每個 100 ms bin 保留每個 path 的
Top-N，例如：

```text
CYDER_IO bucket_path index=209 path=Item/Etc/_Canvas/_Canvas_000.wz \
    events=7850 ntread_us=... host=0 cache_hit=7850 \
    lock_wait_us=... lookup_us=... copy_us=...
```

驗收條件：同一輪能區分「host 很快但 NtReadFile 很慢」與「cache lock／copy
很慢」，且不產生 GB 級 raw log。

### Stage 1：Cache-hit fast path

先處理目前最可能的低風險瓶頸：

1. 每個 thread 保留最近使用的 `(file identity, region)` TLS entry。
2. cache hit 先走 TLS，避免全域 table lookup。
3. 將全域 mutex 改成分片鎖，例如 16 或 32 個 shard。
4. fill、invalidate、close 仍使用明確的生命週期鎖。
5. hit path 只做 bounds check、generation check 與 `memcpy`。
6. 停用 hot path 上不必要的 trace、環境變數查詢與統計分支。

第一版不要直接做完全 lock-free。先使用清楚的 generation／reference-count
語意，確保 close、handle reuse 與 invalidate 不會讓 TLS 指向已釋放資料。

建議 feature flag：

```text
CYDER_MAPLESTORY_FILE_CACHE_FAST_HIT=1
```

預設值保持關閉，直到 A/B 完成。

### Stage 2：跨 handle 的 shared region cache

將目前 per-HANDLE cache window 提升為 per-file region cache：

- 相同 file identity 的 handle 共用 region。
- handle close 只減少 reference，不立即刪除仍被其他 handle 使用的 region。
- 新 handle 可以立即重用已存在的 region。
- region fill 仍受 bounded memory cap 與 LRU 限制。
- 失敗時只 invalidate 該 region，不摧毀整個 file cache。

這一階段主要驗證是否存在「同一 WZ 檔案被多個 handle 重複讀取」的浪費。

建議初始限制：

```text
metadata pool：16 MiB
payload pool：8 MiB
每個檔案 metadata region 上限：1 MiB
單次 payload fill 上限：256 KiB
```

這些數值是實驗初始值，不是產品承諾；應由實際 memory／hitch 結果調整。

建議 feature flag：

```text
CYDER_MAPLESTORY_FILE_CACHE_SHARED_REGIONS=1
```

### Stage 3：大型 payload 的獨立服務路徑

目前大於 4 KiB 的請求會 bypass cache。對已確認的唯讀 WZ／MS 檔案，增加
獨立 payload pool：

- 只接受 `.wz`／`.ms` 且符合 MapleStory process eligibility 的檔案。
- 只接受 bounded、aligned 的 64～256 KiB region。
- 不把大型資料塞進 metadata pool。
- 支援 exact request 從 payload region 直接提供。
- 若 region 不完整，回到原始讀取，不阻塞等待無限大的 prefetch。

這一階段才是處理 `Skill_00000.ms` 等 16～174 KiB 首次讀取的正確位置。
但它不能取代 Stage 1／2，因為 Bin 209 的主要問題是 cache hit 次數，而非
大型 host read。

### Stage 4：mmap／section mapping

只有在 Stage 0～3 的結果仍顯示 page fault 或 fill 成本明顯時，才進一步處理：

- 對 immutable WZ／MS 檔案建立可重用的 read-only mapping。
- 使用 sliding region，不直接永久 map 整個大型 pack。
- mapping 生命週期由 shared file identity 管理。
- 以 bounded background prefetch 降低主執行緒第一次 page fault。
- 所有 `mmap` 失敗安全回退到 `pread`。

若遊戲實際使用 `NtMapViewOfSection`，應優先修正 Wine section／host mmap
語意；若遊戲完全使用 `NtReadFile`，單純增加 mmap 不會減少 `NtReadFile`
呼叫數，必須搭配 shared region 或 parser/index cache。

上游 Wine 對照位置是
[`dlls/ntdll/unix/file.c`](https://github.com/wine-mirror/wine/blob/master/dlls/ntdll/unix/file.c)
與 section／virtual memory 相關的 Unix 實作；本專案的 MapleStory 特化邏輯
仍應只放在 CX26 patch，避免改變一般 Wine 行為。

## 6. A/B 測試矩陣

每個組合至少進行三次 cold-start，固定：同一安全地圖、同一角色、同一攻擊、
同一個被動技能觸發條件。每次只做一次主要動作，並在動作前 arm ring。

| 組別 | Cache | Fast hit | Shared region | mmap | 目的 |
|---|---|---|---|---|---|
| A | off | off | off | off | 純 Wine baseline |
| B | on | off | off | off | 目前 adaptive cache baseline |
| C | on | on | off | off | 驗證 mutex／lookup fast path |
| D | on | on | on | off | 驗證跨 handle region reuse |
| E | on | on | on | on | 驗證 mapping 是否還有額外收益 |
| F | on | on | on | off | 加上 bounded async prefetch 的比較組 |

每輪至少保留：

- 使用者回報：無卡／小卡／明顯卡。
- 100 ms timeline。
- per-bin Top-N path。
- `ntread_total_us`、`host_read_us`、`cache_lock_wait_us`、`cache_fill_us`。
- cache hit／fill／bypass／eviction／invalidate。
- 記憶體峰值與遊戲關閉後是否有殘留 Wine process。

## 7. 判讀規則

### 情境 A：Bin 209 的 `ntread_total_us` 明顯下降

代表主要瓶頸在 ntdll cache hit path、global mutex 或 handle lookup。
優先保留 Stage 1／2，暫緩大型 payload 與 mmap 複雜化。

### 情境 B：Bin 209 的時間不變，但 host 幾乎為零

代表問題更接近 WZ parser、資料解碼、物件建立或主執行緒同步。
此時應加入 parser／resource upload 的 CPU span，而不是繼續增加 prewarm。

### 情境 C：Bin 207／208 的 `cache_fill_us` 很高

代表大型 payload 或 read-ahead fill 在互動時段同步發生。優先使用獨立
payload pool 與 background prefetch，並避免 metadata cache 被大型資料驅逐。

### 情境 D：mmap 只有 page fault，沒有減少 NtReadFile

代表遊戲仍走 `NtReadFile`；mmap 不是有效主路徑，應回到 shared region 或
parser/index cache。

## 8. 安全性與正確性要求

- 只對 MapleStory process 與已辨識的唯讀 WZ／MS 檔案啟用。
- 不攔截寫入、truncate、delete、rename 後仍使用舊 cache。
- `fstat` size／mtime／file-id 改變時 invalidate。
- handle close、process exit、異常 terminate 都必須釋放 reference。
- 不在 global cache mutex 內呼叫可能重入 Wine I/O 的函式。
- prefetch 必須可取消，且不能阻塞 `NtReadFile` 等待整個 prefetch 完成。
- 所有新路徑都必須保留原始 Wine fallback。
- 產品預設關閉，直到 cold-start A/B 顯示穩定改善。

## 9. Patch、測試與建置安排

預計新增或調整：

```text
patches/maplestory-cx26-file-cache-fast-hit.patch
patches/maplestory-cx26-file-cache-shared-regions.patch
patches/maplestory-cx26-file-cache-payload.patch
patches/maplestory-cx26-file-cache-timing.patch
tests/test-maplestory-file-cache-patch.sh
```

建議每一階段各自一個 patch，不要把 fast hit、shared region 與 mmap 綁成
單一不可拆解的 patch。每個 patch 都要：

1. 有唯一 marker。
2. 加入 `scripts/build-wine.sh` 的 CX26 apply list。
3. 有 narrow patch test。
4. 以 project Bash environment 做 x86_64 incremental build。
5. 安裝到正確的 `install/wine-cx26-x86_64` prefix。
6. 先做 direct-engine smoke test，再做 MapleStory A/B。

建置與安裝流程遵循：
[`docs/engine-development-test-workflow.zh-TW.md`](engine-development-test-workflow.zh-TW.md)
與
[`docs/incremental-build-and-patches.md`](incremental-build-and-patches.md)。

## 10. 下一個實際工作項目

下一輪不先做大型 mmap。建議順序如下：

1. 實作 Stage 0 的 per-bin path／lock／lookup／copy timing。
2. 實作 Stage 1 的 TLS hot window 與分片鎖。
3. 重新跑 A、B、C 三組，每組三次 cold-start。
4. 只比較 Bin 209 的 `ntread_total_us` 與使用者體感。
5. 若 C 有改善，再進入 Stage 2 shared region。
6. 若 C 無改善，轉向 parser／resource／主執行緒 CPU span，不盲目增加 cache。

第一個工程成功標準不是「所有 I/O 都變成 mmap」，而是：

> 在不增加初始化卡頓、記憶體失控或遊戲關閉殘留的前提下，讓 Bin 209 的
> 大量 cache-hit 小讀取不再形成可感知的第一次攻擊卡頓。

