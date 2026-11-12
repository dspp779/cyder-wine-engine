# 每次啟動的 native ddraw 路徑

`CX26.3.0-W11-Cyder013` 新增 `native-ddraw-path-v1`。
manifest 的 `capabilities` 是字串陣列；讀取端應容許未知項目。
兩份 `lib/wine/{i386,x86_64}-windows/ntdll.dll` 均含 ASCII marker
`CYDER_NATIVE_DDRAW_PATH_V1`。App 啟用功能前檢查 manifest 與對應 PE marker；
這個功能檢查不取代既有引擎封包／簽署完整性驗證。打包也會檢查兩份 PE，
避免靜態 metadata 把未修改的舊引擎宣稱為新能力。

`CYDER_DDRAW_PATH` 是一個完整 Windows 路徑，接受 drive-absolute 或 UNC，
末檔名須為 `ddraw.dll`。unset／空字串保持原載入行為。PE loader 在初始化
process parameters 後、main imports 前複製一次此值；之後修改該程序環境
不會切換其 ddraw 選擇。只重導向大小寫不敏感的 bare `ddraw`／`ddraw.dll`，
其餘名稱和 absolute LoadLibrary 請求不攔截。

這是檔案名稱解析能力，`WINEDLLOVERRIDES` 的 n／n,b／b 規則仍由原 loader
判斷。App 要載入原版 CNC native PE 時使用 `ddraw=n`。n,b 不是任意錯誤的
保證 fallback；指定路徑不存在時，可能在檔案解析階段直接 DLL_NOT_FOUND。
b 可以替換成 Wine builtin，且回報的 FullDllName 仍可能是請求路徑，不能只
憑 GetModuleFileName 宣稱真正命中外部 DLL。改名 DLL、本程序中途切換以及
已載入其他 absolute 同名模組的完整重用語意不在本能力保證內。

引擎不識別或改寫 CNC 的 INI。App 在 spawn 前驗證官方 payload hash／架構、
DLL+INI 配對，建立不可變的每次啟動設定，再設定既有的
`CNC_DDRAW_CONFIG_FILE`。正常 CreateProcess 會繼承兩個環境變數；每個子程序
在自己的 startup capture 路徑。若啟動器重建環境並丟失變數，仍有舊行為；
本版不實作隱藏 lineage context。不同 request 可在同 prefix 同時用不同
路徑與 INI，不寫 prefix-global registry 或 DLL order。

32-bit CNC 不會因為存在環境變數就被注入 64-bit launcher；只有該程序實際
請求 bare ddraw 才查指定檔。64-bit 程序載入 32-bit native DLL 仍會得到正常
架構錯誤；不宣稱支援 64-bit CNC。非法路徑的失敗也延到 ddraw 被請求時，
不使從未載入 ddraw 的 launcher 提前失敗。

實作為 `patches/cyder-ntdll-native-ddraw-path.patch`，納入 CX26 的
release patch。`tests/test-native-ddraw-path.sh` 驗證 production apply helper
重複套用／逆轉、實際 snapshot helper 與封裝能力 gate；runtime fixture 另在
指定的隔離 engine／prefix 執行。遊戲的登入、顯示與輸入仍須實際驗收。
