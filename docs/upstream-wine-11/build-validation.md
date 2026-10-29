# PR 3 Runtime 建置驗證

目標：CX26.3／Wine 11.0，加上 PR #3 的兩項視窗 backport。這是隔離 install 的開發驗證，不會替換使用者的 Cyder runtime。

## 環境與已修正問題

- macOS 27.2（26B123），Rosetta x86_64 系統執行探測通過。
- 此機 CLT 的 libxcrun 只有 ARM64；`arch -x86_64 /usr/bin/clang` 會在 compiler discovery 階段失敗。
- 實測可用 `/Library/Developer/CommandLineTools/usr/bin/clang` 加明確 SDKROOT、`-arch x86_64` 和 10.15 deployment flag；小程式的架構、minOS 與實際執行均驗證通過。
- 增加 `CYDER_HOST_CLANG`／`CYDER_HOST_CLANGXX` 給 runtime dependency wrapper 與相關 host plugin／shim；維持預設 `/usr/bin/clang`。有空格的 compiler 路徑會安全引用。媒體建置增加 `CYDER_HOST_PYTHON`，預設不變。
- 本機 Homebrew 使用獨立 `.brew-x86`。它在 macOS 27 的 Intel 工具發現仍經過舊 trampoline，因此本機 shim 改為 ARM64 xcrun discovery，並使用實際 CLT make/ar/ranlib/python3。這些是 gitignored 建置環境修復，不包含在 runtime 或 PR 的產品檔案。
- 相關 bundle／MoltenVK 測試改為接受同一個 compiler override，繼續驗證 x86_64 與各 minOS ceiling。
- graphics pack 測試改用明確 minimal fixture，另有 full-video 缺少媒體時必須拒絕的負向測試；沒有放寬產品 full-video 預設或發行 gate。

## 可重現的 compiler 設定

```bash
export OGOM="$PWD"
export MACOSX_DEPLOYMENT_TARGET=10.15
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk
export CYDER_HOST_CLANG=/Library/Developer/CommandLineTools/usr/bin/clang
export CYDER_HOST_CLANGXX=/Library/Developer/CommandLineTools/usr/bin/clang++
export CYDER_HOST_PYTHON=/Library/Developer/CommandLineTools/usr/bin/python3
export CC="$CYDER_HOST_CLANG -arch x86_64"
export OBJC="$CC"
export CXX="$CYDER_HOST_CLANGXX -arch x86_64"
export OBJCXX="$CXX"
```

CLT 路徑是本機實測值，其他機器應以可用 Apple developer toolchain 為準。Wine source/build/install 皆在目前 worktree；封存檔重用原專案下載，未重用其他 Wine build 的 object。

## 驗證狀態

建置進行中，尚未宣稱 runtime 或完整回歸通過。40 項測試初盤點為 35 通過／5 失敗；其中 4 項已修正並重跑通過，CompatDB plugin 等待正式 configure header。最後結果需以本文件後續更新為準。
