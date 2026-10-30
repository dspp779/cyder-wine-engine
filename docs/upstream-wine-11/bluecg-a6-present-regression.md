# BlueCG OpenGL 啟動黑畫面：A6／PR #2 隔離對照

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

## 收斂到的問題點

PR #2 的 `macdrv_surface_flush` 在 `GL_FLUSH_PRESENT` 新增：

```c
macdrv_flush_opengl_context(context->context);
client_surface_present(base->client);
```

第一行不是單純的 glFlush：`cocoa_opengl.m` 明確呼叫 `[context flushBuffer]`，其語意包含 double-buffered context 的 native buffer exchange。此通知也會由 `wglMakeContextCurrent` 在 context binding 階段送出，不能當作應用程式的 SwapBuffers。

在現有 CX26 Wine 路徑，`win32u_wgl_context_flush` 先執行呼叫者的 glFlush／glFinish，才通知 drawable；若 `GL_FLUSH_FORCE_SWAP`，之後又明確呼叫 swap callback。因此在 flush callback 再做一次 native buffer flush 是多餘的 buffer-exchange 行為；雙緩衝的 front-buffer emulation 還可能走到兩次交換。最小實測顯示只去掉這一呼叫就足以恢復 BlueCG 載入／登入呈現。

本次因果證據支持「PR #2 新增的 native flushBuffer 是目前 startup-black 回歸的觸發點」。A6 不是單獨充分原因；不能因移除 A6 讓某行 GL error 消失，就宣稱畫面修好了。至於每個 frame 的 buffer 像素如何被交換、其他遊戲是否有相同路徑，尚未做完整 GPU tracing，不延伸宣稱。

## 整合修正與測試

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
