# Spec: W0-P5 — Feel gaps vs Godot and debug panel additions

Status: approved by user: direkt umsetzen (2026-10-04). Implemented — awaiting in-game playtest.
Milestone: W0 addon. Track: P (presentation) + T (dev tooling). Issue #53.
Pillars served: readable real-time feedback ("feedback over explanation"), fast playtest iteration.

## Player experience goal

A match, a spawned skill/ult gem and an enemy special cast are visible and audible the way they are in the Godot
game; a selected skill/ult gem shows which neighbours activate it. The developer can make the enemy invincible,
freeze its timers and watch every live status in the debug panel.

## Current state (facts)

- Sim emits `match_resolved(length, gems, depth)` and `ability_gem_spawned(col, row, tier, type)`; combat emits
  `enemy_ability_executed(ability)` (ability table has `name`, `icon`, `kind`, `is_special`, `description`).
  No core change was needed for items 1-4.
- `Enemy.invincible` existed (core/enemy.lua) but had no switch; the enemy timers are clock timers on sim time.
- Godot reference: `fight_fx.gd` (match float, spawn sound, "<NAME> READY"), `board_input.gd _refresh_swap_hints`,
  `debug_cheats.gd` (F10 pause enemy timer, F11 invincible, F9 status dump).

## Changes

1. Match feedback (`ui/fight_view.lua`): pooled float "MATCH" / "N-MATCH" + "+points" at the match centre (8
   FontStrings on the board fx layer); sounds `match_4..match_7` by length, `match_cascade` for a 3-match at chain
   depth >= 2 (no pitch in WoW; the per-wave `gem_break` stays).
2. Swap hint (`ui/board_view.lua`): selected skill/ult gem rings same-colour neighbours (4 pooled rings) and shows
   "SKILL/ULT - swap with same colour to activate"; a plain selected gem next to a same-colour ability gem gets the
   ring only; bombs get none.
3. Ability gem spawn: float with the ability name, `ability_spawn_skill` / `ability_spawn_ult` sound, ult banner
   "<NAME> READY" (banner function `FightView:_show_banner`, shared).
4. Enemy cast: on `enemy_ability_executed` orange flash over the figure; specials also banner (icon, name,
   description, red title) and `enemy_special` sound (Ambience channel). Plain hits stay quiet (player_hit covers).
5. Debug: `Debug.toggle_invincible`, `Debug.toggle_enemy_timers` (new `Clock:hold`, `Enemy:set_timers_held`,
   `combat.enemy_timers_held`), `Debug.status_lines`; panel: two Fights buttons, new "Live" tab (7th). All mark `run.dev`.
6. Keyboard shortcuts for the panel: **deliberately dropped** (user decision 2026-10-05; see Non-goals).

## Alternatives considered

- Pitch rising per cascade depth (Godot): impossible in WoW; a different slot is the substitute.
- Enemy cast flash via the red hit disc: rejected, it means "enemy damaged".
- Freezing the whole combat clock for "pause enemy timers": rejected, it would also freeze player statuses.

## Why this could be wrong

- Sound file IDs are listfile picks, not heard yet; 4+ matches stack with `gem_break` and may be too busy.
- A float per 3-match may clutter fast chains (pool of 8 recycles the oldest).
- Enemy special banner shares the frame with the player's ability banner; the last one wins.

## Non-goals

- Keyboard shortcuts (kill / heal / god): **deliberately dropped by the user (2026-10-05), not an open item.** A frame needs `EnableKeyboard` + `SetPropagateKeyboardInput`, neither is
  verified in `docs/design/wow-forever-api.md`; getting it wrong blocks the player's normal keys. Omitted.
- Screen shake / hitstop (shake came with W0-P6), cascade pitch.

## Tests / acceptance

- `ui_fx_test` (match float, sounds by length, pool cap, spawn float/banner, enemy cast, swap hint, allocation),
  `ui_debug_test` (toggles, Live tab), `debug_test` (invincible, timer hold incl. wind-up, status_lines).
- User playtest: do the match sounds / floats feel right; swap hint visible; enemy special banner readable.
