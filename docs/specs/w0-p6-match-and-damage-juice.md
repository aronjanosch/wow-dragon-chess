# Spec: W0-P6 — Match break, ability spawn, streaks and damage juice

Status: approved by user: implement directly (2026-10-05, "everything nice and snappy"). Implemented — awaiting in-game playtest.
Milestone: W0 addon. Track: P (presentation). Issue #53.
Pillars served: readable real-time feedback ("feedback over explanation"), the match-3 core should feel snappy.

## Player experience goal

A match visibly breaks (flash, shards, sparkle), the matching gems visibly run together into the new ability gem
(which lights up), the damage travels as a glowing streak to the enemy and lands there (number, hit reaction), and
big events shake the window. Everything is short and never blocks the board or the input.

## Current state (facts)

- The sim already moves matched gems to their convergence cell (`Sim:_begin_match_fuses`, `Timings.FUSE` 0.24 s,
  `gem.fx = "fuse"`): the "run together" motion exists, only the look (scale 1 -> 0.65, alpha 1 -> 0.2) was plain.
  Ability / junk clears use `gem.fx = "clear"` (scale up + fade). The kept gem pops (`ABILITY_POP` 0.16 s).
- `match_resolved(length, gems, depth)` carried no destination; `ability_gem_spawned(col, row, tier, type)` fires at the
  end of the fuse. `enemy_damaged` / `player_damaged` / `player_healed` / `attack_reflected` /
  `enemy_ability_executed` / `enemy_mirror_changed` / `ability_triggered(info)` already exist (combat.lua).
- Godot reference: `scenes/ui/fight_fx.gd` (`_spawn_projectile`, vignette flashes, `_apply_match_juice`), `scenes/vfx/
  impact_fx.gd` (shards / sparkle / rings), `autoload/juice.gd` (trauma shake), `scenes/animation_timings.gd`.
- Red hit vignette, enemy hit effect model + punch + wound animation (W0-P3/P5) existed; they ran at once on
  `enemy_damaged`.

## Changes

1. **Core (additive):** `match_resolved(length, gems, depth, dest_col, dest_row, spawn_tier)`: where the gems converge
   (the ability spawn cell, else the centre gem's cell) and the spawned tier (0 = none). The pass is unchanged (the
   emit moved after the pure spawn / centre computation). `sim_test` covers it; golden / determinism tests unchanged.
2. **Match break (`ui/board_view.lua`):** `fx_curve` returns scale, alpha, rotation and flash. "fuse": additive flash
   (a second ADD copy of the gem icon) + swell 1.18 in the first 30 %, then shrink to 0.1, spin (`Texture:SetRotation`,
   guarded, only for full-texcoord sets) and fade while converging; "clear" (ability / junk) the same with a longer
   swell; "pop" (fresh ability gem) flashes. All pure functions of `gem.fx_t` (sim time).
3. **Juice layer (`ui/juice.lua`, new):** pooled particles (48), rings (6), streaks (6 x head + 5 trail dots), trauma
   shake. Match shards in the gem colour burst at the convergence cell when the gems arrive (`delay = FUSE`), 4+ adds a
   ring, 5+ sparkles. Ability gem spawn: ring + sparks (skill cyan, ult bigger, golden, second ring, sparkles).
4. **Streaks (`ui/fight_view.lua`):** the player's damage flies 0.2 s from the match centre / ability cell to the enemy
   in the gem's colour (ult weight 2.0: thicker + slower, skill 1.4, bomb 1.2); the damage number, hit effect, wound
   animation and a short knock-back (8 px, Godot) run on arrival (`FightView:_enemy_hit`). Also: enemy cast -> player
   HP bar (boss thicker, curse purple, junk -> board edge), heal (green, from the last match), Fire Shield reflect
   (player -> enemy, orange, same sim instant as `attack_reflected`), Mirror bounce (enemy -> player, silver).
5. **Shake + flashes:** Godot's trauma model on sim time (decay 2.4 / s, offset = 12 px x trauma^2) on the window frame:
   4+ match (0.1 .. 0.65), skill 0.22, ult 0.55, bomb 0.3, Mirror shatter 0.35, CLEARED 0.22, player hit 0.12 .. 0.6 by
   damage / max HP. Vignette flashes in colours: cyan skill, gold ult, silver Mirror shatter, orange reflect, red hit.
   The rest position is captured when a shake starts and restored exactly when it ends (and on hide / pause / menu /
   drag start / option off); no shake while the window is dragged. Menu: "Screen shake: On/Off"
   (`DragonChessDB.options.shake`, default on).
6. **Debug panel (Effects tab):** buttons Break 3 / Break 5 / Skill spawn / Ult spawn / Streak / Ult streak / Enemy cast
   / Shake / Big shake.
7. **Dropped on purpose:** keyboard shortcuts for the debug panel (see W0-P5): no capture of keys in the addon window.

## Alternatives considered

- Frame-by-frame sprite sheets (`assets/bejewled`, 20 rotation frames, 84 px): rejected, 6 x 20 sheets are big for a
  0.24 s effect; scale / alpha / rotation of the single icon gives the same read.
- Flipbook atlases (`GemDissolve_T*_Flipbook`): rejected for now, the grid layouts are unread (probe notes).
- Hit-stop (Godot `Juice.hitstop`): not possible: the sim is the clock; freezing it would also freeze input / timers.
- Line objects for the streak (`CreateLine`): not verified in the API baseline; a head disc + trail dots uses only
  verified calls.

## Why this could be wrong

- The shake moves the whole window (also the title strip and the Esc / menu children); on a low-refresh or
  high-latency display it may read as lag rather than impact. The option and `Juice.SHAKE_MAX` are the levers.
- 6 streaks + 48 particles + 64 gem flashes are cheap on stubs; the live cost is unmeasured (debug footer shows the
  frame cost; use `Break 5` + `Ult streak` repeatedly).
- `Texture:SetRotation` on a masked texture is unverified live; if it misbehaves the guard turns the spin off after
  one error, the rest of the break still shows.
- The streak hides the hit for 0.2 s: with fast chains the damage number lags the match a little (by design:
  causality first). If it feels slow, lower `Juice.FLY`.

## Non-goals

- Hit-stop, cascade pitch, new sounds (the break sound 101 and the W0-P5 slots stay).
- Keyboard shortcuts.
- Reduce-motion CVar handling (the menu option is the switch).

## Tests / acceptance

- `ui_juice_test` (curves, real match flash / spin / clean frames, cropped set / missing `SetRotation`, shard delay and
  pool bounds, no new textures / frames while playing, spawn rings, streak timing + hit-on-arrival, 20 hits through a
  pool of 6, ult / enemy cast / heal / reflect / Mirror directions, vignette colours, shake: rest restored exactly,
  drag / pause / hide / menu / option guards, menu button, no-juice fallback, debug buttons, allocation budget),
  `sim_test` (payload), `ui_smoke` / `ui_fx_test` (hit reaction now waits for the streak).
- User playtest: do the breaks read as snappy; is the shake welcome (option); do streaks / numbers feel causal;
  tune with the debug panel buttons (constants: top of `ui/juice.lua` and `ui/fight_view.lua`).
