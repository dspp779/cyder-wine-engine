# GameSir Wine → CX26 可移植清單

對照基準（2026-08-20）：

- 來源：`gamesir-labs/wine`（Proton Wine 10.0 + GameSir 102 commit），本機 clone 於 CyderBits `.research/gamesir-wine`
- 目標：`cyder-wine-engine` 的 CX26.3 / Wine 11.0（`build/cx26/sources/wine`）
- 原則：只列**無遊戲 exe 名稱**、且 CX26 **確認缺席**的平台修補。硬編 HACK 與 `WINE_PROCESS_ENV_*` 不進 engine，改走 CompatDB / 啟動器。

移植時必須對 CX26 檔案重做 hunk，**禁止**把 Proton 10 patch 直接 `git am`。

---

## 不要移植（已在 CX26，或政策衝突）

| GameSir commit | 原因 |
|----------------|------|
| D3DMetal hooks、mach_msg2、CET/XGETBV、W\|X、PEB/GS、`is_apple_silicon`、MoltenVK wined3d hack、nvapi 預設關、Helldivers icon、CS2/GTA/Diablo LUID、PoE2 MoltenVK ext、Battle.net ACL、Ubisoft SwiftShader ICD、Marvel Rivals powershell、locale registry、icon mask、raw mouse relative… | CrossOver 26 已有同等或更新實作 |
| TLS expansion slots（CW HACK 18756） | CX26 `dlls/ntdll/loader.c` 已有 |
| Don’t use private writable mappings（bug 58008） | CX26 `map_file_into_view` 已是 linux=`MAP_PRIVATE`、else=`MAP_SHARED` |
| Prefer reserved area | CX26 已有 `find_reserved_free_area` / `_outside_preloader` |
| Display mode emulation 預設關 | CX26 `emulate_modeset` 預設為 false（Wine 11 已無 Proton 10 的 `= TRUE`） |
| Service pipe timeout 40s（CW HACK 20218） | CX26 `programs/services/services.c` 已是 `40000` |
| Refuse builtins lacking arch PE dir | CX26 `find_builtin_dll` 已走 `get_pe_dir()`；GameSir 是刪 Proton 10 的無架構目錄 fallback |
| 16+ 款遊戲 HACK、CEF/nw.js argv 表、`WINE_PROCESS_ENV_*`、per-process cmdline 檔 | 與 CompatDB 政策衝突；steamwebhelper 已有 YAML 規則 |
| MapleStory / wineserver abort 防護 / MoltenVK 1.4.0 Cyder patch | GameSir 沒有；維持現有 Cyder stack |

---

## P1 — 已落地（2026-08-20）

已進預設 CX26 apply 清單（禁止 `git am` Proton 10 patch；hunk 對 CX26 重做）：

- `patches/cyder-wineserver-macos-timezone-bias.patch`
- `patches/cyder-wineserver-registry-fsync.patch`
- `patches/cyder-winemac-hide-ime-only-klid.patch`
- `patches/cyder-kernelbase-disk-free-space-fallback.patch`

## P1 — 建議移植（小 diff、無 exe 名、CX26 確認缺）

### 1. macOS 時區：避開 `gmtime`/`localtime` + cache bias

| | |
|--|--|
| GameSir | `eb7c7d14e43` Avoid gmtime/localtime timezone initialization on macOS；`316bf39a51e` Cache timezone bias on macOS |
| CX26 | `server/fd.c` `set_user_shared_data_time()` 仍每秒 `gmtime` + `mktime` + `localtime` |
| 用途 | macOS 上 libc 時區初始化會拖慢 wineserver 熱路徑；DST 切換時 bias 也可快取（GameSir 快取為行程生命期，DST 跨日可能過期，移植時可維持「每秒最多更新一次」但改走 `gettimeofday(..., tz)`） |
| 觸及 | `server/fd.c` |
| 驗證 | 靜態：Apple 路徑不再呼叫 `gmtime`/`localtime`。執行：prefix 內時間相關遊戲 / `GetTimeZoneInformation`；確認 wineserver 不因 tz 初始化卡頓 |
| 風險 | 低。`tz.tz_minuteswest` 在部分系統已 deprecated，但 CrossOver/GameSir 皆用此避開 libc |

合併成**一個** Cyder patch，不要拆兩個歷史 commit。

### 2. `GetDiskFreeSpaceExW`：裝置根失敗時改查真實對應磁碟

| | |
|--|--|
| GameSir | `2d7790ce893` Fake success in GetDiskFreeSpaceExW if opening device fails（固定 400/200 GB） |
| CX26 | 已落地 `cyder-kernelbase-disk-free-space-fallback.patch`：失敗改查 `X:\` / 目前磁碟 / `windows_dir`，不再發明容量 |
| 用途 | 安裝器查 `\\.\C:` 失敗會以為磁碟滿或中止安裝。改查真實 `NtQueryVolumeInformationFile` 容量 |
| 觸及 | `dlls/kernelbase/volume.c` |
| 驗證 | 對 `\\.\C:` 呼叫 `GetDiskFreeSpaceExW` 應成功且接近 host 該磁碟可用量；真的開不了任何目錄時仍回 `FALSE` |
| 風險 | 低。後備路徑可能是「目前磁碟」而非呼叫者指定的代號 |

已落地：失敗時**不**偽造 400/200 GB。

### 3. winemac：不要把 IME-only source 編成 KLID `0xe0000000`

| | |
|--|--|
| GameSir | `27037c0eec0` winemac: stop exposing IME-only KLIDs |
| CX26 | `dlls/winemac.drv/keyboard.c` `get_hkl()` 仍有 `if (!CFEqual(type, kTISTypeKeyboardLayout)) lcid |= 0xe0000000` |
| 用途 | `GetKeyboardLayoutNameW` 會把 IME 來源洩成遊戲去 parse 的 KLID，造成錯鍵盤/輸入 |
| 觸及 | `dlls/winemac.drv/keyboard.c`（約 7 行） |
| 驗證 | 切換注音/拼音 IME 後，遊戲或 `GetKeyboardLayoutNameW` 不再出現 `E000xxxx`；實體美/中鍵盤 layout 仍正常 |
| 風險 | 低。可能影響依賴「IME HKL 高位元」的輸入法測試；macOS IME 狀態本就由 TIS/winemac IME 路徑處理 |

### 4. wineserver registry：寫出前 `fflush` + `fsync`

| | |
|--|--|
| GameSir | `67e6264dcdc` Flush and fsync registry files before closing |
| CX26 | `server/registry.c` `save_branch()`：`ret = !fclose(f)`，無 fsync |
| 用途 | 異常退出時降低 `user.reg` / `system.reg` 只寫緩衝、未落盤 |
| 觸及 | `server/registry.c` `save_branch`（約 4 行） |
| 驗證 | 改 registry 後殺 wineserver，確認檔案完整；`tests/` 若有 registry save 路徑可加窄測 |
| 風險 | 低。fsync 略增關瓶/週期存檔延遲，對遊戲熱路徑幾乎無感 |

---

## P2 — 有條件移植

### 5. `ROSETTA_X87_PATH` + stash `DYLD_INSERT_LIBRARIES`

| | |
|--|--|
| GameSir | `211e7d42764` Support `ROSETTA_X87_PATH`；`d50fc636675` Stash DYLD_INSERT_LIBRARIES before Rosetta loader exec |
| CX26 | `dlls/ntdll/unix/loader.c` `preloader_exec` 無 x87 loader；CX 已有 Dock 名稱 link / `posix_spawn` hack |
| 用途 | 無 preloader 時若啟動 **i386 PE**，re-exec 到 [rosettax87_jit](https://github.com/Lifeisawful/rosettax87_jit)，改善 Rosetta 預設 x87 |
| 觸及 | `dlls/ntdll/unix/loader.c`（須接到現有 `preloader_exec(argv, image_path)`，不要覆寫 CX Dock-link） |
| 前置 | 產品要不要支援 32-bit x87 遊戲；loader 二進位如何打包/授權；minOS 10.15 是否能跑該 loader |
| 驗證 | 設 `ROSETTA_X87_PATH` 後 32-bit 浮點遊戲走 JIT；未設定時行為與現況相同；re-exec 後 `DYLD_INSERT_LIBRARIES` 仍在 |
| 風險 | 高。與 CX `posix_spawn` / 無 preloader 路徑交織；只在明確要 32-bit 線時做 |

**預設不進 CX26 release stack。** 獨立 patch，env 未設則為 no-op。

### 6. `unixpid` debug channel

| | |
|--|--|
| GameSir | `ba211249b56`（`dlls/ntdll/unix/debug.c` 兩行） |
| CX26 | 僅有 `pid` / `timestamp` channel |
| 用途 | Wine debug header 印 Unix `getpid()`，方便對 host `sample`/`fs_usage` |
| 驗證 | `WINEDEBUG=+unixpid` 日誌出現 host pid |
| 風險 | 極低。純診斷，可不進 release 預設 |

### 7. macOS 停用 gstreamer-gl（需先對齊 Wine 11 檔案）

| | |
|--|--|
| GameSir | `556536a6712` 在 `unixlib.c` / `wg_parser.c` `#ifndef __APPLE__` 包 `gst/gl` |
| CX26 | Wine 11 `dlls/winegstreamer/` 已改組，**沒有** Proton 10 那兩個檔；`configure.ac` 仍可探測 `gstreamer-gl-1.0` |
| 用途 | 避開 macOS 上 GST-GL 與 Wine 視窗互通 crash |
| 做法 | 在 CX26 實際 `#include <gst/gl/gl.h>` 或 `use_opengl` 處加同等 `__APPLE__` 守衛；不要套 Proton 10 patch |
| 風險 | 中。檔案對不上；先 `rg gst/gl` 確認仍有 GL 路徑再寫 patch |

### 8. `WINEDLLDIRn` overlay 可新增 builtin（多半不搬）

| | |
|--|--|
| GameSir | `0ab2145a52a` 允許 overlay 目錄提供額外 builtin PE |
| CX26 | 已有 `WINEDLLDIR*` / `WINEDLLPATH`；圖形 DLL 走 CompatDB prepend |
| 用途 | 不改 bottle 即可塞第三方 builtin |
| 建議 | **先不移植**。與 `cxcompatdb.so` 重疊。除非要支援「任意 overlay builtin」且 CompatDB 做不到 |

---

## 建議落地順序

1. **Patch A**（可一週內進預設 stack）：時區 `fd.c` + registry `fsync` + IME KLID + `GetDiskFreeSpaceExW`  
   - 四個獨立 patch 檔，便於 bisect  
   - `patches/README.md` + `build-wine.sh` apply 清單 + 各一個 marker
2. **Patch B**（可選）：`unixpid`
3. **調查後再決定**：gstreamer-gl on Wine 11
4. **產品決策後**：`ROSETTA_X87_PATH`（含 DYLD stash），預設關閉

不要做的下一步：不要從 GameSir 抄 `kernelbase/process.c` 的 exe 表；新遊戲用 CompatDB YAML。

---

## 套用方式（CX26 慣例）

每個 P1 patch 放 `cyder-wine-engine/patches/`，例如：

- `cyder-wineserver-macos-timezone-bias.patch`
- `cyder-kernelbase-disk-free-space-fallback.patch`
- `cyder-winemac-hide-ime-only-klid.patch`
- `cyder-wineserver-registry-fsync.patch`

套用走 `scripts/build-wine.sh` 的 `apply_cyder_patch`（idempotent + marker）。增量驗證見 `docs/incremental-build-and-patches.md`。

參考來源 repo 不納入 release tarball。
