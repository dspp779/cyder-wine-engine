# GameHub／CrossOver 相容性設定彙整

對照基準（2026-08-20）：

| 來源 | 路徑／版本 | 性質 |
|------|------------|------|
| **GameHub（GameSir）** | 本機 research clone：`CyderBits/.research/gamesir-wine`（Proton Wine 10 + GameSir 修補） | **引擎內硬編** exe／路徑 HACK（argv、環境、DLL、圖形） |
| **CrossOver Software Catalog** | `/Applications/CrossOver.app/.../share/crossover/data/crossover.tie`（約 23 MB XML，`c4p`） | **安裝／bottle profile**：medal、registry、環境變數、DLL override、依賴元件 |
| **CrossOver host fixes** | 同目錄 `cxfixes.xml`（`release="20260715"`） | **Linux 宿主套件／OpenGL 診斷**，不是 per-game bottle 設定 |
| 本機 CrossOver App | **26.3** | 與 Cyder CX26.3 對齊的產品線 |

> **GameHub** 指 GameSir 的 Mac／Android 遊戲啟動器；其 Wine 相容層與本專案對照的 `gamesir-wine` 同源。本文件整理的是**可觀測的相容設定**，不是授權轉載完整官方目錄。

Cyder 政策提醒：含遊戲／exe 名稱的行為應走 CyderBits `docs/cyder-compatdb.zh-TW.md`（CompatDB YAML）或啟動器，**不要**再硬編進 `cyder-wine-engine`。平台級、無 exe 名的修補見 [`gamesir-cx26-portable-list.zh-TW.md`](gamesir-cx26-portable-list.zh-TW.md)。

---

## 1. 三份資料各管什麼

```text
GameHub / gamesir-wine
  └─ 執行期：CreateProcess / SetEnvironmentVariable / wined3d / winemac …
       → 依 exe 路徑或 SteamGameId 改 argv、假成功、藏檔、改 GPU 回報

crossover.tie（Software Catalog）
  └─ 安裝期／bottle 範本：裝什麼、預寫哪些 registry／環境變數、medal 評等
       → CrossOver GUI「安裝軟體」與 bottle template 消費

cxfixes.xml
  └─ Linux 宿主：缺哪些 .deb/.rpm、OpenGL/X11 是否夠格跑 CrossOver UI
       → macOS CrossOver 基本不消費（檔內無 darwin／macos distribution）
```

| 問題類型 | 優先查 | Cyder 對應 |
|----------|--------|------------|
| CEF／nw.js／啟動器黑畫面、要加 Chromium 旗標 | GameHub argv 表 | CompatDB `append_args` |
| 整瓶 DPI／Retina／DllOverrides／等子程序 | `crossover.tie` | settings／winetricks／YAML |
| Linux 套件缺 OpenGL | `cxfixes.xml` | 不適用 macOS Cyder |
| wineserver／時區／IME KLID 等平台行為 | 移植清單（無 exe 名） | engine patch |

---

## 2. GameHub（GameSir Wine）遊戲 Hack

來源：`dlls/kernelbase/process.c` 的 `hack_append_command_line` 選項表，以及標記 `HACK`／遊戲名的 commit。路徑比對用 `wcsstr(cmd, exe_name)`；少數列可選 `SteamGameId`。

### 2.1 命令列追加（CEF／nw.js／啟動器）

| 匹配（路徑子字串） | 追加 argv | SteamGameId |
|--------------------|-----------|-------------|
| `Click&Fight.exe` | `--disable_direct_composition=1` | — |
| `Willful.exe` | `--disable_direct_composition=1` | — |
| `Banyu Lintar Angin - Little Storm -.exe` | `--disable_direct_composition=1` | — |
| `Super\Super.exe` | `--disable_direct_composition=1` | — |
| `A Raven Monologue.exe` | `--use-angle=d3d9` | — |
| `antenna\antenna.exe` | `--use-angle=d3d9` | — |
| `Bloody Walls\game.exe` | `--disable_direct_composition=1` | — |
| `Insanitys Blade\nw.exe` | `--use-gl=swiftshader` | — |
| `Warhammer2.exe` | `--in-process-gpu` | — |
| `SummerIslands.exe` | `--in-process-gpu` | — |
| `UplayWebCore.exe` | `--use-angle=vulkan` | — |
| `Paradox Launcher.exe` | `--use-angle=gl` | — |
| `Montaro\nw.exe` | `--use-gl=swiftshader` | — |
| `Aisling and the Tavern of Elves\nw.exe` | `--use-gl=swiftshader` | — |
| `Snares of Ruin 2\SoR2.exe` | `--use-gl=swiftshader` | — |
| `\EpicOnlineServicesUIHelper` | `--use-angle=vulkan` | — |
| `OlympiaRising.exe` | `--use-gl=swiftshader` | — |
| `nw.exe.exe` | `--use-angle=d3d9` | — |
| `DC Universe Online\LaunchPad.exe` | `--use-gl=swiftshader` | — |
| `PlanetSide 2\LaunchPad.exe` | `--use-gl=swiftshader` | — |
| `PaladinLias\Game.exe` | `--use-gl=desktop` | — |
| `EverQuest 2\LaunchPad.exe` | `--use-gl=swiftshader` | — |
| `Everquest F2P\LaunchPad.exe` | `--use-gl=swiftshader` | — |
| `Red Tie Runner.exe` | `--use-angle=gl` | — |
| `UnrealCEFSubProcess.exe` | `--use-gl=swiftshader` | `2316580` |
| `UnrealCEFSubProcess.exe` | `--use-angle=d3d9` | `2684500` |
| `\EACefSubProcess.exe` | `--use-angle=vulkan` | — |
| `steamwebhelper.exe` | `--no-sandbox --single-process --disable-gpu` | — |
| `SlayTheSpire2.exe` | `--rendering-driver opengl3` | — |
| `EADesktop.exe` | `--in-process-gpu --use-gl=angle` | — |
| `SocialClubHelper.exe` | `--no-sandbox --in-process-gpu --disable-gpu` | — |
| `PlayGTAV.exe` | `-nobattleye` | — |

**語意分組**

| 手法 | 用途 |
|------|------|
| `--use-gl=swiftshader` / `--use-angle=*` | 強迫 CEF／nw／LaunchPad 走軟體或特定 ANGLE 後端，避開壞掉的 GPU 合成 |
| `--in-process-gpu` / `--single-process` / `--no-sandbox` | 降低多進程 GPU／沙箱在 Wine 下的失敗率（Steam WebHelper、EA、Social Club） |
| `--disable_direct_composition=1` | 關掉 DirectComposition（部分 indie／nw 黑畫面） |
| `-nobattleye` | GTA V 啟動器避開 BattlEye（相容／反作弊取捨） |

Cyder 現況：`steamwebhelper` 類參數已有 CompatDB YAML 方向；其餘應逐款 YAML，**不要**抄整張表進 engine。

### 2.2 其他具名遊戲／啟動器 HACK（macOS 相關優先）

| 目標 | 模組／手法（commit 摘要） | 備註 |
|------|---------------------------|------|
| Helldivers 2 | `winemac.drv`：限制過度 icon 更新 | CX26 多半已有同等 |
| CS2 | `wined3d`：Apple Silicon GPU 偵測 | CX26／D3DMetal 路徑需對照 |
| GTA 系列 | `wined3d`：啟動崩潰／VRAM；Rockstar Launcher UI | 與 LUID／裝置回報相關 |
| Diablo IV | `setupapi`：GPU LUID + D3DMetal | CX26 常已覆蓋 |
| Path of Exile 2 | `ntdll`：關掉特定 MoltenVK extension | 圖形棧敏感 |
| Marvel Rivals | `kernelbase`：擋 `powershell.exe`；`ieframe` pump | Steam AppId 提及 |
| Battle.net | `advapi32`：資料夾 security descriptor | CX26 常已有 |
| Ubisoft Connect (`upc.exe` / `UplayWebCore.exe`) | 寫入 SwiftShader ICD JSON | `SetEnvironmentVariable` 路徑 |
| EA Desktop | 強制 in-process-gpu（與上表 argv 重疊） | |
| Persona 5 Strikers | 隱藏部分 movie 檔 | 檔案可見性 HACK |
| Manor Lords | 檔案版本查詢 workaround | |
| Halo MCC | `ConvertThreadToFiberEx` 假成功 | |
| Slay the Spire 2 | 強制 OpenGL 渲染 | 與 argv `--rendering-driver` 同主題 |
| Skyrim SE | DPI awareness = system | |
| Post Mortem | `win32u` 藏視窗 | |
| RDR2 | loader：拿掉 Vulkan DLL override | |
| msedgewebview2 | `wine.inf`：冒充 Win7 | |

另有大量 **Proton／winex11／gamescope／KWin** 向 HACK（Forza、Mutter、fullscreen 等），對 **macOS Cyder** 多半不適用，移植時應過濾。

### 2.3 GameHub 還有、但不該進 Cyder engine 的機制

- `WINE_PROCESS_ENV_*`／per-process env 目錄 overlay  
- per-process cmdline 覆寫檔  
- `WINEDLLDIR` overlay 塞額外 builtin（與 `cxcompatdb.so` prepend 重疊）

---

## 3. CrossOver `crossover.tie`（Software Catalog）

### 3.1 檔案角色

- 根節點：`<c4p>`（CodeWeavers CrossOver Compatibility Center／軟體目錄）。
- 主要內容：上千個 `<app appid="com.codeweavers.c4.N">`，含多語系名稱、說明、**medal**（gold／silver／bronze／un*）、平台（Mac／Linux／Android）、`bottletemplate`、`installprofile`、`preinstallregistry`、`installerenvironment`、`installerdlloverrides`、`predependency`、Steam id、安裝筆記等。
- 本機快照規模：約 **5300+** 個含 bottle／registry／DLL 設定的 app 區塊；遊戲分類（`Games/*`）為主體之一。
- CrossOver GUI 安裝軟體與建立 bottle 時讀取；**不是** Wine 源碼裡的 `CreateProcess` HACK 表。

### 3.2 常見設定類型（語意）

| XML 區塊 | 作用 | Cyder 近似 |
|----------|------|------------|
| `<bottletemplate>` | 基底 Windows 版本範本（如 `win98`、較新 win 範本） | prefix Windows 版本／bootstrap |
| `<flag>application\|component\|virtual\|nsplugin</flag>` | 條目類型：一般 App／執行庫元件／虛擬項目／瀏覽器外掛 | CompatDB 不對等；元件多用 winetricks |
| `<medal platform="Mac" …>` | 社群／官方相容評等（歷史版本很多） | 僅參考，非執行設定 |
| `<preinstallregistry>` | 預寫 `HKCU\Software\Wine\…`（DllOverrides、Explorer Desktop、Direct3D、Fonts、Mac Driver…） | 全域／每遊戲 registry、settings |
| `<installerenvironment>` | 安裝或執行時環境變數（見下節 `CX_*`／`WINE_WAIT_*`） | 每遊戲 env |
| `<installerdlloverrides>` | 安裝器階段 DLL／exe override（常見 `msi`、`.NET` 相關） | winetricks／DLL 覆寫 |
| `<predependency>` | 先裝其他 catalog 元件（執行庫、字型…） | winetricks 依賴鏈 |
| `<steamid>` | 與 Steam 標題關聯 | CompatDB 尚未以 Steam AppId 為 matcher（需 engine 擴充） |

### 3.3 具名環境變數（catalog 內實際出現）

從整份 `crossover.tie` 掃出的 **CrossOver／Wine 控制變數**（非一般遊戲自有 env）：

| 變數 | 約略命中 | 代表用途／範例 |
|------|----------|----------------|
| `WINE_WAIT_CHILD_PIPE_IGNORE` | ~340 apps | 值為子 exe 名（常見 `bfggameservices.exe`、更新程式、`Agent.exe`…）：父行程等待子行程 pipe 時忽略列出的程序，避免安裝器／啟動器卡死 |
| `WINE_WAIT_CHILD_PIPE` | ~83 apps | 常見值 `bfgclient.exe`（Big Fish 客戶端）：明確等待該子程序 |
| `WAIT_WINE_CHILD_PIPE` | 少數 | 如 Hearthstone／國服：變體命名 |
| `CX_HACK_NO_SCHED_YIELD` | Steam | 與「不要 sched_yield」類相容相關（Cyder MapleStory 有類似但 exe 綁定的 patch） |
| `CX_HACK_REMOTE_DRIVES` | StarCraft II | 遠端／網路磁碟相關行為 |
| `CX_HACK_FILESYSTEM_TYPE` | Easy Paint Tool SAI | 檔案系統類型回報 |
| `CX_HACK_MSI_COM` | Photoshop CS3／CS5 | MSI／COM 安裝路徑 |
| `CX_MSI_MTA` | Acrobat X／XI Pro | MSI 多執行緒公寓 |
| `CX_SKIP_FONTCONFIG_FONTS` | Office 97、OLE 元件 | 跳過 fontconfig 字型 |
| `CX_PNG_ICON` | 部分 .NET 4.6.x | 圖示處理 |
| `WINE_LARGE_ADDRESS_AWARE` | OMSI 2、Quicken Classic | 大位址空間 |

`WINE_WAIT_CHILD_PIPE*` 在 **Big Fish Games** 類條目大量重複；整理時應視為**機制**，不必逐款抄 300+ 遊戲名。

### 3.4 Registry 模式（高頻）

目錄內最常見的預寫鍵（跨所有 app，不限 Mac）：

| 鍵前綴 | 用途 |
|--------|------|
| `HKCU\Software\Wine\DllOverrides` | 全域或安裝器 DLL 策略 |
| `HKCU\Software\Wine\AppDefaults\<exe>\DllOverrides` | **每 exe** DLL（catalog 大量用於 BFG／QQ／Outlook 等） |
| `HKCU\Software\Wine\Explorer`／`Desktops` | 虛擬桌面解析度 |
| `HKCU\Software\Wine\Direct3D` | 如 `CSMT=disabled`（遊戲條目中偶見） |
| `HKCU\Software\Wine\Fonts\Replacements` | 字型替換 |
| `HKCU\Software\Wine\Mac Driver` | macOS 驅動相關（Retina 等常在此一帶） |
| `HKCU\Software\Wine\X11 Driver` | Linux X11 |

完整逐 app 表過於龐大（unique 有趣條目約 1800+），需要時以本機檔搜尋：

```bash
rg -n 'AppName|CX_HACK_|WINE_WAIT_CHILD' \
  "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/share/crossover/data/crossover.tie"
```

---

## 4. CrossOver `cxfixes.xml`

### 4.1 這份檔**不是**遊戲相容資料庫

- 根：`<cxfixes release="20260715">`
- `<distributions>`：Arch、Debian、Fedora、RHEL、SUSE… 的套件管理員指令與辨識規則  
- `<cxproducts>`：`cx12`…`cx26` 版本正規式（含 `cx26` fallback `cx25`）  
- `<fixes>`：宿主缺套件／OpenGL／X11／ntsync 等 **CrossOver 本體能否跑** 的修復建議  

**無 macOS／darwin distribution**。在 Mac 上閱讀此檔，主要是了解 CodeWeavers 如何為 Linux 宿主做依賴修復，**不能**當遊戲設定來源。

### 4.2 Fix 類型（摘要）

實際 `<fix id=…>` 數量含架構變體（如 `missinglibc.amd64`）約兩百餘；主題包括：

| 類別 | 例 |
|------|-----|
| UI 執行期 | `pygi`、`gir-data`、`gtk2`、Python VTE |
| 基本工具 | `gzip`、`openssl`、`pkexec`、Perl `File::Copy` |
| 打包 | deb／rpm packaging tools |
| 記憶體／執行緒 | `badrlimitas`、`pthreadcancelnotworking`、`brokenldt16` |
| 圖形 | `openglnotworking`、`openglnodri`、`openglnoglsl130`、缺 S3TC／float texture、過舊 AMD／NVIDIA、`x11lowdepth` |
| 音訊 | ALSA 未走 PipeWire／Pulse |
| 同步 | `ntsyncdisabled.*` |

---

## 5. 對 Cyder 的建議用法

1. **要加新遊戲相容**：優先寫 `compatdb/rules/*.yml`（`append_args`、DLL、圖形），對照本文件 GameHub argv 表與 `crossover.tie` 的 env／registry 模式。  
2. **不要**把 GameHub 的 exe 表或 `crossover.tie` 整包搬進 Wine patch。  
3. **平台修補**繼續用 [`gamesir-cx26-portable-list.zh-TW.md`](gamesir-cx26-portable-list.zh-TW.md)。  
4. **玩家可見總表**仍以 CyderBits `docs/games/compatibility-matrix.md` 為準；本文件是**上游機制／Hack 盤點**，供開發移植與 CompatDB 設計。

### 已與 Cyder 對齊的例子

| 上游 | Cyder |
|------|--------|
| GameHub `steamwebhelper` 單進程／關 GPU | CompatDB Steam 規則（argv） |
| CX／GameHub「no sched yield」思路 | MapleStory 專用 patch（exe 綁定，政策例外） |
| CX `Mac Driver`／Retina／DPI registry | Cyder settings／每遊戲 profile |
| GameHub 平台時區／IME／registry fsync／磁碟空間 | 已移植或規劃於 CX26 platform patches |

---

## 6. 再產生／更新本文件時

```bash
# Catalog 內 CX_ / WAIT_ 環境變數
rg -n 'CX_HACK_|WINE_WAIT_CHILD|WAIT_WINE_CHILD' \
  "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/share/crossover/data/crossover.tie"

# GameSir argv 表
rg -n 'options\[\]' -A80 \
  /Users/jjc/ogom/.research/gamesir-wine/dlls/kernelbase/process.c

# cxfixes 是否仍僅 Linux
rg -n 'darwin|macos|Mac OS' -i \
  "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/share/crossover/data/cxfixes.xml"
```

更新後請改本頁「對照基準」日期與 CrossOver／GameSir 版本欄。
