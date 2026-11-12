# Apple Silicon 原生 Wine 建置實驗（2026-09-21）

## 結果

**CX26.3 / Wine 11.0 的 ARM64 基礎引擎已完成編譯、獨立安裝與本機 ad-hoc 簽章；尚未成為可執行 Windows 程式的引擎。**

| 驗證 | 實測結果 |
|---|---|
| configure / 完整 make / make install | 成功，make 輸出 `Wine build complete.` |
| 安裝樹 39 個 Mach-O 檔案 | 全部為單一 `arm64`，minOS 全部 `11.0` |
| 安裝樹 Windows PE | 759 個 AArch64 PE32+ 檔案 |
| 所有 Mach-O `codesign --verify --strict` | 通過（ad-hoc；非公證或 Developer ID 發佈） |
| `arch -arm64 …/bin/wine --version` | exit 0，`wine-11.0` |
| `arch -arm64 …/bin/wineserver --version` | exit 0，`Wine 11.0` |
| `wine cmd /c echo CYDER_ARM64_SMOKE_OK` | 兩次皆 SIGKILL（Python returncode -9），無成功 sentinel |
| FEX 上游 Wine Unix 介面 | configure 成功；編譯因 `sys/prctl.h` 不存在而失敗 |

這次只建置 AArch64 PE，未建 ARM64EC/i386/x86_64 PE，未整合 FEX、DXMT、DXVK 或 D3DMetal。沒有遊戲/FPS 結果。原生主程式可印版本不等於 Windows 程式可跑。

## 本機與來源

- 工作倉庫：`/Users/jjc/cyder-wine-engine`。
- macOS **15.7.7**（24G720），ARM64；Xcode SDK **15.0**，Apple clang **16.0.0**。
- Windows 交叉編譯器：既有 `build/llvm-mingw-20260616-ucrt-macos-universal`。
- 使用現有官方 `tools/archives/crossover-sources-26.3.0.tar.gz`，重新解出乾淨 Wine 原始碼；官方下載 URL 本次 HEAD 回應 200、149054023 bytes。
- 封存檔 SHA256：`ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872`。
- 另從 FEX 官方 GitHub clone 到 `build/arm64-experimental-cx26/FEX-upstream`，固定本次 HEAD `48d71752e2a363d5535181f803b0b0e9666c1825`。未下載 submodule，Wine UnixLib 是獨立 CMake project，不需要它們即可重現上述編譯失敗。

[CrossOver 官方來源頁](https://www.codeweavers.com/crossover/source)目前列出 26.3.0；[官方封存檔](https://media.codeweavers.com/pub/crossover/source/crossover-sources-26.3.0.tar.gz)。本次沒有找到可公開下載的 **ARM64 Preview 對應 Wine + macOS FEX 完整補丁集**；不能將 CX26.3 來源稱為 Preview 來源。公開目錄列表回應 403 不代表個別封存檔不能下載，也不證明 Preview 來源不存在。

## CrossOver 原生路線的現況

CodeWeavers 的 [2026-07-31 公告](https://www.codeweavers.com/blog/mjohnson/2026/7/31/crossover-preview-the-right-to-bear-arm64-on-mac)確認 Mac ARM64 Preview 已推出，使用客製 FEX；原生部分要求 macOS 26.5+，舊系統使用其中的 Intel Wine。當次 Preview 有 ARM64 DXMT，尚無 D3DMetal，須建立新 bottle。這台 macOS 15.7.7 不符合其原生模式要求。

Wine 開發者 Brendan Shanks 的 [2026-08-07 技術說明](https://list.winehq.org/hyperkitty/list/wine-devel@list.winehq.org/message/CKG5CEN2BE5VRXZ7O7NX4YUSBH3247WH/)列出新版系統的必要能力：x18 ABI 切換、4KB process pages、低位址 PAGEZERO 配置、每執行緒 TSO，以及受限制的 cross-architecture entitlement/provisioning。[9 月 9 日回覆](https://list.winehq.org/hyperkitty/list/wine-devel%40list.winehq.org/2026/9/?view=messages)仍表示上游 MR 與文件在準備中。

ARM64 Wine 可讓 Wine 本身及相容函式庫原生執行；x86 遊戲的機器碼仍需要 FEX 等轉譯器。效能變化取決於遊戲、轉譯器、圖形後端與同步行為，目前沒有本專案的效能改善證據。

## 本次編譯修正

採獨立 source/build/install，明確使用 `arch -arm64`、ARM64 Homebrew 與 minOS 11.0。這是使用者要求的 ARM64 實驗，不是既有 x86_64 / minOS 10.15 產品管線的變更。

1. 補齊 native pkg-config 的 Homebrew 系統 `zlib.pc` 搜尋路徑，解決 FreeType/GnuTLS 偵測失敗。沒有關掉字型支援來掩蓋依賴問題。
2. `tools/arm64-lab/cx26-arm64-d3dmetal-build-guards.patch`：CX26 的 `WineMetalLayer` 宣告及 `macdrv_client_surface_presented` 實作只供 x86_64；在 ARM64 使用普通 `CAMetalLayer` 並略過該 D3DMetal event handler。這是編譯修正，不宣稱 ARM64 D3DMetal 支援。
3. 套用既有 `patches/w1-win32u-vulkan-soname.patch`：CX26 在 `--without-vulkan` 仍會編譯引用 `SONAME_LIBVULKAN` 的程式碼。fallback 名称只修正編譯，未附帶 MoltenVK。

這些問題與 ogom 早期設計紀錄的 W1/W2/W3 相符。此次未套入遊戲補丁、修改正式 patch list 或更新 release manifest。`build.sh prepare` 已驗證可重跑，不會重複套用補丁。

## 啟動失敗證據與判讀

實驗使用全新 `/private/tmp/cyder-arm64-smoke-*` prefix。測試在可存取 macOS Mach service 的執行環境進行，非將 sandbox 失敗冒充 runtime 結果。

`logs/smoke-kernel.log` 記錄內部 `lib/wine/aarch64-unix/wine` 的 AMFI ad-hoc 訊息，以及：

```text
ASP: Security policy would not allow process: 44286,
/Users/jjc/cyder-wine-engine/install/wine-cx26-arm64-experimental/lib/wine/aarch64-unix/wine
```

簽章靜態驗證通過，但內部 loader 啟動仍被拒絕。該 loader 的 `__PAGEZERO` 只有 `0x1000`，SDK 15.0，與開發者所述舊 macOS ARM64 位址限制不相容；**這是值得接續驗證的原因，不把一般性 AMFI 訊息當成唯一根因已證實**。目前尚未到達 `cmd` Windows 程式碼，無法測 x18、SEH、FEX 或圖形正確性。

FEX 使用官方來源的 [UnixLib](https://github.com/FEX-Emu/FEX/tree/48d71752e2a363d5535181f803b0b0e9666c1825/Source/Windows/UnixLib)。該介面直接使用 Linux `prctl` 並連結 `rt`，本次第一個錯誤是缺少 `sys/prctl.h`。不能只移除 include 就當成完成 macOS 移植；TSO、unaligned atomics 及記憶體語意仍需實作。這也不表示 Windows PE FEX 核心永遠不能用於 macOS Wine。

## 重跑與路徑

```bash
cd /Users/jjc/cyder-wine-engine
# 全部：驗證來源 hash → 解壓/套用實驗補丁 → configure → make → install
bash tools/arm64-lab/build.sh all

# 或分階段／增量
bash tools/arm64-lab/build.sh prepare
bash tools/arm64-lab/build.sh configure
bash tools/arm64-lab/build.sh build
bash tools/arm64-lab/build.sh install

# 限實驗樹的本機測試簽章
OGOM=/Users/jjc/cyder-wine-engine MACOSX_DEPLOYMENT_TARGET=11.0 \
WINE_INSTALL=/Users/jjc/cyder-wine-engine/install/wine-cx26-arm64-experimental \
SIGN_IDENTITY=- bash scripts/sign-wine.sh \
  --root /Users/jjc/cyder-wine-engine/install/wine-cx26-arm64-experimental

# 每次建立新 prefix；25 秒逾時；失敗會 exit 1
python3 tools/arm64-lab/smoke.py
```

FEX 失敗可獨立重現：

```bash
cd /Users/jjc/cyder-wine-engine
LAB="$PWD/build/arm64-experimental-cx26"
/opt/homebrew/bin/cmake -S "$LAB/FEX-upstream/Source/Windows/UnixLib" \
  -B "$LAB/fex-unixlib-build" \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0
/opt/homebrew/bin/cmake --build "$LAB/fex-unixlib-build" -j2
```

- 產物：`install/wine-cx26-arm64-experimental`（約 1.1GB）。
- 來源、objects 與 FEX：`build/arm64-experimental-cx26`（約 2.2GB）。
- 證據：上述實驗目錄的 `logs/`，包括 `source.sha256`、`configure.log`、`build-stock-failed.log`、`build-missing-vulkan-soname.log`、成功的 `build.log`、`install.log`、`sign.log`、`artifacts.json`、`smoke.json`、`smoke-kernel.log`、`fex-unixlib-build.log`。
- 可重跑工具：`tools/arm64-lab/build.sh`、`tools/arm64-lab/smoke.py` 與該目錄的 patch。
- 檢查：shell/Python 語法、patch 重跑、實際完整編譯、39 個 Mach-O 架構/minOS/簽章、兩輪 smoke。沒有執行正式 x86 遊戲回歸 suite，也沒有宣稱其通過。

## 下一步的具體門檻

1. 在 macOS 26.5+ 與相符新 SDK 上取得/套入 macOS ARM64 Wine runtime 改動及 FEX 移植，確認所需 capability/provisioning 可用。
2. 先通過 ARM64 `cmd`、執行緒、例外與記憶體映射測試，再加入 ARM64EC + FEX 的 x86/x64 小程式。
3. 最後整合 ARM64 DXMT 並測目標遊戲；在登入/進世界等相容性通過後才做同場景 A/B 效能比較。

現有 Cyder012 x86_64 build/install、Cyder runtime、遊戲 bottle 與 release pin 沒有被這次實驗替換；未升級系統、未變更系統安全設定，未 commit 或發佈。
