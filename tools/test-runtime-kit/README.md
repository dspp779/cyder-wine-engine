# Cyder PR #2 + PR #3 測試 runtime

版本：`@TEST_VERSION@`。基底 CX26.3 / Wine 11.0，包含 OpenGL front-buffer present、style-mask 初始化、client visible rect 修正。

測試工具需要 macOS 11+；Apple Silicon 需已安裝 Rosetta 2。DXMT 另需 macOS 15+，DXVK 路徑需 macOS 12+。

DXMT 修正版已補齊專用瓶子的原始 winemetal.dll 可發現檔案。D3D11 裝置測試已回傳 S_OK／feature level 11.0；仍須依 CHECKLIST.md 驗證實際遊戲、視窗切換與長時間穩定性。舊版測試包的 0xc0000135 是啟動器漏做 prefix 準備所致。

## 開始測試

1. 解壓整個 ZIP，保留同一資料夾內所有檔案。
2. 雙擊 **Install.command**。看到「安裝完成」或「已安裝且校驗通過」即可。它不需要管理員密碼。
3. 雙擊 **Verify.command**，應顯示 PASS。
4. 雙擊 **Run Test.command**，選擇後端，再選遊戲或安裝程式 EXE。
   - PR #2 的女神守護之約、BlueCG 等 DirectDraw 黑畫面驗證：選 **wined3d**（預設 OpenGL；BlueCG 的 GDI 對照見下方）。
   - CS2：選 **dxmt**，需要 macOS 15+。
   - DXVK / DXVK2：需要 macOS 12+。

此包安裝到 `~/.cyder-tests/@TEST_NAME@/`，engine、prefixes、logs 分開保存。正常 Cyder 的 engine、瓶子、遊戲庫與偏好不會被替換。首次啟動會建立新的 Windows 環境；遊戲需要的 Steam、VC runtime、字型或其他元件需在這個測試環境安裝。

DXMT 啟動前會在專用瓶子的 system32／syswow64 補入套件中未修改的 winemetal.dll；已相同則不重寫，遇到不同檔案或連結會拒絕覆蓋，請改用新的測試瓶子。

這是直接執行 Wine 的隔離測試工具，**不沿用 Cyder App 的 CompatDB 規則與既有瓶子設定**；測試時明確指定後端。它測的是 engine 與圖形路徑，不等於驗證整個 Cyder App 的啟動流程。未包含 Apple GPTK、遊戲或授權繞過補丁。

## 先做快速檢查

在這個資料夾開啟終端機：

```bash
bash "Run Test.command" --smoke --bottle smoke
```

應看到 64 / 32 位元檔案讀寫，以及 BCrypt「有效簽章接受／修改簽章拒絕」的 PASS。此命令只關閉自己的 smoke 瓶子服務。

可額外檢查 D3D11 裝置建立（這不是完整遊戲／視窗驗收）：

```bash
bash "Run Test.command" --backend dxmt --bottle graphics -- "$PWD/tests/d3d11-device-smoke.exe" --require-winemetal
```

## 指定瓶子與參數

所有瓶子限定在測試目錄下，名稱接受英文、數字、底線及連字號。預設 `shared-test`；同一名稱會持續使用同一環境。

```bash
bash "Run Test.command" --backend wined3d --bottle bluecg -- "/完整路徑/遊戲.exe"
bash "Run Test.command" --backend dxmt --bottle cs2 -- "/完整路徑/Cities2.exe" 參數
```

BlueCG HD 模式 1 的登入畫面目前可用 GDI 對照（不代表 GL 修正已通過）：

```bash
LANG=zh_TW.UTF-8 LC_ALL=zh_TW.UTF-8 bash "Run Test.command" \
  --backend wined3d --wined3d-renderer gdi --bottle bluecg -- "$HOME/games/bluecg/BlueLauncher.exe"
```

在啟動器選 HD 模式 1，等載入圖出現後點一下進入登入介面。新 prefix 的啟動器內嵌網頁需先有 Wine Gecko x86 與 32 位元 mshtml 註冊；參見 repo 的 `docs/upstream-wine-11/bluecg-direct-smoke.md`。本工具不自動安裝依賴。GDI 停用 3D，只適合作為此模式的測試選項，其他 3D 模式不適用；登入、遊戲內、效能及視窗切換仍待驗證。

`--wined3d-renderer` 僅接受 `gl`／`gdi`，且只能與 `--backend wined3d` 搭配。未指定時仍使用 OpenGL；互動選單不會自動套用 GDI。

Steam / CS2：先以 `--backend wined3d --bottle cs2` 安裝並登入 Steam，保持 Steam 執行，再用 `--backend dxmt --bottle cs2` 啟動合法安裝的 Cities2.exe。不要以不同瓶子測「Steam 保持登入」。遊戲或 Paradox Launcher 若要求登入、授權或必要元件，照正常流程處理並記錄失敗點；本包不修改遊戲 DLL。

D3DMetal 需使用者自行合法安裝的 GPTK，可明確指定既有來源，工具只讀取它：

```bash
bash "Run Test.command" --backend d3dmetal --bottle maple \
  --gptk-root "/完整路徑/apple_gptk" -- "/完整路徑/MapleStory.exe"
```

只查看路徑不啟動：

```bash
bash "Run Test.command" --dry-run --backend dxmt --bottle cs2
```

只在該測試瓶子卡住、無法正常離開時使用：

```bash
bash "Run Test.command" --stop --bottle cs2
```

## 還原與移除

正常關閉測試遊戲與 Steam，即可回到原版 Cyder；沒有全域引擎切換需要還原。移除時先確認測試程式已關閉，再在 Finder「前往資料夾」輸入 `~/.cyder-tests/@TEST_NAME@/`，保留需要的測試存檔及日誌後，刪除這個專用資料夾。解壓的測試包也可另外刪除。

不建議直接對正式瓶子做測試。如需沿用既有依賴，先正常結束該瓶子的所有程式，再**複製**瓶子到測試目錄下 `prefixes/自訂名稱`，確認副本不是指向正式環境的符號連結；此工具不會代為複製或修改原瓶子。遊戲本身的安裝目錄、存檔及雲端同步仍依遊戲設定運作，A/B 測試請使用可還原的存檔副本。

## 回報

依 CHECKLIST.md 記錄。日誌在安裝目錄的 `logs/`，每次執行建立獨立檔案；回報時遮蔽帳號、OTP、登入參數。附上 `build-info.json` 的版本、macOS、機型、後端、遊戲版本、瓶子名稱、可重現步驟、預期與實際結果。

本包是 private ad-hoc test，未公證或正式發布。DXMT 保留已核對來源 pin 的上游 0.80 檔案；不把它標成新的正式簽署 graphics release。校驗和驗證傳輸／安裝完整性，不代表所有遊戲已相容。
