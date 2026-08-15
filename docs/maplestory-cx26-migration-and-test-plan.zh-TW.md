# 新楓之谷 CX26 單一引擎移植與測試計畫

## 目標

以 CX26.3 / Wine 11 為唯一持續維護的引擎，將研究分支
`codex/maplestory-oem-special` 已確認的 CX25 OEM 相容性差異移植進來。CX25 OEM
只保留為已知可玩的參考與 fallback；不再維護第二套 CX25 source build。

圖形 backend 的責任要分開：

- 新楓之谷正式路徑使用 D3DMetal / Apple GPTK，不要求 MoltenVK。
- DXVK 是另一條可選的驗證路徑；只有選 DXVK 時才檢查 MoltenVK capability。
- 兩條路徑共用同一個 CX26 Wine engine 與 MapleStory compatibility patch stack。

```mermaid
flowchart LR
    S[CX25 OEM bisect findings] --> P[CX26 MapleStory patch stack]
    P --> E[Single CX26 engine]
    E --> D[D3DMetal + GPTK<br/>primary MapleStory path]
    E --> V[Optional DXVK path<br/>MoltenVK capability check]
    D --> L[Lifecycle and visual test]
    V --> C[Renderer capability smoke test]
    L --> A[OTP → world → 20 minute play]
```

## 已移植的功能群

`scripts/build-wine.sh --cx 26 --maplestory` 會依序套用：

| 功能群 | 包含內容 | 重用性／來源 | 重要性 | 對其他應用程式的影響 | 採用建議 |
|---|---|---|---|---|---|
| 媒體與 WineD3D core | `maplestory-cx26-core.patch`：raw audio parser、user-memory texture pin、format-conversion staging | 可重用於需要 raw audio 或 CPU／GPU texture staging 的 Win32 遊戲；核心做法來自 CX25 OEM／CrossOver 相容性差異，但不是 MapleStory 專屬 API | 高 | 中；會影響 `winegstreamer` 與 `wined3d` 中使用相同 texture／audio 路徑的程式，可能改變記憶體與效能 | 正式納入 MapleStory profile；若要升級為全域行為，需補上 WineD3D／GStreamer regression 與效能測試 |
| 暫存模組載入與 DWARF | `maplestory-cx26-tmp-module-name.patch`、`maplestory-cx26-dbghelp-dwarf-guard.patch` | `.tmp`／`.msf` 載入可重用於會複製或重新命名 PE payload 的 anti-cheat／更新器；DWARF guard 可泛化為 debugger robustness | 高；對 BlackCipher 啟動是必要條件 | 低至中；loader／dbghelp 是共用路徑，但修補已限制在無效或不完整 symbol metadata，不改正常模組解析 | MapleStory profile 建議採用；DWARF guard 可另行提出 upstream 化，`.tmp` 命名修補不建議直接全域套用 |
| D3D11 shared resource 與 texture clear | `maplestory-cx26-d3d11-shared-texture-test.patch`、`maplestory-cx26-d3d11-full-clear.patch`、`maplestory-cx26-dxgi-shared-handle.patch`、`maplestory-cx26-texture-user-memory-reload.patch` | 可重用於使用 shared texture、`ClearView`／UAV clear、producer／consumer handle 或 user-memory texture 的 D3D11 應用程式；CX25 bisect 顯示它們是同一個資源生命週期契約 | 關鍵；拆開會得到局部畫面或再次黑畫面 | 中至高；會影響 D3D11 resource ownership、clear 語義與同步，可能改變其他遊戲的畫面正確性或效能 | MapleStory profile 正式採用，四個 patch 視為不可拆功能群；不建議直接作為所有 D3D11 應用程式的預設，應先做 shared-resource regression |
| D3DMetal view／surface 交接 | `maplestory-cx26-d3dmetal-legacy-surface.patch`、`maplestory-cx26-plain-metal-layer.patch` | 可重用於 D3DMetal 應用程式需要沿用可見 client view、Metal layer 或 helper process surface 的情況；概念是 CX25 OEM 的 view ownership | 高；決定 D3DMetal 是否能持續 present | 中；修改 `winemac.drv` 的 view／layer 交接，可能影響多視窗、overlay、retina 或 helper window | MapleStory D3DMetal profile 建議採用；不建議移除 app scope 後全域套用，需另做多視窗與 overlay 測試 |
| 視窗、焦點與反作弊 helper | `maplestory-cx26-window-resizable-flag.patch`、`maplestory-cx26-blackxchg-foreground.patch`、`maplestory-cx26-fullscreen-restore.patch` | 可重用於有 anti-cheat／overlay helper、fullscreen restore 或 resize handoff 的遊戲；`BlackXchg` 本身是 MapleStory 專屬流程 | 高；避免 helper 啟動或 resize 後失去前景／畫面交接 | 中；會改變 macOS foreground、resize 與 fullscreen 行為，可能影響其他遊戲的 focus、Alt+Enter 或 overlay | MapleStory profile 正式採用；`BlackXchg` 判斷應維持 app-specific，其他兩項可在獨立遊戲 regression 後再考慮泛化 |
| `win32u` message-wait handoff | `maplestory-cx26-message-wait-handoff.patch`：保留 upstream queue retry；queue 已就緒時不把無效 handle 清單送入等待 | 控制流可重用，且保留 upstream 的 retry 語義；觸發原因是 MapleStory 提供的 malformed handle list，不能解讀成「忽略所有無效 handle」 | 關鍵；已由實機確認可越過 CX26 黑畫面 gate 到登入畫面 | 中；`win32u` 是全域共用路徑，其他應用程式可能看到不同的 queue／wait 時序；修補沒有全域吞掉 `STATUS_INVALID_HANDLE`，風險較低但仍需 regression | 正式納入 MapleStory profile；暫不作所有應用程式預設，待 Wine message／wait regression 與其他 malformed-list case 驗證後，再評估 upstream 化 |
| CX25 OEM scheduler 對齊 | `maplestory-cx26-no-sched-yield.patch`：在特定同步路徑避免 host scheduler yield | 只可重用「需要與 CX25 OEM 同步時序」的經驗；不是一般 Win32 語義修正 | 中；是 MapleStory 啟動／反作弊時序的一部分，但不是 renderer 本身 | 高；會影響所有使用該 ntdll sync 路徑的程式之 latency、CPU 使用與公平性 | 只在 MapleStory profile 採用；不建議全域預設，需用多執行緒／CPU／能耗 benchmark 證明沒有回歸 |
| 非 Vulkan 的建置 fallback | `w1-win32u-vulkan-soname.patch` 與 `--without-vulkan` D3DMetal build contract | 可重用於 Wine 在停用 Vulkan 時仍編譯 `win32u/vulkan.c` 的 build environment；與 MapleStory runtime graphics 無關 | 低；只解除編譯／連結阻塞 | 僅影響 build，不影響 D3DMetal runtime，也不會載入 MoltenVK | 可保留為 CX26 build fallback；不應被當成 MapleStory runtime compatibility patch，也不應讓 MoltenVK 成為 D3DMetal 依賴 |

shared texture 與 full-clear 必須視為同一功能群，不能拆成只保留「有一點畫面」的
半成品配置。所有 patch 都放在 engine repo，release manifest 也會記錄順序。

### 採用範圍結論

目前建議的邊界是：將上述功能群保留在 `--maplestory` 的 CX26 compatibility
profile，由單一 CX26 engine 共用實作；不要把 MapleStory 專屬行為散落成全域環境變數，
也不要為了 D3DMetal 路徑引入 MoltenVK。可泛化的部分仍分兩級處理：

1. `win32u` queue handoff、DWARF guard、shared-resource ownership 等架構性修正，
   先以其他應用程式 regression 驗證，再考慮送回較廣泛的 Wine patch。
2. `.tmp` module name、BlackXchg foreground、CX25 no-sched-yield 與 malformed
   handle handoff 的觸發條件，維持 MapleStory profile；這些修正的重用價值在於
   方法與邊界，不代表可以把應用程式特例直接套到所有程式。

這份影響評估是依目前 patch 觸及的 Wine subsystem 與 A/B 結果推導；目前已驗證的是
CX26 + D3DMetal 到登入畫面，尚未完成其他遊戲的全面 regression 或實際 OTP 登入後
20 分鐘遊玩，因此「可泛化」項目仍須在擴大採用前補測。

## 建置策略

```sh
bash scripts/build-media-stack.sh --cx 26 --install-deps
bash scripts/build-media-stack.sh --cx 26
bash scripts/build-wine.sh --cx 26 --maplestory --without-vulkan
```

`RAW_AUDIO_PARSE=1` 仍需要隔離的 x86_64 GLib/GStreamer runtime；這是媒體處理
依賴，不是 Vulkan 依賴。若要驗證 DXVK，另建 `--with-vulkan` 並提供已測試的
MoltenVK，不得把該依賴帶進 D3DMetal 的 gate。

## 測試分層

| 層級 | 入口 | 通過條件 |
|---|---|---|
| 靜態契約 | `tests/test-maplestory-patch-stack.sh` | patch 檔、manifest、CX26-only 與 D3DMetal-neutral 條件成立 |
| 乾淨 source | 同上 | 所有 patch 可對 CX26.3.0 source 正向套用 |
| D3DMetal launcher | `tests/test-maplestory-d3dmetal-launcher.sh` | 強制 `CYDER_GRAPHICS_BACKEND=d3dmetal`，不引用 MoltenVK |
| engine regression | `tests/run.sh` | 既有引擎測試通過；若本機 wineserver 不可用，須標記為環境阻塞 |
| lifecycle smoke | `scripts/run-maplestory-cx26-d3dmetal.sh --no-otp` | MapleStory、BlackCipher/NGS、視窗與 renderer lifecycle 可追蹤 |
| 真實驗收 | 同一 launcher + 有效 BeanFun argv | 登入、進世界、地圖/UI/滑鼠正常，持續遊玩至少 20 分鐘 |

自動 log 只能證明 module load、process lifetime 與 renderer 初始化，不能單獨證明
「不是黑畫面」。最後一層必須人工確認登入畫面與進世界畫面；測試期間保留同一個
prefix、遊戲目錄與 debug log，避免把 bottle 差異誤判為 engine 修復。

## 實機測試入口

```sh
bash scripts/run-maplestory-cx26-d3dmetal.sh \
  --launch-exe '/absolute/path/to/MapleStory.exe' \
  --compatdb '/path/to/CompatDB/compatdb.cdb' \
  --no-otp
```

launcher 會自動尋找本機 CX26 engine 與既有 GPTK；CompatDB policy 是 Cyder app
提供的 `.cdb`，不可把 `cxcompatdb.so` 誤當成 policy database。若 GPTK 不在標準
位置，可補上 `--gptk-root PATH`。真實登入測試再把 BeanFun host、port、ServiceAccountID 與 OTP
放在 `--` 後面；OTP 不會寫入 launcher summary log。

驗收順序固定為：

1. 乾淨 prefix / `MapleTest` cwd 的無 OTP lifecycle。
2. 有效 OTP 登入與角色選擇。
3. 進入地圖後確認地圖、UI、滑鼠與音訊。
4. 連續遊玩 20 分鐘，記錄 BlackCipher/NGS 是否持續存活與 CPU/GPU/能耗觀察。
5. 若失敗，先依 log 判斷是認證、anti-cheat lifecycle、renderer 初始化或畫面交接，
   再決定是否需要下一組 patch；不要先切換到 MoltenVK。
