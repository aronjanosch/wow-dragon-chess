# Spec: W0-G2c — Canonical ability names and the WoW Classic roster

Status: implemented — awaiting in-game playtest. Direction (user 2026-10-04: "forget the old enemies and names, go fully WoW Classic; Freeze is Frost
Nova, Area Clear is Arcane Explosion"); naming of the other ten abilities and the roster table are the director's
proposals (user may change). Milestone: W0. Track: G/C. Depends on W0-G2b (merged).
Pillars served: 4/5 (identity), art direction; no mechanics change.

## Player experience goal

The game is recognisably WoW Classic: you fight Hellhounds, ogres, Hakkar, Ouro and Nefarian with spells named after
real WoW spells. Mechanics, numbers and balance stay exactly as they are.

## Current state (facts)

- Ability ids/names are Godot-era (`fire_wave`, `area_clear`, `freeze`, …; `core/abilities/<colour>.lua`,
  `core/kit.lua`, icon keys in `ui/assets.lua`, banner texts, tests, docs).
- Enemy ids/names are Godot-era (`cerberus_puppy`, `cyclops`, `medusa`, `troll`, `valkyrie`, `thor`, `mummy`,
  `anubis`, `sphinx`, `world_dragon`) in `data/enemies.lua` (hand-owned since G2a), `ui/assets.lua` `ENEMY`, tests
  (`golden_enemies.lua` is keyed by the Godot ids/names and must stay as the numeric reference).
- Design: [../design/classes-and-abilities.md](../design/classes-and-abilities.md) (canonical names),
  [../design/roster.md](../design/roster.md) (roster + model/background IDs), [../DECISIONS.md](../DECISIONS.md).

## Changes

1. **Rename the 12 abilities** (ids, display names, icon keys, banner/toast texts, tests, docs) per the canonical table:
   `fire_wave→flamestrike`, `fire_shield` (stays), `area_clear→arcane_explosion`, `freeze→frost_nova`,
   `row_clear→whirlwind`, `color_chain→chain_lightning`, `lifesteal→drain_life`, `convert→polymorph`,
   `stun→hammer_of_justice`, `color_swap→mind_control`, `shield→power_word_shield`, `bombs→rain_of_fire`. Mechanics
   unchanged. Each ability record gains an empty `variants = {}` table (W1 fills class-tagged variants:
   `{ name, icon, sound, fx, classes = {...} }`) and keeps a `template` field = its canonical id so variants can
   point at a template. Old ids appear nowhere in code afterwards (grep clean) except in comments/docs that
   cite Godot sources.
2. **Replace the roster** per [roster.md](../design/roster.md): enemy ids `hellhound`, `gordok_ogre`,
   `basilisk_matriarch`, `forest_troll`, `harpy`, `hakkar`, `qiraji_scarab`, `anubisath_sentinel`, `ouro`, `nefarian`;
   display names; `model` = FileDataID (put in `Assets.ENEMY`, `model_id`) with the existing portrait fallback;
   enemy ability display names renamed to Classic-style names (kinds/numbers/rotations untouched; e.g.
   Hellhound Bite, Ogre Smash, Stone Gaze, Rend, Wing Flurry, Mortal Strike-style names as the agent sees fit —
   plain, readable, no Godot names). Nefarian phases: "Shadow Flame" (phase 1), "Corrupted" (phase 2).
   Stage labels/names follow the stage table (Dire Maul, Zul'Gurub, Ahn'Qiraj, Blackwing Lair).
3. **Backgrounds:** `Assets.STAGE_BG_FILE = { 131835, 131886, 131819, 131827 }` (loading-screen FileDataIDs) with
   cover-fit crop using the image aspect (assume 1024×512 and make it a constant; confirm in game); `/dcbg` cycles
   the shortlist (the four + `maraudon` 131850, `zulfarrak` 131885, `sunkentemple` 131872, `moltencore` 131851,
   `naxxramas` 131854); atlas path stays as fallback. (The enemy panel at full brightness, the board panel with the
   lighter dim.)
4. **Tests/data:** `enemy_data_test` keeps comparing numbers against `golden_enemies.lua` through an explicit
   `old id → new id` map (names excluded); every test, helper and the bot tests use the new ids; `/dchess fight
   <id>` takes the new ids; ui_smoke expectations updated. `tools/checks.sh` clean on both runners.
5. **Docs:** update `docs/design/abilities.md` (table gets the canonical names next to the old), `enemies.md` header
   mapping old→new, `wow-addon.md` sections that cite ids, `audio.md` slots.

## Alternatives considered

- **Keep Godot ids internally and only rename display names:** cheaper, but every future spec/probe/data file
  would carry two vocabularies; renaming once, now, is cleaner.
- **Rename also the mechanics (e.g. Medusa → a real gorgon boss):** no — mechanics stay the numeric reference.

## Why this could be wrong

- Some mapped creatures may not match their mechanic well (e.g. a Basilisk "Mirror Shield"); the table is easy
  to change later because ids/models/names live in data.
- Model FileDataIDs may not render in the Forever client; the portrait fallback covers failures (confirmed by
  `/dcprobe m2` before relying on them).

## Non-goals

No mechanics/balance changes, no class kits (W1), no sound/effect wiring (W0-P3), no UI layout changes.
