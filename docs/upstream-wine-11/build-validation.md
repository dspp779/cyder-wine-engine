# PR 3 Runtime 建置驗證

目標：CX26.3／Wine 11.0，加上 PR #3 的兩項視窗 backport，以及合併 PR #2 的 OpenGL front-buffer present。這是隔離 install 的開發驗證，不會替換使用者的 Cyder runtime。

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
export HOMEBREW_TEMP=/private/tmp/cyder-brew
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk
export CYDER_HOST_CLANG=/Library/Developer/CommandLineTools/usr/bin/clang
export CYDER_HOST_CLANGXX=/Library/Developer/CommandLineTools/usr/bin/clang++
# GLib 2.78 generators need distutils; Meson 1.12 needs newer Python.
/opt/homebrew/bin/python3.12 -m venv build/host-python-venv
build/host-python-venv/bin/python3 -m pip install meson==1.12.1 setuptools==84.2.1
export CYDER_HOST_PYTHON="$OGOM/build/host-python-venv/bin/python3"
export FLEX=/Library/Developer/CommandLineTools/usr/bin/flex
export M4="$OGOM/.brew-x86/opt/m4/bin/m4"
export AR=/Library/Developer/CommandLineTools/usr/bin/ar
export RANLIB=/Library/Developer/CommandLineTools/usr/bin/ranlib
export LD=/Library/Developer/CommandLineTools/usr/bin/ld
export CC="$CYDER_HOST_CLANG -arch x86_64"
export OBJC="$CC"
export CXX="$CYDER_HOST_CLANGXX -arch x86_64"
export OBJCXX="$CXX"
```

CLT 路徑是本機實測值，其他機器應以可用 Apple developer toolchain 為準。Wine source/build/install 皆在目前 worktree；封存檔重用原專案下載，未重用其他 Wine build 的 object。

## PR #2 合併評估與重建

原先 PR #3／`ef65fc5` 未包含 PR #2。現在已將 `92f813b` 透過 merge commit `e60765f` 合併進 PR #3 分支，並同步最新 main 的 `c53b70e`（graphics 簽章流程）。本次整合與建置都在這個隔離分支；PR #3 尚未合入 main。

- PR #2 僅修改兩個 winemac OpenGL 呈現函式，補上 front-buffer flush 的呈現通知，保留 A6 的條件式 backing sync，swap 增加 NULL context guard；未改 driver struct ABI、遊戲 DLL 或授權驗證。
- 新增 `test-winemac-front-buffer.sh`，對 A6 基礎上的實際 flush／swap 函式套 patch、編譯並執行。覆蓋所有 flags、pending／非 pending、read-view 相等與不等、NULL context，以及 flush-before-present 順序、重複套用拒絕與 reverse 還原。
- 重跑 build script 的 configure-only 入口，確認 patch 判定為 already applied；`opengl.c` 雜湊不變，且恰好保留兩處 present 呼叫，沒有重複套用。
- A6 live-source 測試改在副本先卸除後續 GL patch，再對 A6 reverse／forward，最後重套 GL 並逐檔比對；不對實際 Wine source tree 做測試性修改。
- 透過完整 `build-wine.sh --cx 26 --maplestory --with-vulkan --vulkan-source crossover --jobs 8` 入口接續建置，實際重編 `opengl.o` 並重新連結／安裝 `winemac.so`；重新整理 22 個媒體插件並簽署。PR #2 作者原先只驗證 `--without-vulkan`，本次補上 `--with-vulkan` 建置及一般 API 探測。
- 同步 main 後新增的 graphics release fixture 會被既有 Homebrew Python 蓋過測試用 interpreter；只在 fixture 設定獨立 Homebrew 座標，使其使用預期的假簽署器。正式來源 pin、Team／時間戳及不允許 ad-hoc fallback 的規則不變。
- 合併後再次逐檔檢查 98 個 Mach-O，架構／minOS／簽章／依賴全部通過；再次執行 32／64 位元檔案與 BCrypt、媒體載入、HTTPS 探測，均通過。沒有執行女神守護之約、BlueCG 或 CS2 實機遊戲。

## 最終結果（2026-10-30）

- 完整 Wine runtime 已建置、安裝並以 ad-hoc 開發簽章簽署。基底仍為 CX26.3／Wine 11.0，包含本 PR 的兩項視窗 backport 與 PR #2 的 OpenGL 呈現修正；`wine --version` 為 `wine-11.0`。
- 產物：目前 worktree 的 `install/wine-cx26-x86_64`（約 1.1 GiB，保留開發資訊）。未替換 `~/.cyder` runtime，未產生發行 tarball、Developer ID 簽章或 notarization。
- host x86_64；Windows i386／x86_64；正式 configure 啟用 FreeType、GnuTLS、Vulkan、GStreamer。GStreamer link probe 為 yes，`winegstreamer.so` 實際建成。
- minimal 與 full-video 媒體皆建置通過。最終 runtime 使用獨立 `install/media-cx26-full-video-x86_64`，其 80 個 Mach-O 皆為 x86_64／minOS 10.15；整理入 engine 的插件共 22 個，並包含 plugin scanner。
- Vulkan 輸入沿用本機既有的 CrossOver graphics build（明確 GRAPHICS_INSTALL），本次未重建 MoltenVK，也未產出新的 DXMT／D3DMetal 分包。未加入 Apple GPTK payload。

| 驗證 | 結果 |
|---|---|
| `bash tests/run.sh` | 43 個 Shell 回歸入口與 8 項 Python 單元測試全部通過，含真實 Wine frame-walk 執行；1 個可選子檢查跳過，見下 |
| 原始 CX26 patch stack | 實際 pristine source forward/reverse 與既有 patch 順序測試通過 |
| 四語言媒體 toolchain | 真實編譯／連結 C、C++、ObjC、ObjC++，12 個 x86_64 Mach-O，minOS 通過，錯誤架構拒絕 |
| runtime 產物逐檔檢查 | 98 個 Mach-O 全為 x86_64／minOS 10.15；98 個 `codesign --verify --strict` 通過 |
| 動態依賴 | 所有被檢查的非系統依賴可在 runtime 內解析，無缺檔或外部 Homebrew／媒體路徑 |
| 新 prefix，64 位元及 WoW64 32 位元 | 檔案建立／寫入／讀回／刪除／missing-file error 通過；清除外部 Wine 與 DYLD 搜尋路徑 |
| BCrypt，64／32 位元 | P-256 產生金鑰、簽章、匯出／匯入公開金鑰、有效簽章接受、修改簽章拒絕，皆通過 |
| 媒體實際載入 | 22 個 bundled 插件全部 load；playbin、decodebin、videoconvert、videoscale、audioconvert、audioresample、qtdemux、avidemux、asfdemux、vtdec 均可建立 |
| WinHTTP／Schannel HTTPS | 獨立新 prefix，連線 github.com 得 HTTP 200，保留預設憑證驗證，未設忽略憑證錯誤旗標 |

唯一 skip：`SKIP live round-trip (no patched CX MVKSync.mm); patch content checks OK`。這是可選的 MoltenVK source live round-trip 子檢查；內容檢查及其他 MoltenVK／minOS／pack fixture gates 已執行。本次沿用既有 MoltenVK 輸入，不將這項 skip 記為實機 Vulkan 或 DXMT 驗證成功。

上述完整回歸是本 repo 的測試入口與列出的執行探測，沒有執行整套上游 Wine conformance suite，也沒有執行 CS2。

## 相依套件重建注意事項

- runtime dependency graph 查詢失敗時必須停止，安裝後再次檢查間接依賴的 minOS。實際遇到 libtasn1／nettle bottle 為 macOS 14；不能只檢查 GnuTLS 本身。已增加失敗與新依賴負向測試。
- p11-kit 的 Unix socket 測試在 worktree 下的長 TMPDIR 會逾時；改用明確短 HOMEBREW_TEMP 後，原測試 67/67 通過，未停用測試或放寬 timeout。環境腳本現在保留呼叫者的設定。
- 本機 nettle 4.0 配方複製到 gitignored `ogom/local/nettle`，將 `uses_from_macos "m4" => :build` 改成 `depends_on "m4" => :build`，並在 install 中設定 `ENV["M4"] = Formula["m4"].opt_bin/"m4"`。來源與 SHA-256 保持官方配方值；原因是此機 `/usr/bin/m4` 也透過 ARM-only libxcrun 發現工具。這項本機 tool discovery 調整沒有修改系統檔案。

- GLib 2.78 的 generator 仍 import distutils。使用 Python 3.12 venv + setuptools 84.2.1／Meson 1.12.1，未更動上游 GLib source。媒體的 env-shebang Python 與 FLEX override 也使用同一組 host-tools wrapper；gettext include／library 搜尋路徑明確指向本機已建好的 runtime。四語言整合測試額外連結非 pkg-config 的自製函式庫，覆蓋此類搜尋路徑問題。

- Homebrew brotli 1.2.1 source install 的 enc／dec dylib 對 common dylib 使用 `@rpath`，LC_RPATH 卻保留已刪除的 build 暫存目錄，造成 Wine sfnt2fon 在字型生成時 abort。僅在隔離 `.brew-x86/opt/brotli/lib` 將兩個 dylib 的 `@rpath/libbrotlicommon.1.dylib` 改成 `@loader_path/libbrotlicommon.1.dylib`；正式 engine 仍由現有 bundle 腳本統一重定位。沒有略過字型生成。
- Wine 媒體 profile 現在檢查 video pc、加入 gettext library search path，並用 `--with-gstreamer` 讓缺少必要媒體支援時 configure 失敗。一般未選媒體 profile 的建置不受影響。dry-run 不再寫入 engine version 檔。

- 回歸工具環境的 `.brew-x86/bin/python3` 另以 gitignored wrapper 指向上述原生 Python venv，避免 Intel Python 的 subprocess 再呼叫系統 Git trampoline。原 Homebrew symlink 保留為 `python3.pr3-original`，未更動系統 Python。bootstrap command-array fixture 補入媒體開關；launcher fixture 清除繼承的 MEDIA_INSTALL，讓「偏好 bundled」測試不受開發者明確指定的媒體路徑影響。
- 實際產物稽核發現 bundler 原先略過所有 `@rpath`／`@loader_path` 依賴，導致缺少 11 個間接函式庫卻仍顯示 OK。已在指定且受允許的輸入內解析依賴、遞迴收集並重定位；驗證會拒絕缺失 token、逃出 runtime 的 loader path 或非系統絕對路徑。新增真實 dylib 鏈、實際 dlopen 呼叫與缺檔負向測試。重新整理並簽署後，逐檔稽核與媒體載入探測都通過。

## 建置與測試入口

先完成上方隔離 Homebrew／toolchain 設定。以下命令使用專案腳本保留 minOS；GRAPHICS_INSTALL 應指定已驗證的 CrossOver graphics build：

```bash
source scripts/env-x86_64.sh
brew_x86_install_runtime zlib bzip2 libpng freetype gettext libffi gnutls pcre2
bash scripts/build-media-stack.sh --cx 26 --full-video \
  --media-install "$OGOM/install/media-cx26-full-video-x86_64" --jobs 4
export MEDIA_INSTALL="$OGOM/install/media-cx26-full-video-x86_64"
# export GRAPHICS_INSTALL=/absolute/path/to/validated/crossover-graphics
bash scripts/build-wine.sh --cx 26 --maplestory --with-vulkan \
  --vulkan-source crossover --jobs 8
bash scripts/sign-wine.sh --root "$WINE_INSTALL"
unset CC CXX OBJC OBJCXX
bash tests/run.sh
```

## 開發產物 SHA-256

這些 hash 識別本次隔離、ad-hoc 簽署的開發產物，不是發行下載雜湊。

| 產物（相對 install 根目錄） | SHA-256 |
|---|---|
| `bin/wine` | `d5b4aed5766ba17dc760048e06efcd466ae9a1aa6e26857a475ec78516320dc1` |
| `bin/wineserver` | `37a934ac2a88ec0442dc60f57664888731a53a002f170ed126f13d9a41d8c38e` |
| `lib/wine/x86_64-unix/winemac.so` | `3f7cec5ee04e40c3ff4989a3aebd04a255899ccafe386fbfc8a8ca31ae8b3c98` |
| `lib/wine/x86_64-windows/win32u.dll` | `5e53df08be50d0ddf3b9d515fd745a2734387dbbb44f0935a2461b1e485ad55f` |
| `lib/wine/i386-windows/win32u.dll` | `94cf9d58b3e1919245275db609fc9f4424e255b45c353e67bdee886c0d627eb9` |

## 仍需實機驗證

1. **PR #2 的 GL 驗收**：女神守護之約登入／伺服器畫面，BlueCG 拖曳縮放、Alt+Enter、最小化／還原及 Retina，大富翁 4／cnc-ddraw，以及每 frame 多次 Blt 的負擔。PR #2 作者的一款遊戲成功紀錄保留為上游證據，不計為本次重測。
2. **視窗與其他程式回歸**：frameless／CEF、client overflow、滑鼠座標、Retina 不同比例、resize、Quicken 例外，以及其他遊戲的視窗／全螢幕切換。
3. **CS2／DXMT**：初始化、borderless／Exclusive Fullscreen 的 Cmd-Tab／多螢幕、解析度與重啟、長時間遊玩；目前的函式與 Win32 探測不能證明 DXMT swapchain 行為。
4. **Steam／Paradox**：同一 prefix 的 Steam 登入保持、正常 launcher 與合法 direct Cities2／launcher bypass 路徑、結束與再次啟動。HTTPS smoke 不涵蓋 Steam session／WebHelper。
5. **遊戲內容與媒體**：城市載入、遊玩、存檔／重載、設定、過場影片／音訊；Paradox Mods 下載、重新下載及載入。插件可建立不等於遊戲播放流程已通過。
6. **未修改遊戲 DLL 的基準**：先確認 cohtml 未修補情況；若需遊戲補丁，另以版本／原始 hash／同意／備份／冪等／失敗還原／更新後拒絕的方案處理，排除授權驗證繞過。
7. **支援系統與發行**：實際較舊 macOS／不同 Apple Silicon、DXVK／DXMT／D3DMetal 的整體回歸；要發行仍需正式 graphics payload、Developer ID、封裝 gate 與對應實機驗收。minOS metadata 不代表已在所有舊系統測試。

PR 保持 draft；以上結果建立了可測試的 CX engine，未把上游 stock Wine 11.16 的 CS2 成功紀錄當成 Cyder 相容性驗收。
