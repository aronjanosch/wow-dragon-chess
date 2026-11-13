# Spec: W0-P11 — Between-fight transition like the Godot game

Status: implemented — awaiting playtest (agreed by the user 2026-10-10: "do the transition the way the Godot original does it").
Milestone: W0. Track: P (+ one core timing change for the boss heal beat).

## Player experience goal

After every kill the game visibly takes a breath: the enemy dies, the HUD clears, "CLEARED — Next challenger
approaches" lands, after a boss the heal is celebrated, then the next enemy is announced by name and stage and
the board resumes. Today the addon pauses for the same 1.75 s but shows CLEARED at the kill moment and has no
heal beat / spawn banner, so it reads as "the enemy just swaps".

## Godot reference (facts, `scenes/game.gd` `_run_fight_transition`, `scenes/ui/fight_fx.gd`, `scenes/animation_timings.gd`)

1. Kill: battle pauses gameplay (board frozen), `_hide_between_fight_chrome()` hides enemy name, weakness label,
   attack queue and enemy HP text. Enemy death animation plays.
2. Wait `FIGHT_DEATH_BEAT` 1.0 s.
3. Not run won: `play_fight_clear_sting()` — sound `fight_clear`, trauma 0.22, ability banner "CLEARED" with subtitle
   "Next challenger approaches" (hold `FIGHT_CLEAR_STING * 0.7`), wait `FIGHT_CLEAR_STING` 0.75 s, banner cleared.
4. Boss heal pending: heal moment — heal sound, holy FX on the enemy frame + at the player HP bar, "+N HP" float at
   the bar, the HP bar fills from old to new over `HEAL_MOMENT_HOLD` 5.0 s (fixed length).
5. (Draft — cut in the addon.)
6. Run won: result overlay after the death beat. Otherwise start the next fight and resume gameplay; the spawn shows
   name / weakness / queue again and the ability banner "<ENEMY NAME>" / "STAGE s-f" (`BANNER_HOLD` 1.0, `BANNER_FADE`
   0.4); the enemy drops / fades in (`ENEMY_SPAWN_IN` 0.45).

## Addon today (facts)

- `core/run.lua` `Run:advance` sets `next_at = now + FIGHT_TRANSITION` (1.75) for every kill; `Run:update` starts
  the fight; the boss heal is applied at the kill (`combat:heal_player`, snapshot already has it).
- `core/combat.lua` `_on_enemy_defeated` pauses gameplay (scheduler gate) until `start_fight`.
- `ui/fight_view.lua` `_on_enemy_defeated` starts CLEARED, death fx, sound "cleared" and trauma all at the kill;
  `_on_fight_started` = `hitfx:enter` (slide / fade in, name punch). No heal beat, no spawn banner.

## Changes

1. **Core timing (core/run.lua):** after a boss that is not the last fight the beat is
   `FIGHT_TRANSITION + Run.HEAL_MOMENT` (new, 5.0 s). Keep the heal applied at the kill (snapshot unchanged). Expose
   on the `run_advanced` event (or the run) what the UI needs: the beat phases and the heal amount (e.g.
   `run_advanced(result, index, heal_amount)`), no WoW API in core. Run won stays immediate in core.
2. **View sequence (ui/fight_view.lua, ui/hit_fx.lua as needed), all on sim time and halted by pause/hide like other
   juice:**
   - Kill: death fx + death sound as today; hide enemy name, weakness, HP text and attack queue immediately; no
     CLEARED yet.
   - kill + 1.0 s: CLEARED with subtitle "Next challenger approaches" (reuse the ability banner or the CLEARED
     widget + a subtitle line), "cleared" sound + `TRAUMA_CLEARED` move here; hold ~0.5 s, gone by kill + 1.75 s.
   - Boss (not last): from kill + 1.75 s for 5.0 s: heal sound, a holy heal effect at the player HP bar (native WoW
     effect/asset by reference — reuse what the player-heal path already uses if fitting), "+N HP" float at the bar,
     the player HP bar/text animates from the pre-heal value to the new one over the 5 s (view-only lerp; core HP is
     already final).
   - Next fight start: name / weakness / queue back, ability banner "<NAME>" / "STAGE s-f" (hold 1.0, fade 0.4) on top
     of the existing `hitfx:enter`.
   - Last boss (run won): victory overlay only after a 1.0 s death beat (check how `ui/main.lua` shows it today; delay
     the overlay view-side, core unchanged).
3. Named timing constants in one place (fight_view top or `core/timings.lua` for the core one), with Godot names in
   comments. Update `docs/design/` (run / wow-addon) to the new flow.

## Non-goals

No draft / rest screen, no click-to-continue, no change to snapshot/persistence semantics, no new art files.

## Tests / acceptance

- `tools/checks.sh` clean (lua5.1 + luajit).
- `run_test`: normal kill → next fight at +1.75 s; boss kill → +6.75 s; last boss → run won, no next fight.
- UI test: CLEARED not visible at the kill, visible at +1.0 s; chrome hidden during the beat and back after the
  spawn; spawn banner shows the enemy name; boss heal bar animates (value between old and new mid-beat).
- User playtest: the transition reads like Godot.
