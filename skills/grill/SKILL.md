---
name: grill
description: |
  Answer the open decisions a change still has before it gets proposed. Reads the 待決 section of
  openspec/changes/<slug>/explore.md, sorts each item into "answerable from the code", "answerable by
  running something once", or "only the user can answer", resolves the first two itself, asks the
  third one question at a time with 2–4 concrete options, and writes the result to grill.md as
  numbered decisions (D1, D2…) plus what is still unknown. Use this whenever a change has an
  explore.md with a non-empty 待決 section, when the user says "grill", "grill me", "幫我釘決定",
  "待決", "還有什麼沒定", or asks you to pressure-test a plan before proposing it. Also the stage the
  opsx router injects between explore and propose. If 待決 is empty there is nothing to do — say so and stop.
argument-hint: "[change slug]"
---

# /grill

The change has questions that explore could not close. Close them, cheaply, in the right order, and leave a record propose can build on without renumbering.

## Where you are

`openspec/changes/<slug>/explore.md` exists and its `## 待決` section lists the open items. Read it first. If the section is empty or missing, reply「<slug> 沒有待決，直接 /propose」and stop. Grill is a gate on the way from explore to propose, not a place to re-explore.

If the card's `.openspec.yaml` says the kind is chore or bug-fix, grill does not run for it (`../../references/continue.md`, "Light flow"): reply「<slug> 是 chore / bug-fix，不經 grill，直接 /propose」and stop. Propose turns the open items into assumptions.

Load the project's language before asking anything: `CONTEXT.md` (or `CONTEXT-MAP.md` and the context it points at), `docs/adr/`, `openspec/workplan.yaml`. The user will use words from their own head; you need to know when those words collide with what the project already calls things.

## Classify before you ask

Every 待決 item goes into exactly one bucket. Only the third bucket reaches the user. The point is that the user's attention is the scarce resource in this flow; spending it on something `grep` or a ten-line script could answer is the failure mode this skill exists to prevent.

1. **The code answers it.** Current behavior, what calls what, which table holds it, whether a helper already exists. Go look. Write the answer into explore.md's `## 已知` with the file path, and remove the item from 待決.
2. **Running it once answers it.** Timing, layout, actual output, how a library behaves on this input, whether approach A or B is faster. Build the smallest throwaway that observes the thing, in a scratch directory outside the source tree, following `skills/explore/references/prototype.md`. The observation is the answer. Record it in 已知 with what you ran and what you saw, and remove the item from 待決. Do not ask the user to guess something you can measure.
3. **Only the user can answer it.** Product choice, preference, risk appetite, priority between two valid designs, anything that depends on what they want rather than what is true. These are the questions you ask.

If you are unsure which bucket an item belongs to, try bucket 1 for a few minutes before defaulting to bucket 3.

## How to ask

- Use the **AskUserQuestion** tool for every question. Never ask in plain prose. The popup is what lets the user answer in one click or type their own.
- **One question at a time.** Wait for the answer before the next. Each answer can change what the next question should be; a batch of questions throws that away.
- **2–4 concrete options**, each a real alternative with its consequence in a few words. Yes / No is almost never the right pair; the user can always pick "Other". Put your recommended option first and mark it `(Recommended)`, with one line on why.
- **No shorthand tokens for answering.** Do not ask the user to reply "A" or "1". They answer in their own words or by picking the option.
- **Order the questions by dependency.** If question 3's options change depending on question 1's answer, ask 1 first. Walk the decision tree one branch at a time rather than jumping around.
- After an answer, acknowledge it in one sentence, then ask the next question. No summaries mid-stream.

## In autopilot

When the router line carries `autopilot：`, nobody is watching the pane. AskUserQuestion there makes herdr mark the agent blocked, and the drive loop cannot send the next command. So in autopilot you never call it. Buckets 1 and 2 work the same as always. Each bucket-3 item goes one of two ways:

- **It is a product choice, or the decision is hard to undo** (a data shape that gets migrated, a public interface, anything the user would have to unpick after merge). Write it as a gate in `gates.md` and leave the item in explore.md's 待決:
  ```
  ## <short-id>
  type: decision
  status: open
  問題: <the question, one line>
  已確認: <what is already settled on this point>
  選項: <option> (Recommended) | <option> | <option>
  建議: <why the recommended one>
  證據: <files, what you ran>
  風險: <what goes wrong with the recommendation>
  預設: <what happens if nobody answers>
  ```
  The options follow the same rules as an AskUserQuestion: 2–4 real alternatives, recommended first. `type` is `approval` (a permission) or `decision` (a choice) and nothing else; when 建議 is a command the user must run themselves, add a `needs: run` line.
- **Anything else.** Take the option you would have marked Recommended. Write it as a D like any other, add a `  - 自動採用：autopilot，沒問使用者` line under it, and log one line in decisions.tsv. The user can overturn it at review or on the MR.

If you wrote any gate, still write grill.md with the Ds you have, say which items wait on which gate, and stop. The answer comes back as a prompt. Turn it into its D, remove the item from 待決, and carry on. Once 待決 is empty, propose comes next as usual.

## Challenge the language as you go

When the user uses a word that `CONTEXT.md` or the code uses differently, say so right there:「你說的 cancellation 是整張 Order 取消，還是 CONTEXT.md 寫的部分取消？」When a term is vague ("account", "user"), ask which concrete concept they mean before building a decision on it. When the user states how something works and the code disagrees, show the file and ask which one is right. A decision written on a fuzzy word turns into a bug in apply.

If a term gets resolved, update `CONTEXT.md` inline using `references/CONTEXT-FORMAT.md`. Create the file only when there is something to write.

## Output

When every 待決 item is either resolved into 已知 or answered, write `openspec/changes/<slug>/grill.md`:

```markdown
## 決策
- D1 <one-sentence decision>
  - 理由：<why this, in the user's terms>
  - 否決：<the alternative> 因為 <reason>
- D2 …

## 未決
- <something only running the real thing will show> · 驗證：<how it will be checked, and in which step of apply>
```

Rules that keep this file useful downstream:

- **D-ids are permanent.** Propose copies D1…Dn into design.md's Decisions section as-is, and review checks each D against the code by id. Never renumber, never reuse a number for a different decision.
- **A D is something the user chose.** It comes from an answer to a question you asked, or from a 已知 fact the user confirmed when it changed the picture. Parameters that merely follow from a D (which helper to reuse, the retry count that falls out of a stated time limit) are not new Ds; they go into that D's 理由 line or are left for apply to work out. A grill.md full of Ds the user never saw is a design doc wearing a disguise.
- **One decision per D.** If an answer settles two things, write two Ds.
- **Questions that surface mid-grill are asked the same way.** If answering one item reveals another real choice (a scope the user's words left open, a term that collides with CONTEXT.md), ask it, one at a time. If you cannot get an answer in this run, it goes back into explore.md's 待決 with the options you would offer, so the next /grill picks it up. It does not become a note at the bottom of grill.md, and it does not become a D by default.
- **未決 is not a parking lot.** Only things that genuinely need a run to settle, each with its verification plan. If you can settle it now with bucket 1 or 2, do that instead.
- **Write an ADR too** when a decision meets all three of: hard to reverse, surprising without context, the result of a real trade-off. Use `references/ADR-FORMAT.md`; most decisions will not qualify, and that is fine.

Then tell the user in a few lines what got decided and what is still open. If 待決 is now fully answered, continue to `/opsx-workflow:propose <slug>` per `../../references/continue.md` in this turn; if anything went back into 待決, stop there. Call `opsx status grill <n>/<total> <label>` as you move through the items so the board shows progress.

## What this skill does not do

- It does not write code, proposals, specs, or tasks. Propose does that, from grill.md.
- It does not reopen things explore already put in 已知 or 不做, unless the user brings new information.
- It does not ask about implementation detail that apply can decide on its own (naming, file layout, which helper to use).
