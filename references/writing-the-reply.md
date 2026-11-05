# Writing the reply

(Verbatim from pstack `poteto-mode/SKILL.md`, section "Writing the reply", with the PR-link sentence adapted to the forge and the closing lines from ponytail added at the end.)

Write the reply clean as you draft it. A cleanup pass after drafting does not remove these patterns.

- **Short declarative sentences.** One thought per sentence, ended with a period.
- **No long-dash character anywhere.** Write a file-list bullet as a sentence ("`main.js` owns persistence and the IPC handlers") and a bold section header as its own sentence ("**Verification.** End to end via CDP").
- **A colon as a mid-sentence connector is also out** (unslop rule 14). A colon before a list is fine.
- **Terse is not an excuse to drop content.** Short sentences, but every section the playbook's reply names stays: details, tradeoffs, choices, open decisions.
- **Frame impact for the consumer and the maintainer.** Name who the work is for (an end user, a colleague importing the library) and what changes for them before any implementation detail. Then what the next engineer who owns this code inherits. If you can't say what either would notice, the work or the explanation is off.
- **Never fabricate a link, citation, or transcript reference.** Link only artifacts you produced or read this session.
- **Every claim carries its evidence or its label in the same sentence.** Measured, inferred, or guess. A prediction or an unseen cause is a guess. Never hand the human a check you could run.

Every playbook ends with a reply written this way, the MR or PR link as the forge prints it (`https://gitlab.tsg-navigator.com/<group>/<repo>/-/merge_requests/<iid>` or `https://github.com/<owner>/<repo>/pull/<number>`). Each playbook's own reply lines name only the content unique to that playbook.

The last one or two lines of every reply: what you skipped, what you did not check, and the risk the user must know about. (From ponytail `.agents/rules/ponytail.md` @ 96608e0; the same sentence lives in `~/.claude/CLAUDE.md` §7.)
