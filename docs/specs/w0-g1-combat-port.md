# Spec: W0-G1 — Combat port (battle, damage, 12 abilities, statuses, minimal HUD)

Status: UI/HUD implemented — awaiting in-game playtest (core + minimal text HUD + Puppy fight wiring, 2026-10-04). AGREED rev 2 (critic review 2026-10-04, user approval 2026-10-04). Depends on W0-T1 (core) and W0-P1 (to see it).
Milestone: W0 Base game port. Track: G.
Pillars served: 3 (two-speed combat), 5 (readable pressure — the data model keeps every status
visible), 2 (all timers in sim time).

## Player experience goal

Matching gems hurts a single enemy that attacks you on a visible rhythm. 4-/5-matches spawn skill
and ult gems; matching them fires the colour's ability, which can chain. It plays like the Godot
fight — same numbers, same decisions — just in a WoW window. (HUD polish is W0-P2; this item can
be verified with a simple text/bar HUD.)

## Current state (facts)

From [../design/combat.md](../design/combat.md), [../design/abilities.md](../design/abilities.md)
and `scenes/battle_controller.gd` (636 lines), `scenes/abilities/<color>/*.gd` (12 scripts):
- Damage: 10 per cleared gem (×1.5 weak colour, × curse, ×1.2/×1.5 for 6/7+ matches on ability
  damage); bombs 50; ability damage is `.tres` data (150 skills, Freeze 500, Stun 200, …).
- Ability queue: FIFO, one at a time, cascades wait until the queue drains; ability clears can
  hit ability gems → chain activations (queued). Partner colour from the swap, random other colour
  otherwise. `chain_convert_color` rule for Color Swap (reset on `board_settled`).
- Player statuses: Shield stacks, Fire Shield (timed, reflect), Lifesteal (timed), Curse, Stun,
  Heal block, Sandstorm (board slow). Hit order: Fire Shield → Shield → HP; true damage skips both.
- Player HP 10 000 (×10 economy), enemy HP ×2.5 baked into data; healing only Lifesteal in fight
  and +25 % after bosses.
- Enemy side: attack rotation on a timer, next-3 intents queue; stun/freeze pause the timer;
  Divine Aegis (spell immunity), Mirror Shield (reflect + break), phases for the World Dragon.
  Ability types: see [../design/enemies.md](../design/enemies.md).
- Boon hooks exist in several abilities (`reflect_multiplier`, `clear_column`, `thorns_damage`,
  …) — these exports stay as plain fields but are **not** modified in the addon (no boons).
- Scoring: see [../design/scoring.md](../design/scoring.md).

## Changes

1. **`core/combat.lua`** — port of `battle_controller.gd` + `battle_status_math.gd`: player/enemy
   HP, `take_damage` (returns `reflect` / `shield` / `hp` / `none`), damage routing for sources
   `match` / `ability` / `bomb` / `reflect` / `thorns` / `other`, ability queue and drain hook for
   `core/sim.lua`, status table (timed statuses tick in sim time), fight start/end, god-mode off.
2. **`core/abilities/*.lua`** — the 12 abilities, **data + effect function** each:
   `{id, color, tier, name, params…, execute(ctx)}` using the board primitives from W0-T1.
   Parameters match the `.tres`/script defaults. Banner text placeholders `{damage}` etc. as in
   Godot (text assembled in the UI later).
3. **Kit indirection (for W1):** abilities are fetched via `kit.get(color, tier)`; for W0 there is
   a single default kit (the Godot one). W1 swaps kits per class without touching combat.
4. **Stub enemy only** (`core/enemy.lua`, rev 2): plain-hit rotation on a timer with an intent
   queue, stun/freeze pausing its timer, `delay_attack` (Area Clear). **All other enemy ability
   types (MultiHit, StunAbility/Stagger, HealBlock, ChargeNuke, SpawnJunk, DamageDebuff, HealSelf,
   SpellImmunity, MirrorShield, BoardSlow) and phases move to W0-G2** together with the real
   `enemy.gd` port (684 lines). Enemy attack cycle (verified, `enemy.gd:522–546`): one cycle =
   cooldown + wind-up animation + execute time (MultiHit includes the gaps between hits); the
   addon has no sprites, so each enemy's wind-up (frames ÷ fps) is exported into the data and the
   formula is part of the enemy module so enemies don't hit faster than in Godot.
4a. **Ability data carries an `icon` key** (resolved by `ui/assets.lua`), so the view can overlay the ability's spell icon on the ability gem it creates (user art decision 2026-10-04). `core/` stays asset-free.
4b. **Minimal text HUD** (`ui/hud_min.lua`, replaced by W0-P2): player/enemy HP bars, enemy attack
    timer + next intent text, status list, current ability banner as text. Needed to see the fight.
5. **Order (corrected):** `gems_cleared` (match damage) is emitted **before** `ability_activated`;
   the ability drain then runs **concurrently** with the fuse and junk animations (it does not wait
   for them); then gravity/refill, then the next pass (`board.gd:668–707`). Test it.
5b. **Fight-transition pause:** port `battle_controller.gd:243` pause-after-kill: gameplay is
    paused via the T1 gameplay-pause gate, leftover board work resumes against the next enemy.
5c. **Snapshot contract (W0):** state is saved only between fights; the combat module exposes
    `serialize()` for HP, run position and RNG stream states at that point. `settle_now` freezes
    enemy/status clocks, so a logout can never kill the player. Mid-fight snapshots are out of scope.
6. **Tests** under `test/`: `combat_test` (damage numbers incl. weakness/curse/size
   multiplier, hit order, true damage; the ordering test from 5), `ability_test` (each of the 12
   on a known board: clear shape, damage, chain, partner colour, Color Swap one-colour rule,
   Convert brakes, ability-gem-on-spawn-cell), `enemy_stub_test` (rotation timing incl. wind-up,
   stun/freeze pause the timer). Where Godot already has a test (`ability_gems_test`,
   `board_test`), mirror its assertions and cite the source; scenario golden logs use the T1
   RNG-tape approach.
7. **Order inside the item (two batches):** (a) match damage + stub enemy + HUD + the 8 simple
   abilities → first playable fight; (b) Convert, Color Swap, Bombs, Color Chain.

## Alternatives considered

- **Port only 3–4 abilities first** (Fire Wave, Shield, Row Clear, Stun): faster to a playable
  fight, but the chain/queue/partner-colour rules only get hard with the Convert/Color Swap family;
  defer them within this item rather than split into another milestone? **Order inside the item**:
  first the "simple" 8, then Convert/Color Swap/Bombs/Color Chain, but all in W0-G1.
- **Rebalance while porting:** no — parity first; balance changes only after a playable
  run (Godot's probe scripts show the targets: [../playtests/data/](../playtests/data/)).
- **Keep the Godot battle controller as the reference and generate Lua from it:** GDScript →
  Lua transpiling is more work than a careful manual port of 636 + 12 small files.

## Why this could be wrong

- Many abilities depend on exact Godot timings (telegraph waits, row-clear stagger) for the *feel*
  and for chain ordering. If the core uses different waits, chain outcomes may differ; compare
  with Godot using seeded runs and golden event logs (`tools/export_golden_boards.gd` extension).
- The numbers were tuned for the Godot game's input speed (mouse drag at 1.5 s/swap). WoW play
  (queue time, often one-handed) may need easier tuning — a playtest question, not a port change.
- 13 classes × the same 12 abilities will feel samey until W1; fine for W0.

## Non-goals

No boons/draft/relics, no run ladder (W0-G2), no class kits (W1), no HUD polish (W0-P2), no sound.

## Tests / acceptance

- `tools/checks.sh` runs all core tests, all PASS.
- Agent-verifiable: a tiny scripted bot (no probe port) plays one seeded fight headless against
  the stub enemy and prints the event log. **The statistical comparison with Godot's probe ("±15 %
  fight duration") moved to W0-T2** (needs the 1276-line `difficulty_probe.gd`, `move_eval.gd` and
  the reaction-time model ported; probe policies are `greedy`/`three_clear`, not what this spec
  said before).
- User playtest (after P1+P2): the fight reads the same as Godot; abilities chain; no stuck states.

## Open decisions

1. Tolerance for "same as Godot": **decided in W0-T2**, not here.
2. Keep boon-related exports on abilities? **Yes as plain fields** (no code removal; re-import
   stays trivial).
3. Statuses stored as a flat table per entity vs. objects? **Flat table keyed by status id**
   (garbage-friendly, easy to snapshot).

## Critic findings addressed (2026-10-04)

G1 re-scoped to combat + 12 abilities + stub enemy + minimal HUD (the claim that Puppy/Cyclops/Medusa
cover every enemy type was false); all enemy types, phases and the real `enemy.gd` port move to
W0-G2; wind-up timing and the attack-cycle formula added; fight-transition pause and snapshot
contract added; ordering text corrected; golden tests via RNG tape; statistical Godot comparison
moved to W0-T2.
