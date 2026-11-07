# Principles index

The 24 pstack principles, one file each. Read a principle in full before you cite it; cite only principles whose file you read this session, and name the specific choice it changed. In any copied skill or playbook, "the **principle-<name>** skill" or "**principle-<name>**" means `references/principles/<name>.md`. The one-liners are the Principles index from pstack's `poteto-mode/SKILL.md`.

**Core**

- laziness-protocol — Refactoring, sizing a diff, or tempted to add abstractions, layers, or signal threading. Bias to deletion and the smallest change that solves the problem.
- foundational-thinking — Before writing logic: core types and data structures, scaffold-vs-feature sequencing, what concurrent actors share.
- redesign-from-first-principles — Integrating a new requirement into an existing design. Redesign as if it had been foundational from day one.
- attack-the-premise — Two or more fixes that share one premise have failed the same gate. Write the premise down and test it directly before you write another fix that assumes it.
- subtract-before-you-add — Sequencing an addition, refactor, or rewrite. Remove dead weight first, then build on the simpler base.
- minimize-reader-load — Reviewing or shaping code that's hard to trace. Count layers and hidden state, collapse one-caller wrappers, shrink mutable scope.
- outcome-oriented-execution — Planned rewrites and migrations with explicit phase boundaries. Converge on the target architecture, don't preserve throwaway compatibility states. (Only within the caller list the change's design.md names; CLAUDE.md §3 wins outside it.)
- experience-first — Product, UX, or feature-scope tradeoffs. Choose user delight over implementation convenience. (Prototype flow only.)
- exhaust-the-design-space — A novel interaction or architectural decision with no precedent. Build 2-3 competing prototypes and compare before committing. (Prototype flow only.)
- build-the-lever — Any non-trivial work. Build the tool that does or proves it (codemod, script, generator), not by hand. The tool is the artifact a reviewer reruns.

**Architecture**

- model-the-domain — Writing stateful logic, or code that branches a lot or repeats a shape assumption across files. Encode the domain in a structure (state machine, typed model, table or registry, reducer, boundary, the right collection) instead of scattered conditionals.
- boundary-discipline — Wiring validation, error handling, or framework adapters. Guards at system boundaries, trust internal types, keep business logic pure.
- type-system-discipline — Designing types or a signature in any typed language. Make illegal states unrepresentable, brand primitives, parse external data at boundaries.
- make-operations-idempotent — Designing commands, lifecycle steps, or loops that run amid crashes and retries. Converge to the same end state.
- migrate-callers-then-delete-legacy-apis — Introducing a new internal API while old callers exist. Migrate and delete in one wave. (Only within the caller list the change's design.md names; CLAUDE.md §3 wins outside it.)
- separate-before-serializing-shared-state — Concurrent actors might write the same file, branch, key, or object. Eliminate the sharing first.

**Verification**

- prove-it-works — After a task, before declaring done. Verify against the real artifact, not a proxy or "it compiles".
- fix-root-causes — Debugging. Trace each symptom back to the first place the system went wrong and fix it there. A guard is a fix only when the state it handles is legitimate.
- sequence-verifiable-units — Multi-step work (sweeps, migrations, runs of similar edits) and how you stack commits and PRs. Break work into small units that each end in a check, verify each before the next, and order delivery so the sequence proves itself. (In opsx the Delivery order applies between changes and between PRs; one change is still one commit.)
- test-behavior-not-implementation — Writing, changing, or keeping a test. Assert what the code's users can observe, so the test fails when that behavior breaks and keeps passing when only the internals change.
- explain-the-number — Before you trust, report, or act on a number you measured (a speedup, a regression, a throughput, a latency, or an eval result). Find what limits it, and rule out that it measured something other than the work you think.

**Delegation**

- guard-the-context-window — Context fills up: large outputs, long files, repeated reads, fan-out planning. Route bulk to subagents, keep summaries in the main thread.
- never-block-on-the-human — Tempted to ask "should I do X?" on reversible work. Proceed, present the result, let the human course-correct. (Worker in apply writes a gate; a person in grill is asked, per CLAUDE.md §1.)

**Meta**

- encode-lessons-in-structure — You catch yourself writing the same instruction a second time. Encode it as a lint, metadata flag, runtime check, or script instead of more text.
