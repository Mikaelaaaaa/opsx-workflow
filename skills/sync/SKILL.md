---
name: sync
description: |
  Analyze codebase structure and maintain two living documentation files: 
  docs/ARCHITECTURE.md (Mermaid diagrams + ASCII for humans) and CODEBASE.md 
  (structured context for AI agents). Detects changes since last sync and 
  regenerates only affected sections. Use this skill whenever the user asks to 
  sync docs, update architecture documentation, generate a codebase overview,
  refresh project docs, or says "sync". Also use when the user joins a new 
  project and wants to understand its structure, or after major refactoring 
  when docs are likely stale.
argument-hint: "[--full | --human-only | --ai-only | --diff]"
---

# /sync

Maintain two living documentation files from the actual codebase:

1. **`docs/ARCHITECTURE.md`** — For humans. Mermaid diagrams, ASCII component maps, key flows.
2. **`CODEBASE.md`** — For AI agents. Structured inventory of modules, patterns, entry points, conventions.

Both stay in sync with the code. Running `/sync` detects what changed and updates only the affected sections. Manual edits in `<!-- manual -->` blocks are preserved.

### Documentation Ownership

Four docs coexist in a project. Each has a distinct audience and scope — don't duplicate across them:

| Doc | Audience | Scope | Maintained by |
|-----|----------|-------|---------------|
| `CLAUDE.md` | AI | Behavioral rules: what to do, what not to do, commands, conventions | Human (manual) |
| `CODEBASE.md` | AI | Structural map: modules, exports, dependencies, entry points | `/sync` (auto) |
| `CONTEXT.md` | AI | Domain language: glossary, relationships, flagged ambiguities | `/explore` (proposed, human-confirmed) |
| `docs/ARCHITECTURE.md` | Human | Visual architecture: Mermaid diagrams, flow diagrams, tech stack | `/sync` (auto) |

`CLAUDE.md` is the king — it may include key structural info (e.g., a stacks table for an infra repo) when that info is also an operational instruction. Overlap with `CODEBASE.md` is fine; contradiction is not. When generating `CODEBASE.md`, check `CLAUDE.md` first and don't duplicate what's already there unless the structural detail goes deeper.

---

## Options

- `--full` — Full regeneration, ignore previous state
- `--human-only` — Only update `docs/ARCHITECTURE.md`
- `--ai-only` — Only update `CODEBASE.md`
- `--diff` — Show what would change without writing

---

## Step 1 — Scope

Check `.opsx/sync-meta.json` for previous sync state. Decide what to do:

| Condition | Action |
|---|---|
| `--full` flag or no sync-meta | Full analysis |
| Same git commit hash | "Docs are up to date" → STOP |
| Files changed since last sync | Incremental (re-analyze affected layers only) |

For incremental, get changed files:
```bash
git diff <lastCommitHash>..HEAD --name-only --diff-filter=ACDMR
```

## Step 2 — Scan

Enumerate project files and classify them. Two paths:

**If understand-anything plugin is installed** — use its scanner for speed:
```bash
node <understand-anything-plugin-path>/skills/understand/scan-project.mjs "$(pwd)" ".opsx/intermediate/scan-result.json"
```
Check for the plugin at `~/.claude/plugins/cache/understand-anything/understand-anything/*/skills/understand/scan-project.mjs`.

**Otherwise** — manual discovery:
```bash
git ls-files 2>/dev/null || find . -type f -not -path '*/.git/*' -not -path '*/node_modules/*' \
  -not -path '*/dist/*' -not -path '*/__pycache__/*' -not -path '*/venv/*' | head -500
```

Classify files by extension and directory. Don't read every file — scan enough to understand the shape of the project.

## Step 3 — Analyze

Read key files to understand the architecture. Adapt your analysis to the project type — don't force every project into API/Service/Repository layers.

**What to look for:**
- Entry points (where does execution start?)
- Package manifests (what are the dependencies?)
- Directory structure (what's the organizational principle?)
- Import relationships (what depends on what?)
- Configuration (how is the project configured?)
- Deployment artifacts (how is it deployed?)

**Dispatch subagents for large projects** — If the project has more than 50 source files, use the `structure-analyzer` agent to analyze files in batches. For smaller projects, analyze directly.

**Project type detection** — Let the structure tell you what kind of project this is:

| Signal | Likely type |
|---|---|
| `src/` + `package.json` with a framework | Web app |
| `packages/` or `apps/` + workspace config | Monorepo |
| `stacks/` + `compose.yaml` files | Infrastructure |
| `bin/` or CLI entry point | CLI tool |
| No entry point, just modules | Library |
| Mix of scripts with no clear structure | Scripts collection |

Adapt the documentation structure to what actually exists. An infrastructure repo needs deployment topology and stack descriptions, not class diagrams. A monorepo needs a package relationship map, not a single dependency graph.

## Step 4 — Generate

Read the templates at `references/architecture-template.md` and `references/codebase-template.md` for the expected structure, then generate both files.

**For `docs/ARCHITECTURE.md`:**
- Start with a system diagram (Mermaid `graph TD`)
- Add a component map (ASCII directory → role)
- Include key flows (sequence diagrams) for the 1-3 most important paths
- Add dependency graph, tech stack table, and conventions
- Scan existing file for `<!-- manual -->` blocks and preserve them

**For `CODEBASE.md`:**
- Project identity (name, type, languages, framework)
- Entry points table
- Module inventory (path, purpose, exports, dependencies per module)
- Build & run commands
- Key patterns, data flow, gotchas
- Don't duplicate content already in CLAUDE.md — check first

Create `docs/` directory if it doesn't exist.

## Step 5 — Save

Write `.opsx/sync-meta.json`:
```json
{
  "lastSyncAt": "<ISO 8601>",
  "gitCommitHash": "<HEAD>",
  "filesAnalyzed": 42,
  "version": "0.1.0"
}
```

Clean up: `rm -rf .opsx/intermediate`

Add `.opsx/intermediate/` to `.gitignore` if not already there. The output files (`docs/ARCHITECTURE.md`, `CODEBASE.md`, `.opsx/sync-meta.json`) should be committed.

Report: files analyzed, sections generated, warnings (circular deps, orphan modules), output paths.

## Step 6 — Workplan Health Check + Reconciliation

If `openspec/workplan.yaml` exists, verify it matches reality and reconcile after the sync.

### Health check (auto)

1. For each PR where status ≠ `merged`:
   - Find the forge from `git remote get-url gitlab` (else `origin`). A GitLab host: `glab mr list --source-branch <branch> --merged -F json`. `github.com`: `gh pr list --head <branch> --state merged --json number`. Any other host: skip this check and say so.
   - If the list is not empty (merged on the forge) but workplan says `pending`/`in-progress` → auto-update to `merged`
2. For each change where status ≠ `done`:
   - Check if `openspec/changes/<name>/` still exists
   - If missing (archived or deleted) → auto-update to `done`
3. If any statuses were updated, report: "Workplan updated: <PR> marked merged, <change> marked done"

### Reconciliation (when active changes exist)

If architecture changed significantly (new modules, removed modules, changed dependencies) and there are active changes in the workplan, reconcile the plan against reality.

Load the full state:

```bash
openspec list --json
```

For each active change:
```bash
openspec status --change "<name>" --json
```

Read `openspec/workplan.yaml`, the freshly-generated `docs/ARCHITECTURE.md` and `CODEBASE.md`, and any `CONTEXT.md`. Cross-reference against each active change's artifacts (proposal, design, tasks).

Look for:

- **Resolved dependencies** — A change was blocked on something that's now done. Update workplan status + remove dependency notes from tasks.
- **Invalidated tasks** — A task is no longer needed (another change handled it, or architecture shifted). Remove the task, update workplan.
- **Scope drift** — Design doc says X but code now does Y. Update design to match reality, or flag drift.
- **New work emerged** — Sync revealed a gap. Add new change to workplan, assign to appropriate PR.
- **Ordering changes** — A should go before B now, or they can be parallelized. Reorder in workplan.
- **Hold a change** — External blocker or architecture uncertainty. Set status to `on-hold` in workplan.

### Reconciliation output

Always show the summary table before making changes:

```
## Reconciliation

Docs changed: ARCHITECTURE.md (sync), CODEBASE.md (sync)

| Change | PR | Status | Action |
|--------|-----|--------|--------|
| add-scorer-interface | eval-infra | done | ✓ No changes |
| implement-bullmq-worker | eval-core | pending | UPDATE: task 2 already done, remove |
| wire-langfuse-scoring | eval-integration | pending | HOLD: API endpoint moved |
| (new) add-error-boundaries | eval-core | — | NEW: gap found in architecture |

Apply changes? [AskUserQuestion]
```

After user confirmation, update:
1. OpenSpec artifacts (tasks.md, proposal.md, design.md)
2. `openspec/workplan.yaml` (statuses, new changes, reordering)

If no significant architecture changes were detected, skip reconciliation and just report the health check results.

---

## Incremental Updates

When only some files changed:
1. Identify which architectural layers are affected by the changed files
2. Re-read and re-analyze only those sections
3. Regenerate only the affected parts of both docs
4. Preserve all `<!-- manual -->` blocks and unchanged sections
5. Update diagrams only if relationships changed
