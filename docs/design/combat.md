# Combat — current state

Audited 2026-09-27 (after M0-G1). Code: `scenes/board.gd`, `scenes/battle_controller.gd`,
`scenes/enemies/enemy.gd`, `scenes/board_input.gd` (player input), `scenes/ui/fight_fx.gd`
(fight FX), `scenes/game.gd` (HUD glue).

## Board

- 8×8 grid, 6 colours (Amber, Amethyst, Emerald, Ruby, Sapphire, Topaz; index order 0–5).
  Each colour has a distinct gem shape (colour-blind readability).
- **Real-time, continuous:** no turns. Any SETTLED gem can be swapped at any time, including
  while other parts of the board cascade. Gem states: SETTLED / SWAPPING / FALLING / CLEARING.
- **Input:** drag toward a neighbour (commits past ~28 % of a cell, auto-commits past ~52 %) or
  click-select + click-neighbour. A swap is valid only if it creates a match involving one of the
  two swapped gems; otherwise the gems swap back with a reject sound. All input lives in
  `scenes/board_input.gd` (`BoardInput` node in `game.tscn`): `can_player_swap()` is the gate
  (`""` or `game_over` / `not_in_fight` / `stunned`) and `try_swap(a, b)` the single swap entry
  point (`ok` / gate reason / `not_adjacent` / `unsettled`). A press needs the full gate; a tap
  release only re-checks game over / fight over, and a drag commit doesn't re-check (it was
  checked at press) — so a stun landing mid-press doesn't cancel that press.
- **Resolution** runs in passes: find matches → emit damage → fuse animation → ability queue
  drains → gravity + refill → next pass (cascade depth +1). One pass at a time for the whole board.
- **Region matching (M0-G5):** maximal runs ≥ 3; all runs of one colour that share a cell or
  touch orthogonally merge into **one match** (a connected region: L/T/+, parallel lines, solid
  floods — Dota's "29-MATCH"). Same-colour gems next to a region but in no run ≥ 3 stay on the
  board. Spawn-protected gems are not matchable and split regions.
- **Spawn:** one ability gem per match, tier from the region size: 4 → skill gem, 5+ → ult gem, at
  the swapped-in gem (else the match gem nearest the centre). Fresh ability gems are spawn-protected until the board settles (a player
  swap lifts it). When protection lifts on settle, any line it was blocking resolves like a
  normal cascade (damage, ability fires).
- **Idle hint:** after 6 s without player action a matchable gem wiggles.
- **No moves left:** the board reshuffles plain gems.

## Damage (player → enemy)

- Every cleared gem = **10 damage** (`GEM_DAMAGE`), ×1.5 if the enemy is weak to that colour,
  × curse multiplier, rounded per colour group per wave (exact at ×10: weak 3-match 45, weak single
  15, cursed single 7). Junk deals 0. All HP/damage numbers were scaled ×10 in M1-G1.
- Ability direct damage (e.g. Freeze 500) is scaled by the 6/7-match multiplier (×1.2 / ×1.5) of
  the match that triggered it, then by weakness/curse. An ability gem caught in a big region uses
  the region size (a flood of 7+ → ×1.5, capped).
- Bombs: 50 damage (`BOMB_DAMAGE`) + 3×3 clear.
- Every damage packet applied to the enemy also emits `battle.damage_dealt(amount, gem_type, source)`
  (source `match` / `ability` / `bomb` / `reflect` / `thorns` / `other`) for the agent event log.

## Ability queue

Triggered abilities run FIFO, one at a time. Match cascades wait until the queue is empty.
Ability clears can hit other ability gems → **chain** activation (queued).

## Player statuses

| Status | Source | Effect | HUD |
|---|---|---|---|
| Shield (stacks) | Emerald skill | Blocks one enemy hit per stack, at most 3 (W1-G4: a cast at the cap changes nothing, emits `shield_capped`, the HUD floats "Shield max"; stored stacks are clamped on load) | icon + count |
| Fire Shield (timed) | Ruby ult | Blocks and reflects every hit (+100 each, 12 s) | icon + ring |
| Heal over time `hot` (timed) | Amber skill (Rejuvenation) | 500 HP over 10 s, one tick per second; extendable to 20 ticks | icon + countdown ring, green aura |
| Curse (timed) | Anubis | Outgoing damage ×0.7 | icon + purple HP bar + drip |
| Stun (timed) | Stagger (`StunAbility`: Club Smash, Stone Gaze, Thunderclap, Typhon Roar) — only when the hit reached HP | Input locked, board keeps resolving | overlay "STUNNED" |
| Heal block (timed) | `HealBlockAbility` (Rend, Weighing of the Heart, Corpse Rot) | Player healing ×0 (HoT ticks and the heal ult heal nothing; the boss heal is not blocked) | grey icon + dark HP bar (wins over the curse tint), grey "0" ticks |
| Sandstorm (timed) | `BoardSlowAbility` (Sphinx, Apep) | Falls take 1/factor as long (×0.3 → 3.3× slower, cap included); swaps not slowed | sand icon + sand tint over the board |

Order when hit: Fire Shield (reflect) → Shield stack → HP. `battle.take_damage` returns where the
hit ended (`"reflect"` / `"shield"` / `"hp"` / `"none"` when the fight is over or in god mode); a
stagger stuns only on `"hp"`. **True damage** (Mirror Shield reflect) skips Fire Shield and shield
stacks and goes straight to HP; it can kill the player during an ability drain — the drain then
drops the rest of its queue. `player_damaged(amount, source)`: source `hit` (enemy attack) or
`mirror`. Heal block, Sandstorm and the curse are cleared at fight start. Boons can scale the reflect (Backdraft) and make shield blocks hit back (Thorns), see [boons.md](boons.md).

## Enemy side

- Attack rotation on a timer (`AttackTimer`); the attack queue under the monster shows the next
  3 intents (normal vs special chrome).
- Enemy statuses: stun (Amethyst), freeze (Sapphire ult), slow window (Sapphire skill delays the
  next attack +2 s). Stun/freeze pause the attack timer; overlapping stuns keep the longer one.
  Shown on `EnemyStunIcon`; M1-G9 buffs on the second icon `EnemyBuffIcon` (Mirror wins over Aegis).
- **Divine Aegis** (spell immunity, M1-G9): damage with source `ability` / `bomb` deals 0 (grey
  "IMMUNE", no damage_dealt, no change to healing); player stun / freeze and the cosmetic slow window
  don't apply ("IMMUNE" for stun / freeze). Still work: match damage, Fire Shield reflect, thorns,
  `delay_attack` (Area Clear / Surge). Gold enemy tint.
- **Mirror Shield** (M1-G9): while up, `round(packet × reflect_fraction)` of every `ability` / `bomb`
  packet the enemy takes is dealt to the player as true damage; the enemy still takes the full
  packet. Nothing is reflected from the packet that kills the enemy or once the fight is over.
  Match-source damage cracks it: `break_damage` cumulative match damage in the window shatters it
  and stuns the enemy `break_stun` s (ignored while immune). Silver enemy tint.
- The source rules live in `battle_controller.gd` (both damage paths: `on_gems_cleared`,
  `deal_damage_to_enemy`); `enemy.take_damage` has no source.
- Enemy ability types: see [enemies.md](enemies.md).

## Pause behaviour

- Sandstorm's window ticks in `board._process`, so the gameplay pause and the tree pause both
  freeze it; heal block ticks in `battle._process` like the other player statuses.

- Menu pause (Esc, B.14) = `get_tree().paused`; all gameplay timers use `process_always = false`.
- Agent step mode (M0-T1, `AgentBridge`, debug builds only) also freezes via `get_tree().paused`;
  the pause menu ignores Esc while it is on. See `docs/agent-playtesting.md`.
- Gameplay-beat pause (boss heal, between fights, debug F10) = `battle.pause_gameplay()` /
  `board.pause_gameplay()` (process disabled), separate from the menu pause.
