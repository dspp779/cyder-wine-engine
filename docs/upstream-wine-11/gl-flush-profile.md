# PR #3：flush／swap 量測

## 呈現修正

新增上游 Wine 11.3 b3c408b3c0b6a308c3f07951960c0d47ea87fece：
更新 swap interval 時使用 `flags |= GL_FLUSH_INTERVAL`，保留同次通知的
PRESENT／UPDATED／FINISHED／FORCE_SWAP。先套此修正，再套 62da9c02 的
context-bind 前置修正及 b5ab3b15 的 winemac 呈現修正。

## 啟用與輸出

`CYDER_GL_PROFILE=1` 必須在建立 OpenGL context 前設定；其他值預設關閉。
這是程序限定的診斷設定，不改變 renderer、interval、繪製／呈現時序或遊戲 DLL。

```sh
CYDER_GL_PROFILE=1 WINEDEBUG=-all /absolute/test-engine/bin/wine BlueLauncher.exe 2>run.log
python3 tools/gl-profile/summarize.py run.log
```

每個 context 在下一次 callback 完成且統計窗達五秒時，輸出最多兩行
`CYDER_GL_PROFILE`（flush／swap），然後歸零。context 正常銷毀時輸出餘量；
突然結束／強制關閉可能沒有最後不足五秒的樣本。沒有背景執行緒、逐次 log、
逐次配置或鎖。關閉狀態沒有時鐘讀取或輸出；context 結構增加固定統計空間。
context 可在執行緒間移動，但和原有 OpenGL 契約相同，不可同時 current。

- `callbacks`：driver callback 次數；flush 包含沒有 PRESENT 的同步通知。
- `native`：該 callback 呼叫 native flush 的次數；不能當作實際顯示影格數。
- `callback_ns`：callback 計時開始至 present 完成的經過時間，包含 A6 backing sync。
- `native_ns`：`macdrv_flush_opengl_context` 經過時間，包含 native update／flushBuffer／等待。
- `present_ns`：native flush 返回後至 `client_surface_present` 返回的經過時間。
- `native_max_ns` 及互斥耗時桶：≤100µs、100µs–1ms、1–4ms、4–16ms、>16ms。
- `flags_*`：flush 各旗標出現次數；`interval` 與 `double_buffer` 為輸出時 context 狀態。

這些是 CPU 端 wall time，不是 GPU 執行時間、CPU busy time，也不是整個 Blt 的
成本。opengl32／win32u 前面執行的 glFlush／glFinish 不在 callback 計時範圍內。
interval 在同一窗內改變時，最後的 interval 不足以代表整個窗；穩態測試應避開
切換窗。每個 phase 共用窗的 elapsed；不可將 flush 與 swap 的 elapsed 相加當
程序觀察時間。解析器依 PID/context/phase/interval/double-buffer 分組。

## 水藍魔力測試協定

使用獨立 runtime/prefix、同一 HD 模式與 WineD3D GL，記錄實際載入的 win32u、
winemac、ddraw、wined3d。穩定後採至少三個完整五秒統計窗；分開標示登入畫面與
登入後走動／多次 Blt 場景。可短時間開 `trace+fps` 對照 DirectDraw primary update
計數，但 Wine 的該 fps 計數本身不能證明遊戲邏輯 frame 邊界。

以相同場景比較 profiling 關閉／開啟的低噪音資料，保留統計與無敏感資訊截圖。
不要用移除 native flush 作正式效能對照，因為那會同時改變呈現正確性。
登入畫面量測不等於登入後遊戲驗收；沒有登入後資料時必須明確保留這項限制。

## 本次驗證（2026-10-30，含後續登入後取樣）

- b3c408b3 實際函式測試：256 組旗標／interval／surface 狀態，加重用路徑；
  patch forward/reverse、重複套用檢查均通過。
- profiling 實際 callback 測試：全部 32 組真實旗標、A6 pending/read-view、
  NULL context、native-flush-before-present，off/on 皆通過；統計加總、耗時桶、
  五秒輸出／reset、disabled 零 clock、解析器與 patch 往返均通過。
- 標準 configure/apply 重跑後，win32u/opengl.c、winemac/opengl.c 與 profiler
  header 的 SHA-256 完全相同；A6 全 stack round-trip 通過。
- win32u.so／winemac.so 實際編譯完成，均為 x86_64、minOS 10.15。僅安裝到
  獨立診斷 runtime，ad-hoc 簽章 strict 驗證通過；未替換正式 runtime。
- 完整 tests/run.sh exit 0：49 個 Shell entrypoints 及既有 23 個 Python unit
  tests 通過，含新量測／旗標測試、真實 GL 控制程式、四語言 Meson x86_64/minOS probes、實際
  Wine frame-walk、x86_64/i686 file/BCrypt。僅既有 optional MoltenVK source
  live-round-trip 因缺少 patched MVKSync.mm 跳過；content checks 通過。
- 本次只重建兩個 host 模組及其 link 依賴。恢復的 configure 未建完整媒體／TLS
  stack；其選項不改變這兩個模組的本次測試行為，既有診斷 runtime 的其他
  modules/media/TLS 檔案保留。此結果不是完整 shipping build 或 release archive。

新 native 模組 SHA-256（已 ad-hoc 簽章）：

| 模組 | SHA-256 |
|---|---|
| win32u.so | 26f799043303a9575b4336b6b4d95932e4c20c1f90777c203a26c55f1276e0f6 |
| winemac.so | 2611701d10d38c57978060c8bbb9bb47b378dcfd1da41ae2c2ef99fbd7577382 |

獨立 HD 模式 1／WineD3D GL 已恢復標題與登入 UI，程序限定的載入觀察確認上述
新 native modules，以及 builtin ddraw.dll、wined3d.dll、opengl32.dll/so。
登入前觀察到同步 flush callback，但沒有 PRESENT/native flush/swap 樣本；
因此尚無可報告的「每次 native flush 成本」，不能把初始化數值當作每幀資料。
後續登入後取樣見下節；尚未做有 native 呈現負載的 profiling off/on FPS 對照。
沒有憑證操作，也未修改遊戲 DLL。

### 登入前初步樣本（Apple M4，macOS 27.2）

新模組的獨立 HD 模式 1 run 到達登入 UI。已輸出的七個 context/phase 聚合
共 11 次 flush callback，合計 callback wall time 5,052,000 ns（約 5.05 ms）；
`native=0`、`flags_present=0`，沒有 swap phase。最長的一個聚合觀察窗為
52.338616 秒，包含三次同步通知。這些是初始化／切換成本，不能視為每幀成本，
各 context 的 elapsed 也不能相加當總觀察時間。

目前沒有 native flush 的成本樣本，不能回報「每次 native flush 幾微秒」或
「遊戲內多次 Blt 造成多少 FPS 損失」。此為登入前階段紀錄；使用者後續已自行登入，見下節。不要求、不讀取或輸入憑證。原始 log 與帶帳號的畫面僅
留本機私有暫存目錄，不提交或公開。


### 登入後法蘭城與正常退出（後續完成）

使用者自行登入後，在相同 HD 模式 1／WineD3D GL／同一個遊戲程序觀察法蘭城，
完成一次安全草地的短距離走動，前後截圖確認角色位置與場景有更新；另記錄
151.758737 秒的觀察窗。觀察窗沒有新增 GL profile 聚合。

遊戲經正常關閉與確認流程退出，取得仍存活 context 的 final 統計，故本次結果
不只依賴「沒有即時 log」推論：整個 run 共 10 行聚合、15 次同步 flush callback，
合計 callback wall time 9,874,000 ns（9.874 ms），**PRESENT/native flush/swap
全部為 0**。這是啟動、切換、正常退出的同步成本，不能除以遊戲 frame 數。
短暫 sample 也觀察到 `macdrv_window_set_color_image` 的執行路徑；對照
winemac `surface.c` 可知這是 GDI window-surface 的影像更新，與這次未觸發
OpenGL front-buffer 呈現的觀察一致。這個抽樣不是完整每次 Blt 的追蹤。

為避免量測器失效造成假零，另用獨立 prefix 的隱藏視窗 OpenGL 控制程式，在
同一份 runtime 執行 8 次 `GL_FRONT`/glFlush 與 8 次 back-buffer SwapBuffers。
實際輸出精確計到 8 次 native front flush、8 次 native swap；含第一次 interval
改變的 present，沒有遺失或重複。此控制已加入
`test-winemac-gl-profile-runtime.sh`；它驗證真實呼叫計數，不是像素正確性或
螢幕呈現延遲 benchmark，隱藏視窗的耗時不作遊戲效能數字。

**範圍結論：**本次水藍魔力 HD 模式 1、法蘭城短距離走動／閒置場景沒有
執行 PR #2 新增的 native flush 分支，因此沒有觀察到該呼叫造成的逐幀額外
負擔。不能據此宣稱其他 HD 模式、其他遊戲或真正 GL front-buffer 多次 Blt
同樣零成本；也沒有測出整個 Blt 的 CPU/GPU 成本或 FPS 改善百分比。
Native flush 保持原有語意，沒有為了量測刪除、節流或合併呈現。

遊戲已正常退出；未改正式 runtime、遊戲 DLL 或 renderer 設定。僅獨立遊戲
複本的角色正常走動與退出保存，未進行消費、戰鬥或其他帳號操作。
