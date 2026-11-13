# Spec: M<n>-<Track><n> — <Title>

Status: DRAFT — awaiting agreement. <!-- → agreed → in progress → implemented — awaiting playtest → done -->
Milestone: M<n> <name>. Track: <G|T|P|C|B>.
Pillars served: <VISION.md pillar numbers + one line why>.

## Player experience goal

What should the player notice, feel or do differently afterwards? One to three sentences, in
player terms, not code terms. (Tooling specs: what should the developer/agent be able to do?)

## Current state (facts)

Verified facts with `file:line` references. Mark anything unverified as such.

## Changes

Numbered, concrete, each one checkable. Name files and data (`.tres`) touched. Content goes in
`.tres`, not controller branches.

## Alternatives considered

2–3 real alternatives with the reason each lost. "Do nothing" counts as one.

## Why this could be wrong

Main risks to the design (not the code): what playtest result would tell us we were wrong, and
what we'd try instead. The critic review adds to this section.

## Non-goals

What this spec deliberately does not do.

## Tests / acceptance

- Automated: new test cases (file + what they assert). Headless smoke + three logic tests stay clean.
- Agent-verifiable: what `/verify` (and, once M0-T1 lands, the harness) should show.
- User playtest: what to feel for.

## Open decisions

Numbered, each with a recommendation in **bold**.
