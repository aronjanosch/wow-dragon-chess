# Spec: W0-P4 — In-window menu, minimap button, idle hint and shuffle feedback

Status: implemented — awaiting in-game playtest (from the user's 2026-10-04 playtest feedback). Milestone: W0. Track: P. Depends on W0-G2b.
Pillars served: 1 (snappy: open in one click), 2 (pause is free), 5 (readable: hint when stuck).

## Player experience goal

A minimap button opens the game with one click. A small menu offers restart and sound options. If you do nothing
for a while a movable gem wiggles; if no move exists the board reshuffles visibly.

## Current state (facts)

- Launch is `/dchess` only; no menu, no restart button, no options (user: "no menu"). Esc closes the window.
- Idle hint was cut from W0-P1 (critic: it calls `find_matches`, an allocator). Godot had a 6 s idle wiggle
  (`animation_timings.gd` HINT_*). Core `find_possible_move` exists; no-moves → `board_shuffled` event
  (junk fix in W0-G2a); the UI shows nothing for it.
- `LibStub`/`LibDBIcon` are not available in the client (probe); the minimap button must be our own.

## Changes

1. **Minimap button** (`ui/minimap.lua`): own round button on `Minimap` (gem icon `INV_Misc_Gem_Ruby_02`,
   masked), drag around the minimap edge (angle saved in `DragonChessDB.minimap`), left click toggles the
   window, right click opens the menu, tooltip (title + "Left click: play, drag: move"); plus
   `AddonCompartmentFrame` registration if present (it is in the client).
2. **Menu** (gear button in the title strip): Restart run (inline confirm), Sound on/off, "quiet mode"
   (only key sounds), difficulty chooser entry, window scale (small/normal/large), Close. Options persist in
   `DragonChessDB.options`; the addon cannot set a per-addon volume (only on/off and quiet mode).
3. **Idle hint:** after 6 sim-seconds without a swap, compute one possible move (`find_possible_move`, once per
   idle period, never per frame) and wiggle that gem pair; cancelled by any swap/pause. Allocation-free after
   the one-time call.
4. **No moves → shuffle:** on `board_shuffled` show a short "No moves — shuffling" line and a quick shuffle
   animation (gems pop); if the shuffle fails (`board_shuffled(false)`) show "Stuck" and offer restart.
5. **Tests:** ui_smoke: minimap button position maths and click handlers, menu actions (restart resets the run,
   options persist), idle hint fires once after 6 sim-seconds and stops on swap/pause/hide, shuffle message.

## Non-goals

No per-addon volume slider, no profiles, no keybindings.

## Open decisions

1. Minimap icon — **ruby gem** (swap later for the final logo).
2. Hint delay — **6 s** (Godot value).
