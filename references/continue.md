# Continue to the next node

Every node of the main flow ends by starting the next one in the same session. Nobody types the next command. This holds for every kind and for both modes: interactive changes how permissions are asked, not whether the flow continues.

| Node done | Next | Condition to continue |
|---|---|---|
| explore | `/grill <slug>` | 待決 non-empty and kind is not chore or bug-fix |
| explore | `/propose <slug>` | 待決 empty, or kind is chore or bug-fix |
| grill | `/propose <slug>` | 待決 fully answered |
| propose | `/apply <slug>` | tasks.md written, every applyRequires artifact done |
| apply | `/review <slug>` | every task checked, tests green |
| review | `/pr <slug>` | no Bug or Must-fix left open after the fix round (Consider does not count) |
| pr | `/babysit <slug>` | MR opened and verified |
| babysit | stop | the five merge conditions are green: merging is the user's |

How:

1. Check `openspec/changes/<slug>/gates.md`. Any entry with `status: open` → stop, reply with the gate's question. The user's answer resumes the flow.
2. The condition in the table is not met → stop, say which condition failed and what fixes it.
3. Otherwise invoke the next skill with the Skill tool (`opsx-workflow:<next>`, args `<slug>`) in this turn. Do not ask "shall I continue", do not just name the next step.

Merging is never part of this chain. The flow stops at "waiting for merge".

## The Stop hook enforces it

The text above is not enough on its own, so `hooks/openspec-stop-gate.sh` checks the card's node (`stage_of`) whenever you try to stop. If the next node is grill, propose, apply, review, pr, or babysit and no gate is blocking, it blocks the stop and tells you to invoke that node.

- A gate that asks 要不要接 / 要不要派 / 要不要繼續 does not count as open. Asking whether to continue is a violation of step 3, not a reason to stop. Only a question the user alone can answer (a product choice, a grant, a conflict) belongs in a gate.
- The hook blocks the same node at most 3 times. On the next stop it writes a gate titled 卡在接 /<node> itself and lets you stop. `stop_hook_active` does not release it.
- Babysit leaves `babysit: <ISO time>` under `## MR` in `report.md`; without it the hook keeps asking for `/babysit`.

## Light flow

Small changes do not carry the full ceremony.

- **Skip grill.** A card of kind chore or bug-fix goes from explore straight to propose even when 待決 is non-empty; propose writes each open item into proposal.md as an assumption. The router (`bin/lib/stage.sh`) says the same. Grill runs before tasks.md exists, so only the kind can decide this.
- **A small card** has all of: tasks.md has at most 3 tasks, and the changed files, test paths left out (`tests/` and any file named `*.test.*` or `*_test.*`), share the same first path component in `git diff --name-only main...HEAD`. Only kind chore or bug-fix can be small. Review measures it, because only then do tasks and the diff exist.
- **Review of a small card** runs one merged reviewer (spec conformance and code quality together) and no adversarial one. Any other card runs three.
- **Review runs at most two rounds.** The round number is in report.md's title. After two rounds a third review is not started; a gate lists the Bug and Must-fix items still open.
- **Consider never blocks the flow.** Consider never opens a gate and never sends the card back to apply. Only a Bug or Must-fix still open after the second round opens a gate.
