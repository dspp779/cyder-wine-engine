# 引擎打包的可選 PE Authenticode 簽署

狀態（2026-11-02）：流程與離線測試已實作，**尚未取得正式 Windows code-signing 憑證／服務，沒有產生正式 PE 簽署引擎或更新 runtime**。Apple Developer ID 與 PE Authenticode 是兩個不同身分；既有 Apple 簽署／公證繼續保留，不能代用為 PE 憑證。

此工作在 `codex/issue-12-pe-release-signing` 隔離分支，以 engine `c53b70e` 為基準；不改動原工作目錄的未提交內容。CyderBits 的 prefix 診斷與 OEM 實測另在 `codex/issue-12-prefix-integrity`。

## 預設打包與可選簽署

`pack-engine-artifact.sh` 預設 `CYDER_PE_SIGNING=off`。即使設定 `SIGN_IDENTITY='Developer ID Application: …'`，也**不要求購買或配置 Authenticode 憑證**；保留既有 Apple Developer ID／Mach-O 簽署、graphics 正式驗證與發行時的公證流程。未簽 PE 可依可信 manifest 正常驗證，不把未購買憑證視為損壞。

只有明確設定 `CYDER_PE_SIGNING=required` 才啟用 PE 簽署。僅設定 policy／signer 等變數不會自動啟用；未知 mode 值停止，避免設定錯字被靜默接受。選用後仍須先通過完整設定檢查；失敗不退回 off。兩種模式都在 staging 保留上游既有簽章，不無差別重簽。

預設模式不宣稱逐檔 Authenticode 憑證鏈／時間戳已驗證；由原件保留、發行者綁定的 archive／逐檔 manifest 與 prefix 診斷提供內容證據。staging 不繼承輸入樹中的舊 `cyder-pe-provenance.json`，未實際啟用並通過新驗證時，不產生 `peAuthenticode.status=verified` 的 manifest 宣告。

以下簽署與 Authenticode 封存驗證步驟僅適用於 `required` 模式；其中保留上游 PE、不修改 install／runtime 的規則適用於所有模式。
1. 從 install 複製至既有 pack 的獨立 staging；不簽原始 install、正式 runtime 或使用者 prefix。
2. `strip-wine-install.sh` 先移除自建 PE 的 DWARF，**已帶有 embedded certificate table 的 PE 完全不 strip**，即使有 debug sections 亦保留。這只是保護原位元組，原簽章是否有效僅在選用 required 時由後續 Authenticode 驗章確認；畸形 PE 不會因解析失敗被當成 unsigned strip。
3. bundle 完成後，以 `pe-signing.py prepare` 檢查兩架構 Wine PE 與審核清單逐項一致，先驗證所有輸入，再呼叫 signer。只允許明列原始 SHA-256 且標為 `cyder-built` 的未簽 PE 進入簽署；上游已簽 PE 不會被重新簽署。
4. signer 輸出至新的 staging 暫存檔。除 checksum、certificate directory 及 EOF 對齊／新增 certificate table 外，原有 PE 內容必須不變。簽署器若修改程式內容、無輸出、改寫輸入、回傳失敗或逾時，就停止。
5. `osslsigncode verify` 必須成功，且核對允許的 leaf certificate SHA-256、code-signing 憑證鏈、TSA 憑證鏈、簽章與可驗證時間戳。正式 gate 不使用 `-ignore-crl`／`-ignore-timestamp` 或不可信憑證 fallback；信任或撤銷服務不可用就停止。
6. 產生 `cyder-pe-provenance.json`，記錄審核政策 digest、每檔原始／最終 digest、大小及 action。PE 簽完才產生 ntdll hash／engine manifest。內部與 sidecar engine manifest 的 `peAuthenticode.sha256` 綁定 provenance；CyderBits 既有逐檔 inventory 會自然讀取簽署後內容，不能沿用舊 hash。
7. tar 解壓往返後再比對 provenance digest、逐檔範圍／內容／簽署者／時間戳，全部通過才寫入版本與 checksum sidecar。既有 Mach-O 解壓後驗章仍執行。

選用 PE 簽署時，archive 已存在即使 `--force` 亦拒絕重用／覆寫，必須選擇未使用的引擎標籤。新簽署會改變 PE hash 與 archive 身分，不能以相同標籤悄悄替換舊正式產物。預設 off 不新增這項限制，保留既有快取／`--force` 行為。本次沒有修改 canonical engine version 或發布任何標籤。壓縮／往返驗證失敗留下的候選 archive 不會有新成功 sidecar，須視為失敗候選處理，不得發布。

## 範圍與審核清單

範圍為 `lib/wine/i386-windows/**` 與 `lib/wine/x86_64-windows/**`，依實際 PE header 辨識，不依 `.dll` 副檔名猜測。各架構 machine 必須符合目錄；拒絕 symlink、特殊檔案、未知新增 PE、缺檔、錯誤 digest 或重複路徑。DOS／NE 不是本次 Authenticode 目標；獨立 graphics、Apple GPTK、遊戲、反作弊及其他第三方目錄不會因此被簽署。

先在**可丟棄的副本**執行相同 strip 階段，再建立待審核 inventory：

```bash
python3 scripts/pe-signing.py inventory --root /absolute/path/to/stripped-staging-copy \
  --output /absolute/path/to/new-pe-review.json
```

此命令只讀取引擎並新增 review JSON，拒絕覆寫現有 JSON。所有 action 預設 `review-required`，不自動推定所有權，也不直接變成可簽署政策。正式 policy 範例：

```json
{
  "schemaVersion": 1,
  "signingCertificateSHA256": "正式簽署 leaf certificate DER 的 SHA-256，64 個小寫十六進位字元",
  "timestampURL": "https://your-approved-tsa.example/",
  "files": [
    {
      "path": "lib/wine/i386-windows/bcrypt.dll",
      "sha256": "strip 後、簽署前的精確 SHA-256",
      "action": "sign",
      "ownership": "cyder-built"
    }
  ]
}
```

以上故意不是可直接發布的完整政策。實際 JSON 必須涵蓋兩架構**所有**辨識出的 PE：

- `sign`：只有已核對為自建且有權簽署的未簽 PE，必須 `ownership=cyder-built`。
- `preserve`：原件已簽，記錄其 SHA-256 與原 signer 的 `certificateSHA256`；原件及解壓產物皆須驗章／時間戳通過，位元組不能變動。
- `unsigned-exception`：確實需保持未簽的 PE（例如經審查的 metadata），必須具精確 hash 與具體 `reason`。不提供萬用 glob 或全面 unsigned 例外。

每次自建內容、strip 結果、憑證或政策改變，重新盤點審核。保持上游簽章；無權簽署或來源不清的項目停止並釐清，不為提高覆蓋率統一重簽。

## 簽署後端與憑證設定

簽署服務尚未選定，因此不把私鑰／密碼處理寫死為 PFX。實作採用硬體 Token／HSM／雲端服務都能接上的執行檔 adapter；**目前未包含任何已連接真實帳戶的 provider adapter**，待取得憑證後按實際供應商新增。這是實際正式簽署前的必要工作，不是目前已完成的能力。

設定於受信任的發行機環境：

```bash
export SIGN_IDENTITY='Developer ID Application: …'
export CYDER_PE_SIGNING=required  # 只有主動選用 PE 簽署時才設定
export CYDER_PE_SIGNING_POLICY=/absolute/path/to/reviewed-policy.json
export CYDER_PE_SIGNER=/absolute/path/to/provider-adapter
export CYDER_PE_VERIFY_TOOL=/absolute/path/to/osslsigncode
export CYDER_PE_CA_FILE=/absolute/path/to/trusted-public-code-signing-roots.pem
export CYDER_PE_TSA_CA_FILE=/absolute/path/to/trusted-public-tsa-roots.pem
python3 scripts/pe-signing.py preflight --policy "$CYDER_PE_SIGNING_POLICY"
```

驗證器應使用經核對的 osslsigncode 2.12（本次測試版本）或另經回歸確認的相容版本。CA 檔、adapter、verifier 與政策是發行設定的信任邊界；使用正式公共 CA 憑證與受控 trust stores，不能加入測試根憑證來假裝正式信任。環境變數中只有檔案／工具位置，不把私鑰或 token 提交 repo 或貼入聊天。

adapter 的固定呼叫介面：

```text
provider-adapter --input <staging PE> --output <new staged signed PE> --timestamp-url <HTTPS TSA>
```

adapter 必須自行以供應商正式流程驗證身分、簽署並取得時間戳，只讀 input、只寫 output、成功 exit 0。gate 不透過 shell 執行命令、不接受命令片段，不列印 provider 輸出，避免憑證服務的診斷洩漏認證資訊。正式驗章由獨立 verifier 執行，不採信 adapter 的成功訊息。

一般正式包可繼續只使用 Apple Developer ID 與既有發行／公證流程，保持 `CYDER_PE_SIGNING=off` 或不設定即可。未來若另行決定取得憑證並啟用 PE 簽署，再完成 adapter／policy，以**未使用的新引擎標籤**打包。這不是本階段發行的前置條件。

## 驗證結果與剩餘事項

```bash
python3 tests/test-pe-signing.py
bash tests/test-pe-release-gate.sh
bash tests/test-strip-wine-install.sh
bash tests/test-sign-wine.sh
bash tests/test-sign-wine-preserve-developer-id.sh
bash tests/test-engine-manifest.sh
CYDER_ENGINE_MEDIA_PROFILE=minimal bash tests/test-pack-engine-dxmt-gate.sh
bash tests/test-graphics-release-pack.sh
python3 tests/test-graphics-signing.py
```

Python 有 15 項離線測試；可用既有工具額外執行真實密碼學 fixture（不下載、不使用正式憑證）：

```bash
CYDER_TEST_OSSLSIGNCODE=/absolute/path/to/osslsigncode \
CYDER_TEST_OPENSSL=/absolute/path/to/openssl \
  python3 tests/test-pe-signing.py
```

本次 15 項全部通過，包含以臨時自簽測試憑證簽署測試 PE，驗證內容保持、正確 leaf pin 可驗、錯誤 leaf pin 被拒絕，以及沒有 timestamp 時正式 gate 拒絕。此憑證僅供測試、不加入正式 trust store；正向 timestamp／封裝案例使用明確 mocked verifier，不冒充真實 TSA／正式憑證驗收。

測試另涵蓋保留上游／unsigned 例外、修改內容拒絕、輸入來源／政策錯誤、未知項目、symlink、架構、憑證與工具缺失、provider 失敗／逾時輸出遮蔽、封存往返、重新 prepare 拒絕、已簽 PE 帶 DWARF 仍不 strip，以及預設／明確 off 的 Developer ID 打包不需 PE 憑證、保留 graphics release 路徑；僅 required 無配置時不寫 graphics／不覆寫 archive。亦驗證無效 mode 拒絕、殘留設定不隱式啟用及 manifest 不繼承舊驗章宣告。

完整 `bash tests/run.sh` 已嘗試，於隔離 checkout 的 `test-cyder-cxcompatdb.sh` 因缺少已 configure 的 Wine `build64/include/config.h` 停止；前面的部分 source／Meson 案例亦明示 SKIP。這是環境前置缺口，沒有把完整套件描述為通過，也未為此執行 Wine make／install。相關窄範圍回歸另行執行。

若未來主動選用 PE 簽署，尚需：選定／取得正式 code-signing 憑證及服務、真實 provider adapter、每版可審核的建置來源與 strip 後政策、真實憑證／TSA／CRL 的正向與失敗驗收、正式封存往返、不同支援系統的 wineboot／遊戲／反作弊測試，以及防護開啟的 Bitdefender 同源未簽／簽署對照。簽章保留已在 CyderBits 的 OEM wineboot 實測確認，但不代表防毒必定允許。


## 目前採用方向（2026-11-02）

先不購買憑證、不啟用 paid signing、不更新正式 runtime。P3-01 保留可選受控實驗；P0-01 優先取得受影響樣本精確 hash／建置與 Bitdefender 隔離紀錄，P0-02 保留已補強的 runtime／prefix 關鍵檔案診斷，後續再設計只恢復受管理缺檔且遇重複隔離停止的受控修復。這些不依賴 Authenticode 採購，也不能宣稱已完成防毒誤報修復。

本次可選化回歸：15 項 PE 核心測試全部通過（含既有本機工具的真實測試憑證 fixture）；可選模式 shell fixture 亦完成真正 tar/xz／內外 manifest 往返，僅以 stub 取代 Apple／graphics 簽署與環境相關階段，確認 default/off 在無 PE 憑證設定時能完成測試封裝、不複製陳舊 provenance、不宣告已驗章，且保留來源檔案與副本位元組。這不是實際 Developer ID 發行包驗收。strip、Apple 簽章與 Developer ID 保留、engine manifest、技能驗證及差異格式檢查通過。CyderBits 的 prefix／元件測試 34 cases／158 assertions、hook 與 AppKit 背景／取消／deadline 測試重跑通過；未變更 prefix 診斷程式。完整套件的既有 Wine config.h 前置缺口仍未補建，未宣稱全套通過。
