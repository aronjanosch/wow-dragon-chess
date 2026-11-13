# Spec: W0-P1 — Addon shell + board view (pause on hide, resume)

Status: implemented — awaiting in-game playtest (AGREED rev 2: critic review 2026-10-04, user approval 2026-10-04). Depends on W0-T1.
Milestone: W0 Base game port. Track: P.
Pillars served: 1 (snappy open/close and rendering), 2 (hide = pause, show = resume, survives
`/reload` and logout), 5 (readable board).

## Player experience goal

Type `/dchess` (or click the minimap/compartment entry): a window opens with the board and you
are playing within a second. Close it — the game freezes exactly where it was. Open it again,
even after `/reload` or relogging, and swap away. Dragging and clicking gems feels as direct as in
the Godot game.

## Current state (facts)

- Godot input: drag toward a neighbour (commits past ~28 % of a cell, auto-commit past ~52 %) or
  click-select + click neighbour; `can_player_swap()` + `try_swap(a, b)` are the single entry
  (`scenes/board_input.gd`, [../design/combat.md](../design/combat.md)). Idle hint after 6 s.
- Godot cell size 62 px, 8×8 (`board.gd` `CELL_SIZE`, `GRID_COLS/ROWS`).
- Gems are distinguished by colour **and** shape (colour-blind readability); ability gems show
  tier badges/auras (`scenes/gem.gd`).
- Core exists (W0-T1, merged): `core/*` (see [../design/wow-addon.md](../design/wow-addon.md) "Core" section for the API: `Sim`, events, `try_swap`, `settle_now`, `serialize`).
- WoW facts are **verified on a live client** (build 1.60.1/70205, interface 16001) and recorded in
  [../design/wow-forever-api.md](../design/wow-forever-api.md): Lua 5.1 semantics, events, frame
  types, mouse behaviour, gem icon look, perf. Remaining unverified: SavedVariables survive a
  **cold start** (reported broken in the beta; they survive `/reload`), exact soft-pause event
  behaviour in a real queue.
- A dev probe addon lives in `probe/DragonChessProbe` (symlinked into the beta's AddOns).

## Changes

1. **TOC + bootstrap:** `DragonChess.toc` (Title, Notes, Version, `Interface: 16001` (verified),
   `SavedVariables: DragonChessDB`, `SavedVariablesPerCharacter: DragonChessCharDB`, file list
   core → data → ui). `ui/main.lua` registers `ADDON_LOADED`, `PLAYER_LOGOUT`, and the slash
   commands `/dchess` and `/dragonchess`.
2. **Window:** one movable, clamped, scale-able frame (`Frame` with backdrop via
   `BackdropTemplate` or textures), close button, Esc closes it (`UISpecialFrames`) — closing =
   pause. Remembers position/scale in `DragonChessDB`.
3. **Driver:** a single `OnUpdate` on the window calls `sim:tick(elapsed)` only while shown
   (`elapsed` is clamped in core; a loading screen's first long frame is absorbed).
   `OnHide` stops everything (no hidden-frame updates). No timers via `C_Timer` for gameplay.
   Alt-Z hides UIParent, which fires `OnHide`/`OnShow` — pausing there is intended. Coroutine
   errors from the core are forwarded to `geterrorhandler()`.
   **Soft pause (critic #8, ~10 lines):** while the window is open, `LFG_PROPOSAL_SHOW`,
   `READY_CHECK`, `PLAYER_REGEN_DISABLED` (option, default **off**), the battleground confirm event
   and `PLAYER_ENTERING_WORLD` pause the sim and show a "Paused — click to resume" overlay; the
   window stays open. Pillar 2: never punish being pulled away. (Exact event names to verify on the
   live client.)
4. **Board view (`ui/board_view.lua`):** 64 pooled gem frames created once; each has one texture
   (shape per colour) tinted via `SetVertexColor`, plus a badge texture for tier 1/2, bomb, junk
   and a `protected` glow. Per frame the view sets position/alpha/scale from `gem.x/y/fx`; it
   creates no tables per frame. Gem pool grows only if the core reports `gem_created` beyond 64
   (spawn above the board).
5. **Input (`ui/input.lua`):** drag-to-swap (threshold as in Godot) and click-select +
   click-neighbour, both calling `sim:try_swap(a, b)`, which returns `ok` or a reason
   (`not_adjacent`, `unsettled`, `paused`, `stunned`, …).
   Cursor maths (verified): `GetCursorPosition()` returns screen-scale x and y with y from the
   **bottom**: divide by `frame:GetEffectiveScale()`, subtract `GetLeft()`/`GetBottom()`, flip the
   row index. `OnMouseUp` reaches the pressed frame even when the cursor is released outside
   (verified on a live client), so it is the primary release signal; poll `IsMouseButtonDown` in
   `OnUpdate` only as a fallback. The window is moved by a
   **title bar**, never by the board frame. The held gem's drag-follow offset is a **view-side**
   offset added to core `x,y` (Godot's drag/overshoot visuals are separate from board state).
   **Idle hint cut from W0** (calls `find_matches`, an allocator — later, never per frame).
6. **Persistence:** `DragonChessDB` stores window settings and the current-run snapshot.
   **W0 scope (critic): saved at fight boundaries only** (board only when at rest); a mid-fight
   `/reload` restarts the fight. `PLAYER_LOGOUT` also fires on `/reload`, just before SavedVariables
   are written (verified). On `PLAYER_LOGOUT` the view saves via `sim:settle_now()` +
   `board:serialize()` when at a fight boundary; on `ADDON_LOADED` + first `OnShow` it restores. A corrupt/mismatching
   snapshot (version field) is discarded silently and a new board starts.
7. **Launch:** slash commands; a minimap/compartment entry is W3 (not here). A debug slash
   `/dchess reset` clears the saved run.
8. **Art (updated 2026-10-04, native assets):** no generated textures. `ui/assets.lua` maps asset
   keys → WoW texture paths/FileIDs: the six gem icons `INV_Misc_Gem_*` (vanilla icon files exist in the beta; gem *items* don't). **Decided look:** `INV_Misc_Gem_{Ruby,Sapphire,Emerald,Amethyst,Topaz,Opal}_02`, cropped (`SetTexCoord` 0.08–0.92) and round-masked, see [../design/wow-forever-api.md](../design/wow-forever-api.md) for gem types 0–5, plus badge/overlay textures for tier 1/2, bomb, junk and the
   protected glow from in-game atlases/icons. Badge/overlay textures for tier 1/2, bomb, junk and the protected glow: pick from verified atlases
   (`UI-HUD-ActionBar-IconFrame`, `common-icon-checkmark`, `poi-workorders`,
   `auctionhouse-itemicon-border-purple` exist) or simple generated colour textures
   (`SetColorTexture`) — no extracted files. If Ruby/Amethyst are confused in playtests a shape
   cue is added later. Credits note in `CREDITS.md`.

## Alternatives considered

- **`AnimationGroup` per gem:** less code but timing is owned by the engine and can't pause with
  the sim or snapshot; also more objects. Lost: breaks "pause is free".
- **Texture-only rendering** (`SetTexCoord` on one big board texture): fastest but no per-gem
  hit testing, harder FX. Lost on flexibility, revisit if profiling says so.
- **Button frames with `OnClick`:** simpler input but no drag. The window frame handles
  `OnMouseDown/Up` and computes the cell from `GetCursorPosition()` / effective scale instead of
  64 buttons' scripts; chosen.

## Why this could be wrong

- Drag precision across UI scale / window scale: cell hit math must use
  `frame:GetEffectiveScale()`. Test at several scales.
- `OnUpdate` on a visible frame with 64 children + SetPoint calls each frame may cost more than
  expected; measure with `/dump` + `debugprofilestop()` in a debug build; target < 1 ms/frame.
- `PLAYER_LOGOUT` may be too late to settle long cascades (long ticks); `settle_now` is logic
  only so should be < a few ms (T1 soak must show it).
- Hide on combat entry: closing the window in combat is allowed (not a protected frame), but
  users may want auto-pause in combat; default stays "pause only on hide" (open question).

## Non-goals

No combat/HP/enemies (W0-G1/G2), no HUD (W0-P2), no sounds beyond a swap/clear click (optional),
no options panel, no minimap button, no final art.

## Tests / acceptance

- Automated: `core` tests from W0-T1 stay green (`tools/checks.sh`); new `ui_smoke` test loads
  all `ui/` files under `lua5.1` with a **stubbed WoW API** (`CreateFrame` returning a recording
  fake frame, `UIParent`, `GetCursorPosition`, `SlashCmdList`, …), fires `ADDON_LOADED`,
  `/dchess`, a few `OnUpdate`s, `OnHide`/`OnShow`, `PLAYER_LOGOUT`, and asserts: no error, no leaked
  globals except the documented ones (`DragonChessDB`, `SLASH_*`, `SlashCmdList` entries), the sim
  does not advance while hidden, and a snapshot round-trips.
- In-game checks (user or agent with a WoW client, manual): addon loads with no Lua errors
  (`/console scriptErrors 1`), `/dchess` opens, drag/click swaps work, close/open pauses and
  resumes (board unchanged while closed), `/reload` and relog restore the board.
- User playtest: feels snappy, drag is accurate, no hitches while cascades play.

## Open decisions

1. Window size: **8×56 px board, scale 1.0**, scale option later (Ctrl-wheel scaling cut from W0).
2. Pause on combat start? **No (default)**, per-player option in W3.
3. Texture format? **Not needed** (native assets); TGA only for fallbacks.
4. SavedVariables on cold start are reportedly broken in the beta: **treat an empty DB as a
   normal first run**, never error on missing data; test `/reload` (works) and mention in the
   report whether a cold start restores.

## Critic findings addressed (2026-10-04)

Soft pause with overlay for queue pops/ready checks/world entry added (hide-only pause still
punished an open window; the user's "hide = pause" stays the base rule); cursor maths and
`IsMouseButtonDown` release fallback documented; window drag via title bar, drag offset view-side;
snapshot reduced to fight boundaries; idle hint, Ctrl-wheel scaling and gem-pool growth cut from W0;
CREDITS step added; Interface number verified (16001).

## Art direction update (2026-10-04)

User decision: native WoW assets (see VISION "Theme and art direction"). Change 8 and open decision 3 above replaced; the ability-icon overlay on ability gems is in W0-G1/P2 scope (view side), the asset module is created here.
