# Enemy roster — WoW Classic (replaces the Godot names; mechanics unchanged)

Status: implemented in W0-G2c, models / backgrounds / sounds reworked in W0-P3.1 (awaiting in-game playtest; framing to tune live in the debug panel). Drafted 2026-10-04 (director decision after the user's "forget the old enemies, commit to WoW Classic").
The Godot roster ([enemies.md](enemies.md)) stays as the **mechanics and numbers** reference (HP, rotations,
cooldowns); only names, models, sounds and stage backgrounds change. Implementation: spec W0-G2c, W0-P3.1.

Models are shown with `PlayerModel:SetDisplayInfo(displayID)` (W0-P3.1: textured). `SetModel(FileDataID)` renders
white / untextured and stays only as the fallback before the portrait icon (chain: display ID -> model file ->
portrait). Display IDs were looked up in the wago.tools tables `CreatureDisplayInfo` x `CreatureModelData`
(ModelID -> FileDataID; files found via `tools/wow_asset.sh`). Backgrounds are the logo-free LFG dungeon art
(`Interface\LFGFrame\UI-LFG-BACKGROUND-*`; the loading screens have the WoW logo baked in and are dropped); sounds come
from `sound/creature/*` or `sound/spells/*` by FileDataID. Everything lives in `ui/assets.lua` (`Assets.ENEMY`,
`STAGE_BG_FILE`, `BG_LIST`).

| Stage | Fight | Enemy (new) | Replaces | Mechanic (unchanged) | Model: display ID (file) |
|---|---|---|---|---|---|
| 1 Dire Maul | 1 | **Hellhound** | Cerberus Puppy | plain bite (fast: 75–95 every 1.4 s base, W1-G3), weak Topaz | **38186** (`creature/hellhound` 511081; sounds: attack 600668, death 600677; wound 600671 unused) |
| | 2 | **Gordok Ogre** | Cyclops | Club Smash (stagger) | **415** (`creature/ogre/ogre` 125263) |
| | boss | **Basilisk Matriarch** | Medusa | Stone Gaze stagger + Mirror Shield | **141** (`creature/basilisk/basilisk` 123020) |
| 2 Zul'Gurub | 1 | **Forest Troll** | Troll | Rend (heal block), Regenerate | **167** (`creature/troll/troll`; foresttroll 124001 has no display rows) |
| | 2 | **Harpy** | Valkyrie | Talon Rake ×2 (70–92, 1.6 s) then flurry (52–72 × 4–5, 5.5 s) (W1-G3) | **148** (`creature/harpy/harpy` 124329) |
| | boss | **Hakkar the Soulflayer** | Thor | Thunderclap-style stagger, Aegis, charge nuke | **25634** (`creature/hakkar/hakkar` 124317; no texture-variation rows: may stay white, then pick another Hakkar display) |
| 3 Ahn'Qiraj | 1 | **Qiraji Scarab** | Mummy | junk (web), then three bites (70–89, 1.6 s) (W1-G3) | **7469** (`silithscarab2`; file 125892) |
| | 2 | **Anubisath Sentinel** | Anubis | curse, heal block | **5965** (`creature/anubisath/anubisath` 122906) |
| | boss | **Ouro** | Sphinx | Sandstorm | **15509** (`creature/sandworm/sandworm` 125795) |
| 4 Blackwing Lair | boss | **Nefarian** | World Dragon | phases (3), roar stagger, heal block, Sandstorm, Mirror | **11380** (`creature/dragon/dragonnefarian` 123461) |

Notes: the Godot phase names (Níðhöggr / Apep) become Nefarian phases (e.g. "Phase 2: Shadow Flame", "Phase 3:
Corrupted"), decided in W0-G2c. Names beyond the table (flavour lines, ability names like "Club Smash") may use the
Classic spell names of the mob (e.g. Hakkar: Corrupted Blood / Aspect abilities); keep ability *kinds* unchanged.

Backgrounds (W0-P3.1, `Assets.STAGE_BG_FILE`, FileDataIDs of the LFG art): stage 1 `lfg diremaul` **340663**, stage 2
`lfg zulgurub` **340705**, stage 3 `lfg aqtemple` **340650**, final `lfg blackwinglair` **340659**. Shortlist for the debug
panel / `/dcbg` (`Assets.BG_LIST`, 13 entries): the four above plus `aqruins` 340649, `maraudon` 340677, `zulfarak`
340704, `sunkentemple` 340690, `moltencore` 340678, `naxxramas` 340679 and the encounter-journal backgrounds
`ej diremaul` 608161, `ej zulgurub` 522348, `ej blackwinglair` 1396454. The LFG files are assumed 2:1
(`Assets.BG_FILE_W` x `BG_FILE_H` = 512 x 256, cover-fit crop; confirm in game, the EJ files' aspect is unverified: a
list entry may carry its own `w` / `h`). Per-enemy model framing (`cam_scale`, `pos`, `rot`, `scale`) is tuned live in
the debug panel (Tuning tab) and pasted back into `Assets.ENEMY`.

## Enemy rhythm and ability matchups (W1-G3)

Base values are authored raw; `Run.ATTACK_PACE` (2.2) multiplies cooldown and damage at run time. The three fast
attackers (Hellhound, Harpy, Qiraji Scarab) keep their old DPS (the data test pins it, +-2 %) but spread it over more,
smaller hits, so Fire Shield (12 s, reflects hit + 100) pays reliably against them. Keep these matchups when adding or
tuning enemies:

| Enemy rhythm | Strong | Weak |
|---|---|---|
| Fast, small hits (Hellhound, Harpy, Scarab) | Fire Shield (many hits returned), Rejuvenation (steady damage, little overheal) | Power Word: Shield (one stack per small hit), stun / freeze (delays one small hit) |
| Slow, heavy hits (Ogre, Sentinel, Ouro) | Power Word: Shield (a stack eats a big hit), stun / freeze / Arcane Explosion delay on the special, Fire Shield as a timed shot | untimed Fire Shield |
| Spell-punishing (Mirror, Aegis) | matches, shields | damage ultimates into the mirror |

Rhythm of the fast fights (difficulty 1, after pace): Hellhound a hit of ~168 every 3.75 s; Harpy two rakes of ~160
(4.2 s apart), then a flurry of ~552 (cycle 21.7 s); Scarab web, then three bites of ~157 (4.2 s apart; cycle 26.4 s).
Spec: [specs/w1-g3-reflect-and-fast-attackers.md](../specs/w1-g3-reflect-and-fast-attackers.md).
