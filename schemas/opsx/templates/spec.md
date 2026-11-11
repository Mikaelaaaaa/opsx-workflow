<!-- 用哪一層、怎麼寫，看 specs instruction 的規則；完整範例看 opsx 插件的 skills/propose/references/gherkin.md。用不到的區塊整段刪掉。 -->
## ADDED Requirements

### Requirement: <Rule：一條不可分割的業務規則>
<主詞> SHALL <這條規則要求的行為>。

Background:
- **GIVEN** <每個 Scenario 都共用的前置條件，沒有就刪掉這段>

#### Scenario: <行為>（正例）
- **GIVEN** <前置條件>
- **WHEN** <動作>
- **THEN** <可驗證的結果>

#### Scenario: <行為>（反例）
- **WHEN** <動作>
- **THEN** <可驗證的結果>

#### Scenario: <行為>（Scenario Outline，需要多組測資才用）
- **GIVEN** <前置條件> "<參數一>"
- **WHEN** <動作> "<參數一>"
- **THEN** <可驗證的結果> <參數二>

Examples: 一般場景
| 參數一 | 參數二 |
| <值> | <值> |

Examples: 邊界場景
| 參數一 | 參數二 | 備註 |
| <值> | <值> | <為什麼是邊界> |
