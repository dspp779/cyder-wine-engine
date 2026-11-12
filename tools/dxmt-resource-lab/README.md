# DXMT resource improvement lab — phase 1

2026-10-03：開始執行下一版改進計劃。**獨立 x86_64 PE DLL 已建置；CPU 統計測試通過；GPU 驗收尚未執行。** 本機現在是 macOS 27.0.1，缺少可用的 Rosetta，`arch -x86_64 /usr/bin/true` 回報 Bad CPU type。已向使用者詢問安裝與授權同意，未自行接受條款。

## 實作

- `01-initializer.patch`：在單次初始化前預留足夠 command + reference tracker 空間，空間不足先 flush 已完整建立的命令，再進行當次初始化；不再用會退出 do/while(0) 的 continue。上傳 buffer 必須配置成功後才串入 copy command，Metal upload allocation 失敗不進入可重用 FIFO。CreateBuffer／CreateTexture1D／2D1／3D1 接住 bad_alloc，回報 E_OUTOFMEMORY。零填充擴張先取得新 buffer、必要時提交舊命令，再切換持有參照，消除原先雙 flush 與漏初始化；本階段尚未改成幾何成長。
- Initializer 銷毀前先清理 allocation references，再釋放存放追蹤節點的 CPU heap。
- `02-submission-statistics.patch`：初始化 flush 的時間不再被 commit 計時漏掉；統計只納入已存在且非當前的 frame，從有效樣本建立最小值，修正 event_stall 最小值誤取 sync_count。
- 預設停用的 `DXMT_CYDER_RESOURCE_PROFILE=1`：initializer 聚合操作數、bytes、bridge calls、capacity flushes、zero grows、鎖等待／拷貝／upload allocation 耗時；分別保留最近 64 筆 upload acquire／encode／commit 與 64 筆 frame／chunk／event 對應資料。只在物件銷毀時輸出，沒有逐列 log。這是計時第一階段，尚未涵蓋一般 newTexture／newBuffer、PSO 排隊與完整遊戲 trace。

故障注入僅對 executable basename **cyder-resource-probe** 生效：

- `DXMT_CYDER_TEST_SMALL_HEAP=1` 將 initializer CPU heap 從 1 MiB 改成 4 KiB。
- `DXMT_CYDER_TEST_FAIL=reserve|upload|retain|command|zero|clear` 在第二個匹配點模擬一次配置失敗。
- `DXMT_CYDER_TEST_FAIL_ALWAYS=1` 在第一次觸發後持續失敗，用來檢查沒有無限 retry。

這些 hooks 驗證錯誤控制流程，不等於真實 Metal 記憶體耗盡測試。一般遊戲即使繼承這些環境變數也不啟用故障注入。

## 建置與重現

在 `cyder-wine-engine` repo 執行，先讀 AGENTS.md 和 incremental build 文件。僅編譯 PE D3D11 層，不改正式 install／Wine host／minOS，不發布或更新 engine pin。

```bash
python3 tools/dxmt-resource-lab/prepare.py \
  --upstream /private/tmp/dxmt-implementation-20261003/dxmt-v0.80.tar.gz \
  --gametomac /Applications/GameToMac.app/Contents/Resources/Sources/OverwatchRuntime/dxmt-overwatch-source.tar.gz \
  --workspace build/dxmt-resource-lab-fresh

LLVM_MINGW="$PWD/build/llvm-mingw-20260616-ucrt-macos-universal/bin" \
DXMT_RELEASE="$PWD/install/wine-cx26-x86_64/lib/dxmt" \
WINEBUILD="$PWD/build/arm64-experimental-cx26/build/tools/winebuild/winebuild" \
python3 tools/dxmt-resource-lab/build.py --workspace build/dxmt-resource-lab-fresh
```

`prepare.py` 沿用 pipeline lab 對兩個來源 archive 的固定 SHA-256 驗證，再依序套用本目錄兩個 patch。上游 archive 可自 `https://codeload.github.com/3Shain/dxmt/tar.gz/refs/tags/v0.80` 取得。

此次 `winebuild` 使用已存在、確認版本為 Wine 11.0 的原生 arm64 工具，只做 PE builtin 標記；**沒有改用 ARM Wine 執行測試**。有 Rosetta 的主機也可指定原 x86_64 `build/cx26/sources/wine/build64/tools/winebuild/winebuild`。來源／runtime identity、編譯器、winebuild 路徑與產物 SHA-256 在 build/build.json。

## 測試

CPU 統計測試（直接使用修改後 header）：

```bash
clang++ -std=c++20 -O2 -mmacosx-version-min=11.0 \
  -I build/dxmt-resource-lab-20261003/source/src/dxmt \
  -I build/dxmt-resource-lab-20261003/source/src/util \
  tools/dxmt-resource-lab/statistics-test.cpp -o /private/tmp/dxmt-statistics-test
/private/tmp/dxmt-statistics-test
```

GPU 驗收（需要可執行 x86_64 Wine 與桌面 Metal 存取）：

```bash
python3 tools/dxmt-resource-lab/test.py \
  --engine install/wine-cx26-x86_64 \
  --overlay build/dxmt-resource-lab-20261003/overlay \
  --compiler build/llvm-mingw-20260616-ucrt-macos-universal/bin/x86_64-w64-mingw32-clang++ \
  --compatdb $HOME/ogom/Cyderbits/compatdb/compiled/compatdb.cdb \
  --output /private/tmp/dxmt-resource-acceptance
```

矩陣涵蓋 8192／16384 overflow、tight/padded uploads、mixed SRV/RT/DS clear、零填充連續尺寸增長、4 KiB heap、一次／持續配置失敗、buffer／texture 錯誤後讀回、非白名單程序忽略故障注入，以及 profile 開關／log 上限。用舊 overlay 加 `--baseline` 重現既知 overflow failure，不能將此失敗算成 graphics pass。

此工具只結束自己的測試 prefix。缺 Rosetta、Mach service 失敗、timeout、沒有測試 marker、錯誤 HRESULT 或讀回不符都不是通過。GPU 矩陣實際跑過後仍需重跑 `tools/dxmt-pipeline-lab/test.py` 的 cache/draw regression，再做遊戲內首次真命中 A/B。

## 尚未完成的階段

GPU 驗收是本階段的下一個完成條件。批次 pitched upload、allocator inclusive 回收邊界、zero buffer 幾何成長、獨立 archive 寫入佇列尚未套用；per-resource upload wait 仍需遊戲 trace 支持。正式效能承諾、完整新楓之谷驗收與發行打包均未完成。

基礎 DXMT 授權見 `LICENSE-DXMT`；來源與先前研究見 `../dxmt-pipeline-lab/README.md`、`../dxmt-resource-study/README.md`。
