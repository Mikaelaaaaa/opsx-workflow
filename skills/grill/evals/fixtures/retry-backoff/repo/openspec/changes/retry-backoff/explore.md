## 已知

- Upstream 重新部署時回 503，通常一分鐘內恢復（CONTEXT.md）
- sync job 每頁有 60 秒預算（CONTEXT.md）
- `src/backoff.ts` 已有 `expDelays` 與 `fixedDelays` 兩個 helper

## 待決

- `src/client.ts` 的 `getJson` 現在有沒有任何重試？
- `expDelays(5)` 的等待時間加起來是多少，會不會吃掉 60 秒預算？
- 重試的等待策略要用哪一種：指數退避、固定間隔，還是指數退避加上單次等待上限？

## 不做

- 不改 sync job 的排程
