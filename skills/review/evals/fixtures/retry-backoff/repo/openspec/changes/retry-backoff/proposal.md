## Why

Upstream 重新部署時回 503，nightly sync job 一遇到就整頁失敗。

## What Changes

- `getJson` 遇到暫時性失敗時，以有上限的指數退避重試
- 重試用完仍失敗時，錯誤訊息帶最後一次狀態碼與總等待時間

## Capabilities

### New Capabilities
- `upstream-retry`: 呼叫 upstream 的重試規則

### Modified Capabilities

## Acceptance

- spec Scenario「503 重試到恢復」「單次等待不超過 30 秒」「4xx 不重試」「重試用完的錯誤訊息」
- `npm test` 全綠

## Testing Decisions

- 測 `getJson` 的外部行為，fetch 與 sleep 由參數注入，不打真網路、不真的等

## Out of Scope

- 不改 sync job 的排程

## Impact

- `getJson` 與所有呼叫它的地方（sync job）
