## Context

金額以整數分存放，顯示時才轉成 `$<元>.<分>`。

## Goals / Non-Goals

**Goals:**
- 小數點後一律兩位

**Non-Goals:**
- 負數、多幣別、千分位

## Decisions

這張卡沒有需要使用者選擇的地方，沒有 D。修法在 apply 時依重現結果決定。

## Risks / Trade-offs

- [其他地方自己拼金額字串，沒走格式化函式] → apply 時查呼叫端
