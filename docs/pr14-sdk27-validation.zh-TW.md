# PR #14：SDK 27.2 本機驗證

日期：2026-11-13（Asia/Taipei）。
PR：https://github.com/dspp779/cyder-wine-engine/pull/14 。
基準 commit：`7319b5c783c86885add0a8cbf1d9f741a3cb6590`。
分支：`claude/minos-weak-imports`，另有本輪未提交修正。
工作目錄：`/Users/jjc/ogom/cyder-wine-engine`。
環境：Apple M4、macOS 27.2、Apple SDK 27.2；產品最低 macOS 10.15。

## 已完成

- SDK 實際探測 Wine 與 GLib 來源皆辨識 `pipe2` 需 macOS 27.0。
- Wine dry-run 的 configure 含 `ac_cv_func_pipe2=no`。
- 修正測試固定假設：SDK 27 有 `pipe2`，較舊 SDK 未宣告它；以明列函式的實際探測核對 Autoconf / Meson 名稱擷取。
- 修正探測器：無效編譯器參數、無診斷的異常退出、非預期編譯錯誤皆拒絕放行；未宣告函式仍交由建置系統判定。
- 修正弱匯入掃描：不存在的目錄或以普通檔案代替目錄皆失敗。
- 完整 `bash tests/run.sh` 結束碼 0：60 個 Shell 入口；5 組 Python 測試共 45 案（44 通過、1 選用案例跳過）。新增窄測試另已通過。這輪完整回歸在 Wine 重建前執行，不能代表重建後引擎的 runtime 驗收。
- full-video GLib / GStreamer 實際重建安裝成功，80 個 Mach-O 為 thin x86_64；minOS 與弱匯入掃描通過。GLib `config.h` 不再定義 `HAVE_PIPE2`。
- 專案 Homebrew 僅新增信任 `ogom/local/libidn2`；libidn2 從該配方實際重建成功，receipt 為 `ogom/local`；`nm -m` 顯示本地 `_rpl_strchrnul`，不再匯入系統 `_strchrnul`。

## Wine 建置與封裝

- 第一輪完整 configure / make / install 已完成；最後的 bundler 因原有 graphics prefix 把 minOS 12.0 real 當作未版本化 shim 而失敗。這是建置指南已記錄的組裝順序問題，並非本輪放寬 gate。
- 依 `docs/build-engine-from-scratch.zh-TW.md` 組裝獨立的 `install/graphics-cx26-pr14-dual-x86_64`，包含兩個 versioned reals 與 minOS 10.15 wait-poll shim，再以 `GRAPHICS_INSTALL` 指向它重跑完整建置腳本，結束碼 0。動態依賴可重定位與 minOS gate 均通過。
- 測試標籤 `CX26.3.0-W11-Cyder013-pr14-validation`，由 `scripts/pack-engine-artifact.sh --zstd` 建立，使用 `SIGN_IDENTITY=-`；這是本機 ad-hoc 測試包，沒有正式 Developer ID 簽署、公證或發布。
- 輸出為 `dist/pr14-validation-20261113/`；engine archive 約 60 MiB，另有獨立 DXVK / DXMT 測試包。
- 封裝前 minOS、弱匯入、MoltenVK dual layout、原生 DirectDraw 能力檢查均通過；封裝腳本解壓後驗證 95 個 Mach-O 簽章。
- 另行解壓後確認 95 個 Mach-O 皆為 thin x86_64；ntdll / GLib / GIO 均無 `_pipe2` 匯入，libidn2 無 `_strchrnul` 匯入；再次執行弱匯入掃描通過。
- 封裝沒有 `ntdll.so.pre-qdo`、Apple GPTK 或獨立 graphics 樹。舊 ntdll 備份保留在 `build/pr14-validation-20261113/preserved-install-backups/`，附原始 SHA256。
- Archive SHA256：`6cbb3bba5421a6f8745d7e9d03040444c2722f34ad269adb08f8eb9286dafcd0`，已重新計算並核對 sidecar。

## 解壓後 runtime 驗證

- 使用既有 `tests/test-runtime-smoke.sh`，將 runtime 明確指向解壓內容。x86_64 / i686 的 Win32 檔案操作、BCrypt P-256 正確簽章接受及竄改簽章拒絕均通過。測試僅使用自建 prefix，結束後清理對應 wineserver。
- 另一個全新隔離 prefix 依序執行 `wine wineboot -i`、`wine wineboot -u`、再一次 `wine wineboot -u`，三次退出碼皆 0。這證明目前 macOS 27.2 上的初始化與既有 prefix 更新路徑可執行，不代表已重現或驗證 macOS 15.8 的原始 bottle migration。
- 解壓內容的媒體 factory 探測：明確設定自帶 plugin / scanner 路徑時，`videoconvert`、`h264parse`、`vtdec`、`vtdec_hw`、`decodebin`、`qtdemux` 全部 found。未設定路徑的 fresh registry 全部 missing，故使用時仍需既有 media environment 設定；`avdec_h264` 缺少符合此 profile 未啟用 gst-libav 的設計。這不是實際影片解碼或遊戲播放測試。
- 初次媒體探測因受限執行環境無桌面服務而停住；已核對並停止本輪精確程序，在桌面服務可用環境重跑成功。未把環境失敗記為通過。

## 證據

`build/pr14-validation-20261113/` 保存 dry-run、修改前掃描、媒體 / libidn2 / Wine 建置、完整回歸、封裝與解壓後 runtime 日誌；`artifact-checks.log` 保存產物核對，`packaged-media-probe/results.json` 保存媒體逐項結果，`local-changes.diff` 保存本輪四個程式 / 測試檔案的修改。

修改前掃描會拒絕舊 ntdll / GLib 的 `_pipe2`、舊 libidn2 的 `_strchrnul`，以及殘留的 `ntdll.so.pre-qdo`。直接掃描 install 也會列出 DXMT 的弱匯入；正式 engine pack 原有 staging 會排除 `lib/dxmt`，因此不能把這些原始 install 診斷全部當作 engine archive 的阻塞。

## 尚待驗證

- 實際影片解碼與 HTTPS / TLS 端到端流程。
- macOS 15.8 及 10.15 / 11 的實機 wineboot 更新。
- 實際遊戲、Cyder.app bottle 更新、Developer ID 正式簽署與發布。

本輪不變更正式 runtime、不發布版本；正式引擎標籤仍待決定。原始安裝樹不可視為發行包。
