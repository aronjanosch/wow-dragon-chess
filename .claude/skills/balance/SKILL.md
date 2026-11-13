---
name: balance
description: Measure Dragon Chess balance with the headless bot instead of guessing — full runs per difficulty at human-like swap paces, win rates with confidence intervals, heal and ability counters. Saves a condensed report to docs/playtests/data/. Use before and after any tuning change (ability values, enemy data, run scaling), when a playtest says "too easy / hard / strong", or when asked to "measure", "probe" or "check balance".
---

# /balance — bot measurement

```bash
lua5.1 tools/balance_probe.lua --seeds 100 --paces 0.6 --diffs 3,4 --policies first --title "<what>"
```

- Options: `--seeds N` (runs per row), `--paces 0.6,0.9` (seconds between swaps), `--diffs 1,2,3,4,5`,
  `--policies first,hold` (`first` = first legal move; `hold` = keeps the Amber heal ult while HP > 70 %),
  `--fights` (per-fight table). Deterministic (seeds 1..N), sim time only, about 0.3 s CPU per run.
- **Before / after:** measure the old state too (a `git worktree` of the previous commit in the scratchpad, or a
  scratch copy of the repo with the one value changed); several variants can run in parallel as background jobs.
- **What-if without editing the repo:** a throwaway `lua5.1` script in the scratchpad that loads the core via
  `dofile("test/helpers.lua")` (from the repo root) and overrides a function or a value before the runs.

## Reading the numbers

- 30 seeds: about ±17 points on a win rate. 100 seeds: about ±10. Decide on 100; do not gate on smaller
  differences. D3 and D4 are the sensitive rows (D1 / D2 sit near 100 %, D5 near the floor).
- The bot takes the first legal move: it never times an ability, never banks one, never reads the enemy's
  attack queue. A timing human gets more out of windows (Fire Shield), holds (heal ult) and banks (shield
  stacks). For those, also compute the best case by hand (see `docs/specs/w1-g3-reflect-and-fast-attackers.md`).
- Compare against the right baseline (the change alone, not "today plus three other changes").

## Save

Condense the tables into `docs/playtests/data/<date>-<topic>.md` (variants as rows, what was decided and why)
and reference it from the spec.
