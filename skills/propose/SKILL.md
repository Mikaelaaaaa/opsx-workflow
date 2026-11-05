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

Propose a new change — create the change and generate all artifacts in one step.

Creates a change with artifacts:
- proposal.md (what & why)
- design.md (how)
- tasks.md (implementation steps)

When ready to implement, run `/opsx:apply`.

**Input**: The user's request should include a change name (kebab-case) OR a description of what they want to build.

## Steps

### 0. Workplan Health Check (silent)

If `openspec/workplan.yaml` exists, silently verify it matches reality before proceeding:

1. For each PR where status ≠ `merged`:
   - `gh pr list --head <branch> --json state --jq '.[0].state' 2>/dev/null` — is it merged on GitHub?
   - If merged on GitHub but workplan says `pending`/`in-progress` → auto-update to `merged`
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

Usually the shell already exists (收件 made it, explore and grill wrote into it). Then skip this and read what is there: `inbox.md`, `explore.md` (已知 / 待決 / 不做), `grill.md` (D1…Dn). If `explore.md` has a non-empty 待決 and no `grill.md`, stop: `/grill <name>` first; the router says the same.

### 2b. Confirm the kind

`.openspec.yaml` has `kind:` (chosen at dispatch, one of dev / bug-fix / refactoring / perf / experiment / ops / chore). Read explore.md and inbox.md; if the kind is wrong for what the change actually is, change it and add one line to `decisions.tsv`: `kind 改 <new>：<reason>`. The board shows the change. If `kind` is missing (shell made by hand), set it and say so. Apply loads its playbook from this value.

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
     A task with no verifiable behavior (moving files, pure config, docs) writes `測試：無 · <reason>`, and you must be able to say why. Apply writes that test before the code and review refuses a task whose test is missing, so a vague 驗收 here becomes a blocked review later.
   - Specs stay testable: one `#### Scenario:` per behavior, WHEN / THEN; those scenario names are what 驗收 points at.
   - **Cut tasks as tracer bullets, not layers.** Each task is a thin vertical slice through every layer it touches (schema, API, UI, test), demoable or verifiable on its own, in the order a user would hit it. "All the schema, then all the API, then all the UI" is the shape that leaves nothing testable until the end and nothing shippable if the card stops halfway. Mark a task that needs a human decision mid-way (design review, product call) as such so apply writes a gate instead of guessing; prefer tasks that do not.
   - proposal.md and design.md go through `../technical-writing/SKILL.md` then `../unslop/SKILL.md` before you move on.

b. **Continue until all `applyRequires` artifacts are complete**
   - After creating each artifact, re-run `openspec status --change "<name>" --json`
   - Check if every artifact ID in `applyRequires` has `status: "done"` in the artifacts array
   - Stop when all `applyRequires` artifacts are done

c. **If an artifact requires user input** (unclear context):
   - Use **AskUserQuestion tool** to clarify
   - Then continue with creation

### 5. Update workplan

If `openspec/workplan.yaml` exists, check whether this change is already listed:
- **Listed** → verify status is `pending`, no action needed
- **Not listed** → ask which PR group it belongs to (show existing PR groups from workplan), then add it. PR name must match `[a-z][a-z0-9_-]{0,31}` (it becomes the herdr agent name); branch `{feat|fix|chore|refactor|docs|sec}/<slug>/mikaela`; `depends-on` from design.md.

If no workplan exists, create it with this one feature / PR / change; the commit gate turns on once the file exists.

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
- Prompt: "Run `/opsx:apply` to start working on the tasks."

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
