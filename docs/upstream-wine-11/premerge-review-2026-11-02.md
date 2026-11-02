# PR #3／#6 合併前審查與補驗（2026-11-02）

> 後續更新：[AX-only 根因、獨立修正與本機補驗](ax-unminimize-2026-11-02.md) 已完成 32／64 位元控制及 Retina GL／GDI 雙開。本文的 AX 失敗與單開缺口保留為先前版本的歷史結果；最新狀態、Dock 限制及硬體需求以新報告為準。

本輪只使用乾淨工作樹、私有測試 runtime 與複製的 prefix／遊戲。沒有替換正式 Cyder runtime，也沒有帶入主工作區的 MapleStory、MoltenVK 等未提交修改。未合併 PR、發佈引擎或關閉 issue；#7、#8 的實驗分支不納入本輪。

## PR #2 是否已包含

**是。** `git merge-base --is-ancestor 92f813b 568acec` 成功。

| 提交 | 關係 |
|---|---|
| `92f813baf5e90754b1adbd04b18aa71fd0957d60` | PR #2 的完整 head，透過 `e60765f` merge 進 #3，未壓成不同提交 |
| `8f685ad` | #3 補回 context bind 不應送出 PRESENT 的上游前置修正，保留合法 native flush／present |
| `96f78c9` | #3 保留 interval 更新時的既有 flush flags，並新增預設關閉的 profiling |
| `76a9dff` | #3 補 GL→GDI 隱藏舊 client view，以及重新建立 GL context 的首幀呈現 |
| `568acec` | 本輪審查前 #3 head；含三遊戲實測報告，不含 #6 的排序修正 |

#2 單獨的 front-buffer patch 不是最終完整 backport。審查後仍不另行合併或關閉 #2；應在 #3 最終處理時核對 GitHub 狀態與包含關係。

## 審查發現與處理

1. **與最新 main 的真實衝突：** main 的 PE signing 測試與 #3 的 runtime-kit／DXMT／soak 測試都加在 `tests/run.sh` 尾端。`merge-tree` 確認衝突後，在獨立 #3 審查分支整合 main `a7f4847`，保留兩邊所有入口，提交 `f36ba20`。沒有從髒工作區複製修改。#6 另同步這項整合。
2. **舊工具鏈阻塞可繞開而不改系統：** 預設 x86_64 `/usr/bin/python3` 仍進入缺少 x86_64 slice 的 CLT libxcrun。使用既有 Python 3.12、實體 CLT clang／clang++／ar／ranlib／ld、明確 SDKROOT 與 10.15 flags 後，真實四語言 Meson 測試通過。Meson 1.12.1 複製到私有測試依賴目錄，未安裝系統套件或接受 Xcode 授權。
3. **本輪未發現其他可由目前證據確認的產品程式碼阻擋項目。** 已審閱 patch 順序／遷移、flush flags／NULL context、GL↔GDI／context 重建、預設關閉的診斷、bundle token 解析與拒絕缺檔、test-kit 隔離及 #6 sibling fallback。這是本次自行審查，不是第三方核准；5,054 筆上游清單仍只是原文件定義的盤點，未宣稱逐筆語意審查。

## 本輪實際執行結果

| 項目 | #3 | #6 |
|---|---|---|
| 整合 main 後 `bash tests/run.sh` | exit 0；52 個頂層 Shell 入口 | exit 0；53 個頂層 Shell 入口 |
| 頂層 Python suites | 43 項：42 通過、1 個選用項目跳過 | 同左 |
| 真實四語言 Meson | C／C++／ObjC／ObjC++，12 個薄型 x86_64 Mach-O，minOS 檢查通過 | 同左 |
| 實際 flush／context／visible-rect／style-mask／GDI 方法 | 通過 | 通過，另含缺失排序 anchor 的原版重現與修正版方法 |
| 新 prefix 的 i386／x86_64 file／BCrypt | 通過 | 通過 |
| 真實 GL profile control | 恰好 8 次 native front flush、8 次 native swap | 同左 |
| frame-walk | 完整入口因預設 install 不存在而跳過；另指定 #3 診斷 runtime 補跑通過 | 另指定 #6 診斷 runtime 補跑通過 |

Shell 入口數從 `tests/run.sh` 陣列計算；日誌中的 `==>` 還有巢狀測試輸出，不以其行數當頂層數量。Python 數量不包含 Shell 入口內的 native assertions。

[去識別化驗證摘要與私有日誌 SHA-256](assets/premerge-review-2026-11-02/validation.json)。

仍保留兩項選用限制：MoltenVK patched-source live round-trip 缺少相應來源，content checks 通過；新增自 main 的 real Authenticode crypto 案例未提供 osslsigncode／OpenSSL tool paths，屬 43 項中的 1 個 skip。沒有宣稱正式 PE 憑證或真實防毒驗收。

可重現的核心設定如下；`REVIEW_ROOT`、`TEST_ENGINE` 必須指向隔離 checkout 與對應的已驗證診斷產物，不能指向使用者正式 runtime：

```bash
export OGOM="$REVIEW_ROOT"
export CYDER_HOST_CLANG=/Library/Developer/CommandLineTools/usr/bin/clang
export CYDER_HOST_CLANGXX=/Library/Developer/CommandLineTools/usr/bin/clang++
export CYDER_HOST_PYTHON=/opt/homebrew/bin/python3.12
export AR=/Library/Developer/CommandLineTools/usr/bin/ar
export RANLIB=/Library/Developer/CommandLineTools/usr/bin/ranlib
export LD=/Library/Developer/CommandLineTools/usr/bin/ld
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk
export MACOSX_DEPLOYMENT_TARGET=10.15
export RUNTIME_SMOKE_WINE_RUNTIME="$TEST_ENGINE"
bash tests/run.sh
FRAME_WALK_WINE_RUNTIME="$TEST_ENGINE" bash tests/test-ntdll-frame-walk-guard.sh
```

路徑是本機實測值，其他機器需選擇實際可用的工具。測試用 Wine headers／config.h 及 winemac 原始檔是既有 build 的私有副本；A6 round-trip 在副本進行，#3 副本先移除 #6 patch。編譯器與下載 archive 只作輸入，沒有改寫共享 build tree。

## Runtime 身分與證據界線

本輪沒有新建整套 Wine。遊戲／API probes 使用先前已記錄、strict ad-hoc 簽章驗證通過的兩套診斷 runtime：

| 模組 | #3 診斷 runtime SHA-256 | #6 診斷 runtime SHA-256 |
|---|---|---|
| winemac.so | `950e9b2d364c9b728750bdc6d4c579906bf25ec12892ac5c9029bf8fc4cfb7f0` | `fe31b28d36cc39f0ea547b13d01456b00c02055c6e15a713588dae368811ec12` |
| win32u.so | `26f799043303a9575b4336b6b4d95932e4c20c1f90777c203a26c55f1276e0f6` | 同左 |

#6 遊戲 PID 的模組觀測確認載入其隔離 winemac／win32u／builtin ddraw／wined3d。main 的此次新增內容是 PE 打包／簽章流程；沒有因此宣稱現有診斷 runtime 已重新打包或完整重建。

另以本輪已知遊戲 PID 交叉核對監測工具的 CPU 單位：`proc_pid_rusage` user＋system raw 值 1,253,218,241，在此 M4 上依 Mach timebase 125/3 換算為 52.2174 秒，BSD `ps TIME` 為 52.22 秒；直接當成 ns 會只有 1.2532 秒。本機確認仍需既有 Mach tick 換算，不更動歷史量測值；不外推所有未驗證 OS。

## #6 Retina 補測與 AX 限制

Apple M4／macOS 27.2、單一 1680×945 points／2× 螢幕、HD[1]、GL、RetinaMode=y、96 DPI。由原啟動器進入既有角色的召喚之間；沒有創角、消費或遊戲 DLL patch。

- 原生視窗 481×393 points，原生像素 capture 962×786；Win32 client 為 962×722。這與先前 RetinaMode=n 的 961×721 client 不混算。
- macOS `AXFullScreen` 真正進入原生 Space；全螢幕 1680×945 points／3360×1890 pixels，並非 Alt+Enter 或 CNC borderless。
- 3 輪有完整記錄的 fullscreen→window→Win32 minimize／restore 都恢復原尺寸、位置與完整 UI。固定底部字體 ROI `(110,770)-(600,784)`，6 張返回／還原圖與基準 MAE=0、最大通道差=0。
- 額外確認全螢幕狀態按鈕可開面板，回切一般視窗可關閉；最後再次進全螢幕，經正常退出流程觀察遊戲程序結束。同類 AppKit `NSRangeException` 為 0。
- **AX-only 還原未通過：** 首輪以 AXMinimized=true 最小化後，設定 false 雖回傳成功，讀回仍是 1，視窗不可見；Win32 client 變為 0×0。隔離 Win32 `SW_RESTORE` 可恢復 962×722。此失敗不列入上面的 3 輪通過數。
- **反控制：** 同一遊戲／prefix／Retina 設定改用不含 #6 的 #3 runtime，在登入前且從未進 fullscreen 就重現相同 AX 失敗，Win32 還原同樣成功。不是目前證據支持的 #6 新回歸；也不據此宣稱 Dock、所有 AX 操作或所有最小化入口已修復。

未將動畫區、聊天或角色資訊放入公開截圖；#6 分支的補驗附錄另附安全字體裁圖及去識別化數據。原始畫面、系統日誌與帳密保持私有。兩組遊戲正常退出後，只停止本輪新複製 prefix 的殘留服務；原遊戲／prefix 不受更動，輸入來源已還原。

## 尚未完成的驗證與合併狀態

| 缺口 | 本輪狀態／需要的證據 |
|---|---|
| #6 多螢幕／混合 Retina、其他 OS、不同晶片 | 本機只有單一螢幕與 M4／macOS 27.2，仍需對應環境；不能以 minOS metadata 當實機通過 |
| #6 Retina no3d、多開原生 Space | 本輪新增的是單開 GL；原有 1× no3d 結果保留，不能冒充 2× no3d 或多開驗收 |
| AX-only 還原／Dock 入口 | 已分辨既有 AX 失敗與可工作的 Win32 路徑；Dock 還原未由本輪驗收 |
| 真正 front-buffer 多次 Blt 的遊戲效能 | 8／8 是正確性控制；未補新的 display scanout／多次 Blt 成本實驗 |
| MapleStory／D3DMetal、frameless／CEF／Steam | 本輪窄函式與 API 回歸不是這些實際程式的 GUI 驗收；需指定版本與環境補測 |
| CS2／Paradox／DXMT 完整遊玩 | 先前 D3D11 device／媒體探測與賽馬娘驗收不等於 CS2 可玩；合法遊戲與實際環境驗證仍缺 |
| shipping build／正式 runtime | 本輪沒有完整媒體／TLS 重建、正式 Developer ID 封裝或安裝；未新增發行宣告 |

#3 與 #6 保持 Draft，不因本機回歸通過就宣稱所有合併／發行缺口已填滿。#6 應接在 #3 後處理；#7、#8 保持原 head 與 Draft，未將 HALFTONE／GPU helper 裝入這兩套 runtime。issues 全部保持 open。

相關：[完整建置歷史](build-validation.md) · [三遊戲驗證](three-game-soak-2026-10-30.md) · [PR #6 排序修正](https://github.com/dspp779/cyder-wine-engine/pull/6) · [PR #2](https://github.com/dspp779/cyder-wine-engine/pull/2)。
