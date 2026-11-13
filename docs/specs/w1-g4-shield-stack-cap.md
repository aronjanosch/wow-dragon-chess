# Spec: W1-G4 — Shield stacks cap at 3

Status: implemented — awaiting playtest (rev 2 after critic review, 2026-11-13). User (2026-11-13, translated): "Please work through all open points" (this cap
was listed as an open finding with the proposal "cap at 3").
Milestone: W1 Class identity. Track: G.

## Player experience goal

Power Word: Shield (and its class skins) stays the answer to a heavy hit, but it cannot be banked into long
immunity: at most three hits are covered at any time, and the status icon shows that limit.

## Current state (facts)

- `Combat:add_shield_stack` (`core/combat.lua`) adds a stack without limit; a stack blocks one enemy hit of any
  size and never expires (it also carries over to the next fight with the other statuses).
- The Emerald skill (4-match) grants one stack. Measured with the bot (100 seeds, pace 0.6, first legal move):
  one cast prevents one mean hit (D3 about 510 HP, more on higher difficulties because enemy damage scales and
  the shield does not care), more than a Rejuvenation (500 HP, fixed). Data:
  `docs/playtests/data/2026-11-13-w1-g3-probe.md`.
- The bot never banks: stacks held before a cast are 0 in 68 %, 1 in 22 %, 2 in 7–8 %, 3 in 2 %, 4+ in 1 %.
  With a cap the bot's win rate does not move (D3 75 → 75 with cap 3, 74 with cap 2; D4 45 → 44 / 46).
- A player who prefers Emerald 4-matches can bank far more than the bot; nothing stops ten stacks before a boss.

## Changes

1. `Combat.SHIELD_MAX_STACKS = 3`. `Combat:add_shield_stack` at the cap: emits `shield_capped` and returns early
   (no stack, no change to the stored thorns value, no `status_changed`). The cast still scores and plays its
   effect. `Combat.deserialize` clamps stored stacks to the cap. Add `shield_capped` to the event list in the
   header comment of `core/combat.lua`.
2. Text: the template in `core/abilities/emerald.lua` gets the number field `shield_max = 3` (number fields fill
   placeholders, skins inherit it) and the description "Shield: blocks the next enemy attack (up to {shield_max}
   stacks)". A test asserts `shield_max == Combat.SHIELD_MAX_STACKS`.
3. View (`ui/fight_view.lua`): on `shield_capped` float "Shield max" on the player with the existing
   `_pop_player` (the path "Heal blocked" uses), info colour, rate-limited like `HEAL_BLOCK_GAP`. No change to
   the status icon, no new art.
4. Tests: `combat_test.lua` (cap, event, no thorns change at the cap, snapshot clamp), `ability_test.lua` /
   `class_test.lua` (text, placeholder resolves for every skin), a view test for the float and its rate limit.
   Docs: `docs/design/abilities.md`, `combat.md`, `classes-and-abilities.md`, `DECISIONS.md`, `CHANGELOG.md`.

## Critic findings addressed (2026-11-13)

No cheap status-icon cue exists (the icon pops only on gain / loss) → the float goes through `_pop_player` with a
gap limit; the "3/3" idea is dropped. Thorns at the cap was undefined → early return, nothing changes. Text via
a plain number field instead of `text_extra` (no load-order dependency on Combat). Deserialize is the only other
path that sets stacks → clamp. Carry-over between fights is real and stays: the count cap already limits it to
three hits; dropping carry-over would waste stacks a normal player earned late in a fight.

## Alternatives considered

- **Do nothing:** the measured balance is fine for a non-banking player; the risk is only the deliberate bank.
  Lost because the cap costs the normal player nothing (measured) and closes the hole before a guide finds it.
- **Stacks expire after N seconds:** a second timer to read on the HUD; a count limit is simpler to see.
- **A stack absorbs up to X damage instead of one hit:** changes the spell's identity (it is the answer to the
  big hit) and the W1-G3 matchups.
- **Cap 2:** also neutral for the bot, but punishes the natural case "two 4-matches in one cascade plus one
  held" more often (6–8 % of casts already sit at 2).

## Why this could be wrong

- A cast at the cap is wasted and may feel bad; the "Max" float has to make that readable.
- Three free hits before Nefarian are still strong; if banking stays the best opening, lower the cap or stop
  the carry-over between fights.

## Non-goals

No change to what a stack blocks, to Fire Shield, or to enemy values.

## Tests / acceptance

- `tools/checks.sh` green; probe (100 seeds, D3 / D4) within noise of the current values.
- User playtest: banking stops at three and the game says so.
