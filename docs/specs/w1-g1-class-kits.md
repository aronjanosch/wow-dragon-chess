# Spec: W1-G1 — Class kits: 9 classes × 12 spells as variants of the 12 effect templates

Status: implemented — awaiting playtest (agreed rev 2, 2026-11-11; part A core + data + assets + tests, part B UI: kit in main.lua, status strip, class picker, /dcfx) — critic review worked in; the director decides the details (user: "you orchestrate and design"). Direction agreed by the user 2026-11-11
("map all abilities onto the classes, overlaps allowed, icons and effects must be right, keep the
balancing"). Issue #45.
Milestone: W1. Track: G (+ P presentation data, + start-menu class picker).
Pillars served: WoW Classic fantasy (you play *your* class), readable real-time combat (icon = the spell you know).

## Player experience goal

You open Dragon Chess on your Warrior and the board speaks Warrior: Cleave, Whirlwind, Shield Block, Retaliation —
with the icons, sounds and spell effects you know from the game. On your Mage it is Polymorph, Frost Nova, Arcane
Explosion. What a gem colour *does* is the same for every class (so the balance and the muscle memory carry over);
which spell it is, how it looks and sounds, is your class. You can pick another class on the start screen.

## Current state (facts, verified 2026-11-11)

- 12 ability definitions in `core/abilities/<colour>.lua`, each already carries `id`, `template = id`, `variants = {}`,
  `icon = id`, `name`, `description`, `blurb`, numbers, `execute`.
- `core/kit.lua`: `Kit.DEFAULT` (colour → {skill id, ult id}), `Kit.new(map)` copies the defs, `kit:get(colour, tier)`.
  `Combat.new{ kit = … }` / `Combat.deserialize(data, { kit = … })`; `ui/main.lua` l.153 / l.167 always pass
  `Kit.default()`. The kit is not part of a saved run.
- Presentation is looked up by ability id: icon `A.ICONS[ability.icon]` (`ui/assets.lua`), sound
  `A.SOUNDS["ab_" .. id]` via `A.ABILITY_KEY` (`fight_view.lua` l.1253), spell effect `A.FX[id]`
  (`fight_view.lua` l.1261, `ui/fx.lua`). `combat.lua` l.596 puts `id` / `icon` into the `ability_triggered` info.
- Status icons are fixed keys: `status_shield`, `status_fire_shield`, `status_lifesteal` (player strip,
  `fight_view.lua` l.723), `enemy_stun` / `enemy_freeze` (l.1627); held effects `A.FX_HOLD` (stun stars, freeze block).
- Several canonical icons are wrong today (placeholders that rendered in the first probe): Hammer of Justice shows
  `Spell_Frost_Stun` (Concussive Shot), Mind Control `Spell_Shadow_ShadowBolt`, Arcane Explosion
  `Spell_Frost_FrostBolt02`, Whirlwind `Spell_Nature_Lightning`, Flamestrike `Spell_Fire_FlameBolt`, Rain of Fire
  `Spell_Fire_SelfDestruct`.
- All 109 icon file names used below exist in the community listfile with vanilla-range FileDataIDs (132089–136255),
  checked by script.

## Design

### 1. Model: a variant is a skin, never a rule change

- **Template** = one of the 12 existing definitions (numbers + `execute`). Untouched.
- **Variant** = `{ id, template, name, icon, classes, [description], [blurb] }`. It is registered into
  `ns.Abilities[id]` as a shallow copy of its template with those fields overridden. Everything else (damage,
  durations, counts, score, `execute`, `color`, `tier`) is the template's, by construction.
- **No class twists in this item.** Classes differ in fantasy, not in numbers: the balance of today is preserved
  exactly, and a test proves it (same seed + same inputs → identical fight with any class kit).
- The 12 canonical definitions stay as they are (ids, golden tests, default kit) and are themselves the variant of
  the class that owns the spell (e.g. `frost_nova` is the Mage's Sapphire ult).

### 2. The mapping (9 classes × 12 slots)

Slots: **A1** Amber skill — clears heal you 10 s · **A2** Amber ult — 10 random gems → Amber · **M1** Amethyst skill —
200 dmg + stun 3 s · **M2** Amethyst ult — all gems of one colour → Amethyst · **E1** Emerald skill — block the next
hit (stacks) · **E2** Emerald ult — 5 gems become bombs · **R1** Ruby skill — 150 dmg + cone clear toward the enemy ·
**R2** Ruby ult — 10 s nullify + reflect · **S1** Sapphire skill — 150 dmg + 3×3 clear + enemy attack delayed ·
**S2** Sapphire ult — 500 dmg + enemy frozen 5 s · **T1** Topaz skill — 150 dmg + row clear · **T2** Topaz ult —
chain-clear every gem of the partner colour.

Bold = canonical id (existing definition). Icon = `Interface\Icons\<name>` = the spell's real Classic icon.

| Slot | Mage | Warlock | Warrior |
|---|---|---|---|
| A1 | Evocation `Spell_Nature_Purge` | **Drain Life** `Spell_Shadow_LifeDrain02` | Bloodthirst `Spell_Nature_BloodLust` |
| A2 | **Polymorph** `Spell_Nature_Polymorph` | Corruption `Spell_Shadow_AbominationExplosion` | Battle Shout `Ability_Warrior_BattleShout` |
| M1 | Counterspell `Spell_Frost_IceShock` | Death Coil `Spell_Shadow_DeathCoil` | Intercept `Ability_Rogue_Sprint` |
| M2 | Arcane Power `Spell_Nature_Lightning` | Enslave Demon `Spell_Shadow_EnslaveDemon` | Challenging Shout `Ability_BullRush` |
| E1 | Ice Barrier `Spell_Ice_Lament` | Shadow Ward `Spell_Shadow_AntiShadow` | Shield Block `Ability_Defend` |
| E2 | Blast Wave `Spell_Holy_Excorcism_02` | **Rain of Fire** `Spell_Shadow_RainOfFire` | Recklessness `Ability_CriticalStrike` |
| R1 | **Flamestrike** `Spell_Fire_SelfDestruct` | Hellfire `Spell_Fire_Incinerate` | Cleave `Ability_Warrior_Cleave` |
| R2 | Fire Ward `Spell_Fire_FireArmor` | **Fire Shield** (Imp) `Spell_Fire_FireArmor` | Retaliation `Ability_Warrior_Challange` |
| S1 | **Arcane Explosion** `Spell_Nature_WispSplode` | Howl of Terror `Spell_Shadow_DeathScream` | Thunder Clap `Spell_Nature_ThunderClap` |
| S2 | **Frost Nova** `Spell_Frost_FrostNova` | Inferno `Spell_Shadow_SummonInfernal` | Concussion Blow `Ability_ThunderBolt` |
| T1 | Arcane Missiles `Spell_Nature_StarFall` | Shadow Bolt `Spell_Shadow_ShadowBolt` | **Whirlwind** `Ability_Whirlwind` |
| T2 | Blizzard `Spell_Frost_IceStorm` | Curse of Agony `Spell_Shadow_CurseOfSargeras` | Sweeping Strikes `Ability_Rogue_SliceDice` |

| Slot | Paladin | Shaman | Hunter |
|---|---|---|---|
| A1 | Seal of Light `Spell_Holy_HealingAura` | Healing Stream Totem `INV_Spear_04` | Mend Pet `Ability_Hunter_MendPet` |
| A2 | Blessing of Kings `Spell_Magic_MageArmor` | Flametongue Weapon `Spell_Fire_FlameTounge` | Hunter's Mark `Ability_Hunter_SniperShot` |
| M1 | **Hammer of Justice** `Spell_Holy_SealOfMight` | Earth Shock `Spell_Nature_EarthShock` | Scatter Shot `Ability_GolemStormBolt` |
| M2 | Redemption `Spell_Holy_Resurrection` | Purge `Spell_Nature_Purge` | Tame Beast `Ability_Hunter_BeastTaming` |
| E1 | Blessing of Protection `Spell_Holy_SealOfProtection` | Lightning Shield `Spell_Nature_LightningShield` | Feign Death `Ability_Rogue_FeignDeath` |
| E2 | Seal of Command `Ability_Warrior_InnerRage` | Fire Nova Totem `Spell_Fire_SealOfFire` | Explosive Trap `Spell_Fire_SelfDestruct` |
| R1 | Holy Wrath `Spell_Holy_Excorcism` | Flame Shock `Spell_Fire_FlameShock` | Multi-Shot `Ability_UpgradeMoonGlaive` |
| R2 | Retribution Aura `Spell_Holy_AuraOfLight` | Grounding Totem `Spell_Nature_GroundingTotem` | Deterrence `Ability_Whirlwind` |
| S1 | Consecration `Spell_Holy_InnerFire` | Earthbind Totem `Spell_Nature_StrengthOfEarthTotem02` | Frost Trap `Spell_Frost_FreezingBreath` |
| S2 | Repentance `Spell_Holy_PrayerOfHealing` | Frost Shock `Spell_Frost_FrostShock` | Freezing Trap `Spell_Frost_ChainsOfIce` |
| T1 | Hammer of Wrath `Ability_ThunderClap` | Lightning Bolt `Spell_Nature_Lightning` | Aimed Shot `INV_Spear_07` |
| T2 | Judgement `Spell_Holy_RighteousFury` | **Chain Lightning** `Spell_Nature_ChainLightning` | Volley `Ability_Marksmanship` |

| Slot | Rogue | Priest | Druid |
|---|---|---|---|
| A1 | Hemorrhage `Spell_Shadow_LifeDrain` | Vampiric Embrace `Spell_Shadow_UnsummonBuilding` | Rejuvenation `Spell_Nature_Rejuvenation` |
| A2 | Instant Poison `Ability_Poisons` | Power Infusion `Spell_Holy_PowerInfusion` | Mark of the Wild `Spell_Nature_Regeneration` |
| M1 | Cheap Shot `Ability_CheapShot` | Psychic Scream `Spell_Shadow_PsychicScream` | Bash `Ability_Druid_Bash` |
| M2 | Blind `Spell_Shadow_MindSteal` | **Mind Control** `Spell_Shadow_ShadowWordDominate` | Faerie Fire `Spell_Nature_FaerieFire` |
| E1 | Evasion `Spell_Shadow_ShadowWard` | **Power Word: Shield** `Spell_Holy_PowerWordShield` | Barkskin `Spell_Nature_StoneClawTotem` |
| E2 | Ambush `Ability_Rogue_Ambush` | Shadow Word: Pain `Spell_Shadow_ShadowWordPain` | Insect Swarm `Spell_Nature_InsectSwarm` |
| R1 | Eviscerate `Ability_Rogue_Eviscerate` | Holy Fire `Spell_Holy_SearingLight` | Swipe `INV_Misc_MonsterClaw_03` |
| R2 | Riposte `Ability_Warrior_Challange` | Inner Fire `Spell_Holy_InnerFire` | Thorns `Spell_Nature_Thorns` |
| S1 | Gouge `Ability_Gouge` | Holy Nova `Spell_Holy_HolyNova` | Hurricane `Spell_Nature_Cyclone` |
| S2 | Kidney Shot `Ability_Rogue_KidneyShot` | Silence `Spell_Shadow_ImpPhaseShift` | Entangling Roots `Spell_Nature_StrangleVines` |
| T1 | Blade Flurry `Ability_Warrior_PunishingBlow` | Mind Flay `Spell_Shadow_SiphonMana` | Wrath `Spell_Nature_AbolishMagic` |
| T2 | Adrenaline Rush `Spell_Shadow_ShadowWordDominate` | Dispel Magic `Spell_Holy_DispelMagic` | Starfire `Spell_Arcane_StarFire` |

Why these (the fit rule: the spell's real effect resembles the slot's effect; where a class has nothing close, the
nearest fantasy wins): Thunder Clap / Hurricane really slow attacks (S1 delay); Retaliation / Riposte / Thorns /
Retribution Aura really hit attackers back (R2); Bloodthirst / Seal of Light / Vampiric Embrace really heal on hits
(A1); Shield Block / Lightning Shield really have charges (E1); Fire Nova Totem / Explosive Trap really are armed
objects that blow up (E2); Intercept (3 s) and Concussion Blow / Silence (5 s) match the real durations.

Variant ids = snake_case of the spell name (`thunder_clap`, `power_infusion`, …). Fire Ward (Mage) is its own variant
`fire_ward` of template `fire_shield`. Same icon on two classes is fine (it is the real icon); within one class all
12 icons are distinct (test).

Blurb / description: every variant gets a correct blurb (several template blurbs are stale, e.g. Flamestrike
"Wave-clear a row", Polymorph "Convert partner → Amber": fix those on the canonical definitions too — text only).
A variant overrides the description where the template text names the wrong thing ("Fire shield",
"freeze", "Chain lightning", "fire cone"): e.g. Concussion Blow "Heavy damage · stun enemy", Retaliation
"Strike back at attacks — {fire_shield_duration}s". Placeholders stay; numbers always come from the template.

### 3. Core changes (pure Lua, no WoW API)

- New `core/classes.lua`, loaded after the six ability files and before `data/enemies.lua` — in `DragonChess.toc`,
  in `test/loader.lua` `CORE_FILES`, and its test `class_test` in `tools/checks.sh`:
  - registers the 96 variants into `ns.Abilities` via one helper `variant(template_id, id, name, overrides)` =
    shallow copy of the template + `id`, `template`, `name`, `icon = id` + optional `description` / `blurb`;
  - `ns.Classes = { ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK",
    "DRUID" }, WARRIOR = { id = "WARRIOR", name = "Warrior", kit = { [0] = { skill, ult }, … [5] } }, … }`
    (keys = WoW class tokens, `UnitClass` 2nd return).
- The 12 canonical definitions keep id, icon key (= id), name and numbers; only their `ui/assets.lua` icon file
  names are corrected. The dead `variants = {}` field is removed from them (nothing reads it; a filled table would be
  shared by every copy). No `classes` field is written onto definitions (derive it from `ns.Classes` when needed).
- `core/kit.lua`: `Kit.for_class(class_id)` → `Kit.new(ns.Classes[class_id].kit)` with `kit.class_id` set; nil /
  unknown id → `Kit.default()` (`class_id = nil`). `Kit.default()` unchanged (tests, golden files).
- `core/combat.lua`, `core/run.lua`, `core/sim.lua`: **no change**. Nothing in core reads an ability's id / name /
  icon for logic (verified: the only `id ==` comparisons are status ids).
- Persistence lives in `ui/main.lua`: `class_id` goes into the boundary snapshot table and is read back in the
  restore path (l.167); `fresh_run` (l.153, also used by `/dchess fight` and the debug panel) builds the kit from the
  stored class. No `RUN_VERSION` bump: a save without `class_id` (or with an unknown one) resumes with the default
  kit, which the HUD labels "Classic".

### 4. Presentation (ui/, data in `ui/assets.lua`)

- **Inheritance is resolved once at load**, at the end of `ui/assets.lua` (the TOC loads it after core): for every
  `ns.Abilities` entry whose `template ~= id`, `A.SOUNDS["ab_" .. id]` and `A.FX[id]` are filled as
  copy-of-the-template's-entry overlaid with the variant's own (partial) entry, and `A.ICONS[id]` must exist.
  `A.ABILITY_KEY` is built after that fill. So every existing by-id lookup (`fight_view.lua` l.1253 / l.1261,
  `fx.lua` l.154 / l.206 / l.268–298) keeps working unchanged and no resolver / `info.template` is needed. A variant
  FX entry normally only names `m2` (+ `hold_fx`, `status_text`); `at`, `size`, `duration`, … come from the template,
  so the effect geometry (cone / cell / row / board / enemy / player) always fits the rule. Ults keep `key = true`.
- A variant sound slot gets `fallback = <the template's slot>` so a file that does not exist in the client plays the
  template's sound instead of silence (`play_slot` already follows `fallback` when `PlaySoundFile` reports failure;
  extend it to file fallbacks).
- `A.ICONS`: one entry per variant id; the six wrong canonical icon files are corrected (table above).
- Asset picks per variant: [design/class-kit-assets.md](../design/class-kit-assets.md) (the "Director overrides"
  table wins over the per-class tables). Battle Shout (Warrior A2): sound 568028 `battleshouttarget`, fx 165658
  `battleshout_cast_base`.
- **Non-kit glyphs move out of the way** (they are not tied to a spell, the kit icons are): `kind_curse` and
  `status_curse` → `Spell_Shadow_CurseOfMannoroth`; `kind_stagger` → `Ability_Smash`; `kind_sand` →
  `Spell_Nature_Earthquake`; `bomb` → `INV_Misc_Bomb_04` (all four checked in the listfile).
- **Statuses show the class's spell.** New `FightView:_apply_kit(kit)` (called at run start, resume and whenever the
  combat object is replaced) sets the player status strip textures from the kit: shield stacks → E1 icon, reflect →
  R2 icon, lifesteal → A1 icon. The enemy stun / freeze icon (read live, l.1627) uses the M1 / S2 icon of the kit.
- **S2 is not always "frozen".** The core status kind stays `"freeze"` (template rule, untouched). The view reads two
  presentation fields from the kit's S2 entry in `A.FX`: `status_text` (the l.1530 label: "FROZEN" for Frost Nova,
  Frost Shock, Freezing Trap; "SILENCED" Silence; "ROOTED" Entangling Roots; "STUNNED" for the rest) and `hold_fx`
  (FX key held on the enemy for the duration: the ice block only for the three frost spells, roots for Entangling
  Roots, else the stun swirl). Same two fields exist for M1 (default "STUNNED" + stun swirl).
- Banner, "READY" float and the ability gem badge already read name / icon from the kit ability: they follow.
- `/dcfx` without arguments lists only the event / hold keys and the current kit's 12 spells (not ~110 keys).

### 5. Class picker (ui/start_menu.lua)

- Default class = the character's class (`UnitClass("player")`), stored per character in
  `DragonChessCharDB.class_id` once chosen.
- Start screen (new run only): a row of the 9 class icons (`Interface\Glues\CharacterCreate\
  UI-CharacterCreate-Classes` + `CLASS_ICON_TCOORDS`, class colour from `RAID_CLASS_COLORS`, both guarded with
  fallbacks), the selected one highlighted, its name underneath, and below it the kit preview: 6 colours × 2 spell
  icons with a tooltip (spell name, description with numbers). Clicking a class selects it; Start begins the run
  with it. The class is fixed for the run (resume menu shows it, no picker).
- The picker tooltips format their text through `Kit.format_text` (numbers from the template).
- The fight HUD shows the class name next to the player bar label (small, class colour; "Classic" for the default kit).
- Local best-score records stay shared across classes (W2 decides per-class boards).

### 6. Tests and docs

- `test/class_test.lua` (new, in `checks.sh`):
  - structure: every class has 6 × 2 slots; a variant's template has the slot's colour / tier; 12 distinct icons per
    class; `Kit.for_class` fallback;
  - **field whitelist:** presentation keys are `{ id, template, name, icon, description, blurb }`; every other key
    of a variant is `rawequal` to its template's (numbers, `execute`, `text_extra`, helper functions), and the
    variant has no key the template lacks;
  - **forced parity, all 9 classes:** for each class and the default kit, the same seed and the same scripted
    inputs, with every one of the 12 slots forced (spawn each colour's skill and ult gem and trigger it); compare
    the full event stream with the presentation fields of `ability_triggered` (`id`, `icon`, `toast`, `blurb`)
    stripped, the numeric `hud_state`, and the RNG states (`combat.rng_combat`, the sim's streams) at the end;
  - assets (loads `ui/assets.lua` with the stubs): every variant id has an `A.ICONS` entry, a resolved sound slot
    and FX entry; variant ids are disjoint from enemy ability ids and from the non-ability `A.ICONS` keys; **no kit
    icon file equals a `kind_*` / `status_*` / `enemy_*` / `bomb` icon file**; every S2 / M1 variant has a
    `status_text` and a `hold_fx` that names an existing FX key.
- `ui_fx_test.lua` l.147–157 (asserts exactly 12 abilities, each with its own `m2` + sound file): restrict to the
  canonical definitions (`ab.template == ab.id`). `ability_test.lua` l.295 must not deep-compare whole definitions.
- UI tests: start-menu picker (select, persist, default from a `UnitClass` stub, unknown class → default kit),
  `_apply_kit` updates the status strip on start and resume, S2 label / hold per kit, snapshot round trip keeps
  `class_id`, sound fallback to the template slot.
- Docs: `design/classes-and-abilities.md` (final table), `design/class-kit-assets.md`, `design/audio.md`,
  `design/wow-addon.md`, `DECISIONS.md`, `ROADMAP.md`, `AGENTS.md` addon notes.

## Alternatives considered

- **Class twists now (1–2 rule changes per class):** makes classes play differently (VISION pillar 4) but moves the
  balance for 9 kits at once with no bot to measure it; the user asked to keep the balance. Follow-up item W1-G2.
- **Remap templates to other colours per class** (e.g. Warrior stun on Ruby): more class feel, but colour → effect
  is the game's core vocabulary and enemy weaknesses are per colour. Rejected.
- **Only the first five classes:** the model makes a class cost one table column plus assets; all nine ship.
- **Variant as a UI-only skin table (core unaware):** core already owns `name` / `icon`; one registry keeps banner,
  debug and tests consistent.

## Why this could be wrong

- **Sameness:** nine classes that play identically may feel like a reskin. Mitigation: status icons, sounds and
  effects all change; twists are the planned follow-up.
- **Stretch fits:** some slots have no natural spell (Rogue A1 Hemorrhage as heal-on-clear, Hunter M2 Tame Beast,
  Mage M2 Arcane Power). The icon is right, the fantasy is approximate.
- **Asset drift:** FileDataIDs are picked from the retail listfile and filtered to vanilla ranges, but only the live
  client proves them; a missing sound is silent and a missing model shows nothing (both degrade to "no extra
  effect", never an error). The debug panel can audition every variant.
- **Same icon, different meaning:** `Spell_Fire_SelfDestruct` is Flamestrike (Mage R1), Explosive Trap (Hunter E2)
  and the bomb gem; `Ability_ThunderBolt` is Concussion Blow and the enemy "stagger" intent glyph.

## Critic findings addressed (2026-11-11)

Build breakers (`ui_fx_test` counts 12 abilities; six by-id lookups the resolver design missed) → inheritance is
resolved once at load in `ui/assets.lua`, no core change, test restricted to canonical defs. Status strip built once
→ `_apply_kit`. Hard-coded "FROZEN" → `status_text` / `hold_fx` per variant. Icon clashes with non-kit glyphs (curse =
Shadow Bolt, stagger = Concussion Blow, sand = Hurricane, bomb = Flamestrike / Explosive Trap) → the glyphs move,
plus a collision test. Parity test too weak → all 12 slots forced, event stream minus presentation fields, RNG
states, field whitelist. Dead `variants = {}` removed. Persistence in `ui/main.lua`, not core. Mapping: Warrior A2
Bloodrage (costs health) → Battle Shout. **Not adopted:** turning every A2 into the class's crowd control (Fear, Sap,
Hibernate, Turn Undead, Scare Beast) — the slot *changes* gems, so "bless / imbue / mark / corrupt 10 gems" reads
better than fearing them, and Warlock already uses a fear at S1; Hunter E1 / R2 swap (Feign Death does not strike
back); dropping per-variant sounds / effects (the user wants them right, and the research is done). Hammer of Wrath
and Insect Swarm are both in 1.12 (critic was unsure). Icons were written from the Classic spellbook and checked for
existence in the listfile; the live client confirms the rest.

## Non-goals

- No number, rule, enemy or ladder change (W0-G3 stays a separate draft). No class twists. No per-class records.
  No new effect templates (Divine Shield belongs to W0-G3).

## Acceptance

- `tools/checks.sh` green, incl. the new parity test for all 9 classes.
- In game: the start screen offers the class (own class preselected); ability gems, banner, status strip and enemy
  stun icon show the class's spells; each spell plays a fitting sound and effect; a run resumed after `/reload`
  keeps its class.

## Open decisions (director default in bold; user may change any name)

1. Scope **all 9 classes**.
2. **No twists** in this item.
3. Mapping table above — every cell is the director's proposal.
