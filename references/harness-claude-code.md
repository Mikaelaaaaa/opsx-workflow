# pstack skills in Claude Code

The skills copied from pstack use Cursor names. In Claude Code, read this file once per session, then map each Cursor name in a skill with the tables below. `<pstack>` means the opsx-workflow plugin root, the folder that holds `skills/` and `references/`; every `<pstack>/<path>` is the local copy that `UPSTREAM.md` lists, never the upstream plugin. If a Cursor field has no row, drop it and say so. Never pass a field or value the tool schema rejects.

## Tools

| Cursor | Claude Code |
| --- | --- |
| `Task` | `Agent` |
| `AskQuestion` | `AskUserQuestion`. In `-p` mode it is absent, so ask in plain text. |
| Open a todolist | Use `TodoWrite` if the session offers it. Otherwise keep the list in your reply and update it at each phase. |
| Run another pstack skill (`/name` or "the **name** skill") | `Read` `<pstack>/skills/<name>/SKILL.md` and follow it. The `Skill` tool refuses most of these skills. When you tell the user to type it, write `/opsx:<name>`. |
| `Grep`, `Glob` | `Bash` with `rg` when the session has no `Grep` or `Glob`. |
| The **principle-<name>** skill | `Read` `<pstack>/references/principles/<name>.md`. The index is `<pstack>/references/principles/INDEX.md`. |
| A playbook (`playbooks/<name>.md`) | `<pstack>/skills/apply/references/playbooks/<name>.md`. `feature` is `dev.md`, `perf-issue` is `perf.md`. `investigation` and `prototype` live in `<pstack>/skills/explore/references/`. `babysit`, `session-pickup`, `pause-safely`, and the two forensics playbooks are skills (`babysit`, `pickup`, `pause`, `forensics`). |

## Subagent fields

| Cursor | Claude Code |
| --- | --- |
| `subagent_type: generalPurpose` | `subagent_type: "general-purpose"` |
| `poteto-agent`, `comment-sicko` | `general-purpose`. This plugin ships neither agent. |
| `readonly: true` | `subagent_type: "Explore"`. It keeps `Bash`, so the brief also says "do not edit files", and you check `git status` afterward. |
| `readonly: false` | `general-purpose`. It keeps the session's MCP servers. |
| `environment: "cloud"` | `isolation: "worktree"`. Name the branch or commit the worker checks out. |
| `environment: "local"` | Omit. |
| `cloud_base_branch: <b>` | Tell the worker to check out `<b>` first. |
| `run_in_background: true` | Omit. Subagents run in the background by default and notify you when they finish. |
| `resume` | Spawn a new agent and paste the earlier result into its brief. |
| `file_attachments` | List the paths in the brief. |

## Models

| Cursor | Claude Code |
| --- | --- |
| `claude-<family>-<version>-<effort>[-fast]`, such as `claude-opus-5-5-xhigh` | Omit `model`. This plugin runs every role on the session model (one model, no panel). The copied skills keep the upstream slug in parentheses for diff traceability only. If a role needs more or less reasoning than the session, pass `effort` alone. (Upstream mapping, not used here: `model: "opus"` and `effort: "xhigh"`; `model` takes only `opus`, `sonnet`, `haiku`, `fable`; drop `-fast`.) |
| A `grok-*`, `gpt-*`, or other non-Claude slug | Omit `model` so the agent runs on the session model, and say so. |
| `auto` or `inherit-parent` | Omit `model`. |
| The `pstack-models.mdc` rule, `~/.cursor/rules/pstack-models.mdc` | Not used. This plugin has no per-role model rule and no `setup-pstack`. Use the skill's default slug, mapped with the rows above. |
| A role value `<model> <effort>`, such as `opus high` | `model: "opus"` and `effort: "high"`. |
| "A different model family" (a cross-model panel, judge, or reviewer) | One model family only. Vary `effort` between reviewers, or run one reviewer, and say so. |

## Paths

| Cursor | Claude Code |
| --- | --- |
| `.cursor/skills/`, `~/.cursor/skills/` | `.claude/skills/`, `~/.claude/skills/` |
| `~/.cursor/plugins/`, `.cursor-plugin/plugin.json` | `~/.claude/plugins/`, `.claude-plugin/plugin.json` |
| `.cursor/rules/*.mdc`, always-applied rules | `CLAUDE.md`, or `AGENTS.md` when no `CLAUDE.md` exists. Claude Code never reads `.mdc` files. |
| `https://github.com/cursor/plugins/blob/main/pstack/<path>` | `<pstack>/<path>` when `UPSTREAM.md` lists a local copy. Read the local copy and never fetch it. Give the user the URL when they need a link. |
| Transcripts in `~/.cursor/projects/<slug>/agent-transcripts/` | `~/.claude/projects/<slug>/<session>.jsonl`. The slug is the workspace path with each `/` and `.` changed to `-`, so `/Users/you/proj` is `-Users-you-proj`. The newest `.jsonl` directly in that folder is the current session. Its `<session>/subagents/` folder holds subagent transcripts. Read only this workspace's folder. |

## Blocked actions

When a hook, a safety check, or auto mode blocks an action, follow step 5 in `<pstack>/skills/apply/SKILL.md`.

## Cursor-only features

Claude Code has no Cursor Automations, Bugbot, Cursor cloud agents, or built-in PR tool. This plugin also ships no `deslop`, `control-ui`, `control-cli`, `cursor-team-kit`, `arena`, `swarm`, `create-skill`, `watch-pr`, or `shipping`. When a step needs one, put one line in your reply, `Skipped in Claude Code: <step>. <reason>.`, then go on to the next step. Do not stop, ask, or retry. When a later step needs what the skipped step made, such as a URL or a key, leave a placeholder and name it in the line.

| Cursor | Claude Code |
| --- | --- |
| Cursor Automations: routines, `update_state` routine calls, `api2.cursor.sh/automations` webhooks, routine wakes, and `SendToUser` secret requests | Skip with the line. |
| Bugbot | Bugbot comments on a PR are ordinary review threads, so triage them with the forge command that the step gives (`glab mr view --comments` or `gh pr view --comments`). Skip a step that starts, waits for, or configures Bugbot when the PR has no Bugbot check or comment. |
| Cursor cloud agents | `environment: "cloud"` maps to a worktree, as in Subagent fields. Skip a step that needs the cloud agent itself, such as its dashboard status or its own machine. |
| A built-in PR tool | Use the forge command that the step gives, such as `glab mr create` or `gh pr create`. That is not a skip, so write no line. |
| `arena` | One candidate. Run the step's prompt once on the session model and continue. |
| `create-skill` | The `skill-creator` plugin skill. |
| `/deslop`, `control-ui`, `control-cli` | Skip with the line. |
