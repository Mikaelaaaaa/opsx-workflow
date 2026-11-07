## ADDED Requirements

### Requirement: 暫時性失敗以有上限的指數退避重試
`getJson` SHALL 對 503 與網路錯誤以指數退避重試，單次等待不超過 30 秒；對 4xx SHALL NOT 重試。

#### Scenario: 503 重試到恢復
- **WHEN** upstream 先回兩次 503 再回 200
- **THEN** `getJson` 回傳 200 的內容，期間等待 500 ms、1000 ms

#### Scenario: 單次等待不超過 30 秒
- **WHEN** upstream 一直回 503，重試 8 次
- **THEN** 最長一次等待是 30000 ms

#### Scenario: 4xx 不重試
- **WHEN** upstream 回 404
- **THEN** `getJson` 立即 throw，不等待、不再呼叫 upstream

### Requirement: 重試用完的錯誤訊息
重試用完仍失敗時，錯誤訊息 SHALL 帶最後一次的狀態碼與總等待時間。

#### Scenario: 重試用完的錯誤訊息
- **WHEN** upstream 一直回 503，重試 2 次
- **THEN** 錯誤訊息含 `last status 503, waited 1500 ms`
