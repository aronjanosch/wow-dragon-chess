---
name: critic
description: Run the mandatory critic review on a Dragon Chess gameplay spec before it goes to the user — spawns a separate read-only agent that verifies the spec's facts in code and stress-tests the design against VISION.md, then fold its findings into the spec (rev +1, "Critic findings addressed"). Use after drafting any gameplay/balance spec in docs/specs/, or when asked for a "critic review". Arg: the spec path, plus optional context (user decisions that are fixed, data files).
---

# /critic — critic review of a spec

## 1. Spawn the critic (background, read-only)

Agent tool (model: the one the user picked for this session, no hardcoded default), no worktree (read-only). Prompt skeleton — fill the `<…>`:

```
You are the critic reviewer (read-only: do NOT edit repo files, do NOT commit). Repo: <root>.
Read docs/VISION.md, docs/ROADMAP.md (decisions log), docs/design/*.md, the latest
docs/playtests/*.md, <data files, e.g. docs/playtests/data/…>, related specs <…>, then the
spec under review: <spec path>. Also `gh issue view <N> --comments`.

Fixed by the user (don't relitigate unless you find a concrete reason it cannot work):
<decisions>.

Verify every factual claim against the code (<files/functions the spec relies on>). If needed,
probe with a throwaway `lua5.1` script in <scratchpad> (load the core via `dofile("test/helpers.lua")` from the
repo root, see `tools/balance_probe.lua`) — never inside the repo.

Apply the decision filter hard: decisions vs. number bumps, dominated / always-pick options, pool
maths (do things run dry?), real-time readability ("feedback over explanation": is it visible?),
measurability of every gate (sample sizes, noise), missing test
and doc touch points, and a cheaper alternative. Specific questions: <2–5 hard questions>.

Output: ranked findings tagged BLOCKER / MAJOR / MINOR and VERIFIED / JUDGEMENT, each with a
one-line fix. End with the 3 changes you'd insist on.
```

## 2. While it runs

Useful: run any measurement the critic is likely to ask for (`lua5.1 tools/balance_probe.lua`). Don't start the implementation agent before the findings are in.

## 3. Fold the findings in

- Every BLOCKER and MAJOR: fix in the spec, or reject with a reason written in the spec.
- Measure instead of guessing when a finding is about numbers (the critic's models are estimates).
- Bump the status line (`DRAFT rev N (after critic review <date>)`), add or extend
  `## Critic findings addressed (<date>)` (one paragraph: finding → change).
- Decisions inside the agreed direction are the director's (docs/DIRECTOR.md): decide, write the
  reason into "Alternatives considered", proceed. New directions / identity / feel go to the user.
- Commit (`docs: <ID> rev N after critic review`). The spec then goes to the user for agreement.
