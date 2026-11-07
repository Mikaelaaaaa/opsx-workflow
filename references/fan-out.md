# Fan-out: one pane coordinating subagents

When a parent card merges and more than one child card is ready, `opsx chain <parent>` registers every child in `dispatch.json` with `via: <parent>` and `herdr_name: <this pane's herdr name>`, and prints one line per child: `chain: fan out <slug> · <branch> · <kind> · /<stage> · from <remote>/main`. `<remote>` is the repo's primary remote: `gitlab` when it exists (in Agentory-AI and Agentory-Infrastructure `origin` is only the GitHub mirror and can lag behind the merge), otherwise `origin`. From then on this pane does none of the cards itself. It spawns, relays and opens gates.

## What goes to a subagent, what stays in the pane

| Work | Who |
|---|---|
| A child card's apply, review and pr, when its tasks need nobody | a subagent |
| Anything that needs the user: a level-two action without a grant, a product choice | the pane, as a gate in that card's `gates.md` |
| Two cards where one depends on the other | the pane runs them one after the other, never in parallel |
| Merge (`/babysit merge <sha> <slug>`) | the subagent that owns the card, because the grant gate reads the card from the branch of the directory the command runs in |

A subagent has no herdr agent name. `opsx answer` and the board cannot reach it, so a subagent never waits for the user. It reports and stops.

## Spawning

One Agent call per child, `isolation: "worktree"`, `run_in_background: true`. The brief must contain:

- First commands: `git fetch <remote>` and `git switch --no-track -c <branch> <remote>/main` (both from the `chain:` line). Without `--no-track` git tries to write `.git/config`, the sandbox refuses, and the worktree is left half switched.
- The workflow: call the `apply` skill for `<slug>`, then `review`, then `pr`. Name the skills; a subagent that is not told invents its own process.
- What the parent card changed: its file list (`git show --stat` of the merge) and the D-ids in its `design.md` that the child builds on. The subagent starts with none of this pane's context.
- The report contract: finish with `DONE <slug> <MR url>`, or `NEEDS-USER <slug>` followed by the question, the options and the evidence. Commit and push before reporting, because the harness may remove the worktree once the subagent ends.

## Relaying

Prompts for a fanned-out card reach this pane prefixed with the card's slug:

| Prompt the pane receives | What the pane does |
|---|---|
| `[<slug>] <answer text>` | SendMessage the answer to that card's subagent |
| `/babysit merge <sha> <slug>` | SendMessage the subagent: run `/babysit merge <sha>` in its own worktree |
| `[<slug>] stop` | stop that subagent (TaskStop); its branch and worktree stay |

If the subagent cannot be reached (it ended and the worktree is gone), write a gate in that card's `gates.md`: the card has to be re-dispatched (`opsx stop <slug>`, then 指派 on the board).

When a subagent reports `NEEDS-USER`, write the gate in **that card's** `gates.md`, not the parent's, then keep relaying for the others. The answer comes back as `[<slug>] …`.
