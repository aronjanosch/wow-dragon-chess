# Spec: W0-P3 — Audio, spell effects and creature animation (native WoW assets by FileDataID)

Status: **implemented — awaiting in-game playtest** (2026-10-04; changes 1-3, 5, 6; deviations at the end of this file). Earlier: AGREED to proceed with the director's proposal (user 2026-10-04: "lass uns mit deinem Vorschlag ins Rennen gehen"); IDs are
candidates, each confirmed in game with `/dcprobe sfx|fx|screens|file|m2`; unconfirmed assets stay silent/invisible.
Runs after W0-G2c (it uses the new ability and enemy ids). Milestone: W0. Track: P. Depends on W0-G2b (merged).
Pillars served: 5 (feedback over explanation: effects and sounds explain what happened), 1 (snappy: pooled
effect frames, no per-frame garbage), art direction (native WoW assets, one consistent style).

## Player experience goal

Every ability sounds and looks like the WoW spell it is mapped to (Frost Nova = the frost ring and its sound,
Chain Lightning = lightning, Shield = the shield spell). Gems breaking, enemy hits, stuns and deaths have real
effects and sounds instead of a red disc. Enemies move: attack, get hurt, stunned, die.

## Current state (facts)

- Sounds today (P2 agent picks, user: "badly chosen"): SOUNDKIT constants for open/close/skill/match,
  guesses for ult/hit/cleared/defeat (`ui/assets.lua` `Assets.SOUNDS`/`play`). The user's finds: **101** (SoundKit)
  = gem break, 129 attack (too loud), 132 attack vs shield, 139/235 miss; defeat uses the fail sound (ok).
  See [../design/audio.md](../design/audio.md).
- **Why browsing was hard:** the named `SOUNDKIT` table has only UI names (888); Wowhead blocks scripts (403).
  Solved: the **community listfile** (github.com/wowdev/wow-listfile, FileDataID ↔ path) — searchable with
  `tools/wow_asset.sh '<regex>'`. It gives `sound/spells/*.ogg` (play with `PlaySoundFile(fileDataID)`),
  `spells/*.m2` effect models and `creature/*/*.m2` creature models (show with `PlayerModel:SetModel(fileDataID)`),
  and `Interface\Glues\LoadingScreens\*.blp` scenic art (`SetTexture(fileDataID)`).
- Verified in the live client: `AnimationGroup` works; `PlayerModel:SetAnimation(id)` steps model animations;
  `ModelScene` actors have `SetSpellVisualKit`/`PlayAnimationKit`; `SetModel` accepts file IDs (123 was rejected
  as invalid — real IDs expected to work, **to be confirmed by `/dcprobe fx`**). `PlaySoundFile` exists
  (**confirm with `/dcprobe sfx`**).
- Candidate assets found (from the listfile; to confirm in game): abilities → sounds `flamestrike 568641`,
  `fireshield 569485`, `arcaneexplosion 568678`, `frostnova 569378`, `cleavetarget 568227`,
  `lightningboltimpact 568516`, `lifedrainloop 569031`, `polymorphtarget 569526`, `kidneyshot 569110`,
  `shadowwordpain_chest 568353`, `shieldwalltarget 569473`, `firebombimpact1 568733`; effect models
  `frost_nova_area 166210`, `stunswirl_state_head 166988` (stun stars), `chainlightning_impact_chest 165780`,
  `divineshield_low_base 165961`, `heal_low_base 166292`, `polymorph_impact 166649`,
  `arcaneexplosion_base 165576`, `whirlwind_state_base 167199`, `lifedrain_missile 166469`; creature
  `hellhound 511081` (Cerberus Puppy), hellhound sounds `attack 600668 / wound 600671 / death 600677`.
- Terms (the user asked): a **spell effect/visual** is a particle/model effect shown at a place (the Frost Nova
  ice ring, the stun stars above a head) — `spells/*.m2`. An **animation** is a creature model's own motion
  (stand, attack, wound, stun pose, death) — `PlayerModel:SetAnimation(id)` with the standard IDs
  (0 stand, 1 death, 8 wound, 14 stun, 16/17 attack unarmed/1H, 2 spell). A stunned mob in WoW shows both: the
  stun pose plus the stars effect; we want the same.

## Changes

1. **Asset table:** `Assets.SOUNDS[key] = {kit = id}` or `{file = fileDataID}` (one place; `play(key)` picks the
   call); slots per [../design/audio.md](../design/audio.md): gem break **101**, player hit (quieter than 129),
   blocked 132, miss 139/235, 12 ability sounds from the table above, per-enemy `attack_sound` /
   `special_sound` / `wound_sound` / `death_sound` in `data/enemies.lua` (optional fields, silent if absent),
   cleared/defeat kept. Rate-limit and "bigger = deeper, never squeakier" stay (pick sounds, no pitch).
2. **Effects layer `ui/fx.lua`:** a pool of `PlayerModel` frames (no per-frame allocation), `Fx.play(key,
   target)` where target = enemy frame / board cell / board centre / player bar; effect table in
   `Assets.FX[key] = {model = fileDataID, scale, offset, duration, anim = 0}` hooked on `ability_triggered`
   (per ability), `enemy_damaged` (impact effect replaces the red disc; a small hit effect on the enemy
   model), `status_changed` (stun: `stunswirl_state_head` above the enemy while stunned; freeze: frost nova
   state; Aegis/Mirror: shield models), `gems_cleared` (gem break: a cheap flipbook `GemDissolve_T1_Flipbook`
   at the cell if the grid is known, else a sparkle). Effects run on engine time but are cosmetic: they
   are stopped/hidden on pause, hide and soft pause (no effect plays while the sim is frozen).
3. **Creature animation:** the enemy `PlayerModel` uses `display` → `model` (FileDataID) per enemy in
   `Assets.ENEMY` (Puppy = hellhound 511081; others after the roster decision): idle on show, attack animation
   at `enemy_windup`, wound on `enemy_damaged` (throttled), stun pose while stunned, death animation +
   fade on `enemy_defeated`; fall back to the current display-ID / portrait path if the model fails.
4. **Backgrounds:** done in W0-G2c (loading-screen art by FileDataID, director's picks); this spec only wires the
   remaining polish if needed.
5. **Probe-driven:** every asset ID is first confirmed with `/dcprobe sfx`, `/dcprobe fx`, `/dcprobe screens`;
   unconfirmed IDs stay out of `Assets`.
6. **Tests:** ui_smoke: effect pool never grows past its cap, effects stop on hide/soft pause, per-event sound
   slots fire with the right key and respect the rate limit, animation ids per event, enemy fallback when
   `SetModel` errors; asset-table sanity test (every referenced key exists, IDs are numbers).

## Asset table v1 (director picks from the listfile; user confirmed `/dcprobe fx` renders and approved the sound candidates)

Sounds `{file = FileDataID}` (non-loop picks; cut at `max` seconds), effects `{m2 = FileDataID}`; anything the agent
finds missing for a slot is searched with `tools/wow_asset.sh` and recorded; unresolved slots stay empty.

| Ability (template) | Sound | Effect model | Target |
|---|---|---|---|
| Flamestrike | 568641 flamestrike | 166187 flamestrike_area | board cells of the cone (centre cell) |
| Fire Shield | 569485 fireshield | 166156 fireshield_impact_head (or 166162 fireward_impact_chest) | player bar |
| Arcane Explosion | 568678 arcaneexplosion | 165576 arcaneexplosion_base | the 3×3 centre cell |
| Frost Nova | 569378 frostnova | 166210 frost_nova_area (+ 166211 frost_nova_state on the enemy while frozen) | board centre / enemy |
| Whirlwind | 568227 cleavetarget | 167199 whirlwind_state_base | the cleared row |
| Chain Lightning | 568516 lightningboltimpact | 165780 chainlightning_impact_chest | on each hop / enemy |
| Drain Life | 568353 shadowwordpain_chest (max 1.2 s; `lifedrainloop` is a loop — avoid) | 166469 lifedrain_missile | player bar ← enemy |
| Polymorph | 569526 polymorphtarget | 166649 polymorph_impact | converted cells / board |
| Hammer of Justice | 569110 kidneyshot | 166175 fistofjustice_impact_chest (+ stun stars 166988 while stunned) | enemy |
| Mind Control | 567957 curseoftounges | (search `spells/*shadow*`/`*curse*` m2; else 166649) | board |
| Power Word: Shield | 569738 divineshield | 165961 divineshield_low_base | player bar |
| Rain of Fire | 568733 firebombimpact1 | 166678 rainoffire_missile / 166677 rainoffire_impact_base | bomb cells |

Events: **gem break = SoundKit 101** (user's pick) + a short sparkle (`GemDissolve_T1_Flipbook`, grid 3×4 = 12 frames
confirmed by the user's probe run, or the 4×6 reading if 3×4 plays garbled); player hit = quieter than 129 (candidate
567867 `m1hswordhitplate1a`, else keep 129 with cutoff 0.6 s — `PlaySound` cannot lower volume); blocked = SoundKit 132;
miss = SoundKit 139; hit effect on the enemy = 165559 `aimedshot_impact_chest` (replaces the red disc); stun =
166988 `stunswirl_state_head` above the enemy + stun pose (anim 14); freeze = 166211 on the enemy; death anim 1 + fade;
wound anim 8; attack anim 17 at `enemy_windup`.

Enemy creature sounds (attack / wound / death FileDataIDs; first/best match from `sound/creature/*`, silent if none):
hellhound 600668/600671/600677 · gordok_ogre 557659/557652/557653 · basilisk_matriarch 544938/544937/544939 ·
forest_troll 562789/562786/562783 (`creature/troll/*`) · harpy 551590/551591/551593 · hakkar 551411/551410/551407 ·
qiraji_scarab 560307/560305/– (`silithidwasp`) · anubisath_sentinel 544038/544040/– (`arcanegolem`, stand-in) ·
ouro –/553651/– (`lavaworm`, stand-in; search for a better worm/burrow sound) · nefarian 556312/556330/556356.

## Alternatives considered

- **Own particle system with textures:** more control, but not WoW's look and a lot of code; the listfile gives
  real spell models for free. Kept as fallback for effects that fail to render.
- **`SetSpellVisualKit` on ModelScene actors:** the "official" way to play a spell's visuals, but needs
  SpellVisualKit IDs (not in the listfile); direct `.m2` effect models cover the same visuals with known IDs.
- **Only sounds, no effects:** rejected — the user explicitly wants effects and animations.

## Loops and length

Spell sounds that are channel loops (e.g. `lifedrainloop`) are replaced by non-loop files or cut: keep the handle from
`PlaySoundFile` and call `StopSound(handle)` after a per-sound cutoff (default 1.5 s; `Assets.SOUNDS[key].max`).
The quieter replacement for 129 is chosen from `/dcprobe sfx` or the listfile.

## Why this could be wrong

- Effect `.m2` models may render at odd sizes/pivots in a `PlayerModel` (cameras are tuned for creatures);
  `SetCamDistanceScale`/`SetPosition` need per-effect tuning (a `/dcfx` tuning command like `/dcbg cam`).
- Some models may not exist in the Forever client's data (listfile is for current retail); confirm each.
- 16+ simultaneous model frames may cost frame time; cap concurrent effects, measure with `debugprofilestop`.

## Non-goals

No new abilities, no class kits (W1), no music, no options UI (W0-P4), no roster decision (separate, W0-G2c).

## Open decisions

1. Quiet hit sound — **user picks from `/dcprobe sfx` auditions** (or the listfile search).
2. Roster: which WoW creatures stand in for the ten enemies (hellhound for the Puppy is proposed) — **separate
   step; the listfile + `/dcprobe m2 <id>` make browsing creature models possible**.

## Implementation notes and deviations (2026-10-04)

- Implemented: `Assets.SOUNDS` (slots, gate, gap, cut-off), `ui/fx.lua` (+ `/dcfx`, `/dcsnd`), creature animation,
  per-enemy `attack_sound` / `wound_sound` / `death_sound`, tests (`test/ui_fx_test.lua`, ui_smoke / ui_menu_test
  adapted). Details: [../design/wow-addon.md](../design/wow-addon.md) "UI (W0-P3)", slots: [../design/audio.md](../design/audio.md).
- **Mind Control model:** `shadowworddominate_chest` 166833 (searched `spells/*shadow*|*curse*`; no model is named mind control).
- **Mirror Shield model:** `spellreflection_state_shield` 166940 (listfile search) instead of a second divine shield, so the
  two enemy shields look different; Divine Aegis uses `divineshield_low_base` 165961 as planned.
- Gem-break sparkle (`GemDissolve` flipbook) **skipped**: `gems_cleared` carries only per-colour counts (no cells) and
  the flipbook grid is unconfirmed; the gem-break sound is in.
- Chain Lightning plays its effect once on the enemy (not per `chain_hop`); Drain Life / the shields sit on the
  player bar; the whole effect set is a first guess to tune with `/dcfx cam`.
- No `special_sound` field (the creature list has attack / wound / death only). Missing creature sounds stay silent
  (Qiraji Scarab and Anubisath Sentinel have no death sound, Ouro only a wound sound: no worm attack / death file found).
- The enemy hit effect replaces the red disc whenever an effect frame can show; the disc stays as the fallback when
  no PlayerModel / the model fails. The death animation now plays 0.7 s before the 0.6 s fade (`ANIM.death_hold`).
- `match` sound slot removed: the click per match is replaced by the gem-break sound (kit 101) on `gems_cleared`.
