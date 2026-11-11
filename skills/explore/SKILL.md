---
name: explore
description: |
  Thinking partner that explores ideas and challenges plans against the project's domain model.
  Combines open-ended exploration with structured grilling — surfaces multiple directions when 
  the problem is fuzzy, drills into specifics when decisions crystallize, and sharpens terminology
  against CONTEXT.md throughout. Captures decisions in ADRs and glossary entries inline.
  Use this skill whenever the user wants to think through something, explore a design, discuss 
  architecture, stress-test a plan, get grilled on their approach, compare options, investigate 
  a problem, clarify requirements, review active changes after docs changed, or re-plan work
  — even if they don't say "explore" explicitly. Also trigger when the user says "what do you 
  think about", "let's discuss", "challenge this", "I'm not sure about", "review 
  the plan", "docs changed", "需求變了", "重新看一下", or asks an open-ended design question.
  In the opsx flow it is the first node: it ends by writing openspec/changes/<slug>/explore.md
  (已知 / 待決 / 不做); a non-empty 待決 hands off to /grill, an empty one straight to /propose.
argument-hint: "[topic | change-name | question]"
---

# /explore

**Steps in TodoWrite.** First action after loading: put this skill's steps into TodoWrite verbatim; a step you will not do stays in the list as `skip: <reason>`, never deleted.

Think deeply. Challenge freely. Capture decisions as they crystallize.

**This is a stance, and when you work a card it also has steps.** The conversation has no script; you are a thinking partner who knows the project's domain language and decision history. The nine steps in "Steps" below are the part that always gets a record in explore.md.

**Explore mode is for thinking, not implementing.** Read files and investigate the codebase, but never write application code. Creating documentation artifacts (CONTEXT.md, ADRs, OpenSpec proposals, workplan) is capturing thinking — that's fine.

---

## How to Engage

Your engagement intensity should match the conversation. Don't announce transitions — just shift naturally.

**When the problem is fuzzy** — be curious. Surface multiple directions, sketch ASCII diagrams, ask open questions, follow tangents. Don't rush toward a decision.

**When a decision point emerges** — get specific. Use **AskUserQuestion** with 2-4 concrete options when the user needs to choose between real alternatives. This isn't interrogation — it's helping them see the options clearly.

> Why AskUserQuestion? Open-ended "what do you think?" questions often get vague answers.
> Concrete options force clarity: "Redis vs SQS vs BullMQ for this queue?" is more productive
> than "what queue should we use?" The user can always pick "Other" if none fit.

**In autopilot** (the router line carries `autopilot：`), never call AskUserQuestion. Nobody is at the pane, and herdr marks the agent blocked. Do not settle the user's choices yourself here either. Write each open choice into explore.md's 待決, with the options you would have offered, and let /grill handle it under its autopilot rules (`skills/grill/SKILL.md`, "In autopilot"). A split still goes through the one gate in "Splitting a big card"; autopilot does not skip it.

**When terms are vague** — challenge the language. "What do you mean by 'user'? Is that a Customer, a Tenant Admin, or an End User?" Every vague term in a plan becomes a bug in the implementation.

---

## Domain Awareness

### On first message

Silently load the project's domain context — don't narrate this to the user:

1. Check for `CONTEXT-MAP.md` (multiple contexts) or `CONTEXT.md` (single context) at repo root
2. Scan `docs/adr/` for existing decisions
3. Run `openspec list --json 2>/dev/null` to check for active changes
4. Check for `docs/ARCHITECTURE.md` and `CODEBASE.md` (from `/sync`)
5. Check for `openspec/workplan.yaml` (existing work plan)
6. If workplan exists → run **Workplan Health Check** (see below)

If none exist, that's fine — you'll create them lazily when decisions emerge.

### Workplan Health Check (silent)

Run this automatically whenever `openspec/workplan.yaml` exists. Don't narrate unless something needs a user decision.

1. For each PR where status ≠ `merged`:
   - `git branch --list <branch>` — does the branch exist locally?
   - Find the forge from `git remote get-url gitlab` (else `origin`). A GitLab host: `glab mr list --source-branch <branch> --merged -F json`. `github.com`: `gh pr list --head <branch> --state merged --json number`. Any other host: skip this check and say so.
   - If the list is not empty (merged on the forge) but workplan says `pending`/`in-progress` → auto-update to `merged`
2. For each change where status ≠ `done`:
   - Check if `openspec/changes/<name>/` still exists
   - If missing (archived or deleted) → auto-update to `done`
3. Only report drift to the user if something needs a decision (e.g., branch deleted but PR not merged, or a change directory is gone but its PR isn't done)

### Sharpening terminology

Throughout the conversation, watch for:

- **Glossary mismatches** — The user says "purchase" but CONTEXT.md defines "Order". Gently correct: "In our context, we call that an **Order**."
- **Codebase conflicts** — The user says "client" but the code uses `customer` everywhere. Flag: "The code uses `Customer`, not `Client` — should we align?"
- **New concepts** — The user introduces a term not in the glossary. When its meaning becomes clear, offer to add it.

---

## Breaking Down Work + Workplan

When an idea is clear enough to act on, break it into a two-level hierarchy: **PRs** (for human review) and **commits/changes** (AI execution units). Then persist the plan to `openspec/workplan.yaml` so `/opsx-workflow:apply` can execute it without losing context.

> **Workplan is an advisory planning artifact, not authoritative state.** Git branches and GitHub PR status are the source of truth for progress. Workplan caches the last-known status and is reconciled by the health check on each skill invocation. If workplan says "pending" but GitHub says "merged", GitHub wins.

### PR level — optimized for the reviewer

Split by concern, risk, or reviewability. Each PR should be understandable in one review session (~300-500 lines diff).

Splitting criteria:
- **Different risk** — DB migration vs business logic vs API layer → separate PRs
- **Different concern** — infra setup vs domain logic vs integration wiring → separate PRs
- **Different reviewer** — backend vs frontend vs ops → separate PRs
- **Independent deployability** — if PR 1 can merge and ship without PR 2, split them

### Commit level — optimized for the AI

Each commit = one OpenSpec change. Within a PR, commits tell the story:
- Each commit passes build/test independently (no broken intermediate states)
- Reading the commit log top-down shows the logical progression
- Each commit's diff is self-explanatory without needing other commits for context

### Confirm then write workplan

Show the breakdown to the user, confirm with **AskUserQuestion**, then write `openspec/workplan.yaml`:

```yaml
created: 2026-05-26

features:
  - name: eval-service
    status: active           # active | complete
    prs:
      - name: eval-infra
        branch: feat/eval-infra
        status: pending      # pending | in-progress | merged
        depends-on: []
        description: "Schema and interface definitions — low risk, merge first"
        changes:
          - name: add-scorer-interface
            status: pending  # pending | in-progress | done | skipped | on-hold
            description: "Type definitions + pluggable scorer interface"
          - name: add-queue-schema
            status: pending
            description: "DB migration + BullMQ queue setup"

      - name: eval-core
        branch: feat/eval-core
        status: pending
        depends-on: [eval-infra]
        description: "Core implementation — main logic, careful review"
        changes:
          - name: implement-scorer-plugins
            status: pending
            description: "Pluggable scorer pattern implementation"
          - name: implement-bullmq-worker
            status: pending
            description: "Queue consumer and worker"

  - name: notification-refactor
    status: active
    prs:
      - name: notif-queue
        branch: feat/notif-queue
        status: pending
        depends-on: []
        description: "Replace polling with BullMQ event queue"
        changes:
          - name: setup-bullmq
            status: pending
            description: "Queue infrastructure and worker scaffold"
```

Workplan supports multiple features. Each feature groups PRs; each PR groups changes. Features and changes take `depends-on` too (a feature lists PR names, a change lists sibling changes in the same PR); see "Splitting a big card". `/opsx-workflow:apply` can target a feature (`/opsx-workflow:apply --auto eval-service`), a PR (`/opsx-workflow:apply eval-infra`), or individual changes.

This file is the **planning artifact** (not authoritative state) for:
- Which changes belong to which PR, which PRs belong to which feature
- Which branch each PR uses
- PR dependency order
- Last-known status (reconciled by health check against git/GitHub)

`/opsx-workflow:apply` reads this to know what to do. `/opsx-workflow:explore` writes and updates it.

## Milestones

A project's first big explore splits its milestones with the user, each one sentence of 做完時使用者能做到什麼, written to the workplan's top-level `milestones:` (`name` and `goal`; quote both, since the workplan parser splits a `goal` with a colon in it). Every feature you write gets `milestone:` pointing at one of them. `current_milestone` is set only by the user, when they change phase; never set or change it yourself. A project may have no milestones, and the skill names none of its own. Field shapes and how they decide a card's level: `references/priority.md`.

---

## Splitting a big card

Four layers, defined in `references/work-split.md`: a dispatch sends out work; a **session** (workplan `features[]`) is one pane working a group of similar main changes in order; a **main change** (`prs[]`) is one branch and one PR; a **sub-change** (`prs[].changes[]`) is one commit, done by a subagent.

When the D5 check in explore.md says split (at intake, or after exploring), write the split as one gate in `openspec/changes/<slug>/gates.md`:

```
## split
type: decision
status: open
問題: 照這個拆法建殼、寫 workplan？
已確認: <the D5 result: which of the three applied>
拆法:
  - session <feature> (milestone: <name or none>, depends-on: [<PR names>])
    - main change <pr> · <branch> (depends-on: [<pr>])
      - sub-change <name> (depends-on: [<sibling sub-change>])
選項: 照這個拆法 (Recommended) | 改拆法 | 不拆
建議: <why this grouping: similar topics share a session, different risks get their own main change>
風險: <what a wrong split costs>
預設: 不建殼，等回覆
```

A gate's `type` is `approval` (a permission) or `decision` (a choice) and nothing else; add a `needs: run` line when 建議 is a command the user must run themselves, and a `waits-on: <card name>` line on a `decision` that can only be answered after that card merges into main. The split gate above never takes `waits-on`: the coordinator never answers it. Until the gate is answered, create no shell and do not touch the workplan. Interactive mode asks the same thing with AskUserQuestion instead of the gate. Once confirmed, in this order:

1. Each main change: `openspec new change <pr> --schema opsx`, with an inbox.md that says what the whole main change does and lists its sub-changes.
2. Each sub-change: `openspec/changes/<main>/subs/<sub>/` with `inbox.md` (frontmatter `parent: <main>`, `depends-on: [<sibling>]`) and `.openspec.yaml` (`schema: opsx`, `kind:`, `parent: <main>`). The openspec CLI does not know about these; `opsx check <main>` does.
3. `openspec/workplan.yaml`: the features, PRs and changes with all three levels of `depends-on`. No dependency means no waiting.
4. The original card's inbox frontmatter gets `split_into: <main1>, <main2>`. Its stage becomes `split` and the flow stops there. Before writing `split_into`, turn each `## 併入：` section of the original card's inbox.md into its own card with `opsx split-out <original> <id>`: nobody works a split card again, so a merged item left on it is lost. Log the split (below), then run `opsx chain <original>`: it takes the first main change in `split_into` order that has no unmet dependency, switches this worktree to its branch, and records it in dispatch.json under this pane. Do not switch branches yourself. Whether it continued or printed `chain: …` with a reason it did not (skip, 沒有續接), then run `opsx chain --unclaimed <original>`. It prints one line per main change nobody will pick up on their own, `<main><TAB><unmerged dependencies, comma-separated>`: the coordinator only dispatches a card that has tasks.md, and a freshly split main change has only inbox.md. A main change that is merged, already has a live pane, or has tasks.md is not printed. For each printed line, write this gate in that main change's `openspec/changes/<main>/gates.md`; leave out the `waits-on:` line when the dependency column is empty, and when it is not, recommend waiting for those to merge instead of dispatching now. Write no gate when nothing is printed. Then report what chain did and stop. If it continued, the main change's first command arrives as the next prompt.

```
## dispatch-<main>
type: decision
status: open
waits-on: <the first unmerged dependency>
問題: 派 <main>？
已確認: <original> 已拆卡，<main> 只有 inbox.md，沒有 pane 在做
選項: 從看板派 <main> (Recommended) | 先不派
建議: 從看板派 <main>，它從 explore 接著做（有依賴沒合時：等 <dependencies> merged 再派）
風險: 不派的話這張主 change 沒人做
預設: 不派，等回覆
```

Every inbox.md you write here, and any card you open while exploring, gets the facts in its frontmatter (`kind_of_work`, plus `impact` and `evidence` for an incident); then run `opsx priority <slug>`, and if it prints P0 without a user override write the `p0-review` gate per `references/priority.md`.

Log the split in decisions.tsv with `opsx log`.

## Capturing Decisions

When a decision crystallizes:

**Glossary entries** — Offer when a term is resolved: "Should I add **Tenant** to the glossary?" If confirmed, update CONTEXT.md per `references/CONTEXT-FORMAT.md`.

**ADRs** — Offer only when all three conditions are true:
1. Hard to reverse — changing later would be expensive
2. Surprising without context — a future reader would wonder "why?"
3. Result of a real trade-off — there were genuine alternatives

Read `references/ADR-FORMAT.md` for the format. Most ADRs are a single paragraph.

---

## What You Might Do

**Investigate the codebase** — Read files, grep for patterns, map architecture. Ground discussions in what actually exists, not what you assume.

**Build comparison tables** — When weighing alternatives, a structured comparison (criteria × options) clarifies thinking faster than prose.

**Sketch diagrams** — Use ASCII art for system architecture, data flows, state machines, component relationships. Visual thinking often reveals structure that words miss.

**Surface risks** — What could go wrong? What assumptions are we making? What don't we know yet?

**Challenge assumptions** — Including the user's and your own. "You said this is simple, but I see 3 integration points and a migration. Is it really?"

---

## Two tools for questions you cannot answer by reading

- **Something only running it would settle** (timing, layout, real output, how a library behaves on this input): build a throwaway per `references/prototype.md` and record what you saw. Do not leave it in 待決 for the user to guess.
- **Something that needs digging through history or incidents**: `references/investigation.md`.

## Steps

When the change has a shell, go through these nine in order. Each condition is a judgment you make from the card, not a question for the user. A skill in the Read column is a `Read` of that path, not a Skill-tool call: the Skill tool refuses it (`../../references/harness-claude-code.md`). Put the step's output in the section named in the last column of the table, and record every step in explore.md's `## 步驟` (see "Ending: explore.md"). A step whose condition does not hold is not dropped; it is recorded as `skip：<which condition did not hold>`.

| # | step | do it when | Read | output goes to |
|---|---|---|---|---|
| 1 | 讀卡 | always | `inbox.md`, `attachments/` | none |
| 2 | how | the change spans 2 or more files, or you have not read that subsystem this session | `../how/SKILL.md` (simple path: one explainer; complex: 2 to 4 explorers plus one explainer, subagents are general-purpose) | 已知, a「怎麼運作」block |
| 3 | 影響範圍 | a symbol the change touches has other users (export, DB column, API, config, env) | `../blast-radius/SKILL.md` | 已知, a「影響範圍」block: the safe fact with its evidence level, risks, what was ruled out |
| 4 | why | the change alters structure or ownership, or deletes something that looks deliberate | `../why/SKILL.md` (git, code archaeology and incident postmortem investigators only) | 已知, a「為什麼現在這樣」block with Preserve / Change / Avoid / Risk |
| 5 | prototype | a question only running it settles, and a throwaway fits in an hour | `references/prototype.md` | 已知, with what you ran and what it showed |
| 6 | 查資料 | kind is dev or refactoring and the change adds an interface or a design | none; search for outside practice (similar tools, open-source projects, docs) | 已知, with source links |
| 7 | 對照 code | inbox.md says "the system does X" | none | 已知, the list of statements that disagree with the code |
| 8 | 待決 | always | none | 待決 |
| 9 | unslop | always | `../unslop/SKILL.md` and `references/investigation.md` for the output format | explore.md as a whole |

## Ending: explore.md

When the change has a shell (`openspec/changes/<slug>/`), end by writing `explore.md` in the schema's template:

- **已知**: facts from the code, each with a file path or the command you ran. Anything a prototype answered goes here with what was run and what it showed. Always include the **D5 check**, one line per criterion with your judgment: ① it spans more than one subsystem; ② it mixes different risk (data migration, permissions, external API next to ordinary logic); ③ one shell would hold more than 6 tasks. If any one holds, the card is split ("Splitting a big card"). Do not judge by estimated line count.
- **待決**: only questions the user must answer (product choice, preference, risk appetite). Each with 2–4 concrete options, the recommended one marked `(Recommended)`. A question `grep` or a ten-line script could answer does not belong here.
- **不做**: directions ruled out, with the reason.
- **步驟**: one line for each of the nine steps, shaped `- <n> <step name>：<where its output went>` when you did it, or `- <n> <step name>：skip：<which condition did not hold>` when you did not. Steps 2 to 7 name the 已知 block that holds their output, step 8 writes `待決`, and steps 1 and 9 have no block of their own and always run, so they write `done`. For example `- 1 讀卡：done`, `- 8 待決：待決`, `- 9 unslop：done`. A `skip：` with no reason counts as a missing line. `opsx check <slug>` reads this section, the Stop hook blocks the card in explore while a line is missing, and review compares a skipped 影響範圍 with the real diff.

Call `opsx status explore <n>/<total> "<label>"` as you go. Then continue per `../../references/continue.md`: invoke `/opsx-workflow:grill <slug>` when 待決 is non-empty, `/opsx-workflow:propose <slug>` when it is empty, in this turn.

No shell yet (the user is thinking out loud, not working a card)? Then the conversation might:

- Flow into work breakdown: "Here's 2 PRs with 5 changes — workplan written, run `/opsx-workflow:propose` to create them"
- Result in glossary/ADR updates: artifacts captured inline
- Just provide clarity: the thinking was the value
- Continue later

---

## Guardrails

- Never write application code — documentation and OpenSpec artifacts only
- Don't fake understanding — dig deeper when unclear
- Don't rush — this is thinking time, not task time
- Don't auto-capture — offer to save, don't just do it
- Don't force structure — let patterns emerge naturally
- Always update `openspec/workplan.yaml` when work breakdown or status changes
