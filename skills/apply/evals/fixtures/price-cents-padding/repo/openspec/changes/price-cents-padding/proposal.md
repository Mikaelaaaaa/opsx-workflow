## Why

分位不到 10 的金額少一個 0，客人看到的總計比實際金額看起來少很多（`$10.5` 實為 $10.05），已有客訴。

## What Changes

- 金額格式化對任何 0 以上的整數分，小數點後一律兩位

## Capabilities

### New Capabilities
- `pricing`: 金額顯示格式

### Modified Capabilities

## Acceptance

- spec Scenario「分位不到 10 補零」
- `npm test` 全綠

## Testing Decisions

- 測格式化函式的輸入輸出，照 `src/money.test.mjs` 的寫法
- 購物車總計走同一個格式化，不另寫

## Out of Scope

- 負數、多幣別、千分位

## Impact

- 金額格式化函式，以及所有用它顯示金額的地方
