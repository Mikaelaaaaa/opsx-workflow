---
name: archive
description: |
  Archive a completed change after implementation is done. Use when the user wants to
  finalize, close, or archive a change. Triggers on "archive", "close change", "done with
  this change", "finalize", or similar completion intent.
argument-hint: "[change name]"
compatibility: Requires openspec CLI.
---

# /archive

Archive a completed change.

**Input**: Optionally specify a change name. If omitted, check if it can be inferred from conversation context. If vague or ambiguous you MUST prompt for available changes.

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

### 1. If no change name provided, prompt for selection

Run `openspec list --json` to get available changes. Use the **AskUserQuestion tool** to let the user select.

Show only active changes (not already archived). Include the schema used for each change if available.

Do NOT guess or auto-select a change. Always let the user choose.

### 2. Check artifact completion status

```bash
openspec status --change "<name>" --json
```

Parse the JSON to understand:
- `schemaName`: The workflow being used
- `artifacts`: List of artifacts with their status (`done` or other)

**If any artifacts are not `done`:**
- Display warning listing incomplete artifacts
- Use **AskUserQuestion tool** to confirm user wants to proceed
- Proceed if user confirms

### 3. Check task completion status

Read the tasks file (typically `tasks.md`) to check for incomplete tasks.

Count tasks marked with `- [ ]` (incomplete) vs `- [x]` (complete).

**If incomplete tasks found:**
- Display warning showing count of incomplete tasks
- Use **AskUserQuestion tool** to confirm user wants to proceed
- Proceed if user confirms

**If no tasks file exists:** this is a card being closed without being built (declined at explore or grill, or a duplicate). Before moving it, make sure `explore.md`'s 不做 section says **why** in a paragraph a stranger can follow in six months (what it would take, why that does not fit, what a requester should do instead), and add `outcome: declined` to `.openspec.yaml`. A declined card with no reason is re-litigated the next time someone pastes the same request; the archive is the memory that stops that, and 收件 greps it.

### 4. Assess delta spec sync state

Check for delta specs at `openspec/changes/<name>/specs/`. If none exist, proceed without sync prompt.

**If delta specs exist:**
- Compare each delta spec with its corresponding main spec at `openspec/specs/<capability>/spec.md`
- Determine what changes would be applied (adds, modifications, removals, renames)
- Show a combined summary before prompting

**Prompt options:**
- If changes needed: "Sync now (recommended)", "Archive without syncing"
- If already synced: "Archive now", "Sync anyway", "Cancel"

### 4b. Check the branch for commits pushed after the merge

Run `opsx late <name>`. Exit 0 (`none` or `acked <sha>`): continue. Exit 1 (`late <N> <sha> <branch>` and one line per commit): those commits are on the remote branch but not in main, since the PR merged without them. Show the output and stop: do not archive, do not touch the workplan. Exit 2: it could not tell (the message names the missing field); show it and stop. A card with no MR yet has nothing merged, so skip this step.

### 5. Perform the archive

Create the archive directory if it doesn't exist:
```bash
mkdir -p openspec/changes/archive
```

Generate target name using current date: `YYYY-MM-DD-<change-name>`

**Check if target already exists:**
- If yes: Fail with error, suggest renaming existing archive or using different date
- If no: Move the change directory to archive

```bash
mv openspec/changes/<name> openspec/changes/archive/YYYY-MM-DD-<name>
```

### 6. Update workplan

If `openspec/workplan.yaml` exists:
- Set this change's status to `done`
- If all changes in this PR group are `done`, set the PR status to `merged`
- If all PRs in the workplan are `merged`, set the feature status to `complete`

### 6b. Continue the chain

Run `opsx chain <change-name>`. It decides from the workplan and `dispatch.json` whether this pane goes on to a child card, and it exits 0 with one line of reason when there is none (no workplan, the card was not dispatched, no child is ready). Report that line and stop. A non-zero exit means the workplan is wrong for a ready child (for example its PR has no `branch:`); report the message, which names the PR, and stop without retrying.

- One child: `opsx chain` switches this worktree to the child's branch and the child's first command arrives as the next prompt. Do nothing more in this turn.
- Several children (`chain: fan out …` lines): this pane becomes their coordinator. Follow `../../references/fan-out.md`: spawn one worktree-isolated subagent per line, then relay.

### 7. Display summary

Show archive completion summary including:
- Change name
- Schema that was used
- Archive location
- Whether specs were synced (if applicable)
- Workplan status (if applicable)
- Note about any warnings (incomplete artifacts/tasks)

## Output On Success

```
## Archive Complete

**Change:** <change-name>
**Schema:** <schema-name>
**Archived to:** openspec/changes/archive/YYYY-MM-DD-<name>/
**Specs:** ✓ Synced to main specs (or "No delta specs" or "Sync skipped")

All artifacts complete. All tasks complete.
```

## Guardrails

- Always prompt for change selection if not provided
- Use artifact graph (openspec status --json) for completion checking
- Don't block archive on warnings — just inform and confirm
- Preserve .openspec.yaml when moving to archive (it moves with the directory)
- Show clear summary of what happened
- If delta specs exist, always run the sync assessment and show the combined summary before prompting
- Always update `openspec/workplan.yaml` after archiving
