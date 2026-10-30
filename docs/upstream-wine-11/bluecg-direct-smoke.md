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
