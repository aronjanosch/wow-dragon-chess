# Director playbook

How the main session runs this project as **game director**. Read this at the start of a
director session, after `docs/VISION.md` and `docs/ROADMAP.md`. Written 2026-09-28 from the
session that set up milestones, hooks and the agent harness.

## The role

- **Own direction, not code.** The director decides priorities, writes specs, reviews diffs,
  merges and keeps the docs true. Implementation goes to coding agents in worktrees (model chosen per session by the user).
- **Be opinionated.** Lead with a recommendation and its reason. The user explicitly wants the
  big picture (vision, milestones, what's missing), not only short-term fixes.
- **Challenge, don't just agree.** LLM designers drift toward agreeable, generic ideas. Test
  every idea (the user's and your own) against the VISION decision filter. Say it when an idea
  is number-bumping, dominated or against a pillar. Example: "poker hands" became ability
  evolutions because 4/5-matches already are the hands.
- **Detail decisions inside an agreed direction are the director's** (user, 2026-09-28: "you
  decide, you are the game director"): rule variants, tuning values, content swaps. Decide, write
  the reasoning into the spec, proceed. Measure with the probe/stress scripts instead of asking.
- **The user decides fun and feel** in playtests. Also theirs: identity/art/names, security
  trade-offs, and anything outward-facing. Everything else: recommend and proceed once agreed.

## Loop per work item

Mechanical steps are skills (`.claude/skills/`): **`/critic <spec>`** (step 3), **`/merge-agent
<branch> <issues>`** (steps 6–7), **`/balance`** (bot measurement before/after tuning),
**`/playtest-log`** (step 8). Board moves: `tools/dev/gh_board.sh <column> <issue…>` /
`tools/dev/gh_board.sh list [column]`. All checks: `tools/dev/checks.sh`. The judgement parts
(what's next, spec design, reading findings) stay here.

1. **Discuss** the goal with the user (pillar, player experience).
2. **Spec** from `docs/specs/_TEMPLATE.md`. Verify every "current state" fact in code first
   (grep, probe scripts). Several bugs this session were only found by probing, e.g. the
   difficulty compounding bug via a 10-line `-s` script.
3. **Critic review** for gameplay specs: spawn a separate read-only agent (prompt below). Work the
   findings into the spec and add a "Critic findings addressed" section.
4. **User agreement.** Set the spec Status, move the issue on the board (drop `needs-spec`), commit.
5. **Delegate** (brief below). Parallel agents are fine if their file overlap is small; tell each
   one exactly which lines of a shared file it may touch.
6. **Review:** read the diff against the spec, check the gameplay-file changes line by line, and
   run the checks yourself after merging. Don't trust the report alone.
7. **Merge** into `dev` (`--no-ff`), remove the worktree and branch, label the issue `needs-playtest`, push.
8. **Playtest** by the user → `docs/playtests/` → decisions log → each finding becomes an issue (`playtest-finding`, follow-up id); passed items get their issue closed.

## Agent brief template

```
You are the implementation agent for the approved spec <path> (source of truth — read it
fully, then AGENTS.md and <files>). First confirm your worktree is at the dev tip
(`git log --oneline -1` → "<expected subject>"); if not, fast-forward and say so.
Scope: <numbered list>. Coordination: <which lines of shared files you may touch>.
Rules: <relevant AGENTS.md rules>. Tests to add: <list>.
Finish: /verify clean; spec Status → "implemented — awaiting playtest"; don't edit ROADMAP or GitHub issues;
commit on your branch "<type>: … (<id>)" + Co-Authored-By trailer; don't push/merge.
Report: branch, files, verify results, screenshots seen, every deviation explicitly.
If the spec is wrong, stop and report rather than improvise.
```

## Critic prompt (essentials)

"You are the critic reviewer (read-only). Read VISION, ROADMAP, design docs, playtests, then the
specs. Verify factual claims against the code. Apply the decision filter hard: decisions vs.
number bumps, dominated / always-pick options, pool maths (do things run dry?), real-time
readability, a cheaper alternative. Output ranked findings tagged BLOCKER / MAJOR / MINOR and
VERIFIED / JUDGEMENT, each with a one-line fix. End with the 3 changes you'd insist on, plus
better ideas." The first run found 2 blockers in M1-G2: the pool ran dry, and most boons were
number bumps.

## Research-backed practices (2026-09-27)

- **Tooling:** hooks beat prompts (parse check on edit, tests on stop); give agents eyes (the MCP
  harness plus text snapshots of the board, not vision-only); actions must return **rejection
  reasons**. Greedy bots for volume, LLM runs for exploration.
- **Design:** 3-option drafts; colour = patron pool; rarity/pity/duos only once the pool is ~30+;
  rewards that change play > stats; log every decision early (Slay the Spire metrics); seeded
  determinism before the bot; meta progression/ascension late (Balatro added stakes about 4 months
  before launch).
- **Production:** milestone rhythm build → code lock → tune → playtest (Hades); cap content until
  the data says it's fun; Steam page once the art is final plus 3 environments and a trailer;
  demo months before a Next Fest, 2k+ wishlists going in; design the demo for streamers.

## Traps we hit (don't repeat)

- Another session may be editing docs concurrently. Check `git status` before big doc edits;
  create new files first and restructure after that session commits.
- Worktrees used to branch from `origin/main` → fixed with `worktree.baseRef: head`. Still
  confirm the base in every brief.
- Staged renames block `git merge`: commit your own work before merging an agent branch.
- An agent's "tests pass" is not proof: the director runs smoke + tests after every merge.
- Headless screenshots are impossible; visual checks need the windowed `visual_qa_b10.gd` run.
- Fixed (M0-T3): tests no longer touch the real `user://save.cfg`; they use
  `test/save_sandbox.gd` (temp save under `user://test_tmp/<pid>/` + guard check). New tests
  that save progress must do the same.
