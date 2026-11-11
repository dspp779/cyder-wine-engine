# GameToMac 安裝、底層瓶頸與楓之谷 DXMT 實驗

日期：2026-09-21。對應本機 GameToMac 0.1.19 Alpha build 57。

## 本機安裝結果

- 官網 <https://www.gametomac.com> 的 Download 轉址到
  <https://updates.gametomac.com/GameToMac-0.1.19-alpha-build57.dmg>。
- DMG：261,422,634 bytes；SHA-256
  `c950f632fb52e8e6de51e459dbb222b8ccadcf178161cd6ed3228518cb251abd`。
- 已安裝 `/Applications/GameToMac.app`。`codesign --verify --deep --strict`
  通過；`spctl --assess --type execute -vv` 回傳 accepted／Notarized Developer ID，
  簽署者 Marc Ibrahim，Team ID `4F5RV48Y8T`。
- 本機 Apple M4／macOS 15.7.7（24G720），app 的 `LSMinimumSystemVersion=26.0`。
  `open` 回傳 LaunchServices `-10825`，無法進入 GUI。未完成 GameToMac Steam setup
  或 GameToMac 遊戲實測；沒有改 Info.plist、移除安全檢查或升級系統。

## 原始碼確認的機制

來源全在已安裝 app 的 `Contents/Resources/Sources/`，以下敘述是 source inspection，
不是把作者的測試描述當成本機重測結果。

| 路徑 | 實際修改 | 對 MapleStory 的意義 |
|---|---|---|
| `RUNTIME-BUILD.md`、`wine-source.tar.gz` | CX26.3／Wine 11.0，software exception cached-context 與 generated-code cache | CPU exception／Rosetta 路徑，不是 GPU shader cache |
| `ntdll/unix/signal_x86_64.c` | `aoe_exception_context` 從每執行緒 cache 補 context，避免 debug-register context 的 server round trip | 要先量測 exception 熱點；不能假定楓之谷相同 |
| `aoe_code_cache.h`、`aoe_relocate.h` | 只接受 `RelicCardinal.exe`（另有測試 fixture），檢查位址範圍，把保守允許的短 fragment 搬到穩定位址、處理 RIP-relative relocation，保存 original/shadow PC 對照 | 不是可通用開啟的 Rosetta 磁碟 cache；直接放寬成 MapleStory 可能破壞 exception/unwind 語義 |
| `AOE2.md`、`AoE2RuntimeSource/` | 對特定 exe hash 與原 bytes 的 59-byte startup memory patch，把既有 settings getter 提前，只有條件成立才查 DLC | AoE II 的 retained optimization 不依賴 AoE IV generated-code cache。不能拿來改楓之谷 |
| `CS2.md`、`CS2Renderer/` | 記錄 pipeline recipe/shader input，啟動前重播已見過的 pipeline、保存本機 archive | 可以研究的 graphics translation 機制；未見過的內容仍可能卡 |
| `OVERWATCH.md`、`OverwatchRuntime/` | DXMT v0.80 archive/recipe、Unicode 路徑、先通知完成再持久化、先 join worker 再釋放依賴 | 本輪選擇縮小移植 archive 與生命週期修正 |

AoE II 的 source notes 對部分 release check 的敘述仍停在較早 staging 階段，
不能用它判斷 build 57 是否完成每個跨機驗收。網站的 supported games 也沒有楓之谷。
Overwatch profile 明確把 eager compilation 關閉；本輪也不移植 speculative compile。

## 重新界定楓之谷證據

既有 `maplestory-cx26-first-hit-materialize-findings.zh-TW.md` 記錄首次真命中
有約 655／749 ms 的 Present 空窗，第二次沒有同等大空窗；WZ prewarm、FAST_HIT
與切換 D3DMetal/DXMT 未消除問題。這支持「命中 first-use 在提交關鍵路徑」的分類。

但只看名為 `-[AGXBuffer initImplWithHeap:…]` 的**執行緒名称**，不能等同於
93% CPU time 真正在該 allocator 函式。必須再看 time sample 的 stack／symbol，
也不能只由 HUD 停止斷定唯一根因是 PSO 或 buffer allocation。本輪未重放原始
Instruments trace；原文件所列 `/private/tmp/...` trace 在本次查核位置未找到。

新的 archive 實驗只回答：把**已遇過的普通 graphics PSO** 跨 session 保存後，
first-hit 等待是否縮短。未移植 CPU code-fragment relocation、未修改反作弊、
未更改遊戲的渲染順序、資源同步、buffer 清零或 D3DMetal 封閉 binary。

## 本輪實作

位置：`tools/dxmt-pipeline-lab/`；建置：`build/dxmt-pipeline-lab/overlay/`。
詳見 [實驗說明與重現命令](../tools/dxmt-pipeline-lab/README.md)。

- 在官方 DXMT v0.80 上新增 opt-in ordinary graphics pipeline archive。
- 完整 descriptor/shader/variant/GPU/OS/source-runtime identity 為 key；Metal 嚴格驗證 hit。
- fallback 到正常 PSO 建立；render ready 與 dependent work 先放行，磁碟保存後做。
- 加入 archive checksum sidecar，缺失或 mismatch 在進 Metal 前排除。
- 上限 256 MiB／4,096 archives／每個 8 MiB。中文、空白與長路徑使用 Unicode Win32 API。
- 只重建 x86_64 d3d11 PE，重用官方 v0.80 host bridge（既有 DXMT minOS 15.0 例外）。
- 不動 production apply list、release manifest、預設後端、installed engine 或遊戲檔。

## 驗證紀錄

初版冷快取 4 misses／4 saves，跨程序 warm 4 hits；兩輪各 4,096 pixels 正確。
但 corrupted archive 測試逾時，初版沒有通過完整驗收。
這促成完整性 sidecar；逾時當下 stack 大量無法解析的 Wine syscall dispatcher，
不足以獨立證明 Apple driver 的哪個函式是根因，因此記為 corruption-case failure。

最終版 11 種情境全部通過，每輪 4,096 pixels（合計 45,056）。cold 4 misses／4 saves，
warm 4 hits；corrupt、Metal 拒絕與寫入失敗皆能回退及正常退出。
結果附於 [results.json](../tools/dxmt-pipeline-lab/evidence/results.json)，原始測試 log 同目錄。
測試是實際 D3D11 Draw→CopyResource→Map，不是文字 marker 或 mock。
像素、cache hit、fallback correctness 不等同於楓之谷效能改善；本輪不發布 FPS 增益。

第一次試跑未設定 Cyder explicit backend，載入了非預期後端，該輪讀回失敗，
已排除；正式 harness 強制 backend path 並要求本次 cache counter 證據。

第二版 checksum 使 corruption 回退通過，但 missing-directory 輪在完整像素通過後
退出仍逾時。比對 bridge 原始碼，`newBinaryArchive`／`serialize` 回傳 autoreleased
`NSError`（+0），原 port 的 `Reference<Error>` destructor 卻會 release。
第三版將內部 error 改為 borrowed handle、加局部 autorelease pool；只有交给
外層 owning caller 的錯誤才 retain，並新增「校驗相符但內容無效」測試，
確實走過 Metal reject 路徑。這是本輪找到並修正的具體翻譯層 error ownership 問題。

本機官方 v0.80 `winemetal.so` 是未簽署的 development payload，本實驗原樣重用；
這不同於已通過簽署及公證驗證的 GameToMac app，也不構成正式 engine 發布。

## 尚待遊戲驗收

本機紀錄的 `/Users/jjc/games/tms/MapleStory.exe` 已不存在，`/Users/jjc/games/`
為空。本輪尚未進入楓之谷安全地圖，沒有 first-hit A/B 結果，不能宣稱修復卡頓。
有可用遊戲位置／登入 session 後，用同角色同圖各 ≥3 輪 cache-off／learn／warm
比較 Present gap，並同時判定 PSO wait 與真正 buffer allocation call stack。
如果有 PSO hit 但 gap 不降，下一步應追 resource materialization、CPU exception
或 command submission 同步；不再把開 shader cache 當成成功答案。

最終 overlay：`v0.80-cyder-pso-lab-cb6fa6f818d66dad`。
`d3d11.dll` SHA-256：`be4913fea6371c526bb62870d8d106e1a1bb4ae20017c2f70af452e068ec70b3`。
