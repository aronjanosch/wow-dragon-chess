---
name: verify
description: Verify a Dragon Chess addon change before reporting it done — all headless tests on lua5.1 and luajit, the release package without debug files, and a spec checklist pass. Use at the end of every implementation task, when asked to "verify", or before committing gameplay / UI changes. Pass the spec path as argument if there is one.
---

# /verify

1. `tools/checks.sh` — must exit 0. Paste the failing lines if it does not. One test measures allocations
   (`ui_fx_test`, "allocates < 1 KB") and can fail once under load: re-run that file alone before treating it as
   a regression.
2. `tools/package.sh` — builds `dist/DragonChess-<version>.zip`; it fails if a debug file or a missing TOC entry
   would ship. New `.lua` files must be listed in `DragonChess.toc` (and in `test/loader.lua` `CORE_FILES` when
   they are core files).
3. If a spec was given: go through its "Changes" and "Tests / acceptance" lists and name every deviation.
4. Balance-relevant change (ability values, enemy data, run scaling): run
   `lua5.1 tools/balance_probe.lua --seeds 100 --paces 0.6 --diffs 3,4 --policies first` before and after and
   report both rows. 30 seeds are too noisy to see a 10-point shift.
5. Look and feel cannot be verified headless: say so and list what the user has to check in game (`/reload`).
