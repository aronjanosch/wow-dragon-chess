# Spec: W1-G3 — Longer reflect window, fast attackers, ability × enemy matchups

Status: implemented — awaiting playtest (agreed 2026-11-13, rev 2; user: "passt"). **Duration shipped as 12 s, not 15 s:** the 100-seed probe showed 15 s makes D3 / D4 clearly easier (71 → 84 %, 37 → 55 %); 12 s is the fallback named below (75 % / 45 %). Data: docs/playtests/data/2026-11-13-w1-g3-probe.md.
Milestone: W1 Class identity. Track: G.
User request (2026-11-13): "Raise the duration of Thorns or Fire Shield etc. a bit. And let's also make
enemies that have somewhat higher attack speed, so that Thorns is more effective. […] Also put a bit of time into
mechanics and how the abilities interact with the enemy design."

## Player experience goal

The Ruby ultimate (Fire Shield and its skins: Thorns, Retaliation, Retribution Aura, …) is worth a 5-match in every
fight: against fast attackers it reliably eats and returns several hits, against slow heavy hitters it is a timing
shot that returns one big hit. Enemies differ in attack rhythm, so which defensive spell is best changes from fight
to fight.

## Current state (facts)

- Fire Shield (`core/abilities/ruby.lua`, `fire_shield_duration = 10.0`): for the duration every enemy hit is
  nullified and its full damage dealt back (`Combat:take_damage`, `core/combat.lua`, `reflect_multiplier = 1.0`).
  It does **not** reflect a flat amount: the return equals the hit. All eight class skins are the same template
  (`core/classes.lua`), so one value serves every class.
- Every enemy ability is slowed by `Run.ATTACK_PACE = 2.2` (`core/run.lua`: cooldown × 2.2, damage × 2.2 × 0.9;
  playtest 4: "fewer, harder attacks"). One attack = cooldown + wind-up 0.67 s.
- Measured (throwaway script, difficulty 1, cast at a random moment; "miss" = the window catches no hit):

  | Enemy | rotation cycle | 10 s: miss / hits / reflected | 15 s: miss / hits / reflected |
  |---|---|---|---|
  | Hellhound | 6.2 s | 0 % / 1.6 / 450 | 0 % / 2.4 / 675 |
  | Gordok Ogre | 25.5 s | 32 % / 0.8 / 574 | 13 % / 1.2 / 860 |
  | Basilisk Matriarch | 37.9 s | 25 % / 0.8 / 465 | 3 % / 1.2 / 698 |
  | Forest Troll | 39.4 s | 49 % / 0.5 / 335 | 32 % / 0.8 / 502 |
  | Harpy | 21.0 s | 52 % / 2.1 / 403 | 29 % / 3.2 / 604 |
  | Hakkar | 45.6 s | 36 % / 0.7 / 597 | 26 % / 1.0 / 896 |
  | Qiraji Scarab | 25.5 s | 61 % / 0.4 / 178 | 41 % / 0.6 / 267 |
  | Anubisath Sentinel | 48.2 s | 59 % / 0.4 / 373 | 45 % / 0.6 / 561 |
  | Ouro | 39.4 s | 75 % / 0.3 / 251 | 62 % / 0.4 / 377 |
  | Nefarian P1 / P2 / P3 | 26.6 / 45.3 / 37.2 s | 25 / 34 / 73 % miss | 0 / 2 / 60 % miss |

  A 10 s shield cast without timing does nothing in a quarter to three quarters of the casts against most enemies.
  For comparison the other ultimates always pay: Frost Nova 500 damage + 5 s freeze, Lay on Hands 1500 HP.
- Balance probe (`tools/balance_probe.lua`, 30 seeds, pace 0.6, policy `first`), 10 s → 15 s: D1 30/30 → 30/30,
  D3 21/30 → 22/30, D5 4/30 → 6/30. Inside the noise; the longer window does not break the difficulty curve.
- Enemy phases (`hp_fraction` + `rotation`, `core/enemy.lua`) are generic, not boss-only (unverified for the HUD
  phase banner on a non-boss).

## Changes

### 1. Fire Shield lasts 15 s (was 10 s)

`fire_shield_duration = 15.0` in `core/abilities/ruby.lua`. Texts use the `{fire_shield_duration}` placeholder and
follow. Applies to all skins.

### 2. Bonus damage per reflected hit

New template field `reflect_bonus = 100` on Fire Shield (all skins, no rule split): every reflected hit deals the
hit's damage **plus 100**. `Combat:apply_fire_shield(duration, multiplier, bonus)`; the bonus is part of the one
reflected number (event `attack_reflected`, source `reflect`). It does not scale with difficulty. Effect: a 15 s
window against a fast enemy (3–4 hits) returns 300–400 more, against a bruiser (1–2 hits) 100–200 more. Description:
"Nullifies enemy attacks and reflects the damage +{reflect_bonus} back for {fire_shield_duration}s".
(User decision, see open decision 1.)

### 3. Fast attackers (data only, `data/enemies.lua`)

No new scaling concept: the base cooldown and damage of the abilities change, the global pace stays. Final values =
base cooldown × 2.2 (+ 0.67 s wind-up), base damage × 1.98 (difficulty 1).

**DPS rule:** DPS of a rotation = average damage per cycle / (sum of final cooldowns + 0.67 s per ability + expected
execute time), at difficulty 1. Each changed enemy stays within ±2 % of today's value (hard-coded in the test).

| Enemy (fight) | Today (DPS) | New base values | New result |
|---|---|---|---|
| Hellhound (1-1) | bite 120–160, cd 2.5: one hit of ~277 every 6.2 s (44.9) | bite 75–95, cd 1.4 | ~168 every 3.75 s (44.9) |
| Harpy (2-2) | flurry 80–110 × 4–5, cd 9: ~847 every 21.0 s (40.3) | new `harpy_rake` "Talon Rake" (plain, 70–92, cd 1.6); flurry 52–72 × 4–5, cd 5.5; rotation rake, rake, flurry | two rakes of ~160 (4.2 s apart), then a flurry of ~552; cycle 21.7 s (40.3) |
| Qiraji Scarab (3-1) | web cd 6, bite 200–260 cd 5: one hit of ~455 per 25.5 s (17.8) | bite 70–89, cd 1.6; rotation web, bite, bite, bite | web every 26.4 s, three bites of ~157 (4.2 s apart) (17.9) |

Three of ten fights are fast; Nefarian's phase 2 already has a flurry. The bruisers (Ogre, Sentinel, Ouro, Hakkar)
and the Forest Troll stay as they are. The overlap invariant holds (wind-up 0.67 + longest execute 0.6 < smallest
base cooldown 1.4).

### 4. Matchup table in the design doc

`docs/design/wow-addon.md` (or `docs/design/roster.md`) gets the intended matchups, so later enemy work keeps them:

| Enemy rhythm | Strong | Weak |
|---|---|---|
| Fast, small hits (Hellhound, Harpy, Scarab) | Fire Shield (many hits returned), Rejuvenation (steady damage, little overheal) | Power Word: Shield (one stack per small hit), stun / freeze (delays one small hit) |
| Slow, heavy hits (Ogre, Sentinel, Ouro) | Power Word: Shield (a stack eats a big hit), stun / freeze / Arcane Explosion delay on the special, Fire Shield as a timed shot | untimed Fire Shield |
| Spell-punishing (Mirror, Aegis) | matches, shields | damage ultimates into the mirror |

### 5. Tests and docs

- `enemy_data_test.lua`: the generated Godot golden file (`test/golden_enemies.lua`) stays untouched. The golden
  comparison gets an explicit list `W1_OVERRIDES` (hellhound, harpy, qiraji_scarab) whose changed fields are pinned
  to the new values in the test itself; everything else still compares against the golden. New case: the DPS rule
  above (old values hard-coded). The overlap invariant keeps running over all data.
- `enemy_stub_test.lua` (pins Hellhound 120–160 / 2.5) and whatever `fight_bot_test.lua` derives from it: new values.
- `combat_test.lua` / `ability_test.lua` / `class_test.lua`: duration 15, reflect = hit + bonus (one number, also
  per flurry hit), texts.
- Balance probe before / after, report to `docs/playtests/data/`.
- `docs/design/*` (enemy values, Fire Shield, matchups), `docs/DECISIONS.md`, `CHANGELOG.md`.

## Alternatives considered

- **Flat-only reflect per hit (WoW's Thorns):** would make the ult near useless against the bruisers and split the
  Druid's rule from the other seven skins (skins may not change rules, W1-G1). Lost; the bonus on top (change 2)
  is the form that works for all skins.
- **A per-ability `pace` field:** a second scaling concept for three enemies; editing the base values is plain data.
- **Forest Troll "Berserking" phase below 35 % HP (in rev 1):** a faster rotation would bring Rend's 15 s heal
  block to near-permanent uptime (kills the Amber heals), dropping Regenerate makes the phase easier, and nothing
  on screen keeps showing "fast" after the 1.6 s banner. Moved out; an enrage needs a persistent status cue (own
  item).
- **Only raise the duration:** fixes the average, but against 40 s cycles even 15 s misses often; without fast
  enemies the ult has no fight where it clearly shines.
- **Lower the global attack pace:** undoes the playtest-4 decision (fewer interruptions) for every fight.
- **New enemies in a pool (random per ladder slot):** more variety, but needs models, sounds, records per pool and
  a bigger probe; later item (roadmap W1/W3).

## Why this could be wrong

- Playtest 4 asked for fewer, harder attacks. Three fast fights bring frequent small hits back; if they annoy, the
  first knob is their base cooldown (1.4–1.6 → 2.0, damage up to match).
- Hellhound is the first fight and a new player's first impression; a hit every 3.7 s may feel hectic. Fallback:
  leave Hellhound as is.
- A timing player gets more than the untimed probe shows. Best case of one cast (reflected damage, share of the
  enemy's HP, difficulty 1, before the bonus): Hakkar 2178 (29 %) and Ogre 1464 (39 %) already at 10 s today;
  15 s adds only Hellhound (25 → 37 %) and Nefarian phase 2 (10 → 17 %, the window now spans flurry + Veil);
  12 s would already add Troll (16 → 26 %), Sentinel (24 → 36 %) and Nefarian phase 1. So the long window mostly
  removes misses; the ceiling was high before. If Nefarian phase 2 becomes "hold the Ruby ult", fall back to 12 s.
- Power Word: Shield gets weaker in fast fights (a stack eats ~165 instead of ~277). Intended contrast, but Emerald
  may feel bad there.
- The bonus is a flat number in a game whose enemy values scale with difficulty: at D5 it matters less. Accepted.

## Critic findings addressed (2026-11-13)

Golden / stub tests pin the enemy data → override list in the test, golden file untouched (change 5). "DPS ±5 %"
was undefined and the rev-1 cadences did not reach it → DPS formula + exact base values, ±2 % (change 3). Troll
berserk collides with the Amber heals and has no lasting cue → removed. Always-hold risk on bosses → measured the
timed best case (above): the ceiling exists at 10 s already; fallback 12 s named. "More effective against fast
enemies" is not met by speed alone (reflect = enemy DPS × duration) → `reflect_bonus` (change 2), left to the user.
`pace` field → dropped for plain data edits.

## Non-goals

No new enemies, no class twists, no change to stun / freeze / heal values, no change to the global attack pace,
no new status or HUD element.

## Tests / acceptance

- `tools/checks.sh` green.
- Probe: win rates per difficulty within the 95 % interval of the current values.
- User playtest: Fire Shield feels worth it; fast fights feel different, not annoying.

## Open decisions

1. Bonus per reflected hit (change 2)? **Yes, +100** — without it fast enemies only make the ult reliable, not
   stronger. Alternative: leave it out and judge after the playtest.
2. Hellhound fast in fight 1? **Yes, with the fallback above.**
