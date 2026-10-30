# BlueCG direct Wine smoke test（2026-10-30）

使用包含 PR #2／#3 的獨立測試 runtime（engine source `743e5e2`，DXMT prefix launcher fix `6aaf0ef`），直接執行 `$HOME/games/bluecg/BlueLauncher.exe`。未切換正式 Cyder runtime，也未使用既有遊戲 bottle。

## 測試參數與前置條件

- 專用新 prefix；清除繼承的 Wine／graphics override 與 DYLD 變數。
- `CYDER_COMPATDB=0`、`CYDER_GRAPHICS_BACKEND=wined3d`、`WINE_D3D_CONFIG=renderer=gl`。
- `LANG=zh_TW.UTF-8`、`LC_ALL=zh_TW.UTF-8`，從遊戲目錄執行 `arch -x86_64 "$ENGINE/bin/wine" "$HOME/games/bluecg/BlueLauncher.exe"`。
- `WINEPREFIX`、`WINELOADER`、`WINESERVER` 全部限定測試安裝；以程序模組確認載入該安裝的 32-bit PE 與 native winemac。

此案例測 WineD3D／OpenGL，與已另行通過的 DXMT D3D11 裝置測試分開，不宣稱 BlueCG 使用 DXMT。

## 觀察與受控修正

1. 最小 bootstrap 略過 Gecko／Mono 安裝，新 prefix 首次啟動時存在 BlueLauncher 子程序與隱藏主視窗；記錄有 `Could not find object for MIME L"text/html"`。
2. 僅在同一測試 prefix 安裝 Wine 原始碼指定的官方 `wine-gecko-2.47.4-x86.msi`（WineHQ；SHA-256 `26cecc47706b091908f7f814bddb074c61beb8063318e9efc5a7f789857793d6`）。安裝本身未消除 MIME 問題。
3. 正常終止該 prefix 的 BlueLauncher，再執行 `wine 'C:\windows\syswow64\regsvr32.exe' /s mshtml.dll`，回報註冊成功；其餘參數不變後重啟。
4. 視窗擷取可取得完整的 `BlueCG Launcher 2026.10.27.01` 中文介面、經典／HD 啟動選項及公告區域；記錄已進入 Gecko/mshtml／jscript 路徑，仍有 script-error 診斷。未據此推論全部網頁功能通過。
5. macOS 全視窗清單有該主視窗，但 on-screen 清單沒有；正常 app activation 回傳成功後，程序仍未成為 active。尚未確認此現象由啟動器、Wine 或桌面環境造成。沒有對隱藏視窗盲點擊，也沒有以強制 ShowWindow 改變程式正常流程。

## 驗收界線與後續

已驗證直接呼叫與啟動器繪製，**尚未完成互動／遊戲啟動驗收**。遊戲子程序、DirectDraw／GL front-buffer present、登入、縮放、Alt+Enter、最小化／還原、Retina 與多次 Blt 效能均未通過本次測試。需要在可見桌面確認主視窗顯示與遊戲啟動後再驗證 PR #2。

未輸入帳密、修改遊戲 DLL、繞過授權或安裝到正式 prefix；Gecko 只下載到本機測試資料，不納入 runtime 壓縮檔。測試後保留獨立 prefix、啟動器程序及診斷記錄供檢查。

## HD 模式 1 黑畫面追查與 GDI 對照

後續使用者從啟動器進入 **HD 模式 1（高速／無透明）**，回報遊戲黑畫面但仍有登入背景音樂。遊戲子程序已啟動；程序限定模組觀察確認同一測試 runtime 的 i386 builtin ddraw.dll、wined3d.dll、opengl32.dll 及 native winemac.so。原紀錄有 `GL_INVALID_FRAMEBUFFER_OPERATION (0x506)`，位置為 context 初始化的 glClear；此錯誤不能單獨證明持續黑畫面的根因。

| 對照 | 直接觀察 | 驗收限制 |
|---|---|---|
| 原始 WineD3D OpenGL／builtin DirectDraw | 使用者回報黑畫面與登入 BGM；擷取為黑色 client 區域 | 登入呈現失敗；不能算 PR #2 通過 |
| GL，加 `WINEDLLOVERRIDES=ddraw=n,b` | 確認先載入遊戲附帶 DDRAW.dll，再載入 builtin DirectDraw／WineD3D；仍擷取到黑畫面 | 未完成載入圖點擊續行；不採用為修正 |
| 原始 GL 加 macdrv／WGL trace | `GL_FLUSH_PRESENT`（實際旗標 0x08）後有 client-surface present 呼叫 | PR #2 分支確實執行，不代表最終影格正確 |
| GL，`csmt=0` | 設定生效，仍記錄初始化 glClear 錯誤；遊戲於畫面驗收前結束 | 不構成可比的登入測試；不採用 |
| builtin DirectDraw，僅改 `WINE_D3D_CONFIG=renderer=gdi` | 同一 HD 模式可繪製標題／載入圖，**點一下後正常顯示登入介面** | 只確認登入 UI 呈現，不含驗證帳密、伺服器、遊戲內、效能或 3D 模式 |

第一次 GDI 對照漏掉載入圖後的點擊，曾過早判為失敗；使用者補充流程後已重新啟動同一 GDI 設定、擷取載入圖、送出一次經視窗／點位驗證的點擊，再擷取到完整登入介面。因此 GDI 是本次已驗證的 **HD 模式 1 暫時可用路徑**，不是 GL engine 問題的根因修復。GDI 停用 3D，不應成為其他遊戲或其他 BlueCG 3D 模式的全域預設。

新增測試 launcher 參數 `--backend wined3d --wined3d-renderer gdi`（預設仍為 `gl`）。renderer 只接受 gl／gdi，與 DXMT／DXVK 等後端混用會拒絕；先清除繼承的 WINE_D3D_CONFIG，再設定本次值。bootstrap 繼續用原本 builtin OpenGL，遊戲子程序才繼承選定值。新增離線 dry-run 參數／環境隔離測試不執行 Wine，也不替代上表的實機證據。

只變更測試啟動選項與文件，未改 Wine 原始碼、遊戲 DLL 或正式 runtime。記錄與含預填帳號的截圖僅保存在本機，未附到 PR。登入視窗保留給使用者測試，未代為輸入帳密或登入。

後續已完成 A6／PR #2 的單一模組隔離對照：本次 startup-black 收斂至 PR #2 flush callback 新增的 NSOpenGLContext.flushBuffer。移除該呼叫、保留 A6 與 present 後，**OpenGL 登入 UI 恢復，不需 GDI**。GDI 不再是根因修正；詳見 [隔離對照與證據界線](bluecg-a6-present-regression.md)。原測試 ZIP 尚未包含這次新 engine patch。
