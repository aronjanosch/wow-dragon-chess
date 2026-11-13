# Spec: W0-P12 — Menus in one WoW dialog style: start, pause, result, options

Status: agreed (2026-11-11) — user: "design the menus better", scope and design left to the director ("your
decision"). Presentation only, no critic review (no gameplay rule or number changes).
Milestone: W0 / release polish. Track: P.

## Player experience goal

Every menu looks like it belongs to the game client: a framed dialog with a header plate, real WoW buttons and
checkboxes, grouped options, readable sizes. The start screen sells the run (your class, its spells, the
difficulty, your best score); the pause screen tells you where you are; the end of a run is a result screen, not a
line of text; options are options, not a column of toggle buttons.

## Current state (facts)

- `ui/start_menu.lua`: one box (start form 312 px wide: title text, 9 class icons 28 px, name, 6 × 2 spell preview
  32 px, "Difficulty: Dn" cycler button, Start; resume form 218 px: "Paused", class line, Continue, New run with
  inline confirm). Custom flat buttons (`BUTTON_BG` colour quads).
- `ui/menu.lua`: 9 flat text buttons in a column (Restart run, Sound, Quiet mode, Screen shake, Hide in combat,
  Difficulty, Window, Gems, Close), each cycling / toggling its value in the label.
- Run end: `ui/main.lua` builds a text ("Defeated!\nScore: …\nBest (Dn): …" / "VICTORY! …") shown by
  `Window.set_overlay` (a 340–360 px text box, click = new run). The same overlay shows errors, soft pause and
  "Stuck".
- Records: `Run.best_score(db, difficulty)`, `Run.unlocked(db)`, `Run.can_choose(db, d)`, `Run.record_result`.

## Changes

### 1. Shared panel kit (new `ui/panel.lua`, all art in `ui/assets.lua`)

Small factory used by all four menus (no game logic):
- `Panel.dialog(parent, w, h, title)`: frame with `BACKDROP_DIALOG`, a header plate
  (`Interface\DialogFrame\UI-DialogBox-Header`, title in `GameFontNormal`), mouse-enabled, strata / level above the
  board like today's menus.
- `Panel.button(parent, w, h, label)`: a native `UIPanelButtonTemplate` button (red WoW button); if the template is
  missing (pcall around `CreateFrame`), the current flat button. `Panel.primary(...)` = the same, larger
  (160 × 28, `GameFontNormalLarge`-ish label).
- `Panel.check(parent, label)`: `UICheckButtonTemplate` check box + label on the right; fallback: the flat toggle.
- `Panel.segment(parent, labels, w)`: a row of small buttons, one selected (gold text + lit background), for
  exclusive choices (difficulty, window size, gem set).
- `Panel.section(parent, text)`: gold small-caps style section label with a thin divider line.
- `Panel.icon(parent, size)`: square spell / class icon with the standard icon crop and a 1 px dark border.
- All buttons play the `click` slot; every template / texture / font / colour name lives in `ui/assets.lua`.

### 2. Start screen (`ui/start_menu.lua`, start form) — about 440 × 400

Top to bottom:
1. Header plate "Dragon Chess".
2. Section "Class": the 9 class icons at **36 px** (pitch 44), the selected one with a class-coloured border and
   full brightness, the others dimmed; the class name below in class colour (`GameFontNormalLarge`).
3. Section "Spells": 6 columns (one per gem colour, the gem at 18 px on top in the active gem set), below each the
   skill and the ultimate icon at **36 px** with the icon crop + border; tooltips as today (name, "Skill" /
   "Ultimate" + colour, description). A tiny "4" / "5+" tag left of the two rows says which match makes which gem.
4. Section "Difficulty": a 5-segment row "1 … 5"; locked levels greyed and not clickable, with a tooltip ("Win
   difficulty N−1 to unlock"); right of it "Best: <score>" for the selected difficulty ("—" when none).
5. Primary button **Start**.
6. Footer hint (dim, small): "Match 3 to attack · 4 makes a skill gem · 5+ an ultimate".
Behaviour is unchanged: picking a class / difficulty before anything is played applies at once (existing
`App.set_class` / difficulty logic).

### 3. Pause / resume (`ui/start_menu.lua`, resume form) — about 300 × 250

Header "Paused"; info block: class name (class colour), "<Stage name> <stage>-<fight> · Difficulty <n>", "Score
<score>"; primary **Continue**; buttons **Options** (opens the options panel) and **New run** (inline confirm as
today: first click arms it, label "Abandon this run? Click again").

### 4. Result screen (new form in `ui/start_menu.lua` or a small `ui/result.lua`) — about 340 × 300

Replaces the text overlay for a lost / won run only (errors, soft pause and "Stuck" keep the text overlay):
- Header "Defeated" (red title colour) or "Victory" (gold).
- Lines: class (class colour); lost: "Fell to <enemy name> (<stage>-<fight>)", won: "All ten enemies defeated";
  difficulty.
- **Score** large (`GameFontNormalHuge`), below it "Best (D<n>): <best>" and, on a new best, a gold "New best!";
  on a win that unlocks a level: "Difficulty <n+1> unlocked".
- Primary **New run** → the start screen (with the picker), instead of starting a run directly.
- The victory screen still waits for the death beat (`VICTORY_BEAT`) as today; records are written exactly as
  today (`Run.record_result`), only the display changes.

### 5. Options (`ui/menu.lua`) — about 280 × 330, same anchor as today

- Header "Options".
- Section "Sound": check "Sound", check "Quiet mode (key sounds only)" (disabled look when Sound is off).
- Section "Display": check "Screen shake"; "Window size" segment Small / Normal / Large; "Gems" segment
  Jewels / WoW / Shapes.
- Section "Game": check "Hide in combat".
- Bottom: button "Restart run" (inline confirm as today) and "Close".
- The Difficulty entry leaves the options (the start screen owns it); the title-strip difficulty button and its
  rules stay as they are.
- Esc handling, the stored option keys in `DragonChessDB.options`, and how `ui/main.lua` applies them stay
  unchanged.

### 6. Tests and docs

- `ui_menu_test.lua`, `ui_class_test.lua`, `ui_smoke.lua`: adapt to the new widgets (checks toggle the same option
  keys; segments select; locked difficulty not selectable; Best shown per difficulty; result screen content for a
  loss / a win with new best / with unlock; New run on the result screen leads to the start form; Options from the
  pause form; template-missing fallback builds flat widgets without error). Add the needed template stubs to
  `test/wow_stubs.lua`.
- `release_test.lua` (if present) keeps passing: no debug dependency in the menus.
- Docs: `docs/design/wow-addon.md` (menus section).

## Alternatives considered

- **Blizzard's Settings panel (Interface → AddOns) for options:** the API differs between client generations and
  takes the player out of the game window; an in-window panel is one click.
- **Custom art for buttons / frames:** no own art exists; native templates give the client's look for free.
- **Leave the result as text:** it is the moment the score matters most.

## Why this could be wrong

- Templates (`UIPanelButtonTemplate`, `UICheckButtonTemplate`, the header texture) are assumed to exist in the
  Forever client; each has a fallback, but the fallback is today's plain look.
- Sizes are designed blind (no screenshot in headless tests): the user checks proportions in game; all sizes are
  constants at the top of each file.
- A bigger start screen may cover more of the board behind it; it is a start screen, nothing is running.

## Non-goals

- No gameplay, record or option-semantics change; no new options; no keyboard handling; no change to the fight
  HUD, the title strip or the minimap button.

## Acceptance

- `tools/checks.sh` green.
- In game: the four menus share one look; start → play → pause → options → continue → lose / win → result → start
  works with the mouse only; every option does what it did before.
