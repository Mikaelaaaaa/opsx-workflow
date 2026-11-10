# Continue to the next node

Every node of the main flow ends by starting the next one in the same session. Nobody types the next command. This holds for every kind and for both modes: interactive changes how permissions are asked, not whether the flow continues.

| Node done | Next | Condition to continue |
|---|---|---|
| explore | `/grill <slug>` | 待決 non-empty and kind is not chore or bug-fix |
| explore | `/propose <slug>` | 待決 empty, or kind is chore or bug-fix |
| grill | `/propose <slug>` | 待決 fully answered |
| propose | `/apply <slug>` | tasks.md written, every applyRequires artifact done |
| apply | `/review <slug>` | every task checked, tests green |
| review | `/apply <slug>` | `待修（範圍內）` has items |
| review | `/pr <slug>` | no `待修（範圍內）` item left open (Consider does not count) |
| pr | `/babysit <slug>` | MR opened and verified |
| babysit | stop | the five merge conditions are green: merging is the user's |

How:

1. Check `openspec/changes/<slug>/gates.md`. Any entry with `status: open` → stop, reply with the gate's question. The user's answer resumes the flow.
2. The condition in the table is not met → stop, say which condition failed and what fixes it.
3. Otherwise invoke the next skill with the Skill tool (`opsx-workflow:<next>`, args `<slug>`) in this turn. Do not ask "shall I continue", do not just name the next step.

Merging is never part of this chain. The flow stops at "waiting for merge".

A feature session (`opsx dispatch --feature`, the card's dispatch.json entry has `feature`) runs several main changes in one pane. When babysit stops at "waiting for merge", run `opsx next` in the session's worktree. It prints `/<stage> <主>` for the next main change of the same feature that has no MR yet, or `none`. On a command, invoke it now: switch to that main change's PR branch (apply step 2 does) and continue. On `none`, stop. Main changes that wait on a merge are woken by `opsx chain` later.

When a feature session receives `[<slug>] stop`, the user stopped that one main change on the board. If you are working on it, stop at once. If the worktree has uncommitted changes, make one `wip:` commit of them on that main change's branch, so the worktree is clean before anything switches branch; otherwise the next main change's checkout fails or carries the half-done work into the wrong PR. Do not pick that main change up again; `opsx next` skips it because its dispatch.json entry is `stopped`. Then run `opsx next` and continue with what it prints, or stop on `none`. The card comes back only when the user runs `opsx dispatch <slug>`, which sends `[<slug>] /<stage> <slug>` to this session; then switch back to its branch and continue from the `wip:` commit.

## The Stop hook enforces it

The text above is not enough on its own, so `hooks/openspec-stop-gate.sh` checks the card's node (`stage_of`) whenever you try to stop. If the next node is grill, propose, apply, review, pr, or babysit and no gate is blocking, it blocks the stop and tells you to invoke that node.

- A gate that asks 要不要接 / 要不要派 / 要不要繼續 does not count as open. Asking whether to continue is a violation of step 3, not a reason to stop. Only a question the user alone can answer (a product choice, a grant, a conflict) belongs in a gate.
- The hook blocks the same node at most 3 times. On the next stop it writes a gate titled 卡在接 /<node> itself and lets you stop. `stop_hook_active` does not release it.
- Babysit leaves `babysit: <ISO time>` under `## MR` in `report.md`; without it the hook keeps asking for `/babysit`.

## Light flow

Small changes do not carry the full ceremony.

- **Skip grill.** A card of kind chore or bug-fix goes from explore straight to propose even when 待決 is non-empty; propose writes each open item into proposal.md as an assumption. The router (`bin/lib/stage.sh`) says the same. Grill runs before tasks.md exists, so only the kind can decide this.
- **A small card** has all of: tasks.md has at most 3 tasks (not counting the `## R<N>.` groups review adds), and the changed files, test paths left out (`tests/` and any file named `*.test.*` or `*_test.*`), share the same first path component in `git diff --name-only main...HEAD`. Only kind chore or bug-fix can be small. Review measures it, because only then do tasks and the diff exist.
- **Review of a small card** runs one merged reviewer (spec conformance and code quality together) and no adversarial one. Any other card runs three.
- **Review runs at most two rounds.** The round number is in report.md's title. After two rounds a third full review is not started: the items still open are fixed through `/apply`, and review runs only a confirm pass over them and writes `確認: <sha>` in report.md. A gate is for an item that needs a user decision.
- **Consider never blocks the flow.** Consider never opens a gate and never sends the card back to apply. Only an in-scope Bug or Must-fix that needs a user decision and cannot be fixed opens a gate.
