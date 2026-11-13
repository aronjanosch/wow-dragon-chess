# Spec: W0-P7 — Board ability effects, chain escalation, gem motion, soft glow material

Status: implemented — awaiting in-game playtest (approved by user "implement A, B and D completely", 2026-10-05).
Milestone: W0 addon. Track: P (presentation). Issue #53 (feel).
Pillars served: readable real-time feedback; matches and abilities must feel satisfying.

## Player experience goal

Every ability visibly happens ON the board (cells light up, a beam sweeps a row, a wedge unfolds, lightning jumps
from gem to gem, conversions glow before they morph), each ability colour has its own look, and chains escalate
(a x4 cascade is clearly bigger than a x1 match). Gems land with weight, ability gems look charged, a rejected swap
says "no". Particles are soft glows instead of hard squares.

## Current state (facts, verified in the code)

- The UI listens only to `gem_created`, `gem_removed`, `board_shuffled`, run events and the 20 combat handlers of
  `ui/fight_view.lua` (`HANDLER_ORDER`). Core events with NO listener: `flash` (kinds `area`, `color`, `chain`,
  `convert_to`, `telegraph`, `telegraph_from`, `telegraph_to`, `row_sweep`, `wave`; payload `kind, cells, dur`, `cells` =
  flat `{col, row, col, row, ...}`, `core/board_effects.lua:201/252/288/380`), `chain_hop(c0, r0, c1, r1)`
  (`:356`), `ability_activated`, `gems_cleared_by_effect`, `score_awarded`, `status_changed`.
- `Fx:setup` (`ui/fx.lua:87`) ignores `col`/`row`: `at = "cell" | "row" | "cone"` models appear at the board centre.
- `fx_curve` (`ui/board_view.lua:362`): `fall` has no curve, `land` = uniform 8 % shrink, no swap effect.
- `match_resolved(length, gems, depth, ...)`: `depth` only picks a sound slot (`fight_view.lua:1182`).
- Juice particles are plain colour squares (`ui/juice.lua:118`, `SetColorTexture`). Rings use `A.SLOT_RING` or a disc.
- Ability gems: static badge (rim + pip) and spell icon (`board_view.lua:327`), static white selection disc.
- Everything is sim-time driven and pooled (no frames / textures created while playing). Keep that.

## Changes

### D — soft glow material (first; A and B use it)
D1. Texture research result lives in `docs/design/wow-effect-textures.md` (written by the research step). `ui/assets.lua`
    gets `A.GLOW = { glow, flare, ring, beam, bolt, smoke, wedge }` specs (path or FileDataID, each optional). A
    helper `A.soft(tex, role)` applies the role texture (pcall-guarded) and returns true, else false = fall back to
    the existing colour square / round mask. No effect may depend on a texture being present.
D2. `Juice` particles, rings, streak heads use the soft glow texture when available (fallback = today's square /
    disc). Sparkles use the flare. The debug panel Effects tab shows which roles loaded ("glow ok / missing").

### A — ability effects on the board (new file `ui/board_fx.lua`, pooled, created once)
A1. `BoardFx` subscribes (in `FightView:bind` / `App` bind) to the sim events `flash` and `chain_hop`. It copies the
    cell list into pooled slots (the core may reuse the table; keep no reference) and plays by kind:
    - `area`, `color`, `convert_to`, `chain`: each cell gets a soft glow pulse (colour by kind; `color`/`area` use the
      casting gem colour, last `ability_triggered` gem type).
    - `telegraph`, `telegraph_from`, `telegraph_to`: pulsing glow on the cells for the full duration (`dur`), `from`
      cool/desaturated, `to` bright gem colour; ends with a short flash.
    - `row_sweep`: a beam (stretched beam texture or a row of glow quads) runs outward along the row from the origin
      cell in `ROW_SWEEP` sim seconds, bright core + soft trail; each swept cell flashes as the beam passes.
    - `wave`: a wedge/fan expands from the origin cell to the right in `WAVE_CONE`; per-column slice flashes
      (`CLEAR_STAGGER_STEP * 2` apart) in the ability colour; ember particles rise from the wedge.
    - `chain_hop`: a jagged lightning bolt (3-5 short segments with jitter, bolt/beam texture or glow-dot chain)
      between the two cells for `CHAIN_HOP + CHAIN_HOP_HOLD`, fading over `CHAIN_FADE`, plus a spark burst at the
      target cell.
    Pools: CELLS 64 glow slots, BEAMS 4, BOLTS 8 (segments inside), WEDGE 1. A full pool recycles the oldest.
A2. Per-colour ability signature on `ability_triggered` (extra particles from `Juice`, at the ability cell and on the
    enemy for enemy-targeted abilities; use `A.COLOR.GEM_FX`): Ruby/fire = rising embers + orange wash, Sapphire/frost =
    falling ice shards + blue ring, Topaz/lightning = fast sparks, Amethyst/shadow = slow violet wisps (negative
    drift), Emerald/nature = green leaves/motes drifting, Amber/holy = gold motes + ring. A table in `ui/juice.lua`
    (`Juice.SIGNATURE[gem_type]`), one function `Juice:signature(gem_type, x, y, weight)`.
A3. `Fx:setup` honours `col`/`row`: `at = "cell"` centred on that cell, `at = "row"` centred on that row (full board
    width kept), `at = "cone"` anchored at the cell and pointing right. Keep the unified frame sizes; only the
    centre offset changes. Unknown/nil col/row = old behaviour.
A4. Board light: on `ability_triggered`, a coloured additive wash over the whole board (colour of the gem, peak 0.18
    skill / 0.3 ult, 0.25 s in-out) and for an ult a 0.3 s darkening of the board (alpha 0.35) under the effects.
    Overlay only, never blocks input.

### B — chain escalation and gem motion
B1. Combo meter: `depth >= 2` shows "x<depth>" (gold, growing font/scale with depth, punch on each new level) near the
    board top-right; fades 1.2 s after the board settles (`board_settled` or no match for 1.2 s sim). Pooled
    FontString, no allocation per frame.
B2. Escalation by `depth` (1..6+, `e = min(depth, 6) - 1`): shard count x(1 + 0.25e), ring size x(1 + 0.15e), an extra
    ring from depth 3, trauma + 0.04e (capped by the existing max), vignette flash in gold from depth 4 (peak 0.15 +
    0.05e), extra deep sound layer unchanged (existing `match_cascade` slot, no pitch up).
B3. Gem motion (`ui/board_view.lua` `fx_curve`, pure functions of `fx_t`): `fall` gets a tiny vertical stretch
    (1.0 -> 1.06 tall) via a separate scale-y path if feasible, else none; `land` = squash (x1.12 wide / 0.88 tall)
    snapping back with one small overshoot; landing dust: a small smoke/glow puff at the gem's feet from
    `Juice` when a column of gems settles (triggered from the view when a gem's fx becomes `land`; max 1 puff per
    column per 0.1 s, pool shared with particles). If non-uniform scale needs a second texture size path, implement
    it via `SetSize(w, h)` of the frame (already used for uniform scale).
B4. Swap: the two swapping gems get a short brightness flash (existing flash texture) at the swap start; a rejected
    swap (`swap_rejected`) shakes both gems sideways (+-0.1 cell, 2 cycles in `SWAP * 2`) as a view-only offset and
    plays a small red-white cross puff on them. The sim state is untouched.
B5. Ability gems "charged": skill gem = soft cyan halo (glow texture, ADD) pulsing 0.8 -> 1.0 at ~1.4 Hz with 2
    orbiting spark dots; ult gem = golden halo pulsing 0.85 -> 1.15 at ~1.0 Hz, a slow rotating flare behind it and 3
    orbiting dots; bomb = red flicker. Implemented per gem frame (extra pooled textures created once in
    `_create_gem_frame`, driven by sim `now` + gem id phase offset, setters only when quantised value changes).
B6. Selection glow breathes (alpha 0.35 -> 0.65, 1.6 Hz); the held (dragged) gem gets a soft shadow/halo.

## Alternatives considered

- Blizzard spell models (`Fx`) for all board effects: rejected, they are positioned per fixed frame and cannot follow
  the swept cells; kept for the ability's main model.
- `AnimationGroup` for pulses: rejected, runs on wall time; the project drives everything on sim time (pause-safe).
- Hit-stop: still impossible (sim is the clock).

## Why this could be wrong

- 64 glow slots + beams + per-gem halos add many textures; the live frame cost is unmeasured. Pools are capped and
  the debug footer shows frame cost; B5 halos can be reduced to ability gems only (already so) or disabled in an
  "Effects: Reduced" option if needed.
- Soft-texture FileDataIDs may not exist in the client; all effects must work with the fallback (squares / discs).
- Too much light on a board that sits next to a busy WoW UI may read as noise; every new layer has a constant at the
  top of its file and a debug button.

## Non-goals

Hit-stop, new sounds beyond existing slots, reduce-motion CVar, changes to core rules (core stays pure; if a payload
needs an additive field, add it additively and cover it in `sim_test`).

## Tests / acceptance

- `ui_juice_test` extended + new `ui_boardfx_test.lua` (registered in `tools/checks.sh` TESTS): flash kinds spawn
  the expected slot counts; pools never create new frames/textures while playing (compare counts before/after);
  recycle on full pool; copying of cell lists (mutating the source table after the event changes nothing);
  `Fx:setup` placement for cell/row/cone with col/row and nil fallback; combo meter shows/hides and scales with
  depth; escalation numbers monotonic in depth; `fx_curve` land/fall pure and bounded; rejected swap offset returns
  to 0; ability halo setters quantised (no per-frame setter spam when static); texture-missing fallback path
  (stubbed `A.GLOW` empty) still produces particles; allocation budget (no table growth per frame, as in the
  existing allocation test).
- `tools/checks.sh` fully green with lua5.1 AND luajit.
- Debug panel Effects tab: buttons for every new effect (Row sweep, Wave, Chain bolt, Telegraph, Area flash, Combo x2..x6,
  Land dust, Rejected shake, Skill halo / Ult halo preview already visible via debug spawn).
- User playtest in WoW: do ability effects read, are chains clearly escalating, is anything too loud/slow.

## Deviations

- B5 auras are a pool of 12 (`BoardView.AURA_SLOTS`) assigned to ability gems (halo + flare in a frame behind the gems, orbit dots in a
  frame in front) instead of 5 extra textures inside each of the 64 gem frames (320 textures). Same look, fewer textures; more than 12
  ability gems on the board at once leave the surplus without an aura.
- The debug buttons are a new tab 8 "Board FX" (the Effects tab had no room for ~25 more buttons); `ui_debug_test` was updated from
  seven to eight tabs.
- `swap_rejected` got an additive payload `(a, b)` (the two gems) so the view can shake exactly them; covered in `sim_test`.
- Bolts are chains of glow dots (a texture cannot be rotated as geometry in WoW; `SetRotation` only turns the image). The `bolt` role
  texture is used as a stretched underlay for near-horizontal hops only.
- The wedge texture is optional: without it the `wave` is the staggered column slices + embers.
- `Fx:setup` for `at = "cone"`: the frame centre is shifted `Fx.CONE_SHIFT` (0.45) x effect size to the right of the gem cell; the
  model's own orientation is unchanged (tune with `/dcfx cam`).
- Land `fx_curve`: the old uniform 8 % shrink is now 3 % (the squash carries the effect); `fx_curve` returns two extra values (`sx`, `sy`) for fall / land.
- Particles carry a texture role; two existing `ui_juice_test` checks read the vertex colour of soft particles / the soft head size
  (`vr/vg/vb`, `SOFT_HEAD`) instead of the colour texture. `ui_fx_test`'s "centred on the play area" check for cell / row / cone was
  replaced by the new col/row placement checks (nil col/row = centred is still tested).
- Gold vignette for deep chains only starts if no other flash is running (it never overrides a hit flash).
- `Juice.PARTS` 48 -> 72, `Juice.RINGS` 6 -> 8 (signatures, dust and wave embers share the pool).
