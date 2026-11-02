# AX-only 最小化還原：原因、修正與本機驗證

2026-11-02，基於 PR #6 的 `cbb51ab`，以獨立 `codex/winemac-ax-restore` 分支調查。
**修正版已通過本機 AX-only 還原、32／64 位元控制及 BlueCG Retina GL／GDI 雙開驗證。**
正式 runtime 未更動；#7、#8 未合併、未移植，維持原 head 與 Draft。

[去識別化數據、模組身分與私有證據 SHA-256](assets/ax-unminimize-2026-11-02/validation.json)。
原始遊戲畫面、角色／帳號、憑證及詳細程序日誌不公開。

SHA 快照補註：`private_evidence_sha256` 保留原始取樣結果。其中 `bluecg-gl.log`
與 `bluecg-gdi.log` 的快照長度分別為 48,275／47,843 bytes，取於遊戲正常退出驗證後、
wineserver 最終退出訊息寫入前。兩份日誌其後各追加一行 29 bytes 的正常 `atexit`
診斷；已逐位元確認原 SHA 對應最終檔案的完整前綴。`private_evidence_snapshot_notes`
另列快照長度、原 SHA、最終長度與最終 SHA，不覆蓋原證據，也不公開程序 ID。


## 直接證據支持的原因

舊版 `AXMinimized=true` 可以最小化；設為 false 雖回傳成功，讀回仍為 true，
原 CGWindow 不再可見，也沒有 Win32 restore 事件。這不是 #6 排序修正新引入的問題：
先前不含 #6、未進全螢幕的 #3 已重現；本輪又以無帳號的最小 Win32 GDI 視窗重現。

本機 macOS 27.2 的受控結果：

| 對照 | AX false 的結果 | 意義 |
|---|---|---|
| 原生 AppKit NSWindow／NSPanel，維持原樣式 | 成功還原同一視窗 | 原 AX helper 與系統權限可工作 |
| 原生 NSPanel，在最小化通知清除 style mask 為 0 | 回報成功但維持最小化 | 不需 Wine／BlueCG 即可重現 |
| 同一 NSPanel 保留 `NSWindowStyleMaskMiniaturizable`，style=4 | 成功還原 | 支持可最小化樣式是關鍵變因 |
| 未修正 Wine 控制視窗 | 同樣失敗 | 不只 BlueCG、也不依賴 GL |
| 直接使用既有原生 `deminiaturize:` 路徑 | 成功，收到 Win32 `SC_RESTORE` | 可以修在 AX 還原邊界 |

只用於診斷的 Objective-C trace 顯示：Wine 最小化時，Win32 iconic geometry
導致 Cocoa style mask 從 0xf 變成 0；繼承的 `setAccessibilityMinimized:NO`
此時沒有呼叫 `deminiaturize:`，也未送出 unminimize 通知。反之，AX true
會走正常的 miniaturize／Win32 `SC_MINIMIZE` 路徑。

這是本機實驗與追蹤支持的因果關係；不據此宣稱所有 macOS 版本的 AppKit
實作都完全相同，也沒有把 GDI、cnc-ddraw 或遊戲字體設定當成這個故障的原因。

## 採用的修正

新增 `cyder-winemac-ax-unminimize.patch`，在 WineWindow 覆寫現代 AX setter：

```objc
- (void) setAccessibilityMinimized:(BOOL)minimized
{
    if (!minimized && [self isMiniaturized])
        [self deminiaturize:nil];
    else
        [super setAccessibilityMinimized:minimized];
}
```

只有「確實已最小化，且 AX 要求還原」走既有 Cocoa restore／notification 路徑。
最小化請求、已還原視窗、只是 hidden 的非最小化視窗仍交給 AppKit。
不改樣式計算、排序演算法、renderer、遊戲設定或 driver ABI；未放寬 AppKit 的
最小化驗證，也未用 Win32 `SW_RESTORE` 偷渡成 AX 通過。

另一個「當 `isMiniaturized` 為真時保留 miniaturizable bit」原型已拒絕：
樣式在動畫途中、`isMiniaturized` 尚未變真時就被清除，因此仍失敗。
最終測試 runtime 沒有使用 swizzle、DYLD 注入或這個原型。

修正已加入 CX26 patch apply list、canonical manifest 及 marker-first 重複套用保護。
新增測試編譯真正 patch 中的方法，驗證還原、重複 false、允許／拒絕最小化、
hidden 非最小化視窗的 delegation，並透過 production helper 連套兩次、反向還原。

## 建置與完整回歸的界線

獨立複製來源／build metadata，確認 #6 baseline，移除副本內 #7／#8 的後續實驗，
再透過 production apply helper 套用新 patch。依專案 Bash env、x86_64、SDK 與
10.15 flags 進行單一 `winemac.so` 增量建置，沒有 `make install` 到正式路徑。
私有診斷 runtime 只有下列一個 regular file 與既有 #6 診斷 runtime 不同：

| 項目 | 結果 |
|---|---|
| 替換模組 | `lib/wine/x86_64-unix/winemac.so` |
| SHA-256 | `d6c34a212f7a27dcb8a7fa72ac68de631fe1e1c33d6dda5a384e7746f61966d9` |
| 架構／最低 OS | x86_64／10.15 |
| 簽章與依賴 | strict ad-hoc 驗證成功；動態依賴清單不變 |
| 全套 `tests/run.sh` | exit 0，54 個頂層 Shell 入口 |
| 頂層 Python suites | 43 案例，42 通過，1 個選用 real crypto skip |
| 明確指定修正版 runtime 的 probe | frame-walk、i686／x86_64 file／BCrypt 通過 |
| 真實 GL profile control | 8 次 native front flush、8 次 swap |

計數以 `tests/run.sh` 陣列及 Python suites 為準，不把巢狀日誌當額外入口。
MoltenVK patched-source live round-trip 因缺少相應 source 跳過，content checks 通過。
完整 configure 曾嘗試，但被私有 x86_64 FreeType 開發檔案 preflight 阻擋；
**本輪不是完整 media／TLS 重建，也不是新 shipping package。**

## 實際視窗驗證

本機 Apple M4／macOS 27.2，單一 1680×945 points、2× 螢幕。
操作以精確 host PID、CGWindow ID、唯一 AX title 驗證目標；WoW64 使用真正的
視窗擁有者 PID，不能將初始 launcher PID 當作視窗 PID。

| 測試 | AX-only 最小化／還原 | 原生 Space 往返 | 正常退出與其他檢查 |
|---|---:|---:|---|
| x86_64 Win32 GDI 控制 | 3／3 | 2／2 | 3 次真正 `SC_RESTORE`；WM_CLOSE、message-loop exit、owner 結束 |
| i686 Win32 GDI 控制 | 3／3 | 2／2 | 同上；不是三分鐘 timer 清理 |
| BlueCG HD[1]、GL、Retina=y／96DPI | 3／3 | 3／3，另一次全螢幕輸入檢查 | 與 GDI 同時在線；還原後可操作；從原生全螢幕正常退出 |
| BlueCG HD[1]、GDI／no3d、Retina=y／96DPI | 3／3 | 3／3，另一次全螢幕輸入檢查 | 與 GL 同時在線；回切可關面板；從一般視窗正常退出 |

控制視窗使用獨立合成 prefix；BlueCG 兩個 client 使用各自複製的 prefix／遊戲。
從同一官方啟動器 HD[1] 進入既有角色；僅以 WineD3D renderer=gl／gdi 對照，
沒有使用遊戲 `--soft3d`、cnc-ddraw 或 #7／#8 的縮放 helper。
日誌分別確認 `Using the OpenGL renderer`／`Disabling 3D support`，兩個遊戲 PID
都確認載入修正版模組且無 trace injection。

遊戲返回 481×393 points／962×786 pixels，原生 Space 為
1680×945 points／3360×1890 pixels。每輪要求相同 CGWindow ID、原位置與尺寸，
且 AXMinimized 讀值必須 false→true→false，最小化時從 on-screen list 消失。
同類 `NSRangeException` 兩個 client 均為 0。雙開是兩個獨立 prefix，
不外推到同一 prefix 多 client 或三開的全部組合。

六張還原後固定字體 ROI `(110,770)-(600,784)` 與各自 baseline 的 MAE=0、
最大通道差=0。這表示還原未額外破壞字體；不代表原本的非整數縮放階梯感已修好，
也不把不同 renderer 的底層字體品質當成此次 patch 的效能結論。

| 路徑 | 基準字體裁圖 | 第三輪 AX 還原後 |
|---|---|---|
| GL | ![GL 基準](assets/ax-unminimize-2026-11-02/gl-baseline-font.png) | ![GL 還原](assets/ax-unminimize-2026-11-02/gl-cycle-3-font.png) |
| GDI／no3d | ![GDI 基準](assets/ax-unminimize-2026-11-02/gdi-baseline-font.png) | ![GDI 還原](assets/ax-unminimize-2026-11-02/gdi-cycle-3-font.png) |

另執行既有 GL→GDI→重建 GL 可見控制，三階段實際呈現紅／綠／藍並正常結束。
經螢幕色彩管理轉成 sRGB 後中心值分別為 (255,38,0)、(7,249,0)、(4,51,255)，
以正確主色驗證，不將螢幕截圖誤當成未經色彩管理的 framebuffer 精確值。
安全控制截圖：[紅](assets/ax-unminimize-2026-11-02/GL_RED.png) ·
[綠](assets/ax-unminimize-2026-11-02/GDI_GREEN.png) ·
[藍](assets/ax-unminimize-2026-11-02/GL_BLUE.png)。

### 未列入通過的工具試跑

- 第一版 fullscreen helper 在 AX true 後立即反向切換；AppKit 動畫未完成，false 被忽略。
  修正工具為等待至少 2 秒、bounds 穩定 1 秒及 AX 讀值吻合後，再開始下一步；重新測試通過。
- 舊試跑在完成全部週期後，額外 AX close-button action 回報失敗；這不等於正常退出通過。
  最終工具移除此非必要選項；新控制改用限定 fixture 的 WM_CLOSE，明確觀察 owner 結束。
- 本機 Dock 未提供唯一且 exact-title 符合的 `AXMinimizedWindowDockItem`。
  工具拒絕點擊模糊的 Wine Dock 項目，要求 AX 清理還原後正常 WM_CLOSE。
  **Dock 縮圖／Dock app menu 還原仍未獨立驗收**，不能由 AX-only 通過推定。

## 需其他硬體／系統環境的清單

| 環境 | 必做驗證 |
|---|---|
| 混合 1×／2× 多螢幕 | 跨螢幕移動、Space 往返、最小化還原、點擊座標、字體與顯示器移除／重接 |
| Intel Mac | 實際 x86_64 AppKit／AX／GL／GDI 行為；Rosetta 上的 x86_64 執行不能替代 |
| 其他支援的 macOS（包含最低版本環境） | 編譯 API／載入、AX 與原生動畫、正常退出；10.15 metadata 不是實機驗收 |
| 其他 Apple Silicon／外接解析度與更新率 | 同一程序與像素矩陣；不能由單一 M4 螢幕外推 |

以下**不是硬體需求**，另行保留：

- Dock 入口需能唯一識別的 Dock UI 或人工觀測；不需要購置硬體。
- CEF／Steam／MapleStory D3DMetal、CS2／Paradox／DXMT 完整 GUI／遊玩仍需指定合法
  軟體版本與帳號／資料；窄函式、合成視窗及 BlueCG 不等於這些應用驗收。
- display scanout／真正多次 front-buffer Blt 的成本未測；本輪沒有新增 CPU、功率或效能排名。
- 選用 Authenticode real crypto／MoltenVK source case 需要工具或 source inputs。
- 完整依賴開發檔案、乾淨全 build、media／TLS、正式 Developer ID pack／round-trip
  仍是發行工作；不得直接把這個診斷 `.so` 複製到正式 runtime。

## 重測與交付

工具與原始碼：[受限 AX 生命週期控制](../../tools/window-lifecycle/README.md)。
先觀測精確 target，執行 `ax-window-cycle ... --cycles 3 --fullscreen-cycles 2`，
確認 actual readback、可見性與 geometry；不要以 setter success 當還原成功。
合成控制另以同 prefix 的 `win32-control.exe --close` 結束，檢查 WM_CLOSE 及 owner exit。

兩個遊戲與啟動器均正常退出；三個獨立 prefix 的 wineserver 等待均正常返回，
未留下本輪測試程序或 Wine 視窗，輸入來源已還原。
主 checkout 的 tracked diff SHA-256 與進入本次審查前相同；其他未提交修改未納入。
不宣稱主 checkout 的所有 untracked 檔案在其他並行工作期間都沒有變動。

此修正獨立疊在 #6 後，保留 #3→#6→AX 修正的審查順序。
#7 head `6a35862044a8792e5c896ba45fa4d49090978240`、
#8 head `5be38245d751360302751228918f64ab88fda0e7` 維持 Draft。
issues 保持 open，本輪不執行 merge 或正式 runtime 安裝。
