# Spec: W0-P3.1 — Playtest-3 fixes + debug panel (W0-D1)

Status: implemented — awaiting in-game playtest (agreed by the user 2026-10-04 playtest 3: "not all the models fit yet", "the backgrounds don't quite fit", "sounds
great, attack 20 % quieter", "drop the hurt sound", "debug menu", "/dchess fight nefarian does nothing"; effects
and stun + animation "super"). Milestone: W0. Track: P. Depends on W0-P3 (merged).

## Player experience goal

Every enemy shows its textured creature; the backdrops are scenic without the WoW logo; the fight sounds are balanced
and never annoying; one debug window lets the developer/tester reach any fight, status, effect or sound in seconds.

## Current state (facts, verified from screenshots + data)

- Enemy models rendered **white, untextured** (`SetModel(FileDataID)` loads the bare m2). `SetDisplayInfo(displayID)`
  applies the creature's textures (display 1000 worked). Display IDs for our file IDs were looked up in the
  wago.tools tables `CreatureDisplayInfo` × `CreatureModelData` (ModelID → FileDataID) — picks below.
- Backgrounds: the loading-screen art (`Interface\Glues\LoadingScreens`) has the **"World of Warcraft" logo baked in**
  (visible in the screenshots) → unusable. Logo-free scenic art exists: `Interface\LFGFrame\UI-LFG-BACKGROUND-<dungeon>`
  (e.g. diremaul 340663, zulgurub 340705, aqruins 340649, aqtemple 340650, blackwinglair 340659) and the encounter-journal
  backgrounds (`ui-ej-background-diremaul` 608161, `-zulgurub` 522348, `-blackwinglair` 1396454).
- Sounds: attack sounds too loud (user: ~20 % quieter); the creature **wound ("hurt") sound** on every damaged hit is
  annoying and must go. `PlaySound(File)` has **no volume parameter**; channels have their own user sliders and default
  volumes (SFX 100 %, **Ambience 60 %**, Dialog 100 %, Music 40 %).
- `/dchess fight nefarian` produced no visible effect in the live client (cause unknown; code path `App.dev_fight`
  in `ui/main.lua`, `Run:begin_fight(def)`; the offline ui_smoke case passes).
- Core already has: `Sim:spawn_ability_gem(col,row,tier,gem_type)`, `Combat.god_mode`, `Combat:deal_damage_to_enemy`,
  `heal_player`, `take_damage`, `apply_player_stun`, `apply_heal_block`, `apply_damage_debuff`, board effect primitives
  (`convert_color`, `set_gems_junk`, …) and `Run:begin_fight(def)`.

## Changes

1. **Models via display IDs:** `Assets.ENEMY[id].display_id` (primary; `model_id` stays only as a last fallback) —
   hellhound **38186**, gordok_ogre **415**, basilisk_matriarch **141**, forest_troll **167** (`creature/troll/troll`;
   the foresttroll m2 has no display rows), harpy **148**, hakkar **25634**, qiraji_scarab **7469**
   (`silithscarab2`), anubisath_sentinel **5965**, ouro **15509**, nefarian **11380**. Fallback chain:
   `SetDisplayInfo(display_id)` → portrait icon; per-enemy `cam_scale`/`pos`/`rot` tuned live via the debug panel and
   written into the table.
2. **Backgrounds:** `Assets.STAGE_BG_FILE = { 340663, 340705, 340650, 340659 }` (LFG backgrounds, logo-free), image
   aspect constant for these files (assume 2:1 — confirm; make it a constant), shortlist for cycling = those four +
   `aqruins` 340649, `maraudon` 340677, `zulfarak` 340704, `sunkentemple` 340690, `moltencore` 340678, `naxxramas` 340679
   and the three EJ backgrounds; the loading-screen list is dropped.
3. **Sounds:** remove the creature `wound_sound` playback (keep the data fields, unused) and any other per-hit hurt
   sound; route **creature attack sounds and `player_hit` through the `"Ambience"` channel** (`channel` field per slot,
   default 60 % volume ≈ −40 %; the user can raise it with the Ambience slider; if the user's Ambience is switched off in
   WoW's sound options these play silent — document it); abilities/UI stay on `"SFX"`. Provide `Assets.SOUNDS[k].channel`
   so the user can move any slot between channels from the debug panel.
4. **Stage label** shows the stage name: "STAGE 1-2 · DIRE MAUL" (from `Assets.STAGE_NAME`).
5. **`/dchess fight <id>` fix:** reproduce offline (also with the window hidden / game paused / a fight mid-way), make
   it work in the live client, always print feedback ("fight: nefarian" or the reason), route errors to the chat.
6. **Debug panel (W0-D1):** `/dchess debug` toggles a movable panel (only after the user enables it; stored in
   `DragonChessDB.debug`), all through one `ui/debug.lua` + small pure helpers in `core/debug.lua` (tested):
   - **Fights:** a button per enemy (jump to that fight), difficulty +/−, "kill enemy", "heal player", "hurt player",
     "next fight", god mode toggle, restart run.
   - **Board:** spawn a skill or ult gem of a chosen colour at a random cell (`Sim:spawn_ability_gem`), convert N random
     gems to a colour, make junk, force a shuffle.
   - **Statuses:** stun/freeze enemy, stun player, heal block, curse, Aegis/Mirror on the enemy, Sandstorm.
   - **Effects and sounds:** one button per `Assets.FX` key and per `Assets.SOUNDS` slot (replaces typing `/dcfx`,
     `/dcsnd`), channel selector per sound.
   - **Presentation tuning:** background prev/next (name + ID shown), enemy model cam scale / x / y / z / rotation
     steppers that print the values for `Assets.ENEMY`, FPS/frame-cost readout (`debugprofilestop`).
   Everything cosmetic obeys pause; debug actions are allowed while paused where they make sense and never write records
   or the saved run.
7. **Tests:** ui_smoke/ui_debug_test (panel opens/closes, each action calls the right core API on a fake combat, dev
   actions never record/save, display-ID fallback chain, background shortlist, wound sound absent, Ambience channel for
   creature attack + player_hit), core/debug helper tests; checks clean on lua5.1 + luajit.

## Alternatives considered

- **Lower volume by editing the sound files:** impossible (client data). **Per-sound volume via CVar swaps:** changes the
  global SFX slider; rejected. **Ambience channel:** a free ~−40 % that the user can still tune — chosen, with the caveat.
- **Keep loading-screen art and crop out the logo:** the logo sits mid-image; cropping loses most of the picture.

## Why this could be wrong

- Display IDs may render differently in the Forever client than expected (scale/camera); the debug panel's tuning is the
  mitigation. Hakkar's display has no texture variation rows (may stay white) — then pick another Hakkar display.
- Ambience may be disabled on some users' clients (silent attack sounds); acceptable for a first pass, revisit with a
  per-slot channel option in the menu.

## Non-goals

No new mechanics, no class kits, no gem-break sparkle (needs cell data from the core), no new abilities.
