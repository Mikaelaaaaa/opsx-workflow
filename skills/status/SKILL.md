---
name: status
description: |
  Read-only dashboard showing workplan progress, change status, and actionable suggestions.
  Use when the user says "status", "where am I", "what's left", "progress", "進度", or wants
  to understand the current state of their work before deciding what to do next.
argument-hint: "[feature name]"
---

# /status

Read-only dashboard. Shows the full workplan state, never modifies anything.

## Steps

### 1. Workplan Health Check (silent)

If `openspec/workplan.yaml` exists, silently verify it matches reality:

1. For each PR where status ≠ `merged`:
   - `gh pr list --head <branch> --json state --jq '.[0].state' 2>/dev/null` — is it merged on GitHub?
   - If merged on GitHub but workplan says `pending`/`in-progress` → auto-update to `merged`
2. For each change where status ≠ `done`:
   - Check if `openspec/changes/<name>/` still exists
   - If missing (archived or deleted) → auto-update to `done`

This is the **only** mutation `/status` makes — keeping the cache in sync with reality.

### 2. Load state

```bash
cat openspec/workplan.yaml 2>/dev/null
openspec list --json 2>/dev/null
```

**If no workplan and no changes exist:**
```
No workplan or active changes found.

→ /explore  to think through an idea and plan work
→ /propose  to create a change directly
```
STOP.

### 3. Display dashboard

**If `$ARGUMENTS` specifies a feature name**, show only that feature. Otherwise show all.

For each feature:

```
## Feature: eval-service (active)

├── PR: eval-infra [feat/eval-infra] — merged ✓
│   ├── add-scorer-interface — done ✓
│   └── add-queue-schema — done ✓
│
└── PR: eval-core [feat/eval-core] — in-progress
    ├── implement-scorer-plugins — done ✓ (3/3 tasks)
    ├── implement-bullmq-worker — in-progress (3/5 tasks)
    └── wire-langfuse-scoring — pending (blocked: depends on bullmq-worker)
```

For each in-progress change, read its tasks file and count `- [x]` vs `- [ ]`.

### 4. Suggestions

Based on the current state, suggest the most useful next action:

| State | Suggestion |
|-------|-----------|
| A change is in-progress with remaining tasks | `→ /apply <change-name>  (continue where you left off)` |
| All changes in a PR are done, PR not pushed | `→ /pr  (push and open PR for <pr-name>)` |
| A PR is merged, next PR has pending changes | `→ /apply <next-pr>  (start next PR)` |
| All features complete | `→ /archive  to archive completed changes` |
| Workplan health check found drift | `→ /sync  then check if reconciliation is needed` |
| No active work | `→ /explore  to plan something new` |

Show at most 2 suggestions — the most immediately useful ones.

## Guardrails

- Never modify code, artifacts, or workplan (except health check status sync)
- Never start implementing — just show state and suggest
- Keep output concise — the tree view is the core, not prose
- If workplan exists but openspec CLI is missing, still show workplan status (it's just YAML)
