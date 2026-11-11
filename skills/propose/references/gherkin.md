# BDD 與 Gherkin

propose 寫 specs 時讀這份。前面各節照 HackMD「BDD 與 Gherkin 知識點」原文提煉，範例照原文；最後一節講怎麼把它寫成 openspec 的 spec.md、opsx 流程怎麼用它。

## BDD 是什麼

BDD（Behavior-Driven Development，行為驅動開發）從 TDD 演進而來，用「行為」描述系統需求，關注軟體應該「做什麼」，而不只是「怎麼做」。

- 以行為為中心，從用戶和業務需求的角度描述系統行為。
- 讓 PM、RD、QA 使用同一種語言溝通。
- 將需求直接轉換為可執行的測試。

BDD 解決「需求翻譯」的問題，讓所有角色對需求有一致的理解。

## Gherkin 是什麼

BDD 是開發方法論（概念層面），Gherkin 是描述語言（實踐工具）。

- **領域特定語言（DSL）**：使用自然語言，但有明確的語法規則；人類可讀，機器可執行。
- **結構化語法**：

  ```
  Feature: 功能描述
    Rule: 業務規則
      Scenario/Example: 測試場景
        Given: 給定（前置條件）
        When: 當（執行操作）
        Then: 那麼（預期結果）
        And: 和（連接同類步驟）
  ```

- **可執行性**：Gherkin 文件可被 Cucumber、SpecFlow、Behave 等工具解析，連接到實際的測試代碼（Step Definitions）。

## 核心關鍵字

| 關鍵字 | 用途 | 說明 |
|---|---|---|
| Feature | 功能特性 | 描述要實現的功能模組 |
| Rule | 業務規則 | 原子化的業務邏輯單元 |
| Scenario | 具體場景 | 描述單一測試情境 |
| Scenario Outline | 參數化場景 | 用表格覆蓋多組測資 |
| Given | 前置條件 | 設定初始狀態 |
| When | 執行動作 | 觸發的事件或操作 |
| Then | 預期結果 | 驗證的輸出 |
| And / But | 連接步驟 | 連接多個同類步驟 |
| Background | 共用前置 | 所有場景共享的前置條件 |
| Examples | 測試數據表 | 提供多組參數化數據 |

## 三層架構

### 基礎層：Feature + Scenario（正例 + 反例）

適用時機：驗證單一功能的基本行為。

```gherkin
Feature: 查詢商品價格
  使用者可以查詢系統中任一商品的當前價格

  Scenario: 查詢已上架商品的價格（正例）
    Given 商品 "可樂" 存在於系統中，價格為 30 元
    When 使用者查詢商品 "可樂" 的價格
    Then 系統回傳價格為 30 元

  Scenario: 查詢不存在的商品（反例）
    When 使用者查詢商品「不存在的商品」的價格
    Then 操作失敗
```

- 用雙引號 `""` 標記參數；數字直接寫，不加引號。
- 反例沒有前置條件時，Given 可以省略。
- 應包含正例與反例。

### 中階層：Feature + Rule + Scenario（原子化規則）

適用時機：功能包含多條業務規則。

```gherkin
Feature: 計算訂單折扣

  Rule: 滿額折價
    當單筆訂單金額達到門檻時，系統應給予相應折扣

    Example: 訂單金額達到折扣門檻
      Given 系統設定滿 1000 元折 100 元
      And 購物車中有商品總額為 1200 元
      When 使用者結帳
      Then 折扣金額為 100 元
      And 最終金額為 1100 元

    Example: 訂單金額未達折扣門檻
      Given 系統設定滿 1000 元折 100 元
      And 購物車中有商品總額為 800 元
      When 使用者結帳
      Then 折扣金額為 0 元
      And 最終金額為 800 元
```

- 每條 Rule 是一個不可分割的業務邏輯單元。
- 每個 Feature 對應開發中要實作的一個邏輯模組。
- Rule 幫助把複雜功能拆成獨立規則。

### 進階層：Feature + Rule + Scenario Outline + Examples

適用時機：需要驗證多組測資和邊界條件。

```gherkin
Feature: 會員等級折扣計算

  Rule: 不同會員等級享有不同折扣率
    系統根據會員等級自動計算折扣價格

    Scenario Outline: 查詢商品價格並套用會員折扣
      Given 商品 "可樂" 原價為 30 元
      And 會員「<會員名稱>」的等級為「<會員等級>」
      When 會員「<會員名稱>」查詢商品 "可樂" 的價格
      Then 系統回傳折扣後價格為 <折扣價> 元

      Examples: 一般場景
        | 會員名稱 | 會員等級 | 折扣價 |
        | 小明     | 一般會員 | 30   |
        | 小華     | 銀卡會員 | 27   |
        | 小李     | 金卡會員 | 24   |

      Examples: 邊界場景
        | 會員名稱 | 會員等級 | 折扣價   | 備註             |
        | 小王     | 白金會員 | 21     | 最高折扣          |
        | 小陳     | 未登入   | 30     | 未登入無折扣      |
        | 小張     | 黑名單   | 錯誤    | 黑名單禁止查詢價格 |
```

- 避免重複撰寫相似場景。
- 清楚呈現不同輸入與輸出的關係。
- 測資可以分組（一般場景 vs 邊界場景）。

## 進階技巧

### Background：提煉共用前置步驟

適用時機：多個場景有相同的前置條件。

```gherkin
Feature: 會員下訂單
  會員必須先登入，才能將商品加入購物車並下訂

  Background:
    Given 會員 "小明" 已註冊，帳號為「ming@example.com」
    And 會員 "小明" 已登入系統
    And 商品 "可樂" 存在於系統中，價格為 30 元
    And 商品 "洋芋片" 存在於系統中，價格為 50 元

  Scenario: 會員下訂單包含單一商品
    Given 會員 "小明" 將商品 "可樂" 加入購物車，數量為 2
    When 會員 "小明" 下定訂單
    Then 訂單的訂單金額總額為 60 元
    And 訂單的擁有者為會員 "小明"

  Scenario: 會員下訂單包含多項商品
    Given 會員 "小明" 將商品 "可樂" 加入購物車，數量為 3
    And 會員 "小明" 將商品 "洋芋片" 加入購物車，數量為 2
    When 會員 "小明" 下定訂單
    Then 訂單的訂單金額總額為 190 元
    And 訂單的擁有者為會員 "小明"
```

- Background 會在每個 Scenario 執行前運行。
- 只放共用的前置條件，不要放測試邏輯。

### Docstring：傳遞複雜結構

適用時機：需要傳遞 JSON、XML、Markdown 等多行文本。

```gherkin
Scenario: 建立會員資料
  Given 系統接收到以下 JSON 資料
    """
    {
      "name": "小明",
      "email": "ming@example.com",
      "preferences": {
        "newsletter": true,
        "notifications": false
      }
    }
    """
  When 建立新會員
  Then 會員資料儲存成功
```

- 用三個雙引號 `"""` 包裹。
- 保持原始格式（包括縮排和換行）。

### Data Table：指定批次參數

適用時機：需要一次設定多筆結構化資料。

```gherkin
Scenario: 批次新增商品
  Given 系統中有以下商品
    | 商品名稱 | 價格 | 庫存 |
    | 可樂     | 30   | 100  |
    | 洋芋片   | 50   | 50   |
    | 礦泉水   | 20   | 200  |
  When 使用者查詢所有商品
  Then 系統回傳 3 筆商品資料
```

與 Examples 的區別：

- Data Table：在單一步驟中傳遞多筆資料
- Examples：定義多組完整的場景參數

### 星號（*）取代 And

```gherkin
Scenario: 完成購物
  Given 我正在購物
  * 我有雞蛋
  * 我有牛奶
  * 我有奶油
  When 我檢查清單
  Then 我不需要其他東西
```

用在多個連續的 And 步驟、列舉類型的步驟、要強調步驟並列關係的時候。

## 如何選擇架構

- 問題一：這個功能有多條業務規則需要處理嗎？否 → Feature + Scenario；是 → Feature + Rule + Scenario。
- 問題二：同一條規則需要驗證多組測資嗎？否 → 維持 Scenario；是 → 升級 Scenario Outline + Examples。
- 問題三：多個場景有相同的前置步驟嗎？是 → 加入 Background。

```
你的功能有多條業務規則嗎？
├─ 否 → 使用【基礎層】Feature + Scenario
└─ 是 → 使用【中階層】Feature + Rule + Scenario
         │
         └─ 需要驗證多組測資嗎？
            ├─ 否 → 維持 Scenario
            └─ 是 → 升級【進階層】Scenario Outline + Examples

有重複的前置步驟嗎？
└─ 是 → 加入 Background

需要批次資料嗎？
└─ 是 → 使用 Data Table

需要傳遞複雜結構（JSON/XML）嗎？
└─ 是 → 使用 Docstring
```

## BDD 實踐流程

三方會議（PM + RD + QA 共同討論需求）→ 用 Gherkin 撰寫場景（轉成 Given-When-Then）→ 開發 Step Definitions → 執行測試 → 需求變更時同步更新 Gherkin 文件。opsx 不寫可執行的 Step Definitions：每個 Scenario 由 tasks.md 的 `測試：` 指到的測試檔來證明。

## 撰寫原則

1. **使用業務語言，避免技術細節。**
   - ❌ Given 資料庫中 users 表有一筆 id=1 的記錄
   - ✅ Given 會員 "小明" 已註冊
2. **每個 Scenario 保持獨立**：不依賴其他場景的執行結果，可以任意順序執行。
3. **一個 Scenario 只驗證一件事**：避免過長的場景，複雜邏輯拆成多個 Rule。
4. **善用參數化**：相似場景用 Scenario Outline，減少重複。
5. **保持 Step 的原子性**：每個步驟做一件事，便於重用和維護。

## 常見陷阱

- **過度技術化**：Gherkin 應該讓非技術人員也能理解。
- **步驟耦合**：Given / When / Then 步驟互相依賴內部狀態。
- **缺乏具體性**：使用模糊的詞彙如「正確的」「適當的」。
- **過度使用 Background**：導致場景難以獨立理解。

## 總結

- BDD 是開發方法論，強調用行為描述需求；Gherkin 是實現 BDD 的標準化語言。沒有 BDD，Gherkin 只是語法；沒有 Gherkin，BDD 難以標準化實踐。
- 架構層次（基礎 / 中階 / 進階）依功能複雜度選。
- 善用 Background、Data Table、Docstring 提升可維護性。
- BDD 的核心價值在於讓所有角色對需求有一致的理解。

## 對應到 openspec / opsx

openspec 不認 `Feature:` / `Rule:` 字面關鍵字，Gherkin 的結構改用 openspec 的標題表達：

| Gherkin | openspec spec.md |
|---|---|
| Feature | 一份 `specs/<capability>/spec.md`，不另寫 `Feature:` |
| Rule | `### Requirement: <名>`；標題下第一個非空行就是規則句，必須含 SHALL 或 MUST |
| Scenario / Example | `#### Scenario: <名>（正例）` 或 `#### Scenario: <名>（反例）`，必須 4 個 # |
| Scenario Outline + Examples | `#### Scenario Outline: <名>（正例）`，其下一行 `Examples:` 再接 markdown 表 |
| Background | 放在規則句之後、第一個 Scenario 之前，只有 GIVEN / AND 步驟 |
| Given / When / Then / And | `- **GIVEN**` / `- **WHEN**` / `- **THEN**` / `- **AND**` |
| Docstring | 步驟下縮排的 `"""` 區塊 |

Background 放在規則句前面，`openspec validate` 會把 `Background:` 當成規則句，報缺 SHALL / MUST。

opsx 流程怎麼用：

- **Examples 表 ↔ 測試**：表的每一列是一個測試案例；`測試：` 指到的測試檔要逐列涵蓋，review 逐列對照。邊界值放進表裡，不另寫相似的 Scenario。
- **驗收指 Scenario**：tasks.md 每個 task 的 `驗收：` 寫 `specs/<capability>/spec.md「<Scenario 名>」`。
- **opsx check 檢查**：每個 Requirement 至少一個正例、一個反例；Scenario Outline 必有 `Examples:` 表；不出現禁用模糊詞；Background 不含 WHEN / THEN。

opsx 自己需求的完整範例（過 `openspec validate --strict`）：

```markdown
## ADDED Requirements

### Requirement: init 每次都覆寫 spec 範本
`opsx init` SHALL 每次執行都把插件的 spec 範本寫進 repo 的 `openspec/schemas/opsx/templates/spec.md`，重跑結果相同。

#### Scenario: 舊 repo 重跑 init 拿到插件版範本（正例）
- **GIVEN** repo 已裝過 opsx schema，spec 範本是 openspec fork 來的 WHEN/THEN 版
- **WHEN** 執行 `opsx init`
- **THEN** repo 的 spec 範本與插件的 `schemas/opsx/templates/spec.md` 逐位元相同

#### Scenario: 不在 git repo 裡執行 init（反例）
- **WHEN** 在沒有 `.git` 的目錄執行 `opsx init`
- **THEN** exit code 2，不建立 `openspec/`

### Requirement: init --check 指出過期的範本
`opsx init --check` MUST 比對 repo 的 spec 範本與 specs instruction 是否為插件版，不同就印出是哪一份並以 exit code 1 結束。

Background:
- **GIVEN** repo 已執行過 `opsx init`

#### Scenario Outline: 檢查單一份檔案（正例）
- **GIVEN** repo 的 "<檔案>" 狀態為 "<狀態>"
- **WHEN** 執行 `opsx init --check`
- **THEN** exit code 為 <exit>

Examples:
| 檔案 | 狀態 | exit |
| spec 範本 | 與插件相同 | 0 |
| specs instruction | 與插件相同 | 0 |

#### Scenario: spec 範本被手改過（反例）
- **GIVEN** repo 的 spec 範本被手改過
- **WHEN** 執行 `opsx init --check`
- **THEN** exit code 1
- **AND** 輸出含 "spec 範本與插件版不同" 與 "跑 opsx init 更新"
```
