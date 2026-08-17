# CX26 新楓之谷移植工作紀錄

> CX25 OEM 產品線與 `--cx 25` 建置已退役。現行路徑是正式 Cyder.app + CX26。本文保留為研究紀錄。

> 目標：只維護 CX26 engine，使用 D3DMetal/GPTK 啟動
> `/Users/jjc/games/tms/MapleStory.exe`，並實際到達登入畫面。CX25 OEM 保留作為
> 可比對的已知正常基準。D3DMetal 路徑不引入 MoltenVK；MoltenVK 僅屬於另行驗證的
> DXVK 路徑。

## 測試固定條件

- 遊戲目錄：`/Users/jjc/games/tms`
- 目標檔案：`/Users/jjc/games/tms/MapleStory.exe`
- CX25 基準 prefix：`maplestory-oem25`
- CX26 測試 engine：`/Users/jjc/cyder-wine-engine/install/wine-cx26-x86_64`
- 圖形後端：D3DMetal/GPTK
- CX26 每次測試都使用獨立 prefix、log 目錄，並由 launcher 強制注入
  `CYDER_GRAPHICS_BACKEND=d3dmetal`、GPTK 路徑與 CompatDB `.cdb`。

WZ parser、第一次攻擊卡頓、userspace cache、slot capacity、mmap 與低干擾
I/O 實驗的完整數據，另見
[`maplestory-cx26-wz-cache-experiments.zh-TW.md`](maplestory-cx26-wz-cache-experiments.zh-TW.md)。

## 目前結論（持續更新）

CX26 已能載入 MapleStory、BlackCipher、GR2D_DX11、DwarfAxe，並進入 macOS
window surface 的 present 迴圈；但使用者確認視窗仍是黑畫面，只看得到新楓之谷
造型鼠標。因此目前問題已縮小到 renderer 產生/匯入/提交 frame 的內容，或
D3DMetal surface handoff，而不是工作目錄、CompatDB、GPTK 選擇或 MapleStory
process 啟動。

## 測試與修改紀錄

### 2026-08-15：建立 CX26 production stack

- 修改：新增並註冊 CX26-only MapleStory patch stack，包含：
  `core`、TMP module name、DwarfAxe dbghelp guard、D3D11 shared texture、
  ClearView、DXGI shared handle、texture user-memory reload、BlackXchg foreground、
  fullscreen restore、scheduler-yield workaround。
- 修改：新增 D3DMetal launcher；launcher 要求明確的 CompatDB `.cdb`，固定
  D3DMetal/GPTK，且不檢查或掛載 MoltenVK。
- 修改：新增 patch-stack、launcher contract 與 shell regression tests。
- 建置：
  `bash scripts/build-wine.sh --cx 26 --maplestory --without-vulkan --jobs 8`
- 效果：CX26 engine 成功建置至
  `install/wine-cx26-x86_64`。

### 2026-08-15：CX26 初次 D3DMetal 啟動

- 測試：以錯誤的 CompatDB 路徑啟動。
- 效果：log 顯示 `CompatDB unavailable`；此結果判定為測試配置錯誤，不作為
  graphics regression 證據。

### 2026-08-15：修正 CompatDB 後的 CX26 測試

- 修改：launcher 改為要求實際存在的 `.cdb`，避免缺少 policy 時靜默進入錯誤
  fallback。
- 測試 log：`.maplestory-cx26-logs-cdb2/maplestory-cx26-d3dmetal-20260815-002431-83920.log`
- 效果：log 重複確認 `loaded CompatDB v1 rules=3`、CX26 選到 D3DMetal GPTK，
  並載入 MapleStory、BlackCipher、GR2D_DX11、DwarfAxe；使用者回報黑畫面、
  但遊戲鼠標存在。

### 2026-08-15：CX26 Retina/window 變體

- 測試：調整 window/Retina 相關條件，保持同一遊戲目錄、GPTK、CompatDB 與
  CX26 engine。
- 測試 log：`.maplestory-cx26-logs-retina/maplestory-cx26-d3dmetal-20260815-003331-86857.log`
- 效果：仍為黑畫面；因此單純 Retina/window 尺寸不是已證實的修正。

### 2026-08-15：CX26 無 Maple patch diagnostic build

- 測試：用乾淨 common-only CX26 source 建立
  `install/wine-cx26-nomaple-x86_64`，作為反向控制。
- 效果：MapleStory 在 graphics initialization 前即因未處理 division-by-zero
  crash；證明 MapleStory 需要既有 compatibility patches，不能把「移除全部
  Maple patches」當作有效的畫面 A/B。

### 2026-08-15：CX25 OEM 正常登入基準

- 測試：使用 CX25 OEM wrapper 的 `--workdir /Users/jjc/games/tms`，並用
  `--cx-log`、`--debugmsg` 開啟可比對的 loader、SEH、D3D11、DXGI、wined3d 與
  macOS window events。
- 基準 log：`.maplestory-cx25-comparable-full.log`
- 效果：使用者確認已進入登入畫面；log 大小約 104 MB、797,987 行。
- 關鍵 marker：`MapleStory.exe`、`BlackXchg.aes`、`BlackCall64.aes`、
  `BlackCipher64.aes`、`GR2D_DX11.DLL`、`DwarfAxe.exe`、`jypc.dll`、
  `dxgi_factory_CreateSwapChain`、`d3d11_device_context_ClearView`。

補充校正：上面那份 `.maplestory-cx25-comparable-full.log` 的第一次擷取沒有
傳入 `CYDER_GPTK_ROOT`，因此部分 child process 走了 `fallback=wined3d`；它
保留作為歷史/ fallback 比較，不作為純 D3DMetal 的基準。之後用明確的 GPTK
環境重新擷取：

- 純 D3DMetal 基準 log：`.maplestory-cx25-d3dmetal-comparable.log`
  （約 1.46 MB、13,205 行）。
- 主程序的 x86_64 loader 選擇 D3DMetal 15 次；另有 1 次 i386 fallback，與
  CX25 的 32 位元輔助程序行為一致。
- 主程序載入 GPTK 外部的 `d3d11.dll`、`dxgi.dll`，並載入
  `GR2D_DX11.DLL`、`DwarfAxe.exe`；因此 Wine 內建 `d3d11` trace 不是這條
  D3DMetal 路徑的可靠 frame 進度指標。
- 這份 log 的執行被手動停止，但 CX25 能到登入畫面的事實以使用者先前的
  視覺確認為準。

### 2026-08-15：CX25/CX26 event comparison

- 正確的 CX25 D3DMetal 基準與 CX26 都會從 GPTK 路徑載入外部
  `d3d11.dll`/`dxgi.dll`，都載入 MapleStory、BlackCipher、GR2D_DX11 與
  DwarfAxe；所以現有 Wine `dlls/d3d11` shared-texture patch 並不是主程序
  D3DMetal renderer 的直接實作。
- CX26 diagnostic log：
  `.maplestory-cx26-logs-d3dmetal-hook/maplestory-cx26-d3dmetal-20260815-013751-37700.log`。
  它在 `GR2D_DX11.DLL` 載入後完成
  `get_win_data -> create_metal_device -> create_metal_view -> get_metal_layer`
  流程，並反覆出現 `macdrv_client_surface_presented`/
  `macdrv_client_surface_present`；使用者仍回報黑畫面。
- 目前 CX26 的 `winemac.drv/d3dmetal.c` 與 CX25 OEM source 的關鍵差異是：
  CX26 每次建立 DXGI swapchain 都建立新的 `macdrv_client_surface`，以
  `WineMetalLayer nextDrawable` 發送 `CLIENT_SURFACE_PRESENTED`；CX25 OEM
  則直接把既有 `cocoa_view`/`client_cocoa_view` 傳給 D3DMetal，沒有這個
  client-surface event bridge。這使 D3DMetal surface handoff 成為下一個
  可驗證的 A/B 變因。

### 2026-08-15：A/B 停用 CX26 D3DMetal event bridge

- 修改：新增 `patches/maplestory-cx26-d3dmetal-legacy-surface.patch`。它保留
  CX26 client surface 的建立、保存與 D3DMetal layer 建立，只在設定
  `CYDER_MAPLESTORY_LEGACY_D3DMETAL_SURFACE=1` 時停用
  `nextDrawable -> CLIENT_SURFACE_PRESENTED` 關聯；未設定時維持原本行為。
- 建置：重新執行
  `bash scripts/build-wine.sh --cx 26 --maplestory --without-vulkan --jobs 8`，
  編譯成功；patch-stack 與 launcher regression tests 均 PASS。
- 測試 log：
  `.maplestory-cx26-logs-legacy-surface/maplestory-cx26-d3dmetal-20260815-015637-49266.log`
- log 效果：候選版本載入 MapleStory、BlackCipher、`GR2D_DX11.DLL`、三個
  DwarfAxe process，完成 `get_win_data -> create_metal_device ->
  create_metal_view -> get_metal_layer`；同時未再出現原本約數千次的
  `macdrv_client_surface_presented` bridge marker。這是第一個與 CX25 OEM
  surface handoff 相同方向的可執行 A/B。
- 視覺驗收：候選程序已保持開啟，等待使用者確認是否進入登入畫面；在確認前
  不將此 variant 標記為成功。

### 2026-08-15：測試環境清理

- 問題：一次高噪音 `+process,+seh` diagnostic run 使多個測試 prefixes 累積
  約 8 GB，造成 `No space left on device`；另一次非 GUI 權限啟動則被
  `server_mach_port` 擋下。兩者都不是 engine 畫面結果。
- 處理：保留各次 log 與本工作紀錄，只移除本輪建立的 CX26 diagnostic test
  prefixes，釋放磁碟後以必要的 macOS GUI/Mach 權限及低噪音 log 重新啟動
  上述 A/B 候選。

### 2026-08-15：準備 CX26 plain CAMetalLayer A/B

- 前一個 `CYDER_MAPLESTORY_LEGACY_D3DMETAL_SURFACE=1` 候選仍能完成
  D3DMetal device/view/layer 初始化，但尚未取得使用者的登入畫面視覺確認；
  已保留 log，並結束該測試程序以避免與下一輪共用 prefix。
- 假設：CX26 目前的 `WineMetalLayer` 自訂 `nextDrawable` subclass／backing
  layer 可能仍與 CX25 OEM 直接使用 `CAMetalLayer` 的路徑不同。下一輪只改變
  backing layer 類別，保留其 device、framebufferOnly、filter、背景色與
  contentsScale 設定。
- 修改：新增 `patches/maplestory-cx26-plain-metal-layer.patch`，只有設定
  `CYDER_MAPLESTORY_PLAIN_METAL_LAYER=1` 時改用原生 `CAMetalLayer`；未設定
  時保留 `WineMetalLayer`。同時把 patch 加入 CX26 build stack、release
  manifest 與 patch-stack test。
- 尚未建置或啟動；下一步先做 patch dry-run／stack test，再以獨立 prefix
  建置並啟動相同遊戲、work dir、GPTK 與 CompatDB。

### 2026-08-15：CX26 plain CAMetalLayer A/B 結果

- 建置：完成 patch dry-run；重新執行
  `bash scripts/build-wine.sh --cx 26 --maplestory --without-vulkan --jobs 8`，編譯與安裝成功；
  `tests/test-maplestory-patch-stack.sh` 與 `tests/test-maplestory-d3dmetal-launcher.sh` 均 PASS。
- 啟動：使用獨立 prefix `.maplestory-cx26-test-plain-layer`，遊戲工作目錄為
  `/Users/jjc/games/tms`，外部 GPTK 與 CompatDB 與 CX25 基準相同；啟用
  `CYDER_MAPLESTORY_LEGACY_D3DMETAL_SURFACE=1` 及
  `CYDER_MAPLESTORY_PLAIN_METAL_LAYER=1`。
- log：`.maplestory-cx26-logs-plain-layer/maplestory-cx26-d3dmetal-20260815-020744-56982.log`。
- 效果：仍載入 MapleStory、BlackCipher、`GR2D_DX11.DLL` 與 DwarfAxe，並完成
  `get_win_data -> create_metal_device -> create_metal_view -> get_metal_layer`；
  但沒有新增主遊戲 `CreateSwapChain`/主畫面 present 的證據，仍未看見
  `jypc.dll`。停用 CX26 client-surface event bridge 並改用原生
  `CAMetalLayer` 都沒有把程序推進到 CX25 基準的主遊戲 renderer 階段。
- 驗收：此輪沒有取得使用者的登入畫面確認，因此不標記成功；候選程序已結束，
  log 保留供後續比對。
- 判斷：surface/backing-layer 不是目前最有力的阻塞點；下一輪改測 CX25 OEM
  log 中實際存在、而現有 CX26 launcher 尚未重現的啟動環境 parity，仍維持
  一次只改一個可辨識邏輯群組。

### 2026-08-15：CX25 OEM 啟動環境 parity A/B 準備

- 比對依據：正常 CX25 D3DMetal log 在 `GR2D_DX11.DLL`、DwarfAxe 之後載入
  `jypc.dll`；CX26 plain-layer log 沒有這個 marker。OEM launcher 的實際環境
  另外固定 `CYDER_MSYNC=1`、`CYDER_ESYNC=0`、
  `CYDER_WINE_DIAGNOSTICS=quiet`、`MTL_HUD_ENABLED=1`，而 CX26 launcher 原本
  沒有把它們傳入 `arch -x86_64 env` 的 child。
- 修改：將這四個變數加入 CX26 D3DMetal launcher 的預設值、啟動環境與 launch
  summary；仍可由外部環境覆寫，且沒有改變 D3DMetal／MoltenVK 選擇。
- 驗證：`bash -n scripts/run-maplestory-cx26-d3dmetal.sh`、
  `bash tests/test-maplestory-d3dmetal-launcher.sh` 與 `git diff --check` 均 PASS；
  dry-run 顯示四個值會進入 launch plan。
- 下一步：以這個單一環境 parity 群組重新建置（launcher 變更本身不需重編 Wine），
  使用獨立 prefix 啟動並檢查是否出現 `jypc.dll`／主遊戲 swapchain；若仍停在
  相同階段，保留 log 後再縮小到 NGS／啟動流程差異。

### 2026-08-15：CX25 OEM 啟動環境 parity A/B 結果

- 啟動：用上一個 CX26 build，獨立 prefix `.maplestory-cx26-test-env-parity`，
  啟用同一組 surface A/B，launcher 額外傳入 `CYDER_MSYNC=1`、
  `CYDER_ESYNC=0`、`CYDER_WINE_DIAGNOSTICS=quiet`、`MTL_HUD_ENABLED=1`。
- log：`.maplestory-cx26-logs-env-parity/maplestory-cx26-d3dmetal-20260815-021640-60452.log`。
- 效果：CX26 確實建立 `NGService.exe`，並載入 `GR2D_DX11.DLL`、`LSFG.dll`、
  DwarfAxe；但仍沒有 CX25 基準中的 `HybridCore64.dll`、`jypc.dll`、主遊戲
  `CreateSwapChain` 或主畫面 present。環境 parity 沒有把程序推進到下一階段。
- 驗收：沒有登入畫面確認；候選程序已結束，log 保留。這組 launcher 環境修正
  目前只改善了啟動契約的一致性，尚不能列為黑畫面修復。
- 判斷：研究分支文件記錄自行編譯的 OEM/CX engine 在 host `Z:` 路徑可能停在
  `jypc` 之前，而實體 `C:\MapleTest` 曾成功載入 `jypc`；下一輪只切換遊戲
  路徑，其他 engine、prefix、GPTK、CompatDB 與環境保持不變。

### 2026-08-15：CX26 D3DMetal direct-view A/B

- 修改：新增 `maplestory-cx26-d3dmetal-direct-view.patch`。設定
  `CYDER_MAPLESTORY_DIRECT_D3DMETAL_VIEW=1` 時，CX26 `winemac.drv/d3dmetal.c`
  不建立 CX26 專用 `macdrv_client_surface`，改把既有視窗的 `client_view`
  填入 D3DMetal 相容資料；未設定時保留原本 client-surface 路徑。此 patch
  與前一個 legacy event bridge A/B 分開，便於辨識效果。
- 驗證：patch dry-run、`tests/test-maplestory-patch-stack.sh` 與
  `git diff --check` 均 PASS。重新執行
  `bash scripts/build-wine.sh --cx 26 --maplestory --without-vulkan --jobs 8`，
  編譯、安裝與 minOS 10.15 檢查成功。
- 下一步：以最新 build、獨立 prefix、D3DMetal/GPTK、CompatDB 與
  `CYDER_MAPLESTORY_LEGACY_D3DMETAL_SURFACE=1` 啟動，這次只新增
  `CYDER_MAPLESTORY_DIRECT_D3DMETAL_VIEW=1`；先比對 `jypc.dll`／主遊戲 renderer，
  再請使用者確認畫面。

### 2026-08-15：CX26 D3DMetal direct-view A/B 結果

- 測試：使用最新 build、原始 `/Users/jjc/games/tms/MapleStory.exe`、獨立
  prefix `.maplestory-cx26-test-direct-view`，啟用
  `CYDER_MAPLESTORY_LEGACY_D3DMETAL_SURFACE=1` 與
  `CYDER_MAPLESTORY_DIRECT_D3DMETAL_VIEW=1`；plain-layer 未啟用。
- log：`.maplestory-cx26-logs-direct-view/maplestory-cx26-d3dmetal-20260815-022759-65988.log`。
- 效果：direct-view patch 確實繞過了 client-surface 建立，但 CX26 的
  `macdrv_win_data.client_view` 在這個時機是空值；log 顯示
  `create_metal_view ... 0x0`、`get_metal_layer 0x0`，所以沒有進入可用的
  D3DMetal layer，也沒有 `jypc.dll` 或主遊戲 renderer。這不是成功候選，且
  不能把 CX25 舊資料結構直接套到 CX26。
- 驗收：未取得登入畫面；候選已結束，log 保留。direct-view patch 暫列負面
  實驗，不應進入最後保留的 patch 組合。
- 判斷：CX26 的 client view 是由 `macdrv_client_surface_create()` 建立並掛入
  window data，下一輪不再重複這個會產生空 view 的直通模型；回到 CX26 的
  client-surface handoff，改查它與 CX25 到達 `jypc` 前的其他差異。

### 2026-08-15：CX26 clean stack 與 OEM prefix clone 自動驗證

- 建置校正：移除 direct-view 實驗的正式 stack registration 後，先從增量 source
  tree 反向移除殘留 patch，再重新執行
  `bash scripts/build-wine.sh --cx 26 --maplestory --without-vulkan --jobs 8`。
  安裝完成的 `install/wine-cx26-x86_64` 不再包含
  `CYDER_MAPLESTORY_DIRECT_D3DMETAL_VIEW` 字串；patch-stack 與 launcher tests
  維持 PASS。
- clean prefix 測試：使用全新 prefix
  `.maplestory-cx26-test-cleanstack`，log 為
  `.maplestory-cx26-logs-cleanstack/maplestory-cx26-d3dmetal-20260815-024323-77129.log`。
  它載入 `GR2D_DX11.DLL`、建立非空 D3DMetal device/view/layer，並持續產生約
  623 次 `macdrv_client_surface_presented`；但在 `--no-otp` 啟動下沒有
  `jypc.dll`、`HybridCore64.dll` 或主遊戲 `CreateSwapChain` marker，未改善已知
  黑畫面階段。
- prefix A/B：把已知可啟動的 CX25 OEM prefix 以 APFS clone 複製成
  `.maplestory-cx26-test-oem25-prefix`，只替換 prefix、保留同一 CX26 binary、
  遊戲目錄、GPTK、CompatDB 與 launcher 環境。log 為
  `.maplestory-cx26-logs-oem25-prefix/maplestory-cx26-d3dmetal-20260815-025230-80015.log`。
  結果仍停在 `GR2D_DX11 -> D3DMetal device/view -> DwarfAxe`，有約 4,367 次
  client-surface present，但沒有 `jypc.dll`、`HybridCore64.dll` 或主遊戲
  `CreateSwapChain`；prefix 內容不是目前已證實的差異來源。
- 程序取樣：對 CX26 主程序取樣結果顯示主執行緒在 Cocoa run loop，並有
  `D3DMetalWineThread`、`DXGISwapChain::Present1`、
  `D3DMCommandQueueWorker::DoPresent`；這證明程序仍活著且有提交 render work，
  但不證明 frame 已交給可見的 macOS window。取樣檔：
  `/private/tmp/maplestory-cx26-oem25-prefix.sample.txt`。
- 視窗自動擷取：`CGWindowList` 能看到 Wine window（1366x796），但其 sharing
  state 為不可分享；`screencapture -l` 無法建立該視窗影像，ScreenCaptureKit
  也被 macOS TCC 拒絕。全桌面擷取檔
  `/private/tmp/maplestory-cx26-cleanstack-screen.png` 只包含桌面背景，不能
  當作登入畫面證據。因此本輪沒有可靠的自動影像驗收。
- 驗收結論：上述 telemetry 只能排除「立即 crash／完全沒有 D3DMetal render
  work」，不能排除「提交到錯誤或不可見 surface」；在沒有有效 BeanFun/OTP
  啟動參數時，`jypc` 缺席也不能單獨視為登入失敗的唯一原因。不把本輪標記為成功。
- 清理：已停止測試程序並保留 log；本輪產生的兩個測試 prefix 可安全移除，原始
  CX25 OEM prefix、遊戲目錄、engine source 與所有 log 不受影響。

### 2026-08-15：CX26 主視窗 resizable flag A/B 與系統層驗證

- 假設：CX25 正常基準的主 MapleStory window event 沒有
  `WINE_SWP_RESIZABLE`（flags 沒有 `0x40000000`），但 CX26 先前在標題設為
  `MapleStory` 後仍保留 `40001963`；這可能讓 macOS backend 對主視窗採用不同
  的 backing/window state。
- 修改：新增並註冊 `patches/maplestory-cx26-window-resizable-flag.patch`。
  `win32u/window.c` 以 class `MapleStoryClass` 或標題 `MapleStory` 識別主視窗，
  並在計算 `WINE_SWP_RESIZABLE` 時排除該視窗；其他程式與其他 MapleStory
  auxiliary windows 不變。
- 建置：
  `bash scripts/build-wine.sh --cx 26 --maplestory --without-vulkan --jobs 8`
  完成；`tests/test-maplestory-patch-stack.sh`、
  `tests/test-maplestory-d3dmetal-launcher.sh` 與 `git diff --check` 均 PASS。
- 測試 log：
  `.maplestory-cx26-logs-windowtitleflag/maplestory-cx26-d3dmetal-20260815-031619-92356.log`。
  使用獨立 prefix `.maplestory-cx26-test-windowtitleflag`、相同遊戲目錄、D3DMetal/
  GPTK、CompatDB 與 launcher 環境；本次仍用 `--no-otp`，所以只作生命週期與
  renderer smoke test。
- 效果：主視窗 `0x40036` 在標題設定後的 flags 由先前的 `40001963` 改為
  `00001963`，並在後續 frame/window events 維持沒有 `0x40000000`；初始建立
  event 在標題尚未設定時仍為 `4000003c`，符合只在可辨識主視窗後套用的設計。
  這項 A/B 已證實修正了與 CX25 基準不同的 window flag。
- renderer telemetry：log 有約 7,397 次
  `macdrv_client_surface_presented`，主視窗為 `0x40036`；沒有 crash，且
  sample `/tmp/wine_2026-08-15_031802_JuaD.sample.txt` 顯示
  `DXGISwapChain::Present1`、`D3DMetalWineThread` 與
  `D3DMCommandQueueWorker::DoPresent` 正在工作。這證明 frame work 有提交，
  但不證明提交內容已可見，也不代表已到登入畫面；`--no-otp` 下仍沒有
  `jypc.dll`、`HybridCore64.dll` 或 `CreateSwapChain` marker。
- 系統層影像驗證：嘗試擷取目前桌面，檔案為
  `/private/tmp/maplestory-cx26-windowtitleflag-screen.png`；結果只有桌面背景，
  Wine window 沒有進入可擷取的桌面影像，因此不能把它當作黑畫面或登入畫面的
  證據。最後驗收仍需有效 BeanFun argv 加上可見畫面，或由使用者確認登入畫面。
- 結論：保留此 patch 作為正式 stack 的候選，因為它已使 CX26 主視窗 telemetry
  對齊 CX25；但本輪尚未證明 CX26 到達登入畫面，不能標記為成功。

### 2026-08-15：CX26 macOS 視窗擷取診斷（測試專用，未納入 formal stack）

- 目的：使用不需要使用者在場的像素層驗證，區分「D3DMetal 有提交 frame」與
  「frame 實際可見」。在生成的 `cocoa_window.m` 暫時加入
  `NSWindowSharingReadOnly` 與唯讀 diagnostic，並以
  `arch -x86_64 make -C build/cx26/sources/wine/build64
  dlls/winemac.drv/winemac.so -j8` 建置；這段程式沒有寫入 patch stack，測試後
  已從 source 移除，安裝的正式 `winemac.so` 也已由備份還原。
- 測試：使用同一個 `/Users/jjc/games/tms` work dir、CX26 D3DMetal/GPTK、CompatDB
  與 `--no-otp`，在數個全新隔離 prefix 執行。主要 log 為
  `.maplestory-cx26-logs-capture4/maplestory-cx26-d3dmetal-20260815-033937-98676.log`；
  前兩次診斷 log 保留在 `.maplestory-cx26-logs-capture/`、
  `.maplestory-cx26-logs-capture2/`、`.maplestory-cx26-logs-capture3/`。
- 讀回結果：CX26 主視窗建立時 diagnostic 回報 `sharing=1`，且主視窗仍有大量
  `macdrv_client_surface_presented`；但 macOS `CGWindowList` 對同一個 Wine 主視窗
  仍回報 sharing state `0`，`screencapture -l` 無法建立視窗影像。把 Wine 設為
  前景後擷取整個螢幕，檔案
  `/private/tmp/maplestory-cx26-capture3-fullscreen-front.png` 只包含桌面背景，
  沒有可判讀的遊戲像素。這表示目前 macOS capture path 排除 Wine/D3DMetal 視窗，
  不能據此宣稱黑畫面，也不能據此宣稱登入畫面。
- 清理：已停止所有 capture 測試、還原正式 CX26 runtime、移除本輪建立的隔離
  test prefixes；遊戲目錄、CX25 OEM prefix、engine source 與上述 logs 保留。
- 驗收：本輪仍未取得可見登入畫面；`--no-otp` 也只代表 renderer smoke test，
  不改變「必須有有效 BeanFun argv 並取得可見登入畫面」的最終條件。

### 2026-08-15：補做完整 DXGI/D3D11 trace

- 原因：前幾輪為了降低 log 量自訂了 WINEDEBUG，沒有啟用 `+dxgi`；因此不能
  僅以缺少 `CreateSwapChain` marker 判斷 CX26 未走到 swap-chain。
- 測試：以目前正式 CX26 binary、同一遊戲目錄/work dir、GPTK、CompatDB 與
  `--no-otp`，使用完整
  `+timestamp,+pid,+process,+loaddll,+seh,+winediag,+d3d11,+dxgi,+wined3d,+macdrv,+macdrv_d3dmtl`
  啟動全新隔離 prefix。log：
  `.maplestory-cx26-logs-dxgi/maplestory-cx26-d3dmetal-20260815-034441-203.log`。
- 結果：log 確認載入 `GR2D_DX11.DLL`、`d3d11.dll`、`dxgi.dll`、`wined3d.dll`，
  並進入 CX26 D3DMetal bridge 的 `macdrv_create_metal_device`、非空 view/layer
  與約 1,390 次 `macdrv_client_surface_presented`。但仍沒有
  `jypc.dll`、`HybridCore64.dll`，也沒有 Wine DXGI channel 的
  `dxgi_factory_CreateSwapChain`；同時 CompatDB 曾記錄 i386 backend 缺少
  `d3d11.dll/dxgi.dll` 並 fallback 到 wined3d。這指出目前是「CX26 D3DMetal
  bridge 有提交，但沒有得到可驗收的登入階段」；仍不能宣稱已成功顯示登入畫面。
- 清理：停止本輪 MapleStory 與由本輪測試遺留的 NxOverlay 子程序，移除隔離
  prefix，保留 log。正式 CX26 runtime 未被此 A/B 改動。

### 2026-08-15：macOS accessibility/UI 層交叉驗證

- 以 macOS accessibility bridge 查詢已啟動的 CX26 smoke test；系統 app registry
  只列出 Cyder app bundle（當時未執行），沒有把 Rosetta/Wine 的
  `MapleStory.exe` 註冊成可供 UI bridge 讀取的 app。以 `wine` 或 exe 絕對路徑
  直接查詢也回報 invalid app，因此沒有取得可讀的 accessibility tree 或 UI
  screenshot。
- 這與前一節的 `CGWindow`／`screencapture` 結果一致：目前環境不能以系統 UI
  API 讀取這個 Wine/D3DMetal surface；保留 log 作為程序層證據，不把 UI API
  無法接管誤判成遊戲本身的畫面結果。隔離 prefix 已清理。

### 2026-08-15：以 CX25 baseline 的 MSync=0 做 CX26 單一變因 A/B

- 比對修正：`/Users/jjc/Library/Application Support/Cyder-maplestory-oem25/Logs/sessions/last-wine-launch.log`
  記錄 CX25 成功路徑使用 `CYDER_MSYNC=0`、`CYDER_ESYNC=0`；先前 CX26 launcher
  的預設值是 MSync=1。因此本輪只把 MSync 設為 0，沒有改 patch、D3DMetal/GPTK、
  work dir、CompatDB 或遊戲目錄。
- 測試命令：以 `CYDER_MSYNC=0 CYDER_ESYNC=0` 執行
  `scripts/run-maplestory-cx26-d3dmetal.sh --launch-exe
  /Users/jjc/games/tms/MapleStory.exe --no-otp`，完整 trace 保留在
  `.maplestory-cx26-logs-msync0/maplestory-cx26-d3dmetal-20260815-035840-3045.log`。
- 效果：CX26 仍載入 `GR2D_DX11.DLL`、建立 D3DMetal view/layer、啟動 DwarfAxe，
  約有 1,765 次 `macdrv_client_surface_presented`；仍沒有
  `HybridCore64.dll`、`jypc.dll` 或可確認的登入畫面。MSync 不是目前把 CX26
  推進到 CX25 同一生命週期的分歧。
- 清理：已停止隔離程序、移除本輪 prefix，保留 log；正式 launcher 預設與正式
  runtime 沒有因 A/B 被改寫。

### 2026-08-15：CX25 Retina/DPI registry parity A/B

- 假設：CX25 成功基線的 prefix 具有 `RetinaMode=y`、`LogPixels=192`；先前
  CX26 候選只回報 `1680x945`，可能使 D3DMetal drawable/backing scale 與正常路徑不同。
- 測試：建立隔離 CX26 prefix，先以同一套 CX25 golden registry 設定寫入
  `RetinaMode=y`、`LogPixels=192`，再用正式 CX26 patch stack、D3DMetal/GPTK、
  `/Users/jjc/games/tms` work dir、`CYDER_MSYNC=0` 與 `--no-otp` 啟動。
- log：`.maplestory-cx26-logs-retina-current/maplestory-cx26-d3dmetal-20260815-040721-5401.log`
- 效果：CX26 確實回報與 CX25 相同的 macOS desktop rect `3360x1890`，並載入
  `GR2D_DX11.DLL`、DwarfAxe、D3DMetal layer/present；但仍沒有
  `HybridCore64.dll`、`jypc.dll` 或可比對的 `CreateSwapChain`，所以 Retina/DPI
  不是目前已證實的阻塞點，也不能視為登入畫面成功。
- 清理：已停止本輪隔離程序；保留 log 供比較，正式 CX26 runtime 與 CX25 prefix
  未被覆寫。

### 2026-08-15：有效 CX25 OEM D3DMetal 基準 log

- 基準：使用 CX25 OEM 的直接 wrapper 啟動，同時指定 CX25 bottle/root、`WINEARCH=win64`、
  `CYDER_GRAPHICS_BACKEND=d3dmetal`、GPTK、CompatDB、media runtime、正確的
  `/Users/jjc/games/tms` work dir，以及完整 D3DMetal/D3D11/DXGI trace。有效 log：
  `.maplestory-cx25-d3dmetal-true-20260815-wrapper-win64-2.log`。
- 生命週期：log 依序出現 `MapleStory.exe`、`GR2D_DX11.DLL`、CX25 的
  `macdrv_d3dmtl` device/view/layer、`DwarfAxe.exe`、`HybridCore64.dll`、
  `jypc.dll`，並完成主視窗 1920x1080 client resize。此路徑沒有 CX26 的
  `macdrv_client_surface_presented` event bridge；使用者已確認這次實際進入登入畫面。
- 用途：這份 log 是目前唯一同時具備「正確 CX25 D3DMetal 環境」與「登入畫面已由使用者確認」
  的比對基準。`CreateSwapChain` 文字不是可靠 marker，因為主要實作來自外部 GPTK PE。

### 2026-08-15：GPTK framework path A/B

- 修改：只額外設定 `DYLD_FRAMEWORK_PATH=$GPTK_ROOT/external`，其餘 CX26 formal
  stack、D3DMetal、work dir、CompatDB、`CYDER_MSYNC=0` 與 prefix 條件不變。
- log：`.maplestory-cx26-logs-gptk-framework/maplestory-cx26-d3dmetal-20260815-041207-6484.log`。
- 效果：CX26 仍有非零 D3DMetal view/layer 與約 409 次 surface-present event，
  但沒有 `HybridCore64.dll`、`jypc.dll` 或可確認登入畫面；framework search path
  不是已證實的分歧，沒有保留正式 source 變更。

### 2026-08-15：reuse existing client view A/B（負面結果，已撤回 formal stack）

- 修改：新增暫時 patch `maplestory-cx26-d3dmetal-reuse-client-view.patch`。在
  `my_get_win_data()` 中先取既有 `data->client_view`；若首次呼叫尚未存在，才建立一次
  fallback client surface 後重新取得 window data，並把同一個 view 交給 D3DMetal，跳過
  `macdrv_set_view_d3dmetal_client_surface()` event bridge。這是針對 CX25「直接使用既有
  visible client view」的最小 A/B，不包含 direct-view 的過早取用問題。
- 建置與測試：patch stack test 通過，CX26 D3DMetal runtime 完成重建。以全新 prefix、
  `CYDER_MAPLESTORY_REUSE_CLIENT_VIEW=1`、`CYDER_MSYNC=0`、`--no-otp` 執行 65 秒；
  log：`.maplestory-cx26-logs-reuse-client-view-20260815-0438/maplestory-cx26-d3dmetal-20260815-044121-15897.log`。
- 效果：CX26 建立了非零 fallback view，`macdrv_view_create_metal_view` 與
  `macdrv_view_get_metal_layer` 都是非零指標；reuse 分支也確實沒有
  `client_surface_presented` event。但首次 D3DMetal 取 view 時沒有既有 view，最後仍只
  載入 `GR2D_DX11.DLL` 與 3 次 `DwarfAxe.exe`，沒有 `HybridCore64.dll` 或 `jypc.dll`。
  因此 event bridge/取 view 方式不是足以讓 CX26 進入 CX25 同一 renderer 生命週期的修正，
  不能宣稱已到登入畫面。
- 結論：已把此 patch 從 `scripts/build-wine.sh`、`config/engine-release.json`、
  patch-stack test 與 patch README 的正式清單撤回；patch 檔與 log 保留作為負面實驗紀錄。
  之後會先恢復乾淨 formal CX26 binary，再繼續下一個單一變因。

### 2026-08-15：populate D3DMetal cocoa view A/B（負面結果，已撤回 formal stack）

- 修改：新增暫時 patch `maplestory-cx26-d3dmetal-populate-cocoa-view.patch`，只在
  `CYDER_MAPLESTORY_POPULATE_D3DMETAL_COCOA_VIEW=1` 時，把 CX26 新建立的
  `client_surface->cocoa_view` 同步填入 D3DMetal private data 的舊式 `cocoa_view` 欄位。
  其餘 client view、surface-present event bridge、D3DMetal/GPTK、work dir 與 registry
  條件不變；目的是驗證外部 GPTK 是否仍依賴 CX25 版本存在的欄位。
- 建置與測試：patch stack test 通過，CX26 runtime 完成重建。以全新 prefix、
  `CYDER_MAPLESTORY_POPULATE_D3DMETAL_COCOA_VIEW=1`、`CYDER_MSYNC=0`、`--no-otp`
  執行約 65 秒；log：
  `.maplestory-cx26-logs-populate-cocoa-view-20260815-0515/maplestory-cx26-d3dmetal-20260815-045258-22693.log`。
- 效果：candidate 確實走到 `macdrv_create_metal_device`、非零 Metal view/layer，
  也有 1,468 次 `macdrv_client_surface_presented`；載入 `GR2D_DX11.DLL` 與 3 次
  `DwarfAxe.exe`。但第三次 DwarfAxe 在 `69540.237` 後，直到測試結束仍沒有
  `HybridCore64.dll` 或 `jypc.dll`；CX25 基準則在第三次 DwarfAxe `67675.100` 後
  約 246 ms 就載入 `HybridCore64.dll`，接著載入 `jypc.dll`。因此填補舊式
  `cocoa_view` 欄位未讓 CX26 進入 CX25 的 renderer 生命週期，也不能視為登入畫面成功。
- 結論：已把此 patch 從 `scripts/build-wine.sh`、`config/engine-release.json`、
  patch-stack test 與 patch README 的正式清單撤回；patch 檔與 log 保留作為負面實驗紀錄。
  正式 CX26 runtime 將恢復不帶此候選的 formal stack。

### 2026-08-15：keep foreground A/B（負面結果，已撤回 formal stack）

- 修改：新增暫時 patch `maplestory-cx26-keep-foreground.patch`。在
  `macdrv_app_deactivated()` 保留 `NtUserClipCursor(NULL)`，但於
  `CYDER_MAPLESTORY_KEEP_FOREGROUND=1` 時略過
  `NtUserSetForegroundWindowInternal(NtUserGetDesktopWindow())`；目的在驗證 CX26
  第一次 DwarfAxe 啟動時的 foreground 轉移是否阻塞主程序。
- 建置與測試：patch stack test 通過，CX26 runtime 完成重建。以全新 prefix、
  `CYDER_MAPLESTORY_KEEP_FOREGROUND=1`、MSync=0、ESYNC=0、`--no-otp` 執行約
  65 秒；log：
  `.maplestory-cx26-logs-keep-foreground-20260815-0610/maplestory-cx26-d3dmetal-20260815-050326-30109.log`。
- 效果：log 中沒有 `macdrv_app_deactivated setting fg to desktop`，表示候選分支
  確實生效；但 DwarfAxe timing 仍為 `70163.294 -> 70166.511 -> 70167.190`
  （+3.217s、+0.679s），沒有 `HybridCore64.dll`／`jypc.dll`，只有 1,471 次
  `macdrv_client_surface_presented`。CX25 baseline 則是 +0.629s、+0.522s，
  並在第三次 DwarfAxe 後約 246 ms 載入 `HybridCore64.dll`。因此 foreground
  reset 不是目前阻塞 CX26 進入登入流程的原因。
- 結論：已從 build script、release manifest、patch-stack test 與 README 正式清單
  撤回此 patch；候選 patch 與 log 保留作為負面實驗紀錄。

### 2026-08-15：GDI BITSPIXEL parity A/B（負面結果，已撤回 formal stack）

- 假設：CX25 OEM 的 `winemac.drv/gdi.c` 會在 `GetDeviceCaps(BITSPIXEL)` 明確回傳
  螢幕色深（本機為 32），而 CX26 已移除這個分支。因為正常 CX25 的 DwarfAxe 啟動
  期間大量出現 `macdrv_GetDeviceCaps cap 12 -> 32`，所以暫時恢復 CX25 的
  `CGDisplayCopyDisplayMode`／pixel-encoding 判斷與 `BITSPIXEL` 回傳。
- 修改：新增暫時 patch `patches/maplestory-cx26-gdi-bits-per-pixel.patch`，並暫時
  註冊到 build script；沒有改 D3DMetal view、surface bridge、GPTK、CompatDB 或
  work dir。patch stack test 與 CX26 無 Vulkan runtime build 均通過；編譯只產生
  macOS deprecated API warning。
- 測試：使用全新 prefix、`CYDER_MSYNC=0`、`CYDER_ESYNC=0`、同一個
  `/Users/jjc/games/tms` work dir、D3DMetal/GPTK、CompatDB 與 `--no-otp`。
  log：`.maplestory-cx26-logs-gdi-bpp-20260815/maplestory-cx26-d3dmetal-20260815-052115-40198.log`。
- 效果：候選確實讓 CX26 在測試 log 中回報 `macdrv_GetDeviceCaps cap 12 -> 32`
  （共 1477 次 `macdrv_client_surface_present`）；但 DwarfAxe 仍為
  `71260.610 -> 71263.918 -> 71264.559`，主程序到 GPU 子程序約 3.3 秒，與
  CX26 既有約 3.2 秒延遲同量級。測試持續觀察後仍沒有 `HybridCore64.dll` 或
  `jypc.dll`，也沒有可視登入畫面證據，因此 BITSPIXEL parity 不是根因。
- 結論：已從 build script 移除並反向套用 patch，正式 CX26 runtime 再次以不含
  此候選的 formal stack 重建成功；候選 patch 與 log 保留作為負面實驗紀錄。
  本輪由我建立的 1.3 GiB 隔離 prefix 已清理以恢復磁碟空間，log 保留。

### 2026-08-15：自動化視窗／畫面交叉驗證（負面結果）

- 目的：在使用者不在電腦前時，使用本機視窗清單、macOS 桌面截圖與 Wine log
  交叉判斷 CX26 是否真的到達登入畫面；不輸入帳號、ServiceAccountID 或 OTP。
- 測試：以正式、已重新乾淨編譯的 CX26 runtime，獨立 prefix
  `.maplestory-cx26-test-automated-visual-20260815`、相同遊戲工作目錄、GPTK、
  CompatDB、`CYDER_MSYNC=0`、`CYDER_ESYNC=0` 與 `--no-otp` 執行。
- log：`.maplestory-cx26-logs-automated-visual-20260815/maplestory-cx26-d3dmetal-20260815-053213-46500.log`。
- 視窗檢查：macOS Accessibility/CGWindow 清單確實看到 `MapleStory` 視窗（約
  1366x796）；一般桌面截圖與指定視窗擷取無法合成 Wine x86 surface，所以沒有
  把桌面影像誤當成遊戲畫面。這也驗證了「視窗存在」不能取代可視畫面驗收。
- log 效果：CX26 產生約 15,443 次 `macdrv_client_surface_present`，但直到停止
  前沒有 `HybridCore64.dll`、`jypc.dll` 或 `CreateSwapChain` marker；沒有登入畫面
  的可視證據，因此正式 CX26 仍判定為未成功。
- 清理：停止本次由我啟動的 Wine/CX26 process；保留 log，並只清除已完成 A/B、
  且對應 log 已保留的舊測試 prefix 以釋放磁碟空間。正式 runtime、CX25 基準與
  遊戲目錄未變更。

### 2026-08-15：CX25 wrapper 環境 parity A/B（負面結果）

- 假設：正式 CX26 launcher 直接呼叫 `bin/wine`，而成功的 CX25 基準另外帶有
  `WINEARCH=win64` 與完整 `WINEDLLPATH`。本輪先不改 source 或正式 launcher，
  只在隔離 prefix 明確加入這兩個環境變數；D3DMetal/GPTK、CompatDB、media、
  `/Users/jjc/games/tms` work dir、`CYDER_MSYNC=0`、`CYDER_ESYNC=0` 與 `--no-otp`
  維持相同。
- log：
  `.maplestory-cx26-logs-env-parity-20260815/maplestory-cx26-d3dmetal-20260815-054807-50219.log`；
  prefix 為 `.maplestory-cx26-test-env-parity-20260815`。
- 效果：環境 parity 確實讓 CX26 完成 MapleStory、`GR2D_DX11.DLL`、DwarfAxe
  主程序／GPU／utility 子程序建立，並產生約 520 次 `macdrv_client_surface_present`。
  但仍沒有 `mlang.dll`、`opentype_enum_font_names`、`HybridCore64.dll`、`jypc.dll`
  或 `CreateSwapChain`；DwarfAxe 主程序仍在約 1.45 秒後才建立第一批視窗，未進入
  CX25 的 renderer 生命週期，沒有登入畫面證據。
- 結論：`WINEARCH`／`WINEDLLPATH` 不是足以修正黑畫面的單一變因；沒有加入正式
  launcher，也不宣稱本輪成功。log 保留供後續比較，隔離 prefix 不作為正式資料。

### 2026-08-15：D3DMetal top-level view ABI A/B（負面結果，已撤回 formal stack）

- 假設：CX25 的 D3DMetal private data 同時有 top-level `cocoa_view` 與 client view，
  而 CX26 只填 `client_cocoa_view`；先嘗試把 CX25 欄位意義補回。第一次候選直接
  使用 `data->cocoa_view`，編譯即確認 CX26 的 `macdrv_win_data` 已移除該欄位，因此
  該版本未產生可執行 binary；這個編譯失敗也確認不能把 CX25 結構直接照搬。
- 修改：將候選縮小為 CX26 實際存在的 `data->client_view`，只在
  `CYDER_MAPLESTORY_POPULATE_D3DMETAL_WINDOW_VIEW=1` 時填入 D3DMetal private data
  的舊式 `cocoa_view` slot。暫時加入 build script 後成功重建；未加入 release manifest、
  patch-stack test 或正式 launcher。
- 測試：全新 prefix、正式 D3DMetal/GPTK、CompatDB、相同 work dir、MSync=0、ESync=0、
  `--no-otp`；log：
  `.maplestory-cx26-logs-window-view-20260815/maplestory-cx26-d3dmetal-20260815-055752-56262.log`。
- 效果：candidate 確實走到 MapleStory、`GR2D_DX11.DLL`、DwarfAxe 主／GPU／utility
  子程序與約 272 次 `macdrv_client_surface_present`，但沒有
  `HybridCore64.dll`、`jypc.dll`、`mlang.dll` 或 `CreateSwapChain` marker；沒有登入畫面
  的可視證據。`client_view` slot 不是足以解除黑畫面的修正。
- 結論：已移除 build script 的候選並以不含它的 formal stack 完成乾淨重建；候選 patch
  與 log 保留作為負面實驗紀錄，正式 runtime 不含此變更。

### 2026-08-15：D3DMetal client-surface update-on-present A/B（負面結果，已撤回 formal stack）

- 假設：CX26 的 D3DMetal client surface 在建立時呼叫一次 `update`，之後外部 GPTK
  的 `nextDrawable` 路徑只觸發 `present`；若主視窗尺寸在建立後改變，Metal view
  可能仍保留舊 frame。CX25 baseline 則在成功載入 `HybridCore64.dll` 前後完成
  主視窗 frame/client resize，因此測試在每次 surface present 前補一次 update。
- 修改：新增暫時 patch
  `patches/maplestory-cx26-d3dmetal-update-on-present.patch`，在
  `macdrv_client_surface_present()` 先呼叫 `macdrv_client_surface_update()`；只暫時
  註冊到 build script，沒有改 GPTK、CompatDB、launcher contract 或遊戲檔。
  第一次建置先發現 patch hunk header 格式錯誤，修正後才進行真正 A/B；該次格式錯誤
  沒有產生可執行測試結果。
- 建置與測試：修正後 `bash scripts/build-wine.sh --cx 26 --maplestory --without-vulkan
  --jobs 8` 成功，並以已初始化的隔離 prefix
  `.maplestory-cx26-test-update-present-20260815` 重跑。有效 log：
  `.maplestory-cx26-logs-update-present-20260815/maplestory-cx26-d3dmetal-20260815-061419-63837.log`。
  第一次新 prefix log `061127-63273` 只有初始化階段，未納入判斷。
- 效果：候選確實生效，log 有 1,710 次 `macdrv_client_surface_present` 與 1,712 次
  `macdrv_client_surface_update`，並載入 MapleStory、`GR2D_DX11.DLL` 及 3 次
  `DwarfAxe.exe`。但仍沒有 `HybridCore64.dll`、`jypc.dll`、`mlang.dll`，也沒有
  CX25 成功基準的後續主視窗 renderer 生命週期；沒有可視登入畫面證據。結論是
  update 頻率／尺寸同步不是足以解除黑畫面的修正。
- 結論：已移除 build script 註冊並撤回 build source 的暫時修改；候選 patch、兩份
  log 與隔離 prefix 的測試紀錄保留，正式 CX26 需再做一次不含候選的 clean rebuild。

### 2026-08-15：D3DMetal 輔助程序 legacy client-view handoff A/B（負面結果，已撤回 formal stack）

- 假設：CX25 OEM 的 `DwarfAxe.exe` 等輔助程序仍使用既有 `data->client_view`，而 CX26
  對每個 D3DMetal swapchain 都建立新的 client surface，可能使輔助 renderer 卡在啟動
  生命週期。候選只對非 `MapleStory.exe` 的程序回到既有 client view；主程序仍保留
  CX26 client-surface 路徑，並以 `CYDER_MAPLESTORY_LEGACY_AUX_D3DMETAL=1` 啟用。
- 修改：新增暫時 patch
  `patches/maplestory-cx26-d3dmetal-legacy-aux-view.patch` 與
  `patches/maplestory-cx26-d3dmetal-legacy-aux-view-followup.patch`。第一版因 helper
  插入點造成 C 語法錯誤，沒有產生可執行 binary，未列入遊戲效果判斷；修正插入點後
  兩個 hunk 均成功套用，正式 build 成功完成。
- 測試：使用全新 prefix
  `.maplestory-cx26-test-legacy-aux-view-20260815`、相同 MapleStory 路徑、work dir、
  D3DMetal/GPTK、CompatDB、media、MSync=0、ESync=0 與 `--no-otp`。有效 log：
  `.maplestory-cx26-logs-legacy-aux-view-20260815/maplestory-cx26-d3dmetal-20260815-064320-75197.log`。
- 無畫面驗證結果：主視窗建立為約 `1374x827`，並持續產生 2,229 次
  `macdrv_client_surface_present`；`DwarfAxe.exe` 主程序在 `76180.443`、GPU 子程序在
  `76183.614`、utility 子程序在 `76184.201` 載入。這與 CX25 的輔助程序鏈相近，但
  仍完全沒有 `HybridCore64.dll`、`jypc.dll`、`mlang.dll` 或登入流程 marker；因此
  沒有登入畫面證據，也不能把 present 事件或程序存活當成成功。相較既有 CX26
  update-on-present A/B，DwarfAxe GPU 延遲仍約 3.2 秒，未證明此 handoff 改善根因。
- 結論：候選已從 `scripts/build-wine.sh` 移除，patch 與 log 保留作為負面實驗紀錄；接下來
  會以不含本候選的 formal stack 做乾淨重建，避免暫時環境變數進入正式引擎。

### 2026-08-15：停用 CX26 shared-KMT producer/consumer A/B（負面結果，已撤回 formal stack）

- 假設：CX26 為 MapleStory 加入的 `winekmt_*` shared-texture producer/consumer 合約，可能
  讓 `DwarfAxe.exe` 的 D3D11/WineD3D 路徑與 CX25 OEM 不同；CX25 沒有這組自訂 KMT
  patch，因此先以環境變數 `CYDER_MAPLESTORY_DISABLE_SHARED_KMT=1` 暫時停用
  `OpenSharedResource` 與 shared-handle export，其他 D3DMetal、window 與 launcher 設定不變。
- 修改與建置：新增暫時 patch
  `patches/maplestory-cx26-disable-shared-kmt.patch`，並只在候選 build 暫時註冊到
  `scripts/build-wine.sh`。`bash scripts/build-wine.sh --cx 26 --maplestory --without-vulkan
  --jobs 8` 成功；測試完成後已移除 build script 註冊，正式 source 會再以不含候選的
  formal stack 重建。
- 測試：使用隔離 prefix
  `.maplestory-cx26-test-disable-shared-kmt-20260815`、相同 MapleStory executable、work
  dir、D3DMetal/GPTK、CompatDB、media、MSync=0、ESync=0 與 `--no-otp`。有效 log：
  `.maplestory-cx26-logs-disable-shared-kmt-20260815/maplestory-cx26-d3dmetal-20260815-065331-82983.log`。
- 無畫面驗證結果：仍載入 `DwarfAxe.exe` 主程序（約 `76790.911`）、GPU 子程序（約
  `76794.168`）與 utility 子程序（約 `76794.811`），主程序到 GPU 仍約 3.26 秒；log
  有大量 `macdrv_client_surface_presented`，但仍沒有 `HybridCore64.dll`、`jypc.dll` 或
  `mlang.dll`。同時沒有 `shared KMT` 的 `FIXME` marker，表示這輪路徑沒有證明實際觸發
  被停用的 import/export gate；因此沒有可歸因於該候選的改善，也沒有登入畫面證據。
- 結論：shared-KMT 候選不保留在 formal stack；patch 與 log 保留作為已淘汰的 A/B 紀錄。
  `DwarfAxe` 的啟動延遲與後續模組鏈仍未接近 CX25 成功基準，下一輪需繼續追查其
  D3D11/WineD3D 初始化或遊戲啟動條件的差異。

### 2026-08-15：撤掉 CX26 d3d11 shared-texture test A/B（負面結果，已撤回 formal stack）

- 假設：`DwarfAxe.exe` 使用 Wine 內建 D3D11/WineD3D，而 CX26 的
  `maplestory-cx26-d3d11-shared-texture-test.patch` 同時改動 `ClearView`、shared
  texture import 與 `wined3d` command flush；這組候選可能讓輔助 renderer 卡在 CX25
  不需要的同步／匯入路徑。這次只撤掉該 patch，保留 D3DMetal、window 與其它 MapleStory
  patch。
- 建置與測試：暫時從 `scripts/build-wine.sh` 移除候選註冊，從已套用的 generated source
  撤掉 shared-resource import 與同步 flush（保留另一個 full-clear patch 的 ClearView
  實作），再以 `bash scripts/build-wine.sh --cx 26 --maplestory --without-vulkan --jobs 8`
  建置成功。隔離 prefix 為
  `.maplestory-cx26-test-no-shared-texture-20260815`，有效 log 為
  `.maplestory-cx26-logs-no-shared-texture-20260815/maplestory-cx26-d3dmetal-20260815-070824-91459.log`。
- 無畫面驗證結果：`DwarfAxe.exe` 主程序約在 `77684.460` 載入，GPU 子程序約在
  `77687.699` 載入，延遲約 3.24 秒，與正式 CX26 的約 3.26 秒相同；仍沒有
  `HybridCore64.dll`、`jypc.dll` 或 `mlang.dll`，也沒有登入畫面證據。移除候選後沒有
  使模組鏈接近 CX25 的 `HybridCore64 -> jypc` 順序。
- 結論：此候選淘汰，不保留在正式 stack；patch 與 log 保留作為負面 A/B 紀錄。測試
  prefix 已停止後移除，正式 stack 將重新套回該 patch 並做 regression。

### 2026-08-15：CX26 dbghelp SymInitialize 禁用 A/B（負面結果，已撤回 formal stack）

- 假設：研究分支的 CX25 OEM 文件指出，OEM `SymInitializeW()` 預設回傳
  `ERROR_CALL_NOT_IMPLEMENTED`，只有 `MAPLESTORY_ENABLE_DBGHELP=1` 才進行完整 symbol
  initialization；CX26 目前只有 DWARF 除零 guard。這可能是 `DwarfAxe`／登入前 crash
  reporter 路徑的差異，因此加入只供 A/B 使用的
  `CYDER_MAPLESTORY_DISABLE_DBGHELP_SYMBOLS=1`，讓 `SymInitializeW()` 回傳相同錯誤，並
  加入明確 `MapleStoryPort` marker。
- 建置：`bash scripts/build-wine.sh --cx 26 --maplestory --without-vulkan --jobs 8`
  成功；候選只暫時註冊在 `scripts/build-wine.sh`，測試後已移除，並以不含候選的 formal
  stack 重新建置。測試第一次在未授權的 sandbox 中於 wineserver Mach port 階段失敗，未
  納入效果判斷；第二次以可使用 macOS Wine/GUI 資源的相同條件完成。
- 測試：全新 prefix
  `.maplestory-cx26-test-disable-dbghelp-symbols-20260815`、相同 MapleStory executable、
  `/Users/jjc/games/tms` work dir、D3DMetal/GPTK、CompatDB、media、MSync=0、ESync=0、
  `--no-otp`。有效 log：
  `.maplestory-cx26-logs-disable-dbghelp-symbols-20260815-rerun/maplestory-cx26-d3dmetal-20260815-071846-99155.log`。
- 無畫面驗證結果：log 確實命中 `SymInitializeW` 候選 marker；MapleStory 約在
  `78275.125` 開始，DwarfAxe 約在 `78304.730`（約 29.6 秒後）才啟動，完成約 2,579
  次 `macdrv_client_surface_present`，但仍沒有 `HybridCore64.dll`、`jypc.dll`、
  `mlang.dll` 或登入流程 marker。相較 formal CX26 約 3.2 秒的 DwarfAxe 啟動延遲，
  這個候選明顯變慢，沒有接近 CX25 成功基準；由於目前無法從系統 API 讀取 Wine surface，
  也沒有登入畫面證據。
- 結論：dbghelp symbol-init 禁用候選淘汰，不保留在 formal stack；候選 patch 與 log
  保留作為負面 A/B 紀錄，隔離 prefix 已停止並移除。

### 2026-08-15：CX25 OEM dbghelp binary overlay A/B（未達驗收，未納入 formal stack）

- 假設：CX25 OEM 的 `dbghelp.dll` 不只是 `SymInitializeW()` 的環境變數行為，整個
  OEM builtin binary 也可能影響 MapleStory 在登入前的 crash/report、模組掃描或
  DwarfAxe handoff。為隔離這個變因，從 CX25 OEM Engine 取出 32/64-bit 的
  `dbghelp.dll`（各 446,032 bytes），以 `WINEDLLPATH` overlay 放在 CX26 formal
  `lib/wine` 前面；overlay 只含 dbghelp，其餘 DLL、D3DMetal、GPTK 與 launcher 不變。
- 前兩次嘗試是無效 A/B：直接複製到 prefix 會被 `wineboot` 重新生成 builtin DLL；即使
  設定 prefix override，Wine 仍載入 formal builtin。第三次先完成 prefix 初始化，再以
  `WINEDLLPATH` 做單一 DLL overlay，並從 `trace:dbghelp:SymMatchFileNameW` 與完整
  模組掃描輸出確認確實進入 OEM dbghelp 行為。
- 測試：全新 prefix
  `.maplestory-cx26-test-oem-dbghelp-winedllpath-20260815`、相同 MapleStory executable、
  `/Users/jjc/games/tms` work dir、D3DMetal/GPTK、CompatDB、media、MSync=0、ESync=0、
  `--no-otp`。有效 log：
  `.maplestory-cx26-logs-oem-dbghelp-winedllpath-20260815/maplestory-cx26-d3dmetal-20260815-073655-5788.log`。
- 無畫面驗證結果：主程式約在 `79351.956` 載入，DwarfAxe 約在 `79387.241` 載入，
  比 formal CX26 約 3.2 秒的 DwarfAxe handoff 明顯更慢；之後有約 10,370 次
  `macdrv_client_surface_present`，但沒有 `HybridCore64.dll`、`jypc.dll` 或
  `mlang.dll` 的實際 `Loaded` 行，也沒有登入流程 marker。`trace:dbghelp:` 約 3,244
  行只能證明 OEM dbghelp 路徑正在做模組掃描，不能把它當作畫面成功。
- 結論：OEM dbghelp binary overlay 沒有讓 CX26 到達 CX25 的登入前模組鏈，且增加啟動
  延遲；不納入 formal stack。overlay 與 log 保留作為可重現證據，隔離 prefix 已停止
  並移除。

### 2026-08-15：CX25 OEM mlang overlay A/B（無效／負面結果，未納入 formal stack）

- 假設：CX25 成功 prefix 的 `user.reg` 有 `mlang=native,builtin`，且 CX25 log 曾出現
  `mlang.dll`；CX26 fresh prefix 沒有這個 override。這可能是登入 UI／字型初始化在
  `HybridCore64` 之前分叉的原因，因此只把 CX25 OEM 32/64-bit `mlang.dll` 放入
  `WINEDLLPATH` overlay，沒有替換 CX26 其它 DLL 或 registry。
- 測試：全新 prefix
  `.maplestory-cx26-test-oem-mlang-20260815`、相同 MapleStory executable、
  `/Users/jjc/games/tms` work dir、D3DMetal/GPTK、CompatDB、media、MSync=0、ESync=0、
  `--no-otp`。有效 log：
  `.maplestory-cx26-logs-oem-mlang-20260815/maplestory-cx26-d3dmetal-20260815-074307-6918.log`。
- 無畫面驗證結果：`MapleStory.exe` 約在 `79723.292` 載入、`GR2D_DX11.DLL` 約在
  `79740.723` 載入、DwarfAxe 約在 `79758.502` 載入；整份 log 沒有 `mlang.dll`、
  `HybridCore64.dll` 或 `jypc.dll` 的實際載入，只有 439 次 surface present，亦無
  登入流程 marker。即使 overlay 已放在正式 `lib/wine` 前面，遊戲在這條 no-OTP
  路徑沒有觸發 mlang，因此不能把它視為成功或有效改善。
- 結論：mlang overlay 沒有改變 CX26 的阻塞點，且 DwarfAxe handoff 仍顯著晚於 formal
  baseline；不納入 formal stack。overlay 與 log 保留，隔離 prefix 已停止並移除。

### 2026-08-15：CX25 mlang registry override A/B（無效／負面結果，未納入 formal stack）

- 校正：前一輪只改 `WINEDLLPATH`，沒有完整重現 CX25 的
  `HKCU\Software\Wine\DllOverrides\mlang=native,builtin`。本輪先完成 CX26 prefix
  初始化，再寫入相同 registry override，並保留 OEM mlang overlay；因此這次才是
  prefix policy 與 DLL binary 都對齊的 mlang A/B。
- 測試：第一次啟動只用環境變數 override，Wine 初始化會覆蓋該環境值，未納入效果判斷；
  之後在同一專用 prefix 明確寫入 registry，再以新 log
  `.maplestory-cx26-logs-oem-mlang-override-rerun-20260815/maplestory-cx26-d3dmetal-20260815-074907-8446.log`
  重跑。prefix 使用相同遊戲目錄、work dir、D3DMetal/GPTK、CompatDB、MSync=0、
  ESync=0 與 `--no-otp`。
- 結果：registry 確實保留 `"mlang"="native,builtin"`，但 CX26 主程序仍沒有
  `mlang.dll` 或 `opentype_enum_font_names` 載入／呼叫；因此 CX25 早期 mlang 差異不是
  單純 prefix override 可補的因素。此輪沒有 `HybridCore64.dll`、`jypc.dll` 或登入
  marker，未達畫面驗收。
- 結論：mlang binary + registry override 排除，不納入 formal stack；測試 prefix 已
  移除，log 與 overlay 保留。

### 2026-08-15：CX25 OEM kernelbase binary overlay A/B（負面結果，未納入 formal stack）

- 假設：研究分支的 reverse bisect 把 OEM kernelbase `.dll`→`.tmp`／`.msf` 列為無 OTP
  必要差異；CX26 雖有 `maplestory-cx26-tmp-module-name.patch`，仍可能漏掉其它
  kernelbase 行為。這輪只以 CX25 OEM 32/64-bit `kernelbase.dll` overlay 取代 CX26
  formal binary，保留 CX26 source patch、D3DMetal/GPTK、其它 DLL、work dir 與 launcher。
- 測試：全新 prefix
  `.maplestory-cx26-test-oem-kernelbase-20260815`、相同 MapleStory executable、
  `/Users/jjc/games/tms` work dir、D3DMetal/GPTK、CompatDB、media、MSync=0、ESync=0、
  `--no-otp`。有效 log：
  `.maplestory-cx26-logs-oem-kernelbase-20260815/maplestory-cx26-d3dmetal-20260815-075313-9732.log`。
- 無畫面驗證結果：CX26 主程序約在 `80327.192` 載入，DwarfAxe 三個程序約在
  `80360.119`、`80361.288`、`80361.869` 載入；只有約 2,082 次 surface present，
  沒有 `HybridCore64.dll`、`jypc.dll`、`mlang.dll` 或登入流程 marker。相較 formal
  CX26，OEM kernelbase 沒有恢復 CX25 的 `DwarfAxe → HybridCore64 → jypc` 鏈，且
  handoff 仍明顯延遲。
- 結論：直接替換 OEM kernelbase binary 不能修正 CX26 黑畫面；不混入 formal engine。
  overlay 與 log 保留作為 reverse-bisect 對照，隔離 prefix 已停止並移除。

### 2026-08-15：CX25 OEM winemac/D3DMetal driver overlay A/B（負面結果，未納入 formal stack）

- 假設：CX26 既有 source A/B 只調整部分 surface/view 欄位；若真正差異在整個
  `winemac.so` 或 `winemac.drv`，直接使用 CX25 OEM driver 應能讓 D3DMetal 走到
  CX25 的後續 renderer 鏈。這輪只 overlay CX25 OEM 的 x86_64 `winemac.so` 與 32/64-bit
  `winemac.drv`，其它 CX26 Wine DLL、GPTK、CompatDB、launcher、work dir 均不變。
- 測試：全新 prefix
  `.maplestory-cx26-test-oem-winemac-20260815`、相同 MapleStory executable、
  `/Users/jjc/games/tms` work dir、D3DMetal/GPTK、CompatDB、media、MSync=0、ESync=0、
  `--no-otp`。有效 log：
  `.maplestory-cx26-logs-oem-winemac-20260815/maplestory-cx26-d3dmetal-20260815-075648-10449.log`。
- 無畫面驗證結果：CX26 主程式約在 `80538.905` 載入，DwarfAxe 三個程序約在
  `80570.078`、`80571.010`、`80571.556` 載入；之後約 3,141 次 surface present，
  但沒有 `HybridCore64.dll`、`jypc.dll`、`mlang.dll` 或登入流程 marker。OEM driver
  沒有恢復 CX25 的 `DwarfAxe → HybridCore64 → jypc` 順序。
- 結論：整個 OEM winemac binary 也不是可直接移植的修正；不改 formal source，overlay
  與 log 保留，隔離 prefix 已停止並移除。

### 2026-08-15：CX26 D3DMetal MSync=1／0 對照（MSync=1 負面結果）

- 假設：CX25 OEM 基準未明確把 MSync 關閉，而先前 CX26 的有效 DwarfAxe 對照都使用
  `CYDER_MSYNC=0`；若同步模型造成早期執行緒交接差異，恢復 `MSync=1` 可能讓 CX26
  回到 CX25 的啟動路徑。
- 測試：使用正式 CX26 stack、全新 prefix
  `.maplestory-cx26-test-msync1-20260815`、相同 MapleStory.exe、`/Users/jjc/games/tms`
  work dir、D3DMetal/GPTK、CompatDB、`CYDER_MSYNC=1`、`CYDER_ESYNC=0` 與 `--no-otp`。
  有效 log：`.maplestory-cx26-logs-msync1-20260815/maplestory-cx26-d3dmetal-20260815-080522-12405.log`。
- 無畫面驗證結果：CX26 仍載入 `MapleStory.exe`、`GR2D_DX11.DLL`，並產生一次
  `macdrv_client_surface_update/present`；但沒有建立 `DwarfAxe.exe`、
  `HybridCore64.dll`、`jypc.dll` 或 `mlang.dll`，程序在正式 CX26 `MSync=0` 可到達的
  DwarfAxe 之前結束。log 仍可見同一組遊戲攔截的 FLT divide／C++ exception 時序，沒有
  出現主遊戲登入 renderer 的可視或模組證據。
- 結論：`MSync=1` 不是修正，且比 `MSync=0` 更早停止；正式 CX26 測試維持
  `CYDER_MSYNC=0`。測試 prefix 已停止，log 保留供回歸比對。

### 2026-08-15：CX26 恢復 sched_yield A/B（負面結果，已撤回）

- 假設：CX25 OEM 的 `NtYieldExecution()` 會停用 host `sched_yield()`，但研究分支只在
  CX25 reverse-bisect 判定這是無 OTP 非必要；CX26 可能因 Wine 11 執行緒模型不同而需要
  原生 `sched_yield()`。本輪只反向恢復該一個 `ntdll/unix/sync.c` 差異，保留其它 formal
  CX26 patch、D3DMetal/GPTK、work dir、CompatDB 與 `MSync=0`。
- 修改與建置：加入一次性的 build hook 將
  `maplestory-cx26-no-sched-yield.patch` 反向套用；CX26 x86_64/i386 runtime 成功重建。
  測試後移除 hook，並重新建置回包含 `no-sched-yield` 的 formal runtime。
- 測試：全新 prefix
  `.maplestory-cx26-test-sched-yield-20260815`、相同 MapleStory.exe、
  `/Users/jjc/games/tms` work dir、D3DMetal/GPTK、CompatDB、`CYDER_MSYNC=0`、
  `CYDER_ESYNC=0` 與 `--no-otp`。有效 log：
  `.maplestory-cx26-logs-sched-yield-20260815/maplestory-cx26-d3dmetal-20260815-080920-15107.log`。
- 無畫面驗證結果：恢復 `sched_yield()` 後，CX26 僅載入 `MapleStory.exe`，連
  `GR2D_DX11.DLL`、DwarfAxe、`HybridCore64.dll`、`jypc.dll`、`mlang.dll` 或 surface
  present 都沒有出現；比 formal `no-sched-yield` 更早停止，沒有登入畫面證據。
- 結論：CX26 必須保留正式的 `no-sched-yield`；恢復 host scheduler 不是黑畫面修正，
  暫時 build hook 已撤回，formal runtime 已復原並保留 log。

### 2026-08-15：CX26 撤除 BlackXchg foreground guard A/B（負面結果，已撤回）

- 假設：CX26 formal 目前避免 `BlackXchg.aes` 把共用 Wine application 搶到前景；若這個
  foreground guard 反而阻礙主程序建立 renderer，恢復 CX25 OEM 的原始 foreground 行為
  應能讓 CX26 更接近 CX25。
- 修改與建置：加入一次性的 build hook 反向撤除
  `maplestory-cx26-blackxchg-foreground.patch`，其它 formal patch、D3DMetal/GPTK、
  work dir、CompatDB、`MSync=0` 不變。A/B 完成後移除 hook，正式 runtime 會重新套回該 guard。
- 測試：全新 prefix
  `.maplestory-cx26-test-blackxchg-default-20260815`、相同 MapleStory.exe、
  `/Users/jjc/games/tms` work dir、D3DMetal/GPTK、CompatDB、`CYDER_MSYNC=0`、
  `CYDER_ESYNC=0` 與 `--no-otp`。有效 log：
  `.maplestory-cx26-logs-blackxchg-default-20260815/maplestory-cx26-d3dmetal-20260815-081338-21150.log`。
- 無畫面驗證結果：撤除 guard 後仍只載入 `MapleStory.exe`、`GR2D_DX11.DLL`，並產生一次
  `macdrv_client_surface_update/present`；沒有 DwarfAxe、`HybridCore64.dll`、`jypc.dll`、
  `mlang.dll` 或登入畫面證據，且比 formal `BlackXchg` guard 路徑更早停止。
- 結論：BlackXchg foreground guard 不是目前阻塞點，formal stack 保留該 guard；暫時
  build hook 已撤回，測試 log 保留供比較。

### 2026-08-15：CX26 formal stack 最終乾淨回歸（未達登入畫面驗收）

- 建置與環境：撤回所有一次性 A/B build hook 後，正式 CX26 source/runtime 重新建置成功；
  patch stack、shell syntax 與 `git diff --check` 均通過。正式測試使用全新 prefix
  `.maplestory-cx26-final-formal-20260815`、`/Users/jjc/games/tms` work dir、D3DMetal/GPTK、
  CompatDB、media、`CYDER_MSYNC=0`、`CYDER_ESYNC=0` 與 `--no-otp`。有效 log：
  `.maplestory-cx26-logs-final-formal-20260815/maplestory-cx26-d3dmetal-20260815-081852-24984.log`。
- 無畫面驗證結果：正式 CX26 載入 `GR2D_DX11.DLL`（`81884.095`），約 17.8 秒後建立
  DwarfAxe 主程序與 GPU／utility 子程序（`81901.860`–`81904.651`），並持續產生
  4,122 次 `macdrv_client_surface_present`、3 次 surface update。這證明 D3DMetal
  surface loop 有在跑，但日誌沒有 `HybridCore64.exe`、`jypc.exe`、`mlang.dll`、
  `OpenSharedResource` 或登入流程 marker；仍不可由 present／cursor／process alive
  推論為登入畫面。測試中可見 FLT divide、C++ exception 與 DBG print，與既有 no-OTP
  smoke 路徑一致，未出現可視登入證據。
- 結論：正式 CX26 仍是「黑畫面但有遊戲鼠標／surface present」，尚未達 CX25 OEM
  登入畫面驗收；本輪沒有把任何負面 A/B 變因帶回正式 stack。所有測試程序已停止，
  工作區保留 log 與 prefix 供後續比對。

### 2026-08-15：CX26 engine 搭配 CX25 winewrapper／`--workdir` A/B（負面結果）

- 假設：CX25 正常基準透過 `wineloader + winewrapper.exe --workdir /Users/jjc/games/tms
  --run -- MapleStory.exe` 啟動，而 CX26 launcher 直接呼叫 `bin/wine`；先前的環境
  parity 沒有隔離 wrapper 是否改變 CWD、argv 或 child-process 啟動語意。因此本輪只
  換啟動器，仍使用 CX26 formal engine、D3DMetal/GPTK、CompatDB、media、MSync=0、
  ESync=0 與相同遊戲目錄。
- 第一次建立全新 prefix
  `.maplestory-cx26-test-cx25-wrapper-20260815` 時，初始化佔用約 1.1G，測試尚未
  形成完整 renderer 證據便因主機磁碟不足而中止；截斷 log
  `.maplestory-cx26-logs-cx25-wrapper-20260815/cx26-cx25-wrapper-20260815.log`
  保留，該輪新建 prefix 已移除以恢復空間，不影響 CX25 或正式 CX26。
- 為避免再次建立大型 prefix，第二次在既有隔離的 CX26 formal prefix
  `.maplestory-cx26-final-formal-20260815` 上重跑 wrapper，log 為
  `.maplestory-cx26-logs-cx25-wrapper-reuse-20260815/cx26-cx25-wrapper-reuse-20260815.log`。
  這次確實使用 CX26 `bin/wine` 執行 CX25 OEM `winewrapper.exe`，並由 wrapper 設定
  `/Users/jjc/games/tms` work dir。
- 效果：wrapper 路徑載入 `MapleStory.exe`、BlackCipher、`GR2D_DX11.DLL`，約
  `82506.598` 建立 DwarfAxe，並產生約 2,304 次 `macdrv_client_surface_present`；
  但沒有 `HybridCore64.dll`、`jypc.dll`、`mlang.dll` 或 `OpenSharedResource`。
  與 CX26 direct launcher 的正式結果相同，沒有登入畫面證據；wrapper 不是目前的
  renderer／黑畫面修正。
- 結論：不改 `scripts/run-maplestory-cx26-d3dmetal.sh`，正式路徑維持直接 CX26
  `bin/wine` + 正確 CWD；兩批測試程序已停止，log 保留作為 A/B 證據。

### 2026-08-15：CX25 OEM `mlang/urlmon/wininet/shlwapi` 載入策略 A/B（未生效，未納入 formal stack）

- 假設：CX25 成功基準的 DwarfAxe 會載入 `mlang.dll`、`urlmon.dll`、`wininet.dll` 與
  `shlwapi.dll`；CX26 formal 只看到部分 builtin 模組且沒有 `mlang.dll`。本輪先以
  `WINEDLLPATH` 加 `WINEDLLOVERRIDES='mlang=native,builtin;urlmon=native,builtin'`
  嘗試讓 CX25 OEM runtime 介入，再以 prefix 內的 CX25 OEM x86_64/i386 DLL 實體檔案
  加 registry `native,builtin` override 做第二次驗證。兩次都只使用 CX26 formal engine、
  D3DMetal/GPTK、CompatDB、正確 `/Users/jjc/games/tms` work dir、MSync=0、ESync=0 與
  `--no-otp`；沒有修改 CX26 source 或正式 launcher。
- 第一輪有效 log：
  `.maplestory-cx26-logs-oem-mlang-urlmon-20260815/maplestory-cx26-d3dmetal-20260815-084442-31994.log`。
  `MapleStory.exe` 約 `83404.175`、`GR2D_DX11.DLL` 約 `83417.928`、DwarfAxe 三個
  程序約 `83435.241`–`83437.266`，產生 144 次 surface present；指定的
  `mlang/urlmon` 沒有以 native 載入，相關 `shlwapi/wininet/urlmon` 記錄仍是 builtin，
  也沒有 `HybridCore64.dll`、`jypc.dll` 或登入流程 marker。
- 第二輪有效 log：
  `.maplestory-cx26-logs-oem-netfont-prefix-20260815/maplestory-cx26-d3dmetal-20260815-084703-32535.log`。
  prefix 內確實暫放 CX25 OEM 的四個 DLL 並設定 registry override；但遊戲程序的
  `shlwapi/wininet/urlmon` 仍全部記錄為 builtin，沒有 `mlang.dll`，所以這仍不是
  「CX25 OEM DLL 真正接管後的負面結果」，而是證明目前的 DLL 注入方式沒有生效。此輪
  仍載入 `GR2D_DX11.DLL`、三個 DwarfAxe 並產生 4,005 次 present，沒有登入畫面證據。
- 結論：不能把黑畫面歸因於 CX25 OEM 的這四個 DLL；目前可排除的是 `WINEDLLPATH`、
  環境 override 與 prefix 實體檔案加 registry 的這套介入路徑。測試後已停止全部程序，
  並以備份復原 formal prefix 的 DLL 與 user.reg；log 與復原備份保留，沒有把任何變因
  帶回正式 CX26 stack。

### 2026-08-15：CX25 `cb_access_map_w=1` registry A/B（負面結果，未納入 formal stack）

- 假設：CX25 OEM prefix 的 `Software\\Wine\\Direct3D` 有
  `cb_access_map_w=1`，而 CX26 formal prefix 沒有；CX26 wined3d source 仍保留這個
  constant-buffer map/write 路徑。若 DwarfAxe 的畫面交接或 CEF GPU buffer 依賴它，這個
  單一 registry 變因應能讓 CX26 更接近 CX25。
- 測試：在既有隔離 formal prefix
  `.maplestory-cx26-final-formal-20260815` 只加入
  `HKCU\\Software\\Wine\\Direct3D\\cb_access_map_w=1`，其它 CX26 formal engine、
  D3DMetal/GPTK、CompatDB、正確 work dir、MSync=0、ESync=0 與 `--no-otp` 均不變。
  有效 log：
  `.maplestory-cx26-logs-cb-access-map-w-20260815/maplestory-cx26-d3dmetal-20260815-085353-34188.log`。
- 無畫面驗證結果：`MapleStory.exe` 約 `83955.543`、`GR2D_DX11.DLL` 約 `83972.145`、
  DwarfAxe 主／GPU／utility 約 `83989.685`、`83991.570`、`83992.208`；測試期間約
  2,007 次 surface present，但沒有 `HybridCore64.dll`、`jypc.dll`、`mlang.dll`、
  `OpenSharedResource` 或登入流程 marker。它沒有恢復 CX25 在第三個 DwarfAxe 後的
  `HybridCore64 -> jypc` 模組鏈。
- 結論：`cb_access_map_w=1` 單獨不是黑畫面修正；測試後已停止全部程序並移除 registry
  值，formal prefix 的 user.reg SHA-256 復原為
  `3b37bb367ef075b15950df3ca3c31dfba19ec7639914814a8d6d415a3f205274`，沒有帶回正式
  stack。

### 2026-08-15：CX26 module-load diagnostic（確認未嘗試載入 HybridCore64/jypc）

- 目的：前面各輪只從 `+loaddll` 看到 CX26 沒有 `HybridCore64.dll`／`jypc.dll`；本輪
  不改 source、registry 或 runtime，只增加 `+module` debug channel，確認是載入失敗或
  根本沒有發生載入呼叫。使用 formal CX26 prefix、D3DMetal/GPTK、正確 work dir、
  MSync=0、ESync=0 與 `--no-otp`。
- 有效 log：
  `.maplestory-cx26-logs-module-diagnostic-20260815/maplestory-cx26-d3dmetal-20260815-085716-34796.log`。
  `module:load_dll` 確實記錄了 DwarfAxe 及其 CEF/GPU 相依模組的搜尋與載入；整份
  log 沒有 `HybridCore64` 或 `jypc` 的 `looking for`、`Found`、`Loaded` 或 error
  記錄。也就是 CX26 在這條 no-OTP 路徑並非嘗試載入後找不到，而是主遊戲沒有走到
  CX25 成功基準中第三個 DwarfAxe 後的那個動態載入階段。
- 結論：下一個有效方向應放在「讓主遊戲從第三個 DwarfAxe handoff 繼續執行」的
  CX26 行為差異，而不是繼續替換 `HybridCore64/jypc` 檔案或 DLL search path。診斷
  測試程序已停止，沒有留下設定變更。

### 2026-08-15：CX26 DwarfWebBrowserClass `SWP_NOACTIVATE` A/B（負面結果，未納入 formal stack）

- 假設：研究分支的 CX25 OEM `win32u/window.c` 在
  `NtUserSetWindowPos()` 對 `DwarfWebBrowserClass` 加上 `SWP_NOACTIVATE`，可避免
  DwarfAxe 的瀏覽器視窗在遊戲 renderer 交接時搶走 activation；CX26 formal source
  缺少這段，而 CX26 黑畫面 log 正好在 DwarfAxe 啟動前出現
  `macdrv_app_deactivated setting fg to desktop`。本輪只測這個單一 source 變因。
- 修改與建置：新增
  `patches/maplestory-cx26-dwarf-noactivate.patch`，並登錄至
  `scripts/build-wine.sh`、`tests/test-maplestory-patch-stack.sh`、
  `config/engine-release.json` 與 `patches/README.md`。正式 CX26 runtime 重新建置
  成功，patch dry-run、patch-stack test、shell syntax 與 `git diff --check` 均通過。
- 測試：使用 CX26 formal prefix
  `.maplestory-cx26-final-formal-20260815`、D3DMetal/GPTK、CompatDB、正確
  `/Users/jjc/games/tms` work dir、`CYDER_MSYNC=0`、`CYDER_ESYNC=0` 與
  `--no-otp`；完整 log 為
  `.maplestory-cx26-logs-dwarf-noactivate-20260815/maplestory-cx26-d3dmetal-20260815-091409-41251.log`。
- 無畫面替代驗證：主程式於 `85191.808` 載入，DwarfAxe 主程序於 `85227.051`、GPU
  與 utility 子程序於 `85230.389`、`85231.071` 載入，並持續產生 `8,086` 次
  `macdrv_client_surface_present`。但 DwarfAxe 啟動前仍在 `85226.943` 出現
  `macdrv_app_deactivated setting fg to desktop`，之後也沒有
  `HybridCore64.dll`、`jypc.dll`、`mlang.dll` 或 `OpenSharedResource`；時序與
  CX26 formal 黑畫面一致，沒有恢復 CX25 的第三個 DwarfAxe 後模組鏈。
- 結論：此 `SWP_NOACTIVATE` 移植候選未修復黑畫面，已從 build/release/test stack
  移除並以 source 重建回復原 formal stack；候選 patch 檔與 log 仍保留作為可追溯
  的 A/B 證據，未刪除既有測試資料。測試程序與 wineserver 已停止，無殘留 CX26
  遊戲程序。

### 2026-08-15：CX26 OEM public foreground API A/B（負面結果，未納入 formal stack）

- 假設：CX25 OEM 的 `winemac.drv/window.c` 在 `macdrv_window_got_focus()` 使用
  `NtUserSetForegroundWindow(hwnd)`，CX26 則使用 `NtUserSetForegroundWindowInternal(hwnd)`。
  本輪只把這一個 focus-path 呼叫改回 OEM 的 public API，測試其是否能保留主遊戲的
  foreground，讓 DwarfAxe handoff 繼續。
- 修改與建置：新增
  `patches/maplestory-cx26-public-foreground-focus.patch`，只替換上述一個呼叫；
  patch dry-run、建置與 shell/diff 靜態驗證通過。
- 啟動：第一次非 GUI 權限啟動只得到 `server_mach_port`，沒有遊戲事件；第二次以
  macOS GUI/Mach 權限使用同一 CX26 formal prefix、D3DMetal/GPTK、CompatDB、正確
  `/Users/jjc/games/tms` work dir、`CYDER_MSYNC=0`、`CYDER_ESYNC=0` 與 `--no-otp`
  成功啟動。有效 log 為
  `.maplestory-cx26-logs-public-foreground-20260815/maplestory-cx26-d3dmetal-20260815-092653-48656.log`。
- 無畫面替代驗證：主程式於 `85954.455` 載入，DwarfAxe 主／GPU／utility 於
  `85989.649`、`85993.075`、`85993.736` 載入；測試期間有 `3,631` 次
  `macdrv_client_surface_present`。但 DwarfAxe 啟動前仍於 `85989.536` 出現
  `macdrv_app_deactivated setting fg to desktop`，沒有 `HybridCore64.dll`、
  `jypc.dll`、`mlang.dll` 或 `OpenSharedResource`；與 CX26 formal 黑畫面時序相同。
- 結論：public foreground API 單一變因未修復 handoff，已從 build/release/test stack
  移除並從已建置 source 還原；本輪 log 與第一次權限失敗 log 均保留，所有測試程序
  已停止。

### 2026-08-15：CX26 OEM public app-deactivate API A/B（負面結果，未納入 formal stack）

- 假設：CX25 OEM 的 `macdrv_app_deactivated()` 使用
  `NtUserSetForegroundWindow(NtUserGetDesktopWindow())`，CX26 使用 internal API。
  本輪只替換 app-deactivate handler 的這一行，直接測試 CX26 log 中反覆出現的
  `setting fg to desktop` 事件是否因此不再阻斷 DwarfAxe handoff。
- 修改與建置：新增
  `patches/maplestory-cx26-public-app-deactivate.patch`，只替換上述一個呼叫；
  patch dry-run、建置與 shell/diff 靜態驗證通過。
- 測試：使用 macOS GUI/Mach 權限、CX26 formal prefix、D3DMetal/GPTK、CompatDB、
  正確 `/Users/jjc/games/tms` work dir、`CYDER_MSYNC=0`、`CYDER_ESYNC=0` 與
  `--no-otp`；有效 log 為
  `.maplestory-cx26-logs-public-app-deactivate-20260815/maplestory-cx26-d3dmetal-20260815-093305-54354.log`。
- 無畫面替代驗證：主程式於 `86327.507` 載入，DwarfAxe 主／GPU／utility 於
  `86362.761`、`86366.086`、`86366.708` 載入；測試期間有 `1,326` 次
  `macdrv_client_surface_present`。但事件仍於 `86362.646` 出現
  `macdrv_app_deactivated setting fg to desktop`，沒有 `HybridCore64.dll`、
  `jypc.dll` 或 `OpenSharedResource`，與 formal 黑畫面路徑相同。
- 結論：public app-deactivate API 單一變因未修復 handoff，已從 build/release/test
  stack 移除並從已建置 source 還原；log 保留，測試程序已停止。

### 2026-08-15：CX26 MapleStory main foreground guard A/B（負面結果，未納入 formal stack）

- 假設：CX26 在 DwarfAxe handoff 前收到 `macdrv_app_deactivated`，若此時目前
  active window 仍是 MapleStory 主視窗，應保留主 renderer 的 foreground，不把焦點
  送到 desktop。本輪在 `macdrv_app_deactivated()` 加入只針對 MapleStory main window
  的 early return，其他程式不受影響。
- 修改與建置：新增
  `patches/maplestory-cx26-keep-main-foreground.patch`，並登錄至
  `scripts/build-wine.sh`、`tests/test-maplestory-patch-stack.sh`、
  `config/engine-release.json` 與 `patches/README.md`；正式 CX26 runtime 重新建置
  成功，patch dry-run、patch-stack test、shell syntax 與 `git diff --check` 均通過。
- 測試：使用 CX26 formal prefix
  `.maplestory-cx26-final-formal-20260815`、D3DMetal/GPTK、CompatDB、正確
  `/Users/jjc/games/tms` work dir、`CYDER_MSYNC=0`、`CYDER_ESYNC=0` 與
  `--no-otp`；完整 log 為
  `.maplestory-cx26-logs-keep-main-foreground-20260815/maplestory-cx26-d3dmetal-20260815-094031-60332.log`。
- 無畫面替代驗證：主程式於 `86773.771` 載入，`GR2D_DX11.DLL` 於 `86791.120`
  載入；但 DwarfAxe 啟動前仍於 `86808.986` 出現
  `macdrv_app_deactivated setting fg to desktop`，DwarfAxe 主／GPU／utility 於
  `86809.096`、`86812.436`、`86813.070` 載入，期間至少有 `1,182` 次
  `macdrv_client_surface_present`。後續仍未出現 `HybridCore64.dll`、`jypc.dll`、
  `mlang.dll` 或 `OpenSharedResource`；另於 `86932.497` 又啟動一次 DwarfAxe GPU
  子程序，仍沒有恢復 CX25 的後續模組鏈。
- 結論：active-window guard 沒有阻止實際的 app-deactivate/desktop foreground
  事件，未修復 handoff，故判定為負面結果。候選已從 build/release/test stack
  移除並從已建置 source 還原；本輪 log 保留，測試程序與 wineserver 已停止，未刪除
  既有測試資料。

### 2026-08-15：CX26 Cocoa applicationDidResignActive guard A/B（負面結果，未納入 formal stack）

- 假設：CX26 黑畫面路徑在 DwarfAxe 啟動前先出現 Cocoa application resign，若只對
  MapleStory process 忽略 `applicationDidResignActive`，就不會把
  `APP_DEACTIVATED` 送進 Wine event queue，也不會把 foreground 交給 desktop。
- 修改與建置：新增
  `patches/maplestory-cx26-ignore-resign-active.patch`，在
  `winemac.drv/cocoa_app.m` 對 MapleStory 名稱加入 early return 與診斷訊息，並登錄
  至 build/release/test stack；patch stack、shell syntax、`git diff --check` 與正式
  CX26 runtime 建置均成功。
- 第一次啟動使用原 formal prefix，log 為
  `.maplestory-cx26-logs-ignore-resign-active-20260815/maplestory-cx26-d3dmetal-20260815-094941-66923.log`；
  使用者隨後確認是手動強制關閉，因此這份 log 只記為「未進入遊戲的初始化中止」，
  不作 renderer A/B 結論。
- 有效重跑改用全新獨立 prefix
  `.maplestory-cx26-ignore-resign-active-prefix-20260815`，log 為
  `.maplestory-cx26-logs-ignore-resign-active-retry-20260815/maplestory-cx26-d3dmetal-20260815-095050-67310.log`。
  MapleStory 於 `87383.316`、`GR2D_DX11.DLL` 於 `87400.954` 載入；但仍於
  `87419.067` 出現 `macdrv_app_deactivated setting fg to desktop`，DwarfAxe
  主／GPU／utility 於 `87419.175`、`87422.510`、`87423.156` 載入，期間有 `963` 次
  `macdrv_client_surface_present`。log 沒有 patch 預期的
  `MapleStoryPort: ignoring MapleStory application resign event`，也沒有
  `HybridCore64.dll`、`jypc.dll`、`mlang.dll` 或 `OpenSharedResource`。
- 結論：Cocoa guard 沒有攔截實際 resign/handoff，未修復 CX26 路徑，判定為負面結果。
  候選已從 build/release/test stack 移除並從已建置 source 還原；兩份 log 與獨立
  prefix 均保留，測試程序已停止。

### 2026-08-15：CX26 DwarfAxe foreground transform guard A/B（負面結果，未納入 formal stack）

- 假設：DwarfAxe 子程序在 `transformProcessToForeground()` 把共享的 Wine Cocoa app
  拉到前景，導致 MapleStory 收到 resign event；若只在 process name 或 executable
  basename 命中 DwarfAxe 時跳過 transform，主 renderer 應能保留前景。
- 修改與建置：新增
  `patches/maplestory-cx26-dwarf-foreground.patch`，只在
  `winemac.drv/cocoa_app.m` 的 DwarfAxe process path 加入 early return 與診斷訊息，
  並登錄至 build/release/test stack；修正 patch hunk 行數後，patch stack、shell
  syntax、`git diff --check` 與正式 CX26 runtime 建置均成功。
- 測試：使用新獨立 prefix
  `.maplestory-cx26-dwarf-foreground-prefix-20260815`、D3DMetal/GPTK、CompatDB、
  正確 work dir、`CYDER_MSYNC=0`、`CYDER_ESYNC=0` 與 `--no-otp`；完整 log 為
  `.maplestory-cx26-logs-dwarf-foreground-20260815/maplestory-cx26-d3dmetal-20260815-095633-73269.log`。
- 無畫面替代驗證：MapleStory 於 `87737.684`、`GR2D_DX11.DLL` 於 `87755.517`
  載入；但在 DwarfAxe 啟動前仍於 `87773.597` 出現
  `macdrv_app_deactivated setting fg to desktop`，DwarfAxe 主／GPU／utility 於
  `87773.692`、`87776.954`、`87777.586` 載入，期間有 `998` 次
  `macdrv_client_surface_present`。log 沒有預期的
  `MapleStoryPort: not bringing DwarfAxe to the foreground`，也沒有
  `HybridCore64.dll`、`jypc.dll`、`mlang.dll` 或 `OpenSharedResource`。
- 結論：DwarfAxe foreground guard 沒有攔截實際 handoff，未修復 CX26，判定為負面
  結果。候選已從 build/release/test stack 移除並從已建置 source 還原；log 與 prefix
  保留，測試程序已停止。

### 2026-08-15：測試 prefix 殘留反作弊程序與啟動前清理

- 發現：停止上一輪測試後，程序表仍有兩個獨立 CX26 prefix 的
  `BlackCipher64.aes` 殘留，PID `67452` 屬於
  `.maplestory-cx26-ignore-resign-active-prefix-20260815`，PID `73495` 屬於
  `.maplestory-cx26-dwarf-foreground-prefix-20260815`。兩者都載入 CX26
  `wine`、`winemac.so` 與 `cxcompatdb.so`，不是單純的遊戲 log 管線。
- 處理：只停止上述兩個已辨識 prefix 的 BlackCipher PID，重新查詢後已沒有
  `BlackCipher`、`BlackXchg`、`DwarfAxe`、`MapleStory.exe` 或 CX26 wineserver
  殘留。未刪除 prefix、遊戲檔或 log。
- 修改：`scripts/run-maplestory-cx26-d3dmetal.sh` 新增
  `clean_prefix_session()`；每次非 dry-run 啟動前，對明確的
  `WINEPREFIX`／CX26 `wineserver` 執行 `-k` 再 `-w`，確保上一輪強制關閉留下的
  Nexon/反作弊 helper 不會共用同一 Wine session。缺少 `wineserver` 時直接拒絕
  啟動，不讓測試在無法清理的狀態下繼續。
- 驗證：`test-maplestory-d3dmetal-launcher.sh`、
  `test-maplestory-patch-stack.sh`、shell syntax 與 `git diff --check` 均通過。

### 2026-08-15：啟動前 prefix-clean baseline A/B

- 目的：在發現 Nexon icon 對應的 `BlackCipher64.aes` 殘留後，用新增的 launcher
  cleanup gate 重跑一次 formal baseline；這輪不加入任何 renderer patch。
- 測試：CX26 formal prefix
  `.maplestory-cx26-final-formal-20260815`、D3DMetal/GPTK、CompatDB、正確
  work dir、`CYDER_MSYNC=0`、`CYDER_ESYNC=0`、`--no-otp`；完整 log 為
  `.maplestory-cx26-logs-clean-prefix-baseline-20260815/maplestory-cx26-d3dmetal-20260815-100351-77788.log`。
  launcher 啟動前已執行該 prefix 的 `wineserver -k`／`-w`。
- 無畫面替代驗證：MapleStory 於 `88173.851`、`GR2D_DX11.DLL` 於 `88191.833`
  載入；BlackCipher、DwarfAxe 主／GPU／utility 也正常啟動，約有 `2,785` 次
  `macdrv_client_surface_present`。本次沒有先前多輪常見的
  `macdrv_app_deactivated setting fg to desktop`，但在約 50 秒觀察內仍未出現
  `HybridCore64.dll`、`jypc.dll` 或 `OpenSharedResource`；因無可見畫面，不能宣稱
  登入畫面。
- 收尾：使用相同 formal prefix 再執行一次明確的 `wineserver -k`／`-w`。程序表確認
  已沒有 MapleStory、DwarfAxe、BlackCipher、BlackXchg、NGService 或 CX26
  wineserver；使用者看到的 3 個 Nexon icon 對應程序已清除。

### 2026-08-15：CX26 engine + CX25 winewrapper 啟動層 A/B（負面結果）

- 假設：CX25 正常基準不是直接執行 `wine MapleStory.exe`，而是透過
  `winewrapper.exe --workdir /Users/jjc/games/tms --run -- MapleStory.exe`；
  wrapper 可能負責 CX26 launcher 尚未重現的工作目錄或子程序初始化。
- 測試：使用 CX26 formal engine、D3DMetal/GPTK、CompatDB、`CYDER_MSYNC=0`、
  `CYDER_ESYNC=0` 與新的獨立 prefix
  `.maplestory-cx26-wrapper-oem25-prefix-20260815`，只借用 CX25 OEM 的
  `winewrapper.exe` 作啟動器。第一次未取得 GUI/Mach 權限，只留下
  `server_mach_port`，不作結果；有效 log 為
  `.maplestory-cx26-logs-wrapper-oem25-20260815/maplestory-cx26-wrapper-oem25-20260815-101015.log`。
- 無畫面替代驗證：CX26 + wrapper 於 `88397.962` 載入 MapleStory，
  `GR2D_DX11.DLL` 於 `88412.715` 載入，DwarfAxe 主／GPU／utility 於
  `88431.442`、`88432.857`、`88433.471` 載入；但仍於 `88431.321` 出現
  `macdrv_app_deactivated setting fg to desktop`，沒有 `HybridCore64.dll`、
  `jypc.dll` 或 `OpenSharedResource`，因此 wrapper 沒有改變 CX26 的阻塞階段。
- 收尾：對該 prefix 執行 `wineserver -k`／`-w`，程序表確認沒有 MapleStory、
  DwarfAxe、BlackCipher、BlackXchg、NGService 或 wineserver 殘留。
- 結論：wrapper 啟動層 A/B 為負面結果；不修改正式 CX26 stack，log 保留作為
  可追溯證據。

### 2026-08-15：CX26 OEM25 ntdll userspace file-cache A/B（負面結果，早期崩潰）

- 假設：CX25 OEM 的 `ntdll/unix/file.c` 有 MapleStory 專用的 8 KiB userspace
  file cache，可能影響遊戲與反作弊在 renderer handoff 前的資源讀取時序；本輪只
  暫時將 file-cache implementation 與 `NtCreateFile`、`NtQueryInformationFile`、
  `NtSetInformationFile`、`NtReadFile`、`NtReadFileScatter` 的對應 hook 注入 CX26
  build source，未加入 formal patch stack。
- 建置：`ntdll.so` 增量編譯成功並暫時部署到 CX26 install；在有效測試前先對獨立
  prefix `.maplestory-cx26-ntdll-file-cache-prefix-20260815` 執行
  `wineserver -k`／`-w`，程序表確認沒有 MapleStory、DwarfAxe、BlackCipher 或
  CX26 wineserver。第一次背景啟動因外層工作階段提前結束，沒有產生遊戲 log，不作
  A/B 結論；之後以持續 GUI/Mach 工作階段依同樣清理條件重跑。
- 有效測試 log：
  `.maplestory-cx26-logs-ntdll-file-cache-20260815/maplestory-cx26-d3dmetal-20260815-101912-83035.log`。
  使用 D3DMetal/GPTK、CompatDB、正確 `/Users/jjc/games/tms` work dir、
  `CYDER_MSYNC=0`、`CYDER_ESYNC=0` 與 `--no-otp`。
- 效果：MapleStory 主程式於 `89081.309` 載入，但沒有載入
  `GR2D_DX11.DLL`、DwarfAxe、BlackCipher 後續模組或產生 D3DMetal surface
  presents；初始化期間反覆出現 `c0000005 (EXCEPTION_ACCESS_VIOLATION)`，主程式
  於 `89119.435` 再次在 native code 崩潰並結束，早於 formal CX26 的黑畫面階段。
- 收尾：停止該獨立 prefix 並再次以 `wineserver -k`／`-w` 清理；程序表確認沒有
  MapleStory、DwarfAxe、BlackCipher、BlackXchg、NGService 或 wineserver 殘留。
  已移除 build source 的暫時 file-cache code，重新編譯並恢復 formal CX26
  `ntdll.so`；候選不納入正式 stack，log 與獨立 prefix 保留作為負面 A/B 證據。

### 2026-08-15：重新檢視 CX25 OEM reverse bisect（啟動 gate 判讀）

- `patches/oem25-bisect/README.md` 的分組結果把 CX25 的「早期啟動／無 OTP
  標題與登入」和「進世界後完整畫面」分開：`rev-S`、`rev-W` 仍 pass，`rev-G`
  仍可進世界但畫面殘缺。因此 resize、focus、ClearView/shared-texture 群組不能
  解釋登入前的第一個阻塞點。
- `rev-P` fail、`rev-Pfc` pass：P 組同時包含 ntdll file-cache／no-yield 與 dbghelp，
  而 Pfc 只 reverse 前者並保留 OEM dbghelp。這把早期 gate 的有效差異縮到 OEM
  dbghelp 行為，不支持把 8 KiB file cache 當成必要條件。
- `rev-L` fail、`rev-Lgs` pass：L 組同時包含 kernelbase 與 GStreamer，Lgs reverse
  GStreamer 但保留 OEM kernelbase。這把另一個有效差異縮到 kernelbase 的
  `.dll`→`.tmp`／`.msf` 原始模組名稱還原，不是 raw audio parser。
- CX26 的 `.tmp` patch 已由 module diagnostic log 證實在 BlackCipher 載入
  `Ntdll.dll`、`KERNELBASE.DLL`、`iphlpapi.dll` 時命中，因此目前較不像是完全缺少
  kernelbase sidecar；但 CX26 formal dbghelp 仍實際執行大量 DWARF symbol scan，只有
  `DW_OP_div`／`DW_OP_mod` 除零 guard，並不等價於 CX25 OEM 預設讓
  `SymInitializeW()` 回傳 `ERROR_CALL_NOT_IMPLEMENTED`。
- 判讀：CX26 卡在 `HybridCore64.dll` 以前，比較像反作弊／啟動模組檢查或 crash-report
  symbol 路徑未完成，而不是 resize 觸發載入。先前 CX26 的 dbghelp disable 與 OEM
  binary overlay 都是負面 A/B，故尚不能直接把「完整 OEM dbghelp」列為已證實修正；
  下一輪應改做精確的 CX25 gate 對齊與 log marker 比對，維持 formal stack 不變。

### 2026-08-15：CX25 OEM kernelbase `LoadLibraryExA` 轉換模式 A/B（負面結果）

- 假設：L 組 reverse bisect 的必要差異不只 `.tmp/.msf` sidecar；OEM
  `LoadLibraryExA()` 使用 `file_name_AtoW(name, FALSE)`，而 CX26 使用 `TRUE`，這可能影響
  BlackCipher 以 ANSI API 載入臨時模組。新增一次性實驗 patch
  `patches/experimental/maplestory-cx26-kernelbase-loadlibrarya-ab.patch`，只改這一個
  boolean，沒有改 formal manifest。
- 建置：候選 hook 暫時加入 build script 後成功建置；測試完成後移除 hook，並把 build
  source 與 installed runtime 重新建回 formal `TRUE`。同一 prefix 每次啟動前後均執行
  `wineserver -k`／`-w`；最後確認沒有 MapleStory、DwarfAxe、BlackCipher、BlackXchg、
  NGService 或 wineserver 殘留。
- 測試：D3DMetal/GPTK、CompatDB、正確 work dir、`CYDER_MSYNC=0`、`CYDER_ESYNC=0`、
  `--no-otp`；候選 log 為
  `.maplestory-cx26-bisect-loadlibrarya-20260815/maplestory-cx26-d3dmetal-20260815-110716-95550.log`，
  對照為 clean-prefix baseline
  `.maplestory-cx26-logs-clean-prefix-baseline-20260815/maplestory-cx26-d3dmetal-20260815-100351-77788.log`。
- 效果：候選仍載入 BlackCipher、`GR2D_DX11.DLL` 與 DwarfAxe GPU／utility，反作弊與
  DwarfAxe 時間相對 baseline 提前約 3–5 秒，但兩者都沒有
  `HybridCore64.dll`、`jypc.dll` 或登入流程 marker；surface present 仍持續，沒有登入
  畫面證據。判定 `LoadLibraryExA(TRUE/FALSE)` 不是目前 gate 的修正。
- 收尾：formal runtime 已重新建置；`test-maplestory-d3dmetal-launcher.sh`、
  `test-maplestory-patch-stack.sh`、shell syntax 與 `git diff --check` 通過。

### 2026-08-15：CX25 OEM dbghelp `is_wine_loader()` loader-name A/B（負面結果）

- 假設：CX25 OEM 的 `dbghelp/module.c` 不只辨識 `wine`，還會依 `WINELOADER`
  basename 辨識 `wine`／`wine64`；CX26 的 `is_wine_loader()` 只接受精確字串
  `wine`。若反作弊或 crash reporter 依賴 dbghelp 的 Wine loader module identity，
  這個差異可能影響 `HybridCore64.dll` 前的 gate。
- 變因：新增一次性實驗 patch
  `patches/experimental/maplestory-cx26-dbghelp-loader-name-ab.patch`，只移植
  `is_wine_loader()` 的 loader-name 判斷；沒有移植 OEM dbghelp 其餘舊版 symbol
  結構、配置或呼叫介面。因 CX26 沒有 OEM 的 `wine/heap.h`，候選使用 CX26 已有的
  `HeapAlloc`／`HeapFree`，以免引入無關差異。
- 建置與收尾：候選編譯成功；候選 hook 之後已從
  `scripts/build-wine.sh` 移除，build source 與 installed runtime 已重新建回
  formal CX26。每次啟動前後都對同一 prefix 執行 `wineserver -k`／`-w`，最後沒有
  MapleStory、DwarfAxe、BlackCipher、BlackXchg、NGService 或 wineserver 殘留。
- 測試：使用 D3DMetal/GPTK、CompatDB、正確 work dir、
  `CYDER_MSYNC=0`、`CYDER_ESYNC=0`、`--no-otp` 與同一 prefix。第一次詳細
  `+process` log 只作診斷，因追蹤開銷過大未作 gate 結論；有效窄 log 為
  `.maplestory-cx26-bisect-loader-name-rerun-20260815/maplestory-cx26-d3dmetal-20260815-112057-12170.log`，
  對照為 clean-prefix formal baseline
  `.maplestory-cx26-logs-clean-prefix-baseline-20260815/maplestory-cx26-d3dmetal-20260815-100351-77788.log`。
- 效果：候選完整載入 `BlackXchg`、`BlackCipher64`、`GR2D_DX11.DLL` 與
  `DwarfAxe.exe`，但約 60 秒內仍沒有 `HybridCore64.dll`、`jypc.dll` 或登入流程
  marker；與 formal CX26 相同地停在 DwarfAxe／surface-present 階段。這個
  `is_wine_loader()` 差異不是目前黑畫面 gate 的修正，不納入正式 stack。

### 2026-08-15：CX25 OEM dbghelp debug-info 位址檢查 A/B（負面結果）

- 假設：CX25 OEM 的 `dbghelp.c` 比 CX26 少了
  `base != (ULONG_PTR)base` 檢查；這是 OEM bisect 中尚未單獨拆出的最小差異，可能
  影響 Wine loader debug-info 的 ELF/Mach-O 解析，進而影響反作弊或 crash reporter
  在 `HybridCore64.dll` 前的啟動 gate。本輪只移除這個條件，沒有移植 OEM dbghelp
  的舊 symbol-reference 結構或 `SymInitializeW` 行為。
- 建置：候選 patch 暫時加入 build hook 並成功編譯、部署；測試前後都對獨立 prefix
  `.maplestory-cx26-bisect-dbghelp-base-guard-20260815/prefix` 執行
  `wineserver -k`／`-w`。測試結束後已移除候選 hook、刪除一次性 patch、恢復
  `build/cx26/sources/wine/dlls/dbghelp/dbghelp.c` 的正式條件，並重新建置正式 CX26
  runtime。
- 測試：D3DMetal/GPTK、CompatDB、正確 work dir、`CYDER_MSYNC=0`、
  `CYDER_ESYNC=0`、`--no-otp`；候選 log 為
  `.maplestory-cx26-bisect-dbghelp-base-guard-20260815/maplestory-cx26-d3dmetal-20260815-113206-21602.log`。
  此 log 包含完整的 `loaddll`、`seh`、D3DMetal 與 macOS window 事件。
- 效果：候選里程碑為 MapleStory `93471.362`、BlackXchg `93479.895`、
  BlackCipher64 `93481.413`、GR2D `93485.381`、DwarfAxe 主／第二 instance／utility
  約 `93503.292`、`93506.612`、`93507.194`；之後持續出現 client surface present，
  但沒有 `HybridCore64.dll`、`jypc.dll`、`mlang.dll` 或登入流程 marker。與 formal
  CX26 一樣停在 DwarfAxe 後的黑畫面階段，故此條件不是目前 gate 的修正，不納入正式
  stack。
- 驗證：正式 runtime 重新建置成功；候選 prefix 已再次 `wineserver -k`／`-w` 清理，
  沒有留下 MapleStory、DwarfAxe、BlackCipher、BlackXchg、NGService 或 wineserver。

### 2026-08-15：launcher prefix 清理的 macOS Wine server 時序修正

- 診斷：在尚未建立 wineserver 的新 prefix 上，`wineserver -k` 後立即呼叫
  `wineserver -w` 可能建立／干擾 Mach port，後續 Wine client 只留下
  `Can't check in server_mach_port`，遊戲尚未開始，這些 log 不作 CX26 gate 結論。
- 修改：`scripts/run-maplestory-cx26-d3dmetal.sh` 的每次啟動清理仍先對指定 prefix
  執行 `wineserver -k`，但移除空 prefix 不安全的 `-w`，改為短暫等待讓被終止的
  clients reap。這是測試基礎修正，不是 MapleStory 相容性 patch，也不改 MoltenVK／D3DMetal
  backend。
- 驗證：launcher 靜態測試、shell syntax 與 `git diff --check` 通過；使用同一組
  launcher 環境的無害 `cmd /c exit` 可在 `-k` 後正常建立 Wine server。這輪 module
  diagnostic 的新 prefix 在連續切換期間仍有 Mach-port 失敗，已標為無效診斷，並逐一
  清掉本輪所有 prefix；沒有把它當作遊戲變因結果。

### 2026-08-15：CX25 OEM dbghelp `SymSetScopeFromIndex` A/B（編譯期排除）

- 假設：P 組 reverse bisect 中，OEM `dbghelp.c` 將 symbol index 直接轉成
  `struct symt *`；本輪嘗試只移植 `SymSetScopeFromIndex()` 這個呼叫點，作為比整包
  OEM dbghelp 更小的 A/B。
- 結果：CX26 的現代 `dbghelp` 沒有 OEM 使用的 `symt_index2ptr()` API；候選在
  i386／x86_64 `dbghelp.c` 編譯時都以 `call to undeclared function 'symt_index2ptr'`
  失敗。要使其可編譯必須連帶移植 OEM 的完整 symbol-reference 內部架構，無法再視為
  單一變因，因此不進行 runtime 測試。
- 收尾：已移除一次性 hook／patch，恢復 `symt_index_to_symref()` 正式程式碼並重新
  建置 CX26 runtime 成功；此候選判定為「不可隔離／不納入」，不是遊戲負面結果。

### 2026-08-15：CX26/CX25 message-wait handoff gate A/B 與正式候選

- CX26 clean-prefix baseline log
  `.maplestory-cx26-handoff-trace-20260815/logs/maplestory-cx26-direct-handoff-20260815.log`
  在主視窗最後變更為 `(4,55)-(1370,823)` 後，反覆呼叫
  `NtWaitForMultipleObjects`，handle 清單包含兩個無效值、`NULL` 與 server queue
  handle `0x98`，接著持續收到 `0xc0000008`。此階段沒有
  `HybridCore64.dll`、`jypc.dll` 或後續 shared-resource handoff。
- CX25 OEM sync control log
  `.maplestory-cx25-sync-control-20260815.log` 顯示相同啟動路徑後直接進入正常的
  `RtlWaitOnAddress`／`NtWaitForAlertByThreadId`；其 `HybridCore64.dll`、`jypc.dll`
  與最後 resize marker 依序出現，沒有 CX26 baseline 的 invalid-handle 重試型態。
- LLDB 只作診斷，沒有修改 runtime：CX26 的 stack 是
  `NtUserMsgWaitForMultipleObjectsEx` → `win32u!wait_objects` →
  `win32u!wait_message` → `NtWaitForMultipleObjects`；因此 gate 位於 CX26
  `win32u/message.c` 的 message-wait handoff，而非 D3DMetal `WaitOnAddress`。
- 暫時 A/B：
  - `CYDER_MAPLESTORY_SKIP_INVALID_MSG_WAIT=1` 直接略過觀察到的 NULL handle
    型清單，能載入 `HybridCore64.dll` 與 `jypc.dll`，但僅是診斷性 bandage，未納入。
  - `CYDER_MAPLESTORY_LEGACY_DRIVER_WAIT=1` 模擬 CX25 的 driver-event 早退，亦能
    通過同一 gate；仍留下一次非重複性的 `0xc0000008`，所以沒有直接採用環境變數。
- 正式候選修正：新增
  `patches/maplestory-cx26-message-wait-handoff.patch`。它保留
  `process_driver_events()` 的結果；若已有 driver event 就直接回傳 queue result，
  否則只執行一次 `NtWaitForMultipleObjects`，收到 server queue 後再處理一次 driver
  event，不再使用 CX26 原本的反覆 retry 迴圈。這與 CX25 OEM `wait_message()` 的
  控制流一致，且不依賴診斷環境變數。
- 已把 patch 加入 `scripts/build-wine.sh --maplestory` 與
  `patches/README.md`；clean CX26.3.0 patch-stack test、launcher test、shell syntax
  與 `git diff --check` 均通過。候選 `win32u.so` 已編譯並部署到 CX26 runtime，
  hash 與 build output 一致。
- 正式候選測試使用全新 prefix
  `.maplestory-cx26-formal-wait-20260815/prefix`、D3DMetal/GPTK、CompatDB、正確
  `/Users/jjc/games/tms` 工作目錄、`CYDER_MSYNC=0`、`CYDER_ESYNC=0`、`--no-otp`；
  log 為
  `.maplestory-cx26-formal-wait-20260815/logs/maplestory-cx26-d3dmetal-20260815-130525-50958.log`。
  里程碑為 MapleStory `99069.145`、DwarfAxe `99104.927`、
  `HybridCore64.dll` `99108.203`、`jypc.dll` `99118.813`；其後持續出現有效
  handle wait 與 client-surface present，程序穩定觀察約一分鐘。log 仍有一次
  `0xc0000008`，但不再形成 baseline 的重複卡住型態。
- 收尾：停止該獨立 prefix 後，程序表確認沒有 MapleStory、BlackCipher、DwarfAxe、
  NGService 或 wineserver 殘留。由於本輪使用 `--no-otp` 且無法直接觀看 Wine 視窗，
  這是「已通過 CX25 對應登入前 gate、待視覺登入畫面確認」，不是最終登入畫面驗收。

### 2026-08-15：CX26 message-wait handoff 窄化候選成功驗證

- 修改：保留 CX26 upstream 的 `do...while` driver-event retry；只在第一次
  `process_driver_events()` 已回報 queue ready 時，直接返回 server-queue 結果，避免
  MapleStory 在 message handoff 階段提供的無效 handle 清單被送進
  `NtWaitForMultipleObjects`。正式 patch 已同步更新為此較窄的控制流，未全域忽略
  `STATUS_INVALID_HANDLE`，也未修改 D3DMetal backend 或 MoltenVK。
- 建置／部署：`build/cx26/sources/wine/dlls/win32u/message.c`、CX26 installed
  `win32u.so` 與 `patches/maplestory-cx26-message-wait-handoff.patch` 三者一致；
  保留既有 `scripts/build-wine.sh --maplestory` patch stack。
- 測試：使用同一個已初始化的
  `.maplestory-cx26-formal-wait-20260815/prefix`、D3DMetal/GPTK、CompatDB、
  `/Users/jjc/games/tms` work dir、`CYDER_MSYNC=0`、`CYDER_ESYNC=0` 與 `--no-otp`；
  完整 log 已保存於
  `.maplestory-cx26-logs-message-wait-narrow-20260815/maplestory-cx26-d3dmetal-20260815-141125-70582.log`。
- 效果：`GR2D_DX11.DLL` 於 `103031.801` 載入，DwarfAxe 於 `103049.731` 開始，
  `HybridCore64.dll` 於 `103053.031`、`jypc.dll` 於 `103063.548` 載入；之後產生
  `2,908` 次 `macdrv_client_surface_present`，未出現 `c0000008` 或
  `STATUS_INVALID_HANDLE`。使用者實際確認畫面已進入 MapleStory 登入畫面。
- 結論：此窄化修正保留 upstream wait/retry 架構，同時通過目前 CX26 的 MapleStory
  handoff gate；可作為 CX26 正式 engine 的登入畫面候選。

### 2026-08-15：功能群採用範圍調整

- `w1-win32u-vulkan-soname.patch` 改列為不採用的特殊 build fallback：移出預設
  CX26 patch order 與 release manifest，只有明確指定
  `--vulkan-soname-fallback` 才套用；D3DMetal 正式路徑不依賴它，也不依賴 MoltenVK。
- `maplestory-cx26-no-sched-yield.patch` 改為在 `NtYieldExecution()` 內檢查目前
  process image basename，只有 `MapleStory.exe` 返回 `STATUS_NO_YIELD_PERFORMED`；
  其他 Wine 應用程式保留原本的 `sched_yield()` 行為。
- `maplestory-cx26-message-wait-handoff.patch` 提升為所有 CX26 build 都套用的
  `win32u` 共用修正。它只在 queue 已就緒時保留 driver-event 結果，仍保留 upstream
  retry 與真正 invalid handle 的錯誤語義，不對其他遊戲吞掉 invalid handle。
- 其餘已驗證的 media／WineD3D、loader／DWARF、D3D11 shared resource、D3DMetal
  view、window／fullscreen／helper 功能群維持正式採用；BlackXchg 與 scheduler
  行為仍保留精確的 MapleStory 條件。
- 驗證：patch stack、`test-build-wine`、engine manifest、D3DMetal launcher 與
  shell／diff checks 均通過；installed ntdll 的 process guard 仍待增量建置後做
  smoke test。

### 2026-08-15：CX26 scheduler guard 增量建置與最終畫面驗證

- 建置：將生成中的 `dlls/ntdll/unix/sync.c` 以 x86_64 toolchain 增量編譯，
  只更新 CX26 installed runtime 的
  `install/wine-cx26-x86_64/lib/wine/x86_64-unix/ntdll.so`；舊檔另存於
  `/private/tmp/ntdll-cx26-before-maplestory-guard.so`。編譯結果確認為 Mach-O
  x86_64，避免把 Apple Silicon arm64 物件誤裝入 CX26。
- 啟動前：確認 formal prefix 沒有既有 MapleStory、BlackCipher、DwarfAxe 或
  wineserver，並由 launcher 先執行同 prefix wineserver cleanup。
- 測試：使用 CX26 D3DMetal、GPTK、CompatDB、正式遊戲目錄與
  `CYDER_MSYNC=0`／`CYDER_ESYNC=0`／`--no-otp`；完整 log 為
  `/private/tmp/cx26-policy-20260815-logs/maplestory-cx26-d3dmetal-20260815-145055-79544.log`。
- 效果：log 依序確認 `MapleStory.exe`、`BlackXchg.aes`、`BlackCipher64.aes`、
  `DwarfAxe.exe`、`HybridCore64.dll`、`jypc.dll` 載入；主視窗建立為
  `1374x827`，共記錄 `6,319` 次 `macdrv_client_surface_present`，沒有
  `c0000008`、`STATUS_INVALID_HANDLE` 或 `invalid handle`。使用者確認實際畫面
  已進入 MapleStory 登入畫面。
- 結論：scheduler 對齊在 installed CX26 已生效，但只對 `MapleStory.exe`
  basename 返回 `STATUS_NO_YIELD_PERFORMED`；其他 process image 仍走原本的
  `sched_yield()`。本輪四項採用範圍調整完成驗收。

### 2026-08-15：補齊 CX26 OEM25-equivalent GStreamer media stack

- 修改：`scripts/build-media-stack.sh` 新增 `minimal`／`full-video` profile、
  `--full-video` shortcut 與 `--media-install` 隔離安裝選項；建置目錄也依 profile
  分開，避免 full-video 的 Meson configure 覆蓋原本可用的最小影音 build。
- full-video 具體啟用 GStreamer base/good/ugly/bad 的 OEM25 對應插件：
  `applemedia`、`asfdemux`、`audioparsers`、`avi`、`deinterlace`、`id3demux`、
  `isomp4`、`playback`、`videoconvertscale`、`videofilter`、`videoparsers`、
  `wavparse`，以及 audio convert/resample、typefind、OpenGL integration。
  `gst-plugin-scanner` 也以 x86_64 helper 安裝，讓 GStreamer registry discovery
  路徑完整；`gst-libav` 維持關閉，避免引入尚未準備的 FFmpeg 依賴。這個 profile
  的完整性定義為與 OEM25 實際可用插件集合對齊。
- 預期效果：CX26 `winegstreamer` 不再只有 `libgstcoreelements.dylib`，可在
  engine 層發現 OEM25 使用的影片 demux/parser、Apple media 與 playback plugin；
  原本的最小 profile 仍可作為音訊與啟動 regression baseline。
- 測試紀錄：新增 `tests/test-build-media-stack.sh`，檢查 profile 介面、Meson
  feature flags、FFmpeg 隔離、plugin scanner 及 full-video 安裝驗證清單。
  full-video build 已完成，輸出為
  `install/media-cx26-full-video-x86_64/`（GLib 2.78.0／GStreamer 1.24.4，22 個
  plugin，x86_64）；用 x86_64 GStreamer API 逐一載入 22 個 plugin，結果為
  `22 loaded, 0 failed`。
- MapleStory lifecycle smoke 使用全新 prefix
  `/private/tmp/cx26-full-video-prefix-20260815/`，log 為
  `/private/tmp/cx26-full-video-logs-20260815/maplestory-cx26-d3dmetal-20260815-154900-2143.log`。
  full-video media path 下 `winegstreamer.dll` 載入，MapleStory、BlackXchg、
  BlackCipher64、HybridCore64、jypc 依序出現，建立 `1374x827` 視窗並產生
  `1,553` 次 surface presents；未見 `c0000008`、`STATUS_INVALID_HANDLE` 或
  engine crash。這是啟動／媒體 runtime smoke，不等同於已在遊戲內觸發一段影片；
  實際影片播放仍需登入後以遊戲內容驗收。

### 2026-08-15：將 full-video GStreamer 內嵌 Cyder011 engine artifact

- 修改：`scripts/bundle-wine-dylibs.sh` 會把 media install 的全部 GStreamer
  plugin dylib 及其遞迴依賴納入 engine；插件移至
  `lib/wine/gstreamer-1.0/`，`gst-plugin-scanner` 移至
  `libexec/gstreamer-1.0/`，並對跨目錄依賴改寫為可重定位的
  `@loader_path/../x86_64-unix/…`。核心 GLib/GStreamer dylib 仍位於
  `lib/wine/x86_64-unix/`。
- 修改：`scripts/run-maplestory-cx26-d3dmetal.sh` 優先使用 engine 內建 media
  stack；`--media-install`／`MEDIA_INSTALL` 仍可覆寫，方便 A/B 與故障診斷。啟動
  log 現在記錄 `MEDIA_SOURCE`、plugin directory 與 scanner path。
- 修改：`scripts/pack-engine-artifact.sh` 的預設 media profile 改為 `full-video`，
  並在封裝前要求插件目錄與 x86_64 `gst-plugin-scanner`；`--media-profile minimal`
  保留為明確的非影片 fallback。DXMT／DXVK 仍維持獨立 graphics payload。
- 效果：Cyder011 engine artifact 不再依賴建置機的 `.brew-x86` 或外部
  `install/media-*` 路徑；完整影音能力與 engine 一起發佈，符合「只維護一個版本」
  的部署方向。
- 測試：以 full-video 產物建立暫存 engine bundle，確認 22 個 plugin 為
  `x86_64`、所有 plugin `ctypes` 載入結果 `22/22`，GStreamer
  `gst_plugin_load_file` 結果 `22/22`，scanner 與核心 dylib 無 build-tree／
  `.brew-x86` 絕對路徑，且所有 dylib minOS ≤ 10.15。

## 下一步與驗收

1. 保留目前已驗證可建置的 CX26 formal stack，包含新的 message-wait handoff patch；
   legacy/plain-layer 只作為可回退的 A/B 開關，不將 direct-view 負面實驗重新加入正式 stack。
2. 下一輪若要判斷 `jypc` 以前的差異，必須使用與 CX25 成功基準相同的有效 BeanFun
   argv（ServiceAccountID 與短期 OTP 只在記憶體／argv 傳遞，不寫入 log）；
   `--no-otp` 僅能作 lifecycle smoke test。
3. 以相同遊戲目錄、work dir、GPTK、CompatDB 與 prefix 做單一變因 A/B；每個
   variant 先編譯、再啟動，並在本檔追加修改、log 路徑與效果。
4. 若找到能使 CX26 顯示登入畫面的 variant，保留最小必要 patch，做乾淨重建與
   patch/test regression。
5. 最終必須有可視影像或使用者看到並確認 CX26 登入畫面；僅有 cursor、process
   alive、D3DMetal `Present` 或 client-surface event 不算成功。
