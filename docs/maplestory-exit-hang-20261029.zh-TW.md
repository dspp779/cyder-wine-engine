# 2026-10-29 新楓之谷遊戲內退出卡住：取樣分析

狀態：已縮小調查範圍，**尚未確定最初故障點，也尚未修復正常退出**。
本次為新楓之谷，不能套用 MapleStory Classic 的 GRAP/QDO 殘留結論。

## 環境與事件

- Cyder `0.13.2-scroll-test.20261029.1`；引擎 `CX26.3.0-W11-Cyder012`。
- macOS 27.2 (26B123)，x86_64 Wine 經 Rosetta；DXMT 0.80，60 FPS，
  `MTL_HUD_ENABLED=1`，msync/esync 關閉，`WINEDEBUG=-all`。
- prefix：`~/Library/Application Support/Cyder/bottles/shared`。
- 引擎：`~/.cyder/runtime/Engines/wine-x86_64`。
- 使用者確認 14:07、14:12 兩次正常關閉；14:15 這次從**遊戲內選單退出／登出**後卡住。
- 14:21 取樣時根程序 PID 68869 仍存活，先前程序快照約 101–102% CPU；
  BlackCipher PID 71063 約 2%，wineserver PID 68871 約 0.3%；另有三個 DwarfAxe overlay。
  主視窗仍在 WindowServer 中但不在螢幕上；音樂持續。
- 14:26 已在確認 prefix、程序啟動身分且無其他遊戲後，針對此 prefix 停止。
  再次檢查已無 MapleStory、BlackCipher、DwarfAxe、wineserver；保留 Cyder/Beanfun。

注意：request journal 的 `completed / observation-finished` 代表啟動觀察結束，
**不能證明遊戲已正常退出**。前兩次正常關閉是使用者確認，加上後續啟動／server
生命週期的旁證，不能單靠 journal 推導。第三次的 `uncertain` 在 14:15:47
已出現，亦不能直接當成後來退出卡住的錯誤原因。

## 已有證據

### 1. Wine/macOS 主執行緒的例外處理是最具體的線索

遊戲取樣的主執行緒 Thread_691276，1225/1225 個取樣點都呈現：

```text
run_cocoa_app → NSApplication run → main dispatch queue
→ _dispatch_call_block_and_release → 0x0 → _sigtramp
→ segv_handler +159 → 0x209879174 (unknown)
```

已核對實際 runtime `ntdll.so` UUID：
`D806520D-2D81-36EC-B2BB-47BD5734A9B0`，與取樣完全一致。
以該二進位反組譯確認 `segv_handler +159`（檔案位移 `0x3b8af`）
恰為 `call _save_context` 後的返回位置。vmmap 則將未知頂層位址
`0x209879174` 對應到 Rosetta 的 `ntdll.so.aot` 可執行區域。

因此可優先追查主執行緒在 Cocoa callback 中的例外處理；但不能把
`0x0` 直接宣告為已證實的空 block 呼叫，也不能把 AOT 位址直接命名為
`save_context` 內某一條指令。欠缺暫存器、原始 fault PC、每執行緒 CPU 時間
與第二次間隔取樣，尚無法區分「持續卡在 handler」與「重複觸發／堆疊回溯失真」。

多條 Windows 執行緒（包括 dxmt-encode/finish）有大量相同的
`__wine_syscall_dispatcher +389` 回溯。這不足以證明實際遞迴、堆疊溢位或 GPU deadlock。
音訊 callback 仍有活動，符合仍有背景音樂；它本身不是音訊造成退出失敗的證據。

### 2. wineserver 沒有呈現 Classic 的 QDO busy-loop

server 2603 個主執行緒取樣中，2514 個位於 main_loop 的等待路徑；
少數為 read_process_memory、event 等正常請求。沒有高 CPU 的
`get_directory_entries(index=0)` 路徑，且本次根遊戲程序尚未退出。
NGS 仍存在可能只是遊戲尚未結束的結果，不能倒推出 NGS 是起因。

### 3. 共用輸出不是每次啟動獨立、完整且有時間戳的事件紀錄

`last-wine-launch.log` 保留前一個 server 65891 的部分輸出與 atexit，
接著為本次 server 68871 的 start。比較這兩段：

| 訊息 | 前一段 | 本次 |
|---|---:|---:|
| NSEventModifierFlagFunction 警告 | 9 | 9 |
| Illegal Audio-MPEG-Header | 1 | 1 |
| Unknown interface query | 4 | 4 |
| Protocol error / sendmsg disconnected | 0 | 3 |

相同的音訊、DXGI、HUD 警告不能解釋為何只有最後一次失敗。
本次另有 `Protocol error: process 03ec/0794/0100: sendmsg: Socket is not connected`。
原始 source `server/request.c:send_client_fd()` 對應的是 server 向 client 傳 fd
失敗後呼叫 `kill_process(process, 1)`；這是值得追查的通訊異常，不能忽略。
但這些是 Wine Windows process ID，不能當作 macOS PID；紀錄缺少對照與可靠
逐行時間戳，無法證明它們對應遊戲／NGS，或與主執行緒例外的因果先後。
14:26 最後的 SIGINT 與 atexit 是本次人工清理造成，不能算正常退出證據。

## 修復評估

1. **優先候選：macOS 主執行緒的例外／執行緒狀態。** 本地 CX26 的
   `loader.c:apple_main_thread()` 將原生主執行緒留給 CFRunLoop，另啟
   `apple_wine_thread()` 初始化 Windows 執行緒；`save_context()` 會讀取
   `amd64_thread_data()`，其路徑依賴 `NtCurrentTeb()` 的 pthread TLS。
   上游 [MR9579 v5](https://list.winehq.org/hyperkitty/list/wine-gitlab%40list.winehq.org/message/EQ2IPJOEHN4T4OMQAIK4G37PLO5DIRGU/)
   曾提出把 macOS 主執行緒註冊成 Wine system thread 的方案。
   這提供可研究方向，**不是本次已確診為缺少 TEB，也不是可直接移植的修正**。
   需要確認當時主執行緒 TLS／fault register，評估 CX26 與上游執行緒模型差異。
2. **低成本單變量 A/B：先只關閉 Metal HUD。** 本次 HUD 開啟且主執行緒
   處於 dispatch callback；這讓 HUD 成為可先排除的候選，但堆疊沒有證明
   callback 屬於 HUD。保持 DXMT、prefix、滾輪、同步與引擎不變，在相同安全場景
   重複啟動、遊戲內退出。一次成功不能當作修復，因為原本已有兩次成功。
3. 若仍重現，再做獨立的 DXMT/DXVK A/B；不能同時更換 HUD、引擎、同步設定。
4. 不對未知原因增加自動殺 prefix，也不吞掉 SIGSEGV 或僅為此修改全域滾輪。
   同 prefix 可能存在其他遊戲，隱藏視窗也不等於使用者已要求退出。

## 下次重現的採集方式

新增 [`../tools/collect-maplestory-exit-hang.py`](../tools/collect-maplestory-exit-hang.py)。
在仍卡住、尚未清理時，指定**當次** MapleStory.exe 的 macOS PID：

```sh
python3 tools/collect-maplestory-exit-hang.py \
  --pid <當次PID> --out /private/tmp/maple-exit-hang-<唯一名稱>
```

工具只讀取該 PID，兩次採集執行緒 CPU/時間和 3 秒 sample，中間間隔 2 秒，
再取 vmmap。每步核對 UID、PID、啟動秒／微秒，避免 PID 重用。
不呼叫 Wine、wineserver、kill 或 debugger，不採集 argv、環境、登入票券或全程序記憶體；
輸出是權限 0700 的新目錄，失敗保留 incomplete manifest，不覆寫舊資料。
macOS 權限不足時應回報失敗，不以另一個 prefix 重跑。

需要同場補充一次正常退出的前／後快照，並記下遊戲內按下退出的時刻。
若新取樣仍無法解碼，再考慮專用診斷引擎或短暫 debugger 取得 fault PC/TLS。
debugger 會暫停程序，也可能改變反作弊行為；不能將它造成的失敗當作原問題。
不預設開啟會大量輸出或可能含登入參數的 process/loaddll trace。

離線測試：`python3 tests/test-maplestory-exit-hang-collector.py`，5 項通過：
雙次採集與允許的唯讀指令、不錄 argv、拒絕錯誤 EXE、PID 重用／退出、採集失敗。
已另驗證實機 libproc 身分讀取、macOS `ps -M -c` 欄位。
這些測試驗證採集工具，**不是 MapleStory 正常退出或修復驗收**。

本輪沒有修改／重建／替換引擎，沒有改動使用者的遊戲設定。
