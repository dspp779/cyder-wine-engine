# ROSETTA_X87_PATH：移植評估（暫不納入）

狀態：**延後**。記錄評估結論，之後若要支援 32-bit x87 爛點遊戲再決策。  
對照日期：2026-08-21。

相關：[GameSir → CX26 可移植清單](gamesir-cx26-portable-list.zh-TW.md) §P2.5。

---

## 1. 這是什麼

Apple Silicon 上透過 Rosetta 跑 **i386 Windows PE** 時，預設 x87 浮點路徑可能極慢或行為不佳。[rosettax87](https://github.com/Lifeisawful/rosettax87)／[rosettax87_jit](https://github.com/Lifeisawful/rosettax87_jit) 提供外部 **runtime loader**：Wine 在啟動 32-bit 映像前 `execv` 到該 loader，改善 x87。

整合慣例是 host 環境變數：

```bash
export ROSETTA_X87_PATH=/path/to/runtime_loader   # 或舊版 rosettax87 二進位
wine /path/to/app.exe
```

**未設定則應為 no-op。**

---

## 2. 誰有、誰沒有

| 樹 | `ROSETTA_X87_PATH` |
|----|-------------------|
| WineHQ upstream | 無（非官方功能） |
| Gcenx `wine@devel`（較早，release notes 如 11.0／11.1／11.6 曾列 HACK） | 曾有：`HACK: ntdll: recognize ROSETTA_X87_PATH` |
| Gcenx／Homebrew `wine@devel` **11.15**（2026-08 查） | **已無**；`ntdll.so` 無該字串；[rosettax87_jit README](https://github.com/Lifeisawful/rosettax87_jit) 標 **Deprecated**，無替代 |
| GameSir／GameHub wine | 有（`211e7d42764` + DYLD stash `d50fc636675`） |
| CrossOver 26／Cyder CX26 | **無** |

常見誤解：「以前 Wine 原生支援、上游後來拿掉」。實際是 **macOS 社群建置／GameHub 的 HACK**；Gcenx 套件後續撤掉，不是 WineHQ 版本線上的正式 API。

---

## 3. 參考實作比較

### 3.1 Gcenx（歷史 `wine@devel`）

- 概念：`getenv("ROSETTA_X87_PATH")` 後，在 loader／preloader 的 `exec` 路徑對 32-bit 改走外部 loader。
- 產品形態：使用者自行安裝 rosettax87，全域或 shell export env。
- 現況：devel 建置已移除；**不能**再當「跟 wine@devel 對齊即可」的現成依賴。

### 3.2 GameSir（較完整）

來源：`.research/gamesir-wine`（Proton 10 系）。

1. **`ntdll: Support ROSETTA_X87_PATH`**
   - `get_initial_unix_pe_machine`：讀 PE header 判斷是否 i386（補「無 preloader、直接 `wine /unix/path.exe`」）。
   - `should_exec_initial_rosetta_loader`：env 已設且初始 PE 為 i386。
   - `preloader_exec(argv, machine)`：i386 + env → `execv(ROSETTA_X87_PATH, …)`，否則原路徑。
   - 鉤在舊式 `__wine_main` 首次 `WINELOADERNOEXEC`／`pre_exec`／`loader_exec` 流程。

2. **`ntdll: Stash DYLD_INSERT_LIBRARIES before Rosetta loader exec`**
   - exec 前把 `DYLD_INSERT_LIBRARIES` 存到 `ROSETTA_X87_SAVED_DYLD_INSERT_LIBRARIES` 並 unset，避免與 Rosetta loader 衝突／遺失。

### 3.3 Cyder CX26（現況）

`dlls/ntdll/unix/loader.c`：

- `HAVE_WINE_PRELOADER` **未定義**（無 wine-preloader）。
- `preloader_exec(char **argv, const char *image_path)`：Apple 上 CW Dock 名稱 link + `posix_spawn(… SETEXEC | DISABLE_ASLR)`，再 fallback `execv`。
- Wine 11 `__wine_main` **已改寫**，與 GameSir 鉤的首次 `pre_exec`／`loader_exec` 結構**不一致**。
- 已安裝 `ntdll.so`：**無** `ROSETTA_X87_PATH` 字串。設 env **目前無效**。

---

## 4. 若移植：改動範圍

| 項目 | 內容 |
|------|------|
| 程式 | 主要 `dlls/ntdll/unix/loader.c`：在最終 exec／spawn 前插入 env 閘門 + i386 判斷；可選 PE peek、DYLD stash |
| Patch 形態 | **獨立** opt-in patch；對 CX26 tree **重做 hunk**；禁止 `git am` Proton／舊 Gcenx patch |
| 整合點 | 接上現有 `preloader_exec(argv, image_path)`／`exec_wineloader`；**不可**默默拆掉 Dock link／`posix_spawn` ASLR 行為（或需文件化取捨） |
| 產物 | **不**預設把 `rosettax87_jit` 打進 engine tarball（授權、簽署、minOS；jit 常要求較新 macOS，與產品 floor **10.15** 可能衝突） |
| App | 每遊戲／進階偏好 → **launcher 設 host env**（指向使用者或可選 sidecar 的 loader）。CompatDB `set_env` 只動 Windows env，**不夠** |
| 測試 | env 未設：64-bit／一般 32-bit 行為不變；env 設 + 假／真 loader：i386 走 loader、amd64 不走；Dock／spawn 回歸 |

規模：邏輯約數十行，**風險在與 CX 啟動路徑交織**，不在行數。

---

## 5. 不良影響與風險

| 風險 | 嚴重度 | 說明 |
|------|--------|------|
| 與 CW Dock／`posix_spawn` 衝突 | 高 | 改錯 `argv[0]` 或跳過 spawn → Dock 名稱／ASLR 行為異常 |
| 誤傷 64-bit | 高（若判斷錯） | 必須嚴格 i386 + env；否則啟動失敗 |
| 外部 loader 失敗 | 中 | 路徑／權限／架構／minOS 不合 → 整次啟動掛掉；需明確錯誤 |
| DYLD inject | 中 | 不 stash 可能丟注入庫；亂 unset 也可能弄壞依賴 |
| 安全 | 中 | env 可指向任意可執行檔；僅應由 Cyder 可信設定寫入 |
| 維護成本 | 中 | Gcenx 已放棄；Cyder 等於自維護社群已棄 HACK |
| 產品收益面窄 | — | 僅少數 **32-bit + x87** 標題；多數 64-bit／D3DMetal 遊戲無感 |
| 預設無 env | 低 | 實作正確時對既有使用者為 no-op |

---

## 6. 建議產品形態（若日後納入）

1. **Engine：** 獨立 patch，env 未設 = no-op；不進預設「必開」行為。  
2. **Loader：** 可選 sidecar 或文件化「使用者自備」；先確認目標 loader 的 minOS／授權是否可接受。  
3. **UI：** 每遊戲進階選項（例如「使用 Rosetta x87 loader」）→ launcher export `ROSETTA_X87_PATH`。  
4. **CompatDB：** 可當「此款建議開啟」的標記來源，但 **執行仍靠 launcher 設 host env**，不要只用 `set_env`。  
5. **預設 release stack：** 維持**不包含**，直到有明確 32-bit 產品線與測試樣本。

---

## 7. 納入前檢查清單

- [ ] 選定 loader（rosettax87 vs jit）與授權／打包方式  
- [ ] 確認 loader 與 Cyder host minOS 10.15（或提高 floor）相容  
- [ ] 在 CX26 `preloader_exec` 畫清：x87 插在 `posix_spawn` 前或僅 fallback `execv`  
- [ ] 實作 env 閘門 + i386；決定是否要 PE peek、DYLD stash  
- [ ] 煙測：無 env；有 env + 64-bit；有 env + 32-bit；Dock 名稱  
- [ ] 文件：進階選項說明、失敗時怎麼關  

---

## 8. 查核指令（之後覆核用）

```bash
# Cyder 原始碼／安裝樹
rg -n 'ROSETTA_X87' build/cx26/sources/wine/dlls/ntdll/unix/loader.c
strings install/wine-cx26-x86_64/lib/wine/x86_64-unix/ntdll.so | rg ROSETTA_X87

# 本機 Homebrew wine@devel（若有）
strings "$(brew --prefix)/Caskroom/wine@devel/"/*/Wine*/Contents/Resources/wine/lib/wine/x86_64-unix/ntdll.so \
  | rg ROSETTA_X87 || true

# GameSir 參考
git -C /Users/jjc/ogom/.research/gamesir-wine show 211e7d42764 -- dlls/ntdll/unix/loader.c
git -C /Users/jjc/ogom/.research/gamesir-wine show d50fc636675 -- dlls/ntdll/unix/loader.c
```
