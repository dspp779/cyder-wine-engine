# PR #2 + PR #3 測試 runtime 封裝驗證（2026-10-30）

- Engine source：`743e5e21d1d95ec1d120c41ac42821bf310ec69e`，PR #2 merge 已包含於 PR #3 分支。
- 版本：`CX26.3.0-W11-Cyder012-test-pr2-pr3-743e5e2`；private ad-hoc test，未公證／正式發布。
- 核心封存：`engine-wine-x86_64-CX26-3-0-W11-Cyder012-test-pr2-pr3-743e5e2.tar.xz`。
- 核心 SHA-256：`30354edf63abfcbe5611d1b82d5875bf8f4e4f78825e928c58027582bf1357f0`。
- 透過 `pack-engine-artifact.sh --xz` 封裝，明確 `COPYFILE_DISABLE=1`，使用獨立 test config／engineId／輸出目錄。
- 完整媒體 profile；22 個 GStreamer 插件及 scanner。未加入 Apple GPTK 或遊戲。
- MoltenVK 雙版本與 shim 來源為 SHA-256 校驗通過、原始簽章驗證通過的 Cyder012 封存檔；沒有從已安裝 runtime 的變更副本取用。來源檔案 hash 詳見 build-info.json。
- DXMT 0.80 的 11 個來源檔符合既有官方 pin，保持原始位元組與上游 unsigned native，不把它宣稱為新的 Developer ID graphics release。

## 已完成

1. 核心 strip、媒體重定位、cxcompatdb gate、雙版本 MoltenVK gate、minOS gate 通過；封存解壓後 94 個核心 Mach-O 簽章通過。
2. 合併版本先前的 43 項 Shell 回歸與 8 項 Python 單元測試通過；唯一可選 MoltenVK live-source 子檢查跳過，詳見 build-validation.md。
3. 新增測試包 7 項單元測試通過：封存越界、危險連結／hardlink、校驗、正式 runtime 路徑與非法瓶子選擇拒絕。
4. 真實暫存安裝、Verify、重複安裝通過；保留測試存檔、偵測損壞、還原後再驗證，以及外部 prefix／連結拒絕均通過。
5. 安裝後 runtime 的 x86_64／i686 檔案讀寫與 BCrypt 正／反向簽章探測通過。
6. 同一測試瓶子的 builtin OpenGL D3D11 裝置探測回傳 `S_OK`，feature level `0xa100`（10.1）。這不代表所有圖形操作正常：日誌仍有 GL capability／framebuffer 訊息，未做畫面驗收。

## 已知限制：DXMT 探測未通過

`D3D11CreateDevice` 測試程式在進入裝置建立前，回報 `winemetal.dll` 載入失敗，程序狀態 `0xc0000135`。檔案存在且來源 pin 相符；加入套件內 WINEDLLPATH 與 dylib 路徑的對照仍失敗。尚未確認是載入相容性、engine／DXMT ABI 或其他因素，**不得記為 DXMT 初始化成功或 CS2 可玩**。

新瓶子先用 builtin graphics 初始化，再執行所選後端，避免初始化過程先套用 DXMT；這只改善受控啟動流程，沒有解決上述模組載入問題。沒有替換、補簽或修補上游 DXMT／遊戲 DLL 來掩蓋失敗。

此版適合先測 PR #2 的 OpenGL front-buffer、A6 與 PR #3 的視窗幾何行為。CS2、Steam／Paradox、Mods、Exclusive Fullscreen、長時間穩定性及其他遊戲仍依 CHECKLIST.md 實機驗證；遇到同一 DXMT loader 錯誤時，後續城市／模組案例列為「未測」。

## 安裝與還原

解壓測試 ZIP → Install.command → Verify.command → Run Test.command。工具不需 Xcode／Python；需要 macOS 11+，Apple Silicon 另需 Rosetta 2。DXVK 需要 macOS 12+，DXMT 需要 macOS 15+ 且目前有上述已知載入失敗。

預設只使用 `~/.cyder-tests/pr2-pr3-743e5e2/` 的 engine、prefixes 與 logs。直接測試 launcher 不承接 Cyder App 的 CompatDB 與偏好；正式 App／runtime／瓶子不切換。正常結束測試程式後，可直接回原版 Cyder。完整步驟及存檔／瓶子副本注意事項見測試包 README.md。

可重現工具：Python 3.12+ 執行 `scripts/create-test-runtime-kit.py`，以 project engine／graphics artifacts、已簽的 universal zstd、input provenance 及本文件產生測試包；7 項單元測試為 `tests/test-test-runtime-kit.py`，真實安裝交易測試為 `CYDER_TEST_KIT=/path/to/kit bash tests/test-test-runtime-kit-install.sh`。安裝端只用系統工具與包內 decoder。
