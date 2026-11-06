# opsx-workflow

Unified development workflow plugin for Claude Code. Covers the full cycle: think → build → review → ship.

## 安裝（Claude Code 2.1.275+）

```
/plugin install opsx-workflow --marketplace Mikaelaaaaa/opsx-workflow
```

或本機路徑：`claude plugin marketplace add ~/code/sandbox/opsx-workflow && claude plugin install opsx-workflow@opsx-workflow`。
需要 Python 3.11 以上（macOS 內建的 3.9 不夠，pyenv 或 brew 裝一個）。裝完跑一次 `bash <plugin root>/bin/opsx init --global`（裝 `~/.local/bin/opsx`、建 `~/.local/state/opsx/`、掛 herdr 看板 plugin），
再到每個要用的 repo 根目錄跑 `opsx init`。

## 看板

資料全是投影（`opsx collect`：`openspec/changes/*/`、`~/.local/state/opsx/`、`herdr agent list`、`glab mr view`），看板自己不存狀態。

- 網頁：herdr 裡叫 action `open-board`（`opsx init --global` 已 `herdr plugin link`），或 `bash herdr-board/scripts/open-board.sh`。
  首頁四段 待處理 / 進行中 / 待指派 / 已完成；按鈕背後是 `opsx answer`（回 gate、三種授權答案）、`opsx dispatch`、`opsx merge`（寫一次性核准，叫 agent `/babysit merge`，閘門只放行那一次）、`opsx stop`。
- 右側 pane：herdr 裡叫 action `open-pane`（overlay 開 pane `board`，`python3 herdr-board/tui.py`），同一份清單，↑↓ 選、Enter 跳 pane、q 關；不回 gate、不派工。
- 快捷鍵：herdr 的鍵綁 action，在 `~/.config/herdr/config.toml` 加兩段（prefix 是你 herdr 的前綴鍵）：
  ```toml
  [[keys.command]]
  key = "prefix+o"
  type = "plugin_action"
  command = "opsx-board.open-board"

  [[keys.command]]
  key = "prefix+shift+o"
  type = "plugin_action"
  command = "opsx-board.open-pane"
  ```
- 對原型看畫面：`python3 herdr-board/server.py --collect herdr-board/tests/fixtures/collect-sample.json`，開 `http://127.0.0.1:8791/#token=$(cat ~/.local/state/opsx/board-token)`。
- 收件匣 tab、同步腳本、紀錄 tab 在 `board-inbox`、`board-log` 兩張卡（`openspec/workplan.yaml`）。

## Skills

| Skill | Description |
|-------|-------------|
| `/explore` | Thinking partner + domain-aware grilling. Challenges plans against CONTEXT.md, sharpens terminology, captures decisions in ADRs, breaks work into multi-feature workplans. |
| `/sync` | Analyze codebase → maintain `docs/ARCHITECTURE.md` (Mermaid diagrams for humans) and `CODEBASE.md` (structured context for AI). Reconciles workplan against reality when architecture changes. |
| `/status` | Read-only dashboard showing workplan progress across all features, changes, and tasks. Suggests next action. |
| `/propose` | Propose a new OpenSpec change — creates proposal, design, and tasks artifacts in one step. |
| `/apply` | Implement tasks from an OpenSpec change. **Interactive** (default): step-by-step with pauses. **Autopilot** (`--auto`): autonomous implement → self-check → test → commit → dual-pass review → auto-fix → PR. |
| `/archive` | Archive a completed change. Checks artifact/task completion, syncs delta specs. |
| `/pr` | Create a well-formatted pull request with conventional commit title and structured body. |
| `/review` | Dual-pass spec-driven code review. Spawns two parallel agents — spec conformance + code quality — and merges findings into a graded report (Bug / Must-fix / Suggestion). |

## Agents

| Agent | Model | Purpose |
|-------|-------|---------|
| `structure-analyzer` | Sonnet | Extract architectural structure from source files |
| `doc-renderer` | Sonnet | Generate Mermaid/ASCII documentation from analysis data |

## Hooks

| Hook | Event | What it does |
|------|-------|-------------|
| `security-guard.sh` | PreToolUse (Bash) | Blocks push to main, force push, .env staging, AI attribution, credential leaks (14 patterns) |
| `secret-mask.sh` | PostToolUse (Bash) | Warns if Bash output contains exposed secrets (11 patterns) |
| `conventional-commit.sh` | PostToolUse (Bash) | Warns if commit message doesn't follow `feat:\|fix:\|chore:` format |

## Workflow

```
                ┌──────────────────────────────────────────┐
                │           Development Workflow            │
                └──────────────────────────────────────────┘

  ┌─────────┐     ┌──────────┐     ┌─────────────────────────────┐     ┌─────────┐
  │ /explore │────▶│ /propose │────▶│          /apply             │────▶│  /pr    │
  │         │     │          │     │                             │     │         │
  │ Think   │     │ Plan     │     │ Build ─▶ Self-check ─▶ Test │     │ Ship    │
  │ Grill   │     │ Design   │     │   │                         │     │ Merge   │
  │ Decide  │     │ Tasks    │     │   ▼                         │     │         │
  └────┬────┘     └──────────┘     │ Dual-pass /review           │     └────┬────┘
       │                           │ ├─ Spec conformance agent   │          │
       ▼                           │ └─ Code quality agent       │          ▼
  ┌─────────┐   ┌──────────┐      │   │                         │    ┌──────────┐
  │CONTEXT  │   │ /status  │      │   ▼                         │    │ /archive │
  │.md +    │   │          │      │ Auto-fix (inline) ─▶ Commit │    │          │
  │ADRs     │   │ Dashboard│      └─────────────────────────────┘    │ Finalize │
  └─────────┘   └──────────┘                                        └──────────┘

  ┌──────────┐
  │ /sync    │  ◄── Run after major changes to update ARCHITECTURE.md + CODEBASE.md
  └──────────┘
```

### Typical Flow

1. **Explore** — `/explore` to think through an idea, challenge it, sharpen the domain language
2. **Propose** — `/propose` to create an OpenSpec change with proposal, design, and tasks
3. **Apply** — `/apply` to implement tasks from the change (interactive or autopilot)
4. **Sync** — `/sync` to update architecture docs after changes
5. **Review** — `/review` to verify implementation against spec + code quality (built into autopilot, or standalone)
6. **PR** — `/pr` to create a well-formatted pull request
7. **Archive** — `/archive` to finalize and archive the completed change

### Autopilot Flow (`/apply --auto --pr`)

In full autopilot mode, `/apply` handles the entire cycle automatically:

```
implement task → self-check (4 greps) → next task → ... → test → commit
                                                                    ↓
                                            spawn 2 review agents (parallel)
                                            ├── Agent A: spec conformance
                                            └── Agent B: code quality + sibling files
                                                                    ↓
                                            merge + validate evidence → inline fix → test → commit → PR
```

**Self-check** (after each task): 4 concrete grep-based checks — unused imports, pattern divergence from sibling files, dead dependencies, copy-paste duplication. Issues are fixed inline immediately.

**Dual-pass review** (after all tasks committed): Two parallel agents independently review the work — one checks spec conformance (design decisions, goals, tasks), the other checks pure code quality (bugs, dead code, cross-file consistency). Findings require evidence:
- **Bug**: must describe a concrete failure scenario
- **Must-fix**: must cite a specific spec decision (D1, D2...) or convention rule
- No evidence → auto-downgrade to Suggestion → no auto-fix

**Auto-fix**: Only Bug and Must-fix findings with validated evidence are fixed. Fixes are scoped to the exact file:line identified. One fix cycle max — prevents infinite loops.

### When to use `/sync`

- After merging a major feature (keeps docs current + reconciles workplan)
- When onboarding someone new (generates a structural overview)
- Before starting a big refactor (understand the current shape)
- When docs feel stale or outdated

## Install

見上面「安裝」。改了 plugin 檔案後要重開 Claude Code 才載得到新的 skill / hook；`claude plugin update opsx-workflow` 同步 marketplace 來源。

## Structure

```
opsx-workflow/
├── .claude-plugin/plugin.json
├── skills/
│   ├── explore/                  # Think + grill + capture
│   │   ├── SKILL.md
│   │   └── references/
│   │       ├── CONTEXT-FORMAT.md
│   │       └── ADR-FORMAT.md
│   ├── sync/                     # Architecture doc sync
│   │   ├── SKILL.md
│   │   └── references/
│   │       ├── architecture-template.md
│   │       └── codebase-template.md
│   ├── status/SKILL.md            # Read-only workplan dashboard
│   ├── propose/SKILL.md          # Propose OpenSpec change
│   ├── apply/SKILL.md            # Implement change tasks
│   ├── archive/SKILL.md          # Archive completed change
│   ├── pr/SKILL.md               # Create pull request
│   └── review/SKILL.md           # Code review
├── agents/
│   ├── structure-analyzer.md
│   └── doc-renderer.md
├── hooks/
│   ├── hooks.json
│   ├── security-guard.sh         # PreToolUse: block dangerous ops + credential scan
│   ├── secret-mask.sh            # PostToolUse: warn on secret exposure
│   └── conventional-commit.sh    # PostToolUse: conventional commit format check
├── evals/evals.json
└── README.md
```

## Dependencies

- **gh** CLI (for `/pr` and `/review`)
- **understand-anything** plugin (optional — `/sync` uses it for faster scanning if available)
