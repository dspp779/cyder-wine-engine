# DXMT v0.80：MapleStory pipeline archive 實驗

日期：2026-09-21。這是獨立 renderer 實驗，不在 Wine production patch apply list，
也沒有修改 engine-release.json、正式 engine install、Cyder 預設或遊戲程式。

## 目的與邊界

把已實際遇到的普通 vertex/pixel graphics pipeline 保存成 Metal binary archive，
後續程序建立相同 pipeline 時先嚴格查詢 archive。仍會建立本次程序的 MTLFunction／
MTLRenderPipelineState；不是跳過繪圖，也不是把所有編譯或 buffer 配置移出第一幀。
尚未遇過的特效仍需付首次成本。Compute、geometry、tessellation 沿用 upstream。

只在 process basename 是 `MapleStory` 或 `cyder-pipeline-probe`，且設定了絕對 POSIX
路徑 `DXMT_CYDER_PIPELINE_CACHE` 時啟用。目錄需預先建立；一次只給一個遊戲程序使用。
預設不啟用。需 Wine 的 Z: 對應主機 `/`，同本 repo 的直接啟動流程。

- key：shader 原始內容、variant、編譯 flags、Metal 版本、明列的完整 graphics
  descriptor 欄位、GPU registry ID、macOS major/minor/patch、source/runtime build identity。
  不 hash padding、pointer 或暫時的 Metal handle。
- 命中要求 Metal 的 `fail_on_binary_archive_miss` 成功；不以「檔案存在」當作命中。
- 每個 archive 有 SHA-1 完整性 sidecar；損毀、截斷或缺校驗資料時不交給 Metal parser。
  SHA-1 在這裡是 accidental-corruption 檢查，不是來源認證或安全邊界。
- Metal bridge 回傳的 NSError 是 autoreleased／借用物件；局部錯誤使用非 owning
  wrapper，只對交回 owning caller 的錯誤 retain，並使用局部 autorelease pool。
  這避免 error-path double release／pool drain 時 hang。
- 缺檔、拒絕、寫入失敗皆回正常 pipeline 建立。archive 收集導致建立失敗時，
  移除 archive collection descriptor 後再試正常建立。
- 編譯完成先 publish ready、通知 render thread、解鎖及排入 dependent tasks，才保存。
  scheduler 改為在 pipeline/shader map 之前析構並 join，避免 worker 存取已釋放物件。
  持久化仍占用編譯 worker，未聲稱完全消除 worker contention。
- archive 限 4,096 個／總 256 MiB／每個 8 MiB；sidecar 每個 40 bytes 另計。
  達上限後正常繪圖，不增加 archive。沒有 eviction 或跨程序 quota lock。
- log 每程序最多 128 筆 `CYDER_PSO hit/miss/saved/...`。

## 來源

GameToMac 0.1.19 Alpha build 57，官網下載：
<https://updates.gametomac.com/GameToMac-0.1.19-alpha-build57.dmg>

對照 `/Applications/GameToMac.app/Contents/Resources/Sources/OverwatchRuntime/` 的
`dxmt-overwatch-source.tar.gz`、`build.py`，及 `Sources/OVERWATCH.md`。
作者隨包提供修改後 DXMT 的 MIT 授權，保留於 `LICENSE-DXMT`。
本實驗縮小移植 archive、completion callback、worker lifetime、Unicode env 讀取；
新增 checksum sidecar，不帶入 Overwatch 的 recipes、預編譯猜測、遊戲設定或 shader IR。
`build.py` 改寫自隨包的 PE-only builder，重用目前官方 v0.80 的 Metal bridge/helper library。

基準原始碼：<https://github.com/3Shain/dxmt/tree/v0.80>。
`prepare.py` 以固定 SHA-256 驗證官方 tarball 與 GameToMac source tarball，後者只補
官方 tag archive 缺少的 `libs/DXBCParser` submodule。patch 套到官方 v0.80，
不是把 GameToMac 整棵修改樹視為基準。工具鏈、69 個 source files、overlay identity
與 DLL SHA-256 記在 `build/build.json`。

## 重現建置

在 `$HOME/ogom/cyder-wine-engine` 執行；先讀本 repo AGENTS.md。
`--workspace` 指向本 repo `build/` 下新的實驗目錄。原始資料下載到自己的 cache。

```bash
python3 tools/dxmt-pipeline-lab/prepare.py \
  --upstream /private/tmp/gametomac-study-20260921/dxmt-v0.80.tar.gz \
  --gametomac /Applications/GameToMac.app/Contents/Resources/Sources/OverwatchRuntime/dxmt-overwatch-source.tar.gz \
  --workspace build/dxmt-pipeline-lab-fresh

LLVM_MINGW="$PWD/build/llvm-mingw-20260616-ucrt-macos-universal/bin" \
DXMT_RELEASE="$PWD/install/wine-cx26-x86_64/lib/dxmt" \
WINEBUILD="$PWD/build/cx26/sources/wine/build64/tools/winebuild/winebuild" \
python3 tools/dxmt-pipeline-lab/build.py --workspace build/dxmt-pipeline-lab-fresh
```

這只重編 x86_64 PE `d3d11.dll`。host `winemetal.so` 保持官方 v0.80，minOS 15.0，
符合本 repo 已有 DXMT 例外；沒有新增 host make 或改 Wine minOS。
本機 install 所帶的此 x86_64 bridge 沒有 codesign，實驗 overlay 保持位元組相同；
這是已實測可載入的 development payload，不是正式簽署 engine release。
`build.py` 只重建指定 workspace 的 `build/`、`overlay/`，不可指向使用中的 overlay。

## 測試

```bash
LLVM_MINGW="$PWD/build/llvm-mingw-20260616-ucrt-macos-universal/bin" \
python3 tools/dxmt-pipeline-lab/test.py \
  --engine install/wine-cx26-x86_64 \
  --overlay build/dxmt-pipeline-lab/overlay \
  --compatdb $HOME/ogom/Cyderbits/compatdb/compiled/compatdb.cdb \
  --output /private/tmp/cyder-pso-new-test
```

輸出目錄必須不存在。每輪實際 Draw、CopyResource、Map，核對 2 種 pixel shader ×
2 種 sample mask × 1,024 pixels。驗證停用、cold、warm、corrupt、repair、校驗相符但 Metal 內容無效、其他程序拒用、
不存在目錄、4,096 entry 上限、超過 MAX_PATH 的中文路徑 cold/warm。
只停止該測試 prefix 的 wineserver；timeout／像素錯誤／未真的命中均失敗。

這些是 graphics correctness/cache tests，**不是楓之谷 first-hit 驗收或效能 benchmark**。
準備腳本 dry-run/apply 產出的 source tree 也要和已建置來源逐檔比對。
本次證據與結論見 `../../docs/gametomac-maplestory-pipeline-study.zh-TW.md`。

## 楓之谷 A/B 接法

使用既有 `scripts/run-maplestory-cx26-d3dmetal.sh --graphics-backend dxmt`，
同一個 `--wine-install`、獨立的 `--wineprefix`、`--compatdb`、`--log-root` 與實際
`--launch-exe`。先 `--no-otp --dry-run`，再按 engine workflow 進行直接啟動。

所有 A/B 輪固定 `CYDER_GRAPHICS_BACKEND_PATH` 為本次 overlay 的絕對路徑；
A：unset `DXMT_CYDER_PIPELINE_CACHE`；B：設成獨立的持久 cache 目錄，
先完成一次真命中並正常退出，再新 session 測相同第一下。

backend log 必須明列實驗 overlay，B 必須有 `CYDER_PSO hit`，否則不能算測到修正。
保持角色、地圖、技能、畫質、同步、I/O flags 相同，不揮空先暖；各至少 3 次。
記錄 Present gap、PSO wait、實際 allocator call-stack、真命中／buff 分開。
若 archive 有命中但 first-hit gap 不降，就保留為負結果，不把它納入正式設定。

回復：取消 `CYDER_GRAPHICS_BACKEND_PATH` 與 `DXMT_CYDER_PIPELINE_CACHE`。
正式 install 與遊戲檔未被此實驗覆寫；一般啟動不會選用它。
