# W1-G2 Amber heals: balance probe (2026-11-11)

Tool: `tools/balance_probe.lua` (headless, lua5.1, deterministic seeds 1..30, no god mode, the bot swaps every 0.6 s or
0.9 s of sim time). Spec: `docs/specs/w1-g2-amber-heals.md` section 4. Reproduce:
`lua5.1 tools/balance_probe.lua --seeds 30` (about 2 min for the full matrix) and
`lua5.1 tools/balance_probe.lua --seeds 30 --paces 0.6 --diffs 3 --fights` for the per-fight tables.

Reading notes: the bot is a first-legal-move player, not a strategist; boards diverge after the first Amber ult, so only
distributions are comparable between before and after. "median HP at fight end" is over won fights only. Per-fight
"HP at end" is the HP when the enemy died, before the boss heal. In the BEFORE section "ults" are Polymorph (convert) casts,
so "ults <60 % HP" and the `hold` policy mean nothing there (`hold` is just a second sample).

# BEFORE: lifesteal kit (commit a56ddbd)

Seeds 1..30 per row, sim step 1/30 s, no god mode. `first` = first legal move, `hold` = skip moves that fire an Amber ult while HP > 70 %.
Heal columns are per run, mean (HP; max HP 10000). `lifesteal` = unsourced `player_healed` minus boss heals (old code). `waste` = overheal + Heal Block loss (n/a before W1-G2: no `heal_lost` event). `uptime` = share of fight time the Amber skill status was up.

| policy | pace | D | wins | win rate (95 % Wilson) | dies in fight (median) | median HP at fight end (won fights) | heal lifesteal | heal hot | heal ult | heal boss | waste | skills | ults | ults <60 % HP | uptime |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| first | 0.6 | 1 | 30/30 | 100% (89%-100%) | - | 85% | 9374 | 0 | 0 | 5102 | n/a | 14.7 | 17.3 | 8% | 19% |
| first | 0.6 | 2 | 28/30 | 93% (79%-98%) | f6 (2 runs) | 72% | 10777 | 0 | 0 | 5849 | n/a | 16.8 | 20.8 | 25% | 20% |
| first | 0.6 | 3 | 14/30 | 47% (30%-64%) | f6 (16 runs) | 56% | 9803 | 0 | 0 | 5091 | n/a | 15.4 | 15.5 | 58% | 20% |
| first | 0.6 | 4 | 6/30 | 20% (10%-37%) | f6 (24 runs) | 51% | 7034 | 0 | 0 | 3493 | n/a | 11.0 | 11.2 | 71% | 19% |
| first | 0.6 | 5 | 1/30 | 3% (1%-17%) | f5 (29 runs) | 42% | 5383 | 0 | 0 | 2081 | n/a | 8.3 | 6.5 | 75% | 19% |
| first | 0.9 | 1 | 1/30 | 3% (1%-17%) | f6 (29 runs) | 47% | 3780 | 0 | 0 | 3750 | n/a | 7.5 | 7.9 | 73% | 13% |
| first | 0.9 | 2 | 0/30 | 0% (0%-11%) | f5 (30 runs) | 43% | 2205 | 0 | 0 | 1750 | n/a | 4.3 | 3.0 | 85% | 11% |
| first | 0.9 | 3 | 0/30 | 0% (0%-11%) | f3 (30 runs) | 42% | 1430 | 0 | 0 | 750 | n/a | 2.7 | 2.9 | 80% | 11% |
| first | 0.9 | 4 | 0/30 | 0% (0%-11%) | f3 (30 runs) | 61% | 1130 | 0 | 0 | 0 | n/a | 2.1 | 1.3 | 75% | 11% |
| first | 0.9 | 5 | 0/30 | 0% (0%-11%) | f2 (30 runs) | 58% | 860 | 0 | 0 | 83 | n/a | 1.6 | 1.0 | 60% | 9% |
| hold | 0.6 | 1 | 30/30 | 100% (89%-100%) | - | 86% | 9854 | 0 | 0 | 4812 | n/a | 15.1 | 15.2 | 14% | 20% |
| hold | 0.6 | 2 | 27/30 | 90% (74%-97%) | f10 (3 runs) | 74% | 10916 | 0 | 0 | 5878 | n/a | 16.7 | 18.2 | 30% | 19% |
| hold | 0.6 | 3 | 15/30 | 50% (33%-67%) | f6 (15 runs) | 58% | 8646 | 0 | 0 | 4443 | n/a | 13.1 | 16.1 | 58% | 19% |
| hold | 0.6 | 4 | 3/30 | 10% (3%-26%) | f6 (27 runs) | 54% | 6147 | 0 | 0 | 3323 | n/a | 9.6 | 10.5 | 73% | 18% |
| hold | 0.6 | 5 | 2/30 | 7% (2%-21%) | f3 (28 runs) | 42% | 4889 | 0 | 0 | 1782 | n/a | 7.7 | 6.2 | 79% | 19% |
| hold | 0.9 | 1 | 1/30 | 3% (1%-17%) | f6 (29 runs) | 46% | 3701 | 0 | 0 | 3750 | n/a | 7.4 | 7.7 | 86% | 13% |
| hold | 0.9 | 2 | 0/30 | 0% (0%-11%) | f5.5 (30 runs) | 42% | 2293 | 0 | 0 | 1750 | n/a | 4.3 | 2.1 | 84% | 12% |
| hold | 0.9 | 3 | 0/30 | 0% (0%-11%) | f3 (30 runs) | 43% | 1310 | 0 | 0 | 667 | n/a | 2.6 | 1.8 | 72% | 10% |
| hold | 0.9 | 4 | 0/30 | 0% (0%-11%) | f3 (30 runs) | 62% | 1136 | 0 | 0 | 0 | n/a | 2.2 | 1.2 | 72% | 11% |
| hold | 0.9 | 5 | 0/30 | 0% (0%-11%) | f2 (30 runs) | 58% | 882 | 0 | 0 | 83 | n/a | 1.6 | 0.7 | 67% | 9% |

### Per fight (mean over runs that reached the fight)

**first, pace 0.6, D3**

| fight | enemy | reached | won | damage taken | min HP | HP at end (won) | duration (won) | heal in fight |
|---|---|---|---|---|---|---|---|---|
| 1 | hellhound | 30 | 30 | 1748 | 8353 | 8421 | 36s | 199 |
| 2 | gordok_ogre | 30 | 30 | 3112 | 5717 | 5936 | 54s | 625 |
| 3 | basilisk_matriarch | 30 | 30 | 3378 | 3399 | 3692 | 80s | 1137 |
| 4 | forest_troll | 30 | 30 | 1739 | 4946 | 5104 | 76s | 1018 |
| 5 | harpy | 30 | 29 | 1619 | 4455 | 5003 | 55s | 1269 |
| 6 | hakkar | 29 | 19 | 4198 | 2118 | 3711 | 101s | 1349 |
| 7 | qiraji_scarab | 19 | 19 | 336 | 6037 | 6495 | 60s | 906 |
| 8 | anubisath_sentinel | 19 | 19 | 1111 | 5997 | 6650 | 67s | 1009 |
| 9 | ouro | 19 | 19 | 1356 | 5924 | 7136 | 122s | 1949 |
| 10 | nefarian | 19 | 14 | 8606 | 2430 | 3946 | 206s | 2848 |

**hold, pace 0.6, D3**

| fight | enemy | reached | won | damage taken | min HP | HP at end (won) | duration (won) | heal in fight |
|---|---|---|---|---|---|---|---|---|
| 1 | hellhound | 30 | 30 | 1738 | 8326 | 8368 | 36s | 133 |
| 2 | gordok_ogre | 30 | 30 | 2967 | 5845 | 6074 | 52s | 669 |
| 3 | basilisk_matriarch | 30 | 29 | 3231 | 3671 | 4191 | 82s | 1212 |
| 4 | forest_troll | 29 | 29 | 2045 | 5029 | 5474 | 75s | 1126 |
| 5 | harpy | 29 | 28 | 1643 | 4483 | 5101 | 57s | 1144 |
| 6 | hakkar | 28 | 15 | 4421 | 1969 | 3957 | 97s | 1040 |
| 7 | qiraji_scarab | 15 | 15 | 385 | 6334 | 6679 | 60s | 1114 |
| 8 | anubisath_sentinel | 15 | 15 | 1296 | 6200 | 6428 | 71s | 833 |
| 9 | ouro | 15 | 15 | 1468 | 5772 | 7230 | 122s | 2318 |
| 10 | nefarian | 15 | 15 | 7926 | 2979 | 3484 | 194s | 2671 |

# AFTER: HoT kit (hot_percent = 5, heal_percent = 15)

The `heal lifesteal` column is 0 by construction (the source no longer exists); `waste` = HP lost to overheal plus HP lost
to Heal Block, now measured through `heal_lost`. "ults" are Lay on Hands casts.

Seeds 1..30 per row, sim step 1/30 s, no god mode. `first` = first legal move, `hold` = skip moves that fire an Amber ult while HP > 70 %.
Heal columns are per run, mean (HP; max HP 10000). `lifesteal` = unsourced `player_healed` minus boss heals (old code). `waste` = overheal + Heal Block loss (n/a before W1-G2: no `heal_lost` event). `uptime` = share of fight time the Amber skill status was up.

| policy | pace | D | wins | win rate (95 % Wilson) | dies in fight (median) | median HP at fight end (won fights) | heal lifesteal | heal hot | heal ult | heal boss | waste | skills | ults | ults <60 % HP | uptime |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| first | 0.6 | 1 | 30/30 | 100% (89%-100%) | - | 89% | 0 | 3042 | 4214 | 3717 | 6812 | 10.2 | 6.0 | 7% | 16% |
| first | 0.6 | 2 | 30/30 | 100% (89%-100%) | - | 82% | 0 | 3544 | 6413 | 4886 | 6908 | 11.4 | 7.5 | 12% | 15% |
| first | 0.6 | 3 | 21/30 | 70% (52%-83%) | f6 (9 runs) | 69% | 0 | 4443 | 6782 | 4799 | 4322 | 11.7 | 6.6 | 31% | 16% |
| first | 0.6 | 4 | 10/30 | 33% (19%-51%) | f6 (20 runs) | 62% | 0 | 4520 | 7006 | 4318 | 3175 | 10.8 | 6.3 | 33% | 16% |
| first | 0.6 | 5 | 4/30 | 13% (5%-30%) | f4 (26 runs) | 59% | 0 | 3166 | 4956 | 2444 | 2665 | 8.1 | 4.5 | 49% | 17% |
| first | 0.9 | 1 | 16/30 | 53% (36%-70%) | f6 (14 runs) | 58% | 0 | 3333 | 5238 | 5138 | 1676 | 8.0 | 4.2 | 50% | 11% |
| first | 0.9 | 2 | 2/30 | 7% (2%-21%) | f6 (28 runs) | 44% | 0 | 2238 | 3249 | 2835 | 512 | 4.9 | 2.4 | 69% | 11% |
| first | 0.9 | 3 | 0/30 | 0% (0%-11%) | f3 (30 runs) | 47% | 0 | 1385 | 1765 | 1000 | 277 | 3.0 | 1.3 | 74% | 10% |
| first | 0.9 | 4 | 0/30 | 0% (0%-11%) | f3 (30 runs) | 61% | 0 | 1112 | 1375 | 250 | 77 | 2.2 | 1.0 | 76% | 10% |
| first | 0.9 | 5 | 0/30 | 0% (0%-11%) | f3 (30 runs) | 58% | 0 | 743 | 732 | 0 | 18 | 1.5 | 0.5 | 67% | 10% |
| hold | 0.6 | 1 | 30/30 | 100% (89%-100%) | - | 89% | 0 | 3120 | 4107 | 3723 | 6061 | 10.3 | 5.5 | 5% | 16% |
| hold | 0.6 | 2 | 30/30 | 100% (89%-100%) | - | 80% | 0 | 3960 | 6193 | 4998 | 6161 | 11.5 | 7.1 | 16% | 15% |
| hold | 0.6 | 3 | 24/30 | 80% (63%-90%) | f6 (6 runs) | 72% | 0 | 4396 | 7561 | 5215 | 4146 | 11.9 | 6.9 | 29% | 16% |
| hold | 0.6 | 4 | 9/30 | 30% (17%-48%) | f6 (21 runs) | 64% | 0 | 4169 | 6589 | 3780 | 2626 | 10.3 | 5.5 | 45% | 16% |
| hold | 0.6 | 5 | 4/30 | 13% (5%-30%) | f5.5 (26 runs) | 59% | 0 | 3642 | 5568 | 2752 | 2022 | 8.7 | 4.7 | 56% | 18% |
| hold | 0.9 | 1 | 13/30 | 43% (27%-61%) | f6 (17 runs) | 58% | 0 | 3369 | 4765 | 5373 | 1522 | 7.7 | 3.9 | 52% | 10% |
| hold | 0.9 | 2 | 2/30 | 7% (2%-21%) | f6 (28 runs) | 46% | 0 | 2216 | 3646 | 3123 | 305 | 4.7 | 2.5 | 70% | 10% |
| hold | 0.9 | 3 | 0/30 | 0% (0%-11%) | f3 (30 runs) | 47% | 0 | 1493 | 2050 | 1167 | 140 | 3.2 | 1.4 | 76% | 11% |
| hold | 0.9 | 4 | 0/30 | 0% (0%-11%) | f3 (30 runs) | 61% | 0 | 1082 | 1600 | 167 | 52 | 2.2 | 1.1 | 76% | 10% |
| hold | 0.9 | 5 | 0/30 | 0% (0%-11%) | f3 (30 runs) | 58% | 0 | 793 | 800 | 0 | 0 | 1.6 | 0.5 | 69% | 10% |

### Per fight (mean over runs that reached the fight)

**first, pace 0.6, D3**

| fight | enemy | reached | won | damage taken | min HP | HP at end (won) | duration (won) | heal in fight |
|---|---|---|---|---|---|---|---|---|
| 1 | hellhound | 30 | 30 | 1692 | 8444 | 8685 | 36s | 377 |
| 2 | gordok_ogre | 30 | 30 | 3270 | 5978 | 6321 | 54s | 906 |
| 3 | basilisk_matriarch | 30 | 30 | 3086 | 4038 | 4593 | 81s | 1358 |
| 4 | forest_troll | 30 | 30 | 1525 | 5918 | 6116 | 72s | 901 |
| 5 | harpy | 30 | 29 | 1674 | 5244 | 5914 | 56s | 1116 |
| 6 | hakkar | 29 | 23 | 3827 | 3400 | 5019 | 99s | 1711 |
| 7 | qiraji_scarab | 23 | 23 | 355 | 6916 | 7088 | 56s | 794 |
| 8 | anubisath_sentinel | 23 | 23 | 1003 | 6830 | 6801 | 63s | 500 |
| 9 | ouro | 23 | 23 | 459 | 6832 | 8248 | 122s | 1845 |
| 10 | nefarian | 23 | 21 | 7707 | 4291 | 5790 | 206s | 3270 |

**hold, pace 0.6, D3**

| fight | enemy | reached | won | damage taken | min HP | HP at end (won) | duration (won) | heal in fight |
|---|---|---|---|---|---|---|---|---|
| 1 | hellhound | 30 | 30 | 1708 | 8407 | 8601 | 36s | 309 |
| 2 | gordok_ogre | 30 | 30 | 3086 | 6180 | 6469 | 52s | 953 |
| 3 | basilisk_matriarch | 30 | 30 | 3317 | 4298 | 4642 | 78s | 1490 |
| 4 | forest_troll | 30 | 30 | 1574 | 6060 | 6378 | 72s | 935 |
| 5 | harpy | 30 | 29 | 1535 | 5425 | 6333 | 55s | 1194 |
| 6 | hakkar | 29 | 24 | 3740 | 3747 | 5477 | 97s | 1821 |
| 7 | qiraji_scarab | 24 | 24 | 372 | 7205 | 7844 | 59s | 989 |
| 8 | anubisath_sentinel | 24 | 24 | 1589 | 7017 | 7290 | 67s | 856 |
| 9 | ouro | 24 | 24 | 841 | 6883 | 8204 | 117s | 1755 |
| 10 | nefarian | 24 | 24 | 6897 | 5332 | 5868 | 197s | 3044 |

# Gate comparison (spec W1-G2 section 4; the director decides, nothing was retuned)

| gate | before | after | verdict |
|---|---|---|---|
| D3 win rate at pace 0.6 in 55-85 % | first 47 %, hold 50 % | first 70 % (52-83), hold 80 % (63-90) | inside |
| D5 win rate at pace 0.6 <= 25 % | first 3 %, hold 7 % | first 13 % (5-30), hold 13 % (5-30) | inside |
| median HP at fight end 40-75 % (D3, pace 0.6, won fights) | first 56 %, hold 58 % | first 69 %, hold 72 % | inside, near the top |

Other rows worth a look: D4 at pace 0.6 first 20 % -> 33 %, hold 10 % -> 30 %; the casual pace 0.9 moves from 0-3 % wins to
53 % (first) / 43 % (hold) at D1 and 7 % at D2; D1 and D2 at pace 0.6 are 100 % (first / hold), so the easy rows become
a walk-over for a 0.6 s bot (before: D1 100 %, D2 93 % / 90 %). The spec's "today approx 67 %" for D3 was the critic's
scratch probe; this probe measures 47-50 % on the unchanged code, so the +20 to +30 point move is the number to use.
Waste is large (D3 pace 0.6 about 4.3 k per run, more at D1 / D2: a first-legal-move bot fires heal ults at high HP and
the HoT runs at full HP); a human holds the ult, so the effective heal is higher than the bot shows (spec risk 2).
Under `hold` the share of heal ults fired below 60 % HP is only 29 % at D3: the policy avoids chosen swaps, not
accidental clears by area / row / cone effects that reach the banked gem.
