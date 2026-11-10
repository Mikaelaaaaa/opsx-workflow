# Continue to the next node

Every node of the main flow ends by starting the next one in the same session. Nobody types the next command. This holds for every kind and for both modes: interactive changes how permissions are asked, not whether the flow continues.

| Node done | Next | Condition to continue |
|---|---|---|
| explore | `/grill <slug>` | 待決 non-empty |
| explore | `/propose <slug>` | 待決 empty |
| grill | `/propose <slug>` | 待決 fully answered |
| propose | `/apply <slug>` | tasks.md written, every applyRequires artifact done |
| apply | `/review <slug>` | every task checked, tests green |
| review | `/pr <slug>` | no Bug or Must-fix left open after the fix round |
| pr | `/babysit <slug>` | MR opened and verified |
| babysit | stop | the five merge conditions are green: merging is the user's |

How:

1. Check `openspec/changes/<slug>/gates.md`. Any entry with `status: open` → stop, reply with the gate's question. The user's answer resumes the flow.
2. The condition in the table is not met → stop, say which condition failed and what fixes it.
3. Otherwise invoke the next skill with the Skill tool (`opsx-workflow:<next>`, args `<slug>`) in this turn. Do not ask "shall I continue", do not just name the next step.

Merging is never part of this chain. The flow stops at "waiting for merge".

A feature session (`opsx dispatch --feature`, the card's dispatch.json entry has `feature`) runs several main changes in one pane. When babysit stops at "waiting for merge", run `opsx next` on that card's branch. It prints `/<stage> <主>` for the next main change of the same feature that has no MR yet, or `none`. On a command, invoke it now: switch to that main change's PR branch (apply step 2 does) and continue. On `none`, stop. Main changes that wait on a merge are woken by `opsx chain` later.
