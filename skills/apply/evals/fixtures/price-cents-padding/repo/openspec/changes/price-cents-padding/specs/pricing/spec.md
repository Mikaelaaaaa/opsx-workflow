## ADDED Requirements

### Requirement: 金額小數點後一律兩位
金額格式化 SHALL 對任何 0 以上的整數分輸出 `$<元>.<兩位分>`。

#### Scenario: 分位不到 10 補零
- **WHEN** 金額是 1005 分
- **THEN** 顯示 `$10.05`

#### Scenario: 零元
- **WHEN** 金額是 0 分
- **THEN** 顯示 `$0.00`
