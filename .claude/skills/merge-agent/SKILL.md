---
name: merge-agent
description: Director step after an implementation agent reports done — review its worktree branch against the spec, merge it (--no-ff), re-run all checks after the merge, clean up the worktree. Use when an agent's task notification arrives with a finished branch, or when asked to "merge the agent" / "merge <branch>". Args: <branch>.
---

# /merge-agent — review, merge, verify, clean up

Never trust the agent's report alone: the checks run again after the merge.

## 1. Pre-flight

```bash
git status --short          # must be clean; commit or park your own work first
git worktree list           # find the agent's worktree path for the branch
git log --oneline HEAD..<branch>
git diff --stat HEAD...<branch>
```

- The branch name in the agent's report can be wrong: trust `git worktree list`.
- Worktree still dirty (`git -C <path> status --short`): the agent did not commit. Ask it (SendMessage)
  instead of merging half the work.
- A probe running from the main checkout: wait, the merge would change files under it.

## 2. Review

- Read the spec. Diff the rule files line by line: `git diff HEAD...<branch> -- core/ data/`. Skim tests,
  `ui/` and docs.
- Check against AGENTS.md: `core/` without WoW API and globals, `ui/` without rules, asset references only in
  `ui/assets.lua`, class skins change only the whitelisted fields, golden test data untouched, new files in
  the TOC, release code independent of the debug files.
- Tests the agent changed: an assertion that was loosened or removed needs a reason in its report.
- Go through every reported deviation: accept (and tell the user) or send it back before merging.

## 3. Merge and verify

```bash
git merge --no-ff <branch> -m "merge: <item summary>"
tools/checks.sh             # exit 0 = clean
```

Balance-relevant: run `/balance` before and after. Conflicts: keep both sides' intent, re-run the checks.
Never leave a red branch.

## 4. Clean up

```bash
git worktree remove <worktree path>
git branch -d <branch>
```

Push only with the user's go (see AGENTS.md).

## 5. Report to the user

What changed for the player, the post-merge check result, accepted deviations, what you noticed yourself,
and what the in-game playtest should judge.
