## ADDED Requirements

### Requirement: 金額小數點後一律兩位
金額格式化 SHALL 對任何 0 以上的整數分輸出 `$<元>.<兩位分>`。

#### Scenario: 分位補成兩位（Scenario Outline，正例）
- **WHEN** 金額是 <分> 分
- **THEN** 顯示 "<顯示>"

Examples: 一般場景
| 分 | 顯示 |
|---|---|
| 1005 | $10.05 |

Examples: 邊界場景
| 分 | 顯示 | 備註 |
|---|---|---|
| 0 | $0.00 | 零元 |

#### Scenario: 分位不到 10 不少一個 0（反例）
- **WHEN** 金額是 1005 分
- **THEN** 不顯示 "$10.5"
