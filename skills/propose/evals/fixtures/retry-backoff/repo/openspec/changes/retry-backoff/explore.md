## 已知

- Upstream 重新部署時回 503，通常一分鐘內恢復（CONTEXT.md）
- sync job 每頁有 60 秒預算（CONTEXT.md）；`src/sync.ts` 每次請求 timeout 5 秒（`REQUEST_TIMEOUT_MS`）
- `src/client.ts` 的 `getJson` 現在沒有任何重試：非 2xx 直接 throw
- `src/backoff.ts` 已有 `expDelays` 與 `fixedDelays`；實跑 `expDelays(5)` = [500, 1000, 2000, 4000, 8000]，合計 15500 ms

## 待決

## 不做

- 不改 sync job 的排程
