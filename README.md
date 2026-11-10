# opsx-workflow

Unified development workflow plugin for Claude Code. Covers the full cycle: think → build → review → ship.

## 安裝（Claude Code 2.1.275+）

```
/plugin install opsx-workflow --marketplace Mikaelaaaaa/opsx-workflow
```

或本機路徑：`claude plugin marketplace add ~/code/sandbox/opsx-workflow && claude plugin install opsx-workflow@opsx-workflow`。
需要 Python 3.11 以上（macOS 內建的 3.9 不夠，pyenv 或 brew 裝一個）。裝完跑一次 `bash <plugin root>/bin/opsx init --global`（裝 `~/.local/bin/opsx`、建 `~/.local/state/opsx/`、掛 herdr 看板 plugin），
再到每個要用的 repo 根目錄跑 `opsx init`。

`init --global` 會把 PATH 上 `python3` 背後真正的執行檔記在 `~/.local/state/opsx/python`，opsx 和 hooks 只用它（繞過 pyenv shim，每次省 250 ms 左右）。
升級到有這個檔的版本後、或 pyenv 換了 python 版本後，要再跑一次 `opsx init --global`；沒跑的話 opsx 會報錯，卡的 branch 上的授權閘門會擋下 Bash 呼叫。

`init --global` 與 `init` 也會改使用者層 Claude Code settings（`$CLAUDE_CONFIG_DIR/settings.json`，沒設才是 `~/.claude/settings.json`）。要寫什麼只有一份標準設定：`templates/settings.opsx.json`（opsx / openspec 的 allow 規則、opsx state 目錄可寫、herdr socket、`gh pr *` 在沙盒外執行）；`init` 在 repo 裡再把該 repo 的根目錄加進可寫目錄。state 目錄下的 `grants.toml` 與 `python` 在沙盒內唯讀（防止被注入的 session 改授權、或換掉 hook 跑的 interpreter），所以要改它們得在沙盒外（你的終端機）跑 `opsx init --global` 或 `opsx answer --grant`。`dispatch.json` 目前仍可被沙盒內的 session 寫，這個缺口由 `merge-approval-protect` 補。只追加不存在的項目，改檔前把原檔備份成 `settings.json.opsx-bak`，重跑不動；檔案不是合法 JSON 時直接報錯、不改它。

新電腦 onboarding：裝好 plugin → `opsx init --global` → 每個 repo 根目錄 `opsx init` → `opsx init --check` 確認和標準設定一致（只讀；缺什麼逐項印出，exit 1）。要改全部機器的設定，改 `templates/settings.opsx.json`、再各跑一次 `opsx init --global`，不要手改各台的 settings。

資料夾要在 Claude Code 的信任對話框按過信任，專案層 settings 的 allow 與 additionalDirectories 才生效；`opsx init`、`opsx init --check`、`opsx dispatch` 發現 repo 沒信任會警告。opsx 自己的設定在使用者層，不受信任狀態影響；opsx 不會替你改信任紀錄。

## 看板

資料全是投影（`opsx collect`：`openspec/changes/*/`、`~/.local/state/opsx/`、`herdr agent list`、`glab mr view`），看板自己不存狀態。

- 網頁：herdr 裡叫 action `open-board`（`opsx init --global` 已 `herdr plugin link`），或 `bash herdr-board/scripts/open-board.sh`。
  首頁四段 待處理 / 進行中 / 待指派 / 已完成，另有收件匣 tab（見下）；按鈕背後是 `opsx answer`（回 gate、三種授權答案）、`opsx dispatch`、`opsx merge`（寫一次性核准，叫 agent `/babysit merge`，閘門只放行那一次）、`opsx stop`。
- 右側 pane：herdr 裡叫 action `open-pane`，在按鍵的 pane 右邊以 split 開 pane `board`（`python3 herdr-board/tui.py`）；這個 tab 已經開著就跳過去，不疊第二個。同一份清單，↑↓ 選、Enter 跳 pane、i / d 展開收件匣 / 已完成、q 關；不回 gate、不派工。
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
- 收件匣 tab：沒派出、還沒 explore 的卡（explore 過才到首頁待指派），依 inbox.md 的 `source` 分組，加上沒有 repo 的「待分類」。每個按鈕都有對應的子命令，終端機做得到同一件事：
  - `opsx new [--repo <path>] -- <一句話>`：＋新增。範圍選到單一 repo 時建在那裡（slug `me-<YYYYMMDD-HHMM>`），否則寫進 `~/.local/state/opsx/unfiled/` 待分類。
  - `opsx file <slug> --repo <path>`：待分類選 repo 建卡。
  - `opsx drop <slug> [--repo <path>] -- <理由>`：捨棄，理由必填；收件卡歸檔並標 `outcome: declined`，待分類移到 `unfiled/dropped/`。
  - `opsx sync [--source gitlab|github|debt]`：撈 `sources.toml` 登記的 repo 裡指派給你的 issue，和 code 裡的 `shortcut:` 註解，以 inbox.md 的 `source` 去重（含 archive），建殼或更新。上游關閉、註解刪掉只標記（列灰色），卡由你捨棄。每次跑完經 `opsx log --sync` 在 `~/.local/state/opsx/sync.log` 記一列 source `sync`（文字是新建、更新、沒變、錯誤數與第一個錯誤），紀錄 tab 讀得到；同一時間只跑一支，另一支退出碼 3。
  - 每日同步：`opsx init --global` 裝 launchd job `com.opsx.sync`（`~/Library/LaunchAgents/com.opsx.sync.plist`），每天 09:00 跑 `opsx sync`，輸出在 `~/.local/state/opsx/sync.out`。
- 紀錄 tab 在 `board-log` 那張卡（`openspec/workplan.yaml`）。

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
