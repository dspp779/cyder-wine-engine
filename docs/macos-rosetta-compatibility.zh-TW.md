# macOS 與 Rosetta 建置相容性

Cyder engine 的 macOS host 程式為 x86_64：Intel Mac 原生執行，Apple Silicon
需要可用的 Rosetta。建置主機的 macOS、compiler 輸出架構與產物的最低系統版本
是三個獨立條件，升級作業系統或安裝新版 Xcode 後都要分別檢查。
專案相對路徑的指令均從 `cyder-wine-engine` checkout 根目錄執行。

以下 Apple 支援資訊核對於 2026-10-20；本機驗證環境為 Apple M4、macOS
27.0.1（26A434）、Apple clang 21。其他系統版本的列項是執行前提，不能當作
本專案已在每個版本通過建置或遊戲驗收的保證。

## 不同主機與 macOS 版本

| 主機與系統 | x86_64 執行方式 | 建置與驗證條件 |
|---|---|---|
| Intel Mac，硬體支援的 macOS 10.15 至 26 | 原生執行；不安裝 Rosetta 2 | 選擇支援該主機的 Xcode；10.15 是一般 host 產物的宣告下限，不代表最新工具鏈可在 10.15 建置 |
| Apple Silicon，硬體支援的 macOS 11 至 15、26 | 透過 Rosetta | 新機與系統升級後都先做 x86_64 執行探測；不要依賴先前的安裝狀態 |
| Apple Silicon，macOS 27 | 仍可安裝、使用 Rosetta | 本機升級後曾缺少 Rosetta，重裝後恢復；不能推論每台升級機器都會移除它 |
| Apple Silicon，macOS 28 起的規劃 | Apple 公告僅保留特定舊遊戲所需的有限功能 | 不能據此宣稱任意 Wine engine、clang 或 x86_64 Homebrew 可用；此專案尚未完成該系統的相容性驗證 |

[Apple Rosetta 支援說明](https://support.apple.com/en-us/102527)確認一般 Rosetta
可用於 macOS 27 及以前，並說明 macOS 28 的功能限制。macOS 27 的
[官方硬體清單](https://support.apple.com/en-ca/127255)以 Apple Silicon 為範圍；
Intel Mac 不應套用 Apple Silicon 的系統升級步驟。

## Xcode 主機條件與產物 minOS

安裝完整 Xcode，並確認 `xcode-select` 選到正確的 Developer 目錄；MoltenVK
建置不能只靠 Command Line Tools。依
[Apple Xcode 系統需求](https://developer.apple.com/xcode/system-requirements/)
選擇版本，並記錄實際 compiler 與 SDK：

```bash
sw_vers
xcode-select -p
xcodebuild -version
/usr/bin/clang --version
xcrun --sdk macosx --show-sdk-path
```

例如 Xcode 16.4 的官方主機範圍是 macOS 15.3 至 26.1.x；Xcode 26.6 的範圍
是 macOS 26.2 至 26.x。macOS 27 不應沿用這兩列作為 Xcode 相容性依據。
新版 Xcode 的官方 deployment target 範圍，與直接呼叫 clang 所產生的 Mach-O
`minos` 也需分開看：本機 clang 21 可用明確旗標產生 x86_64、minOS 10.15 的
小型程式與 cxcompatdb，但這不等於完整 engine 已在舊版 macOS 通過執行驗收。

### Xcode 27 的 legacy MoltenVK 限制

本機隔離建置已確認：Xcode 27 會直接拒絕 deployment target 10.15，回報
允許範圍為 12.0 至 27.0.x。因此 legacy MoltenVK 1.2.10 的 Xcode 專案及
external dependencies 不能只靠設定 `MACOSX_DEPLOYMENT_TARGET=10.15` 就在
此主機從零建出。新版 MoltenVK 1.4.2 real 可依專案例外以 12.0 建置；
Wine／media 直接使用 clang 的 10.15 成功案例不涵蓋 legacy 的 Xcode 專案。

需要完整 dual-variant 封裝時，legacy real 應由可建 10.15 的相容工具鏈產生，
或使用來源、版本與 patch 組合相符的既有已驗證 artifact。使用既有輸入須核對
archive checksum、codesign、x86_64 架構與 minOS 10.15，並在建置紀錄標示
來源與 checksum，不能宣稱該元件在本機重新建出。不要提高全域 minOS、改寫
Mach-O load command，或把較高 minOS 的 dylib 改名來繞過 pack gate。

一般 Wine host binaries 與 cxcompatdb 維持 `MACOSX_DEPLOYMENT_TARGET=10.15`；
DXMT 與特定 MoltenVK real 的例外依 `scripts/pack-minos-scan.py`，不向上改動
全域目標。Apple Silicon 本身從 macOS 11 起，10.15 是產物相容性宣告，並非
Apple Silicon 可安裝的系統版本。

## 先確認 Rosetta 是否能執行

在 Apple Silicon 執行以下探測；第一個指令成功但沒有輸出是正常的：

```bash
arch -x86_64 /usr/bin/true
arch -x86_64 /usr/bin/uname -m
```

預期第一個指令退出碼為 0，第二個輸出 `x86_64`。若連系統的 `true` 都出現
`Bad CPU type in executable`，先檢查 Rosetta，還沒有進入 Wine 或專案程式。
可用下列資料輔助診斷，但安裝收據或 daemon 狀態不能取代實際執行探測：

```bash
pkgutil --pkg-info com.apple.pkg.RosettaUpdateAuto
launchctl print system/com.apple.oahd
```

`oahd` 是按需啟動的系統服務，閒置時未執行本身不表示損壞。若系統探測成功，
但只有某個工具失敗，檢查該檔的 `file`／`lipo -archs`、檔案是否完整，以及
實際執行路徑；不要因此刪除 Homebrew prefix 或重建全部 Wine。

### 安裝或補裝 Rosetta

Apple Silicon、macOS 27 及以前可依 Apple 說明連線安裝：

```bash
/usr/sbin/softwareupdate --install-rosetta
```

依提示閱讀、接受授權；若系統要求管理員權限，於本機完成驗證。自動化環境只在
已閱讀並同意授權後使用 `--agree-to-license`。完成後重跑上面的 `true` 與
`uname -m`，再檢查專案工具：

```bash
arch -x86_64 /usr/bin/clang --version
"$PWD/.brew-x86/bin/python3" --version
```

Python 只在專案 Homebrew 已安裝它時檢查；尚未安裝依賴時缺少 Python 不是
Rosetta 失效。若安裝失敗，保留安裝訊息並排查系統更新服務、網路與權限；
不要手動刪除系統 Rosetta 元件，也不要把 macOS 28 的有限功能當作一般安裝路徑。

## 明確指定 compiler 輸出架構

`arch -x86_64` 選擇的是執行程式的 slice，不保證 compiler 的預設 target。
本機 macOS 27 的 Apple clang 即使由 Rosetta 啟動，仍可能輸出 arm64；此次
cxcompatdb 曾因此得到 arm64、minOS 11.0 的產物。

`build-wine.sh` 的預設 `CC`／`OBJC` 都是 `/usr/bin/clang -arch x86_64`，並在
configure、make、install 使用相同的 deployment target。完整路徑可避開 PATH
前方 llvm-mingw 的 Windows cross compiler。自訂 `CC`／`OBJC` 會保留，呼叫端
須確保它們也產生 macOS x86_64 產物；不要混入 `-arch arm64` 或較高的 minOS。
獨立的 `build-cyder-cxcompatdb.sh` 同樣明確指定 `-arch x86_64`。

media stack 也透過持久化的 Meson native file 固定 C、C++、Objective-C 與
Objective-C++ compiler，並保留自訂 `CC`／`CXX`／`OBJC`／`OBJCXX`。舊的或
工具鏈設定不同的 Meson cache 會停止建置並保留資料；改用新的 `OGOM_BUILD_DIR`
再建置。安裝前會檢查 build 產物為 thin x86_64，安裝後再檢查架構與 minOS。

Host 依賴使用專案的 `.brew-x86`，不混用 `/opt/homebrew` 的 arm64 libraries。
切換 prefix 時也要一起核對 `HOMEBREW_REPOSITORY` 與 `HOMEBREW_CELLAR`，避免
shell profile 殘留 arm64 路徑。完整性驗證會要求 `bin/brew` 屬於指定 repository，
且 Git 的實際根目錄與有效 HEAD 都正確；只有 prefix 目錄或 `.git` 存在不夠。
驗證失敗時保留舊 prefix，先檢查資料，或選擇一致的新 prefix／repository／Cellar
重新 bootstrap。Intel 的分離安裝可使用指向該 repository 的 brew symlink。

更換 compiler、SDK 或 flags 後，保留需要的既有資料，再處理 `build64/config.cache`
並重新 configure；不要直接對舊 Makefile 執行 make 後宣稱已切換工具鏈。

建置後同時查架構與 minOS，不能只看 compiler 啟動成功：

```bash
ENGINE="$PWD/install/wine-cx26-x86_64"
lipo -archs "$ENGINE/bin/wineserver"
lipo -archs "$ENGINE/lib/wine/x86_64-unix/cxcompatdb.so"
otool -l "$ENGINE/lib/wine/x86_64-unix/cxcompatdb.so" \
  | rg -A5 'LC_BUILD_VERSION|LC_VERSION_MIN_MACOSX'
```

這兩個 host 產物應為 x86_64；cxcompatdb 的 minOS 應為 10.15。這些檢查
不涵蓋 graphics payload 的額外系統需求，也不取代 pack gate 與舊系統實測。

## 分辨 Rosetta 故障與測試權限

| 現象 | 判斷與下一步 |
|---|---|
| 系統 `arch -x86_64 /usr/bin/true` 就失敗 | 先修復 Rosetta，再測專案工具 |
| 系統探測成功，plugin 卻是 arm64 或 minOS 11.0 | 檢查 compiler 的 `-arch x86_64` 與 10.15 flags，重新建置受影響產物 |
| Wine 已啟動，出現 `Can't check in server_mach_port` | 屬於 Mach service／session 或沙箱問題；保留原測試設定，在具有 Mach 存取權的桌面環境重跑 |
| x86_64 連結器拒絕 arm64 library | 檢查依賴與 search paths；不要移除架構旗標來繞過錯誤 |
| CX26 完整 make 出現未定義的 `SONAME_LIBVULKAN` | 無 Vulkan configure 成功仍可能在 `win32u/vulkan.c` 編譯失敗；此來源組合可明確使用既有 `--without-vulkan --vulkan-soname-fallback` 選項，或完成 graphics 輸入後驗證 `--with-vulkan` 路徑 |

`--vulkan-soname-fallback` 是明確選用的建置修補，提供缺少 SONAME 巨集時的
預設 library 名稱；它不會安裝 Vulkan runtime，也不表示無 Vulkan 的 build
能執行 Vulkan 遊戲。完整 make 與 install 都要驗證，不能以 configure 成功
代替。此選項不改變 repository 的預設 patch policy。

2026-10-20 本機修復 Rosetta 並補上 cxcompatdb 架構旗標後，原先 7 項失敗
測試均通過；完整 `bash tests/run.sh` 退出碼為 0。Wine
frame-walk 實際執行於可存取 Mach service 的環境。MoltenVK live round-trip
子測試因缺少 patched `MVKSync.mm` 而跳過，其 patch 內容檢查通過；此結果
不代表完整 engine 重建、所有 graphics 路徑或遊戲驗收已完成。

建置步驟見[從零建置指南](build-engine-from-scratch.zh-TW.md)；增量建置與測試
見[開發測試流程](engine-development-test-workflow.zh-TW.md)。
