---
name: logic-map
description: Turn the code one PR changed into a logic map the user can judge the work by — a numbered feature list, a flowchart whose decision nodes are numbered D1…Dn, and a condition table that gives each node its exact condition in FEEL with the file:line it came from. Reads only the code in the PR's diff range, never the spec, the chat, or the commit messages, so the map shows what the code does rather than what anyone meant it to do. Use when a PR is finished and the user wants to check the development work, when the opsx pr stage asks for a logic map, or when someone says "logic map", "邏輯表", "程式邏輯", "畫這支 PR 的邏輯", "他用了哪些邏輯", or "讓我判斷他的開發工作".
---

# Logic map

You produce one document: `logic-map.md`. The user reads it to decide whether the code in one PR does what they wanted. They will not read the code. Every condition you write is the thing they judge, so a wrong or softened condition is the worst mistake you can make here.

Write in the user's language (Traditional Chinese unless the request is in another language). Follow `../technical-writing/SKILL.md`: short sentences, the real symbol names, one name per thing, no metaphors.

## Inputs

You get a repo path and a diff range (`<base>...<head>`), and an output path. Nothing else. If any of the three is missing, stop and say which one.

Do not read `openspec/`, `report.md`, PR descriptions, or commit messages. They say what the author intended. The map exists to show what the code does, so the user can see where the two differ. Reading intent first makes you describe the intent.

## Steps

1. List the changed files: `git -C <repo> diff --name-only <base>...<head>`. Skip tests, fixtures, docs, and lockfiles. Keep source, hooks, scripts, and skill files whose text is executed as instructions.
2. For each kept file, read the diff, then read every changed function in full. A condition often sits outside the changed lines but decides whether they run.
3. Group the changes into features. A feature is one behavior someone outside the code would notice ("the commit gate picks the repo from `git -C`"). One PR usually has one to three.
4. For each feature, write the three parts below.
5. Take the title from the branch name only. If `<head>` is a branch name, use it; otherwise run `git -C <repo> rev-parse --abbrev-ref HEAD`. Do not read the commit message or the PR description to name the map: a PR title is intent too.
6. Write `logic-map.md` to the output path. Print the path and the number of features, nodes, and ⚠ marks.

## The three parts of a feature

### 1. Feature list

Number the steps the code takes, in execution order, in plain words. Each step names the function or file it lives in. Four to eight steps; merge trivial ones.

### 2. Flowchart

Draw it as plain text in a fenced block, not Mermaid. The user reads it in a terminal and in a PR comment, and text reads the same in both. Mermaid shows up as code until a viewer renders it.

- Read left to right, top to bottom, in execution order.
- A decision is `D<n> <短問句>?`, numbered in execution order. An action is a short verb phrase.
- The main path goes right with `─→`. A branch drops down with `└` and carries its label: `─是→`, `└否→`, or the value for a multi-way choice (`─問用戶→`).
- Where two paths join, end both with `─┐` / `─┤` on the same column and continue below with `▼`.
- A loop writes `(回D<n>)` at the end of the path that returns, instead of drawing the line back.
- Use only `─ │ └ ┐ ┤ ┘ ▼ →`. Keep lines under about 100 characters; split a long chart into two blocks at a decision and say where the second one starts.

Keep the chart to the logic the PR added or changed, plus every existing decision on the path from the entry of the enclosing function to it, including checks that return early before the new code runs for some input. A reader who cannot see the earlier checks will think the new code runs in cases it never reaches. Mark an existing decision with `（既有）` after its question so the user knows not to judge it as new work.

```
訊息 → D1 已登入? ─是→ 讀DB ─┐
             └否→ 讀session ─┤
                              ▼
       抽取候選 → 還有c? ─有→ D2 可信? ─否→(回)
                    │          └是→ D3 可存? ─否→(回)
                    │                  └是→ D4 怎麼存? ─問用戶→(回)
                    │                          └存→ D5 到期 →(回)
                    └沒了→ 排序 → D6 超預算? ─是→ 移除最低 →(回D6)
                                        └否→ 注入並回答
```

### 3. Condition table

One row per decision node, same numbers as the chart.

| 節點 | 決策 | 條件（FEEL） | 結果 | 位置 |
|---|---|---|---|---|

- **條件** is the code's condition rewritten in FEEL. Keep every literal: numbers, strings, word lists, regexes. If a list has more than five items, write the constant's name and put the full list in a note under the table.
- Translate faithfully, not charitably. If the code checks a substring, write `contains(…)`, not "is a merge question". If the code checks only the first match, say so. `references/feel.md` maps common shell and Python idioms to FEEL.
- **結果** names what each branch does, using the action names from the chart.
- **位置** is `path:line` of the condition, the line where the `if`, `case`, or `[[ ]]` starts.
- When the order of the checks changes the result (an earlier check swallows cases a later one was meant for), say it in the row of the earlier check.

### ⚠ marks

After the table, list what a careful reviewer would question. Each item is one sentence: the node, what the code does, and the concrete input that goes the wrong way. Mark patterns such as:

- Matching intent by keyword or substring.
- A number with no name or comment (`0.7`, `500`, `300`).
- A branch that silently does nothing, or falls back to a default the caller cannot see.
- A check whose order hides a later check.
- A missing case: an `if` with no `else` where the input can take the other value.

Do not mark style. Do not invent a problem to fill the list. An empty list is a valid result; write `無`.

## Output template

```markdown
# 邏輯表：<分支名>

範圍：`<base>...<head>` · 讀的檔：<n> 個 · 功能：<n> 個

## 功能 1：<一句話>

### 做了什麼
1. …

### 流程圖
```
…
```

### 條件表
| 節點 | 決策 | 條件（FEEL） | 結果 | 位置 |
|---|---|---|---|---|

### ⚠ 要看的地方
- …
```

Read `references/examples.md` before writing your first map. It has three complete maps: a Bash hook, a Python decision chain, and a product feature.
