# Prototype

**You own the design decision, not the code. The prototype is a throwaway instrument. The real build follows the dev playbook.**

This is the one place where "smallest change" and the verification bar invert. Speed over polish, code quality does not matter, no planning. The rigor is in picking the right answer cheaply: propose variations the user did not ask for, throw an approach away and try another.

Grill sends bucket-2 items here (things that running once would settle); explore uses it when a 待決 item would otherwise be a guess.

1. **Scope the decision the prototype exists to make**: which layout, which interaction, which density, or for an empirical fork which behavior, timing, or approach. No decision means no prototype; route back to the main flow.
2. **Pick the branch by the question.**
   - *Does this logic / state / timing behave the way we think?* → the smallest script that exercises the question. Push the state machine through the cases that are hard to reason about on paper; print the full relevant state after every step so the reader sees what changed. Log the timing or the output; that observation is the answer.
   - *What should this look like?* → vanilla HTML/CSS/JS or the lightest stack that renders the idea, CDN deps, a dev server with reload. Several radically different variants behind one switcher (buttons or a keypress, each labeled) rather than one polished mock; that is "exhaust the design space" made cheap.
3. **Build it throwaway, in a scratch directory outside the production source tree**, named so nobody mistakes it for product code. No production framework, no tests, no abstractions, no persistence (state in memory; if the question is the database, hit a scratch DB or file with a "PROTOTYPE — wipe me" name). One command to run.
4. **Gather references when the design space is open**: prior art, a moodboard of directions, and let the user pick before building. Skip when the direction is already set.
5. **Verify on the matching surface.** Visual decision: screenshot each variant and drive the interaction. Behavioral decision: watch the thing you are deciding. The observation is the test here, not an assertion.
6. **Present alternatives, tradeoffs, and a recommendation.** The output is the decision plus the throwaway artifact, never shippable code. Record the answer where it lives in this workflow: explore.md 已知 (with what you ran and what you saw) or a grill D-id. Then delete the scratch directory or leave a clearly marked placeholder for the user to confirm first.

**Reply:** the variants explored, the evidence (screenshots for a visual decision, the observed output or timing for a behavioral one), tradeoffs, your recommendation, and the scratch path. Say plainly that the prototype is throwaway.
