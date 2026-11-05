---
name: tdd
description: "Red → green → refactor for one task at a time. In opsx every kind of change reads this at apply step 3b: write the test named in tasks.md (驗收 scenario + edges), see it fail, commit it, then implement to green. Also use when the user asks for TDD, a failing test, or a regression test."
disable-model-invocation: true
---

# TDD Bug Fix

When fixing a bug with a clear, cheap test path, make the broken behavior executable before changing production code. The goal is a focused regression test that fails before the fix and passes after it.

Do not force a test when it would be impractical. If the available test would require broad harness setup, brittle mocks, slow end-to-end infrastructure, production-only state, vague reproduction steps, or large unrelated fixture churn, skip adding a new test and use the closest useful verification instead.

## Workflow

1. **Understand the bug.** Identify the intended behavior, current behavior, affected path, and smallest observable reproduction.
2. **Choose the narrowest executable check.** Prefer the closest unit, component, integration, or regression test already used for that codepath. If no practical test path is obvious, do not create one from scratch just to satisfy the workflow.
3. **Write the failing test first.** Add the smallest focused test that would have caught the bug. The test should encode intended behavior, not mirror the current implementation.
4. **Run the new test before fixing.** Confirm it fails for the intended reason. If it passes or fails for an unrelated reason, correct the test or reproduction before editing the implementation.
5. **Fix the bug.** Make the smallest production change that satisfies the intended behavior while preserving nearby contracts.
6. **Rerun the regression test.** Confirm the test now passes.

## If a Failing Test Is Impractical

Use the closest executable regression check instead: a targeted script, manual reproduction command, browser automation, snapshot comparison, log assertion, or focused integration check.

Prefer no new test over a bad test. A bad test is one that mostly tests mocks, encodes current implementation details, depends on timing or unrelated global state, needs expensive infrastructure for a small fix, or would be deleted immediately after proving the fix.

## Guardrails

- Do not change tests merely to match a wrong implementation.
- Do not weaken existing assertions unless the expected behavior has genuinely changed and the reason is clear.
- Keep the regression test focused on the bug. Avoid broad fixture churn or unrelated coverage expansion.
- If the bug is flaky, make the test deterministic where possible and document the signal being locked down.
- If the bug exposes a broader class of failures, first land the focused regression path, then consider additional sibling coverage.

## What a good test looks like

Tests verify behavior through public interfaces, not implementation details. The good ones are integration-style: they exercise real code paths through the API a caller would use, and they read like a specification ("user can checkout with a valid cart" says exactly which capability exists). They survive refactors because they do not care about internal structure. The bad ones mock internal collaborators, test private methods, or verify through a side door (querying the database directly instead of using the interface); the warning sign is a test that breaks when you rename an internal function although behavior did not change. In opsx the `驗收：` line on each task names the scenario the test must express; if the test cannot be read back as that scenario, it is testing shape, not behavior.

Do not write all the tests first and then all the code. That horizontal slicing tests imagined behavior, locks in data shapes and signatures before you understand the implementation, and produces tests that pass when behavior breaks and fail when it is fine. One task, one test, red, green, next.

## Final Response

Report the evidence, not just the outcome:

- Name the failing-before test or executable check and the failure it produced.
- Name the passing-after test run and any nearby validation performed.
- If failing-before evidence could not be demonstrated, state why and describe the closest regression check used instead.
