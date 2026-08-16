# Cyder Wine Engine 開發與測試流程

本文件是 Cyder Wine Engine 的單一操作入口。目的不是取代各個腳本的說明，
而是固定「從修改、建置、驗證、遊戲實測到打包」的順序，避免下次因為使用到
錯誤的 engine install、舊 wineserver、污染的 build tree 或過量 log 而得到
無法比較的結果。

目前 CX26 產品基準為 `CX26.3.0-W11-Cyder011`。引擎工作一律在
`/Users/jjc/cyder-wine-engine` 進行，不要透過 Cyder.app 來替代引擎測試。

## 1. 先分清楚三種路徑

| 路徑 | 用途 | 規則 |
|---|---|---|
| `build/cx26/sources/wine` | 已套用 Cyder patch 的 source tree | 可重建，不直接當 release |
| `build/cx26/sources/wine/build64` | configure、objects、build products | 先確認 `prefix`，不可猜測 |
| `install/wine-cx26-x86_64` | 本地安裝與 pack 的 engine tree | 測試時明確指定，不能被 `/tmp` 取代 |

遊戲測試的 Wine prefix 與 log 可以放在 `/private/tmp` 做一次性實驗；那只是
runtime state，不是 engine install。正式 acceptance test 則應明確指定要測的
packed runtime 或 repo install，避免腳本自動找到另一份舊 engine。

## 2. 每次工作開始前的 preflight

在 zsh 或其他互動 shell 中，不要直接 `source` Bash 環境檔。所有專案腳本以
`bash` 執行；若要做手動 host incremental build，使用 `bash -lc 'source ...'`
包住整段命令。先固定工作目錄與 engine 來源：

```bash
ENGINE_ROOT=/Users/jjc/cyder-wine-engine
cd "$ENGINE_ROOT"
export OGOM="$ENGINE_ROOT"
export MACOSX_DEPLOYMENT_TARGET=10.15

git status --short
test -f AGENTS.md
test -f docs/incremental-build-and-patches.md
test -f patches/README.md
cat config/engine-version.txt
```

接著確認 build tree 的 install prefix：

```bash
rg '^prefix =' build/cx26/sources/wine/build64/config.status
```

結果必須指向：

```text
.../cyder-wine-engine/install/wine-cx26-x86_64
```

如果指向 `/tmp`、另一個 checkout 或不確定，先停止，不要 `make install`。
刪除 `build64/config.cache` 後用 `build-wine.sh --configure-only` 重新設定，或
直接走完整建置流程。不要使用 `git reset --hard`、`git clean` 清理使用者的
dirty tree；先保留現有修改與實驗 log，再針對明確的 build product 處理。

## 3. 標準建置流程

### 3.1 先 dry-run

每次切換 CX、Vulkan source、patch stack 或 build tree 後，先確認準備步驟與
參數：

```bash
OGOM="$ENGINE_ROOT" MACOSX_DEPLOYMENT_TARGET=10.15 \
  bash scripts/build-wine.sh \
    --cx 26 --maplestory --with-vulkan --vulkan-source crossover \
    --jobs 8 --dry-run
```

dry-run 不代表 source、configure、install 已成功；它只確認腳本選到的路徑、
依賴與命令。真正的建置仍需跑下一步。

### 3.2 完整或乾淨狀態不明時的建置

若是新 patch、configure 選項改變、toolchain/minOS 改變、install tree 來源
不明，或曾經用錯誤 flags 做過 host incremental build，使用完整路徑：

```bash
OGOM="$ENGINE_ROOT" MACOSX_DEPLOYMENT_TARGET=10.15 \
  bash scripts/build-wine.sh \
    --cx 26 --maplestory --with-vulkan --vulkan-source crossover \
    --jobs 8
```

這條命令會重新套用 CX26 patch、configure、編譯並安裝到
`install/wine-cx26-x86_64`，也會同步根目錄的 `version`。本次產品版本以
`config/engine-version.txt` 為準，不要手動把舊版 install tree 當成新版本。

### 3.3 只改一個 host module 時的增量建置

只有在 source、configure、prefix 與 toolchain 都已確認一致時，才做增量建置。
所有 host make 必須保留專案 minOS；最安全的方式仍是使用
`scripts/rebuild-wine-host-unix.sh`。手動命令需在 Bash 環境中顯式帶入
`MACOSX_DEPLOYMENT_TARGET` 與 `CYDER_MACOSX_VERSION_MIN_FLAG`。

若看到任何 `built for macOS 15.0`、`_os_sync_wait_on_address` 或 host `.so`
混入過高 `minos`，立即停止遊戲測試，改跑：

```bash
bash scripts/rebuild-wine-host-unix.sh
```

不要只重建發生錯誤的單一檔案，因為同一個 build tree 可能已有其他 host
products 被錯誤 SDK flags 污染。

## 4. Patch 與 source tree 的可重複性

Patch 只透過 `scripts/build-wine.sh` 套用。新增或修改 patch 時，四個地方要
一起更新：

1. `patches/*.patch`。
2. `scripts/build-wine.sh` 的 CX26 apply list 與穩定 marker。
3. `patches/README.md` 的順序、目的與 marker table。
4. `config/engine-release.json` 及一個最窄的 `tests/test-*.sh`。

套用邏輯必須先檢查穩定 marker，再嘗試 forward/reverse patch。不能只依賴
`patch --forward --dry-run`，因為已套用的 patch 在某些情況會被判定為可繼續，
導致同一個 helper 或 guard 重複寫入。MapleStory no-sched-yield patch 的
marker 應保持精確：

```text
if (is_maplestory_process()) return STATUS_NO_YIELD_PERFORMED;
```

發現 source tree 已經有重複 helper、重複 guard 或 patch 順序不明時，先回到
完整建置流程，不要在 install tree 上直接手改二進位檔。

## 5. 安裝 tree 的一致性驗證

建置完成後，先驗證 install tree，再跑遊戲：

```bash
ENGINE="$ENGINE_ROOT/install/wine-cx26-x86_64"

cat "$ENGINE/version"
test "$(cat "$ENGINE/version")" = "$(head -n 1 config/engine-version.txt)"
test ! -e "$ENGINE/lib/wine/x86_64-unix/libMoltenVK.real.dylib"
test -f "$ENGINE/lib/wine/x86_64-unix/libMoltenVK.dylib"
test -f "$ENGINE/lib/dxvk/x86_64-windows/d3d11.dll"
test -f "$ENGINE/lib/dxvk/i386-windows/d3d11.dll"
test -f "$ENGINE/lib/dxvk2/x86_64-windows/d3d11.dll"
test -f "$ENGINE/lib/dxmt/x86_64-unix/winemetal.so"

otool -l "$ENGINE/bin/wine" | rg minos
otool -l "$ENGINE/bin/wineserver" | rg minos
otool -l "$ENGINE/lib/wine/x86_64-unix/ntdll.so" | rg minos
```

產品 host binaries 與 dylibs 的 `minos` 不得高於 10.15；DXMT 是明確的 macOS
15+ 例外，依 `scripts/pack-minos-scan.py` 的既有規則處理。此階段也要確認
`strings` 能在 ntdll 找到需要的 MapleStory file-cache marker，避免測到舊的
install：

```bash
strings "$ENGINE/lib/wine/x86_64-unix/ntdll.so" \
  | rg 'CYDER_MAPLESTORY_FILE_CACHE|CYDER_IO summary|CYDER_IO host_pread'
```

## 6. 測試順序

先做不需要登入的靜態／回歸測試，再做 direct engine smoke test：

```bash
cd "$ENGINE_ROOT"
bash tests/test-build-wine.sh
bash tests/test-maplestory-patch-stack.sh
bash tests/test-maplestory-file-cache-patch.sh
bash tests/test-maplestory-d3dmetal-launcher.sh
bash tests/test-engine-manifest.sh
bash tests/test-pack-minos-scan.sh
bash tests/run.sh
```

`tests/run.sh` 若在受限環境出現 `server_mach_port`、CoreSimulator 或其他
Mach service 錯誤，這是測試環境失敗，不是引擎通過。記下第一個失敗測試與
錯誤，改在具有 macOS Mach service 權限的實際桌面環境重跑；只有完整測試
真正結束且所有測試通過，才標記為 regression pass。

## 7. Direct MapleStory 測試

引擎行為測試使用 `scripts/run-maplestory-cx26-d3dmetal.sh`，不開 Cyder.app。
它會驗證 CX26 install、GPTK、CompatDB、GStreamer 與 D3DMetal 路徑，並在
每次真正啟動前終止同一個 prefix 的舊 wineserver session。

### 7.1 先做 dry-run 與 no-OTP smoke

所有路徑都顯式指定；`WINE_INSTALL` 應該是 repo install 或已驗證的 packed
runtime，不能讓腳本意外選到舊的 `~/.cyder/runtime`：

```bash
ENGINE="$ENGINE_ROOT/install/wine-cx26-x86_64"
PREFIX="/private/tmp/cyder-cx26-test-prefix"
LOG_ROOT="/private/tmp/cyder-cx26-test-logs"

MAPLESTORY_CX26_WINE_INSTALL="$ENGINE" \
MAPLESTORY_CX26_WINEPREFIX="$PREFIX" \
MAPLESTORY_CX26_LOG_ROOT="$LOG_ROOT" \
MAPLESTORY_CX26_WINEDEBUG='+timestamp,+pid,+winediag' \
  bash scripts/run-maplestory-cx26-d3dmetal.sh \
    --launch-exe '/absolute/path/to/MapleStory.exe' \
    --compatdb '/absolute/path/to/compatdb.cdb' \
    --gptk-root '/absolute/path/to/apple_gptk' \
    --wineprefix "$PREFIX" --no-otp --dry-run

MAPLESTORY_CX26_WINE_INSTALL="$ENGINE" \
MAPLESTORY_CX26_WINEPREFIX="$PREFIX" \
MAPLESTORY_CX26_LOG_ROOT="$LOG_ROOT" \
MAPLESTORY_CX26_WINEDEBUG='+timestamp,+pid,+winediag' \
  bash scripts/run-maplestory-cx26-d3dmetal.sh \
    --launch-exe '/absolute/path/to/MapleStory.exe' \
    --compatdb '/absolute/path/to/compatdb.cdb' \
    --gptk-root '/absolute/path/to/apple_gptk' \
    --wineprefix "$PREFIX" --no-otp
```

先確認能到登入畫面、語系正確、沒有立即退出，再進行需要 OTP 的 acceptance
test。OTP 只在當次命令列輸入，不寫入文件、shell history、issue 或 log；
launcher 的 summary 會把 OTP 遮罩。

### 7.2 OTP acceptance 與首次資源測試

OTP 測試使用同一套已驗證的 `ENGINE`、prefix、GPTK、CompatDB 與工作目錄，
只替換最後的登入參數：

```bash
MAPLESTORY_CX26_WINE_INSTALL="$ENGINE" \
MAPLESTORY_CX26_WINEPREFIX="$PREFIX" \
MAPLESTORY_CX26_LOG_ROOT="$LOG_ROOT" \
MAPLESTORY_CX26_WINEDEBUG='+timestamp,+pid,+winediag' \
  bash scripts/run-maplestory-cx26-d3dmetal.sh \
    --launch-exe '/absolute/path/to/MapleStory.exe' \
    --compatdb '/absolute/path/to/compatdb.cdb' \
    --gptk-root '/absolute/path/to/apple_gptk' \
    --wineprefix "$PREFIX" -- \
    tw.login.maplestory.beanfun.com 8484 BeanFun T9_SERVICE_ACCOUNT_ID OTP
```

每次只改一個變因，建議順序如下：

1. 新 prefix：登入前、選角、進入有怪物地圖、第一次攻擊。
2. 同一 prefix 重複啟動：確認 warm cache 與 cold cache 的差異。
3. 啟用 `CYDER_MAPLESTORY_FILE_CACHE=1`：重新建立新 prefix 再做同樣流程。
4. 需要分析 WZ 讀取時，必須同時啟用 `CYDER_MAPLESTORY_IO_TRACE=1` 與
   `CYDER_MAPLESTORY_IO_PROFILE=1`，並在 `WINEDEBUG` 加入 `+cyderio`；只開
   `IO_PROFILE` 不會建立 `.wz` 追蹤項目，也不會輸出 `CYDER_IO summary`。
   只有要定位 offset 時才另外啟用
   `CYDER_MAPLESTORY_IO_PROFILE_FULL_OFFSETS=1`；若要量 host read 時間，才
   另開 `CYDER_MAPLESTORY_IO_PROFILE_TIMING=1`。若要把最近的 WZ
   `NtReadFile`／host read 與事件時間對齊，改用 `CYDER_MAPLESTORY_IO_RING=1`；
   ring 只在 Unix process termination 階段輸出，因此測試完成後仍應從遊戲內
   正常關閉，避免強制中斷造成事件遺失。若要只記錄第一次攻擊，另外指定
   `CYDER_MAPLESTORY_IO_RING_ARM_FILE` 為一個尚不存在的暫存檔；進入地圖並
   確認畫面穩定後，再建立該檔案，下一個一般檔案讀取會清空 ring 並開始記錄，log
   會留下 `CYDER_IO ring armed` 標記。arm 後會同時包含 WZ、圖形與其他一般檔案
   讀取。若預期讀取量很大，改用 `CYDER_MAPLESTORY_IO_SUMMARY=1`；它不保留
   每一筆 event，而是在記憶體依路徑彙總 count、bytes、host duration、讀取長度
   分布、offset 範圍與前後時間，結束時只輸出少量 `CYDER_IO aggregate`。未指定
   arm file 時維持啟動即記錄的舊行為。若要對齊第一次攻擊的讀取尖峰，再加入
   `CYDER_MAPLESTORY_IO_TIMELINE=1`；它會輸出 100ms 時間桶，但仍不保留逐筆
   event。
   若要直接驗證自製 WZ read-ahead 是否真的命中，加入
   `CYDER_MAPLESTORY_IO_CACHE_STATS=1`，且必須同時開啟
   `CYDER_MAPLESTORY_IO_SUMMARY=1`。結束時會輸出每個 WZ 路徑的
   `CYDER_IO cache`，包含 hits、fills、fill bytes、fill duration、fill failures
   、bypass 與 `needs_close` skip；另外會輸出 compact decision summary，區分
   cache attempt、`needs_close`、未註冊 handle 與沒有可用 offset 的 skip。若使用 arm file，這些計數會在 arm 時清零，但已填入的 cache
   window 會保留，因此不會因為統計而重新製造一次 cold-cache 讀取。
   若要測試 mmap-backed window fill，另加
   `CYDER_MAPLESTORY_FILE_CACHE_MMAP=1`；此模式只供實驗，預設關閉。
   若要驗證 WZ 是否走 `NtMapViewOfSection`／host `mmap`，另開
   `CYDER_MAPLESTORY_IO_SECTION_MAP=1`。它只在程序結束時輸出 section mapping
   的總量與 `.wz` 路徑統計，不會改變讀取路徑，也不會逐筆寫 log。
5. 每次記錄：prefix 是否全新、引擎版本、graphics backend、到達畫面、第一個
   卡頓事件、log 路徑與是否正常關閉。

不要同時切換 engine、graphics backend、file cache、HUD、WINEDEBUG 與 prefix，
否則無法知道改善來自哪一個變因。測試完先關閉遊戲，再壓縮封存 log：

```bash
find "$LOG_ROOT" -type f -name '*.log' -size +50M -print
find "$LOG_ROOT" -type f -name '*.log' -size +50M -exec gzip -9 -- {} +
```

只保留能回答問題的 summary/profile；`+process`、`+loaddll`、完整 offset
trace 不是預設值，因為它們會放大 log I/O 並干擾卡頓實驗。若必須做完整 trace，
使用獨立 log root，並在每一輪結束後確認磁碟空間。

## 8. Pack 與交接

只有 install tree 驗證與測試通過後才打包。測試版使用未簽名或測試身份；正式
發佈才使用 Developer ID：

```bash
CYDER_ENGINE_VERSION_LABEL="$(head -n 1 config/engine-version.txt)" \
SIGN_IDENTITY='-' \
  bash scripts/pack-engine-artifact.sh --xz --force
```

pack 會檢查 DXVK、minOS、codesign 與 archive round-trip。不要把 raw install
tree 直接複製到 `~/.cyder/runtime` 後稱為 release；若要交給 Cyder，交付
`dist/artifacts/` 的 archive、sha256 與 manifest，並依
`integration-with-cyder.md` 匯入。

## 9. 快速故障判斷

| 現象 | 優先檢查 |
|---|---|
| `version` 不是 Cyder011 | `ENGINE` 指到舊 install；重新指定 `WINE_INSTALL` |
| `prefix` 指到 `/tmp` | build64 configure state 錯；重新 configure 或完整建置 |
| patch 重複 helper／guard | marker 檢查不在 forward patch 前；恢復乾淨 source 後重建 |
| `built for macOS 15.0` | host incremental 遺漏 minOS；跑 `rebuild-wine-host-unix.sh` |
| `server_mach_port` | 舊 wineserver 或環境無 Mach service；用同一 prefix 的 launcher 清 session，並在桌面環境重跑測試 |
| 遊戲顯示 DXVK 但實際走 WineD3D | install／packed runtime 沒有 DXVK payload 或 DLL override 不完整 |
| D3DMetal 找不到 | GPTK、`libd3dshared.dylib`、CompatDB 或 `WINE_INSTALL` 不一致 |
| 第一次操作卡頓但 log 很大 | 降低 `WINEDEBUG`，關閉 full offset trace，改用 profile summary |
| 磁碟快速被吃滿 | 停止 trace、關閉遊戲、壓縮或移除可重建的 raw log；保留 summary 與必要 profile |

## 10. 完成條件

一次引擎開發／測試工作只有在以下項目都完成時才算可交接：

- patch、README、manifest 與窄測試已同步更新。
- build64 prefix 正確，install `version` 與 config 版本一致。
- host minOS、MoltenVK 單一 dylib、DXVK/DXVK2/DXMT payload 驗證通過。
- `bash tests/run.sh` 通過；若是環境錯誤，已在報告中明確分開，不冒充 pass。
- direct engine dry-run、no-OTP smoke 與需要的 OTP acceptance 已完成。
- cold/warm 或 file-cache A/B 的變因、prefix、引擎版本、log 路徑都有記錄。
- 若要交付 runtime，已使用 pack script 產生 archive、sha256、manifest；沒有直接交付半成品 install tree。

相關細節請參考：

- [`incremental-build-and-patches.md`](incremental-build-and-patches.md)
- [`maplestory-cx26-migration-and-test-plan.zh-TW.md`](maplestory-cx26-migration-and-test-plan.zh-TW.md)
- [`patches/README.md`](../patches/README.md)
- [`integration-with-cyder.md`](integration-with-cyder.md)
