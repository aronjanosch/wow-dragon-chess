# Roadmap — Dragon Chess for WoW (working title)

> The Godot prototype this addon was ported from lives in a private archive repo; paths like `scenes/…` or `docs/archive/…` refer to it.

Milestone plan and the reasons for each item. Why: [VISION.md](VISION.md). Current system state:
[design/](design/) (see [design/wow-addon.md](design/wow-addon.md) for the port map). Specs:
[specs/](specs/) (`w<milestone>-<track><n>-<slug>.md`). The Godot roguelite roadmap (M0–M5,
GitHub milestones M0–M5, issues #4–#38) is archived in
archive/roadmap-godot-roguelite.md and frozen on the branch
`archive/godot-roguelite`.

## How we work

Same loop as before: **discuss → spec → critic review → user agreement → implement → verify →
user playtest.** A spec marked "drafted — awaiting agreement" is not approved. Naming:
`W<milestone>-<track><n>`, tracks **G** gameplay · **T** tooling/tech · **P** presentation ·
**C** content · **R** release. GitHub issues/milestones for W0+ are created once the specs are
agreed (status lives there, not here).

Branches: **`wow-addon`** is the working branch (integration branch for the addon);
**`archive/godot-roguelite`** freezes the Godot game as of 2026-10-04; `dev`/`main` keep the Godot
game as it was. The Godot project stays in the repo as the reference implementation and test
lab for rules; the addon is the product.

## Milestones

| | Goal | Exit criteria |
|---|---|---|
| **W0 Base game port** | The Godot base game (board, abilities, enemies, run ladder, score) playable as an addon | You play a full 10-fight run in WoW; hide/show pauses and resumes; `/reload` keeps the run; core logic tested headless |
| **W1 Class identity** | Each Classic class gets its own 12-spell kit (2 per colour) as variants of the 12 effect templates | First five classes (Mage, Warlock, Warrior, Paladin, Shaman) feel different in play; later Hunter, Rogue, Priest, Druid |
| **W2 Social** | Guild/channel scoreboard, queue-time niceties | Two clients see each other's scores via the addon channel; pause + alert when a queue pops |
| **W3 Polish & release** | Art/sound consistency pass on native assets, title/IP gate, packaging | Public release on CurseForge/Wago/GitHub; credits and policy check done |

## W0 — Base game port (order = dependency order)

Scope = the Godot base game **without** roguelite layers (boons, draft, relics, shop, doors).
What's ported and what's cut: [design/wow-addon.md](design/wow-addon.md).

| Id | Item | Spec |
|---|---|---|
| W0-T1 | Pure-Lua core: seeded RNG, board, region matching, gravity/refill as a fixed-step simulation; headless tests under `test/` | #39 · [w0-t1-lua-core.md](specs/w0-t1-lua-core.md) |
| W0-P1 | Addon shell + board view: TOC, window, gem pooling, drag/click swap, pause on hide, resume, `SavedVariables` snapshot | [w0-p1-addon-shell-board-view.md](specs/w0-p1-addon-shell-board-view.md) |
| W0-G1 | Combat port: battle controller, damage, ability queue, 12 abilities (6 colours × skill/ult), player statuses, stub enemy, minimal text HUD | [w0-g1-combat-port.md](specs/w0-g1-combat-port.md) |
| W0-G2 | Enemies + run ladder: converter + full `enemy.gd` port (G2a), ladder/difficulty/score/enemy-status UI (G2b) | [w0-g2-enemies-ladder.md](specs/w0-g2-enemies-ladder.md) |
| W0-G2c | WoW Classic roster + canonical ability names: rename the 12 abilities (Frost Nova, Arcane Explosion, …), replace the Godot enemies with Classic mobs (models, names, backgrounds by FileDataID) | [w0-g2c-classic-roster-rename.md](specs/w0-g2c-classic-roster-rename.md) |
| W0-T2 | Bot port + parity measurement: `move_eval`, greedy / three_clear policies, reaction-time model, RNG-tape comparison with Godot's probe | outline only |
| W0-P2 | Godot-style fight screen with WoW assets: two panels, enemy model/portrait, attack queue, status icons, banner, score plaque, FX | [w0-p2-godot-style-hud.md](specs/w0-p2-godot-style-hud.md) |
| W0-P3 | Audio, spell effects and creature animation by FileDataID (listfile): per-ability sounds, effect models, stun/hit/death, scenic backgrounds | [w0-p3-audio-fx-anim.md](specs/w0-p3-audio-fx-anim.md) |
| W0-P4 | Minimap button, in-window menu (restart, sound), idle hint, no-moves shuffle feedback | [w0-p4-menu-hint-minimap.md](specs/w0-p4-menu-hint-minimap.md) |
| W0-P5 | Match / spawn / enemy-cast feedback (floats, sounds), swap hint, debug invincible / timer hold / live status tab | [w0-p5-feel-and-debug.md](specs/w0-p5-feel-and-debug.md) |
| W0-P6 | Snappy juice: gem break (flash / shards / sparkle), ability spawn rings, damage streaks with hit-on-arrival, trauma shake (menu option), colour vignette flashes, debug buttons | [w0-p6-match-and-damage-juice.md](specs/w0-p6-match-and-damage-juice.md) |
| W0-P3.1 | Playtest-3 fixes: textured models via display IDs, logo-free backgrounds, quieter attack / no hurt sound, stage names, `/dchess fight` fix, **debug panel** | [w0-p31-polish-and-debug-panel.md](specs/w0-p31-polish-and-debug-panel.md) |

## W1 – W3 (outline)

- **W1:** class kits **done as skins** (W1-G1, [specs/w1-g1-class-kits.md](specs/w1-g1-class-kits.md), all 9 classes); open follow-up: class twists (W1-G2, needs a way to measure balance first). Model in [design/classes-and-abilities.md](design/classes-and-abilities.md):
  12 effect templates, spell **variants** tagged by class, a class = one skill + one ult variant per colour (12 spells).
  Classic has **9 classes**; start with **Mage, Warlock, Warrior, Paladin, Shaman**, then Hunter, Rogue, Priest, Druid.
  Each class may get 1–2 small rule twists so classes differ in play. Class picker at run start.
- **W2:** addon channel scoreboard (join a hidden custom channel, `SendAddonMessage` with
  `"CHANNEL"`, ChatThrottleLib-style throttling, serialized + compressed packets, rank by
  guild/realm/all heard), local personal-best list for comparing; queue integration
  (`LFG_PROPOSAL_SHOW`, `UPDATE_BATTLEFIELD_STATUS` → alert + auto-pause).
- **W3:** consistency pass on the native-asset look (frames, backgrounds, boss presentation, sounds), minimap button/Compartment entry, settings panel, CurseForge/Wago
  packaging (BigWigs packager + CI), title/IP gate, CREDITS, retail + Forever interface numbers.

## Deferred (documented, not planned)

Boon draft, relics, shop, doors/path choice, ascension, run history, meta unlocks, grid-fight
prototype, balance bot (the Godot designs stay in `docs/design/boons.md`, `docs/archive/`).
Re-import candidates once W0–W2 are loved: boons (they already live in data), run summary.

## Decisions log

> The current, consolidated decisions live in [DECISIONS.md](DECISIONS.md). This log is the chronological record.

- 2026-11-11 — W1-G1 class kits (user: "map all abilities onto the classes, overlaps allowed, icons and effects must be right, keep the balancing"): all 9 classes as skins of the 12 templates, no twists, class picker, version 0.2.0. Critic review worked in (spec rev 2). W0-G3 stays out. Jewels gem set stays in the public package (user). Release target: CurseForge (project to be created by the user). Spec: [specs/w1-g1-class-kits.md](specs/w1-g1-class-kits.md).
- 2026-10-05 — Debug keyboard shortcuts are dropped for good (no key capture in the addon window); the debug panel
  buttons are the interface. W0-P6 "everything nice and snappy": match break, spawn, streaks, shake (user).

- 2026-10-04 — Pivot: ship as a free, open-source WoW addon instead of a Steam game (user). No
  business goals; a standalone Godot release stays possible if the addon takes off.
- 2026-10-04 — Rewrite is unavoidable (Lua), design/values are reused. Core logic is pure Lua with
  no WoW API so it runs and is tested headless with LuaJIT.
- 2026-10-04 — Scoreboard: addon channel only, no backend, no cheat protection, no global board.
  Local high scores always (user).
- 2026-10-04 — Roguelite layers (boons, relics, shop) cut from the addon scope; kept in docs and
  on `archive/godot-roguelite` (user).
- 2026-10-04 — Classes: each WoW class gets its own ability mapping onto the gem colours (user).
- 2026-10-04 — Critic review of W0-T1/P1/G1: scheduler contract, `lua5.1` as primary test runner, snapshots at fight boundaries only (W0), G1 re-scoped (stub enemy, enemy types → G2, bot parity → T2), soft pause on queue pop/ready check/world entry. Details in each spec's "Critic findings addressed".
- 2026-10-04 — Art direction (user): drop the pixel look; use native WoW assets by reference — gem icons (vanilla `INV_Misc_Gem_*`, verified) for the board, spell icons for abilities (overlaid on the ability gem), creature models/art for enemies, bosses and backgrounds, WoW sounds. One consistent Blizzard style. All asset references live in one module `ui/assets.lua`.
- 2026-10-04 — First in-game playtest of the board+combat build (user): it works; the text HUD is "super schlecht" — the fight screen must follow the Godot layout (board left; enemy, attack queue, bars, score plaque right) with WoW assets substituted. Gems: user plans own gem art later (Blizzard vanilla icons are a stand-in). → W0-P2 spec.
- 2026-10-04 — Playtest 2 (user): board/combat/ladder work; wants per-ability sounds + spell effects + creature animations (stun stars, death, attack), nicer backgrounds, minimap button, menu (restart/sound), idle hint + shuffle feedback. Asset source: the community listfile (FileDataID ↔ path) via `tools/wow_asset.sh` — sounds (`PlaySoundFile`), effect/creature models (`PlayerModel:SetModel`), loading-screen art (`SetTexture`). → W0-P3, W0-P4.
- 2026-10-04 — Playtest 2 follow-up (user): **forget the Godot enemy names; commit fully to WoW Classic** (mobs, spells, backgrounds). Classic/Forever has **9 classes** (not 13); first five: **Mage, Warlock, Warrior, Paladin, Shaman**. Abilities become effect templates with WoW-spell variants per class (12 spells per class, 2 per colour); **Freeze → Frost Nova, Area Clear → Arcane Explosion** (other ten renamed by the director, see design/classes-and-abilities.md). Every ability gets its WoW spell's sound, effect and animation; spell loops are cut/avoided. The director picks the backgrounds. Decisions register: DECISIONS.md.
- 2026-10-04 — Playtest 3 (user): effects/stun/animation "super", sounds super; models partly white (display IDs fix), loading-screen backgrounds carry the WoW logo (switch to LFG backgrounds), attack sounds −20 %, no hurt sounds, debug menu wanted, `/dchess fight nefarian` silent. → W0-P3.1.
- 2026-10-04 — Godot repo layout: addon lives in `wow/` of this repo on branch `wow-addon`
  (director's recommendation; user may switch to a separate repo).

## Open questions

- **SavedVariables on cold start** reportedly don't load in the Forever beta (they survive `/reload`): persistence and high scores must tolerate an empty DB; re-test as Blizzard patches ([design/wow-forever-api.md](design/wow-forever-api.md)).
- Gems don't exist as items in the beta (WotLK+), so gem art comes from icons/atlases/shapes, not socket-gem items — resolved: vanilla gem icons exist (probe 2026-10-04).

- Native assets to verify on a live client: gem-icon set (proposal in design/wow-forever-api.md) and whether six shapes stay distinguishable (colour-blind readability; fall back to a shape overlay if not), creature display via `PlayerModel`/`ModelScene` vs portrait textures, usable background atlases, `SOUNDKIT` choices, asset stability across patches.
- Enemy roster: decided (design/roster.md); creature models/animations to be confirmed in game (`/dcprobe m2`, `/dcprobe fx`).

- WoW Forever / Midnight API facts to verify early: PNG vs TGA textures, `Interface` number,
  addon-channel cross-realm/faction reach and current throttle values.
- Colour count: Godot has 6 colours (12 abilities). Keep 6; classes reuse the 12 effect templates via spell variants (9 classes × 12 spells).
- Final title (VISION release gate).
- Does the game also pause in combat (`PLAYER_REGEN_DISABLED`) or just on hide? Default: only hide.
