### Eval

**You own the experiment design. Plan, blind, run, synthesize.**

**Non-negotiables for blinding:**

- No `eval`, `test`, `judge`, `experiment`, `rubric`, `score`, `compare`, `benchmark`, `candidate`, or `arena` in any directory, file, or prompt the candidate sees.
- The candidate prompt looks like an organic user request. State the goal, not the meta.
- No chain-eliciting cues. Don't ask the candidate to list which skills, principles, or files they applied. Ask for design notes generally and grade chain-following from code shape, not self-report.
- Sanitize directory and slug names. Use project-shaped names a user might pick.
- Don't tell the candidate other candidates exist.
- The judge can know it's judging but sees outputs by sanitized label only, never by model name.
- Comparing two variants: one judge scores both sets in a single pass on one scale, blind to which set each came from.

**Steps:**

1. **Frame.** State what variant is under test and what behavior counts as success. Write the rubric (3-6 concrete criteria) for the judge only. Hold it back from candidates.
2. **Set up sanitized environments.** Per-candidate working dir with the variant in place. Plant any context an organic task would have: a project skeleton, the skills the candidate would naturally read.
3. **Author one organic prompt.** What a user would type. No leakage of what's being measured.
4. **Run N candidates, each in its own `claude` session** (upstream: different models per the `arena` skill's Phase B; this plugin has one model, so the variation between candidates is the variant under test plus sampling, not the model). Do not spawn them from this session: a spawned agent inherits this session's cwd, git status, user skills and plugin skills, which leaks the task. Each works in its own sanitized dir. Same prompt to each. The user starts these sessions outside the sandbox.
   - A scenario of this repo's own skills: `bash evals/run-candidate.sh <skill> <eval-id> <new|old> <results-dir>`, once per candidate and variant. It builds the sanitized dir, runs `claude -p`, and prints `work:`, `session:` and `transcript:`.
   - Anything else: per candidate, make a fresh `<uuid>`, put the variant under test in `<dir>/.claude/skills/`, then run `cd <dir> && claude --setting-sources project,local -p "<prompt>" --session-id <uuid> --settings <settings-file> --permission-mode acceptEdits --allowedTools Bash`. `<settings-file>` is JSON with `sandbox.enabled` true, `sandbox.autoAllowBashIfSandboxed` true and `sandbox.allowUnsandboxedCommands` false, so Bash can write only inside `<dir>` (the same file `evals/run-candidate.sh` writes). `--setting-sources project,local` keeps user and plugin skills out and needs no API key.
   - Interactive: hand the user the commands. In autopilot, write an authorization gate in `gates.md` (`type: approval`, `needs: run`) that holds the full commands, then stop. Do not start the session yourself and do not fall back to spawning.
5. **Spawn one blinded judge** as an ordinary `general-purpose` subagent with a fresh context (upstream: a different model family per the `arena` skill's Phase C). Judge sees outputs by sanitized label and the rubric, never a model name.
6. **Verify the chain from transcripts, not self-report.** Read each candidate's transcript: the path the runner prints as `transcript:`, or without a runner `<config dir>/projects/<slug>/<session id>.jsonl`. `<config dir>` is `$CLAUDE_CONFIG_DIR`, or `~/.claude` when it is unset. `<slug>` is the candidate's working dir with each `/` and `.` changed to `-` (the Paths table in `references/harness-claude-code.md` gives the rule). `<session id>` is the uuid passed to `--session-id`. If that file is missing, report the path you derived. Do not glob across `<config dir>/projects/*/`. That crosses workspace boundaries and reads private chats from unrelated projects. Look at which files each candidate actually opened. Grade chain-following from the files it really read plus the shape of the code, never from the candidate's own claims.
7. **Read every candidate output yourself** end to end. Compare to the judge's verdict. Disagreement means a model is biased or the rubric is ambiguous. Synthesize.

**Reply:** variant under test, rubric, per-candidate notes, judge's verdict, your synthesis, and a recommendation for whether to promote the variant.
