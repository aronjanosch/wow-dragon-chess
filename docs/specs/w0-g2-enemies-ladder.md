# Spec: W0-G2 — Enemies and run ladder (full enemy port, 10 fights, difficulty, score)

Status: G2a implemented; G2b implemented — awaiting in-game playtest (spec rev 2, after critic review 2026-10-04).
Milestone: W0 Base game port. Track: G. Depends on W0-T1, W0-G1 (core merged); G2b also on W0-P2 (UI).
Pillars served: 3 (two-speed combat — enemy specials are what the setup layer answers), 5 (readable
pressure — every enemy mechanic must be understood by watching), 7 (free, finishes the base game).

## Player experience goal

A full run: 10 fights over three stages plus the final boss, each enemy with its own rhythm and
mechanic (stagger, heal block, immunity, mirror, sandstorm, phases), difficulty 1–5, a score and a
local best score per difficulty. It plays like the Godot game's M1-G9 build.

## Current state (facts)

- Core has the stub enemy only (`core/enemy.lua`, Cerberus Puppy, plain hit, stun/freeze pause,
  `delay_attack`, wind-up formula). Combat already ports the player-side halves of Aegis/Mirror/
  Curse/Heal block/Stun/Sandstorm; the stub's `is_spell_immune` / `is_mirror_up` return false
  ([../design/wow-addon.md](../design/wow-addon.md) "Combat (W0-G1)").
- Godot data: 10 enemies + abilities as `.tres` (`scenes/enemies/*.tres`, `abilities/*.tres`),
  `EnemyData` (name, max_health, is_boss, ability_rotation, weak_to_color, phases, sprite_frames, tint),
  `EnemyPhaseKit` (hp_fraction, phase_name, rotation). Roster and values:
  [../design/enemies.md](../design/enemies.md) (difficulty-1 values, M1-G8 HP ×2.5, M1-G9 mechanics).
- Ability types in Godot (`scenes/enemies/abilities/*.gd`): plain `EnemyAbility`, `MultiHit`,
  `StunAbility` (stagger), `HealBlockAbility`, `ChargeNuke`, `SpawnJunk`, `DamageDebuff` (curse),
  `HealSelf`, `SpellImmunity` (Aegis), `MirrorShield`, `BoardSlow` (Sandstorm); `GridRip` is the
  grid-fight prototype only (**not ported**).
- Run rules ([../design/run.md](../design/run.md), `autoload/run_manager.gd`): fixed ladder of 10
  fights (stage 1–3: 2 normals + boss; stage 4: World Dragon alone, phases at 66 %/33 %), player
  10 000 HP persisting across fights, +25 % max HP heal after bosses, difficulty 1–5 (HP +15 % and
  damage +20 % per level above 1, applied to **copies**, never to cached data — M0-G1 rule),
  scoring per [../design/scoring.md](../design/scoring.md), best score per difficulty (B.15).
  Boons/Rest/draft are **cut**.
- Known Godot quirks to decide (from the W0-G1 report): the repeating attack timer can start a
  second attack while a long one (wind-up + MultiHit) is still running; `find_possible_move` counts
  junk colours (issue #49: junk-only boards never reshuffle, becomes live once enemies spawn junk).

## Changes

Split into **G2a (core + data, lands first)** and **G2b (ladder + UI wiring, after W0-P2 is merged)**.

### W0-G2a — enemy port + data (`core/`, `data/`, tools; minimal UI touch)

1. **One-shot converter** `tools/convert_enemies.py` (not part of `checks.sh`): tokenises the Godot
   `.tres` text (free-form ExtResource ids → path → script type; `ArrayExtResource(..)`
   rotations; `SubResource` phases with the rotation inside) and writes
   `data/enemies.lua`. **Rules:** read `@export` defaults from the `.gd` scripts
   (`hp_fraction` 0.66 for `Phase_norse` is load-bearing; `is_boss` false, `weak_to_color` −1,
   `cooldown` 1.0, `stun_duration` 3.0, `junk_count` 3, `hit_interval` 0.12, …); emit the **effective
   `is_special`** (every subclass overrides it to true; plain hit has its own field) and a `kind`
   string for UI glyphs (`plain`, `flurry`, `stagger`, `heal_block`, `nuke`, `junk`, `curse`, `heal`,
   `aegis`, `mirror`, `sand`); keep the **stub's field names** (`windup`, `weak_to_color`,
   `rotation`, `icon`); `windup` = constant **8/12 s** (all roster sprite packs share the attack
   clip: 8 frames at speed 12; per-enemy override field); `display` key = placeholder `1000` for all
   (roster decision is separate). Legacy enemies (`dragon`, `slime`, `slime_king`, `goblin`) and
   `grid_rip` are skipped. **After G2a lands `data/enemies.lua` is hand-owned** (the converter is
   history; Godot's `.tres` are frozen on the archive branch).
2. **`core/enemy.lua`** becomes the full port of `scenes/enemies/enemy.gd`, with abilities in
   `core/enemy_abilities.lua` (all 11 types). Behaviours to honour (critic-verified):
   - **Attack cycle:** keep Godot's repeating timer **with the re-arm (parity)**: one cycle =
     cooldown + wind-up + execute; the timer restarts with the previous ability's cooldown at timeout.
     Add a cheap guard (skip a timeout while a hit is in flight) and a **data test asserting
     `max(windup + execute_time_max) < min(cooldown)`** (true for the shipped roster). The earlier
     "fix the overlap" idea is dropped: the overlap cannot occur with the shipped data and changing
     the re-arm alters stun/freeze timing and `enemy_next_attack`.
   - **Execute is stepwise and freezable:** MultiHit (hit count first, then one damage per hit,
     gaps), SpawnJunk (0.62 s telegraph), stagger/heal-block steps run as `Clock` timers or a small
     state machine, **never as free `sim:wait` service tasks**, so `Combat:settle_now()` (clocks
     frozen) can never fire remaining hits. Test: `settle_now` mid-flurry deals 0 hits. `cycle_time`
     becomes an *expected* value for the HUD only (`execute_time_expected`).
   - **Phases** (`_check_phase_thresholds` exactly): only in `take_damage` when HP > 0 and also after
     reflect/thorns damage; `hp_frac <= hp_fraction` in a loop (one hit may cross two thresholds);
     monotonic (healing never un-phases); skip an empty rotation; label defaults to "Phase N"; resets
     `rotation_index`; restarts the timer to `rotation[1].cooldown` only if the enemy is active (not
     stunned). The rotation is a **reference swap**, never a mutation of shared data; intents rebind.
   - Order and RNG: pre-execute `roll_damage`, then `take_damage`, then `execute`; stagger / MultiHit /
     heal-block roll inside `execute` with base 0; `range_i(hi<=lo)` draws nothing (0-damage abilities
     consume no RNG); Heal Self doesn't pass through heal block; Aegis blocks only `ability`/`bomb`
     sources; stun/freeze bounce while immune (also the Mirror break stun); `delay_attack` still
     applies while immune; `apply_mirror_shield` resets the crack counter.
3. **Interface for the UI (defined here, built in G2b/P2):** `hud_state` gains `aegis_remaining/max`,
   `mirror_remaining/max/crack_ratio`, `phase_name`, intent `kind`; events `enemy_phase_changed`,
   `enemy_mirror_changed(active, broken)` (shatter vs expiry), existing `enemy_immune`. Combat's
   `is_spell_immune` / `is_mirror_up` are connected to the enemy.
4. **Wiring kept minimal:** `Enemy.STUBS` stays as an **alias to the data** so `ui/main.lua` keeps
   working; a dev slash command `/dchess fight <id>` starts any enemy (needs the small `main.lua`
   edit, plus `.toc`/`loader.lua` lines with `data/enemies.lua` loaded before `enemy.lua`) — the
   only UI-file touches, reported explicitly.
5. **Junk fix (precise):** `would_swap_match` must reject a swap when **either swapped gem is junk
   or not settled** (neighbours already exclude junk via `type_at`); do **not** add `protected`
   (it is released on `board_settled`). Seed parity with Godot ends where junk is on the board
   (RNG consumption differs); keep the `shuffle_board` cap and define the `false` result as "no
   move possible → board stays, event fires". New cases in `match_test`; Godot issue #49 gets a
   comment.
6. **Tests** (`test/`): `enemy_data_test` against a **golden table dumped from Godot once**
   (`tools/export_enemy_golden.gd` run headless, HP/ranges/cooldowns/params, committed as
   `test/golden_enemies.lua`; skipped silently if absent) — not prose, not a regen-diff;
   `enemy_test` (rotation, cycle formula, phases incl. double-threshold, stun/freeze, Aegis, Mirror
   crack/break, Sandstorm on the sim, heal block, curse, stagger only on HP hit, multi-hit gaps, nuke
   delayed by stun, `settle_now` mid-flurry); **bot acceptance:** for each enemy, N = 5 seeds, the
   scripted bot with `god_mode` (or inflated player HP) must bring the enemy to 0 within a sim-time
   cap of 600 s with no stuck state (stuck = board not settling within 30 s); runtime budget for
   the whole suite stays under ~2 min.

### W0-G2b — ladder, difficulty, score, enemy-status UI (after W0-P2)

7. **`core/run.lua`:** 10-fight ladder, `advance()`, **per-fight scaled copies** (copy once per
   original ability — they are shared across rotations/phases): scale `damage_min`/`damage_max` of
   every ability (per-hit flurry, stagger, heal-block hits too), Mirror `break_damage` and
   `max_health` by the HP factor, rounding `int(round(x))` separately per field, clamp `max >= min`;
   **never** scale durations, `stun_duration`, `cooldown`, `heal_percent`. Boss heal +25 % applied
   before the fight-boundary snapshot (the World Dragon's heal is a no-op). The 1.75 s between-fight
   beat moves out of `ui/main.lua`. Score: `combat.score` is carried across fights (G1 already tallies
   it; no kill/time bonus exists in Godot). Test: `data/enemies.lua` deep-compared unchanged after all 5
   difficulties.
8. **Persistence:** `DragonChessDB.records[difficulty]` (created if missing), highest unlocked
   difficulty; **best score is recorded on win AND loss**, unlock only on win; run snapshot version
   bumps to 3 and silently discards older saves.
9. **UI wiring + enemy-status UI (owner: this item):** stage label from the run, difficulty chooser
   (`/dchess difficulty N` + small control), run-won/lost overlays with score/best; **enemy status
   and phase visuals**: stun/freeze icon, Aegis (gold tint + icon), Mirror (silver + icon, crack/
   SHATTERED text), phase banner, junk and Sandstorm board tints, per-kind intent glyphs in the queue
   (`kind` → asset key table in `ui/assets.lua`). Needed so "each boss mechanic readable" can pass.
10. **Tests:** `run_test` (ladder order, copies never mutate originals, heal rules, unlock/records
    incl. loss records, multipliers D1–D5), ui_smoke extensions for the new visuals, a full-run bot
    test on a seed (god_mode), within the runtime budget.

## Alternatives considered

- **Hand-port the data instead of a converter:** 10 enemies × ~4 abilities by hand invites typos
  and drifts from the Godot reference; the converter is a one-off script that can be re-run.
- **Port only normal enemies first, bosses later:** the bosses carry the M1-G9 mechanics that make
  the game interesting; the ladder without them isn't the base game.
- **"Fix" the overlapping-attack quirk (no re-arm):** rejected by the critic — the overlap cannot occur
  with the shipped data and the change alters stun/freeze timing; kept parity plus a data test.
- **Regenerate `enemies.lua` from the `.tres` in a test:** contradicts "converter output is the source
  of truth" and needs `scenes/` and python in CI; replaced by a one-shot converter + golden snapshot.

## Why this could be wrong

- A constant wind-up (8/12 s) may feel off for WoW creature models; it is data (`windup`) and tunable
  without code changes.
- Difficulty numbers were tuned for Godot input speed (mouse, desktop session); WoW players in a
  queue play slower/one-handed. Expect a playtest-driven rebalance; the W0-T2 bot port gives the
  measurement tool.
- 10 fights may be too long for "queue minutes"; run length is a later decision (the ladder is
  data), the pause/resume rule makes long runs safe.
- The Godot reference may later change (it is frozen on an archive branch), so the converter output is
  the source of truth for the addon from now on.

## Non-goals

No creature roster decision (display IDs stay placeholder; roster = separate decision using a
display-ID scan), no boons/draft/relics/shop, no grid-fight, no class kits (W1), no scoreboard
(W2), no new enemies or rebalancing.

## Tests / acceptance

- `tools/checks.sh` clean on `lua5.1` and `luajit`; the converter is run in CI-like fashion by a
  test that regenerates and diffs `data/enemies.lua`.
- Agent-verifiable: seeded bot runs reach every enemy; no stuck states over N seeds.
- User playtest (in WoW after G2b): a full run, each boss mechanic readable, difficulty chooser works,
  best score persists across `/reload`.

## Open decisions

1. Overlapping-attack quirk — **keep parity + guard + data test** (rev 2).
2. Junk dead end — **fix in Lua (precise rule in change 5), issue #49 follows**.
3. Wind-up source — **constant 8/12 s with per-enemy override** (rev 2).
4. Records storage — **`DragonChessDB`** (account-wide), not per character.
5. Difficulty selector UI — **`/dchess difficulty N` + a small control in the window**.

## Critic findings addressed (2026-10-04)

Dropped the "fix the overlap" decision in favour of parity + guard + a data test (the overlap is
unreachable with shipped data and the change alters stun/freeze timing); execute modelled as
Clock-compatible steps so `settle_now` can't fire hits; converter rules rewritten (script defaults,
effective `is_special`, `kind`, constant wind-up, stub field names) and made one-shot with a Godot
golden snapshot; the P2/G2 interface (`hud_state` fields, events, `STUBS` alias, `/dchess fight`) and
an owner for the enemy-status/phase UI (G2b item 9) defined; bot acceptance made measurable (god_mode,
N, time cap, budget); phase details, difficulty-copy rules, junk-fix wording, score/records semantics
(records on win and loss) added.
