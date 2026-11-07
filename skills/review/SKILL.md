---
name: review
description: |
  Spec-driven code review of an OpenSpec change before it becomes an MR. Refuses to start unless
  every task has its test and the change's tests are green, then runs three reviewers in parallel
  (A: spec conformance against design.md D-ids and tasks; B: code quality using the ponytail six
  categories; C: adversarial, attacks the premise and checks the tests prove the acceptance
  criteria), merges their findings with lead judgment into four buckets, auto-fixes Bug and Must-fix
  once, and writes report.md. Use when the user says "review", "code review", "check my changes",
  "審一下", gives a change slug or MR number, or when the opsx router injects `review · <slug>`.
argument-hint: "[change slug | MR number]"
compatibility: Spawns three Agent subagents (A and B on claude-sonnet-5-5, C on claude-opus-5-5).
---

# /review

Three readers who do not share context, one lead who decides. The report they leave is what `/pr` and the board build on.

## Step 0: the gate

Read `openspec/changes/<slug>/tasks.md` and `status.json`. For every checked task, the `測試：` file must exist (or the line says `測試：無 · <reason>`), and `status.json.tests` must be `green`. If either fails, do not review: say which tasks lack tests or that the suite is red, and that `/apply <slug>` has to finish first. A review of untested code is a review of a guess.

`opsx status review 1/7 "gate 過了"`.

## Step 1: shared inputs

```bash
git diff main...HEAD > /tmp/review-<slug>-diff.txt
git diff --name-only main...HEAD > /tmp/review-<slug>-files.txt
git log --oneline main...HEAD > /tmp/review-<slug>-commits.txt
```

Paths to hand every agent: project root, branch, `proposal.md`, `design.md` (D-ids), `tasks.md`, `grill.md` if present, `CLAUDE.md`, `ARCHITECTURE.md`, `CONTEXT.md` when they exist. Scope from `$ARGUMENTS`: a slug, an MR number (`glab mr diff <n>`), or auto-detect the one in-progress change; several → **AskUserQuestion**.

## Step 2: three agents, one message

Spawn all three in a single message so they run concurrently. None of them sees the others' output. Each reads the diff and every changed file in full, plus two or three sibling files per changed file for the local pattern.

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

Evidence you cannot verify downgrades the finding one level. Only BUG and MUST_FIX in Act on get fixed.

Seed the report's D 對照 table from Agent A's `D_TABLE` (followed → 照做, violated → 偏離) and keep every row, followed ones included. After bucketing, a row whose finding you dismissed becomes 照做, and a row that a B or C finding in Act on or Consider contradicts becomes 偏離. Cite file:line, not a finding number. Agents B and C write `d_id: none`.

A BUG of the kind 「task 已勾但沒實作」 is always Consider, never Act on: fixing it is redoing `/apply`. Before routing it there, read the diff yourself and confirm the task has no code at all; if it has code that contradicts a D, it is a MUST_FIX against that D and takes the normal Act on path. The report line says 回 `/apply <slug>` 做完; review changes no code and does not touch tasks.md for it.

## Step 4: fix once

Scope first, before any edit. For every Act-on finding, write its 修前清單 into the Act on section of report.md: the finding's cited file:line, plus at most the one test location for the round's 回歸測試. A fix that needs any other place is 超出 the scope: move that finding to Consider and change nothing for it.

Then apply the fixes, touching only the listed places. The whole fix round may add at most 一個 回歸測試 in total, covering only the line fixed; it must be red before the fix and green after. Run the test agent (same as apply's). A fix that turns the suite red is reverted and reported. Commit: `fix(<scope>): address review findings` with one line per finding in the body. If a hook or safety check blocks the commit, follow `../../references/harness-claude-code.md`; do not reword the command to get past it. One cycle; no second review.

## Step 5: report.md

```markdown
# Review · <slug> · <date> · <commit>

## D 對照
| D | 狀態 | 位置 |
|---|---|---|
| D1 | 照做 / 偏離 | <file:line，或指向的 finding> |

## 四桶
### Act on（已修）
- <file:line> <description> · D-id <Dn|none> · 來源 <A|B|C> · 修前清單 <file:line> · commit <sha>
### Consider
- <file:line> <description> · D-id <Dn|none> · 來源 <A|B|C>（未實作的 task 寫：回 `/apply <slug>` 做完）
### Noted
- <file:line> <description> · D-id <Dn|none> · 來源 <A|B|C>
### Dismissed
- <file:line> <description> · D-id <Dn|none> · 來源 <A|B|C> · 因為 …

## 測試
<test agent 最後一次的摘要：N passed，lint 狀態>

## Ledger
<commit sha> · <what was verified and how> · verdict: <green|red>
```

`opsx status review 7/7 "report.md 寫好"`. Reply with the bucket counts, what got fixed, what the user should look at in Consider, and the two closing lines. Next step: `/pr <slug>`.

## Guardrails

- Never skip step 0. The gate is the whole point of test-first.
- Three agents every time; C is not optional and not only for contested designs.
- Findings without evidence are not findings.
- One fix cycle. Anything left is in the report for the human reviewer or the next session.
- Review never implements a task. 已勾但沒實作 goes back to `/apply`.
