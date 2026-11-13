# Audio — sound slots (WoW SoundKit IDs and FileDataIDs)

Status: implemented in W0-P3 (2026-10-04), balance reworked in W0-P3.1 (channels, no hurt sound); awaiting in-game
playtest. All IDs live in `ui/assets.lua` (`Assets.SOUNDS`, one table; a missing slot is silent).
`PlaySound(kitID, channel)` for SoundKit IDs, `PlaySoundFile(fileDataID, channel)` for `sound/**/*.ogg` files. There is
no per-sound volume, so a too-loud sound has to be replaced or moved to another channel; no pitch tricks (bigger events
use deeper sounds). Long spell sounds / channel loops are cut with `StopSound(handle)` after the slot's `max` seconds
(default 1.5 s for files).

## Channels (W0-P3.1)

Each slot has an optional `channel` field (default `Assets.SOUND_CHANNEL` = `"SFX"`). Every WoW sound channel has its own
user volume slider and default (SFX 100 %, **Ambience 60 %**, Dialog 100 %, Music 40 %), which is the only per-sound
volume lever there is. Playtest 3: attack sounds were too loud (~20 %) and the creature hurt sound annoying, so:

- **`player_hit` and the creature `enemy_attack` play on `"Ambience"`** (default 60 %, about -40 %); the user can raise or
  lower them with the Ambience slider in WoW's sound options. **Caveat:** if the user switched Ambience off in WoW's sound
  options these two play silent (nothing else is affected). A per-slot channel option in the menu is the follow-up if that
  turns out to be a problem.
- Abilities, UI, gem break, miss, blocked, cleared, defeat and the creature death sound stay on SFX.
- **No creature wound ("hurt") sound:** the `enemy_wound` slot and its playback are gone (the `wound_sound` fields stay in
  `data/enemies.lua`, unused; the wound *animation* stays). No other per-hit hurt sound exists.
- A fallback slot inherits the channel of the slot it backs up (`player_hit`'s kit 129 fallback also plays on Ambience).
- The debug panel's Sounds tab plays any slot and cycles its channel (SFX / Ambience / Dialog / Master), writing
  `Assets.SOUNDS[slot].channel`; "Print channels" lists the slots that are off the default in copy-paste form.

## How to find sounds

`tools/wow_asset.sh 'sound/spells/frostnova'` searches the community listfile (FileDataID ↔ path); creature sounds:
`sound/creature/<mob>/*attack*|*wound*|*death*`. SoundKit browsing: `/dcprobe sound`, `/dcprobe snd <text>`. In the addon:
`/dcsnd` lists the slots, `/dcsnd <slot>` plays one (ignores quiet mode and the rate limit), `/dcsnd <slot> <FileDataID>`
tries a file in a slot (e.g. a creature slot). Verified live earlier: kit 101, 129, 132, 139, 235 and the UI kits below.
Every file ID below is a director pick from the listfile; confirm in game, change the ID in `ui/assets.lua` if it sounds wrong.

## Slots

| Slot | Event (source) | Sound | Rate limit / cut-off | Quiet mode |
|---|---|---|---|---|
| `gem_break` | `gems_cleared` | kit **101** (user: "super") | gap 0.1 s | silent |
| `player_hit` | `player_damaged` | file **567867** `m1hswordhitplate1a` (quieter than 129); fallback kit 129 cut at 0.6 s | max 0.8 s; channel Ambience | plays |
| `blocked` | `attack_blocked`, `attack_reflected` | kit **132** | | plays |
| `miss` | `swap_rejected` | kit **139** (235 is the alternative) | | silent |
| `open` / `close` | window show / hide | SOUNDKIT `IG_MAINMENU_OPEN` 850 / `IG_MAINMENU_CLOSE` 851 | | silent |
| `click` | menu buttons | SOUNDKIT `GS_TITLE_OPTION_OK` 798 | | silent |
| `ability` | skill without its own slot | SOUNDKIT `IG_CHARACTER_INFO_TAB` 841 | | silent |
| `ult` | bomb / phase change / ult without its own slot | `RAID_WARNING`, else `UI_BNET_TOAST` 18019 | | plays |
| `cleared` | `enemy_defeated` | `IG_QUEST_LIST_COMPLETE`, else `UI_BNET_TOAST` | | plays |
| `defeat` | `run_lost` | `IG_QUEST_FAILED` (fail sound, ok) | | plays |
| `enemy_attack` / `enemy_death` | `enemy_windup` / `enemy_defeated` | file from the enemy def (below); no wound slot (W0-P3.1) | gap 0.2 / 0.2 s, max 1.5 / 2.5 s; attack on Ambience | silent |

### Abilities — one slot each (`ab_<ability id>`), fired on `ability_triggered`; ults are key sounds (quiet mode)

| Colour | Skill | File (`sound/spells/…`) | Ult | File |
|---|---|---|---|---|
| Ruby | Flamestrike | 568641 `flamestrike` | Fire Shield | 569485 `fireshield` |
| Sapphire | Arcane Explosion | 568678 `arcaneexplosion` | Frost Nova | 569378 `frostnova` |
| Topaz | Whirlwind | 568519 `whirlwindshort` | Chain Lightning | 568516 `lightningboltimpact` |
| Amber | Drain Life | 568353 `shadowwordpain_chest` (max 1.2 s; `lifedrainloop` is a loop, avoided) | Polymorph | 569526 `polymorphtarget` |
| Amethyst | Hammer of Justice | 569344 `fistofjustice` | Mind Control | 567957 `curseoftounges` |
| Emerald | Power Word: Shield | 569738 `divineshield` | Rain of Fire | 568733 `firebombimpact1` |

Class kits (W1-G1): the table above lists the canonical (default kit) spells. Every class spell is a variant with its
own slot `ab_<variant id>` (96 more); the picks are in [class-kit-assets.md](class-kit-assets.md). A variant slot is the
template's slot overlaid with the variant's file (so `key` and `gap` come from the template) and has
`fallback = <template slot>`: a file that does not play in the client plays the template's sound instead of silence.
Resolved once at load at the end of `ui/assets.lua`.

### Enemy creature sounds (`attack_sound` / `death_sound` in `data/enemies.lua`; absent = silent; the Wound column is kept in the data but unused since W0-P3.1)

| Enemy | Attack | Wound | Death | Source |
|---|---|---|---|---|
| Hellhound | 600668 | 600671 | 600677 | `creature/hellhound` |
| Gordok Ogre | 557659 | 557652 | 557653 | `creature/ogre` |
| Basilisk Matriarch | 544938 | 544937 | 544939 | `creature/basilisk` |
| Forest Troll | 562789 | 562786 | 562783 | `creature/troll` |
| Harpy | 551590 | 551591 | 551593 | `creature/harpy` |
| Hakkar | 551411 | 551410 | 551407 | `creature/hakkar` |
| Qiraji Scarab | 560307 | 560305 | – | `creature/silithidwasp` (stand-in) |
| Anubisath Sentinel | 544038 | 544040 | – | `creature/arcanegolem` (stand-in) |
| Ouro | – | 553651 | – | `creature/lavaworm` (stand-in; no worm attack / death file found) |
| Nefarian | 556312 | 556330 | 556356 | `creature/nefarian` |

### W0-P5 feel slots (unconfirmed file picks, audition with `/dcsnd <slot>`)

| Slot | Event | Sound | Notes |
|---|---|---|---|
| `match_4` / `match_5` / `match_6` / `match_7` | `match_resolved` length 4 / 5 / 6 / 7+ | 569631 `arcanemissileimpact1a` / 569402 `holybolt` / 569383 `holylight_low_head` / 567966 `holy_impactdd_uber_chest` | gap 0.15 s; longer = deeper file (no pitch in WoW); plays on top of `gem_break`; silent in quiet mode |
| `match_cascade` | 3-match at chain depth >= 2 | 569565 `arcanemissileimpact1b` | stands in for Godot's rising cascade pitch |
| `ability_spawn_skill` / `ability_spawn_ult` | `ability_gem_spawned` tier 1 / 2 | 642843 `ui_quest_objectivecomplete_01` / 567431 `levelup` | ult is a key sound (plays in quiet mode) |
| `enemy_special` | `enemy_ability_executed` with `is_special` | 568054 `arcane_form_precast` | Ambience channel, key sound |

### W0-P6 juice: no new sounds

The match break / ability spawn / streak / shake layer (`ui/juice.lua`, [wow-addon.md](wow-addon.md) "UI (W0-P6)") is
silent by design: the per-wave `gem_break` (SoundKit 101, the user's pick) and the W0-P5 slots above carry the audio
(break, 4+ match, spawn, enemy special, player hit). Quiet mode and the sound switch are unaffected; the "Screen shake"
option only covers the window offset. If the shards need a sound of their own it is a new slot in `Assets.SOUNDS`
(audition with `/dcsnd`), not a change to slot 101.

### Unresolved / to decide in game

- Player hit: 567867 is unconfirmed (the fallback only triggers when `PlaySoundFile` is unavailable, not when a file sounds bad).
- Scarab / Sentinel death and Ouro attack / death sounds (no suitable file found); stand-ins may sound off.
- 235 vs 139 for the miss; whether the creature attack sound is too frequent (`enemy_attack` gap 0.2 s) and whether Ambience is acceptable as the channel of `player_hit` / `enemy_attack` (user's attack volume was "~20 % too loud" in playtest 3; -40 % is the Ambience default).
