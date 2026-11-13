> **Not in the WoW addon scope (2026-10-04).** Kept as design record of the Godot roguelite layer; re-import candidate after W2.

# Boons — current state

Implemented in M1-G2 (spec ../specs/m1-g2-boon-draft.md), awaiting
playtest. Code: `scenes/boons/`, `RunManager.run_boons` / `run_flags` / `pick_boon`,
`scenes/ui/draft_screen.*`, `game.gd._run_draft()`. If this file and the `.tres` data disagree, the
data wins — fix this file.

## When

- After every **won normal fight** (6 per run: 2 per stage in stages 1–3). No draft after a boss
  (boss heal moment instead) or after the World Dragon.
- Flow: CLEARED sting → draft screen → next enemy spawns. Gameplay stays paused
  (`battle.pause_gameplay`, set on the kill) while the screen is up, so carried-over cascades and
  spells resume against the next enemy after the pick.

## Draft screen

- 3 cards (fewer only when the pool runs dry): patron colour + gem shape, patron name, boon name,
  one-line summary with the **real values for this run** (effects applied to a throwaway copy of the
  current run ability). The boon kind is **not** shown (telemetry only).
- **Rest**: heal 10 % of max HP (capped; `RunManager.REST_HEAL_PERCENT`). Always available.
- **Next enemy**: name, weakness colour, its first 3 attack intents (attack-queue icons,
  `AttackQueue.show_intents`).
- Input: click, or keys `1` / `2` / `3` / `R`. Pausable (the pause menu freezes it).
- Owned boons: listed in the pause menu (name — summary; summary values shown from the base kit).
- Agent harness: screen `draft`, `set_choices("draft", …)` with ids = boon ids + `rest`;
  `choose("draft", id)`; the snapshot gets `draft {offer, rest_heal, next_enemy}` while open and
  `boons` (owned ids) always.
- Telemetry: `draft_offer {options: ids, kinds}` on open, `draft_pick {id, skipped, decision_seconds}`
  on pick (Rest = id `rest`, `skipped: true`; decision time excludes pause-menu time).

## Offer rules (`scenes/boons/draft_rules.gd`, stream `RunManager.rng_draft`)

1. 3 options from **3 different patrons**: uniform among patrons that still have unowned boons,
   then uniform within the patron.
2. Fewer than 3 patrons left → fill the remaining slots with other unowned boons from any patron.
   Fewer than 3 unowned boons in total → show what's left.
3. Owned boons are never offered. Same seed + same picks → same offers.

## Data model

- `boon.gd` (Resource, one `.tres` per boon in `scenes/boons/<patron>/`, all listed in
  `scenes/boons/pool.tres`): `id`, `display_name`, `patron` (gem_type), `kind`
  (TWEAK / SHAPE / TRADE_OFF / SETUP), `summary` (≤ 44 chars rendered), `icon`, `effects`.
- Summary placeholders: `{<property>}` = value after the boon, `{<property>_from}` = before
  (derived ones too, e.g. `{clear_size}`), `{value}` = the first effect's raw value.
- `ability_param_effect.gd`: `gem_type`, `tier`, `property`, `op` ADD / MUL / SET, `value`.
  Int exports are rounded on write (`roundi`); bools accept SET only. Writes to the run-kit copy
  (`RunManager.get_run_ability`) only — never the cached `.tres`.
- `run_flag_effect.gd`: `RunManager.run_flags[flag] = value`. `game.gd.start_fight()` passes flags
  to the board (`board.bombs_trigger_adjacent`); the board never reads RunManager.
- `start_run()` resets `run_boons`, `run_flags` and rebuilds the kit copies.
- Tweaks that can stack with a trade-off on the same knob use MUL so the order doesn't matter
  (Eternal Flame × Backdraft = 7.5 s, Bloodthirst × Blood Pact = 6 s).

## The 18 boons

| Patron | Boon (id) | Kind | Effect (data) | Card text at base |
|---|---|---|---|---|
| Ruby — Sekhmet | Wildfire (`wildfire`) | SHAPE | Fire Wave `cone_spread` MUL 2 (0.4 → 0.8) | Fire Wave cone 2× as wide |
| | Backdraft (`backdraft`) | TRADE-OFF | Fire Shield `fire_shield_duration` MUL 0.5, `reflect_multiplier` SET 3 | Fire Shield 5s, reflects ×3 |
| | Eternal Flame (`eternal_flame`) | TWEAK | Fire Shield `fire_shield_duration` MUL 1.5 | Fire Shield 10s → 15s |
| Sapphire — Skadi | Avalanche (`avalanche`) | TRADE-OFF | Area Clear `clear_radius` SET 2, `damage` SET 0 | Area Clear 5x5, no direct damage |
| | Cold Snap (`cold_snap`) | TRADE-OFF | Area Clear `attack_delay` SET 4, `damage` SET 0 | Area Clear delays 4s, no direct damage |
| | Permafrost (`permafrost`) | TWEAK | Freeze `stun_duration` ADD 2 | Freeze 5s → 7s |
| Topaz — Zeus | Crossfire (`crossfire`) | SHAPE | Row Clear `clear_column` SET true (`board.clear_cross`) | Row Clear also clears the column |
| | Lightning Rod (`lightning_rod`) | TRADE-OFF | Color Chain `target_most_common` SET true | Color Chain hits the most common color |
| | Surge (`surge`) | SETUP | Color Chain `delay_per_8_gems` SET 1 | Color Chain delays enemy 1s per 8 gems |
| Amber — Anansi | Brood (`brood`) | TWEAK | Convert `convert_count` ADD 6 | Convert 10 → 16 gems |
| | Blood Pact (`blood_pact`) | TRADE-OFF | Lifesteal `lifesteal_percent` SET 250, `lifesteal_duration` MUL 0.4 | Lifesteal heals 250%, lasts 4s |
| | Bloodthirst (`bloodthirst`) | TWEAK | Lifesteal `lifesteal_duration` MUL 1.5 | Lifesteal lasts 10s → 15s |
| Amethyst — Hecate | Interrupt (`interrupt`) | SETUP | Stun `special_multiplier` SET 2 | Stun lasts ×2 if a special is next |
| | Hex (`hex`) | SETUP | run flag `stun_ability_damage_bonus` = 0.3 (float) | Stunned foes take +30% ability & bomb dmg |
| | Long Night (`long_night`) | TWEAK | Stun `stun_duration` MUL 1.5 | Stun 3s → 4.5s |
| Emerald — Athena | Wildcard Bombs (`wildcard_bombs`) | SHAPE | run flag `bombs_trigger_adjacent` = true | Bombs also go off when a neighbor clears |
| | Thorns (`thorns`) | SETUP | Shield `thorns_damage` SET 300 | Each shield block deals 300 damage |
| | Munitions (`munitions`) | TWEAK | Bombs `bomb_count` ADD 3 | Bombs ult: 5 → 8 bombs |

12 of 18 are SHAPE / TRADE-OFF / SETUP. No boon adds ability damage to the convert ults.

## Mechanics behind the new knobs

- **Backdraft** — `battle.take_damage` reflects `hit × fire_shield_reflect_multiplier` (set on each
  Fire Shield cast; a base cast resets it to 1).
- **Crossfire** — `board.clear_cross(row, col)`: row + column, nearest cells first, row and column
  sweep beams.
- **Lightning Rod** — targets the colour with the most gems (own colour excluded, ties → lower
  gem_type) instead of the swap partner.
- **Surge** — after the chain: `floor(cleared / 8) × delay_per_8_gems` s added to the enemy's
  attack timer, shown as the same SLOWED state Area Clear uses.
- **Interrupt** — stun × `special_multiplier` when `enemy.peek_next_ability().is_special_intent()`.
- **Hex** (M1-G8, replaced Twin Nether, #30) — while the enemy is stunned or frozen (any
  source), damage whose source is `ability` or `bomb` (ability direct damage and ability / bomb
  clears) is × (1 + `stun_ability_damage_bonus`) = ×1.3, before weakness / curse
  (`battle_controller.hex_multiplier`, applied in `_scale_outgoing_damage`, so the damage and the
  `damage_dealt` telemetry match). Match clears (incl. the Color Swap flood) get nothing.
  `RunFlagEffect.float_value` stores the number; `RunManager.run_flag_float()` reads it.
  Readable as: Hex-boosted enemy damage popups are purple and punch (declared exception to the
  presentation freeze).
- **Wildcard Bombs** — a settled bomb orthogonally next to any cleared gem (match wave or effect
  clear) pops with it and activates like a matched bomb (3×3, 50 dmg). One hop per clear; the
  bomb's own 3×3 chains further.
- **Thorns** — each shield-stack block deals `thorns_damage` to the enemy (raw, like reflect: no
  weakness / curse; damage source `thorns`). Stacks carry the value of the newest Shield cast.

## Known risks (check in playtest)

- **Brood (Convert 16) and long convert cascades:** resolved by M0-G5 (#27). The "stuck board" was
  a self-running Amber ult chain (#26: up to 35 % runaway with Brood), not a freeze. Region
  matching + the Convert brake bound it; re-measure with the opt-in `test/chain_stress.gd`
  (`--convert=amber|swap --boons=brood`) after any Convert / Color Swap / Brood change.
