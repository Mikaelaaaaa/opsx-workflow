---
name: audit
description: >
  Quality audit of a whole repo: bugs, security holes, what breaks under real
  load, risky code without tests, slow paths, and what to delete, merge or
  split. Ranked, each finding explained in plain English. Changes no code;
  every finding becomes one openspec inbox card. Use for "audit this codebase",
  "review the whole repo", "find bloat", "what can I delete", /audit, or when
  taking over a repo nobody has looked at for a while.
---

Audit the whole repo like the senior developer who just inherited it and
will be paged when it breaks. Order of importance: correct, safe, holds under
load, tested, fast, lean. Lean still matters: every extra line must be read,
tested and fixed later. This is a report the user asked for, so give it in full.

## 1. Map first

- Audit what the user names: a folder, a package, or the whole repo.
  Nothing named: the whole repo.
- Read the README, the deploy and build config, the dependency list, the
  entry points (main, routes, handlers, jobs, CLI commands) and the tests.
- Find the expected load: one person running a script, or many users and
  processes at once. Judge scale against that, and say which load you assumed.
- Trace the main flows end to end: where data comes in, what is stored,
  what goes out. Read those paths fully: input from users, money, auth,
  data writes, background jobs, anything shared between processes.
- Big repo: go deep where a mistake costs the most, not file by file. Say
  which parts you did not read.

## 2. Look for

1. **Bug:** wrong result, crash, missed edge case (empty, zero, last item,
   rounding, time zones), callers that disagree with what a function returns,
   the same rule applied differently in two places.
2. **Risk:** security holes (injection, weak randomness, secrets in code,
   missing checks on input from users), data loss (errors swallowed, writes
   in the wrong order, no transaction).
3. **Scale:** fine for one user, wrong for many: check-then-write races, the
   same work done by every process, memory or lists that only grow, a query
   per item, O(n^2) on big input, per-process state that must be shared.
4. **Missing test:** risky logic (a branch, a parser, money, security, data
   writes) with no test that fails when it breaks. One good test, not coverage.
5. **Speed:** big slowdowns are problems. Small wins (work repeated in a hot
   loop) are suggestions; some software counts every millisecond.
6. **Lean:** code that should not exist or should be smaller.
   - delete: dead code, unused options, flags and config, speculative features
   - reuse: two helpers doing the same thing (keep one, name the path)
   - stdlib / native: the standard library or platform already does it;
     a dependency doing what a few lines or the platform can do
   - yagni: interface with one implementation, factory with one product,
     wrapper that only passes calls through
   - merge: near-copies that must change together
   - split: one function or class doing several unrelated jobs, so it is
     hard to read or test. Split by job, never by line count, and never into
     helpers that exist only to make a function shorter.

## 3. Check before you report

- Every finding needs a concrete case: "this input or situation leads to this
  wrong result". No case, no finding.
- Before calling code unused, grep the whole tree for it, including tests,
  fixtures, config, and string or dynamic references.
- A shortcut marked with a `shortcut:` (or older `ponytail:`) comment that names its limit is a
  decision, not a finding, unless the expected load already crosses it.
- Propose the smallest fix that works. Prefer fixes that delete code. Never
  add layers, frameworks or config the problem does not need.
- No style taste, no "consider", no vague worries.

## 4. Output

(This section replaces ponytail-audit's report file. The output is one
openspec change per finding, so each finding enters the main flow at 收.)

Very simple English: short sentences, everyday words. Explain a technical
term the first time you use it. The reader may never have seen this code.

Write `What this repo does:` in two or three sentences, and the load you
assumed. This paragraph goes into every card's `inbox.md`, so a card can be
read on its own.

Rank the findings in three groups, most important first:
- **must:** bug, security, data loss, breaks at the expected load.
- **should:** risky code without a test, real slowness, duplication, a
  function that mixes jobs, code that should not exist.
- **nice:** small speed-ups, shorter forms.

At most 20 findings; if you left smaller ones out, say how many in the chat
reply. Every finding has all four parts, each one or two short sentences:
**What this is**, **Problem**, **Fix**, **If we skip it**, plus the file
location (`path:Lstart-end`) as the evidence.

For each finding, run 收 once, in the audited repo:

1. Deduplicate first. Read `openspec/changes/*/inbox.md` and
   `openspec/changes/archive/*/inbox.md` in that repo. A card whose `source`
   starts with `audit:<repo>@` and whose 證據 names the same file location,
   or whose 一句話 is the same finding, already exists. Append one line to
   that card's 證據 (`<today> audit:<repo>@<commit>: still present` or
   `: moved to <path:Lstart-end>`) and do not create a new change.
2. Otherwise `openspec new change <slug> --schema opsx --description "<finding title>"`.
   The slug is kebab-case from the finding title.
3. Write `openspec/changes/<slug>/inbox.md` from the template at
   `schemas/opsx/templates/inbox.md`:

   ```
   ---
   type: audit
   source: audit:<repo>@<short commit sha>
   severity: must | should | nice
   found: <YYYY-MM-DD>
   related:
   ---

   ## 一句話

   <finding title>

   ## 這個 repo 做什麼

   <the "What this repo does" paragraph and the assumed load, verbatim, same in every card>

   ## 四部分

   - **What this is:** ...
   - **Problem:** ...
   - **Fix:** ...
   - **If we skip it:** ...

   ## 證據

   <path:Lstart-end>, and the lines that show the problem, quoted.
   ```

4. Add the facts to that frontmatter: `kind_of_work` (a live bug or hole is
   `incident`, with `impact` and `evidence`; the rest are `planned`), then run
   `opsx priority <slug>`. If it prints P0 without a user override, write the
   `p0-review` gate per `references/priority.md`.

`Verdict:` (one line: healthy, or what to fix first), `Lean: -<N> lines,
-<M> dependencies possible.` when lean findings exist, and `Not checked:`
(the parts you did not read or could not run) go in the chat reply only, not
into any card. The reply also lists the changes created (slug and severity)
and the existing cards that got an appended line.

Nothing found: `What this repo does:`, then `Healthy. Nothing to fix.` and
one line on what you checked. No change is created.

Changes no code. Creates openspec change shells only.
