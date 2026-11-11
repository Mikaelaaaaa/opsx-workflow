---
name: apply
description: |
  Implement the tasks of an OpenSpec change, one task at a time, test first. Reads
  `openspec/workplan.yaml` for branch and dependency order, loads the playbook for the change's
  kind (dev / bug-fix / refactoring / perf / experiment / ops / chore), and for every task writes
  the test named in tasks.md before the code, runs it red, implements to green, checks the task
  off, commits one change as one commit, and writes status.json / decisions.tsv so the board can
  see progress. Asks nothing in autopilot: anything that needs the user becomes a gate in gates.md.
  Use when the user says "apply", "implement", "start working on", "do the tasks", "自動開發",
  "做下去", names a change slug, or when the opsx router injects `apply · <slug>`.
argument-hint: "[--auto] [pr-name | change-1 change-2 ...]"
compatibility: Requires openspec CLI and the opsx CLI (bin/opsx) for status.
---

# /apply

Implement tasks from an OpenSpec change. One change = one commit on its branch. Every task starts with its test.

The flow around you: `/opsx-workflow:propose` wrote `tasks.md` where each task carries `驗收：` (the spec scenario it satisfies) and `測試：` (the test file to write first). After you, `/opsx-workflow:review` refuses to look at a change whose tasks lack tests or whose tests are not green, and the Stop hook refuses to let you stop with unchecked tasks. So the order below is not ceremony; it is what the next stage will check.

## Setup (both modes)

### 0. Workplan health check (silent)

If `openspec/workplan.yaml` exists, reconcile it before anything else:

1. For each PR with status ≠ `merged`: find the forge from `git remote get-url gitlab` (else `origin`). A GitLab host: `glab mr list --source-branch <branch> --merged -F json`. `github.com`: `gh pr list --head <branch> --state merged --json number`. Any other host: skip this check and say so. A non-empty list means merged on the forge; if the workplan says otherwise → update to `merged`.
2. For each change with status ≠ `done`: if `openspec/changes/<name>/` is gone (archived) → update to `done`.
3. Report drift only when a decision is needed (branch deleted but MR not merged).

### 1. Pick the target

Parse `$ARGUMENTS`: `--auto` → autopilot; a PR name → every pending change in that PR; change names → those; nothing → show the workplan table and use **AskUserQuestion**. Without a workplan, `openspec list --json` and ask; work on the current branch.

### 2. Dependencies, branch, context

- A PR whose `depends-on` is not all `merged`: interactive asks whether to proceed; autopilot skips it and says why.
- Switch to the PR's branch (`git checkout <branch>` or create it from main). Never work on `main` / `master`.
- Per change: `openspec status --change <name> --json` and `openspec instructions apply --change <name> --json`; read every `contextFiles` entry. `blocked` → skip and report; `all_done` → mark `done` in the workplan and move on.
- Read `kind` from `openspec/changes/<name>/.openspec.yaml` (set at dispatch, confirmed by propose). Missing → treat as `dev` and say so.

### 3. Load the playbook for the kind

`Read references/playbooks/<kind>.md` (dev, bug-fix, refactoring, perf, hillclimb or eval for experiment; ops and chore have no file, use the table below) and `Read ../tdd/SKILL.md`. Put the playbook's steps into TodoWrite verbatim, interleaved with the skeleton below; a step you will not do stays in the list as `skip: <reason>`. The board reads progress from `status.json`, not from the todo, so call `opsx status apply <n>/<total> "<label>"` as you move.

| kind | playbook | what it adds on top of the skeleton | done when |
|---|---|---|---|
| dev | `playbooks/dev.md` | how (if explore skipped it) → architect → test first → implement → throughput checkpoint → verify → interrogate if contested | tasks all checked, every task's test file exists and the whole change is green |
| bug-fix | `playbooks/bug-fix.md` | reproduce yourself for runtime evidence → bisect to the mechanism → failing test (repro + edges), run red, not committed alone → fix → original repro passes | repro red → green, one commit; repro command and first red line in the commit message body |
| refactoring | `playbooks/refactoring.md` | characterization tests first → name the target shape → delete before moving → small steps, green after each → equivalence proof → reader load actually down or revert | pins green before and after, equivalence script output identical |
| perf | `playbooks/perf.md` + `../benchmark-checklist/SKILL.md` | behavior-preserving tests first → baseline trace through the seven questions → the seven mantras in order → change → measure again → compare artifacts | behavior tests green, baseline number, after number, delta, artifact path |
| experiment | `playbooks/hillclimb.md` or `playbooks/eval.md` | the harness is the test; freeze it after the seven questions; one hypothesis, one change, one measurement per loop | results table + verdict (do / don't / retry), decision.tsv |
| ops | none | compose validate → sops → pre-up → up → healthcheck; a task that touches a script still gets a shell assertion first | healthcheck green; deploy is level three, always a gate |
| chore | none | skeleton 3b (only when code is touched), 4, 10, 11, 12 | commit; touched code has a green test |

## Per task: the skeleton

Run this for every unchecked task, in order. Numbers match the requirement doc so the board and the reviewers can refer to them.

| # | step | read |
|---|---|---|
| 1 | Before writing: list every place the change reaches (callers, tests, fixtures, config, exports). Climb the ladder: does it need to exist, does the codebase already have it, does the stdlib or platform, does an installed package, can it be one obvious line, only then the smallest working code | `~/.claude/CLAUDE.md` §2–§3 (already in your context) |
| 2 | Name the data shape and where it lives (state machine, table, typed model) before touching code | `../../references/principles/model-the-domain.md` |
| 3 | If the task crosses a function boundary, sketch the types and signatures first, then fill the bodies. One candidate, no arena | `../architect/SKILL.md` |
| **3b** | **Write the test first.** Open the task's `測試：` path. Cover the `驗收：` scenario and the edges (empty, upper bound, bad input, out of permission). Run it once and confirm it is red; a green test here means it tests nothing, rewrite it. Do not commit the failing test alone; it lands in the change's one commit with the code (step 10). A task marked `測試：無 · <reason>` skips this step; put `skip: 無可驗收行為` in the todo | `../tdd/SKILL.md` |
| 4 | Implement until that test is green. Only then may anything the test did not demand be added, and only if a task asks for it. Then the four greps: unused imports you added; pattern divergence from two or three sibling files; a dependency you added that nothing imports; a helper that already existed under another name. Fix inline | — |
| 4b | **Comment pass over every file you touched**, before the test agent sees it. Keep a comment only for a non-obvious why the code cannot show; delete phase narration (`# --- 1. 找 gate ---`, `第一段 / 第二段`), who-asked-for-it and when (`review C`, `2026-11-06 改`), and anything the test or the commit message already says. Then run the unslop rules over what is left, rules 13 and 33 most of all: no arrows, no symbol-speak, whole sentences. A deliberate shortcut is the one exception and has one shape: `shortcut: <ceiling>, <when to upgrade>` | `../../references/comments.md` · `../unslop/SKILL.md` |
| 5 | Need the user? (a level-two action without a grant, a product choice.) Write one entry in `gates.md`: `type: approval | decision` (`approval` asks for a permission, `decision` asks for a choice; no other value, and never the board labels 等待授權 / 等待決定), the question, your recommendation, evidence, risk, what happens if nobody answers. When the recommendation is a command the user has to run themselves (outside the sandbox, say), add `needs: run` so the board does not offer a one-click "照建議". When a `decision` can only be answered after another card merges into main, add `waits-on: <that card's name>`; the coordinator parks the pane only on that line and never guesses it from the question's wording, so a gate without it is handled as an ordinary gate and the coordinator may answer your recommendation. An `approval` gate also carries `action: <value>`, copied from the grant hook's deny message; the board's "this time / this card" grant fails without it. Write it with Edit or Write and leave out `opened_at:`; a hook adds it after the write, because a hand-typed time gets the timezone wrong. Shape it the way a reviewer answers fastest: first `已確認：` with everything already settled on this point (so the work so far is not lost and the reader does not re-derive it), then `還需要你答：` with 2–4 concrete options, never "please clarify". Then keep working on what does not depend on it. Do not wait at the terminal; in autopilot the grant hook will deny the action and tell you the same thing. The same goes for any action a hook, a safety check, or auto mode blocks: stop on that action, put the full block message in the gate, and never get around it, unless a skill step names that deny as a failure to record (`/opsx-workflow:pr` step 5b): then record it as that step says, write no gate, and do not retry. Do not retry the command in another spelling (wildcards, `cd "$(…)"`), do not wrap it in a script, do not read hook scripts or settings files to find the gap. In autopilot, write Bash the way the router's `Bash 會被 dontAsk 拒的寫法` line says from the very first command (no loops, no assigning a command substitution to a variable and expanding it, no pipe inside a command substitution, one thing per call), so the deny never happens; a command that is still denied follows the rule above, not a rewrite | `../ketchup/SKILL.md` (action item fields) |
| 6 | A problem outside this task's scope? Do not fix it. Open the card with `opsx new --kind-of-work <incident|planned> [--impact <值,…> --evidence "<一行>"] [--area <value from openspec/areas.txt>] --repo <top> -- "<one line>"`: it writes `source: agent:<this card>` and the facts (`kind_of_work`, plus `impact` and `evidence` for an incident) into the frontmatter by itself. When the repo has `openspec/areas.txt`, `--area` is required and its value must be a line of that file; without the file, leave `--area` out. Put the full evidence in `--evidence` before you know whether it merges: nothing can amend it afterwards. The printed slug may be an existing card that this one was merged into (stderr says `併進 <target>（id <id>）`); never edit that card's `## 證據`, and when the evidence did not fit on one line, give the item its own card with `opsx split-out <target> <id>` and write the rest into that card's `## 證據`. Otherwise put longer evidence under `## 證據` in the new card's `inbox.md`. Run `opsx priority <slug>` only when it was not merged (a merged item is always P2 and the printed slug is someone else's card); if it prints P0 without a user override, write the `p0-review` gate per `../../references/priority.md`. The board shows it in the inbox. Open it, never dispatch it (worker 只開收件匣卡、不派): no `opsx dispatch`, no `/dispatch`, for this card or any other. Dispatching belongs to the user on the board and to `opsx coordinate`; a worker that dispatches multiplies panes until the user hits their usage limit | — |
| 7 | New branch, loop, parser, money, or security logic that tasks.md did not name? Add a small test for it to the same test file | — |
| 8 | Run the test agent (below) over **every** test file this change's tasks name, not just this one. Measured a number? Pass it through the seven questions first. Record the result: `opsx status apply <n>/<total> "<label>" --tests green` or `--tests red` | `../benchmark-checklist/SKILL.md` |
| 9 | Verify against the real artifact: run the command, hit the endpoint, open the page. "It compiles" is not done | `../../references/principles/prove-it-works.md` |
| 10 | Check the task off (`- [ ]` → `- [x]`), only when its test is green. One change = one commit: `git commit -m "<type>(<scope>): <summary>" -m "<body>" -- <paths>` (pathspec, never `git add -A`). For kind bug-fix the body carries the repro command and the first line of its red output (`playbooks/bug-fix.md` step 5). The commit hook checks the branch maps to this change and tasks are checked | — |
| 11 | One line in `decisions.tsv` through `opsx log <slug> <your agent name> <tag> "<what you decided and why>" "<evidence>"`, never a hand-written `printf` or `log.sh` (the board reads only that row format). Tag `替你決定` only when you picked a path the user would otherwise have had to choose (a product choice, a trade-off between two valid designs); every other call, including "no decision needed", gets `已決定`. The board lists `替你決定` rows in its banner, so overusing the tag buries the ones that matter | `../show-me-your-work/SKILL.md` (what to log; not its log.sh) |
| 12 | Reply: state first (done, broken, next). When the reply states one of three kinds of claim, the same sentence carries its evidence. A root cause gives file:line. A test result gives the test command and its pass and fail counts. A caller check gives the grep command and what it matched. A claim without that evidence is marked inferred or guess, never written as done; an action that was blocked or not run is said to be so. Then the last two lines: what you skipped, what you did not check, risks the user must know | `../../references/writing-the-reply.md` |

## Test agent

Spawn one **Agent** (general-purpose) when step 8 comes, and again after review fixes. Give it the project root, the list of test files from tasks.md, and the project's test and lint commands (CLAUDE.md first, then package.json / pyproject, then the usual `pnpm test`, `pytest`, `go test ./...`). A whole-suite run can take longer than the Bash tool's timeout (this repo's `tests/run.sh` takes about 20 minutes in an agent sandbox), so 背景跑 it with `run_in_background` and read its output file: `tests/run.sh` prints `START <name>` before each file and `PASS|FAIL <name> (<n>s)` after it, so a file that is still running is visible. It reports `STATUS: PASS|FAIL`, a one-line summary for tests and lint, the failing tests with the first lines of each error, and the full log.

On FAIL: read the log, fix, with a scope guard (a fix that needs files outside this task's scope aborts the change instead). Re-run. At most two fix cycles per change; still red → leave the working tree as is, write the failure into the reply, `opsx status … --tests red`, continue to the next change.

## Two modes

| | Interactive (default) | Autopilot (`--auto`) |
|---|---|---|
| Ambiguity | ask with **AskUserQuestion** | decide, log it in decisions.tsv |
| Level-two actions (push, MR, migrate, install, delete, external API, `.env`, a test file in a directory with no tracked tests: `test-path`) | ask | the grant hook decides from grants.toml / dispatch.json; denied → gate (step 5) |
| Commit | after the user says so | after the change's tests are green |
| Pausing | on unclear task, design issue, error | never; a design issue becomes a gate or an inbox card, not a stop |

Autopilot never touches `main`, never force-pushes, never merges. Those are level three and the hook denies them regardless of mode.

Speaking to a customer or anyone outside the team (an issue comment, an email, a chat message) is level three too. The grant hook cannot see an email or a chat message, and it judges every `glab issue note` / `gh issue comment` as `mr`, so not being denied does not make it allowed. Before you speak, write a `type: approval` gate and stop on that action. The one exception is `/opsx-workflow:pr` step 5b: the MR link it leaves on the issue the card came from is level two under `mr`, and the hook decides it.

## When the main change has subs/

A change with `openspec/changes/<main>/subs/` is a main change (`../../references/work-split.md`). You are the session: the main change's PR branch is yours, and each sub-change becomes one commit on it.

1. 先 propose 沒有 tasks.md 的子殼, one after another in workplan order, through the `propose` skill. They share your context; a subagent would have to rebuild it.
2. Pick the sub-changes whose workplan `depends-on` is empty or already stacked (checked in the main shell's tasks.md). Hand each to its own subagent, all at once: one Agent call per sub-change, `isolation: "worktree"`, `run_in_background: true`. A sub-change whose dependencies are not stacked yet waits until they are.
3. The brief follows `../../references/fan-out.md` ("Spawning") with these differences:
   - Start point: the PR branch's current HEAD, not `<remote>/main`. Branch: `git switch --no-track -c <action>/<主>--<子>/<user> <PR branch>`. opsx maps `<主>--<子>` to `subs/<子>/`: `opsx status` writes the sub-shell's status.json and the commit gate reads the sub-shell's tasks.md.
   - The workflow: call the `apply` skill for the sub-change, on its own tasks.md. Name the skill.
   - 派工指示: read the `## 派工指示` section of the main shell's `<top>/openspec/changes/<主>/inbox.md`, not the sub-shell's. `opsx note` writes only to main cards, so a sub-shell's inbox.md never has that section. A note that contradicts a D in the main shell's `design.md` is reported as `NEEDS-USER <子>`, so step 4 finds the right gates.md.
   - It commits once and stops: 不 push, no review, no pr. The harness may remove its worktree when it ends, and a resumed subagent does not get the old worktree back; the commit stays on its branch in the shared `.git`, which is all stacking needs. A follow-up for a finished sub-change goes to a new subagent on that branch, not a resumed one.
   - Report contract: `DONE <子> <sha>`, or `NEEDS-USER <子>` followed by the question, the options and the evidence.
4. On `NEEDS-USER <子>`, write the gate in 子殼的 gates.md (`subs/<子>/gates.md`), not the main shell's, and keep going with the others.
5. When a subagent cannot write the main repo's `openspec/` from its worktree, write its status for it: `opsx status <phase> <n>/<total> "<label>" --sub <子> --worker subagent-<子>`.
6. When a subagent ends with anything that is not `NEEDS-USER` (`DONE <子> <sha>`, an error, an empty report), first mark its sub-change finished so the Stop hook stops counting it as running: `opsx status apply <total>/<total> "<what it reported>" --sub <子> --worker session`, with `<total>` taken from that sub-shell's status. Then stack each `DONE <子> <sha>` onto the PR branch, in workplan 順序 (the order of the PR's `changes[]`), from the PR branch: `opsx stack <主> <子> <sha>`. It cherry-picks the one commit and checks that sub-change off in the main shell's tasks.md; do not check it off by hand or through skeleton step 10. A report that arrives before its turn waits; the command refuses a sub-change whose dependencies are not stacked yet.
7. `opsx stack` 退出 3 means conflict: it already aborted and logged a line in decisions.tsv. session 自己重做 that sub-change on the PR branch, through the same sub-shell (`--sub <子>`, worker `session`), test first, one commit. 不在衝突標記上手解: the subagent's tests were green on the old base, nobody would re-verify a hand merge. Then hand the sub-changes that depended on it to new subagents from the new HEAD.
8. A prompt `有新的派工指示，Read inbox.md 的 ## 派工指示` with no `[<子>]` prefix is a note written after the subagents started (`opsx note <主>` sends it to this pane, and a subagent's turns never reach the router). SendMessage every running sub-change subagent to read the `## 派工指示` section of `<top>/openspec/changes/<主>/inbox.md`, with the real path written in (the relative `inbox.md` does not exist in its worktree); each judges against its own tasks, and one that conflicts with a D in the main shell's `design.md` reports `NEEDS-USER <子>` (step 3). A sub-change whose subagent is not spawned yet needs nothing: its brief reads the file when it starts. For a sub-change that already reported `DONE`, read the note against its proposal and treat it as affected when unsure: if its sha is not stacked yet (`opsx stack`), drop the sha and hand the sub-change to a new subagent from the PR branch's current HEAD; if it is already stacked, do not rewrite the PR branch, write a `type: decision` gate in `subs/<子>/gates.md` and let the user choose.
9. When every item in the main shell's tasks.md is checked, run the whole test suite once on the PR branch, then continue to `/opsx-workflow:review <主>` and `/opsx-workflow:pr <主>` once for the main change (`../../references/continue.md`). Sub-changes get no review or pr of their own.

## When review sent tasks back

A `## R<N>. review 退回` group at the end of tasks.md holds in-scope findings from review round N. They are ordinary tasks: same skeleton, 測試先紅再修 (the regression test must be red on the current code before the fix), checked off only when green, one commit for the group (`fix(<scope>): address review findings`, one body line per finding). Do not edit report.md; review moves the `待修（範圍內）` lines when it re-reads your fix. When the group is done, continue to `/opsx-workflow:review <slug>` as usual.

## When this pane coordinates other cards

After `opsx chain` fans out (see `archive` step 6b), this pane hands each child card to a subagent and stays the only place that talks to the user. What goes to a subagent (independent cards whose tasks need nobody), what stays here (anything that needs the user, and cards that depend on each other), how prompts for a child arrive (`[<slug>] …`) and how a subagent's `NEEDS-USER` report becomes a gate in that card's `gates.md`: `../../references/fan-out.md`.

## After the last change

1. Update the workplan: changes → `done`; the PR → `in-progress` when all its changes are done.
2. `opsx status apply <total>/<total> "全部 task 完成" --tests green` (only if the last run really was green).
3. Reply with the table: change · tasks · tests · commit. Then continue to `/opsx-workflow:review <slug>` per `../../references/continue.md`: invoke it now, in this turn, unless a gate is open or the tests are not green.

## Guardrails

- Read the workplan and the change's context files before starting; use the CLI's `contextFiles`, do not guess names.
- Every task's test before its code. A checked task whose test file is missing is a review BUG by definition.
- Minimal, scoped diffs; check the task off right after it lands; update the workplan after each change.
- Stage by pathspec. Conventional commit subject in English, body in Chinese when a design call needs recording. No AI attribution anywhere.
- Max three test runs per change. Aborted changes do not block the others. Respect `depends-on`.
- Out-of-scope problems become inbox cards, never silent fixes.
- Principles are read when the situation calls for them (`references/principles/INDEX.md` lists which); cite only what you actually read this session.
