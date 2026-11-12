# DXMT resource / CPU / submission study

2026-09-21 的研究重現工具。沒有部署 buffer、texture 或同步修改；原始碼與 GPU readback 揭露 DXMT v0.80 初始化遺失問題。

完整分析：[`../../docs/maplestory-dxmt-resource-cpu-submit-study.zh-TW.md`](../../docs/maplestory-dxmt-resource-cpu-submit-study.zh-TW.md)。

- `probe.cpp`：使用硬體 D3D11 裝置；比較 257×512 RGBA8、row pitch 1028/1280 的 64 張紋理建立時間，逐列讀回所有紋理；另以 4/8 個 2048-slice array 觸發初始化命令區邊界，複製至 atlas 後逐像素檢查。
- `reproduce.py`：編譯 probe、建立新的 disposable prefix、指定 overlay、保留原始 log。逾時、無測試輸出或讀回不符均不算通過。只終止自己 prefix 的 wineserver。
- `check-ring.py`：抽出原始 RingBumpState template，使用 fake allocator 比較 `<` 與 `<=`；不是 GPU 壽命驗證。
- `evidence/`：本輪原始資料。`overflow.log`、`repeat-16384.log` 的 return code **1 是已確認的繪圖正確性失敗**，不是測試通過；`--expect-overflow-bug` 只是確認重現既知問題。

```bash
python3 tools/dxmt-resource-study/reproduce.py \
  --engine $HOME/ogom/cyder-wine-engine/install/wine-cx26-x86_64 \
  --overlay $HOME/ogom/cyder-wine-engine/build/dxmt-pipeline-lab/overlay \
  --compiler $HOME/ogom/cyder-wine-engine/build/llvm-mingw-20260616-ucrt-macos-universal/bin/x86_64-w64-mingw32-clang++ \
  --compatdb $HOME/ogom/Cyderbits/compatdb/compiled/compatdb.cdb \
  --output /private/tmp/dxmt-resource-reproduction \
  --expect-overflow-bug

python3 tools/dxmt-resource-study/check-ring.py \
  --source build/dxmt-pipeline-lab/source/src/dxmt/dxmt_ring_bump_allocator.hpp \
  --output /private/tmp/dxmt-ring-reproduction
```

GPU 測試需要桌面 Wine/Mach service/Metal 存取。檢查修正版本時去掉 `--expect-overflow-bug`，要求 16384/16384 讀回正確。分析針對本機 v0.80 source；不能推論其他 DXMT 版本或 D3DMetal 有相同缺陷。沒有 MapleStory 實機幀時間結果。
