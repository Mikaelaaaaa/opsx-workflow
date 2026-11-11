# BDD 與 Gherkin

寫 spec 的規則在 specs instruction，這份放完整範例與解說，需要時才讀。前面各節照 HackMD「BDD 與 Gherkin 知識點」原文，範例照原文；最後一節是一份用 opsx 自己需求寫成的 openspec spec。

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

優勢：

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

## BDD 實踐流程

三方會議（PM + RD + QA 共同討論需求）→ 用 Gherkin 撰寫場景（轉成 Given-When-Then）→ 開發 Step Definitions → 執行測試 → 需求變更時同步更新 Gherkin 文件。opsx 不寫可執行的 Step Definitions：每個 Scenario 由 tasks.md 的 `測試：` 指到的測試檔來證明。

## 撰寫原則的對照例

使用業務語言，避免技術細節：

- ❌ Given 資料庫中 users 表有一筆 id=1 的記錄
- ✅ Given 會員 "小明" 已註冊

## 總結

- BDD 是開發方法論，強調用行為描述需求；Gherkin 是實現 BDD 的標準化語言。沒有 BDD，Gherkin 只是語法；沒有 Gherkin，BDD 難以標準化實踐。
- 架構層次（基礎 / 中階 / 進階）依功能複雜度選。
- 善用 Background、Data Table、Docstring 提升可維護性。
- BDD 的核心價值在於讓所有角色對需求有一致的理解。

## 對應到 openspec / opsx

上面的 Gherkin 寫成 openspec 的 spec.md 是什麼樣子：下面是一份用 opsx 自己需求寫的完整 spec，過 `openspec validate --strict`。標題怎麼對應看 specs instruction。

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

#### Scenario: 檢查單一份檔案（Scenario Outline，正例＋反例）
- **GIVEN** repo 的 "<檔案>" 狀態為 "<狀態>"
- **WHEN** 執行 `opsx init --check`
- **THEN** exit code 為 <exit>

Examples: 一般場景
| 檔案 | 狀態 | exit |
|---|---|---|
| spec 範本 | 與插件相同 | 0 |
| specs instruction | 與插件相同 | 0 |

Examples: 邊界場景
| 檔案 | 狀態 | exit | 備註 |
|---|---|---|---|
| spec 範本 | 與插件不同 | 1 | 手改過或插件更新了 |
| specs instruction | 與插件不同 | 1 | schema.yaml 還是 fork 來的版本 |

#### Scenario: spec 範本被手改過（反例）
- **GIVEN** repo 的 spec 範本被手改過
- **WHEN** 執行 `opsx init --check`
- **THEN** exit code 1
- **AND** 輸出含 "spec 範本與插件版不同" 與 "跑 opsx init 換成插件版"
```
