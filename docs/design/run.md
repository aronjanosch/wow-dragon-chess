> **Addon scope (2026-10-04):** ladder, difficulty and persistence ideas port; the boon draft / Rest / run kits mutation do not (see [wow-addon.md](wow-addon.md)).

# Run — current state

Audited 2026-09-27 (after M0-G1); M1-G2 boon draft added 2026-09-28. Code: `autoload/run_manager.gd`, `autoload/telemetry.gd`, fight flow in
`scenes/battle_controller.gd` / `scenes/game.gd`, menu in `scenes/main.gd`.

## Structure

- Fixed ladder of **10 fights**: stages 1–3 (Greek, Norse, Egyptian) each have 2 normals + a boss,
  stage 4 is the World Dragon alone. Beating it wins the run.
- Between normals: non-modal "CLEARED" sting (~1.75 s), then the **boon draft** (M1-G2, 6 per run:
  3 boons or Rest, with the next enemy previewed — see [boons.md](boons.md)), then the next enemy
  drops in. Gameplay is paused during the draft; unfinished cascades and spells carry over into
  the next fight.
- After a boss: heal moment (holy FX, HP bar fills over 5 s).
- Run won / lost: modal overlay with final score, best score (B.15), the run seed (small, M1-T1), back to menu.

## Player

- 10000 max HP (M1-G1 ×10 economy), persists across fights. **Healing after bosses:** +25 % of max HP (capped).
- Draft **Rest** option: +10 % of max HP (capped) instead of a boon.
- Other healing only from Amber Lifesteal during fights.

## Difficulty

- Levels 1–5; winning a run unlocks the next.
- Per level above 1: enemy HP +15 %, enemy damage +20 % (linear, e.g. D3 = HP ×1.3, dmg ×1.4;
  D5 = HP ×1.6, dmg ×1.8), on top of the M1-G8 base (enemy HP ×2.5 baked into the `.tres`).
- WoW addon (W0-P10): on top of the difficulty factor every enemy ability's `damage_min` / `damage_max` is multiplied by
  `Run.ENEMY_DAMAGE_SCALE` 0.9 (−10 %, all difficulties; with `Run.ATTACK_PACE` 2.2 in `scaled_ability`). Mirror
  `break_damage` is not attack damage and follows only the HP factor.
- Scaling works on per-fight copies of the enemy and its abilities; the cached `.tres` are never
  modified (M0-G1). Any future run-scoped upgrade must follow the same copy pattern.

## Run-scoped ability kits (M1-G1)

- `start_run()` builds `RunManager.run_kits` (gem_type → AbilityKit copy). Skill, ult and
  `ability_pool` point at run-scoped PlayerAbility copies (one original → copy map), so the cached
  `kit.tres` / ability `.tres` are never modified. Each new run starts from fresh copies.
- `RunManager.get_run_ability(gem_type, tier)` is the single place run upgrades (M1-G2 boons)
  read and modify abilities. `battle_controller.get_kit()` / `get_ability()` read `run_kits`
  (fallback to `RunManager.BASE_KITS` only if no run has been started).
- Boons (M1-G2) modify only these copies (`AbilityParamEffect`) or `RunManager.run_flags`
  (`RunFlagEffect`); `run_boons` / `run_flags` reset in `start_run()`. Details: [boons.md](boons.md).

## Persistence (`user://save.cfg`)

- `[progress] highest_unlocked_difficulty`
- `[scores] best_scores` — best run score per difficulty, recorded on both win and loss (B.15)
- Settings (volume, fullscreen) live separately in `user://settings.cfg` (`autoload/settings.gd`).

## Pause & options (B.14)

Esc pauses the fight (tree pause) with resume, volume sliders, fullscreen, restart run and quit
to menu (both need a confirm click). The same panel opens as Options from the main menu.

## Seeds & determinism (M1-T1)

- Every run has a seed: `RunManager.start_run(difficulty, seed := -1)`; −1 rolls a random 32-bit
  seed, stored in `RunManager.run_seed`. The run-end overlay shows it small ("seed N") for bug
  reports. The agent harness passes one via `AgentBridge.enable({seed})` / `start_run(d, seed)`.
- Gameplay randomness comes from seeded streams, each seeded from `run_seed` + a fixed salt, so
  extra rolls in one system never shift another system's sequence:

  | Stream | Used for |
  |---|---|
  | `rng_refill` | initial board fill, initial-match clear, no-move reshuffle, refill spawns |
  | `rng_effects` | convert / bomb / junk target picks (Amber/Amethyst converts, bomb makers, enemy junk) |
  | `rng_combat` | partner colour for cascade-triggered converts, enemy damage rolls, flurry hit count + per-hit damage |
  | `rng_draft` | M1-G2 draft offers (`scenes/boons/draft_rules.gd`) |
  | `rng` | master stream, reserved for run-level rolls (map, events) |

- Board and ability/enemy resources never reference `RunManager`: `game.gd._enter_tree` hands
  `rng_refill` / `rng_effects` to the board before it fills the grid; `battle_controller.rng_combat`
  is what enemies and abilities read. Shuffles use `RunManager.shuffle(array, rng)` /
  `scenes/rng_util.gd` (Fisher–Yates), never `Array.shuffle()`.
- Visual / audio randomness (gem tilt, sparkles, chain-lightning jaggedness, screen shake, SFX pitch)
  and the Debug-menu gem pick stay on the global RNG on purpose. The list lives in `run_manager.gd`.
- **Scope:** identical seed + identical action timing (AgentBridge step mode or the bot at a
  fixed fps, e.g. `--fixed-fps 60`) → identical run. A human run is *not* reproducible from its
  seed: real-time timing changes the order of rolls (when refills happen relative to enemy
  attacks). Test: `test/agent_test.gd` runs `test/agent_seeded_fight.gd` twice per seed in a child
  process and compares event-log hashes.

## Run telemetry (M1-T1)

- `autoload/telemetry.gd` (`Telemetry`) writes one JSON-lines file per run to
  `user://runs/<run_seed>_<unix_time>.jsonl`; the newest 200 files are kept. Local only, never
  uploaded. Every line has `schema: 1`, `type` and `t` (wall-clock seconds since run start).
- Events: `run_start {seed, difficulty, version, agent}` · `fight_start {enemy, stage, fight,
  player_hp}` · `fight_end {result, duration, hp_lost, hp_lost_mirror (M1-G9: part of hp_lost from
  Mirror Shield reflect), damage_by_color, damage_by_source,
  abilities_cast_by_color_tier, ability_spawns_by_color_tier, matches_by_color_length, max_match,
  cascades_max}` · `death {enemy, ability, hp_before}` · `run_end {result, stage, fight, score,
  duration}` · `draft_offer {options, kinds}` / `draft_pick {id, skipped, decision_seconds}` (M1-G2:
  `options` = boon ids, `kinds` = `tweak` / `shape` / `trade_off` / `setup`; Rest = id `rest` with
  `skipped: true`; `decision_seconds` excludes pause-menu time).
  - `fight_end.result`: `won`, `lost`, `abandoned`, or `skipped` (debug cheat jumped ahead).
    `run_end.result`: `won`, `lost`, `abandoned` (pause-menu restart / quit, window close, or a new
    run started while one was open).
  - Keys of the per-fight maps are colour names (`amber` … `topaz`, `none` for colourless);
    `*_by_color_tier` / `matches_by_color_length` use `"<colour>:<tier|length>"` (tier `1` skill,
    `2` ult, `bomb`). From M0-G5 on a match is a whole region: `matches_by_color_length` buckets
    lengths ≥ 8 into one `8+` key, and `max_match` is the biggest region size. `fight_end.duration` is game seconds (pauses excluded); `run_end.duration`
    is wall-clock seconds. `version` is `application/config/version` from `project.godot`;
    `agent` is true when the AgentBridge harness was on.
- Fight data is aggregated in memory from existing board / battle signals (`game.gd` calls
  `Telemetry.attach_fight`). Disk writes happen only between fights (run start, fight end, run
  end, draft calls); `fight_start` is buffered and written with its `fight_end`.
- Off for headless and `-s` script runs (smoke check, logic tests, visual QA) so they never touch
  the player's `user://runs`. User args: `--telemetry-dir=<path>` enables it and writes there
  (tests, M1-T2 bot); `--no-telemetry` disables it.
- `tools/run_stats.gd` prints a markdown summary: `Godot --headless --path . -s tools/run_stats.gd
  [-- --dir=<path>]` (runs, win rate by difficulty, deaths by enemy, damage share by colour, pick
  rate per boon, win rate when picked). It skips bad lines and tolerates missing keys.
