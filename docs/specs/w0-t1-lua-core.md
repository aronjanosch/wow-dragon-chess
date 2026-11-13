# Spec: W0-T1 — Pure-Lua core (RNG, board, region matching, simulation)

Status: DONE — implemented and merged 2026-10-04 (headless item, no playtest).
Milestone: W0 Base game port. Track: T.
Pillars served: 1 (snappy: deterministic cheap simulation), 2 (pause is free: sim time, not wall
time), 3 (the board rules of the two-speed combat). Foundation for every later item.

## Player experience goal

Developer/agent goal: the whole board game — swaps, region matches, gravity, refill, cascades,
gem tiers — runs as plain Lua with no WoW API, so it is tested headless on this machine with
LuaJIT, and the WoW view (W0-P1) is a thin renderer over it. Player-facing: a board that behaves
exactly like the Godot one (same match rules, same feel of continuous real-time play).

## Current state (facts)

Verified in `scenes/board.gd` (read 2026-10-04):
- 8×8 grid (`GRID_COLS/ROWS`), 6 colours (index 0–5), real-time continuous play: per-gem state
  SETTLED / SWAPPING / FALLING / CLEARING; settled gems are always swappable (`request_swap`
  `board.gd:470`), also while other parts cascade.
- Region matching (`find_all_matches`, `board.gd:278`): maximal H/V runs ≥ 3 of eligible gems
  (settled, not junk, not spawn-protected), union-find merge of same-colour runs that share or
  touch a cell; region size → spawn tier (`spawn_tier_for_length`: 4 → skill, ≥ 5 → ult;
  `board.gd:239`); size multiplier 6 → ×1.2, ≥ 7 → ×1.5 (`board.gd:257`). Convert-marked gems cap
  a region at a skill (`spawn_tier_for_region`).
- A swap is valid only if the resulting grid has a match containing one of the two swapped gems
  (`_match_involves_gems`, `board.gd:505`); otherwise swap back + `swap_rejected`.
- Spawn position: the swapped-in gem if part of the region, else the gem nearest the region centre
  (`_match_center_gem`). Fresh ability gems are spawn-protected until the board settles; a player
  swap lifts it.
- Resolve is a coroutine chain of awaits (fuse → ability drain → gravity/refill) with
  `_dirty` / `_resolving` flags (`board.gd:537–707`); cascades wait for the ability queue to drain.
- Timings in `scenes/animation_timings.gd`: SWAP 0.14, CLEAR 0.20, FUSE 0.24, FALL_PER_CELL 0.09,
  FALL_CAP 0.38, LAND 0.12, ABILITY_POP 0.16.
- Seeded streams: `rng_refill` (initial fill, refill, shuffle), `rng_effects` (convert/bomb/junk
  picks); `scenes/rng_util.gd` Fisher–Yates `shuffle`, `range_i`.
- No-moves-left → reshuffle plain gems (`find_possible_move`, `shuffle_board`).
- Ability primitives live on the board but are combat-ignorant: `clear_area`, `clear_row`,
  `clear_wave`, `clear_color(_chained)`, `convert_color`, `convert_random_gems`,
  `convert_random_to_bombs`, `set_gems_junk`, `set_gravity_slow` (`board.gd:1334–1640`).
- Not verified: exact refill rule details at `_animate_gravity_and_spawn` (`board.gd:911`) and the
  junk/bomb adjacency expansion (`_expand_with_adjacent_junk`, `_adjacent_triggered_bombs`) —
  the implementing agent must read them before porting.

## Changes

New directory `wow/` (layout in [../design/wow-addon.md](../design/wow-addon.md)):

1. **`core/rng.lua`** — arithmetic-only PRNG (no `bit` library, works in plain Lua 5.1/LuaJIT and
   WoW): `new(seed)`, `next()`, `range_i(a, b)`, `shuffle(array)` (Fisher–Yates, deterministic),
   `fork(seed, salt)` for the named streams `refill` / `effects` / `combat` (each stream seeded
   from `seed + salt`, like `RunManager`). Never use `math.random` in `core/`.
2. **`core/board.lua`** — pure grid state: `cells[col][row]` gem tables `{id, type, tier, bomb,
   junk, protected, marked, state, x, y}` (`x,y` = float cell position, owned by the core), no
   rendering. Gem types 0–5, tier 0/1/2, states as in Godot.
3. **`core/match.lua`** — `find_matches(board)` returning regions `{length, gems}` using the exact
   Godot algorithm (runs, union-find, deterministic order), `would_swap_match`, `find_possible_move`,
   `tier_for_length`, `tier_for_region`, `damage_multiplier_for_length`.
4. **`core/sim.lua`** — event-driven simulation on **continuous sim time**. `Sim.new{seed, ...}`,
   `sim:tick(dt)` (`dt` clamped to ≤ 0.05 s) advances the clock by jumping to each due wake-up in
   order, so results do not depend on the frame rate (and 144 Hz screens don't judder: the view
   reads positions computed from the exact sim time). Scheduler contract (rev 2, from the critic):
   - `spawn(fn)` runs `fn` **immediately** to its first yield (Godot signal handlers run
     synchronously up to their first await, e.g. a status-only ability drain finishes inside
     `need_ability_drain.emit()`).
   - `wait(seconds)`, `wait_until(pred)` and `wait_event(name)` (for `abilities_drained`,
     `gameplay_unpaused`, …). Many coroutines may be alive at once (one per swap, per convert morph,
     the gravity pass inside clears, the settle-path drain).
   - Wake order is deterministic: earliest wake time first, ties by spawn order.
   - A **gameplay-pause gate** (`sim:pause_gameplay()` / `resume_gameplay()`, port of
     `pause_gameplay` / `wait_if_paused`, `board.gd:111–126`, used in >8 places): gated coroutines
     don't wake while paused; this is separate from hide-pause (which just stops ticking). It is what
     lets leftover cascades hit the next enemy after a kill.
   - Never yield inside `pcall` or a `table.sort` comparator (PUC Lua 5.1 and WoW can't; LuaJIT
     can — verified: LuaJIT would hide such bugs). Coroutine errors are re-raised with a traceback
     (`error(debug.traceback(co, err))`; in WoW the UI layer forwards to `geterrorhandler()`).
   The resolve pass is a The resolve pass is a
   direct port of the Godot await chain onto this scheduler (match → spawn/fuse → ability drain
   hook → gravity/refill → next pass). Motion (swap, fall, clear/fade progress, spawn pop) is
   interpolated in core (cubic ease-out for swap; fall **accelerates** quadratically, fall time =
   `clamp(0.09 × distance, 0.09, 0.38) / slow_factor`, and a gem only counts as settled after the
   0.12 s landing tween — `board.gd:925–950`; refill: columns collapse bottom-up, new gems spawn
   above the board with **no match avoidance**, colours from the `refill` stream, columns 0→7,
   top row first) and
   written to `gem.x/y` and a `gem.fx` progress field so the view only reads.
5. **Events:** `sim:on(name, fn)` / `sim:emit`. Names mirror Godot's signals: `match_resolved
   (length, gems, depth)`, `gems_cleared(type_counts)`, `swap_rejected`, `board_settled`,
   `ability_activated(info)`, `ability_gem_spawned`, `gems_cleared_by_effect`, `junk_spawned`,
   `gravity_slow_changed`, plus `gem_created`/`gem_removed` for the view's pool. The core never
   calls UI; combat (W0-G1) subscribes. The ability drain is a hook (`sim.set_drain(fn)`) returning
   a wait condition so combat can hold cascades like in Godot.
6. **Ability primitives** (`clear_area`, `clear_row`, `clear_wave`, `clear_color(_chained)`,
   `convert_color`, `convert_random_gems`, `convert_random_to_bombs`, `set_gems_junk`,
   `set_gravity_slow`) ported into `core/board_effects.lua` with the same return values, using the
   `effects` stream. (Only the **logic**; telegraph/morph animation is expressed as `wait()` times
   plus a `flash` event for the view.)
7. **Snapshot (board level):** `sim:settle_now()` (runs the scheduler with a large virtual dt, no animation wait,
   until idle; **combat/enemy/status clocks are frozen while it runs**, see W0-G1) and
   `board:serialize()` / `Board.deserialize()` incl. RNG stream states (only valid at rest;
   coroutines are not serialisable). `settle_now` must reach the *same final board* as normal
   ticking would (asserted by test). **W0 scope decision (critic):** the run is saved at **fight
   boundaries** (plus the board when it is at rest); a `/reload` or logout mid-fight restarts the
   current fight from its start. Hide/show needs no snapshot at all (state stays in memory).
8. **Tests** under `test/` (plain `luajit test/<name>.lua`, print PASS/FAIL, exit code ≠ 0 on
   failure) + `tools/checks.sh` (runs all; the single list of tests; calls `lua5.1` and `luajit` explicitly, **`lua5.1` is the primary runner** — `lua` on this machine is 5.5). See below.

## Port facts the implementer must honour (verified by the critic)

- Tie-break orders matter for outcomes: `_match_center_gem` picks the first gem of the region in
  order *horizontal runs (row by row), then vertical runs*; the random partner colour is drawn
  from `count_colors()` keys in **board scan order (column by column)**. Iterate arrays only,
  never `pairs`.
- A matched ability gem that is also the spawn cell fires, then becomes the new ability gem
  (`board.gd:614–648, 848–864`) — needs a golden test.
- `set_gravity_slow` is at `board.gd:960` (outside the 1334–1640 primitive range cited above).
- Godot's `_collapse_column_animated` moves any non-null gem (also SWAPPING/CLEARING) and gravity
  from `_clear_cells` can overlap another pass (`board.gd:997`, `1799`). **Decision: port as-is
  first, record divergences in the report; fix only if a test shows stuck/duplicated gems.**
- Godot's hitstop (`Juice.hitstop`, `Engine.time_scale` dips of 35–65 ms) slightly slows enemy
  and status timers. **Accepted divergence** (no hitstop in the addon core).
- Godot's RNG is PCG32; ours is not. **Golden comparison therefore uses an RNG tape**: a Godot
  exporter records each stream's draws for a scripted scenario, the Lua test replays that tape
  through a stream stub and diffs the event log (replaces "golden boards exported from Godot").
- Addon file loading: core files start with `local _, ns = ...`; the headless loader passes `ns`
  like WoW does. (WoW also ships a `bit` library; "no bit" stays as a conservative choice.)

## Alternatives considered

- **Explicit state machine instead of coroutines** (no scheduler): serialisable at any moment, but
  the Godot resolve chain is await-shaped; rewriting it as states loses 1:1 traceability and
  risks parity bugs. Lost on parity cost; snapshot-at-rest solves the serialisation need.
- **Core outputs only logical events, view animates from them:** keeps core tiny, but then
  the view must reimplement fall/swap timing and pause logic; sim time and picture can drift.
  Lost: core-owned `x,y` is a few lines and keeps pause/reload exact.
- **Use `math.random` / `GetTime()`**: breaks determinism, pause and headless tests. No.
- **Do nothing / start with the UI**: a UI prototype first would hide parity bugs in match
  logic; the cheap tests here pay off for every later item.

## Why this could be wrong

- Coroutines + fixed step might hide GC cost (closures per wait). Measure garbage per second in a
  headless soak (`collectgarbage("count")`); if bad, pre-allocate waits or switch hot paths to
  plain state.
- Region/cascade parity: subtle ordering differences vs. Godot (dictionary iteration order
  there is insertion order; Lua `pairs` is unordered). The port must never depend on `pairs`
  order — iterate arrays only. Cross-check against Godot with golden boards (below).
- `settle_now()` may diverge from live play if animation waits changed logic order. Test it.
- 6 colours may not suit the class mapping (W1); the core takes the colour count as a parameter.

## Non-goals

No combat, no abilities' *effects on enemies* (just board primitives), no WoW frames, no
SavedVariables writing, no art. No boon-related board flags (`bombs_trigger_adjacent` is kept as a
board property because Godot has it, default false).

## Tests / acceptance

- `rng_test`: same seed → same sequence; different salts independent; distribution sanity;
  `shuffle` is a permutation and deterministic.
- `match_test`: golden boards (hand-written 8×8 colour grids, plus 5 exported from Godot with
  `GDScript` helper `tools/export_golden_boards.gd`) — region sizes, spawn tiers, L/T/+, parallel
  rows merge to one region, protected gems split regions, junk not matchable, swap validity.
- `sim_test`: scripted swaps; a valid swap reaches settled; an invalid one emits `swap_rejected`
  and returns; cascades terminate; fixed seed → identical final board and identical event
  sequence on two runs; `settle_now` equals ticked result; no-moves board reshuffles.
- `effects_test`: each primitive on a known board (area/row/wave/colour clears, convert,
  bombs, junk, gravity slow factor).
- `pause_test`: not ticking changes nothing (state hash equal); resuming continues identically.
- `scheduler_test`: spawn runs to first yield immediately; wake order (time, then spawn order); `wait_event`; gameplay-pause gate holds coroutines; yield inside `pcall` is flagged by a lint check; error forwarding.
- Soak: 10 000 random valid swaps on a seed, no error, board always full and all gems settled at
  the end, garbage count recorded in the report.
- Agent-verifiable: `tools/checks.sh` all PASS. User playtest: none yet (headless item).

## Open decisions

1. Fixed step vs event-driven time? **Event-driven continuous time (rev 2)**: frame-rate independent, no judder, deterministic under any `dt`.
2. Where do animation durations live? **`core/timings.lua`**, copy of `animation_timings.gd`
   values that matter to logic order; view-only timings stay in `ui/`.
3. Golden boards: **hand-written boards plus RNG-tape scenarios exported from Godot** (tape exporter is a small `tools/export_tape.gd`; may land after the first playable, not a blocker for P1).
4. Test runner? **`lua5.1` primary** (WoW is Lua 5.1; LuaJIT allows yields in `pcall` and would hide bugs), LuaJIT secondary for speed.

## Critic findings addressed (2026-10-04)

Scheduler contract (spawn-immediate, signal/predicate waits, deterministic wake order,
gameplay-pause gate) added; time model changed from fixed 1/120 s steps to event-driven
continuous time (kills 144 Hz judder and makes results `dt`-independent); `lua5.1` is the primary
test runner because LuaJIT permits yields inside `pcall` that PUC Lua 5.1/WoW does not (verified
by the critic); the Godot "golden" comparison uses an RNG tape because Godot's PCG32 can't be
reproduced (statistical probe comparison moved to its own item W0-T2); fall/refill facts, tie-break
orders, the spawn-on-ability-gem edge case, the gravity race (port as-is, document), hitstop
(accepted divergence) and a corrected line reference were written into "Port facts"; snapshot
scope reduced to fight boundaries (+ board at rest) for W0.
