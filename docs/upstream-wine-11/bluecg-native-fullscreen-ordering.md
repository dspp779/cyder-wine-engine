# BlueCG 原生全螢幕：子視窗排序例外與修正

日期：2026-11-01（Asia/Taipei）。追蹤：[engine #4](https://github.com/dspp779/cyder-wine-engine/issues/4)。
本文件接續 [三遊戲補測](three-game-soak-2026-10-30.md)，區分原生 macOS 全螢幕與遊戲 Alt+Enter。

## 直接證據與原因

原先 GL、no3d 退出全螢幕後皆曾出現持續裁切，最小化／還原 helper 40 秒逾時，
標準退出也未能使遊戲結束。事後以已知 PID／時間讀取 unified log，兩次都有
`NSRangeException`；完整例外堆疊指出：

```text
-[__NSArrayM insertObject:atIndex:]
-[WineWindow order:childWindow:relativeTo:]
-[WineWindow orderBelow:orAbove:activate:]
PerformRequest
```

`cocoa_window.m` 的排序方法先從 window-server 的前到後 snapshot 移除待排序的
child，再尋找參考視窗 `other`。若參考視窗暫時不在 snapshot，`indexOfObject:`
回傳 `NSNotFound`；原方法直接以它或它加一作為插入索引，必然超出陣列邊界。
原始實際 Objective-C 方法的最小重現也確實拋出同一個 `NSRangeException`。
這不是僅根據 CPU sample 猜測的鎖問題。

例外由 run-loop 的 `PerformRequest` 處理 request 時逸出，打斷 pending request
的排空；`orderBelow:` 也還沒有走到配對的 screen-update 恢復。舊 sample 顯示
Windows 遊戲執行緒停在 `macdrv_set_cocoa_parent_window` → `OnMainThread` 等待。
這解釋了視窗幾何已恢復、遊戲內容卻停留在全螢幕尺度，以及後續視窗操作／退出
可能卡住的連鎖。新增切換事件有時能讓 request 繼續處理，因此不是每一次退出
都永久卡死；不能把 `AXFullScreen=false` 或尺寸還原當作畫面及事件處理通過。

## 修正

`patches/cyder-winemac-missing-order-anchor.patch` 只改動上述排序方法：

- snapshot 找得到參考視窗時，沿用原有路徑。
- 找不到時，從 Cocoa parent 的既有 `childWineWindows` 取得後到前的順序，
  將已存在的 child 移到參考 sibling 的上／下方，再用既有 setter 重排。
- child 或參考 sibling 不在該 parent 中、或相對自己排序時，不附加未知視窗。

後到前陣列的 Above 插在參考者之後，Below 插在之前；與 window-server
前到後 snapshot 的索引方向相反。這一點由實際方法回歸測試覆蓋。
此引擎修正不修改縮放公式、全域 renderer、Win32 driver ABI，也不 patch 遊戲 DLL；
官方 updater 的核心檔更新另列如下。

## 同遊戲檔的反向確認

本輪官方啟動器要求修復核心檔。先保留舊副本，再由官方 updater 完成修復；
只有 `bluecg.dll` 改變，EXE／既有 DDRAW 未變。以下兩種 runtime 比較都使用
更新後同一份遊戲檔、同一角色及 prefix，不能將遊戲更新當作引擎修正成效。

| 核心檔 | 大小（bytes） | SHA-256 |
|---|---:|---|
| 原始備份 bluecg.dll | 3,170,304 | `2a077cba7325953f1518fe83b7bdd0371a21e5b7d1f1e476a5eff87e3af0b937` |
| 官方更新後 bluecg.dll | 3,181,568 | `832fd1de73783849251a1b397f082d289feb957eaabac1473a77ce4a28d8ed1a` |

更新後遊戲畫面顯示核心版本 `2026/11/01 05:55:36 (UTC+8)`；啟動器仍為
2026.10.27.01。Apple M4／16 GiB、macOS 27.2（26B123）、HD [1]／3Ddevice:1、
1x、client 961×721，召喚之間 (15,6)，小地圖開啟、同一宋體替代配置。
本次反向確認為單開；先前原始失敗為兩開，兩者不混作效能比較。

| Runtime／renderer | 實際觀測 |
|---|---|
| 原始／GL，6 輪 | 第一輪畫面／最小化還原正常；後續第 2、5 輪返回截圖裁切，再次切換有時恢復。系統紀錄 15 筆 AppKit NSRangeException，完整堆疊與原失敗相同。最末還原與標準退出可完成，不宣稱六輪都永久卡住 |
| 修正／GL，3 輪 | 3 輪返回均恢復正確比例，3 次最小化還原均 0→1→0、client 961×721；全螢幕狀態按鈕開啟及視窗狀態按鈕關閉面板成功；標準退出完成；系統同類例外 0 |
| 修正／no3d，6 輪 | 六張返回畫面均正常，六次最小化還原均 0→1→0、client 961×721；全螢幕開啟／視窗模式關閉狀態面板成功；標準退出完成；系統同類例外 0 |

原始 runtime 在更新後遊戲仍出現同一排序例外，排除「只是遊戲更新就移除了此
引擎例外」的說法；這也修正了第一輪未重現時的暫時判斷。

## 建置與回歸

獨立 `engine-fullscreen-fix` 只替換重建的 `winemac.so`，保留原始 runtime。
載入模組已以遊戲 PID 的 lsof 核對；host 為 x86_64／minOS 10.15，strict ad-hoc
簽章通過，動態依賴清單與原始模組相同。win32u.so 未更動。

- 新 winemac.so SHA-256：`fe31b28d36cc39f0ea547b13d01456b00c02055c6e15a713588dae368811ec12`。
- `tests/test-winemac-missing-order-anchor.sh`：先執行原方法確認 NSRangeException，
  再驗證修正後正常／缺失／空 snapshot／自身／未知參考及未知 child，最後反向還原 patch。
- 完整 `tests/run.sh` 結束 0：54 Shell entrypoints、27 Python tests。
  因預設 install 路徑不存在而跳過的 runtime 檢查，另顯式指定診斷 runtime 補跑：
  frame-walk、x86_64／i686 檔案與 BCrypt、真實 GL 8 native front flush／8 swap 均通過。
  既有 optional MoltenVK live-source round-trip 仍因缺少 patched source 跳過，content checks 通過。
- 標準腳本已多次套用／檢查新 patch，marker 僅一份。完整 media configure 因既有
  GStreamer 開發 header 路徑缺失未成功；原先驗證過的 Makefile／config.status／config.h
  與明確工具鏈、10.15 flags 保留，僅增量重建 winemac。這不是完整媒體／TLS 重建或發布包。

原始遊戲截圖、unified logs 與 sample 含角色文字／本機資訊，保持私有。
排序修正與回歸測試提交：[ `dda03d1` ](https://github.com/dspp779/cyder-wine-engine/commit/dda03d11b85434923dcd985fdb618d017f89e398)。
分支為 `codex/bluecg-native-fullscreen-ordering`，以 PR #3 分支為基底供獨立審查；
尚未合併或發佈，不表示正式 Cyder runtime 已包含修正。

修正版測試結束後已正常關閉遊戲並停止各自 prefix 的殘留服務，視窗盤點為空、
輸入來源已還原；原始 runtime 兩個模組的 hashes 完全不變。
本機只驗證上述 1x、單開、單螢幕序列；未把先前一般視窗的 2x Retina 結果算作
本修正的 2x 原生全螢幕回歸，也未重跑一小時效能／記憶體長測。
