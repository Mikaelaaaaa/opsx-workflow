---
name: deepen
description: Find deepening opportunities in a codebase, informed by the domain language in CONTEXT.md and the decisions in docs/adr/. Use when the user wants to improve architecture, find refactoring opportunities, consolidate tightly-coupled modules, make a codebase more testable and AI-navigable, or says "find shallow modules", "this area is scattered", "architecture check-up".
---

# Deepen

(Source: `~/.claude/skills/improve-codebase-architecture/SKILL.md`. A parallel flow in opsx: each candidate the user picks becomes a new change shell with `kind: refactoring`, and the apply playbook for it is `skills/apply/references/playbooks/refactoring.md`.)

Surface architectural friction and propose **deepening opportunities**: refactors that turn shallow modules into deep ones. The aim is testability and AI-navigability.

## Glossary

Use these terms exactly in every suggestion. Consistent language is the point. Don't drift into "component," "service," "API," or "boundary." Full definitions in [`references/architecture-language.md`](../../references/architecture-language.md), shared with `architect` and the refactoring playbook.

- **Module**: anything with an interface and an implementation (function, class, package, slice).
- **Interface**: everything a caller must know to use the module: types, invariants, error modes, ordering, config. Not just the type signature.
- **Implementation**: the code inside.
- **Depth**: leverage at the interface: a lot of behaviour behind a small interface. **Deep** = high leverage. **Shallow** = interface nearly as complex as the implementation.
- **Seam**: where an interface lives; a place behaviour can be altered without editing in place. (Use this, not "boundary.")
- **Adapter**: a concrete thing satisfying an interface at a seam.
- **Leverage**: what callers get from depth.
- **Locality**: what maintainers get from depth: change, bugs, knowledge concentrated in one place.

Key principles (see the language reference for the full list):

- **Deletion test**: imagine deleting the module. If complexity vanishes, it was a pass-through. If complexity reappears across N callers, it was earning its keep.
- **The interface is the test surface.**
- **One adapter = hypothetical seam. Two adapters = real seam.**

This skill is _informed_ by the project's domain model. The domain language gives names to good seams; ADRs record decisions the skill should not re-litigate.

## Process

### 1. Explore

Read the project's domain glossary (`CONTEXT.md`, only rag-demo has one today; skip when absent) and any ADRs in the area you're touching first.

Then use the Agent tool with `subagent_type=Explore` to walk the codebase. Don't follow rigid heuristics. Explore organically and note where you experience friction:

- Where does understanding one concept require bouncing between many small modules?
- Where are modules **shallow**, with an interface nearly as complex as the implementation?
- Where have pure functions been extracted just for testability, but the real bugs hide in how they're called (no **locality**)?
- Where do tightly-coupled modules leak across their seams?
- Which parts of the codebase are untested, or hard to test through their current interface?

Apply the **deletion test** to anything you suspect is shallow: would deleting it concentrate complexity, or just move it? A "yes, concentrates" is the signal you want.

### 2. Present candidates

Present a numbered list of deepening opportunities. For each candidate:

- **Files**: which files/modules are involved
- **Problem**: why the current architecture is causing friction
- **Solution**: plain English description of what would change
- **Benefits**: explained in terms of locality and leverage, and also in how tests would improve

**Use CONTEXT.md vocabulary for the domain, and the architecture-language reference for the architecture.** If `CONTEXT.md` defines "Order," talk about "the Order intake module", not "the FooBarHandler," and not "the Order service."

**ADR conflicts**: if a candidate contradicts an existing ADR, only surface it when the friction is real enough to warrant revisiting the ADR. Mark it clearly (e.g. _"contradicts ADR-0007, but worth reopening because…"_). Don't list every theoretical refactor an ADR forbids.

Do NOT propose interfaces yet. Ask the user: "Which of these would you like to explore?"

### 3. Grilling loop

Once the user picks a candidate, drop into a grilling conversation (the `grill` skill's method: one question at a time, each with a recommended answer). Walk the design tree with them: constraints, dependencies, the shape of the deepened module, what sits behind the seam, what tests survive. Classify each dependency with [`references/deepening.md`](references/deepening.md) to decide how the deepened module is tested across its seam.

Side effects happen inline as decisions crystallize:

- **Naming a deepened module after a concept not in `CONTEXT.md`?** Add the term to `CONTEXT.md`, same discipline as `grill` (see `skills/grill/references/CONTEXT-FORMAT.md`). Create the file lazily if it doesn't exist.
- **Sharpening a fuzzy term during the conversation?** Update `CONTEXT.md` right there.
- **User rejects the candidate with a load-bearing reason?** Record the reason in the candidate's row so the next audit does not re-suggest it. (ADRs are not written in opsx; the decision is that the reason lives with the change or in grill.md.)
- **Want to explore alternative interfaces for the deepened module?** See [`references/interface-design.md`](references/interface-design.md). Open question: that reference asks for three subagents producing three interfaces, which conflicts with `architect`'s single-candidate rule; until decided, run it as one subagent that writes all three briefs' answers and compares them.

### 4. Open the change

For each candidate the user chose, run 收: `openspec new change <slug> --schema opsx --description "<candidate title>"`, write `inbox.md` with `type: 技術債`, `source: deepen`, the Files / Problem / Solution / Benefits block as the body, and the grill decisions (D1…Dn) as the start of its `grill.md`. Set `kind: refactoring` in `.openspec.yaml`. The change then walks the main flow from explore.
