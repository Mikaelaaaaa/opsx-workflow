---
name: pr
description: |
  Open or update the merge request for the current change: reads the change's report.md and
  tasks.md, writes the description in the mr-note format (English section headers, Chinese
  tables with 編號 / 程式碼改動 / 業務層邏輯 / 對應測試, real test file names), pushes the branch,
  creates the MR on GitLab (glab) or the PR on GitHub (gh) depending on the repo's primary remote,
  verifies the description landed, and writes the MR URL back into report.md. Use when the user
  says "pr", "open MR", "開 MR", "create PR", "submit", "送審", or when the opsx router injects
  `pr · <slug>` after review. Does not merge; merge is always the user's.
argument-hint: "[change slug] [title hint]"
compatibility: Requires glab (GitLab repos) or gh (GitHub repos). Push and MR creation are level-two actions; in autopilot the grant hook decides.
---

# /pr

Turn a reviewed change into a merge request the reviewer and the PM can both read.

## Where you are

`openspec/changes/<slug>/report.md` exists (review ran) and has no MR URL yet. If report.md is missing, stop and say `/review <slug>` comes first; the Stop hook will say the same. If report.md still lists items under `待修（範圍內）`, stop and say `/apply <slug>` comes first; the Stop hook will say the same. If it already has an MR URL, this is an update: regenerate the description and `glab mr update` / `gh pr edit`. The update path never comments on the issue; step 5b runs only for a new MR.

## Steps

1. **Pre-flight.** Not on `main` / `master`. `git status` clean, or say what is uncommitted and stop. Which forge: `git remote -v`; in Agentory-AI and Agentory-Infrastructure the primary is the `gitlab` remote, `origin` is only a mirror, so push to `gitlab`; elsewhere `origin`. Read `references/mr-note.md`.
2. **Gather.** `git log <base>..HEAD --oneline`, `git diff <base>...HEAD --stat`, `report.md` (四桶 and ledger verdict), `tasks.md` (每 task 的 編號 and `測試：` path), `proposal.md` (Summary material), `design.md` (D-ids for Reviewer notes), `grill.md` if present. Migrations: anything under `drizzle/`, `alembic/`, `migrations/` in the diff.
3. **Write the description to a file** `openspec/changes/<slug>/mr.md` in the mr-note format. Title = the conventional-commit subject of the branch's main commit, `type(scope): summary`. Changes table rows = tasks, one per task, 編號 = task number, 對應測試 = that task's `測試：` file. Test plan = the test agent's last summary from report.md and the merge-gate command for this repo (`pnpm test:merge-gate` in Agentory-AI; see each repo's CLAUDE.md). Reviewer notes = 範圍、rollback / risk when ACL / schema / enforcement paths moved, D-ids that deviated, follow-ups as inbox card slugs. No emoji, no slogans, no bracketed explanations in headers.
4. **Push and open.** `git push -u <remote> <branch>`, then `glab mr create --title "<title>" -F openspec/changes/<slug>/mr.md --source-branch <branch> --target-branch main` (or `gh pr create --title … --body-file …`). Never `--fill`; the format hook denies an MR without the table. Set the MR to auto-merge only if the repo's CLAUDE.md says so. Run every `gh` call here and in step 5 as its own Bash command, never chained with `;`, `&&`, `||`, `|`, `$(…)` or a trailing `echo exit=$?`: the sandbox exclusion that lets `gh` reach GitHub is the pattern `gh pr *`, and a chained command does not match it, stays inside the sandbox and fails with `x509 … OSStatus -26276`.
5. **Verify.** `glab mr view <iid> -F json` (or `gh pr view --json body,url`): description length > 0 and contains `## Changes` and `| 編號 |`. A 200 on update can still have written an empty body; read it back. Then append to report.md:

   ```
   ## MR
   <url> · opened <date> · auto-merge: <yes|no>
   ```

   and `opsx status pr 5/5 "MR 已開"`.
5b. **Back-link.** Leave the MR URL on the issue the card came from, only when this run opened a new MR (report.md had no MR URL before step 5) and the card's inbox.md `source:` starts with `gitlab:` or `github:`. Cards from any other source are skipped. Locate the issue through inbox.md's `upstream_url`, not through `source` (its `<repo>` is the local repo name).
   - GitLab: `glab issue note <n> -R <upstream_url without /-/issues/<n>> -m "<mr url>"`, where `<n>` is the `#<n>` at the end of `source`.
   - GitHub: `gh issue comment <upstream_url> --body "<mr url>"`, as its own Bash command for the same reason as step 4: the sandbox exclusion is `gh issue comment *`.

   The comment is the MR link and nothing else; never close the issue or change its labels. If the command exits non-zero, or inbox.md has no `upstream_url` (missing `upstream_url` counts as a failure; do not guess the project), add one line under `## MR` in report.md, `issue 回寫失敗：<reason>` (the first stderr line, or `缺 upstream_url`), and go on to step 6. A failed back-link does not stop /pr: the MR is already open. When the grant hook denies the command, that is a failure too: if the deny message carries `action: mr` (a one-time `mr` grant was used up by step 4), write `issue 回寫失敗：無 mr 授權`; for any other deny, use the first line of the deny message as the reason. Then go on; do not write a gate and do not retry, even though the deny message asks for a gate (apply step 5 names this exception).
6. **Reply.** The URL, the title, what the Test plan says, and the two closing lines (skipped / unchecked / risks). Then continue to `/babysit <slug>` per `../../references/continue.md`: invoke it now unless a gate is open. Babysit handles CI and review threads and stops when the card is waiting for the user to merge.

## Guardrails

- Push and MR creation need a level-two grant in autopilot; without one, write a gate and stop here.
- No AI attribution in the title, body, or commits.
- Do not merge. Do not resolve threads. That is `/babysit` for comments and the user for the merge button.
