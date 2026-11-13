# Decisions register — read this first in every new session

> The Godot prototype this addon was ported from lives in a private archive repo; paths like `scenes/…` or `docs/archive/…` refer to it.

Durable, user-made decisions for the **WoW addon** (public repo `aronjanosch/wow-dragon-chess`). Newest block last within a topic.
The ROADMAP decisions log has the chronological story; this file is the current truth. If something here
conflicts with older docs (Godot docs, archived roadmap), this file wins. Update it whenever the user decides.

## Product

- **Free, open-source WoW addon** (Lua, repo root), target client **WoW Forever (live since 2026-11-04,
  client folder `_forever_`, build 1.60.1.70790)**, interface **16001** (unchanged from the beta). No money, no monetisation, no backend, no global leaderboard. Godot game frozen on
  `archive/godot-roguelite` (reference + rules).
- **Cut for now (documented, not deleted):** boons, relics, shop, doors, ascension, grid-fight mode (grid mode
  may come later). Roguelite layers are re-import candidates after the base game is loved.
- Social: addon-channel scoreboard only, **no cheat protection**, local high scores always (W2).
- Pause: hiding the window pauses; soft pause on queue pop / ready check / world entry. **Entering combat hides
  the window, leaving combat reopens it at the resume panel** (option, default on; user 2026-11-05).

## Content: everything is WoW Classic (decided 2026-10-04)

- **Enemies and bosses come from WoW Classic.** The old Godot names (Cerberus Puppy, Cyclops, Medusa, Thor,
  Anubis, Sphinx, World Dragon, Greek/Norse/Egyptian stages) are **forgotten**; mechanics are kept, names/models
  are replaced. Roster: [design/roster.md](design/roster.md).
- **Classic/Forever has 9 classes** (Warrior, Paladin, Hunter, Rogue, Priest, Shaman, Mage, Warlock, Druid) — the
  earlier "13" was wrong. **First five: Mage, Warlock, Warrior, Paladin, Shaman.**
- **Abilities = effect templates + spell variants.** The 6 gem colours × (skill + ult) = 12 effect templates.
  Each template has a canonical WoW spell name and may have several **variants** (other WoW spell names,
  icons, sounds, visuals) tagged by class. A class kit = for every colour one skill variant + one ult variant →
  **every class ends with 12 spells (2 per colour)**. This avoids designing 9 × 12 unique effects.
  Current rename (2026-10-04): Freeze → **Frost Nova**, Area Clear → **Arcane Explosion** (could also be Cleave
  etc. for other classes); the other ten get canonical names too — [design/classes-and-abilities.md](design/classes-and-abilities.md).
- **Each ability gets the sound, effect and animation of its WoW spell**, consistently. Sounds: `PlaySoundFile`
  (listfile FileDataIDs) or SoundKit IDs; effects: `spells/*.m2` models; creatures: `creature/*/*.m2` models +
  animations; backgrounds: loading-screen art. [design/audio.md](design/audio.md), spec W0-P3.

- **Class kits shipped (W1-G1, 2026-11-11): all 9 classes × 12 spells.** A variant is a skin only (name, icon,
  text, sound, effect, status label / hold effect); numbers and `execute` are the template's, proven by the forced
  parity test in `test/class_test.lua`. **No class twists yet** (user: keep the balance). Mapping table:
  [design/classes-and-abilities.md](design/classes-and-abilities.md); asset picks (unconfirmed in game):
  [design/class-kit-assets.md](design/class-kit-assets.md). The class is picked on the start screen (own class
  preselected, stored per character), fixed for a run and saved with it; a save without a class plays the default
  kit ("Classic"). Non-kit glyphs (curse, stagger, sandstorm, bomb) use icons no kit uses.
- **Amber is the healing colour (W1-G2, user 2026-11-11):** Amber skill = heal over time (5 % of max HP over 10 s,
  re-cast extends up to 20 ticks), Amber ult = instant heal **15 %** (the user's number); both stopped by Heal Block.
  Lifesteal and the convert ult are deleted. Measured with `tools/balance_probe.lua` (bot, swap pace 0.6 s):
  D3 win rate 47–50 % → 70–80 %, D5 3–7 % → 13 %; inside the gates of the spec, values kept. First knob if it
  plays too easy: `heal_percent` 15 → 12. Report: `docs/playtests/data/2026-11-11-amber-heals-probe.md`.
- **Release build has no debug tooling** (user 2026-11-11): `tools/package.sh` stages the addon without
  `core/debug.lua` / `ui/debug.lua` (`ns.DEV` switch); the public repo gets the same staged tree.
- **Licence: MIT** (user 2026-11-11) for the public repo and CurseForge (project id 1799077); `LICENSE`.
- **CurseForge name: "Dragon Chess"** (no game name in project names, CurseForge moderation policy).
- **W0-G3 (new ladder + Divine Shield) stays a separate draft** (user 2026-11-11) — not part of the class kits.

## Art / assets

- **Native WoW assets by reference** (never copied into repo/package): gem icons `INV_Misc_Gem_{Ruby,Sapphire,
  Emerald,Amethyst,Topaz,Opal}_02` cropped + round-masked (stand-in; the user plans **own gem art** later), spell
  icons, atlases, models, sounds. All references live in `ui/assets.lua`.
- **No Bejeweled / PopCap assets** (or any foreign art) in the package. Alternative readable gem set "Shapes"
  (menu: Gems: WoW / Shapes, `DragonChessDB.gem_set`): native raid-target markers by reference
  (`Interface\TargetingFrame\UI-RaidTargetingIcon_1..7`: star/circle/diamond/triangle/square/cross, distinct shape + colour).
- **Asset discovery:** the community listfile (`tools/wow_asset.sh '<regex>'`, github.com/wowdev/wow-listfile)
  is the lookup for sounds / effect models / creature models / loading screens. Wowhead blocks scripts (403);
  the in-game `SOUNDKIT` table has UI names only. Sound IDs already chosen by the user: **101 = gem break**
  (keep), 132 attack vs shield, 139/235 miss, 129 attack (too loud → quieter), defeat uses the fail sound.
- **Creature models:** use `PlayerModel:SetDisplayInfo(displayID)` (textured) — `SetModel(FileDataID)` renders white. Display IDs come from wago.tools `CreatureDisplayInfo` × `CreatureModelData`. Backgrounds: LFG dungeon backgrounds (`Interface\LFGFrame\UI-LFG-BACKGROUND-*`), **not** loading screens (WoW logo baked in).
- **Sound balance:** no per-sound volume exists; creature attack + player hit go through the Ambience channel (~60 %); **no hurt/wound sounds** (user).
- Loops: many spell sounds are channel loops (long) → pick non-loop files or cut with `StopSound` after a short time.
- Backgrounds: scenic loading screens (`Interface\Glues\LoadingScreens`), chosen by the director per stage.
- Animations: AnimationGroup works; model animations via `SetAnimation` (0 stand, 1 death, 8 wound, 14 stun,
  16/17 attack); a spell effect (e.g. Frost Nova ring, stun stars) is an effect model, a creature motion is an animation.

## Presentation / feel (2026-10-05)

- **Debug keyboard shortcuts are dropped** (no `EnableKeyboard` in the addon window); the debug panel is the interface.
- **Juice is view-only and pooled:** match break, spawn rings, damage streaks (hit reaction on arrival), trauma shake and
  colour vignettes live in `ui/juice.lua` / the HUD on sim time; shake has a menu option (`options.shake`, default on).
  No hit-stop (the sim is the clock). Break sound 101 stays. Spec: [specs/w0-p6-match-and-damage-juice.md](specs/w0-p6-match-and-damage-juice.md).

## Process

- Workflow: discuss → spec → critic review → user agreement → implement (subagents) → verify (`tools/checks.sh`)
  → user playtests in the live client. **Subagents run on Sonnet** (user instruction 2026-10-04).
- Test runner is **`lua5.1` primary**, LuaJIT secondary (WoW = real Lua 5.1; LuaJIT hides yield-in-pcall bugs).
- Persistence: run saved at fight boundaries; SavedVariables cold-start bug in the beta → empty DB is normal.
- WoW client path for testing: `<WoW>/_forever_/` (live; the old
  `_classic_beta_/` link stays for reference; addons symlinked into `Interface/AddOns/`; SavedVariables under `WTF/Account/<account>/SavedVariables/`). Dev probe: `/dcprobe …`.

## Gem art (2026-10-04, playtest 4)
- **Default gem set "Jewels" = the user's own gem art** (image-generated by the user 2026-11-11: oval amber, teardrop amethyst, emerald cut, round ruby, kite sapphire, trillion topaz; source sheet `docs/art/gems-source-2026-11-11.png`, cut to `media/gems/*.tga`, 128 px). History: the Godot gem art (`assets/bejewled/`, licence unknown) was removed for the CurseForge release (third-party content needs a licence); Andrew Tidey's CC0 set was tried and rejected as too garish, two rounds of free-asset research found nothing the user liked. Gem sets in the menu: Jewels / WoW / Shapes. Before sourcing any art: licence first.

## W1-G3 Reflect window and fast attackers (2026-11-13)
- **Fire Shield (Ruby ult, all eight skins) lasts 12 s (was 10 s; 15 s was agreed first and cut after the 100-seed probe: D3 71 → 84 %, D4 37 → 55 % wins; with 12 s 75 % / 45 %) and every reflected hit deals the hit + 100** (`reflect_bonus`, one number, also per flurry hit; not scaled by difficulty).
- **Hellhound, Harpy and Qiraji Scarab become fast attackers** (smaller, more frequent hits, same DPS as before; values in the spec). Global `Run.ATTACK_PACE` and all other enemies unchanged; the Forest Troll "berserk" phase was dropped (collides with the Amber heals, no lasting cue).
- Matchup table (who is strong or weak against which enemy rhythm) lives in `docs/design/roster.md`. Fallbacks if playtests complain: Hellhound back to the old bite; window 12 s; fast cooldowns 1.4–1.6 -> 2.0. Spec: `docs/specs/w1-g3-reflect-and-fast-attackers.md`.

## W1-G4 Shield stacks cap at 3 (2026-11-13)
- **Power Word: Shield (Emerald skill, all skins) holds at most 3 stacks** (`Combat.SHIELD_MAX_STACKS`). A cast at the cap still scores and plays its effect but adds nothing and floats "Shield max". Measured: the bot never banks, so 100-seed win rates do not move; the cap closes the deliberate bank of ten stacks before a boss. Carry-over between fights stays. Fallbacks if banking stays the best opening: cap 2, or no carry-over. Spec: `docs/specs/w1-g4-shield-stack-cap.md`.

## One repo (2026-11-13)
- **One repo:** the addon is developed in the public repo `aronjanosch/wow-dragon-chess` (addon at the root, fresh history); the former private repo with the Godot prototype is an archive. Releases via tag + BigWigs packager.
