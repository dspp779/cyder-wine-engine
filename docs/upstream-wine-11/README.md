# Wine 11.0 到 11.20 更新與 Cyder 整合評估

截至 2026-10-30，Wine 官方 mirror 最新發布標籤為 wine-11.20（2026-10-16）。本清單固定比對 wine-11.0 到 wine-11.20，不包含 11.20 後未發布 master、Wine Staging 或 CrossOver 私有修改。共 5054 筆提交、20 個 development release、公告列出 532 筆 bug 修正條目（同一 bug 可重複，不代表唯一 bug 數）。

完整提交以 Git tag 的可達集合計算，逐版聯集須無重複且等於總集合。每筆保留 SHA、原始標題、來源連結與初步分流。這是完整提交盤點及元件風險分析；只有本文特別標明的候選做了 diff 審查，沒有把 5,054 筆都當成已完成語意／回歸驗證。Cyder CX26.3 是 fork，不能用版本號判定某筆一定缺少。

## 逐版條列

| 版本與完整清單 | 發布日 | 提交 | 公告 bug 條目 | 中文重點 |
|---|---|---:|---:|---|
| [11.1](11.1.md) | 2026-01-23 | 208 | 22 | 解除 code freeze 的累積修改、WindowsCodecs 像素格式、MSADO。 |
| [11.2](11.2.md) | 2026-02-06 | 212 | 32 | PDB 載入最佳化、C runtime 的 MSVC constructor、版本資源機制。 |
| [11.3](11.3.md) | 2026-02-20 | 224 | 30 | Mono 11.0.0、vkd3d 1.19、DirectSound FIR、PDB、Aero theme。 |
| [11.4](11.4.md) | 2026-03-06 | 222 | 17 | MSXML SAX 重寫、DirectSound 重採樣、CFGMGR32、Unix 時區配對。 |
| [11.5](11.5.md) | 2026-03-20 | 199 | 22 | 建置系統 C++、內附 ICU、Linux syscall user dispatch、VBScript。 |
| [11.6](11.6.md) | 2026-04-03 | 262 | 28 | Android driver 起步、遊戲 mod 的 DLL 載入順序 heuristics、VBScript。 |
| [11.7](11.7.md) | 2026-04-17 | 312 | 35 | MSXML 移除 libxml2 起步、VBScript、D3DX sRGB filter、DirectSound 7.1。 |
| [11.8](11.8.md) | 2026-05-01 | 240 | 22 | Mono 11.1.0、MSXML、XKBRegistry 鍵盤配置、VBScript。 |
| [11.9](11.9.md) | 2026-05-15 | 195 | 24 | 內附 SQLite、system thread 起步、ARM64 模擬碼執行緒暫停、VBScript。 |
| [11.10](11.10.md) | 2026-05-29 | 249 | 17 | vkd3d 2.0、無 libxml2 的 XPath、VBScript。 |
| [11.11](11.11.md) | 2026-06-12 | 225 | 25 | 內附 SymCrypt 取代 TomCrypt、USER32 window info shared memory、Wayland layered windows、VBScript。 |
| [11.12](11.12.md) | 2026-06-29 | 216 | 27 | 內附 FFmpeg libswresample／libswscale、Mono 11.2.0、MSXML XSLPattern。 |
| [11.13](11.13.md) | 2026-07-10 | 198 | 22 | input pointer、X11 scancode、ARM64EC FFmpeg 最佳化。 |
| [11.14](11.14.md) | 2026-07-24 | 181 | 21 | DirectSound 7.1 格式轉換、BCrypt AES-GMAC、FreeBSD 新 WoW64、Start Menu 圖示。 |
| [11.15](11.15.md) | 2026-08-08 | 207 | 41 | BCrypt KDF、Mingw ARM64EC 建置、WindowsCodecs、local NTLM。 |
| [11.16](11.16.md) | 2026-08-21 | 245 | 35 | Mono 11.3.0 含 ARM64、VA-API 硬體解碼、ARM64EC exception。 |
| [11.17](11.17.md) | 2026-09-04 | 383 | 44 | vkd3d 2.1、display mode emulation 起步、preferred UI language。 |
| [11.18](11.18.md) | 2026-09-18 | 381 | 21 | NTOSKRNL driver 支援、廣泛程式正確性修正、標準 C headers 相容性。 |
| [11.19](11.19.md) | 2026-10-02 | 353 | 23 | GDIPlus 垂直文字、Unicode 18.0.0、DNS cache、VBScript parser。 |
| [11.20](11.20.md) | 2026-10-16 | 342 | 24 | ARM64EC relay debugging、XML validation、CDROM 移往 Mount Manager。 |

## 元件分流統計

- 應用元件：2032 筆。
- 測試：837 筆。
- 圖形視窗：714 筆。
- 核心執行：526 筆。
- 影音：314 筆。
- 建置介面：299 筆。
- 其他平台：156 筆。
- 加密驗證：121 筆。
- 維護資料：55 筆。

## 整合判斷

- **本 PR 回植兩項視窗正確性修正**：`48e2d504` 初始化兩個 style mask 輸出；`6cfa941d` 保留超出裝飾裁切區的 client area。兩者都在 11.20，已比對 Wine 官方 diff 與 CX26.3 原始檔。前者保留 CX Quicken 例外；後者不觸及 swapchain、授權或遊戲 DLL。對真正函式做編譯與幾何／旗標測試後才接入預設 patch stack。
- **PR #2 的 front-buffer present 已整合**：透過 merge 保留 `92f813b`，納入上游 `b5ab3b15` 的 CX／A6 適配。`GL_FLUSH_PRESENT` 會先 flush context 再 present；swap 保留 A6 的 pending 條件並處理 NULL context，未改變 driver struct ABI。新增實際函式編譯、旗標矩陣、順序與 A6 疊加往返測試，並以 `--with-vulkan` 重建。這不取代 BlueCG／其他 GL 遊戲的實機回歸。
- **其餘 Metal／OpenGL 應分批遷移**：`52e03c61` MetalViewSwapChain 重構、`1a63b0d7` CALayerHost 跨程序呈現、`1300ec99` autorelease pool、後續 GL profile、latched client surface 與 drawable 調整具前後相依性。CX 有自己的 `d3dmetal.c`、固定大小 `macdrv_functions` ABI 與 A6 backing 修改；不能逐個機械套用。CAContext wrapper 在 CX 目前不存在，不能只取 autorelease pool hunk。
- **核心、WoW64、記憶體與同步需專案級驗證**：system thread、低位址保留、top-down allocation、ARM64/ARM64EC context、syscall wrapper、RtlWaitOnAddress 與 server 變更可能影響反作弊及整個 prefix。11.20 的 `81e52628` 是同步候選，但不是未知卡死的通用解方。需先建立確定重現與 CX server/protocol 對照。
- **加密不能拆半套**：11.11 將 bcrypt 從 Unix TomCrypt 路徑轉向 bundled SymCrypt，後續 KDF、AES-GMAC、curve、RSA size 驗證依賴此前提。直接覆蓋 bcrypt 會改變建置與載入架構。應先用有效 ECDSA／RSA／KDF 向量驗證 CX，再規劃完整依賴；不導入任何授權驗證繞過。
- **啟動與 DNS**：`4cf90548` 以 AI_DNS_ONLY 避免 wineboot mDNS timeout，是高優先候選；需確認 CX ws2_32 對旗標的實際支援及 hostname/FQDN/離線回歸，未以一句 flag 修改宣稱已修復。DNS cache 也需 TTL、negative caching 與網路切換測試。
- **mod DLL load order**：11.6 的 heuristics 會改變多款遊戲的 native/builtin 選擇，需與 CX 原始 hook、Cyder cxcompatdb prepend、使用者 override 一起驗證。不直接全域啟用新策略。
- **Mono 不是 Unity Mono**：11.3／11.8／11.12／11.16 的 Wine Mono 更新不會自動替換 CS2 遊戲內 Unity Mono。不能據此退役 `mscorlib` 遊戲修補或證明 P/Invoke 行為相同。
- **DirectSound／DirectMusic／Media Foundation**：FIR、重採樣、7.1、loop、mixing 與 format conversion 可改善多種遊戲，但需延遲／音量／通道／循環測試。內附 FFmpeg／vkd3d／ICU／SQLite、MSXML 移除 libxml2 都是完整依賴遷移；Cyder 自有媒體與 graphics 分包流程不能直接被上游 configure 取代。
- **Linux／Wayland／X11／Android／FreeBSD**：保留完整清單供跨平台參考，這些平台的 driver 改動不直接回植 macOS。VA-API 不等於 macOS VideoToolbox。ARM64EC 也不等於現有 x86_64 Rosetta engine 可立刻改成原生 ARM64。
- **一般 DLL、C runtime、COM、XML、文字與資源**：完整清單保留每個 module 與 bug；先以使用程式、API 測試及相依性篩選，避免把使用者未遇到的 5,054 筆變更一起放進 CX26.3。小型 crash/overflow 修正可另立 narrow PR；本 PR 沒有完成每筆 diff 的 backport 審查。
- **macOS 最低版本與打包**：上游移除 pre-10.15 workaround 不會授權提升 Cyder host floor；仍須 host 10.15、DXMT 15.0、versioned MoltenVK 12.0 例外與既有 codesign／pack gates。i386 macOS preloader 移除不等於刪除 i386 Windows PE 支援。

版本公告只是變更索引，不是 Cyder 相容性證明。本 PR 不升級 Wine base、不宣稱 CS2 已可玩、不替換使用者 runtime。保留現有 Cyder012 identity，正式打包前需按 repository 發行流程決定新版本識別。

## CS2 社群補丁逐份盤點

固定來源：[macgameport 1c0b8b7](https://github.com/macgameport/cities-skylines-2-macos/tree/1c0b8b7cbacbc17db90ec3bc0ad974c7cd7242dc)。以下是該 repo 的全部 11 份 `.patch`，不等於 Wine 官方更新。

1. `wine-6cfa941-win32u-visible-rect.patch`：官方 Wine 可見區域修正，本 PR 回植。
2. `wineandaqua-dxmt.patch`：九檔 DXMT 接線、ObjC wrapper、Metal view 與固定 ABI exports；CX 已有獨立 D3DMetal/DXMT 接線，需逐欄位比較，不能疊加。
3. `winemac-crossprocess-remote-layer.patch`：合併版，含子 HWND／root 幾何映射、Retina 邊界、Win32 z-order、0×0、resize、layer lifetime。需 Wine 11.11+ 基礎與 DXMT 成對修改。
4. `winemac-crossprocess-child-core.patch`：前項的 stock Wine 核心部分，非額外第三套修正。先確認 CX CAContext 基礎，不直接套用。
5. `winemac-crossprocess-dxmt-glue.patch`：成對 acquire/release export、view-keyed surface table、per-child deferred release、延遲 layer 背景。要和 core 及 DXMT unix 半邊一起驗證。
6. `dxmt-remote-layer-fallback.patch`：處理 foreign child HWND 的 NULL win_data；用 dlsym 找遠端 layer exports，release 辨識 remote handle。維持固定 struct ABI，但缺另一半仍會失敗，不能當獨立 NULL guard 發布。
7. `dxmt-fork-iomanip.patch`：補 `<iomanip>` 建置 include；只在實際採用該 fork/compiler 時評估，無直接遊戲執行修正。
8. `winemac-crossprocess-child.patch`：舊的 geometry-less 版本，已被合併版取代，不套用。
9. `dxmt-nullcheck-win-data.patch`：已淘汰；只把 NULL dereference 改成後續 abort，不能解決黑窗。
10. `winemac-foreign-hwnd.patch`：診斷用，會洩漏 client surface 且畫面仍黑，不套用。
11. `dxmt-force-crossprocess.patch`：診斷用強制放行，非已驗證發行方案，不套用。

上游 build-engine-1116 還有 donor freetype/gnutls 路徑探測、rpath、prefix 更新與 Steam 生命週期處理，屬 wrapper packaging，不能照搬至 Cyder。上游使用混合來源 DXMT PE/unix 二進位，Cyder 必須維持自有分包、簽署及 hash provenance。十項遊戲端 DLL 修補留在應用／game recipe 的獨立安全設計，不加入 Wine engine。授權繞過完全排除。

## 驗證與限制

- 已通過：兩個新測試會對 CX26.3 pristine 函式套 patch、編譯實際函式、驗證四邊 client overflow／decorated／shaped／present override 與 style mask 四種組合、Quicken early return，並 reverse 還原逐位元比較；manifest 記錄與順序檢查、test-build-wine、test-engine-manifest。
- 完整 runtime 建置與回歸已補驗：CX26.3／Wine 11.0，full-video GStreamer，43 個 Shell 回歸入口與 8 項 Python 單元測試通過（含 PR #2 與最新 main）；98 個 host Mach-O 的架構、minOS 10.15、ad-hoc 簽章與 runtime 內依賴檢查通過。新 prefix 的 32／64 位元 Win32 檔案與 BCrypt、22 個媒體插件／10 個元件及預設憑證驗證 HTTPS 探測通過。唯一 skip 為可選 MoltenVK source live round-trip 子檢查。詳見 [完整建置紀錄與限制](build-validation.md)。
- 尚需：macOS GUI／Steam session／CS2／DXMT／其他遊戲與較舊 macOS 實機驗證；正式發行還需對應 graphics payload、Developer ID 與封裝流程。PR 保持 draft，函式與 API 測試不代替遊戲驗收。
- 5054 筆清單依 tag 區間計算，532 是公告 bug 條目總和。`inventory.json` 為可機讀索引；各版本頁保留完整提交，原文標題可逐筆連回官方 diff。類別依前綴分流，不宣稱自動分類等同完整人工語意審查。
