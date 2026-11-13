# WoW addon — port map and architecture

Status: AGREED plan 2026-10-04; W0-G2a (enemies) and W0-G2b (run ladder, difficulty, enemy-status UI; awaiting in-game playtest) implemented 2026-10-04; W0-T1 (pure-Lua core), W0-P1 (addon shell + board view, awaiting in-game playtest), W0-G1 (combat core + minimal text HUD, playable Puppy fight; awaiting in-game playtest) and W0-P2 (Godot-style fight screen with WoW assets; awaiting in-game playtest) implemented 2026-10-04. Branch `wow-addon`. Goal and reasons:
[../VISION.md](../VISION.md); plan: [../ROADMAP.md](../ROADMAP.md). This file says what comes
from the Godot game, what is cut, and how the addon is structured. When code exists, this file
becomes the "current state" doc of the addon.

Platform facts and external references (forever-addon-kit, API baseline, SavedVariables bug,
`C_EncodingUtil`, addon-message restrictions): [wow-forever-api.md](wow-forever-api.md).

## Layout

Exists now (W0-T1, W0-P1); the rest is planned (marked *).

```
<repo root>/           ← the addon itself (symlink the repo into Interface/AddOns/DragonChess)
  DragonChess.toc       core files in test/loader.lua CORE_FILES order, then ui/ (ui_smoke checks it)
  core/                 ← pure Lua, NO WoW API, no globals (`local _, ns = ...`)
    rng.lua             MRG32k3a, arithmetic only; streams via Rng.fork(seed, SALT.*)
    timings.lua         board durations that drive logic order (from animation_timings.gd)
    board.lua           grid state, gem tables, fill / reshuffle, serialize at rest
    match.lua           region matching (Godot algorithm), tiers, move search
    scheduler.lua       event-driven coroutine scheduler (sim time, pause gate, events)
    board_effects.lua   ability board primitives (clear_area/row/wave/color, converts, junk)
    sim.lua             board.gd await chain: swap → passes → fuse → drain hook → gravity
    clock.lua           combat clock: freezable one-shot timers on gameplay time (W0-G1)
    kit.lua             ability kits (kit:get(color, tier)), banner text, partner colour (W0-G1)
    abilities/<color>.lua  the 12 abilities: .tres data + execute(ability, ctx) (W0-G1)
    enemy_abilities.lua the 11 enemy ability kinds (W0-G2a)
    enemy.lua           enemy.gd port: rotation, wind-up, stun / delay, phases, Aegis, Mirror (W0-G2a)
    combat.lua          battle_controller port: HP, damage routing, queue, statuses, score (W0-G1)
    run.lua             ladder, difficulty copies, boss heal, between-fight beat, records helpers (W0-G2b)
    debug.lua           game-state helpers of the debug panel (kill / heal / hurt / god / statuses / board cheats), marks run.dev (W0-D1)
  data/enemies.lua      the 10 enemies + 29 abilities (generated once by tools/convert_enemies.py, hand-owned now)
  ui/                   WoW frames, the only WoW-API code (see "UI (W0-P1)")
    assets.lua          every texture / mask / font / template / colour reference
    board_view.lua      pooled gem frames, reads gem.x/y/fx, badges, selection glow
    input.lua           drag-to-swap + click-select -> combat:try_swap
    fight_view.lua      fight screen from combat:hud_state + events (W0-P2; replaced hud_min.lua)
    juice.lua           pooled shards / rings / streaks + trauma shake (W0-P6), fired by fight_view; W0-P7: soft glow, signatures, dust
    board_fx.lua        ability effects on the board (flash / chain_hop events), combo meter, board light (W0-P7)
    hit_fx.lua          chip bars, low HP, status pop / blink / shatter / aura, windup telegraph, entrance / death, number pop (W0-P8)
    window.lua          window chrome: title strip, close/pause, board + enemy panels, bottom strip, FX layers, overlay
    panel.lua           menu widget kit: dialog, buttons, checks, segments, sections, icons (W0-P12; start_menu / result / menu use it)
    debug.lua           the debug panel: /dchess debug, nine tabs (W0-D1, Live tab W0-P5, Board FX W0-P7, Hit FX W0-P8)
    main.lua            SavedVariables, slash commands, driver, fight flow, soft pause, persistence
test/                   ← headless tests; `tools/checks.sh` runs them (lua5.1 + luajit)
  loader.lua t.lua helpers.lua   loader (strict globals), assert helper, board/tape/recorder
  lint_globals lint_yield rng_test match_test scheduler_test sim_test effects_test
  pause_test soak               (+ golden_boards.lua, generated)
  ui_smoke wow_stubs            ui/ under a stubbed WoW API (strict globals, recording frames)
  combat_test ability_test enemy_stub_test fight_bot_test   (W0-G1)
  enemy_data_test enemy_test enemy_bot_test                (W0-G2a; golden_enemies.lua, generated)
  run_test                                                (W0-G2b)
  debug_test ui_debug_test                                (W0-D1: core helpers; panel, dev fight, channels, tuning)
  ui_fx_test ui_menu_test ui_juice_test ui_boardfx_test    (W0-P3..P7: effects / sounds, menu / hint, juice, board effects)
tools/
  checks.sh             single test list; `--list`
  export_golden_boards.gd  Godot → test/golden_boards.lua (region-matching parity)
  export_enemy_golden.gd   Godot → test/golden_enemies.lua (enemy data parity, run once)
  convert_enemies.py       one-shot .tres → data/enemies.lua (history, not in checks.sh)
```

Rule: `core/` never calls WoW globals (`CreateFrame`, `GetTime`, …). `ui/` never contains game
rules. This mirrors Godot's "board knows no combat" split and is what makes headless tests and
a later balance bot possible.

## Dev build vs release build

The repo itself (symlinked into the client as `<WoW>/_forever_/Interface/AddOns/DragonChess`) is the **dev build**: it contains the debug tooling
(`core/debug.lua` game cheats, `ui/debug.lua` panel, the title-strip "Debug" button, `/dchess debug|fight|bg`, `/dcfx`,
`/dcsnd`, `/dcbg`). `core/debug.lua` sets `ns.DEV = true`; everything dev-only is gated on `ns.DEV` / `ns.Debug` /
`ns.DebugPanel` being present, so the addon also loads and runs without those two files.

The **release** has no debug features. Releases are cut by pushing a tag `v<version>`: the BigWigs packager
(`.pkgmeta`, `.github/workflows/release.yml`) builds the zip without `docs/ test/ tools/ probe/` and without the two
debug files (their TOC lines sit between `#@debug@` markers, which the packager disables) and uploads it to GitHub
Releases and CurseForge (secret `CF_API_KEY`). `tools/package.sh` builds the same content locally: it stages a copy of
the addon, removes `core/debug.lua`, `ui/debug.lua` and their two TOC lines, fails if a `debug.lua` or a debug TOC line
is left, and zips the staged tree to `dist/DragonChess-<version>.zip` (`--stage <dir>` only stages, no zip). The public
texts are `README.md`, `CHANGELOG.md` and `docs/store/curseforge-description.md`. In a release build `/dchess debug`, `/dchess fight`,
`/dchess bg` are unknown commands (normal help); a saved `db.debug.enemy_tuning` is ignored. `test/release_test.lua`
loads the release TOC (`loader.toc_files{release = true}`), plays a few seconds and checks the dev surface is gone and
that the TOC lists every `.lua` file.

## Port map

| Godot system | Addon | Notes |
|---|---|---|
| `scenes/board.gd` (grid, region matching, gravity, ability primitives) | `core/board.lua`, `match.lua`, `scheduler.lua`, `board_effects.lua`, `sim.lua` | Event-driven continuous sim time (`Sim:tick(dt)`, dt-independent), coroutine-driven resolve; view reads `gem.x/y/fx/fx_t` and events, never drives logic |
| `rng_util.gd`, seeded streams | `core/rng.lua` | Arithmetic-only PRNG (no `bit` lib), streams `refill`/`effects`/`combat` like Godot |
| `battle_controller.gd`, `battle_status_math.gd` | `core/combat.lua` | HP, damage routing, ability queue, statuses |
| `scenes/abilities/<color>/` (6 kits × skill/ult) | `core/abilities/<color>.lua` | 12 effects as data + small effect functions; class mapping in W1 |
| `scenes/enemies/*.tres` (10 enemies + abilities) | `data/enemies.lua` (generated) | Converter script reads the `.tres`; ability types (MultiHit, StunAbility, …) become Lua effect types |
| `run_manager.gd` ladder, difficulty, score | `core/run.lua` | 10 fights, difficulty 1–5; **no boons, no draft** |
| `board_input.gd` | `ui/input.lua` | Drag/click swap via cursor position; single swap entry point |
| `game.tscn` HUD, `fight_fx.gd` | `ui/*.lua` | Cheaper FX: textures + alpha/scale tweens, no particles; native WoW look |
| `pause_menu`, `settings` | `ui/` + `SavedVariables` | Hide = pause; options in WoW interface panel |
| `telemetry.gd` | — (later: local run log) | Not needed for W0 |

## Cut (kept in docs/archive and on `archive/godot-roguelite`)

Boon draft and boons ([boons.md](boons.md)), relics, shop, doors, ascension, run-scoped kits
mutation (kits stay fixed per class), grid-fight prototype, agent harness / MCP, telemetry,
main-menu scene, parallax backgrounds.

## Reused as-is

Rules and numbers: [combat.md](combat.md), [abilities.md](abilities.md), [enemies.md](enemies.md),
[scoring.md](scoring.md), [run.md](run.md) (ladder, difficulty). Where those docs describe cut
features, ignore them for the addon.

## Core (W0-T1): contract and known divergences from Godot

API: `Sim.new{seed | board, rng_refill, rng_effects, release_on_settle}`; `sim:tick(dt)`,
`sim:try_swap(a, b)` → `"ok"` / `"invalid"` / `"paused"` / `"unsettled"` / `"not_adjacent"`,
`sim:on(event, fn)`, `sim:set_drain(fn)` (combat's ability queue; runs as a sim coroutine, the
cascade continues when it returns), `sim:pause_gameplay()` / `resume_gameplay()`,
`sim:settle_now()`, `sim:serialize()` / `Sim.deserialize()` (at rest only), board primitives as
`sim:clear_area(…)` etc. (call from a sim coroutine). Events: see the header of `core/sim.lua`.
Without combat, `release_on_settle = true` lifts spawn protection on `board_settled`.

Divergences (deliberate or by construction):

- **Time:** exact event times instead of Godot's per-frame tween/timer steps (a 0.14 s tween
  ends at 0.14, not on the next frame; the convert stagger's `process_frame` poll resumes at once).
  No hitstop (`Engine.time_scale` dips), accepted.
- **RNG:** MRG32k3a instead of PCG32 (Godot draws can't be reproduced); the board calls only
  `stream:range_i` / `Rng.shuffle_with`, so a recorded Godot tape can be injected (stub in
  `test/helpers.lua`; the Godot tape exporter is not written yet).
- **Gravity race (port as-is):** collapses move any non-nil gem, also SWAPPING / CLEARING ones,
  exactly like `_collapse_column_animated`. Soak (10 000 swaps, combat stub firing primitives,
  grid integrity checked every tick): ~700 busy gems moved per run, 0 overlapping gravity passes,
  no duplicated / lost / stuck gems on any seed tried — not fixed.
- **Motion:** one motion per gem, a new one starts from the current position and replaces the
  old (Godot lets two tweens write `position` until the older ends). Visual only.
- **Freed gems** are `removed` at once (Godot `queue_free` stays valid until frame end). A Godot
  tween whose targets were all freed never finishes; core skips such waits (race-only).
- **`shuffle_board` is bounded** (1000 rounds, `board_shuffled(false)` when no move can be
  made): Godot's loop never ends when plain gems can't form a move (e.g. a junk-covered board).
- **`would_swap_match` on an empty cell** returns false (Godot would error; it only probes full
  boards).
- **Events:** `gems_cleared(counts, order)` (order = Godot dictionary order), `junk_spawned(gems)`
  instead of pixel positions; added `gem_created`, `gem_removed`, `flash`, `chain_hop`,
  `board_shuffled`. Cells are a flat array (`board:get(col, row)`), not `cells[col][row]`.
- **Not ported:** `clear_cross` (Crossfire boon, boons are cut), visual-only randomness, the
  `is_inside_tree()` shortcuts.
- **Known Godot behaviour kept (parity):** `find_possible_move` counts a junk gem's colour (like
  `would_swap_match`), so a board whose only "moves" involve junk is not reshuffled although every
  real swap is rejected — a dead end until something clears the junk.

## UI (W0-P1)

Install: symlink the repo root into `<WoW>/_forever_/Interface/AddOns/DragonChess` (live client; the beta used `_classic_beta_`).
`/dchess` or `/dragonchess` toggles the window, `/dchess reset` starts a new run (new seed, clears
the saved run), `/dchess combat` toggles "hide in combat" (default on, also in the menu).

- **Window** (`DragonChessFrame`, strata HIGH): scale 1.0 (`DragonChessDB.window.scale`,
  0.5–2, no UI yet), moved only by the title bar, clamped, position saved on drag stop
  (`DragonChessDB.window.point/rel/x/y`). Close button or Esc (via the Esc catcher, see "UI (W0-P4)") hides it. Created
  lazily on the first `/dchess`. Layout since W0-P2: see "UI (W0-P2)" below (the W0-P1/G1 version
  was a 100 px text HUD strip above an 8 × 56 px board).
- **Driver:** one `OnUpdate` on the window: input update → `sim:tick(elapsed)` → pending next fight →
  view update → HUD update; runs only while shown, not soft-paused and not crashed. Hide = pause
  (no tick, input cancelled); combat's enemy and status clocks are timers on the sim's gameplay time,
  so hiding freezes attacks, statuses and the fight transition too (ui_smoke checks it).
  `combat:try_swap`, run start and the frame step (tick + fight start + view + HUD) run in `pcall`; an error goes to
  `geterrorhandler()` once, stops the driver and shows "click to start a new run" (a dead coroutine
  leaves the board unusable). `ns.traceback` = `debugstack(co)` so core errors carry the coroutine stack.
- **Fight flow (W0-G1; superseded by "Run (W0-G2b)" below: ladder, `run:update()`, stage label from the run):** the sim is created *without* `release_on_settle`
  and `Combat.new{sim, seed, kit = Kit.default()}` hooks onto it; every fight is
  `Enemy.STUBS.hellhound`. Swaps go through `combat:try_swap`; gate reasons show a short text
  over the board (`stunned` → "Stunned!", `not_in_fight` → "Wait for the next enemy"; `game_over`
  is covered by the overlay). `enemy_defeated` → CLEARED over the board → after 1.75 sim seconds
  (Godot `FIGHT_DEATH_BEAT` 1.0 + `FIGHT_CLEAR_STING` 0.75) `combat:start_fight` with a fresh Hellhound;
  HP, score and statuses carry over (score accumulates per run, in memory). `run_lost` → overlay
  "Defeated! Score N – Click to try again"; the click starts a new run (new seed, score 0).
- **Minimal HUD** (`ui/hud_min.lua`, W0-G1 4b; **removed in W0-P2**, history only): enemy name + weakness, enemy HP
  bar, next three intents (name, damage range), hit timer ("hit in 2.4s" incl. the wind-up; "NOW!"
  while winding up; "STUNNED"/"FROZEN" + remaining) with a thin timer bar, player HP bar (turns
  violet while stunned), status line (Shield ×n, Stunned / Fire Shield / Lifesteal / Curse ×m /
  Heal Block with whole seconds), score, "-dmg" / "+heal" / "Blocked" / "Reflected" pops next to the
  bars, ability banner (toast + blurb from `ability_triggered`, holds 1.1 s, fades 0.4 s), CLEARED.
  All fades use sim time. Per frame it reads `combat:hud_state(out)` into one reused table; setters
  run only on changed values, timer strings come from a precreated tenths cache, the status line is
  rebuilt only when a whole second changes. ui_smoke: HUD + view allocate 0 KB over 300 fight frames
  (lua5.1); whole idle driver frames < 4 KB. Core timers allocate ~7 KB per 300 frames while the enemy
  attacks (a coroutine per clock start) – core, not the view. No spell-icon overlay on ability gems
  yet (optional in the spec; W0-P2).
- **Soft pause** (window stays open, overlay "Paused (reason) – click to resume", input blocked):
  `LFG_PROPOSAL_SHOW`, `READY_CHECK`, `PLAYER_ENTERING_WORLD`, `UPDATE_BATTLEFIELD_STATUS` when
  `GetBattlefieldStatus(index) == "confirm"`. Events are registered in `pcall`. Reopening the window
  clears a soft pause.
- **Hide in combat** (`DragonChessDB.options.combat_hide`, default on; menu "Hide in combat", `/dchess
  combat`): `PLAYER_REGEN_DISABLED` hides an open window (hidden = paused), `PLAYER_REGEN_ENABLED`
  reopens it at the resume panel (still paused until Continue). Only a window that combat closed is
  reopened; opening or closing it by hand during combat cancels the reopen (`App.hidden_by_combat`).
  Replaces the old opt-in soft pause `DragonChessDB.pause_in_combat` (cleared on load).
- **Board view:** 64 pooled gem frames (created once with the view; a safety net creates one more
  if ever needed). Each frame: gem icon (`ns.Assets.GEM_ICON[type]`, cropped 0.08–0.92, round
  Selectable gem sets (W0-P5): `Assets.GEM_SETS` = `wow` (above) and `shapes` (raid-target markers, unmasked: Amber circle, Amethyst diamond, Emerald triangle, Ruby cross, Sapphire square, Topaz star; paths `Interface\TargetingFrame\UI-RaidTargetingIcon_2/3/4/7/6/1`, not live-probed). Active set `DragonChessDB.gem_set` (default wow, menu "Gems: ..."), read via `Assets.gem(t)` / `Assets.apply_gem(tex, t)` (board gems + weakness icon; missing entry falls back to wow). Switch redraws at once (`App.set_gem_set`).
  mask), additive gold glow while `protected`, corner badge rim + pip (tier 1 blue/white, tier 2
  orange/gold, bomb black/red), junk = desaturated + darkened. Position = `gem.x/y` (+ the input's
  drag offset), CENTER-anchored to the board's top-left; refills above the board are clipped
  (`SetClipsChildren`). Effect curves (view-only): clear grow + fade, fuse shrink + fade, pop /
  land bounce, telegraph pulse, morph out/in scale. Setters only run when a value changed; no
  tables per frame (ui_smoke: < 4 KB per 300 idle frames).
- **Input** (Godot `board_input.gd` constants): deadzone 8 px at a 62 px cell (scaled), release
  commit ≥ 0.28 cell, auto-commit ≥ 0.52 cell while held, re-aim below 0.18, lateral wiggle 0.24,
  soft overshoot ≤ 0.1; the neighbour slides back past 0.5. A press without drag is a tap:
  select / deselect / swap with the selected gem (the core's `not_adjacent` moves the selection).
  Cursor: `GetCursorPosition() / GetEffectiveScale()` minus `GetLeft()/GetBottom()`, row flipped.
  Release = `OnMouseUp`; the `IsMouseButtonDown` poll is the fallback. The drag follows the cursor
  directly (no smoothing, unlike Godot's `DRAG_FOLLOW` lerp).
- **Persistence (W0: fight boundaries only):** `DragonChessDB = { window = {…}, run, options = {…, combat_hide} }`
  with `run = { v = 3, combat = <Combat:serialize()>, board = <Sim:serialize()> or nil, ladder = <Run:serialize()> }` (v = 2 before W0-G2b), written
  when a fight starts (the state right before it; the board only if at rest then) and refreshed on
  `PLAYER_LOGOUT` (also `/reload`) while between fights (after a kill). Mid-fight logout keeps the
  fight-start snapshot, so **a `/reload` mid-fight restarts that fight** with the HP / score /
  statuses it started with (and its board, or a new board if the board was busy at that boundary).
  A lost run or an error clears `run`; not touched if the window was never opened this session. The
  first show restores `run`; a corrupt / other-version snapshot (incl. W0-P1 board-only `v = 1`
  ones) starts a new run silently. Missing DB = normal first run (beta cold-start SavedVariables bug).
  `DragonChessCharDB` is declared and initialised but unused (reserved).
- **Globals:** `DragonChessDB`, `DragonChessCharDB`, `DragonChessFrame`, `SLASH_DRAGONCHESS1/2`,
  `SlashCmdList.DRAGONCHESS` — ui_smoke fails on any other.

## UI (W0-P2): Godot-style fight screen

Spec: [../specs/w0-p2-godot-style-hud.md](../specs/w0-p2-godot-style-hud.md). Static chrome in
`ui/window.lua`, widgets in `ui/fight_view.lua` (`App.hud`), every asset in `ui/assets.lua`.

- **Backgrounds (W0-P2.1, W0-G2c):** since W0-G2c each stage uses a loading-screen file
  (`Assets.STAGE_BG_FILE` = 131835 / 131886 / 131819 / 131827 = Dire Maul / Zul'Gurub / Ahn'Qiraj / Blackwing
  Lair; `Assets.STAGE_NAME`), cover-fit with an assumed 1024x512 image (`Assets.BG_FILE_W/H`; crop via
  `Assets.cover` / `cover_coords`, never stretched). If the file does not load (`GetTexture` nil) the atlas
  `Assets.STAGE_BG_NAME` (cover-fit via `C_Texture.GetAtlasInfo`) and then the colour are the fallback. Board dim
  55 %. `/dcbg` cycles the 9-item `Assets.BG_LIST` shortlist (`{name, id}`) and prints name + FileDataID. Enemy model framing: `Assets.MODEL_DEFAULT`
  + per-enemy `cam_scale` / `pos` / `rot` / `scale` in `Assets.ENEMY`; `/dcbg cam <scale> [x y z [rot]]`
  re-frames live; `SetAnimation(0)` after the model is set.
- **Layout** (1010 × 588 at scale 1.0): title strip (drag handle, "II" pause button = soft pause
  "paused", close button), **board panel** left (524 × 524: stage art under a 72 % dark layer,
  translucent checker tiles, 8 × 64 px board), **enemy panel** right (470 × 524, stage art at full
  brightness), **bottom strip** (30 px): player status icons + player HP bar | score plaque at the
  seam | enemy HP bar. Panels use the tooltip border, the window the gold dialog border. The overlay
  (soft pause / game over / error) covers both panels + the strip with a gold-bordered dialog box.
- **Enemy panel:** "STAGE 1-1" (from the run since W0-G2b), name in capitals, "WEAK <gem icon> TOPAZ".
  Enemy = `PlayerModel:SetModel(Assets.ENEMY[display].model_id)` (FileDataID, roster.md; a file the client
  cannot load reports `GetModelFileID` nil/0), then `SetDisplayInfo(display_id)` (1000), re-applied
  on every window show; if the frame type or all calls fail → round portrait icon (+ ring atlas). All pcall-guarded.
  Hit: size punch (6 %, 0.22 s) + additive red disc; death: fade out 0.6 s; new fight resets.
- **Attack queue** (column on the enemy panel's left edge): 3 round intent icons from
  `hud_state.intents` (52 px current, 40 px next two; special = orange disc + ring tint), a
  `Cooldown` sweep on slot 1 over the attack cycle incl. the wind-up, timer text under it
  ("2.4s" / red "NOW!" + additive pulse while winding up / violet "STUNNED" / "FROZEN"), enemy stun /
  freeze and slow slots at the bottom (icon + whole seconds + dark elapsed part).
- **Cooldown vs sim time:** the Cooldown widget animates on `GetTime()`; the view re-sets it whenever
  `GetTime() - (cycle - remaining)` drifts > 0.08 s from what it set, and clears it on hide, soft
  pause, error and game over (`FightView:freeze()`), so it always shows the sim's attack timer.
- **Bottom strip:** status icons (shield stacks, fire shield, lifesteal, curse, stun, heal block)
  packed left in that order, number = stacks / whole seconds, elapsed part dimmed from the top. HP
  bars = `StatusBar` + `Interface\TargetingFrame\UI-StatusBar`, "cur / max"; player bar violet while
  stunned, then heal-block grey, curse purple (Godot colours). Score plaque: parchment atlas
  (fallback achievement parchment file) + gold border, count-up over 0.45 s.
  **Per kit (W1-G1 B):** `FightView:_apply_kit(kit)` (called from `bind`, i.e. start, resume, restart, debug fights; also
  once with nil in `new`) sets the strip icons from the kit (shield <- Emerald skill, fire shield <- Ruby ult, lifesteal <-
  Amber skill), the enemy stun / freeze icon (Amethyst skill / Sapphire ult), the label over the attack slot
  (`A.FX[<spell id>].status_text`: FROZEN / STUNNED / SILENCED / ROOTED) and the held enemy effect (`hold_fx`: `freeze`,
  `stun_stars`, `roots_hold`; `Fx:hold(name, on, key)` shows `key` on the frame instead of the `A.FX_HOLD` default and
  replaces a different model on the same frame). No kit = the old fixed keys / literals. A small class label (class
  colour, "Classic" for the default kit) sits at the right end of the player HP bar.
- **FX:** ability banner (BossBanner atlas + filigree, spell icon from `ability_triggered.icon`, title,
  blurb; in 0.12 / hold 1.1 / out 0.4 s), CLEARED (banner art, fade in 0.2 s), floating damage numbers
  (8 pooled FontStrings on the enemy, 4 for player pops: -dmg / +heal / Blocked / Reflected / Heal
  blocked; rise 46 px over 0.9 s, boosted hits gold + larger font), red edge vignette 0.35 s on
  `player_damaged`, swap feedback ("Stunned!") over the board. All on sim time.
- **Board view:** ability gems show their ability's spell icon (round, 56 % of the gem, on a dark
  disc; bombs the bomb icon). The key comes from `view:set_icon_source(fn)` — `ui/main.lua` asks
  `combat.kit:get(colour, tier).icon`; the lookup runs only when a gem's look changes.
- **Sounds:** since W0-P3 one slot table, see "UI (W0-P3)" below and [audio.md](audio.md).
- **Fallbacks:** every atlas via `Assets.apply(tex, spec)` = `C_Texture.GetAtlasExists` +
  `pcall(SetAtlas)` → file → colour (rings / filigree just hide); `CreateFrame("PlayerModel")` and
  `CreateFrame("Cooldown")` in `pcall` (no sweep → the timer text remains).
- **Budget:** ui_smoke measures fight view + board view at 0.11 KB per 300 live fight frames (lua5.1,
  limit 1 KB) and whole idle driver frames at < 1 KB.
## UI (W0-P3): sounds, spell effects, creature animation

Spec: [../specs/w0-p3-audio-fx-anim.md](../specs/w0-p3-audio-fx-anim.md) (implemented, awaiting in-game playtest).
Slot table with the final IDs: [audio.md](audio.md). All asset ids live in `ui/assets.lua`.

- **Sounds** (`Assets.SOUNDS[slot]`): `{kit = id | SOUNDKIT name | list}` → `PlaySound`, `{file = FileDataID}` →
  `PlaySoundFile`; fields `gap` (min seconds between plays = rate limit, `GetTime`), `max` (cut-off: the handle is
  `StopSound`ed after `max` s, default 1.5 for files, by `Assets.tick()` from the HUD frame; a fixed 8-entry ring, no
  allocation), `key` (plays in quiet mode, else `Assets.KEY_SOUND` by slot name), `fallback` (kit slot when
  `PlaySoundFile` is missing / fails: `player_hit` falls back to kit 129 cut at 0.6 s). `Assets.play(key, file, force)`
  is the single gate (`sound_enabled`, `quiet`; `force` = `/dcsnd`, skips quiet + gap). Events (fight_view handlers):
  `gems_cleared` → `gem_break` (kit 101, gap 0.1), `swap_rejected` → `miss` (139), `attack_blocked` /
  `attack_reflected` → `blocked` (132), `player_damaged` → `player_hit`, `ability_triggered` → `ab_<ability id>` (bombs /
  unknown ids: generic `ult` / `ability`), `enemy_windup` / `enemy_damaged` / `enemy_defeated` → `enemy_attack` /
  `enemy_wound` (gap 0.4; **removed in W0-P3.1**, see below) / `enemy_death` with the file from the enemy def (`attack_sound` / `wound_sound` /
  `death_sound` in `data/enemies.lua`, optional, silent when absent). Quiet mode keeps ult sounds, player hit,
  blocked, cleared, defeat.
- **Spell effects** (`ui/fx.lua`, `App.hud.fx`): a pool of `PlayerModel` frames created once (6 one-shots + 4 state
  frames, hard cap; a full pool recycles the oldest), shown with `SetModel(m2 FileDataID)` + `SetAnimation` +
  per-effect framing defaults. `Assets.FX[key] = {m2, at = enemy|player|board|cell|cone|row, size, scale, offset,
  px, cam_scale, rot, anim, duration, gap}`. One-shots: per ability (key = ability id; cell = the gem's cell,
  cone = toward the enemy, row = the gem's row), `enemy_hit` (replaces the red disc; the disc stays when no effect
  frame can show; nil from `Fx:play` = throttled). State effects (`Fx:hold(name, on)`, polled from `hud_state`
  every frame): `stun_stars` above the enemy while stunned, `freeze`, `aegis`, `mirror`. Lifetimes count in sim
  time (`Fx:update(now)`); models animate on engine time, so `FightView:halt()` (hide, soft pause, menu, game
  over, error, reset) hides every effect and cuts pending sounds, and nothing plays while the sim is frozen (no
  event fires, the HUD update does not run). Every model call is pcall-guarded; a model that fails is hidden (a
  failed state effect is not retried). No `PlayerModel` → `Fx.NONE` (no effects, disc fallback).
- **Creature animation** (enemy `PlayerModel`, `Assets.ANIM`): stand 0 on show; attack 17 (fallback 16) at
  `enemy_windup` for the wind-up + 0.35 s; wound 8 on `enemy_damaged` (0.45 s, throttled 0.6 s, never over an
  attack); stun pose 14 while stunned; death 1 at `enemy_defeated`, then the fade after `death_hold` 0.7 s.
  Priority death > stun > attack > wound > stand; `SetAnimation` only on change.
- **Dev commands:** `/dcfx` lists the event / hold keys and the current kit's 12 spell ids (any other key still works),
  `/dcfx <key>` plays one (6 s), `/dcfx cam <scale> [x y z [rot]]`
  re-frames the last played effect and prints the values for `Assets.FX`; `/dcsnd` lists sound slots,
  `/dcsnd <slot> [FileDataID]` auditions one (also creature slots with a file). Globals: `SLASH_DCFX1`, `SLASH_DCSND1`.
- **Tests:** `test/ui_fx_test.lua` (asset-table sanity, event → slot, gap, quiet / sound-off, cut-off, hide / pause
  stops, effect pool cap + targets + stop conditions, model / sound failures, animation ids, allocation budget
  < 1 KB per 300 HUD frames with effects live).

## UI (W0-P3.1 / debug panel): display-ID models, LFG backgrounds, sound balance, stage names, `/dchess debug`

Spec: [../specs/w0-p31-polish-and-debug-panel.md](../specs/w0-p31-polish-and-debug-panel.md) (implemented, awaiting
in-game playtest). Tables in `ui/assets.lua`; sound slots / channels in [audio.md](audio.md); enemy IDs in
[roster.md](roster.md).

- **Models:** `Assets.ENEMY[id].display_id` is shown with `SetDisplayInfo` (textured). Chain in
  `FightView:_show_enemy`: display ID -> `model_id` via `SetModel` (untextured, rejected when `GetModelFileID` is
  nil / 0) -> portrait icon. Framing (`cam_scale`, `pos`, `rot`, `scale`) per enemy, tuned live
  (`FightView:reframe()`), pasted back into the table. `Assets.format_enemy(key)` prints the paste line.
- **Backgrounds:** `STAGE_BG_FILE` = the four LFG files; `BG_FILE_W` x `BG_FILE_H` (512 x 256, assumed 2:1) drive the
  cover-fit crop; a `BG_LIST` entry may carry `w` / `h`. `FightView:cycle_bg(dir)` steps the 13-entry shortlist
  (`/dcbg` = next; the panel has prev / next / print). A file that does not load falls back to the stage atlas, then a
  colour (unchanged).
- **Stage label:** `STAGE 1-2 · DIRE MAUL` (`Assets.STAGE_NAME`, UTF-8 U+00B7); the dev fight keeps `DEV`; a phase name
  is appended as before.
- **Sounds:** per-slot `channel` (`Assets.play` passes it to `PlaySound` / `PlaySoundFile`; fallbacks inherit it);
  `player_hit` + `enemy_attack` on `"Ambience"`; no creature wound sound. `Assets.channel_of / set_channel /
  next_channel` (the panel's channel buttons).
- **`/dchess fight <id>` (fixed):** `App.dev_fight` first brings the game into a visible state (creates + shows the
  window, starts / restores the run, closes the menu, lifts a soft pause, replaces a lost / won / crashed / stuck
  run), then calls `ns.Debug.fight`; the slash handler always prints `fight: <id>` or the reason and routes errors to
  the chat + error handler. Offline (stubs) the old command always worked, so the live "does nothing" was most likely a
  hidden / paused window or an open menu (the enemy switched silently behind the overlay, nothing printed on success);
  not reproducible beyond that, confirm in game.
- **Debug panel** (`ui/debug.lua`, helpers in `core/debug.lua`): `/dchess debug` (first use enables it:
  `DragonChessDB.debug.enabled`; later toggles; `/dchess debug off|on`). Position + tab stored in `DragonChessDB.debug`.
  A separate movable `DIALOG` frame (not tied to the window); created once on first open; the OnUpdate runs only while
  shown (cuts finished sounds with `Assets.tick`, refreshes the footer twice a second; `App.profile` makes
  `on_update` measure the frame cost into `App.frame_ms` / `frame_peak`). Tabs:
  - **Fights:** one button per enemy (= `App.dev_fight`), Difficulty -/+ (next fight), Kill enemy, Next fight (back to
    the ladder), Heal / Hurt player (never lethal), God mode, Restart run (the only action that clears the dev flag).
  - **Board:** spawn a skill / ult gem of a colour at a random settled plain cell (`Sim:spawn_ability_gem`), convert
    5 random gems to a colour, Junk x4, forced Shuffle (own re-roll of every plain gem; at rest only).
  - **Status:** stun / freeze / Aegis / Mirror (enemy, need a live enemy), stun player, heal block, curse, Sandstorm;
    numbers in `Debug.STATUS` (`core/debug.lua`), "Print values".
  - **Effects:** one button per `Assets.FX` key (replaces typing `/dcfx`; needs the window open and not paused), Stop.
  - **Sounds:** one button per `Assets.SOUNDS` slot (forced play, ignores quiet / gap; creature slots use the current
    enemy's file) + a channel button (SFX / Amb / Dlg / Mst) + "Print channels".
  - **Tuning:** background prev / next / print (name + FileDataID shown), enemy model steppers for cam / x / y / z / rot /
    scale (edit `Assets.ENEMY`, re-frame live, print the line; Reset enemy, Print enemy, Print all), reset the frame peak.
    The footer (every tab) shows FPS (`GetFramerate`, guarded), smoothed + peak frame cost (ms) and the run state.
- **Dev run rule:** every game-state action marks the run `run.dev = true` (`ns.Debug.mark`); `ui/main.lua` never writes
  records or the boundary snapshot for a dev run (unchanged W0-G2a rule). Cosmetic actions (effects, sounds, backgrounds,
  framing) do not mark it. Game actions work while the window is hidden / paused (`App.show()` opens it if there is no
  game yet); effects obey pause. Core board work that waits (convert, junk) runs as a `sim:spawn` coroutine like an enemy
  ability; the UI wraps every call in `pcall` (core has no pcall) and prints the `ok, message` result.
- **New API use (all guarded):** `GetFramerate` (unverified in the baseline; `type()` check), `PlayerModel:SetDisplayInfo`
  (live-verified with display 1000), the channel argument of `PlaySound` / `PlaySoundFile` (`"SFX"` verified; `"Ambience"`
  is the standard channel name, unverified in the Forever client).
- **Tests:** `test/debug_test.lua` (every helper on the real sim / combat / run), `test/ui_debug_test.lua` (dev fight in
  never-opened / hidden / paused / menu / lost / mid-fight / error states with feedback, panel enable / toggle / persist,
  every tab's buttons against the real game, effects vs pause, channel cycling, tuning writes + paste lines, dev run never
  recorded or saved, allocation budget), updated `ui_smoke` / `ui_fx_test` (display-ID chain, shortlist, stage names,
  Ambience channel, no wound sound). Stub additions (append-only): `GetFramerate`, `W.error_displays`.

## UI (W0-P5): match / spawn / cast feedback, swap hint, debug additions

Spec: [../specs/w0-p5-feel-and-debug.md](../specs/w0-p5-feel-and-debug.md). Awaiting in-game playtest; sound file IDs
are unconfirmed picks (audition with `/dcsnd <slot>`). Needed no core event changes: all events existed.

- **Match float + sound** (`FightView:_on_match`, `match_resolved`): pool `pops_match` (8 FontStrings on the board fx
  layer, no allocation while playing, text string per event) shows "MATCH" / "N-MATCH" and "+points"
  (`Combat.match_score`) at the centre of the region's gems. Sounds `match_4`..`match_7` by length (7+ = deepest file);
  a 3-match at chain depth >= 2 plays `match_cascade`; a plain first-level 3-match is silent (the per-wave `gem_break`,
  kit 101, stays). Godot raises the pitch with the cascade; WoW has no pitch, so a different slot stands in. Quiet mode
  mutes all of them.
- **Ability gem spawn** (`ability_gem_spawned`): float with the ability name (cyan), `ability_spawn_skill` /
  `ability_spawn_ult` (key sound), ult banner "<NAME> READY". The banner is `FightView:_show_banner(icon, title,
  blurb, enemy)`, shared by player abilities and enemy specials (last one wins).
- **Enemy cast** (`enemy_ability_executed`): orange additive `cast_glow` over the figure (0.4 s) on every cast; specials
  also show the banner (intent icon, name, description, red title) and play `enemy_special` (Ambience channel).
  Plain hits have no extra sound (player_hit plays on damage); the creature sound stays at the wind-up.
- **Swap hint** (`BoardView:_update_swap_hints`, port of `_refresh_swap_hints`): selected skill/ult gem -> text
  "SKILL - swap with same colour to activate" / "ULT - ..." at the board bottom and a pooled ring (4) on each settled
  neighbour of its colour; a plain selected gem only rings an adjacent same-colour ability gem; bombs get nothing.
  Evaluated per frame from the board (4 lookups, setters only on change). The "same colour activates" predicate is a
  view-side copy of the sim rule (hint only; the sim still decides).
- **Debug panel:** Fights tab got "Invincible" (`Debug.toggle_invincible`: `combat.enemy_invincible` + live
  `Enemy.invincible`, carried into the next fights; Kill enemy still works) and "Enemy timers" (`Debug.toggle_enemy_timers`:
  `Enemy:set_timers_held` -> `Clock:hold` on the attack cooldown, every wind-up in flight and the multi-step execute;
  statuses keep running; carried into the next fights via `combat.enemy_timers_held`). New 7th tab **Live**:
  `Debug.status_lines(combat, out)` lists player statuses (remaining/max), Sandstorm, enemy stun/slow/Aegis/Mirror,
  "enemy attack in", wind-up, flags; refreshed 4x/s only while the tab shows. All three mark `run.dev`.
- **Deliberately dropped (user decision 2026-10-05):** keyboard shortcuts for the panel. No key capture in the addon.

## UI (W0-P7): board ability effects, chain escalation, gem motion, soft glow

Spec: [../specs/w0-p7-board-effects-and-chain-juice.md](../specs/w0-p7-board-effects-and-chain-juice.md). Awaiting in-game playtest.
Texture research: [wow-effect-textures.md](wow-effect-textures.md).

- **Soft glow material (D):** `Assets.GLOW` = per role (`glow flare ring beam bolt smoke wedge`) `{ primary, fallback }`
  candidates (path or FileDataID). Only `Interface\Cooldown\star4 / ping4 / starburst` are known to exist; the rest is
  unverified. `Assets.soft(tex, role)` tries the candidates (pcall; with `Assets.GLOW_CHECK` a `GetTexture()` of nil counts
  as "not loaded"), caches the resolved path per role and returns true/false; `Assets.soft_report()` ("glow ok, flare
  missing, ...") feeds the Board FX tab. A role may be missing (`false` / `{}`): particles fall back to colour squares, rings to
  the old atlas / disc, streaks to masked discs, cell glows to colour squares, beams to colour quads, the wedge is
  dropped (the column slices carry the wave), auras to masked discs. Swap the paths in `ui/assets.lua` after the in-game check
  (debug panel > Board FX > "Texture test" shows all candidates side by side).
- **`ui/juice.lua` additions:** particles carry a texture role (`glow` default, `flare` for sparkles / sparks / shards of ice,
  `smoke` for dust; chain role -> glow -> square); `Juice.PARTS` 72, `RINGS` 8. `Juice:signature(gem_type, x, y, weight, delay)`
  with the table `Juice.SIGNATURE` (Ruby embers up, Sapphire ice shards down + blue ring, Topaz fast sparks, Amethyst wisps
  drifting inward, Emerald leaves/motes, Amber gold motes + ring). `Juice.chain_scale(depth)` (pure, e = min(depth, 6) - 1):
  shards x(1 + 0.25e), ring x(1 + 0.15e), extra ring from depth 3, trauma + 0.04e, gold vignette peak 0.15 + 0.05e from
  depth 4. `Juice:land_dust(col, row)` (<= 1 puff per column per `DUST_GAP` 0.1 s), `Juice:reject_puff(col, row)`.
- **`ui/board_fx.lua` (`App.hud.boardfx`, stand-in `BoardFx.NONE`):** subscribes (`BoardFx:bind(sim)` in `FightView:bind`,
  `unbind` in `FightView:unbind`) to the sim events `flash(kind, cells, dur)`, `chain_hop(c0, r0, c1, r1)` and
  `board_settled`. The cell list is COPIED into slots. Pools (created once): `CELLS` 64 glow slots, `BEAMS` 4 (trail +
  core), `BOLTS` 8 (10 glow dots + an underlay texture), `WEDGE` 1; a full pool recycles the entry that ends first.
  Kinds: area / color / convert_to / chain = pulse per cell (colour = casting gem, chain = gold); telegraph(_from/_to)
  = pulse for the whole `dur` + closing flash (from = cool, to = gem colour); row_sweep = one beam per direction from the
  origin + cell flashes delayed by distance; wave = wedge (if the texture loads) + column slices `CLEAR_STAGGER_STEP * 2`
  apart + rising embers; chain_hop = jagged chain of glow dots re-jittered every 0.03 s (a stretched bolt texture under
  it for near-horizontal hops) + spark burst at the target. The cast colour comes from `ability_triggered`
  (`set_cast`). Board light (`light(gem_type, tier)`): additive wash (peak 0.18 skill / 0.3 ult, 0.25 s), ult also a 0.3 s
  darkening (alpha 0.35). Combo meter (`combo(depth)`): "x<depth>" gold, scale `BoardFx.combo_scale(depth)` + a 0.2 s punch
  per new level, near the board's top-right, fades 0.3 s after `max(last match, board_settled) + 1.2 s`; a depth-1 match
  resets it. Frame levels (host + n): light 9, glow 10, combo 11.
- **Core addition (additive):** `swap_rejected(a, b)` now carries the two gems (no listener needed it before).
- **`ui/fx.lua`:** `Fx:play(key, col, row, ...)` honours the cell: `at = "cell"` centred on it, `"row"` on its row, `"cone"`
  starts at it and points right (centre shifted `Fx.CONE_SHIFT` x size); nil col/row = centred as before.
- **`ui/board_view.lua`:** `fx_curve` returns two more multipliers (`sx`, `sy`): fall stretches up to 1.06 tall, land
  squashes (1.12 wide / 0.88 tall) and springs back with one overshoot; the frame is `SetSize(w, h)`. `on_land(col, row)`
  (dust) fires once when a gem's effect becomes `land`; swapping gems flash at the swap start; `swap_rejected` shakes the
  two gems sideways (+-0.1 cell, 2 cycles in 2 * SWAP, back to exactly 0) and calls `on_reject` (puff). Ability gem auras
  (B5; W0-P10 calmer: skill 0.6 Hz, ult 0.4 Hz, bomb flicker 15 / 7 rad/s, constants `AURA_*` at the top of `ui/board_view.lua`) are a pool of `AURA_SLOTS` 12 (halo + flare behind the gems, orbit dots in front) assigned to skill / ult / bomb gems,
  not 5 textures per gem frame (64 x 5 would be 320 extra textures). Selection glow breathes (alpha 0.35 -> 0.65 at 1.6 Hz),
  the dragged gem gets a soft halo. `halt_fx()` (called through `FightView.on_halt`) hides auras, halo, shake and flashes.
- **Escalation in the HUD (`FightView:_on_match`):** shards / rings / extra ring through `Juice:match_break(..., depth)`,
  trauma (also for 3-matches at depth >= 2, capped at `TRAUMA_MATCH_MAX`), gold vignette from depth 4 (only if no flash runs).
  `FightView:_on_ability` adds the board light, the signature at the gem cell and (damage abilities) on the enemy when the hit
  lands.
- **Debug panel:** new tab 8 "Board FX": Row sweep, Wave, Chain bolt, Telegraph, Tele from, Area flash, Color flash, Light
  skill / ult, Combo x2..x6, Rejected shake, Land dust, Sig <colour> x6, Texture test, and the glow report line.
- **Tuning:** constants at the top of `ui/board_fx.lua` (pool sizes, `CELL_PEAK`, `CELL_SOFT`, `BEAM_*`, `BOLT_*`,
  `WASH_*`, `DARK_*`, `COMBO_*`), `Juice.SIGNATURE` / `SOFT_SCALE` / `DUST_*` in `ui/juice.lua`, `FALL_STRETCH` /
  `LAND_SQUASH` / `REJECT_AMP` / aura numbers in `ui/board_view.lua`, colours `FX_*`, `AURA_*`, `VIG_COMBO`, `COMBO_TEXT` in `Assets.COLOR`.
- **Not verified live:** every texture except star4 / ping4 / starburst, the look of ADD glows on this board, the frame cost
  of 64 cell textures + beams + bolts + auras (the debug footer shows it), `Texture:GetTexture()` after `SetTexture` as a
  "loaded" test (`Assets.GLOW_CHECK`).

## UI (W0-P8): hit / status readability

Spec: [../specs/w0-p8-hit-status-readability.md](../specs/w0-p8-hit-status-readability.md). Awaiting in-game playtest.

- **`ui/hit_fx.lua` (`App.hud.hitfx`, stand-in `HitFx.NONE`, a plain table without metatable):** `HitFx.new(view, juice)` is built
  once by `FightView.new` (pcall; failure -> stand-in, the view falls back to its old code: `hf.layout` / `hf.pop_frame` are
  nil on the stand-in). The view only forwards: `update(st, now)` (the reused hud_state, after `_update_statuses`),
  `windup(ability, windup, now)`, `blocked / reflected / heal`, `enter` (fight_started), `death(boss, now)`
  (enemy_defeated), `phase`, `score(amount)` (new subscription `score_awarded`), `pop_start / pop_frame` (damage numbers),
  `figure(now, death_alpha)` (-> dx, dy, alpha multiplier of the enemy frame), `layout(icon, x_left, now)` (status strip),
  `halt()`, `dev(kind, now)`. Everything is sim time, created once (2 chip textures, heal flash, 3 halos on the bottom strip,
  1 vignette frame with 8 edges, tele glow, death flash, entrance ring, plaque glint), setters only on quantised change.
- **Chip bars (1):** a texture behind each fill (`BACKGROUND` sublevel 2: player pale red, enemy whitish) holds the old value
  `CHIP_HOLD` 0.35 s after a drop, then slides to the new value in `CHIP_SLIDE` 0.25 s (ease out); whole-pixel widths; heals
  snap it; `HitFx.chip_value(from, target, t)` is the pure curve. The chip is display only: values come from hud_state.
  Heal: green additive flash over the player bar (`HEAL_DUR` 0.25 s, peak 0.45) + a green Juice ring at the bar.
- **Low HP (2):** HP <= 25 % (and > 0, not stunned / over): red glow around the bar (alpha 0.15 .. 0.5) and a heartbeat on the
  hit-fx vignette (0.08 .. 0.2) at 1.2 Hz, 2.2 Hz below 10 %. The hit-fx vignette frame is separate from the view's
  flash vignette (its own colour); the windup telegraph wins over the heartbeat while it runs. Debug "Low HP on/off" forces it.
- **Status icons (3, 4):** each icon (7 player + enemy stun / slow / Aegis / Mirror) has a record. Appears -> scale pop 1.5 -> 1
  in 0.18 s + a Juice ring in the class colour **at the icon's board position** (the strip uses `cx - pad`, the enemy icons
  fixed positions from the layout constants; chosen over an own ring pool because Juice already has one). Last
  `max(2 s, 25 % of max)` -> blink 1 <-> 0.55 at 4 Hz. Disappears with `<= EXPIRE_EPS` 0.35 s left -> 5 shards (Juice
  burst in the class colour); a cleared status (more time left) vanishes silently; the last shield stack shatters smaller (3);
  an eaten shield stack / a re-applied status pops 1.25. The strip is centre-anchored (`CENTER` of the bottom frame, `home`
  tables remembered by the view) and scaled with `Frame:SetScale` with the offsets divided by the scale; re-packing slides over
  `SLIDE_TIME` 0.12 s (whole-pixel setter). The 2 px class edge is the icon's edge texture (now +-2 px), coloured from
  `Assets.STATUS_EDGE[id]`: buffs gold, debuffs violet / red, enemy Aegis gold, Mirror silver, the player's stun / slow on the enemy cyan.
  After `halt()` the next update adopts the current statuses without popping them (`resync`).
- **Aura (5):** `HitFx.aura_pick(st)` = stun > curse > fire_shield > shield > lifesteal; two soft halos (outer + inner) under the
  bar, colour `Assets.STATUS_AURA[id]`, alpha `AURA_MIN .. AURA_MAX` (0.12 .. 0.38), curse 0.5 Hz, others 1 Hz.
- **Block / reflect / heal (6):** block = cyan-white ring at the bar + `VIG_BLOCK` flash (peak 0.35) + shield icon punch 1.4;
  reflect = the old orange flash + fire shield icon punch.
- **Damage numbers (7):** only on the enemy and player pools (`pops_match.plain = true` keeps the board floats as before).
  Pop scale 1.6 (crit 1.9) -> 1 over 0.12 s via `FontString:SetScale` (**unverified**: `HitFx.new` probes it with pcall; without
  it the big font is used for the first 0.12 s and the shake / stack still work), crit shake +-3 px for 0.15 s, player hits
  shake 1 .. 3 px by damage / max HP, extra numbers within 0.12 s on the same pool stack +14 px (max 3), heal numbers rise at 0.6x.
- **Telegraph (8):** `enemy_windup(ability, seconds)` -> tint by `Assets.INTENT_TINT[kind]` (attack red, curse purple, junk
  brown, mirror / aegis silver, anything else orange); glow on the figure `telegraph_env(k)` = 0.5 k with a 3 -> 10 Hz +-15 %
  pulse; the edge vignette ramps 0 -> 0.2 over the last 40 % (`telegraph_vig`). Ends when hud_state stops reporting a windup
  (the hit), on stun, fight over, halt.
- **Figure (9, 10, 11):** entrance = slide 24 px from the right + fade 0 -> 1 in 0.35 s (`figure()` feeds the view's knock
  offset and holder alpha), a soft ring at the feet (own texture), name text punch 1.35 -> 1 (needs `SetScale`). Death = 14
  (boss 20) rising gold / hit-tint motes (Juice particles), white additive flash 0.15 s, ring (boss: wide), upward drift 6 px
  during the existing fade (trauma stays the existing `TRAUMA_CLEARED`). Phase change = impact ring weight 2, trauma 0.3,
  cast-tint flash, name punch.
- **Score (12):** `score_awarded(amount)` (ability activations only; matches score through `score_changed`, which the spec does not
  list) -> plaque `Frame:SetScale` punch 1 -> `score_peak(amount)` (1.08 .. 1.18, capped) -> 1 in 0.2 s + a gold glint.
- **Debug panel (13):** new tab 9 "Hit FX" with one button per entry of `HitFx.DEV_BUTTONS` (chips, heal, low HP, pop per status,
  shatters, auras, block, reflect, telegraph per kind, entrance, death, boss death, phase, score, number stack).
- **Tuning:** constants at the top of `ui/hit_fx.lua`; colours / class tables `STATUS_EDGE`, `STATUS_AURA`, `INTENT_TINT`,
  `CHIP_*`, `HEAL_FLASH`, `LOW_HP`, `VIG_BLOCK`, `DEATH_*`, `SCORE_GLINT` in `ui/assets.lua`.
- **Not verified live:** `FontString:SetScale` (probe + fallback), the look of the halos around the 30 px strip, how the pulsing
  elements (low HP, blink, windup vignette) read together, the soft glow textures (as in W0-P7).

## UI (W0-P6): match break, ability spawn, streaks, damage juice

Spec: [../specs/w0-p6-match-and-damage-juice.md](../specs/w0-p6-match-and-damage-juice.md). Awaiting in-game playtest.
All view-side, sim time, pooled; the only core change is an additive event payload.

- **Core payload:** `match_resolved(length, gems, depth, dest_col, dest_row, spawn_tier)`: `dest` = where the gems
  converge (the ability spawn cell, else the centre gem's cell), `spawn_tier` 0 = no spawn. The sim already moves the
  matched gems to `dest` in `Timings.FUSE` (0.24 s, `gem.fx = "fuse"`), so "the gems run together" is the sim's own motion.
- **Gem break** (`BoardView`, `fx_curve(fx, t)` -> scale, alpha, rotation, flash; every gem frame has a second additive
  copy of its icon, `f.flash`): "fuse" = flash + swell (1.18 at 30 %), then shrink to 0.1 / spin 216 deg / fade while it
  converges; "clear" (ability / junk clears) the same with a longer swell; "pop" (fresh ability gem) flashes. The spin
  uses `Texture:SetRotation` through pcall (first failure sets `BoardView.can_rotate = false`) and only for gem sets
  whose texcoords are the full image (Jewels, Shapes): SetRotation replaces a crop (WoW set). Frames are cleaned
  (flash hidden, rotation 0) on release / re-bind / look refresh.
- **`ui/juice.lua`** (`App.hud.juice`, built in `FightView.new`, stand-in `Juice.NONE` if the build fails, then hit
  reactions run at once): pools built once (`PARTS` 48 colour squares, `RINGS` 6 = the `SLOT_RING` atlas or a round disc,
  `SHOTS` 6 streaks of a head + `TRAIL` 5 dots; a full pool recycles the entry that ends first, a recycled streak
  delivers its hit at once). No frame / table allocation while playing, `update(now)` returns when idle. Coordinates are
  board-local px; targets (`ex/ey` enemy, `px/py` player HP bar, `jx/jy` board right edge) are computed from the window layout.
- **Match break shards:** `match_break(length, x, y, gem_type, delay)` at the convergence cell with `delay = FUSE`
  (particles may start in the future, hidden until then): 6 / 10 / 14 / 18 shards for 3 / 4 / 5 / 6+, a ring from 4,
  gold sparkles from 5. Colour = `Assets.COLOR.GEM_FX[type]`.
- **Ability spawn** (`ability_gem_spawned`): `spawn_fx`: skill = cyan ring + 8 sparks, ult = bigger golden ring + second
  ring + 14 sparks + sparkles; the gem itself pops with a flash.
- **Streaks:** `FightView:_on_enemy_damaged` launches a streak from the origin (match centre, or the ability's gem
  cell after `ability_triggered`) to the enemy, colour = the matched gem / ability gem (default light blue), weight 1 /
  skill 1.4 / bomb 1.2 / ult 2.0 (thicker, 1.4x slower), flight `Juice.FLY` 0.4 s (W0-P10, was 0.2; ult 0.56 s). `FightView:_enemy_hit` (damage number,
  hit effect model or red disc, wound animation, 8 px knock-back out 0.05 / back 0.12) runs when it lands, plus an
  impact ring + sparks. The sim has already dealt the damage (HP bars update at once). Other streaks: enemy cast ->
  player HP bar (boss weight 1.6 else 1.15; curse purple; junk -> board right edge), heal / lifesteal (green, from the
  last match), Fire Shield (orange, player -> enemy: `attack_reflected` marks the sim instant, the `enemy_damaged` right
  after it starts at the player), Mirror bounce (`player_damaged` source "mirror": silver, enemy -> player).
- **Shake:** `Juice:add_trauma(x)` (0..1, stacks), decay 2.4 / s on sim time, window offset = `SHAKE_MAX` 12 px x trauma^2
  (view-only LCG, no core RNG). Triggers: 4+ match 0.1 .. 0.65, skill 0.22, ult 0.55, bomb 0.3, Mirror shatter 0.35,
  CLEARED 0.22, player hit 0.12 .. 0.6 by damage / max HP (full at 15 %). The rest position (`GetPoint(1)`) is captured
  when a shake starts and restored exactly when it ends; also on `halt` (hide / pause / menu / game over / reset), when the
  title strip's drag starts (`Window` hook `on_drag`; the saved position is therefore always the rest one) and when the
  option goes off. Never shakes while dragging.
- **Vignette flashes:** one frame with 8 edge textures recoloured on change (`FightView:_flash_vignette(colour, peak,
  dur)`): red hit (peak 1, 0.35 s), cyan skill (0.5), gold ult (1), silver Mirror shatter (0.6, + the SHATTERED! text,
  shake, impact), orange reflect (0.8); 0.27 s except the hit.
- **Option / menu:** "Screen shake: On/Off" (`DragonChessDB.options.shake`, default on, validated in `init_options`,
  applied by `App.apply_options` -> `hud:set_shake`). Off = no trauma, no window offset (flashes, streaks, shards stay).
- **Debug panel (Effects tab):** Break 3 / Break 5 / Skill spawn / Ult spawn / Streak / Ult streak / Enemy cast / Shake /
  Big shake (`FightView:dev_juice`); they need the window open and unpaused, Shake refuses while the option is off.
- **Tuning:** constants at the top of `ui/juice.lua` (pool sizes, `FLY`, `HEAD`, `SHARD_SPEED`, `SHAKE_MAX`,
  `SHAKE_DECAY`, burst counts) and `ui/fight_view.lua` (vignette peaks, knock-back, weights, trauma values); colours in
  `Assets.COLOR` (`GEM_FX`, `PROJ_*`, `VIG_*`, `RING_*`, `SPARKLE`).
- **Not verified live:** `Texture:SetRotation` on masked textures, ADD blend of the second gem icon, the `SLOT_RING`
  atlas as an expanding ring, `GetPoint(1)` / `SetPoint` shake round trip, the frame cost of 48 particles + 6 streaks +
  64 flash textures. Dropped: hit-stop (the sim is the clock).

## UI (W0-P4): minimap button, menu, idle hint, shuffle feedback

Spec: `docs/specs/w0-p4-menu-hint-minimap.md`. Awaiting in-game playtest.

- **Minimap button** (`ui/minimap.lua`, created in `ADDON_LOADED`): own round `Button` on `Minimap` (no
  LibStub / LibDBIcon), ruby gem icon `INV_Misc_Gem_Ruby_02` with a round mask, classic tracking border
  (vanilla file names, not probed: if missing only the icon shows). Drag = angle around the edge
  (`DragonChessDB.minimap.angle`, degrees, default 225; pure maths `position` / `angle_from`). Left click
  toggles the window, right click toggles the menu, tooltip. Also `AddonCompartmentFrame:RegisterAddon`
  (all in pcall / type checks; a missing `Minimap` or compartment is not fatal).
- **Menu** (`ui/menu.lua`, "Menu" button in the title strip): Restart run (first click arms an inline
  "Really restart? Click again"), Sound On/Off, Quiet mode (only key sounds: ult, player hit, cleared,
  defeat), Difficulty (cycles like the D-button), Window size (Small 0.85 / Normal 1 / Large 1.2), Close
  (closes the menu). Options in `DragonChessDB.options` `{sound, quiet, scale}` (validated in
  `ADDON_LOADED`; empty DB = defaults). All sound goes through the one gate in `Assets.play`
  (`Assets.sound_enabled`, `Assets.quiet`, `Assets.KEY_SOUND`). While the menu is open the game is paused
  (no tick, no input, no overlay) and the menu frame sits above the result overlay (Restart stays reachable).
- **Esc order:** the window is no longer in `UISpecialFrames`; an invisible named frame `DragonChessEsc` is
  (armed while the window is shown). Esc hides it: the menu closes first (catcher re-armed), the second Esc
  hides the window. Hiding the window by any other path closes the menu too.
- **Start / resume panel (W0-P10)** (`ui/start_menu.lua`, driven by `ui/main.lua`): every `on_show` opens it over the
  content area (dim layer, below the menu frame, above the gems); the game is paused like with the menu
  (`App.start_open` blocks `on_update` tick and `can_input`, `hud:halt()`). Form `resume` (title "Paused": Continue, New run
  with inline confirm) when `App.run_in_progress()` (restored snapshot = `App.restored`, or fight index > 1, score > 0, HP
  lost); form `start` (title "Dragon Chess": difficulty cycler + Start) otherwise. New run = `App.reset()` then the
  start form again (paused). The difficulty cycler on a fresh run restarts the run and keeps the panel. Esc hides the
  window (panel closes with it); crash / stuck / game-over / victory overlays take priority (no panel; their click starts a
  run directly); `/dchess fight` closes the panel. Spec: `docs/specs/w0-p10-pacing-and-start-menu.md`.
- **Class picker (W1-G1 part B)** (start form only, `ui/start_menu.lua`): a row of the 9 class icons (`ns.Classes.ORDER`;
  `Assets.CLASS_ICONS` sheet + `CLASS_ICON_TCOORDS`, class colour `RAID_CLASS_COLORS`; a missing global falls back to a
  plain coloured button with the class initial, `Assets.class_color` / `class_coords`), the chosen one framed, its name
  below, then the kit preview (6 colours x skill / ultimate icon, gem icon above; hover tooltip = spell name,
  "Skill / Ultimate - Colour", description through `Kit.format_text`). Clicking a class plays `click`, calls
  `App.set_class(id)` (stores `DragonChessCharDB.class_id`; on a fresh run, fight 1 / score 0, the run restarts with the
  new kit and the panel stays, like the difficulty cycler) and refreshes. Layout (box 312 x ~254): title 26, icons 28 px
  (pitch 32, 284 wide), name 16, preview 14 + 32 + 4 + 32 px (pitch 47), then the difficulty and Start buttons (190 x 24).
  The resume form shows "Class: <name>" (class colour, "Classic" for the default kit) and no picker.
- **Class persistence:** the class of the next run = `DragonChessCharDB.class_id` if it names a class, else the character's
  class (`UnitClass("player")` token, guarded), else none = default kit ("Classic"). `fresh_run` builds
  `Kit.for_class(App.selected_class())`; the boundary snapshot carries `class_id` (no `RUN_VERSION` bump) and the restore
  path rebuilds the kit from it (missing / unknown -> default kit). A resumed run keeps its own class whatever the stored
  choice is.
- **Menus in one dialog style (W0-P12)** — spec `docs/specs/w0-p12-menus.md`; presentation only, no rule / record / option
  change. Supersedes the layout details of the three menu bullets above (flat buttons, the 312 px picker box, the options
  column, the text overlay for a lost / won run); their behaviour (Esc order, pause rules, snapshots, class storage) stands.
  - **Panel kit** (`ui/panel.lua`, art / names in `ui/assets.lua`): `dialog` (backdrop + `UI-DialogBox-Header` plate, title
    font string; plate texture not loading = title on the plain dialog), `scrim` (click-eating dim over the content area),
    `button` / `primary` (`UIPanelButtonTemplate`), `check` (`UICheckButtonTemplate` + our own label font string),
    `segment` (row of flat buttons, one selected, per-button disable + tooltip), `section` (gold label + divider), `icon`
    (square button, 1 px dark border, standard crop), `show_tip` / `hide_tip` (guarded GameTooltip). Native widgets go
    through a guard (`pcall(CreateFrame)` + method check: `SetText` / `Enable` / `Disable`, `SetChecked` / `GetChecked`);
    a missing template or method builds the flat widget instead, never an error. Callers use `Panel.set_text` (label also
    in `button.dc_text`), `set_enabled`, `on_click` (click sound; a disabled button ignores clicks), `check.set_checked`.
    No keyboard handling anywhere (mouse only); no debug dependency (release build).
  - **Start form** (`ui/start_menu.lua`, 440 x ~378): header "Dragon Chess"; section Class (9 icons 36 px, pitch 44, the
    chosen one with a class-coloured 2 px frame, the others dimmed; class name below in `GameFontNormalLarge`); section
    Spells (6 colour columns: gem 18 px in the active gem set, skill and ultimate icon 36 px, tags "4" / "5+" left of
    the rows; tooltips unchanged, texts from the kit); section Difficulty (5 segments, locked ones greyed with the tooltip
    "Win difficulty N-1 to unlock", "Best: <score>" right of it, "-" without a record; a click calls `App.set_difficulty`);
    primary Start (160 x 28); dim hint line. `App.set_gem_set` refreshes an open start form (preview gems).
  - **Pause form** (300 x ~232): header "Paused", class name (class colour), "<Stage name> <stage>-<fight> · Difficulty <n>",
    "Score <n>", primary Continue, Options (`App.open_menu()`; the options panel sits above), New run (inline confirm,
    "Abandon this run? Click again").
  - **Result screen** (`ui/result.lua`, 340 x ~284, `App.result_menu`): replaces the text overlay for a lost / won run only
    (crash / soft pause / stuck keep it, and hide the result while up). `on_run_lost` / `on_run_won` write the records as
    before and fill `App.result = { won, score, best, new_best, unlocked, difficulty, class_id, enemy, stage, fight, dev,
    fights }`; `refresh_overlay` opens / closes the screen (a win waits for `VICTORY_BEAT`). Header "Defeated" (red) /
    "Victory" (gold), class, "Fell to <enemy> (<stage>-<fight>)" / "All <n> enemies defeated", difficulty, score in
    `GameFontNormalHuge`, "Best (Dn): <best>", gold "New best!", green "Difficulty <n+1> unlocked" (win). The primary
    New run = `App.new_run_from_result()` = `App.reset()` + the start form (class / difficulty pickers).
  - **Options** (`ui/menu.lua`, 280 x ~348, same anchor as before, 12 px lower for the plate): sections Sound (Sound, Quiet
    mode — dim while Sound is off, still clickable), Display (Screen shake, Window size Small / Normal / Large, Gems
    Jewels / WoW / Shapes), Game (Hide in combat), then Restart run (inline confirm) and Close. The difficulty entry is gone
    (the start form owns it; the title-strip D button stays). Option keys and `App.set_option` / `set_gem_set` unchanged.
  - Tests: `ui_menu_test` (full mouse flow incl. loss / win results, sizes, template-missing / bare-template fallbacks,
    disabled buttons), `ui_class_test`, `ui_smoke`, `ui_juice_test`, `release_test`; the stubs know `UIPanelButtonTemplate` /
    `UICheckButtonTemplate` (`W.missing_templates`, `W.bare_templates`). Sizes were designed blind: judge them in the client.
- **Idle hint** (`ui/hint.lua`, `BoardView:set_hint`): after `Hint.DELAY` = 6 sim-seconds with the board at
  rest, the player able to swap and no press / menu / pause, ONE `Match.find_possible_move` lookup per idle
  period; the pair then wiggles view-side (out 0.12 + swing 0.24 + back 0.12, rest 0.85 s = Godot HINT_*, as a
  0.12-cell nudge toward / away from each other). Cancelled and restarted by any swap attempt, press, pause,
  hide, menu, restart. Allocation-free after the lookup (ui_menu_test budget).
- **Shuffle feedback** (`sim` event `board_shuffled(ok)`): ok -> "No moves - shuffling" line (`hud:flash`) +
  staggered pop of every gem (`BoardView:pop`, view-only); not ok -> "Stuck" overlay, click = new run.
- Tests: `test/ui_menu_test.lua` (stubs: `Minimap`, `GameTooltip`, `AddonCompartmentFrame`, `GetCenter`).

## Combat (W0-G1): contract and known divergences from Godot

Spec: [../specs/w0-g1-combat-port.md](../specs/w0-g1-combat-port.md). Numbers are Godot's:
[combat.md](combat.md), [abilities.md](abilities.md), [scoring.md](scoring.md).

**Wiring.** `Combat.new{sim, seed | rng_combat, kit, player_max, player_hp}` hooks itself onto
the sim (create the `Sim` *without* `release_on_settle`): `gems_cleared` → damage,
`ability_activated` → FIFO queue, `sim:set_drain` → the queue drain, `board_settled` → chain
colour reset + leftover drain + `release_spawn_protection`, `match_resolved` /
`gems_cleared_by_effect` → score. `combat:start_fight(enemy_def)` starts a fight (and is the
transition after a kill); `combat:try_swap(a, b)` is the player's swap entry point (gate
`""` / `game_over` / `not_in_fight` / `stunned`, then `sim:try_swap`'s reasons).

**Abilities.** `core/abilities/<color>.lua` register plain tables in `ns.Abilities[id]`:
`{id, template, variants = {}, color, tier, icon, name, description, blurb, damage, score, <params>, execute(self, ctx)}`
(W0-G2c: canonical WoW ids `flamestrike`, `fire_shield`, `arcane_explosion`, `frost_nova`, `whirlwind`, `chain_lightning`,
`drain_life`, `polymorph`, `hammer_of_justice`, `mind_control`, `power_word_shield`, `rain_of_fire` — see
[abilities.md](abilities.md); `template` = the canonical id, `variants` is filled by W1 with class-tagged spell variants)
with `ctx = {sim, board, combat, info}`. `icon` is an asset key for `ui/assets.lua`. Combat finds
them only through `kit:get(color, tier)` (`Kit.default()` = the Godot kits; a kit holds copies, so
W1 can swap or tune kits without touching combat). Boon knobs (`reflect_multiplier`,
`clear_column`, `target_most_common`, `delay_per_8_gems`, `special_multiplier`, `thorns_damage`)
stay as plain fields at their neutral defaults. `Kit.banner_text(ability)` fills `{placeholders}`
like `PlayerAbility.get_blurb()`.

**Enemy data shape (W0-G1 stub; extended by "Enemies (W0-G2a)" below).** `core/enemy.lua`, data as plain tables (`Enemy.STUBS.hellhound`):
`{id, name, display, max_health, weak_to_color, windup, rotation = {{id, name, icon, damage_min,
damage_max, cooldown, is_special, execute_time}}}`. Attack cycle = `cooldown + windup +
execute_time` (`Enemy.cycle_time`; the first attack waits `rotation[1].cooldown`); `windup` =
the Godot sprite's attack animation, frames ÷ fps (Hellhound: 8 ÷ 12). The damage roll and random
partner colours use the combat stream (`Rng.SALT.combat`) like Godot.

**Time.** Statuses and enemy timers are `core/clock.lua` timers: scheduler service tasks on
gameplay time, exact wake-ups, frozen by the gameplay-pause gate (the kill pause) and by
`combat:settle_now()` (board work runs to rest with unbounded virtual time while the enemy and
status clocks are frozen — no attack, no expiry, so a logout can never kill the player).

**Snapshot (W0).** `combat:serialize()` only between fights (no enemy, after the kill, or after
the run ended): HP, score, shield stacks, timed statuses (remaining / max / value), combat RNG
state. `Combat.deserialize(data, {sim})`. The board is `sim:serialize()` (at rest only); the run
position belongs to `run.lua` (W0-G2b).

**HUD read API** (for `ui/`, W0-P1 / W0-P2; never changes state):

- `combat:hud_state(out)` fills and returns `out` (tables reused, no per-frame garbage):
  `player_health`, `player_max_health`, `score`, `game_over`, `fight_over`, `queue_length`,
  `player_stunned`, `statuses = {shield = stacks, fire_shield / lifesteal / curse / stun /
  heal_block = {remaining, max}}` (`curse.multiplier`), `has_enemy`, `enemy_name`,
  `enemy_display`, `enemy_health`, `enemy_max_health`, `enemy_weak_to`, `enemy_next_attack`
  (timer, s; -1 none), `enemy_next_hit` (incl. wind-up), `enemy_winding_up`,
  `enemy_stun_remaining` / `_max` / `_kind` (`stun` / `freeze` / `""`), `enemy_slow_remaining` /
  `_max`, `intents` (next 3 rotation entries: `name`, `is_special`, `icon`, damage range).
- Direct reads: `combat:status_remaining(id)`, `combat:status_max(id)`, `combat.enemy:…`
  getters, `Combat.COLOR_NAMES`.
- Events (`combat:on(name, fn)`, on the sim's bus): `fight_started(enemy)`,
  `enemy_health_changed(hp, max)`, `enemy_damaged(amount, boosted)`,
  `damage_dealt(amount, gem_type, source)`, `enemy_windup(ability, seconds)`,
  `enemy_ability_executed(ability)` (the hit lands now), `enemy_status_changed(kind, active,
  remaining, max)`, `enemy_immune(kind)`, `enemy_defeated(enemy)`,
  `player_health_changed(hp, max)`, `player_damaged(amount, source)`, `player_healed(amount)`,
  `attack_blocked`, `attack_reflected(amount)`, `heal_blocked`, `status_changed(id, active,
  remaining, max)`, `ability_triggered(info)` (banner: `toast`, `blurb` filled, `tier`, `score`,
  `id`, `icon`, `col`, `row`, `is_bomb`, `gem_type`), `score_awarded(amount)`,
  `score_changed(total)`, `run_lost`.

Divergences (deliberate or by construction):

- **Glue moved into combat:** `game.gd`'s score tally (match table, 15 per effect-cleared gem,
  ability scores) and fight transition (`start_fight` clears the gravity slow, resets curse /
  heal block / chain colour, then lifts the kill pause). Player HP lives in combat (Godot:
  RunManager); difficulty scaling, boss heal and `advance()` are W0-G2.
- **Events:** one `status_changed` replaces `damage_debuff_changed` / `player_stun_changed` /
  `heal_block_changed` (and Godot's HUD polling); added `enemy_windup`, `enemy_status_changed`,
  `score_changed`; `fight_started` = `enemy_spawned`.
- **Exact times:** statuses, stuns and the attack timer end at their exact gameplay time, not on
  the next frame. Enemy timers also freeze in the gameplay pause (Godot's `Timer` doesn't, but
  the battle only pauses while the enemy is dead — no difference in play).
- **Enemy timer details (unobservable):** Godot's repeating `AttackTimer` keeps firing (and is
  ignored) while the enemy is stunned and is restarted after a hit that lands during a stun; the
  stub just doesn't re-arm it. A hit whose enemy died during the wind-up is dropped (Godot still
  emits `ability_executed`, then `take_damage` returns `none`). Kept on purpose: a stun during
  the wind-up doesn't stop that hit; `delay_attack` during the wind-up is lost.
- **Bomb weakness:** a bomb deals 50 × the weakness of *its own colour* (Godot behaviour;
  combat.md's "Bombs: 50" is the unweakened value).
- **Lifesteal** also heals from an overkill clear after the kill (Godot behaviour).
- **Not ported:** Row Clear's `clear_column` (Crossfire boon needs `clear_cross`, cut), the debug
  attack-timer pause (F10), sounds. Divine Aegis / Mirror Shield / curse / heal block / player
  stun: the combat side is ported here, the enemy side is "Enemies (W0-G2a)" below.
- **Golden logs:** tests use the RNG tape (`H.tape`) for the combat stream; no Godot-exported
  combat logs yet (the statistical comparison is W0-T2).

## Enemies (W0-G2a): roster, ability kinds, divergences

Spec: `docs/specs/w0-g2-enemies-ladder.md` (G2a). The Godot `.tres` are frozen; `data/enemies.lua`
is the source of truth from here on (generated once by `tools/convert_enemies.py`).

**Data** (`ns.EnemyData = { list = ladder order, by_id, abilities }`, `Enemy.STUBS` aliases `by_id`).
Enemy: `{id, name, display (asset key = id), display_id = 1000 (fallback; the model FileDataID is `Assets.ENEMY[display].model_id`), max_health,
weak_to_color, is_boss, windup = 8/12, rotation, phases = {{hp_fraction, phase_name, rotation}}}`.
Ability: `{id, name, icon (= id), kind, is_special (effective), damage_min, damage_max, cooldown}` plus
kind params. Shared tables (Nefarian reuses Wing Buffet in a phase); **never mutate** (G2b
copies per fight). Ladder (W0-G2c WoW Classic roster, old Godot names in [enemies.md](enemies.md)): `hellhound`, `gordok_ogre`,
`basilisk_matriarch`, `forest_troll`, `harpy`, `hakkar`, `qiraji_scarab`, `anubisath_sentinel`, `ouro`, `nefarian`
(`enemy.model_id` lives in `Assets.ENEMY`, `display_id` 1000 is the fallback). Legacy enemies and `grid_rip` are not ported.

| kind | Godot script | params | execute |
|---|---|---|---|
| `plain`, `nuke` | `EnemyAbility`, `ChargeNukeAbility` | | the generic pre-execute roll only |
| `flurry` | `MultiHitAbility` | `hit_count_min/max`, `hit_interval` | count, then one roll per hit, on the enemy's `exec_timer` |
| `stagger` | `StunAbility` | `stun_duration` | roll in execute; stun only if the hit reached HP; none in god mode |
| `heal_block` | `HealBlockAbility` | `duration` | pre-roll hit, then the window (even if blocked; not in god mode) |
| `junk` | `SpawnJunkAbility` | `junk_count` | `sim:set_gems_junk` on a board coroutine (0.62 s telegraph) |
| `curse` | `DamageDebuffAbility` | `damage_multiplier`, `duration` | `combat:apply_damage_debuff` |
| `heal` | `HealSelfAbility` | `heal_percent` | `enemy:heal(round(max * pct))` (not blocked by the player's heal block) |
| `aegis` | `SpellImmunityAbility` | `duration` | `enemy:apply_spell_immunity` |
| `mirror` | `MirrorShieldAbility` | `duration`, `reflect_fraction`, `break_damage`, `break_stun` | `enemy:apply_mirror_shield` (resets the crack counter) |
| `sand` | `BoardSlowAbility` | `factor`, `duration` | `sim:set_gravity_slow` |

**Hit cycle.** Timer fires -> `enemy_windup` -> hit lands (`enemy_ability_executed`; the pre-execute
`range_i(damage_min, damage_max)` -> `combat:take_damage` for kinds with `pre`; `hi <= lo` draws
nothing, so 0-damage abilities consume no RNG; flurry / stagger roll inside execute) -> execute ->
`_execute_done` restarts the timer with the ability's cooldown. Godot's repeating-timer re-arm is kept
(restart with the previous cooldown at timeout); a timeout while a hit or execute is in flight is
skipped (guard) and `enemy_data_test` asserts `max(windup + execute max) < min(cooldown)` so the
guard never fires with shipped data. `Enemy.cycle_time` / `execute_time_expected` are expected values
for the HUD only.

**Freezable execute.** A flurry's gaps are `Clock` timers (never free `sim:wait` tasks), so a
`settle_now` (clocks frozen) deals 0 hits; the remaining hits follow when the clock thaws. A junk
spawn is *board work* (like the player's convert effects): `settle_now` finishes it. Abort rules: a
flurry / stagger / heal block stops when the fight or the run is over (Godot `battle.game_over /
fight_over`); a stun does not cancel a running flurry.

**Phases** (`_check_phase_thresholds`): only in `Enemy:take_damage` while HP > 0 (so also after
Fire Shield reflect / thorns), `hp / max <= hp_fraction` in a loop (one hit may cross two), monotonic,
empty rotations skipped (consumed), label = `phase_name` or `"Phase N"`, `rotation` swapped **by
reference**, index reset, timer restarted with the new first cooldown only when the enemy is active
(not stunned). Invincible enemies never phase.

**Statuses.** Aegis: `immune` flag + `immune_timer` (max of remaining / new duration); `combat`
zeroes `ability` / `bomb` damage (emits `enemy_immune("damage")`), stun / freeze / slow bounce
(`enemy_immune(kind)`), match damage / reflect / thorns / `delay_attack` still work. Mirror: reflects
`reflect_fraction` of ability / bomb packets as true damage, match damage cracks it, `break_damage`
shatters it and stuns the enemy `break_stun` s (bounces while immune).

**Events / HUD.** `enemy_phase_changed(label)`, `enemy_mirror_changed(active, broken)` (broken =
shattered, else expired), `stagger_resolved(landed)`, existing `enemy_immune`. `hud_state` adds
`enemy_phase_name`, `enemy_aegis_remaining/max`, `enemy_mirror_remaining/max/crack_ratio`; `intents`
are the ability tables (`.kind` for the glyph).

**Junk dead end (Godot #49) fixed.** `Match.would_swap_match` rejects a swap whose gem is junk or not
settled (spawn protection is not checked: released on `board_settled`). A board whose only "moves"
were junk swaps now reshuffles (capped; `board_shuffled(false)` + board unchanged when impossible).
Seed parity with Godot ends where junk is on the board; `golden_boards` diverges on 2 of 8 boards
(test uses the legacy search to show the old result and asserts the new move is valid).

**Dev.** `/dchess fight <id>` starts any enemy (kept for following fights until `/dchess reset`).
Tests: `enemy_data_test` (golden table from Godot, shape, overlap invariant), `enemy_test`,
`enemy_bot_test` (every enemy x 5 seeds, god mode, 1.5 s pace, 600 s cap, no stuck state, data
unchanged).

## Run (W0-G2b): ladder, difficulty, records, enemy-status UI

Spec: `docs/specs/w0-g2-enemies-ladder.md` (G2b). Code: `core/run.lua` (pure), wiring in `ui/main.lua`,
visuals in `ui/fight_view.lua` / `ui/assets.lua` / `ui/window.lua`.

**Run** (`ns.Run`). `Run.new{combat, difficulty, index}` rides on a Combat (HP, score, statuses carry over
there). Ladder = `data/enemies.lua` list order: stage 1-3 = two normals + a boss, stage 4 = the World
Dragon (`Run.STAGE_SIZES = {3,3,3,1}`). `run:begin_fight()` emits `run_fight_starting(run, def)` BEFORE
`combat:start_fight(scaled_def)` (the UI writes its boundary snapshot + stage label there); `run:update()`
(once per frame after `sim:tick`) starts the next fight when `sim.now >= run.next_at` (kill + 1.75 s,
`Run.FIGHT_TRANSITION`, moved out of `ui/main.lua`; after a boss that healed + `Run.HEAL_MOMENT` 5.0 s, W0-P11). On `enemy_defeated` the run advances at once:
a boss before the last fight heals +25 % of max HP (`combat:heal_player`, `player_healed` pop; capped,
Heal Block ignored like Godot; applied before the next fight-start snapshot), `run_advanced(result, index, heal)`
(`next_fight` / `stage_complete`), or `run_won` after the last fight (no heal, gameplay stays paused). A
lost run is combat's `run_lost` (`run.over = "lost"`). The score is `combat.score` (carried, no bonuses).
`run:serialize()` = `{v = 1, difficulty, index}` (the fight about to start / running); `Run.deserialize`
validates. Dev: `run:begin_fight(def)` forces an enemy for the following fights too and sets `run.dev` (no
records, nothing saved).

**Difficulty** (`Run.scale_def(def, d)`): a COPY of the enemy per fight (also at D1): max HP x(1 + 0.15 (d-1)),
every ability's `damage_min/max` x(1 + 0.20 (d-1)) (per hit for flurries, stagger and heal-block hits too),
Mirror `break_damage` x the HP factor; each rounded separately (half away from zero), `max >= min`; durations,
`stun_duration`, `cooldown`, `heal_percent`, hit counts never scale. One copy per original ability (they are
shared across rotations and phases, so scaled once). `run_test` deep-compares `data/enemies.lua` after D1-D5
and two full runs.

**Records** (plain functions on `DragonChessDB`, account-wide): `db.records[d] = {best, wins, runs}`,
`db.unlocked` (highest unlocked difficulty, default 1), `db.difficulty` (the choice for the next run, clamped
to unlocked). `Run.record_result(db, d, score, won)` -> `new_best, unlocked_now`: best score on win AND loss,
the next difficulty unlocks on a win only; corrupt values are tolerated (an empty DB is a first run).
`DragonChessDB.run.v` = 3 (2 and older discarded silently).

**UI flow.** Stage label from the run ("STAGE 2-1", "DEV" for a forced enemy; the phase name is appended:
"STAGE 4-1  -  NIDHOGGR"), stage background from `run:stage()`. Run won -> overlay "VICTORY! / Score / Best (Dn):
.. - new best! / Difficulty n unlocked!"; lost -> "Defeated! / Score / Best / Click to try again"; the click starts a
new run on the selected difficulty. Difficulty chooser: `/dchess difficulty N` (no argument prints the status),
and a title-strip button ("D2") that cycles the unlocked levels. A change starts a new run at once only when
nothing is at stake (fight 1, score 0); otherwise it applies to the next run (button "D1>2", chat note,
`/dchess reset` starts it now). `/dchess bg [cam ...]` = `/dcbg [cam ...]`. The overlay box grows with its text.

**Enemy-status visuals** (`FightView`, all from `hud_state` + events, zero per-frame allocation):

| Thing | Visual |
|---|---|
| Divine Aegis | additive gold glow over the figure (pulsing), icon + whole seconds at the figure's feet, "Immune" pop when a spell / stun bounces (`enemy_immune`) |
| Mirror Shield | silver glow, icon + seconds, crack bar "Crack 45%" (`enemy_mirror_crack_ratio`), "Mirror!" pop; shatter = "SHATTERED!" text (`enemy_mirror_changed(false, true)`), expiry just disappears; Mirror true damage reads "-N mirror" |
| Stun / freeze | existing queue slot (icon + seconds, STUNNED / FROZEN); a stun bouncing off Aegis shows no slot |
| Phase | banner (PHASE + NAME, 0.15 / 1.6 / 0.5 s) on `enemy_phase_changed`, phase name in the stage line, queue rebinds to the new rotation |
| Sandstorm | sandy layer over the board (fades in the last second) + player status icon with seconds (`hud_state.sand_remaining/max`) |
| Junk | brown flash over the board on `junk_spawned` (the gems themselves stay desaturated + dark) |
| Intent glyphs | `Assets.intent_icon(ability)`: own `ICONS` key, else `KIND_ICON[kind]` -> `kind_*` (plain, flurry, stagger, heal_block, nuke, junk, curse, heal, aegis, mirror, sand) |

Aegis / Mirror visuals are hidden once the fight is over (CLEARED). `Assets.ENEMY` has all ten enemies (model display
1000 + a distinct stand-in portrait icon each; the creature roster is a later decision). Most new icon names are
(vanilla) = not probed live: see the marks in `ui/assets.lua` and fix paths there.

**Tests.** `run_test` (ladder order / labels, scaling incl. golden numbers and deep-compare, records, snapshot,
fight flow with heal rules and the 1.75 s beat, an enemy killed mid-junk-telegraph, two full god-mode bot runs
D1 / D5 through all ten fights). `ui_smoke` additions: stage label / backgrounds per stage, boss heal on the bar,
difficulty button / slash / locks / mid-run rule, victory overlay + records + restart persistence, v2 snapshots
discarded, every status visual, intent glyphs, asset coverage, `/dchess bg`, a 300-frame allocation check with
Aegis + Mirror + Sandstorm running (< 1 KB).

## WoW-specific design points

- **Pause/resume:** the sim only advances while the window is shown. `OnHide` stops the driver;
  `OnShow` continues. `PLAYER_LOGOUT` / reload: W0 saves the run **at fight boundaries** (board
  only if at rest); a mid-fight reload restarts the fight (coroutines can't be saved). Soft pause
  with overlay on queue pop / ready check / world entry.
- **Real-time timers:** all game time is sim time (event-driven, continuous), never `GetTime()`, so pause is
  automatic and tests are deterministic and frame-rate independent. The driver clamps `dt`.
- **Tests:** `lua5.1` is the primary runner (WoW is Lua 5.1; LuaJIT allows yields inside `pcall`),
  LuaJIT secondary. `lua` on the dev machine is 5.5 — don't use it.
- **Performance budget:** 64 gem frames created once and pooled; no table creation in the
  per-frame path where avoidable; textures/vertex colour for colour variants.
- **Art/sound (decision 2026-10-04):** native WoW assets, referenced from the installed game —
  never copied into the repo/package. Gems = vanilla gem icons `INV_Misc_Gem_*` (six colours), ability gem = gem +
  spell icon overlay, enemies/bosses = creature models or portraits, backgrounds/frames = in-game
  art/atlases, sounds = `SOUNDKIT`/FileIDs. **All references live in `ui/assets.lua`** (one place
  to fix when a patch moves a path); `core/` stays asset-free. Enemy/ability data therefore carries
  asset keys (e.g. `icon`, `display`), not file paths. Credits/Blizzard attribution in `CREDITS.md`.

## Between-fight transition (W0-P11)

Spec `docs/specs/w0-p11-fight-transition.md`; Godot reference `game.gd _run_fight_transition`. All times are sim
seconds from the kill and halt with pause / hide like the other juice.

- **Core (`core/run.lua`):** `run.next_at = kill + FIGHT_TRANSITION (1.75)`, plus `HEAL_MOMENT (5.0)` after a boss
  that actually healed (heal > 0; a boss killed at full HP gets the normal beat). The heal itself is still applied at
  the kill (snapshot unchanged). `run_advanced(result, index, heal)` carries the healed amount. Run won stays
  immediate in core.
- **View (`ui/fight_view.lua`, constants at the top, Godot names in comments):**
  - kill: death fx + creature death sound, enemy name / weakness / HP text / attack queue hidden (`_set_chrome`);
  - kill + 1.0 s (`DEATH_BEAT`): CLEARED + subtitle "Next challenger approaches" fades in (0.2 s), holds 0.5 s,
    fades out by 1.75 s; the "cleared" sound and `TRAUMA_CLEARED` play now (`_update_transition`). None after the last boss;
  - boss that healed, kill + 1.75 s for 5.0 s: sound `heal_moment`, holy effects (`Assets.FX.heal_moment` at the player
    bar for the whole moment, `heal_moment_enemy` 2 s on the enemy frame; both reuse the divineshield model, placeholders),
    "+N HP" float, and the player HP bar / text rise from the pre-heal value to the final one (view-only: `update`
    rewrites `st.player_health`; the `player_healed` pop of the kill moment is swallowed while `combat.fight_over`);
  - fight start: chrome back, ability banner "<ENEMY NAME>" / "STAGE s-f" (the stage line with place name; the shared
    banner timings, hold 1.1 s, fade 0.4 s) on top of `hitfx:enter`.
- **Victory (`ui/main.lua`):** `App.won` is set at the kill (input blocked, records, save), but the overlay and the HUD
  halt wait `VICTORY_BEAT` 1.0 s of sim time (`App.won_at`) so the last boss's death plays.
