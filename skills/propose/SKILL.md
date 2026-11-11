---
name: propose
description: |
  Propose a new change with all artifacts generated in one step. Use when the user wants to
  quickly describe what they want to build and get a complete proposal with design, specs,
  and tasks ready for implementation. Triggers on "propose", "new change", "plan a feature",
  "I want to build", or similar intent to start structured work.
argument-hint: "[change name or description]"
compatibility: Requires openspec CLI.
---

# /propose

**Steps in TodoWrite.** First action after loading: put this skill's steps into TodoWrite verbatim; a step you will not do stays in the list as `skip: <reason>`, never deleted.

Propose a new change — create the change and generate all artifacts in one step.

Creates a change with artifacts:
- proposal.md (what & why)
- design.md (how)
- tasks.md (implementation steps)

When the artifacts are done it continues straight into `/opsx-workflow:apply` (`../../references/continue.md`).

**Input**: The user's request should include a change name (kebab-case) OR a description of what they want to build.

## Steps

### 0. Workplan Health Check (silent)

If `openspec/workplan.yaml` exists, silently verify it matches reality before proceeding:

1. For each PR where status ≠ `merged`:
   - Find the forge from `git remote get-url gitlab` (else `origin`). A GitLab host: `glab mr list --source-branch <branch> --merged -F json`. `github.com`: `gh pr list --head <branch> --state merged --json number`. Any other host: skip this check and say so.
   - If the list is not empty (merged on the forge) but workplan says `pending`/`in-progress` → auto-update to `merged`
2. For each change where status ≠ `done`:
   - Check if `openspec/changes/<name>/` still exists
   - If missing (archived or deleted) → auto-update to `done`
3. Only report drift to the user if something needs a decision

### 1. If no clear input provided, ask what they want to build

Use the **AskUserQuestion tool** to ask what change they want to work on.

From their description, derive a kebab-case name (e.g., "add user authentication" → `add-user-auth`).

Do NOT proceed without understanding what the user wants to build.

### 2. Create the change directory (if it does not exist yet)

```bash
openspec new change "<name>" --schema opsx
```

Usually the shell already exists (收件 made it, explore and grill wrote into it). Then skip this and read what is there: `inbox.md`, `explore.md` (已知 / 待決 / 不做), `grill.md` (D1…Dn). If `explore.md` has a non-empty 待決 and no `grill.md`, stop: `/opsx-workflow:grill <name>` first; the router says the same. The exception is a card whose kind is chore or bug-fix (`../../references/continue.md`, "Light flow"): do not stop; write each open 待決 item as one 假設 sentence at the end of proposal.md's What Changes, and carry on. Confirm the kind in 2b first: if 2b changes it to anything else while 待決 is non-empty and there is no `grill.md`, stop and route to `/opsx-workflow:grill <name>`.

### 2b. Confirm the kind

`.openspec.yaml` has `kind:` (chosen at dispatch, one of dev / bug-fix / refactoring / perf / experiment / ops / chore). Read explore.md and inbox.md; if the kind is wrong for what the change actually is, change it and record it with `opsx log <name> <your agent name> 已決定 "kind 改 <new>：<reason>"`. The board shows the change. If `kind` is missing (shell made by hand), set it and say so. Apply loads its playbook from this value.

### 3. Get the artifact build order

```bash
openspec status --change "<name>" --json
```

Parse the JSON to get:
- `applyRequires`: array of artifact IDs needed before implementation (e.g., `["tasks"]`)
- `artifacts`: list of all artifacts with their status and dependencies

### 4. Create artifacts in sequence until apply-ready

Loop through artifacts in dependency order (artifacts with no pending dependencies first):

a. **For each artifact that is `ready` (dependencies satisfied)**:
   - Get instructions:
     ```bash
     openspec instructions <artifact-id> --change "<name>" --json
     ```
   - The instructions JSON includes:
     - `context`: Project background (constraints for you — do NOT include in output)
     - `rules`: Artifact-specific rules (constraints for you — do NOT include in output)
     - `template`: The structure to use for your output file
     - `instruction`: Schema-specific guidance for this artifact type
     - `outputPath`: Where to write the artifact
     - `dependencies`: Completed artifacts to read for context
   - Read any completed dependency files for context
   - Create the artifact file using `template` as the structure
   - Apply `context` and `rules` as constraints — but do NOT copy them into the file
   - Show brief progress: "Created <artifact-id>"; `opsx status propose <n>/<total> "<artifact-id>"`

   Rules specific to opsx:
   - **proposal.md uses the opsx template's sections, not the fork's instruction text.** The `instruction` JSON still lists the four stock sections; the template on disk adds `Acceptance`, `Testing Decisions`, `Out of Scope`, and all three are filled, never left as comments. Write it as a brief that survives the card sitting unpicked for weeks: interfaces, types and behavior, not file paths or line numbers; what the system should do, not which function to edit. `Acceptance` lines are each independently runnable (command + expected output, or a spec Scenario name) and are what tasks.md's `驗收：` lines point at. `Out of Scope` carries explore.md's 不做 plus anything excluded in this round, so the agent that picks the card up does not gold-plate the neighbors.
   - **design.md Decisions = grill.md's D-ids, verbatim and in order.** Copy `D1 … Dn` with their 理由 / 否決 lines; never renumber, never merge two Ds, never add a D the user did not decide (an implementation choice you make goes in the prose, not as a D). Review checks each D by id.
   - **tasks.md: every task carries two sub-lines**, in the template's shape:
     ```
     - [ ] 1.1 <task>
       - 驗收：<specs/<capability>/spec.md 的 Requirement / Scenario 名>
       - 測試：<the test file apply writes first, e.g. packages/db/src/kb-export.test.ts>
     ```
     A task with no verifiable behavior (moving files, pure config, docs) writes `測試：無 · <reason>`, and you must be able to say why. Apply writes that test before the code and review refuses a task whose test is missing, so a vague 驗收 here becomes a blocked review later. When the Scenario a task's 驗收 names has an Examples table, its 測試 covers every row of that table (the instruction's 與 tasks 的關係 says the same), because review checks the table row by row and a row with no test is a finding.
   - **Specs follow the Gherkin rules in the specs instruction.** Write each spec.md from the `instruction` that `openspec instructions specs --change <name> --json` returns, and open `references/gherkin.md` when you want a worked example; this line does not repeat either of them. The rules exist for the people who check the work later. Every Requirement gets a positive and a negative Scenario, so the spec says what must not happen as well as what must. Boundary values go into an Examples table rather than into prose, so review can match each row to a test instead of trusting that "the edges" were covered. Scenario names are still what 驗收 points at.
   - **Merged items in inbox.md.** Each `## 併入：<time> <source>` section in inbox.md is a problem another agent's card was merged into this one. Before writing tasks.md, every such section either becomes a task (name its `- id:` in the task line) or is split out with `opsx split-out <name> <id>` when it does not belong in this change. One left in place with no task is lost once the card archives.
   - **Cut tasks as tracer bullets, not layers.** Each task is a thin vertical slice through every layer it touches (schema, API, UI, test), demoable or verifiable on its own, in the order a user would hit it. "All the schema, then all the API, then all the UI" is the shape that leaves nothing testable until the end and nothing shippable if the card stops halfway. Mark a task that needs a human decision mid-way (design review, product call) as such so apply writes a gate instead of guessing; prefer tasks that do not.
   - proposal.md and design.md go through `../technical-writing/SKILL.md` then `../unslop/SKILL.md` before you move on.

b. **Continue until all `applyRequires` artifacts are complete**
   - After creating each artifact, re-run `openspec status --change "<name>" --json`
   - Check if every artifact ID in `applyRequires` has `status: "done"` in the artifacts array
   - Stop when all `applyRequires` artifacts are done

c. **If an artifact requires user input** (unclear context):
   - Use **AskUserQuestion tool** to clarify
   - Then continue with creation

d. **In autopilot** (the router line carries `autopilot：`), never use AskUserQuestion. Unclear context that is a product choice, or a decision that is hard to undo, becomes a gate in `gates.md` in grill's format (`../grill/SKILL.md`, "In autopilot"), and you stop there. Anything else, make the call, say it in design.md's prose (not as a D), and log it in decisions.tsv. A change missing from the workplan gets its own feature and PR named after the slug, instead of a question about which PR group it belongs to.

### 4c. Sub-change shells

When `openspec/changes/<name>/subs/` exists, `<name>` is a main change (`../../references/work-split.md`). The openspec CLI sees only the main shell, so:

- The main shell's tasks.md has one item per sub-change, in workplan `depends-on` order. Each item's `驗收：` points at that sub-change's spec and its `測試：` at the test files the sub-change's tasks name. Checking it off means that sub-change is committed on the PR branch.
- Each `subs/<sub>/` gets proposal.md, specs/<capability>/spec.md, design.md and tasks.md from the same templates and rules as above. Its design.md cites the main shell's D-ids rather than inventing new ones; its tasks are cut against the D5 limit (more than 6 means the split was wrong, say so).
- The main shell's specs/ holds the union of the sub-change specs, because archive merges only the main shell's specs. A sub spec that changes is copied to the main shell.
- Last, run `opsx check <name>`. Any line it prints is a missing piece: fix it and run again. While it fails, do not continue to `/opsx-workflow:apply`.

Run `opsx check <name>` for every change, not only a main change with `subs/`: it also checks the card's fact fields (`kind_of_work`, and `impact` plus `evidence` for an incident) when an agent opened the card, and for every card this one opened.

### 5. Update workplan

If `openspec/workplan.yaml` exists, check whether this change is already listed:
- **Listed** → verify status is `pending`, no action needed
- **Not listed** → ask which PR group it belongs to (show existing PR groups from workplan), then add it. PR name must match `[a-z][a-z0-9_-]{0,31}` (it becomes the herdr agent name); branch `{feat|fix|chore|refactor|docs|sec}/<slug>/mikaela`; `depends-on` from design.md.

If no workplan exists, create it with this one feature / PR / change; the commit gate turns on once the file exists.

### 5b. Several independent changes from one discussion

When this proposal produced more than one change and they do not depend on each other, give them separate PRs whose `depends-on` names only what they really need. `opsx chain` uses exactly that field: children that depend on the same merged parent are fanned out to subagents by the parent's pane (`../../references/fan-out.md`); a chain of `depends-on` is worked one after the other in one pane.

### 6. Show final status

```bash
openspec status --change "<name>"
```

## Output

After completing all artifacts, summarize:
- Change name and location
- PR group (from workplan, if exists)
- List of artifacts created with brief descriptions
- What's ready: "All artifacts created! Ready for implementation."

Then continue to `/opsx-workflow:apply <name>` per `../../references/continue.md`: invoke it now unless a gate is open or `opsx check <name>` still prints lines. Apply switches to the PR's branch itself.

## Artifact Creation Guidelines

- Follow the `instruction` field from `openspec instructions` for each artifact type
- The schema defines what each artifact should contain — follow it
- Read dependency artifacts for context before creating new ones
- Use `template` as the structure for your output file — fill in its sections
- `context` and `rules` are constraints for YOU, not content for the file. Do NOT copy `<context>`, `<rules>`, `<project_context>` blocks into the artifact.

## Guardrails

- Create ALL artifacts needed for implementation (as defined by schema's `apply.requires`)
- Always read dependency artifacts before creating a new one
- If context is critically unclear, ask the user — but prefer making reasonable decisions to keep momentum
- If a change with that name already exists, ask if user wants to continue it or create a new one
- Verify each artifact file exists after writing before proceeding to next
