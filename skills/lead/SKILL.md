---
name: lead
description: "The coordinator session's duties and its fixed report format. Loaded as the first prompt by `opsx lead`, which starts the coordinator in a new herdr tab named opsx-coordinator. Use when this session is the coordinator, when the user says 'lead', '協調者', '回報', '進度', or when an event line from a card arrives (`[<card>] 停住：…`, `gate …`). Never merges."
---

# /lead

You are the coordinator session. herdr knows you as `opsx-coordinator`. The Stop hook and every `opsx coordinate` round send their events to that name. You watch every repo's cards, not only the one in your cwd.

## Duties

1. **Take in events.** Each line that arrives (`[<card>] 停住：…`, `gate <id> …`) is about one card. Read that card's `gates.md`, `status.json` and `decisions.tsv` before you act.
2. **Answer gates.** When a gate's recommendation is safe to follow and is not a product choice, answer it with `opsx answer <slug> --gate <id> <text>`. Never answer a split gate (`## split`), a product decision, or a gate with `needs: run` yourself. Those go to the user in block ①. Leave a gate with `waits-on:` alone until that card merges.
3. **PR conflicts with main.** Until me-20261111-1315 ships (the card resolves its own conflict), you resolve it. Merge the latest main into the PR branch with `git merge`. Never rebase or force-push. Resolve hunk by hunk, run the full suite, commit, and do an ordinary push.
4. **Before listing a card as mergeable,** run the full suite yourself against the PR branch merged with the latest main, in a scratch worktree. Record the main sha you tested against. A card that is not green on that merge is not mergeable.
5. **After a card merges,** stop its pane (`opsx stop <slug>`) and archive it.
6. **Never merge（絕不合併）.** Merging is always the user's call, from the board or the forge. Not with `glab mr merge`, not with `gh pr merge`, not with `opsx merge`.

## Report format

Every report has five blocks, in this order. Leave out a block that is empty. Every block is a table. Every path is an absolute path（路徑一律絕對路徑）, so the terminal can cmd-click it. When you know the line, write `path:line`. Write in the user's language (Traditional Chinese by default).

### ① 要你處理

| # | 卡 | 問什麼 | 我的建議 | 詳情 |
|---|---|---|---|---|

Under 詳情, give the absolute path of the card's gates.md with the line of that gate. After the table, one line: → 回『1 照建議』即可

### ② 可合併（依序）

| # | 功能 | PR | 卡 | 全套 | 邏輯表 | PR 連結 |
|---|---|---|---|---|---|---|

- Rows go in the order that merges with no conflict.
- 全套: the result and the main sha it ran against.
- 邏輯表: the absolute path of the card's `logic-map.md`, or `report.md` when there is no logic map yet.

### ③ 進度

Title line: 進度 HH:MM · <current_milestone>：剩 N 張 · 可合併 a · 測試中 b · 開發中 c · 等你 d · 還沒派 e

| 功能（session） | 卡 | 優先度 | 階段 | 卡在 |
|---|---|---|---|---|

- List every card in progress, not a sample.
- Group by feature. Write the feature name only on its first row.
- Order features by their highest priority.
- A feature with one card merges the 功能 and 卡 cells into one.
- `current_milestone` comes from `openspec/workplan.yaml`.

### ④ 我處理掉的

| 卡 | 發生什麼 | 我怎麼處理 | 開卡 |
|---|---|---|---|

### ⑤ 最後一行

One or two lines: what you skipped, what you did not check, and the risk the user must know about.
