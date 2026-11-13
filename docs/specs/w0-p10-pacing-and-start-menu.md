# Spec: W0-P10 — Pacing (damage, streaks, auras) + start / resume menu

Status: implemented — awaiting playtest (agreed (user, 2026-10-10) — values below decided in chat; critic review skipped (pure tuning + flow, no new mechanic).)
Milestone: W0. Track: P (+ one G tuning value).

## Player experience goal

The game is a bit easier, the gem streaks flying to the enemy and the aura pulse of ability gems are calm
enough to read. Opening the window never throws you into a running fight: you always get a menu first —
a start screen for a new run, or a pause menu over the frozen old fight when a run is in progress.

## Current state (facts)

- Enemy damage per run copy: `core/run.lua` `Run.multipliers` (+20 %/level) × `Run.ATTACK_PACE` 2.2 in `scaled_ability`.
- Streak flight: `ui/juice.lua:40` `Juice.FLY = 0.20` s (× `FLY_HEAVY` 1.4 at weight >= 2). The HUD hit reaction
  fires on arrival (`on_hit`).
- Ability gem aura: `ui/board_view.lua` `_update_aura` — skill pulse 1.4 Hz, ult 1.0 Hz, bomb flicker
  `sin(now*31)*sin(now*13.7)`.
- `ui/main.lua` `on_show` calls `ensure_run()` and the driver ticks at once; the in-window menu (`ui/menu.lua`,
  `App.open_menu`) already pauses the game (`App.menu_open` → `can_input`/tick blocked).

## Changes

1. **Enemy damage −10 %:** new `Run.ENEMY_DAMAGE_SCALE = 0.9`, multiplied into `damage_min` / `damage_max` in
   `scaled_ability` (all difficulties). Golden data (`data/enemies.lua`) unchanged. Mirror-Shield break damage is
   not enemy attack damage — leave it unscaled by this knob. Update `run_test` expectations and
   `docs/design/` (wherever the damage formula is documented).
2. **Streaks slower:** `Juice.FLY = 0.40` (ult = 0.56 via the unchanged `FLY_HEAVY`). Check any juice/hud test that
   hard-codes the old flight time; derive from `Juice.FLY` instead of new literals.
3. **Aura calmer:** skill pulse 1.4 → 0.6 Hz, ult 1.0 → 0.4 Hz, bomb flicker about half speed (31 → 15, 13.7 → 7).
   Pull the numbers into named locals/fields at the top of `board_view.lua` (tuning in one place).
4. **Start / resume menu on every window open:**
   - On every `on_show` the run is loaded/created and bound as today (board, enemy, HP visible), but the game starts
     **paused** behind a start panel (same pause semantics as `App.menu_open`: no tick, no input, `hud:halt()`).
   - Run in progress (restored snapshot, or the current session's run past its first moment: fight index > 1 or
     score > 0 or player HP < max): panel title "Paused", buttons **Continue** (closes panel, game runs) and
     **New run** (inline confirm like the menu's Restart, then a fresh run that also starts paused behind the
     panel in its "new run" form) — the old fight stays visible, dimmed, behind it.
   - No run in progress (fresh run): panel title "Dragon Chess", difficulty row/cycler (reuse `App.cycle_difficulty`
     / `difficulty_text`, only unlocked levels) and **Start**.
   - Esc on the panel hides the window (as Esc does with nothing open). Game-over / victory / crash overlays keep
     their current behaviour (the panel does not open over them; their click still starts a new run — that new
     run starts directly, no extra panel).
   - Debug `/dchess fight <id>` closes the panel (like it closes the menu today).
   - Build the panel in `ui/menu.lua` (or a small new `ui/start_menu.lua` if cleaner; then add it to the `.toc`
     and the test loader), no game rules in it; `ui/main.lua` decides which form to show.

## Non-goals

No new art, no animation for the panel beyond a dim layer; no change to pause-on-hide, soft pause or the
existing in-window menu items; no HP / cooldown changes.

## Tests / acceptance

- `tools/checks.sh` clean (lua5.1 + luajit).
- `run_test`: scaled damage includes the 0.9 factor. `ui_menu_test` (or a new test in `checks.sh`): showing the
  window opens the start panel, tick/input are blocked until Continue/Start; a restored run shows the resume
  form, a fresh one the start form; New run asks for confirmation.
- User playtest in the client: difficulty feel, streak + aura speed, menu on open / after /reload.
