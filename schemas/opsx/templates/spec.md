<!--
照下面的形狀寫，換成這張 change 的需求。完整寫法與原文範例：opsx 插件的 skills/propose/references/gherkin.md

關鍵字：Feature（功能模組）、Rule（原子化業務規則）、Scenario / Example（單一情境）、Scenario Outline + Examples（表格覆蓋多組測資）、Given / When / Then / And（前置、動作、預期、連接同類步驟）、Background（共用前置）、Docstring（""" 包多行文字）、Data Table（一個步驟帶多筆資料）、*（並列步驟）

選層，依序問：
1. 有多條業務規則嗎？否：基礎層，一個 Requirement 配正例與反例。是：中階層，每條規則一個 Requirement。
2. 同一條規則要驗多組測資嗎？是：進階層，Scenario Outline + Examples 表，一般場景與邊界場景都放進表裡。
3. 多個場景有相同的前置步驟嗎？是：加 Background。
需要批次資料用 Data Table；需要傳 JSON / XML 用 Docstring。

原子化：每條 Rule 是不可分割的業務邏輯單元；每個 Feature 對應一個要實作的邏輯模組；Rule 把複雜功能拆成獨立規則。

撰寫原則：
1. 使用業務語言，不寫資料表、欄位、函式名。
2. 每個 Scenario 保持獨立，可以任意順序執行。
3. 一個 Scenario 只驗證一件事。
4. 相似場景用參數化（Scenario Outline）。
5. 保持 Step 的原子性，每個步驟做一件事。
6. 每個 Requirement 至少一個正例、一個反例；反例沒有前置條件時可省略 GIVEN。
禁用模糊詞：正確的、適當的、合理的、正常、良好、妥善、等等、相關的、appropriate、properly、correctly、reasonable、etc.

openspec 格式：Feature 是這份 spec.md；Rule 是 ### Requirement:，標題下第一個非空行是含 SHALL 或 MUST 的規則句；Scenario 是 #### Scenario: <名>（正例｜反例）；Scenario Outline 是 #### Scenario Outline:，其下 Examples: 表；Background 放在規則句之後、第一個 Scenario 之前，只有 GIVEN；步驟寫 - **GIVEN** / **WHEN** / **THEN** / **AND**，參數用雙引號。
-->
## ADDED Requirements

### Requirement: 查詢商品價格
系統 SHALL 回傳已上架商品的當前價格；查詢不存在的商品時操作失敗。

#### Scenario: 查詢已上架商品的價格（正例）
- **GIVEN** 商品 "可樂" 存在於系統中，價格為 30 元
- **WHEN** 使用者查詢商品 "可樂" 的價格
- **THEN** 系統回傳價格為 30 元

#### Scenario: 查詢不存在的商品（反例）
- **WHEN** 使用者查詢商品 "不存在的商品" 的價格
- **THEN** 操作失敗

### Requirement: 會員等級折扣
系統 MUST 依會員等級套用折扣率回傳折扣後價格；黑名單會員查詢價格時操作失敗。

Background:
- **GIVEN** 商品 "可樂" 原價為 30 元

#### Scenario Outline: 查詢商品價格並套用會員折扣（正例）
- **GIVEN** 會員 "<會員名稱>" 的等級為 "<會員等級>"
- **WHEN** 會員 "<會員名稱>" 查詢商品 "可樂" 的價格
- **THEN** 系統回傳折扣後價格為 <折扣價> 元

Examples:
| 會員名稱 | 會員等級 | 折扣價 |
| 小明 | 一般會員 | 30 |
| 小華 | 銀卡會員 | 27 |
| 小王 | 白金會員 | 21 |

#### Scenario: 黑名單會員查詢價格（反例）
- **GIVEN** 會員 "小張" 的等級為 "黑名單"
- **WHEN** 會員 "小張" 查詢商品 "可樂" 的價格
- **THEN** 操作失敗
