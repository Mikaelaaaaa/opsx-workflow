## 1. 重試

- [x] 1.1 `getJson` 以指數退避重試，單次等待上限 30 秒
  - 驗收：specs/upstream-retry/spec.md「503 重試到恢復（正例）」「單次等待不超過 30 秒（正例）」
  - 測試：src/client.test.ts
- [x] 1.2 只對 503 與網路錯誤重試，4xx 立即 throw
  - 驗收：specs/upstream-retry/spec.md「4xx 不重試（反例）」
  - 測試：src/client.test.ts
- [x] 1.3 重試用完的錯誤訊息帶最後狀態碼與總等待時間
  - 驗收：specs/upstream-retry/spec.md「重試用完的錯誤訊息（正例）」「總等待時間不算最後一次失敗之後（反例）」
  - 測試：src/client.test.ts
