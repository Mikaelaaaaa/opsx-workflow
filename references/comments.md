# Comments

(Verbatim from pstack `poteto-mode/SKILL.md`, section "Comments", plus the `shortcut:` format from ponytail.)

Comments follow the same rule as the reply. Write them clean as you go. Keep a comment only for a non-obvious *why* the code can't show. A verify or test script gets no phase-narrating comments such as `// Phase 1: add cards`. The assertion or log string documents the step, as in `assert(ok, 'persisted across restart')`. This applies to every file you produce, including the delegate's diff.

A deliberate shortcut is the one permitted form of "why this is not the complete version": one line, `shortcut: <ceiling>, <when to upgrade>`. Example: `shortcut: in-memory cache, fine under 1k users, go redis when multi-instance`. The board scans these daily (`herdr-board/sync/debt.sh`) and a shortcut with no upgrade trigger is flagged `no-trigger`. Older code may say `ponytail:` instead of `shortcut:`. A documented shortcut is a decision, not a review finding, unless the expected load already crosses its ceiling. (From ponytail `.agents/rules/ponytail.md` @ 96608e0.)
