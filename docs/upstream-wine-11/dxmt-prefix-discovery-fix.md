# DXMT winemetal 載入失敗：prefix discovery 修正

## 原因與對照

舊獨立測試 launcher 設定了 CX graphics backend 與 Unix DLL prepend，但沒有執行 Cyder App 已有的 `cyder_ensure_dxmt_winemetal_prefix` 等價準備。

Wine 11 PE loader 的 `find_dll_file` 先搜尋 Windows DLL 路徑；`find_builtin_without_file` 在正常 64-bit 瓶子（非 bootstrap／非舊 32-bit prefix 特例）不會搜尋缺少 prefix 檔案的任意 builtin。新 prefix 中沒有 system32／syswow64 的 winemetal.dll，因此尚未進入 Unix `load_builtin`／backend prepend 路徑，就回傳 DLL_NOT_FOUND。加入 WINEDLLPATH 或 dylib 路徑無法繞過這個前置發現流程。

在同一瓶子、同一引擎、同一個 D3D11 程式，只補入原始 DXMT 0.80 的 x86_64／i386 winemetal.dll 後，從 `0xc0000135` 轉為 `D3D11CreateDevice HRESULT=0x00000000 feature_level=0xb000`。未修改 Wine DLL 搜尋政策、DXMT 位元組或遊戲 DLL；這個結果不支持先前懷疑的 engine／DXMT ABI 不相容。

## 修正範圍

- `prepare-dxmt-prefix.sh` 僅處理已標記版本、屬於測試安裝的 prefix。
- 原始來源必須存在、非 symlink；呼叫者先驗證 sealed engine 的所有檔案 hash。
- 先檢查兩種架構與 Windows 目錄，再複製任何檔案。
- 缺檔以暫存檔與 atomic no-clobber link 發布；已相同不改 inode／mtime。
- 不同的既有 DLL、symlink、外部 prefix 或越界 Windows 目錄一律拒絕，不覆寫未知檔案。
- 安裝後、builtin wineboot 完成後、選定 DXMT 的遊戲啟動前執行。不需要全域 engine patch，也不碰正式 Cyder runtime。

7 項離線測試涵蓋原始位元組、冪等、第二架構缺失時不先寫第一架構、未知 DLL 保留、symlink／外部 prefix／目錄越界及版本不符拒絕。實機 D3D11 探測另要求 `winemetal.dll` 已載入，避免只憑 backend 名稱判定 DXMT。

## 實機驗證結果（2026-10-30）

修正啟動器在全新專用瓶子自動完成 builtin wineboot 與 prefix 元件準備後：

```text
DXMT prefix discovery: original x86_64/i386 winemetal.dll ready
D3D11CreateDevice HRESULT=0x00000000 feature_level=0xb000
winemetal loaded=yes path=C:\windows\system32\winemetal.dll
```

在探測程序仍持有裝置時，程序限定的 native module 觀察同時找到套件內 `lib/dxmt/x86_64-unix/winemetal.so`、DXMT 的 d3d11.dll／winemetal.dll，以及同一引擎的 winemac.so／ntdll.so。不是僅依後端環境名稱或回退的 WineD3D 裝置判定通過。

7 項 helper 安全／冪等測試與既有 7 項 test-kit 單元測試通過。修正不需重新編譯 Wine，原始 engine／DXMT 位元組未變；修正版 test kit 使用獨立 `dxmtfix1` identity，保留舊 ZIP 的歷史 hash。

## 驗證界線

D3D11 裝置建立不是 CS2、全螢幕切換、模組或長時間遊戲驗收。DirectDraw／BlueCG 仍以 wined3d OpenGL 作獨立案例，避免混淆 PR #2 的修正路徑。舊測試 ZIP 保留原始 hash 與失敗紀錄；修正版另用新目錄／測試 identity，不覆寫已交付版本。
