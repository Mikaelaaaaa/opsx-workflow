---
name: review
description: |
  Spec-driven code review of an OpenSpec change before it becomes an MR. Refuses to start unless
  every task has its test and the change's tests are green, then runs three reviewers in parallel
  (one merged reviewer on a small chore or bug-fix card, at most two rounds)
  (A: spec conformance against design.md D-ids and tasks; B: code quality using the ponytail six
  categories; C: adversarial, attacks the premise and checks the tests prove the acceptance
  criteria), merges their findings with lead judgment into four buckets, sends every verified Bug and Must-fix
  that this change caused back to `/apply`, files the rest as inbox cards, and writes report.md. Use when the user says "review", "code review", "check my changes",
  "審一下", gives a change slug or MR number, or when the opsx router injects `review · <slug>`.
argument-hint: "[change slug | MR number]"
compatibility: Spawns three Agent subagents (A and B on claude-sonnet-5-5, C on claude-opus-5-5).
---

# /review

**Steps in TodoWrite.** First action after loading: put this skill's steps into TodoWrite verbatim; a step you will not do stays in the list as `skip: <reason>`, never deleted.

Three readers who do not share context, one lead who decides. The report they leave is what `/pr` and the board build on.

## Step 0: the gate

Read `openspec/changes/<slug>/tasks.md` and `status.json`. For every checked task, the `測試：` file must exist (or the line says `測試：無 · <reason>`), and `status.json.tests` must be `green`. If either fails, do not review: say which tasks lack tests or that the suite is red, and that `/apply <slug>` has to finish first. A review of untested code is a review of a guess.

A main change with `subs/`: also run `opsx check <slug>`. Any line it prints is a sub-change shell that is incomplete; stop the same way and name the lines.

Read the round from report.md: its title is `# Review · <slug> · 第 <N> 輪 · …`; no report.md means N is 0, and this run is round N+1. When N is already 2 or more, two rounds are done (the confirm pass in Step 4 edits report.md in place, keeps the 第 2 輪 title and is not a round): review does not start a reviewer. If report.md still lists items under `### 待修（範圍內）` and their `R` tasks in tasks.md are not all checked, send them back to `/apply <slug>` (Step 4). If those tasks are checked, run the confirm pass in Step 4. Write a gate in `gates.md` (`type: decision`) only for an item that needs a user decision and cannot be fixed; if nothing is open, say the review budget is used up and continue to the next node.

Decide small or not by `../../references/continue.md`, "Light flow" (kind chore or bug-fix, at most 3 tasks, one first path component outside tests). A small card runs one merged reviewer in step 2; any other card runs three.

`opsx status review 1/7 "gate 過了"`.

## Step 1: shared inputs

```bash
git diff main...HEAD > /tmp/review-<slug>-diff.txt
git diff --name-only main...HEAD > /tmp/review-<slug>-files.txt
git log --oneline main...HEAD > /tmp/review-<slug>-commits.txt
```

Paths to hand every agent: project root, branch, `proposal.md`, `design.md` (D-ids), `tasks.md`, `grill.md` if present, `CLAUDE.md`, `ARCHITECTURE.md`, `CONTEXT.md` when they exist. Scope from `$ARGUMENTS`: a slug, an MR number (`glab mr diff <n>`), or auto-detect the one in-progress change; several → **AskUserQuestion**.

## Step 2: three agents, one message

A small card spawns one merged reviewer (model `claude-sonnet-5-5`) instead: it gets both the Agent A brief and the Agent B brief below and returns one list in the shape below with `AGENT: AB`; Agent C does not run. Any other card spawns all three in a single message so they run concurrently. None of them sees the others' output. Each reads the diff and every changed file in full, plus two or three sibling files per changed file for the local pattern.

**Agent A, spec conformance** (model `claude-sonnet-5-5`). For each D-id in design.md: the file:line that implements it, or a finding. Goals have code; non-goals have none (scope creep is a finding). Each `- [x]` task does what it says, and its `測試：` file tests the `驗收：` scenario it names. Risks in design.md have their stated mitigation. Classification: BUG = task checked and the diff has no code for it (cite task number, plus the D-id it serves); MUST_FIX = the diff has code for the task or goal but it contradicts a decision (cite D-id), even if the task feels unfinished. Do not flag trade-offs design.md already acknowledges. Also return `D_TABLE`: one row per D-id in design.md, followed as well as violated; a followed D gets its file:line, a violated D points at its finding.

**Agent B, code quality** (model `claude-sonnet-5-5`). Knows nothing about the spec. Reviews for the six ponytail categories, each finding with a concrete failure case or it is downgraded: bug (input → wrong output), 安全 (trust boundary crossed without validation), 負載 (what breaks at 10× rows or users), 沒測試的風險 (new branch / loop / parser / money / auth with no test), 慢 (N+1, unbounded scan, sync I/O in a hot path), 多餘 (dead code, unused dep, duplicate helper, abstraction with one caller). Plus the code-quality lens from `../interrogate/references/code-quality-review.md`. MUST_FIX requires quoting the convention line from CLAUDE.md / ARCHITECTURE.md. Read `references/ponytail-review.md` for the category definitions.

**Agent C, adversarial** (model `claude-opus-5-5`). Prompt from `../interrogate/references/reviewer-prompt.md` with `rubric.md`. Its stance is that this change is wrong: attack the premise in design.md, list the alternative it skipped and why that one might be better, name the input, load, or ordering that breaks it. Then the tests: for each task, does the test actually prove the `驗收：` scenario, which edge is missing (empty, limit, bad input, wrong tenant), would the test still pass if the implementation were subtly broken. Every finding needs a concrete failure scenario; without one it is not listed.

All three return the same shape:

```
AGENT: <A|B|C>
D_TABLE:                      # agent A only
- d_id: <D1>
  status: <followed|violated>
  where: <file:line of the implementation, or of the finding it violates>
FINDINGS:
- severity: BUG|MUST_FIX|SUGGESTION
  file: <path>
  line: <n>
  d_id: <related D-id, or none>
  description: <one line>
  evidence: <failure scenario | D-id | convention quote>
  fix: <concrete instruction>
SUMMARY: <one paragraph>
```

## Step 3: lead judgment

Read `../interrogate/references/lead-judgment.md`. Merge: same file:line from two agents → one finding, keep the stronger evidence, mark it high-signal. Then every finding lands in one bucket, with a one-line reason:

- **Act on**: evidence verified by you (read the cited line, confirm the scenario), fix now.
- **Consider**: plausible but not proven, or a design question for the user; goes to the report, not to code.
- **Noted**: style or preference, no action.
- **Dismissed**: evidence does not hold; say why.

Evidence you cannot verify downgrades the finding one level, so an unverifiable finding in scope goes to Consider, not back to apply.

Then scope every BUG and MUST_FIX left in Act on. 範圍內 = the failure scenario cannot happen on main (a caller this change broke counts); run the scenario on main when you can. When it cannot be run, 範圍內 = the cited file:line is inside the added or changed lines of `git diff -U0 main...HEAD` (take `main` as the remote default branch, `origin/main` after `git fetch`; a stale local main pulls already-merged code into scope, and the "on main" scenario runs on the same base). 範圍外 = the scenario happens on main too. Only 範圍內 BUG and MUST_FIX are sent back to `/apply`.

Run `opsx check <slug>` and read every `Must-fix 候選` line it prints: the card's explore.md wrote 影響範圍 as skip, yet the diff touches a file other files reference. A candidate is a grep hit, not proof: it misses shell variables and config keys, and it flags files only their own tests reference. Read the cited reference yourself; a candidate you confirm is a Must-fix, and review sends it back to explore (the `## R<N>. review 退回` group in tasks.md, so `/apply` and explore's 影響範圍 step redo it); one you cannot confirm goes to Consider.

Seed the report's D 對照 table from Agent A's `D_TABLE` (followed → 照做, violated → 偏離) and keep every row, followed ones included. After bucketing, a row whose finding you dismissed becomes 照做, and a row that a B or C finding in Act on or Consider contradicts becomes 偏離. Cite file:line, not a finding number. Agents B and C write `d_id: none`.

A BUG of the kind 「task 已勾但沒實作」 is 範圍內: the task is this change's own. Before routing it, read the diff yourself and confirm the task has no code at all; if it has code that contradicts a D, it is a MUST_FIX against that D. Both take the Step 4 path: the report line says 回 `/apply <slug>` 做完, and review itself never writes the missing code.

## Step 4: hand back, do not fix

In this step review changes no code: it touches only `tasks.md`, `report.md` and the inbox.

- **範圍內, verified.** Append a group `## R<N>. review 退回` to tasks.md, one task per finding, each with the same `驗收：` and `測試：` sub-lines as any task (the `測試：` is the finding's regression test). List each under `### 待修（範圍內）` in report.md with its file:line. Then invoke `/apply <slug>` in this turn: apply writes the test first, fixes, checks the task off.
- **範圍外.** Do not fix it in this PR. Run `opsx new -- "<finding, failure scenario, file:line, 優先度 P2>"` (a security or data-loss incident takes the priority workplan-priority gives it instead of P2), and write `開卡 <slug>` on the finding's line in Consider.
- **Unverifiable or a design question.** Consider, as before.
- **Confirm pass** (round 2 is done and its R tasks are checked): re-read only the diff of the fixed items, not the whole change. Move each confirmed item from `待修（範圍內）` to Act on with the fixing commit, and write one line `確認: <sha>` (the current HEAD) in report.md. An item that is still wrong is not sent back to `/apply` (every R task is already checked, so apply would have nothing to do and the card would loop): it gets a `type: decision` gate, and the flow waits for the user. No third full review.

If a hook or safety check blocks any action here, follow `../../references/harness-claude-code.md`; do not reword the command to get past it. The suite is the test agent's job inside apply; review does not run a fix cycle.

## Step 5: report.md

```markdown
# Review · <slug> · 第 <N> 輪 · <date> · <commit>

## D 對照
| D | 狀態 | 位置 |
|---|---|---|
| D1 | 照做 / 偏離 | <file:line，或指向的 finding> |

## 四桶
### 待修（範圍內）
- <file:line> <description> · D-id <Dn|none> · 來源 <A|B|C> · task R<N>.<k>
### Act on（已修）
- <file:line> <description> · D-id <Dn|none> · 來源 <A|B|C> · 修前清單 <file:line> · commit <sha>
### Consider
- <file:line> <description> · D-id <Dn|none> · 來源 <A|B|C>（未實作的 task 寫：回 `/apply <slug>` 做完）
### Noted
- <file:line> <description> · D-id <Dn|none> · 來源 <A|B|C>
### Dismissed
- <file:line> <description> · D-id <Dn|none> · 來源 <A|B|C> · 因為 …

確認: <sha>   <!-- 只在第 2 輪後的確認 pass 寫 -->

## 測試
<test agent 最後一次的摘要：N passed，lint 狀態>

## Ledger
<commit sha> · <what was verified and how> · verdict: <green|red>
```

A later round rewrites the file from this template but keeps an existing `## MR` section verbatim: `/pr` appends it, and the router and merge read the URL from it.

`opsx status review 7/7 "report.md 寫好"`. Reply with the bucket counts, what was sent back to apply, which inbox cards were opened, what the user should look at in Consider, and the two closing lines. Then continue per `../../references/continue.md`: `/apply <slug>` while `待修（範圍內）` has items, otherwise `/pr <slug>`, in this turn, unless a gate is open. Consider never opens a gate and never sends the card back to apply. Only an item that needs a user decision and cannot be fixed opens a gate.

## Guardrails

- Never skip step 0. The gate is the whole point of test-first.
- Three agents every time except a small card (one merged reviewer); on any other card C is not optional and not only for contested designs.
- Findings without evidence are not findings.
- Two rounds at most. Anything in scope is fixed by `/apply` in this session; anything out of scope is an inbox card; the rest is in the report for the human reviewer.
- Review never implements a task or fixes code. 已勾但沒實作 and every in-scope finding go back to `/apply`.
