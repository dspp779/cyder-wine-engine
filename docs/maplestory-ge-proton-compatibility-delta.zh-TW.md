# MapleStory：GE-Proton／linux_maplestory × Cyder CX26 相容差異

> 日期：2026-09-06  
> 狀態：Experiment B 初稿；**W1／W2 已納入 CX26 預設 patch stack 並裝進本機 install**  
> 相關：[`maplestory-wine-breakthrough-opportunities.zh-TW.md`](maplestory-wine-breakthrough-opportunities.zh-TW.md)

## 1. 來源與本機副本

| 來源 | 路徑／連結 | 備註 |
|---|---|---|
| 社群安裝器／說明 | `third_party/linux_maplestory/`（clone of [oldschoola/linux_maplestory](https://github.com/oldschoola/linux_maplestory)，HEAD `181cd74` 2026-08-04） | Steam GMS appid `216150`；停用 NGS **不是**目標 |
| GE 源碼 game-patch | `third_party/ge-proton-maplestory-patches/*.patch`（自 proton-ge-custom 下載） | 已進 **GE-Proton11-2／11-3** release notes |
| umu registry gamefix | [umu-protonfixes#597](https://github.com/Open-Wine-Components/umu-protonfixes/pull/597)（merged 2026-07-22） | 對應 linux_maplestory 的 `.reg` |

GE release 明寫（GE-Proton11-2 起）：

> MapleStory: fixed startup failures involving accessibility settings and CharPrevA/CharPrevExA null pointers.

## 2. GE／社群修補清單（可優化候選）

### 2.1 Wine 源碼級（高價值、可考慮進 CX26 patches）

| # | 修補 | 模組 | Upstream | GE | CX26 現況（2026-09-06） | TMS／Cyder 建議 |
|---|---|---|---|---|---|---|
| **W1** | `CharPrevA`／`CharPrevExA`：`start==NULL` 時勿解參考 | `dlls/kernelbase/string.c` | [bug 59926](https://bugs.winehq.org/show_bug.cgi?id=59926)；GE [PR #603](https://github.com/GloriousEggroll/proton-ge-custom/pull/603) | `maplestory-kernelbase-charprev-null.patch`（`if (!start) return NULL;`） | **已納入** `maplestory-cx26-kernelbase-charprev-null.patch`（每趟 CX26 建置，同 message-wait） | 啟動 crash 防護；非 first-hit |
| **W2** | `SPI_SETSTICKYKEYS`／`SPI_SETFILTERKEYS`：`WINE_SPI_FIXME`→`WINE_SPI_WARN` | `dlls/win32u/sysparams.c` | [bug 59927](https://bugs.winehq.org/show_bug.cgi?id=59927)；GE [PR #601](https://github.com/GloriousEggroll/proton-ge-custom/pull/601) | `maplestory-spi-stickykeys-filterkeys.patch` | **已納入** `maplestory-cx26-win32u-spi-sticky-filter-keys.patch`（每趟 CX26 建置） | 啟動期 accessibility SET；非 first-hit |

這兩支是社群宣稱「三個 launch blocker」裡的 **Wine 本體**；與 first-hit materialize **無關**，但可降低「換 Wine／換啟動路徑又炸」的機率，並往 upstream／generic 靠。

### 2.2 GE-Proton11-1 **byte-patch only**（勿直接搬到 CX26）

`patches/patch-wine-binaries.sh` 綁死 **GE-Proton11-1** 偏移，除 CharPrev／SPI 外還有：

| Byte 標籤 | 意涵 | CX26 建議 |
|---|---|---|
| HeapSetInformation → 強制成功 | 可能來自 Mac／特定 Wine 行為差 | **不要** byte-patch install；若 TMS 需要，先寫 source A/B |
| SetLastError(0) 相關 | 同上 | 同上 |
| （註解）`dinput8.dll` 整檔替換 | 來自「另一個 Wine build」 | Mac／winemac 路徑不同；**不適用**直接替換 |

GE-Proton11-3 起應以 **源碼 patch** 為準，不再依賴 11-1 byte-patch。

### 2.3 Prefix／registry／runtime（政策層，多數非 Wine patch）

| # | 項目 | linux_maplestory／umu | CX26／OEM 已知 | 建議 |
|---|---|---|---|---|
| **R1** | AppDefaults `Version=win10`（`MapleStory.exe` 等） | `05-appdefaults-winver.reg` | Cyder／CompatDB 通常已偏 win10 | 確認 TMS prefix；缺再補 **launcher／bottle**，不要進 Wine patch |
| **R2** | `UseTakeFocus=N`（X11／alt-tab） | `01-usetakefocus.reg` | **Linux/X11 語意**；mac 是 winemac | **低優先／可能無關**；Mac 應對齊既有 winemac focus 行為 |
| **R3** | DirectInput：`UseLinuxInputEvents`、non-exclusive、Grab=N | `04-input-fixes.reg` | Linux evdev／`input` group | **Mac 不適用原樣**；若技能鍵問題，另查 winemac／HID（GameSir 等已有 CX26 線） |
| **R4** | `nxl:` protocol／Nexon Launcher 登錄 | `10-nexon-launcher-protocol.reg` | GMS Steam／Nexon launcher；TMS 是 BeanFun | **TMS 不搬**；屬 GMS launcher 契約 |
| **R5** | Direct3D `cb_access_map_w=1`、`CSMT=disabled` | `11-wine-direct3d-dll-overrides.reg` | OEM／CX26 A/B：**非**黑畫面必要；`cb_access_map_w` 曾單獨 A/B 負面 | **不要**當 first-hit／顯示主修補再投入 |
| **R6** | VC++ 2022 原生 DLL（含 `vcruntime140_threads.dll`） | `files/vc_runtime` + `13-apply-…` | Prefix 依賴；遊戲／安裝器常自帶 | 若缺檔再補 **bottle 檔案**，非 Wine source |
| **R7** | Virtual desktop／Wayland `BadWindow` | opt-in `--virtual-desktop` | Linux compositor | **Mac 無關** |
| **R8** | Apple keyboard F-keys／hid | `20-hid-apple-fkeysfirst.sh` | Linux hid | 僅 Linux；Mac 系統設定另議 |

### 2.4 明確**不是**優化 first-hit 的東西

社群這批修補全部對準 **啟動／輸入／launcher 契約**。  
對 CX26 已結案的 **真命中 Present gap ~0.65–0.75 s**，預期 **零直接效益**（見 findings）。

## 3. Cross-source 矩陣（更新）

| 項目 | Cyder CX26 | Wine 11.0（CX pin） | GE-Proton（11-2+） | GMS macOS OEM（bisect 基線） |
|---|---|---|---|---|
| message-wait handoff | yes | no（CX patch） | ? | OEM 行為內建／未單獨拆 |
| CharPrevA／ExA NULL | **yes** | **no**（stock） | **yes** | ?（未對 binary 驗證） |
| SPI sticky／filter WARN | **yes** | **no**（stock） | **yes** | ? |
| `.tmp`／`.msf` module-name | yes | no | ? | yes（OEM 差異） |
| win10 AppDefaults | bottle／CompatDB | — | yes（umu） | yes |
| Linux DirectInput／nxl: | n/a | — | yes | n/a（Mac／不同 launcher） |
| first-hit materialize 修補 | 無（產品 M0／M1） | — | 無 | 無證據 |

## 4. GMS macOS／CX25 OEM 版本（你問的「有沒有更新」）

### 4.1 Bisect／成功基線用的是什麼

研究文件（ogom，最後更新 **2026-07-20**）一致記載：

| 欄位 | 值 |
|---|---|
| 產品 | Nexon 北美官方 macOS 包內 **CrossOver OEM** |
| CrossOver | **`25.0.1.38865`** |
| Build tag | **`oem-maplestory-na-ngl-0.0.31`** |
| 用途 | CX25 OEM reverse bisect／台版成功基線 golden |

也就是：**不是**零售 CrossOver 25／26，而是 Nexon 鎖定的 OEM 25.0.1 客製 runtime。

### 4.2 本機 2026-09-06 抽樣

| 樣本 | 結果 |
|---|---|
| `MapleStory.app`（Nexon GMS Mac） | **未找到**（Applications／常見路徑無） |
| 零售 `/Applications/CrossOver.app` | **`26.3`／`26.3.0.39832`**（≠ OEM bisect 目標） |
| OEM engine 安裝樹 | 本機 `install/` 僅 CX26；無 `wine-maplestory-oem25*` |
| Cyder-maplestory-oem25 Application Support | 路徑亦未見（產品線已退役） |

**結論（保守）：**

- Bisect 當時鎖定的 GMS Mac OEM 是 **25.0.1.38865／oem-maplestory-na-ngl-0.0.31**。  
- **沒有證據**顯示本機已換成更新的 Nexon MapleStory Mac OEM；也**沒有**現成 app 可就地比對「官方有沒有默默升到 CX26 OEM」。  
- 零售 CrossOver 已是 26.3，**不能**拿來當「GMS macOS 已更新」的證明。  
- 若要確認 Nexon 是否出新 OEM：需重新下載官方 Mac 包，比對 `CrossOver Product Version`／`oem-maplestory*` build tag（Experiment A）。

## 5. 建議落地順序（TMS／Cyder）

1. **W2 SPI WARN** — **已納入** CX26 預設 patch stack（2026-09-06）。  
2. **W1 CharPrev** — **已納入**（GE 同款 `return NULL`；若之後要對齊 Windows `ptr-1` 再單開 A/B）。  
3. **R1 win10** — 只核對 prefix，不進 Wine。  
4. **跳過** R2–R4／R7–R8 原樣搬移；R5 不再當顯示主線；R6 僅缺檔時補。  
5. **不要**期待 W1／W2 改善 first-hit HUD 卡。

## 6. 工件索引

```text
third_party/linux_maplestory/                          # git clone
third_party/ge-proton-maplestory-patches/
  maplestory-kernelbase-charprev-null.patch
  maplestory-spi-stickykeys-filterkeys.patch
```

`third_party/` 應保持本機參考、勿當 release 產物打包進引擎。
