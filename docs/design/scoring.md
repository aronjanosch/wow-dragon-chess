# Scoring System

Match values live in `scenes/score_rules.gd` (`MATCH_SCORES`, `match_score()`), singles in
`scenes/game.gd` (`SINGLE_SCORE`), ability values on each ability `.tres` (`score`). Audited 2026-09-27.

## Matches

| Match length | Score |
|---|---|
| 3 | 50 |
| 4 | 125 |
| 5 | 200 |
| 6 | 500 |
| 7+ | 850 (capped, M0-G5: region matches reach 20–30 gems; Dota caps at its 7-match value too) |

## Singles

- 15 per gem cleared **by an ability effect** (not by a match). Junk cleared by an ability also scores 15.

## Abilities

| Activation | Score |
|---|---|
| Skill (4-match gem) | 150 |
| Ult (5+-match gem) | 450 |
| Emerald bomb | 0 |

## Not implemented

- **Doubles ×3** (from the original draft): no multiplier for simultaneous matches exists in code.
  Decide whether to spec it or drop it.
