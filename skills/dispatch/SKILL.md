---
name: dispatch
description: |
  Hand a change to a worker: open its worktree and a herdr pane in the repo's workspace, start a
  claude or codex session there with the right permission profile, send the first command, and
  record it in dispatch.json so the board can track it. Use when the user says "dispatch", "派",
  "派工", "指派", "把 X 派給 claude/codex", "開一個 agent 做 X", or wants a change worked on in the
  background. Needs HERDR_ENV (run from inside a herdr pane). Never merges, never answers gates.
argument-hint: "<slug> [--agent claude|codex] [--mode interactive|autopilot] [--kind <kind>] [--model <id>]"
compatibility: Requires herdr and the opsx CLI (bin/opsx). Same script the board's 指派 button calls.
---

# /dispatch

The board's 指派 button and this skill run the same script: `bin/opsx dispatch`. This skill only fills in the arguments and relays the result.

## Steps

1. Resolve the slug. `$ARGUMENTS` first; otherwise list `openspec/changes/*/` that have `inbox.md` or `tasks.md` but no entry in `~/.local/state/opsx/dispatch.json`, and ask with **AskUserQuestion** which one.
2. Fill the three choices the dialog on the board would show, asking only for what is not given:
   - **kind** (default from the card's source hint: GitLab label bug / agent 回報 bug → `bug-fix`; shortcut → `refactoring`; "太慢" in the title → `perf`; else `dev`). Seven values: dev, bug-fix, refactoring, perf, experiment, ops, chore.
   - **agent + model**: claude with the model implied by kind (dev / refactoring / perf / experiment → `claude-opus-5-5`; bug-fix / chore / ops → `claude-sonnet-5-5`), or codex (`gpt-5`).
   - **mode**: `interactive` (每步問) or `autopilot` (開到可合併: `drive.sh` carries it through every stage to review → pr → babysit until the five merge conditions are green; anything that needs the user becomes a gate). `drive` is still accepted and means `autopilot`.
3. Run it from the repo root:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/bin/opsx" dispatch <slug> --agent <a> --model <m> --mode <mode> --kind <kind>
   ```

   The script: writes `kind` into `.openspec.yaml`; picks the branch from `workplan.yaml` or `{feat|fix|chore|refactor}/<slug>/<user>`; `git worktree add .claude/worktrees/<slug>`; `herdr tab create` in the workspace mapped in `workspaces.toml` (or creates one named after the repo and records it); `herdr agent start <slug>` with `--permission-mode dontAsk --settings <generated allow/deny>` for autopilot (anything outside allow is denied without a prompt; the grant hook allows what has a grant); `herdr agent prompt <slug> "/<stage> <slug>"` where the stage comes from the same table the router uses; writes `dispatch.json`; in autopilot starts `opsx drive` in the background, which records its own pid.
4. Relay the script's last line (repo/slug → agent · model · mode · kind · workspace pane · first command). If it refused (bad slug, no card, no herdr), say why and what to fix; do not reimplement any step by hand.

## What it will not do

Answer a gate (that is the board or `herdr agent prompt`), merge, or dispatch a card that is still in the inbox without a kind. `opsx stop <slug>` is the reverse.
