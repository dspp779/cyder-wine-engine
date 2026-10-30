# BlueCG OpenGL 啟動黑畫面：A6／PR #2 隔離對照

**後續校正：正確修正是補上上游 62da9c02 的前置通知修正，保留 flushBuffer。**
先前 bc4ba8f 的刪除方案只證明「避開這次呼叫可以恢復畫面」，不能證明
flushBuffer 在所有呈現情境都多餘。後續單一變因實測已確認：A6、原始 PR #2
與 flushBuffer 全部保留，只修正 win32u 綁定時誤送的 PRESENT 旗標，同樣恢復
標題／載入／登入 UI。以下較早的移除對照保留為研究歷程，由文末的新結果取代。

2026-10-30。使用者補充：Cyder 0.13.2／整合 PR #2、#3 前，不需 GDI 即可顯示，原本問題是視窗拉伸後黑畫面。本次區分「啟動即黑」與「resize 後黑」，不以 GDI 當 engine 根因修正。

## 結果

同一 CX26.3／Wine 11.0 基底、HD 模式 1、builtin DirectDraw、`renderer=gl`、繁中語系、CompatDB 關閉。診斷 runtime 由相同已校驗測試 engine 複製，只有獨立重建的 winemac.so 不同；prefix 從同一靜止測試 prefix 各自複製，避免 server 或殘留設定混用。模組均為 x86_64／minOS 10.15，診斷副本 ad-hoc 簽署後驗證，程序限定的載入觀察核對實際路徑。

| A6 | PR #2 | 僅移除 flush callback 的 native buffer flush | 載入／點擊後登入 |
|---|---|---|---|
| 保留 | 保留 | 否 | 黑畫面；原測試有初始化 glClear 的 GL_INVALID_FRAMEBUFFER_OPERATION |
| 移除 | 保留（同等 present 行為適配至無 A6 source） | 否 | 點擊前後仍黑；初始化 glClear 錯誤未再出現 |
| 保留 | 移除 | — | OpenGL 載入圖與登入介面恢復 |
| 保留 | 保留 | 是 | OpenGL 載入圖與登入介面恢復，初始化 glClear 錯誤未再出現 |

各次都使用啟動器 HD 模式 1；登入 UI 前依正常流程點一下，未輸入帳密、送出登入或修改遊戲 DLL。截圖含遊戲預填資料，僅保存在本機，不附到 PR。

## 第一輪收斂到的觸發呼叫（尚非完整根因）

PR #2 的 `macdrv_surface_flush` 在 `GL_FLUSH_PRESENT` 新增：

```c
macdrv_flush_opengl_context(context->context);
client_surface_present(base->client);
```

第一行不是單純的 glFlush：`cocoa_opengl.m` 明確呼叫 `[context flushBuffer]`，其語意包含 double-buffered context 的 native buffer exchange。此通知也會由 `wglMakeContextCurrent` 在 context binding 階段送出，不能當作應用程式的 SwapBuffers。

在現有 CX26 Wine 路徑，`win32u_wgl_context_flush` 先執行呼叫者的 glFlush／glFinish，才通知 drawable；若 `GL_FLUSH_FORCE_SWAP`，之後又明確呼叫 swap callback。因此在 flush callback 再做一次 native buffer flush 是多餘的 buffer-exchange 行為；雙緩衝的 front-buffer emulation 還可能走到兩次交換。最小實測顯示只去掉這一呼叫就足以恢復 BlueCG 載入／登入呈現。

本次因果證據支持「PR #2 新增的 native flushBuffer 是目前 startup-black 回歸的觸發點」。A6 不是單獨充分原因；不能因移除 A6 讓某行 GL error 消失，就宣稱畫面修好了。至於每個 frame 的 buffer 像素如何被交換、其他遊戲是否有相同路徑，尚未做完整 GPU tracing，不延伸宣稱。

## 第一輪緩解方案與測試（已被上游方案取代）

後續 patch `cyder-winemac-gl-flush-no-buffer-swap.patch` 依序套在 PR #2 後面：

- flush callback 保留 A6 conditional backing sync 與 client_surface_present，不交換 native buffers。
- swap callback 保留原本 native flush／swap、present、NULL-context guard，不改 ABI。
- GL_FLUSH_FORCE_SWAP 仍由 win32u 的既有 swap callback 處理。
- build apply marker、release config 的有序 patch list 與 A6 reverse／reapply 測試一起更新；manifest writer 直接讀 canonical release config。
- actual-function 測試改用真實旗標位元（FINISHED=1、INTERVAL=2、UPDATED=4、PRESENT=8、FORCE_SWAP=16），涵蓋全部 32 組旗標、pending/non-pending、read-view 是否相同、NULL context、patch 冪等／往返，以及 flush 加 swap 只有一次 native exchange。

診斷建置在 source 副本與單獨 object 目錄進行，沿用已確認的 project Bash 環境、compiler、10.15 flags 與相同 ABI dependencies，沒有修改原 build/install 或既有測試包。正式修正另經 `build-wine.sh --configure-only` 套用並重建正式 source 的 winemac 模組。

## 仍需驗收

本次恢復的是 HD 模式 1 的標題／載入／登入 UI。尚未驗證帳密、伺服器、遊戲內、多次 Blt 效能或其他模式；也不代表原來 resize 問題已解決。嘗試對修正版登入視窗做 native resize 時，前景／點位檢查拒絕了操作，未送出 drag，因此不記為 resize pass。Alt+Enter、minimize/restore、Retina 與女神守護之約等 PR #2 目標遊戲仍須重測。

舊的 dxmtfix1／bluecg-gdi1 ZIP engine 含原始 PR #2 行為；其檔案與 hash 保持不變，不能標為已包含本次 GL 修正。目前修正版是本機診斷 runtime 與 PR source，尚未重新產生 shipping archive；正式 runtime 未替換。

### 本次回歸結果

正式 source 的 winemac.so 重建成功，仍為 x86_64／minOS 10.15。完整 `tests/run.sh` exit 0：43 個 Shell 入口及三組 Python 測試（8、8、7，共 23 項）通過；僅原有 optional MoltenVK source live-round-trip 因缺少 patched MVKSync.mm 而 skip，patch content checks 通過。補強後的 front-buffer 旗標／冪等測試另再次執行通過。未執行完整 upstream Wine conformance suite，也未以此取代其他遊戲 GUI 驗收。

## 上游前置修正：取代刪除 flushBuffer（後續驗證）

上游提交順序：

1. Wine 11.3 的 [62da9c02](https://github.com/wine-mirror/wine/commit/62da9c02a7b349e10601e4e2430ed824c1a074fe)，2026-02-19：context_sync_drawables 綁定 new_draw 後，保留 flush 通知但移除 GL_FLUSH_PRESENT。
2. Wine 11.4 的 [b5ab3b15](https://github.com/wine-mirror/wine/commit/b5ab3b155a58823595a6a7bdbefb5b4e98736957)，2026-02-25：winemac 在真正收到 PRESENT 時執行 native flushBuffer 並選定 client surface；PR #2 backport 了這項行為，卻未帶上前一項。

**較精確的根因是 backport 缺少前置的通知語意修正**。CX26 以「context 綁定／drawable 同步」冒充「frame 應呈現」，b5ab3b15 才在這個錯誤時機觸發 native 呈現。移除 flushBuffer 是遮斷結果，修正上層通知才保留原本應有的呈現行為。

上游目前的 winemac 仍保留 flushBuffer，較新 win32u 也有 GL_FLUSH_ACTIVATE 分離啟用通知；不能把 bc4ba8f 宣稱為上游通用修正。Apple 的 [flushBuffer 文件](https://developer.apple.com/documentation/appkit/nsopenglcontext/flushbuffer())指出它在 double-buffered context 將 back buffer 複製／可能交換到 front，且隱含 glFlush；非 double-buffered context 為 no-op。它與單純提交 GL 命令不同。

本次新對照：同一舊測試 engine、相同 prefix 快照、renderer=gl／HD 模式 1，只重建替換 win32u.so 的該一行；winemac.so 直接保留原始含 A6／PR #2／flushBuffer 的版本。載入觀察核對這兩個 native 模組及 builtin WineD3D。標題／載入圖出現，正常單次點擊後登入 UI 完整顯示，使用者也即時回報「有畫面」。未操作帳密。minOS 10.15、ad-hoc 簽章驗證通過。

此組合仍記錄兩次初始化 glClear 的 GL_INVALID_FRAMEBUFFER_OPERATION，但登入畫面已正常，進一步說明該 error 並非持續黑畫面的充分判據。尚未做逐 frame 的 GPU buffer tracing，不宣稱已直接觀測每次黑色像素的來源。

整合改為 `wine-win32u-no-present-on-context-bind.patch`，排在 PR #2 的 present patch 前；原刪除方案移入 obsolete 並在增量建置中安全反向移除。native flushBuffer、真正的 present、swap callback 與 A6 都保留。離線測試以實際 context_sync_drawables 函式驗證綁定成功／失敗、同／異 read/draw、reuse 均不誤送 PRESENT，同時保留 winemac 的真實呈現測試。舊 bc4ba8f 的回歸計數是歷史結果，新的完整回歸另行記錄。

### 最終上游方案的驗證結果

正式 build entrypoint 已反向移除舊 workaround、套用 62da9c02 適配 patch；正式 source 的 win32u.so 與 winemac.so 重建成功，均為 x86_64／minOS 10.15。新 stack 的完整 `tests/run.sh` exit 0：**44 個 Shell 入口、23 項 Python 測試通過**；仍只有既有 optional MoltenVK source round-trip skip（patch content checks 通過）。新增 context-bind／遷移測試另再執行通過。

實機登入 UI 的成功不等於完整 3D／front-buffer emulation／resize 驗收；既有 GL 初始化錯誤仍另外追蹤。這次沒有改變正式 runtime，也沒有重包先前已交付的 ZIP。
