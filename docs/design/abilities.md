# Abilities overview and rules

> **Renamed (2026-10-04, in code since W0-G2c):** the 12 abilities have canonical WoW spell names (Freeze → Frost Nova, Area Clear → Arcane Explosion, …) and become effect templates with class-tagged spell variants — see [classes-and-abilities.md](classes-and-abilities.md). The old Godot names below are the same effects.

Reference for the **implemented, playtested** state (audited 2026-09-27). Numbers live in code/data:
per-ability knobs are `@export`s in `scenes/abilities/<color>/*.gd` (defaults) and `*.tres` (damage,
score). If this file and the data disagree, the data wins — update this file.

## General mechanics

- **Spawn tiers:** a 4-match spawns a **skill** gem, a 5+-match spawns an **ult** gem, 3-matches spawn
  nothing. L / T / + shapes count as one match (3 across + 3 down sharing a gem = 5 → ult).
- **Region matching (M0-G5):** a connected same-colour region of runs ≥ 3 is one match and spawns
  one gem by its size, so two touching parallel 4-rows give 1 ult (8) and a Convert / Color Swap
  flood gives one "N-MATCH" ult per region (see `docs/specs/m0-g5-region-match.md`; replaces the
  B.12 carving).
- **Spawn position:** the swapped-in gem if it is part of the match, otherwise the match gem closest
  to the match center (cascades).
- **Activation:** matching an ability gem (with its own color) triggers it. An ability gem hit by
  another ability's clear also triggers (**chain**). Freshly spawned ability gems are protected from
  matches/hits until the board settles; a player swap lifts that protection.
- **Queue:** triggers run FIFO, one at a time; cascades wait until queued abilities finish.
- **Damage:** every cleared gem deals 10 damage (×1.5 if the enemy is weak to that color, × damage
  debuffs, rounded). Junk deals 0. (×10 economy since M1-G1.)
- **6/7-match bonus:** ×1.2 (6) / ×1.5 (7+) on the **direct damage** of ability gems triggered by that
  match. It does not boost the ult spawned by the match or the per-gem clear damage.
- **Swap partner:** "partner color" = color of the gem swapped with. Without a swap (chain/cascade), a
  random other color on the board is used.

## Abilities by color

| Color | Tier | Ability | Effect | Direct dmg |
|---|---|---|---|---|
| **Ruby** | skill | **Flamestrike** (was Fire Wave; `fire_wave` → `flamestrike`) | Cone of fire widening toward the enemy side, clears gems in it | 150 |
| | ult | **Fire Shield** (`fire_shield`, unchanged) | 12 s (W1-G3, was 10 s): blocks every enemy hit and reflects its full damage +100 (`reflect_bonus`, one number). Recast resets timer | — |
| **Sapphire** | skill | **Arcane Explosion** (was Area Clear; `area_clear` → `arcane_explosion`) | Clears 3×3 around the gem; delays next enemy attack by +2 s | 150 |
| | ult | **Frost Nova** (was Freeze; `freeze` → `frost_nova`) | Freezes enemy 5 s (overlapping stuns keep the longer one) | 500 |
| **Topaz** | skill | **Whirlwind** (was Row Clear; `row_clear` → `whirlwind`) | Clears the full row, sweeping outward from the gem | 150 |
| | ult | **Chain Lightning** (was Color Chain; `color_chain` → `chain_lightning`) | Clears every gem of the partner color | — |
| **Amber** | skill | **Rejuvenation** (`rejuvenation`, W1-G2; replaces Drain Life / lifesteal) | Heal over time: 5 % of max HP (500) in 10 ticks, one per second, first tick 1 s after the cast, no clears needed. A cast while it runs adds 10 ticks (cap 20, the tick timer is not restarted, the rate never doubles). Heal Block: the tick heals 0 and is consumed | — |
| | ult | **Lay on Hands** (`lay_on_hands`, W1-G2; replaces Polymorph / convert) | Instant heal of 15 % of max HP (1500), capped at max, 0 under Heal Block | — |
| **Amethyst** | skill | **Hammer of Justice** (was Stun; `stun` → `hammer_of_justice`) | Stuns enemy 3 s | 200 |
| | ult | **Mind Control** (was Color Swap; `color_swap` → `mind_control`) | All gems of the partner color → Amethyst (ability gems keep their tier; bombs/junk skipped). One colour per chain; flood regions spawn at most a skill (see below) | — |
| **Emerald** | skill | **Power Word: Shield** (was Shield; `shield` → `power_word_shield`) | +1 shield stack; each stack blocks one enemy hit (Fire Shield is checked first) | — |
| | ult | **Rain of Fire** (was Bombs; `bombs` → `rain_of_fire`) | 5 random gems become bombs. A bomb keeps its color, triggers when matched with that color, clears 3×3 | 50 per bomb |

Mind Control (Amethyst) adds no ability damage; damage comes only from the resulting clears. The Amber abilities are heals
(no damage, no RNG draw). `Combat:heal_player(amount, source, blockable)` emits `player_healed(amount, source)` with
source `hot` / `ult` / `boss` and `heal_lost(amount, reason, source)` for the part that did not land (`overheal`, `block`;
never for the boss heal, which ignores Heal Block). `sim:convert_random_gems` stays (debug panel, tests) but no ability uses it.
The HoT is the player status `hot` (renamed from `lifesteal`): one chained Clock timer on gameplay time (frozen by the
pause, `settle_now` and the between-fight beat, carried into the next fight, no heal once the run is lost); tick k of a
10-tick cycle heals `round(T*k/10) - round(T*(k-1)/10)` (T = 5 % of max HP), so a cast sums to exactly T. Serialized as
remaining, max, ticks left, cycle phase, interval, ticks per cycle, T, granted ticks.

**Mind Control rules (M1-G8, #29):**
- **One colour per chain (A):** every Color Swap that fires before the board next settles converts
  the same partner colour. The first one picks it (swap partner, or a random other colour for
  cascade activations); later ones reuse it and convert whatever gems of that colour have refilled
  since. Tracked in `battle_controller.chain_convert_color`, reset on `board_settled` and at fight
  start.
- **Flood regions spawn at most a skill (F):** Color Swap calls
  `board.convert_color(partner, AMETHYST, mark_converted = true)`. Converted gems carry
  `Gem.convert_marked` (board-generic flag, no visual); a match region containing ≥ 1 marked gem
  spawns at most a skill (`board.spawn_tier_for_region`) instead of an ult. Marks clear on settle.
  Converted ult gems keep their tier and still fire (Dota parity).
Each ability record in `core/abilities/*.lua` also carries `template` (= its canonical id) and an empty `variants = {}` (W1 fills class-tagged spell variants).

Every skill activation scores 150, every ult 450, bombs 0 (see [scoring.md](scoring.md)).

**Banner text is value-driven (M1-G1):** `blurb` / `description` on each ability `.tres` use
`{property}` placeholders (e.g. `Reflect attacks — {fire_shield_duration}s`, `{damage} dmg`),
filled from the ability's own exports by `PlayerAbility.get_blurb()` / `get_description()`.
Derived values: `{bomb_damage}` (Bombs, from `BOMB_DAMAGE`), `{clear_size}` (Area Clear).
Abilities run from per-run copies (`RunManager.run_kits`, see [run.md](run.md)).

**Boon knobs (M1-G2):** exports whose defaults keep the table above unchanged; only boons
([boons.md](boons.md)) change them on the run copies.

| Ability | Export (default) | Boon |
|---|---|---|
| Fire Shield | `reflect_multiplier` (1.0) — reflected damage = hit × this, then `reflect_bonus` (100, W1-G3, addon only) is added | Backdraft |
| Row Clear | `clear_column` (false) — also clear the gem's column | Crossfire |
| Color Chain | `target_most_common` (false) — hit the most common other colour | Lightning Rod |
| Color Chain | `delay_per_8_gems` (0) — enemy attack delay per 8 gems cleared | Surge |
| Stun | `special_multiplier` (1.0) — stun × this if the next intent is special | Interrupt |
| Shield | `thorns_damage` (0) — damage to the enemy per blocked hit | Thorns |

Run flag `bombs_trigger_adjacent` (Wildcard Bombs): bombs also go off when an orthogonally
adjacent gem clears (board property, set per fight by `game.gd`).
Run flag `stun_ability_damage_bonus` (Hex, float 0.3): read by `battle_controller` at fight start;
see [boons.md](boons.md).

## Open design notes

- Original draft wanted Emerald bombs to be **multicolor wildcards** (activate with any color). M1-G2
  answers it with the cheaper Wildcard Bombs boon (adjacent trigger). The full "matches with any
  colour" version would need region-matching changes; revisit if the boon feels weak.
- Fire Shield: the original draft had 15 s, playtest 4 had 10 s; W1-G3 (2026-11-13) is 12 s with +100 per reflected hit: most enemy cycles are longer than 10 s, but 15 s moved the 100-seed probe too far (D3 71 → 84 %, D4 37 → 55 %; 12 s: 75 % / 45 %).
