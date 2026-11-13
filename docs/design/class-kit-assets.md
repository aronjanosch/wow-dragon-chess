# Class kit assets — sound and effect picks per spell variant (W1-G1, Amber rows W1-G2)

Status: listfile research 2026-11-11 (three research agents + director overrides), **unconfirmed in game**. Source of
the ids: community listfile via `tools/wow_asset.sh`. Encoded in `ui/assets.lua` (`SOUNDS["ab_<id>"]`, `FX[<id>]`,
`hold_fx`). Icons: see [../specs/w1-g1-class-kits.md](../specs/w1-g1-class-kits.md) (all verified in the listfile).

Rules: the spell's own file where one exists, else the closest of the same school; non-loop sounds or a `max`
cut-off. A FileDataID below 570000 does **not** prove a vanilla file (names like `spell_sh_*`, `warrior_*`,
`hunter_*`, `sindragosa_*` are later additions that may or may not exist in the Forever client): therefore a variant
sound that fails to play falls back to its template's sound, and a missing model simply shows nothing. Audition every
variant in the debug panel and fix ids here + in `ui/assets.lua`.

## W1-G2 Amber heals (2026-11-11)

The Amber slots became heals: A1 = HoT (`rejuvenation` template), A2 = instant heal (`lay_on_hands` template, key sound).
Both play on the player panel (`at = "player"`; canonical sizes 240 px / 1.2 s and 280 px / 1.6 s, to tune live). Rows below
are updated for A1 / A2 of every class and Mage M2 (Polymorph replaces Arcane Power). A1 rows that kept their old pick:
`bloodthirst` 568812 / 165726, `seal_of_light` 569017 / 166773, `healing_stream_totem` 568572 / 166244, `mend_pet`
569570 / 166292 (unchanged). Removed: `hemorrhage`, `vampiric_embrace`, `battle_shout`, `blessing_of_kings`,
`hunters_mark`, `instant_poison`, `power_infusion`, `flametongue_weapon`, `corruption`, `mark_of_the_wild`,
`arcane_power` (icons, sounds and effects deleted from `ui/assets.lua`).

New picks this item (every id seen in `wow_asset.sh` output on 2026-11-11, unconfirmed in game): sounds 568145
layonhands_low_chest, 568017 greaterheal_low_base, 569376 renew, 568907 firstaid, 568719 beastsoothe, 568859
soulstoneresurrection_base, 569419 flashheal_low_base, 569570 heal_low_base, 568028 battleshouttarget; models 166452
layonhands_low_chest, 166273 greaterheal_low_base, 166696 renew_base, 166204 food_healeffect_base, 166709
revivepet_impact_base, 166927 soulstoneresurrection_base, 166292 heal_low_base, 165658 battleshout_cast_base,
166694 rejuvenation_impact_base. Icons (all in the listfile): Spell_Nature_Rejuvenation, Spell_Holy_LayOnHands,
Spell_Nature_HealingTouch, Spell_Holy_Renew, Spell_Holy_GreaterHeal, Spell_Holy_HealingAura, Spell_Nature_HealingWaveGreater,
INV_Misc_Food_10, Spell_Nature_Purge (Evocation), Spell_Shadow_LifeDrain02, INV_Stone_04, Spell_Nature_BloodLust,
Spell_Holy_AshesToAshes, Ability_Hunter_MendPet, Ability_Hunter_BeastSoothe, Spell_Holy_SealOfSacrifice, INV_Potion_54,
INV_Spear_04. Not found in the listfile: a Healing Touch sound without the post-vanilla `spell_dr_*` name, Conjure Food /
Chain Heal / Healthstone / Healing Potion / Last Stand sounds of their own, a Chain Heal model. Deviations from the
spec's pick list: none beyond the proxies named in the rows (Chain Heal sound is flashheal, not a healingwave file).

## Director overrides (these win over the tables below)

| Variant | Field | Value | Reason |
|---|---|---|---|
| `hammer_of_justice` (canonical) | sound | 569344 `fistofjustice` | its own sound; `kidneyshot` 569110 moves to Rogue Kidney Shot |
| `whirlwind` (canonical) | sound | 568519 `whirlwindshort` | its own sound; `cleavetarget` 568227 belongs to Cleave |
| `retaliation` | sound | 569059 `strike` | vanilla name instead of `spell_heroicstrike_impact_01` |
| `sweeping_strikes` | sound | 568003 `rendtarget` | keeps `strike` unique within the Warrior kit |
| `concussion_blow` | sound / fx | 567960 `knockdown` / 166890 `slam_impact_chest` | vanilla instead of Shockwave (post-vanilla) |
| `blade_flurry` | sound | 568003 `rendtarget` | short vanilla sound instead of `warrior_bladestorm` |
| `freezing_trap` | sound | 569310 `frostnovastateend` | the Sindragosa impact is post-vanilla and loud |
| `silence` | hold | 166988 `stunswirl_state_head` | no silence state model exists |
| `insect_swarm` | sound max | 1.2 | state sound, may loop |
| `feign_death` | fx | inherit the template's | no fitting model |


## Mage
| slot | variant id | spell | sound id | sound path | max | fx m2 id | fx path | hold | note |
|---|---|---|---|---|---|---|---|---|---|
| A1 | conjure_food | Conjure Food | 568907 | sound/spells/firstaid.ogg |  | 166204 | spells/food_healeffect_base.m2 |  | no food sound exists; first aid is the closest heal cue (W1-G2); icon INV_Misc_Food_10 to confirm in game |
| A2 | evocation | Evocation | 568917 | sound/spells/restorationimpact.ogg |  | 166539 | spells/manainfuse_base.m2 |  | moved from A1 (W1-G2); a key sound now (ult slot); alt fx 166540 manashield_state_base |
| M1 | counterspell | Counterspell | 568860 | sound/spells/counterspell.ogg | | 165822 | spells/counterspell_impact_chest.m2 | | exact |
| M2 | polymorph | Polymorph | 569526 | sound/spells/polymorphtarget.ogg |  | 166649 | spells/polymorph_impact.m2 |  | W1-G2: replaces Arcane Power; placement and duration (board, 1.4 s) from the Mind Control template entry |
| E1 | ice_barrier | Ice Barrier | 569018 | sound/spells/icebarrirerimpact.ogg | | 166366 | spells/ice_barrier_state_chest.m2 | | alt sound 568316 icebarrirerstate, alt fx 166388 icebarrier_state |
| E2 | blast_wave | Blast Wave | 569062 | sound/spells/firenova.ogg | | 166144 | spells/firenova_area.m2 | | no blastwave files; fire nova is the closest fire AoE |
| R1 | flamestrike | Flamestrike | existing | | | existing | | | canonical |
| R2 | fire_ward | Fire Ward | 569262 | sound/spells/firewardtarget.ogg | | 166162 | spells/fireward_impact_chest.m2 | | exact |
| S1 | arcane_explosion | Arcane Explosion | existing | | | existing | | | canonical |
| S2 | frost_nova | Frost Nova | existing | | | existing | | existing (166211) | canonical |
| T1 | arcane_missiles | Arcane Missiles | 569631 | sound/spells/arcanemissileimpact1a.ogg | | 165569 | spells/arcane_missile.m2 | | alts 569554 / 569565 (impact1c / 1b) |
| T2 | blizzard | Blizzard | 568542 | sound/spells/blizzardimpact1a.ogg | | 165716 | spells/blizzard_impact_base.m2 | | alts blizzardimpact1b..f (568843, 568493, 569304, 569145, 568128) |

## Warlock
| slot | variant id | spell | sound id | sound path | max | fx m2 id | fx path | hold | note |
|---|---|---|---|---|---|---|---|---|---|
| A1 | drain_life | Drain Life | 568353 | sound/spells/shadowwordpain_chest.ogg | 1.2 | 166469 | spells/lifedrain_missile.m2 |  | W1-G2: now a variant of rejuvenation (the old canonical Drain Life picks, unchanged) |
| A2 | healthstone | Healthstone | 568859 | sound/spells/soulstoneresurrection_base.ogg |  | 166927 | spells/soulstoneresurrection_base.m2 |  | closest to a Healthstone; no create / use files |
| M1 | death_coil | Death Coil | 568670 | sound/spells/deathcoiltarget.ogg | | 165890 | spells/deathcoil_impact_chest.m2 | | exact |
| M2 | enslave_demon | Enslave Demon | 568125 | sound/spells/demoniccirclesummon.ogg | | 166039 | spells/enslavedemon_impact_base.m2 | | sound is a proxy (no enslave sound); alt 569150 demonicsummonteleport1 |
| E1 | shadow_ward | Shadow Ward | 569668 | sound/spells/shadowward.ogg | | 166830 | spells/shadowward_impact_chest.m2 | | exact; alt fx 166827 shadowshield_state_base |
| E2 | rain_of_fire | Rain of Fire | existing | | | existing | | | canonical |
| R1 | hellfire | Hellfire | 569016 | sound/spells/incinerate_impact_base.ogg | | 166297 | spells/hellfire_area_base.m2 | | no hellfire sound; fire impact proxy; alt 569153 immolate |
| R2 | fire_shield | Fire Shield (Imp) | existing | | | existing | | | canonical |
| S1 | howl_of_terror | Howl of Terror | 567950 | sound/spells/fear.ogg | | 166803 | spells/shadow_nova_area.m2 | | alt fx 166065 fear_impact_chest |
| S2 | inferno | Inferno | 569601 | sound/spells/infernalimpactbase.ogg | | 166414 | spells/infernal_impact_base.m2 | 166988 spells/stunswirl_state_head.m2 | alt fx 166413 infernal_impact |
| T1 | shadow_bolt | Shadow Bolt | 569471 | sound/spells/shadowstrike_impact_chest.ogg | | 166815 | spells/shadowbolt_missile.m2 | | no shadowbolt sound; alts 569148 shadowprecasthigh, 568751 illidanshadowblast1; alt fx 166814 shadowbolt_chest_impact |
| T2 | curse_of_agony | Curse of Agony | 569079 | sound/spells/curse.ogg | | 165852 | spells/curseofagony_head.m2 | | exact model; generic curse sound |

## Warrior
| slot | variant id | spell | sound id | sound path | max | fx m2 id | fx path | hold | note |
|---|---|---|---|---|---|---|---|---|---|
| A1 | bloodthirst | Bloodthirst | 568812 | sound/spells/bloodlust_player_cast_head.ogg | | 165726 | spells/bloodlust_player_cast_head.m2 | | no bloodthirst files; bloodlust is closest (name + red buff look) |
| A2 | last_stand | Last Stand | 568028 | sound/spells/battleshouttarget.ogg |  | 165658 | spells/battleshout_cast_base.m2 |  | W1-G2; buff shout as a proxy (no Last Stand files) |
| M1 | intercept | Intercept | 569628 | sound/spells/druid_feralcharge.ogg | | 166841 | spells/shieldbash_impact_chest.m2 | | charge sound is Druid Feral Charge (best charge-like); alt fx 165784 chargetrail (trail, not an impact) |
| M2 | challenging_shout | Challenging Shout | 569236 | sound/spells/challengingshout.ogg | | 165783 | spells/challengingshout_cast_base.m2 | | exact |
| E1 | shield_block | Shield Block | 569473 | sound/spells/shieldwalltarget.ogg | | 166843 | spells/shieldwallwar_impact_base.m2 | | no shieldblock files; alt fx 166842 shieldwall_impact_base |
| E2 | recklessness | Recklessness | 569491 | sound/spells/recklessnesstarget.ogg | | 166685 | spells/recklessness_impact_chest.m2 | | chest-sized model over the whole board (small); alt fx 165737 bloodyexplosion |
| R1 | cleave | Cleave | 568227 | sound/spells/cleavetarget.ogg | | 165796 | spells/cleave_cast_base.m2 | | same sound as Whirlwind (existing); alt 569059 strike; alt fx 165798 cleave_impact_chest |
| R2 | retaliation | Retaliation | 568646 | sound/spells/spell_heroicstrike_impact_01.ogg | | 166705 | spells/retaliation_state_chest.m2 | | sound is a proxy (post-vanilla filename, id < 570000); alt 569059 strike |
| S1 | thunder_clap | Thunder Clap | 569222 | sound/spells/thunderclap.ogg | | 167120 | spells/thunderclap_cast_base.m2 | | exact |
| S2 | concussion_blow | Concussion Blow | 569193 | sound/spells/warrior_shockwave_area.ogg | | 167170 | spells/warrior_shockwave_area.m2 | 166988 spells/stunswirl_state_head.m2 | Shockwave assets are post-vanilla (risk in Classic client); vanilla-safe alts: sound 569059 strike, fx 166890 slam_impact_chest / 166841 shieldbash_impact_chest |
| T1 | whirlwind | Whirlwind | existing | | | existing | | | canonical |
| T2 | sweeping_strikes | Sweeping Strikes | 569059 | sound/spells/strike.ogg | | 167003 | spells/sweepingstrike_impact_chest.m2 | | exact model; generic strike sound |



## Paladin
| slot | variant id | spell | sound id | sound path | max | fx m2 id | fx path | hold | note |
|---|---|---|---|---|---|---|---|---|---|
| A1 | seal_of_light | Seal of Light | 569017 | sound/spells/sealoflight_impact_base.ogg | | 166773 | spells/sealoflight_impact_base.m2 | | own spell, sound+model pair |
| A2 | lay_on_hands | Lay on Hands | 568145 | sound/spells/layonhands_low_chest.ogg |  | 166452 | spells/layonhands_low_chest.m2 |  | W1-G2: canonical Amber ult, own sound + model; alt 569343 layonhands_low_head / 166453 |
| M1 | hammer_of_justice | Hammer of Justice | existing (569110 kidneyshot) | | | existing | | | canonical |
| M2 | redemption | Redemption | 568667 | sound/spells/resurrection.ogg | | 166704 | spells/resurrection_low_base.m2 | | own spell; alt model 166927 soulstoneresurrection_base |
| E1 | blessing_of_protection | Blessing of Protection | 568491 | sound/spells/holyprotection.ogg | | 165703 | spells/blessingofprotection_state_classic.m2 | | alt model 165700 blessingofprotection_base |
| E2 | seal_of_command | Seal of Command | 568274 | sound/spells/sealofmight.ogg | | 166770 | spells/sealofcommand_impact_base.m2 | | sound is Seal of Might (no sealofcommand sound); alt 568337 sealofvengeance_impact_base |
| R1 | holy_wrath | Holy Wrath | 568618 | sound/spells/exorcism.ogg | | 166350 | spells/holynova_impact_base.m2 | | alt model 166049 exorcism_impact_chest (chest impact), 166574 missile_wave_holy (wave, untested shape) |
| R2 | retribution_aura | Retribution Aura | 568744 | sound/spells/retributionaura.ogg | | 166707 | spells/retributionaura_base.m2 | | own spell |
| S1 | consecration | Consecration | 569211 | sound/spells/holy_impactdd_uber_base.ogg | | 165818 | spells/consecration_impact_base.m2 | | no consecration sound; generic holy uber impact |
| S2 | repentance | Repentance | 569770 | sound/spells/directdamage/holyimpactdduber.ogg | | 166328 | spells/holy_impactdd_uber_base.m2 | 166988 spells/stunswirl_state_head.m2 | no own sound; alt 569402 holybolt |
| T1 | hammer_of_wrath | Hammer of Wrath | 569272 | sound/spells/hammeroftherighteousimpact.ogg | | 166323 | spells/holy_hammer_missile.m2 | | alt model 166567 missile_hammer |
| T2 | judgement | Judgement | 568781 | sound/spells/judgmentsofthewiseimpact.ogg | | 166435 | spells/judgement_impact_chest.m2 | | alt sound 568169 judgementofthepure |

## Shaman
| slot | variant id | spell | sound id | sound path | max | fx m2 id | fx path | hold | note |
|---|---|---|---|---|---|---|---|---|---|
| A1 | healing_stream_totem | Healing Stream Totem | 568572 | sound/spells/spell_sh_greaterhealingwave_impact_01.ogg | | 166244 | spells/giftwaterspirit_impact_base.m2 | | no totem files; alt sound 569570 heal_low_base, alt model 166292 heal_low_base |
| A2 | chain_heal | Chain Heal | 569419 | sound/spells/flashheal_low_base.ogg |  | 166292 | spells/heal_low_base.m2 |  | W1-G2; no chain heal files in the vanilla set (the spell_sh_resto_chainheal_* files are post-vanilla): closest heal |
| M1 | earth_shock | Earth Shock | 568161 | sound/spells/spell_sh_unleashedearth_impact_01.ogg | | 165987 | spells/earthshock_impact_chest.m2 | | alt sound 569545 rockbiterimpact |
| M2 | purge | Purge | 568736 | sound/spells/purge.ogg | | 166547 | spells/mass_dispell_impact.m2 | | alt model 166665 purge_impact_chest (small), 165955 dispel_low_base |
| E1 | lightning_shield | Lightning Shield | 569084 | sound/spells/lightningshieldimpact.ogg | | 166500 | spells/lightningshield_state_base.m2 | | own spell |
| E2 | fire_nova_totem | Fire Nova Totem | 569062 | sound/spells/firenova.ogg | | 166144 | spells/firenova_area.m2 | | own spell |
| R1 | flame_shock | Flame Shock | 569427 | sound/spells/spell_sh_unleashflame_impact_01.ogg | | 166186 | spells/flameshock_impact_chest.m2 | | own model but chest impact, not cone-shaped; alt 165812 coneoffire_hand, 166176 flamebreath |
| R2 | grounding_totem | Grounding Totem | 568951 | sound/spells/spellreflection_state_shield.ogg | | 166286 | spells/groundingtotem_impact.m2 | | spell-reflect sound fits (grounding redirects spells); alt model 166940 spellreflection_state_shield |
| S1 | earthbind_totem | Earthbind Totem | 568460 | sound/spells/spell_sh_unleashedearth_impact_04.ogg | | 166052 | spells/exploding_stone_impact.m2 | | no totem files; generic earth |
| S2 | frost_shock | Frost Shock | 568421 | sound/spells/spell_sh_unleashfrost_impact_01.ogg | | 166371 | spells/ice_impactdd_uber_chest.m2 | 166211 spells/frost_nova_state.m2 | alt model 166394 icespike_impact_base |
| T1 | lightning_bolt | Lightning Bolt | 568188 | sound/spells/spell_lightningbolt_impact_02.ogg | | 166497 | spells/lightningbolt_missile.m2 | | alt sound 568529 spell_lightningbolt_impact_04; alt model 166496 lightningbolt_impact_chest |
| T2 | chain_lightning | Chain Lightning | existing (568516 lightningboltimpact) | | | existing | | | canonical |

## Hunter
| slot | variant id | spell | sound id | sound path | max | fx m2 id | fx path | hold | note |
|---|---|---|---|---|---|---|---|---|---|
| A1 | mend_pet | Mend Pet | 569570 | sound/spells/heal_low_base.ogg | | 166292 | spells/heal_low_base.m2 | | nature heal; no own files. alt sound 568719 beastsoothe |
| A2 | revive_pet | Revive Pet | 568719 | sound/spells/beastsoothe.ogg |  | 166709 | spells/revivepet_impact_base.m2 |  | W1-G2; own model, sound is Beast Soothe (no revive pet sound) |
| M1 | scatter_shot | Scatter Shot | 568411 | sound/spells/concussiveshotimpact.ogg | | 165713 | spells/blindingshot_impact.m2 | | alt model 167118 throatshot_impact_chest |
| M2 | tame_beast | Tame Beast | 569579 | sound/spells/beasttaming.ogg | | 165669 | spells/beastlore_impact_base.m2 | | alt model 165668 beastcall_impact_head |
| E1 | feign_death | Feign Death | 568087 | sound/spells/aspectofthebeast.ogg | | inherit | | | no feign-death files; sound is a loose hunter-buff fit, model left to the template (alt shield-like 166982 stoneform_state_base) |
| E2 | explosive_trap | Explosive Trap | 569082 | sound/spells/hunter_explosiveshotimpact1.ogg | | 166054 | spells/explosivetrap_recursive.m2 | | own model; alt sound 568733 firebombimpact1 (used by Rain of Fire) |
| R1 | multi_shot | Multi-Shot | 568665 | sound/spells/spell_hu_cobrashot_impact_02.ogg | | 166597 | spells/multishot_impact.m2 | | alt model 166598 multishot_missile |
| R2 | deterrence | Deterrence | 568326 | sound/spells/resistanceaura.ogg | | 165947 | spells/deterrence_state_base.m2 | | sound is a generic buff, weak; alt 568300 spiritarmorimpact |
| S1 | frost_trap | Frost Trap | 568571 | sound/spells/spell_ma_curtainfrost_impact_01.ogg | | 166219 | spells/frosttrap_aura.m2 | | alt model 166220 frosttrap_aura_nomist; alt sound 568119 precastfrostmagiclow |
| S2 | freezing_trap | Freezing Trap | 569104 | sound/spells/sindragosa_xplosion_frost_impact_01.ogg | | 166394 | spells/icespike_impact_base.m2 | 166211 spells/frost_nova_state.m2 | sound is a large frost impact, may be loud; alt 569310 frostnovastateend; alt hold 166391 iceprison_base |
| T1 | aimed_shot | Aimed Shot | 568867 | sound/spells/hunter_chimerashotimpact1.ogg | | 166598 | spells/multishot_missile.m2 | | missile of a different shot; alt model 166217 frostshot_missile / 166158 fireshot_missile (wrong school) |
| T2 | volley | Volley | 568085 | sound/spells/hunter_chimerashotmissile.ogg | | 165559 | spells/aimedshot_impact_chest.m2 | | enemy-chest impact; alt model 166597 multishot_impact |


## Rogue
| slot | variant id | spell | sound id | sound path | max | fx m2 id | fx path | hold | note |
|---|---|---|---|---|---|---|---|---|---|
| A1 | first_aid | First Aid | 568907 | sound/spells/firstaid.ogg |  | 166204 | spells/food_healeffect_base.m2 |  | W1-G2; own sound, food heal model as the closest |
| A2 | healing_potion | Healing Potion | 569419 | sound/spells/flashheal_low_base.ogg |  | 166292 | spells/heal_low_base.m2 |  | W1-G2; closest heal files (the potionX_spellobject models are bottle objects, not an effect) |
| M1 | cheap_shot | Cheap Shot | 567960 | sound/spells/knockdown.ogg | | 165786 | spells/cheapshot_impact_chest.m2 | | alt sound 569596 rogue_deviousimpact |
| M2 | blind | Blind | 568533 | sound/spells/shadowwordbefuddle_headdru.ogg | | 165713 | spells/blindingshot_impact.m2 | | WEAK: no blind sound; befuddle = confusion. alt sound 568774 sleepimpact; alt fx 166803 shadow_nova_area |
| E1 | evasion | Evasion | 568798 | sound/spells/vanish.ogg | | 166827 | spells/shadowshield_state_base.m2 | | alt fx 166823 shadowprotection_chest, 166952 sprint_impact_chest |
| E2 | ambush | Ambush | 569555 | sound/spells/backstab_impact_chest.ogg | | 165645 | spells/backstab_cast_base.m2 | | cast_base used as board-area base effect; alt 166821 shadowfury_impact_base |
| R1 | eviscerate | Eviscerate | 569637 | sound/spells/evisceratetarget.ogg | | 166048 | spells/eviscerate_impact_chest.m2 | | chest model, not a cone; alt 166047 eviscerate_cast_hands |
| R2 | riposte | Riposte | 569740 | sound/spells/rogue_dismantle.ogg | | 166824 | spells/shadowreflect_state_chest.m2 | | Riposte disarms; no riposte sound. alt fx 166940 spellreflection_state_shield (already Mirror) |
| S1 | gouge | Gouge | 568415 | sound/spells/gougetarget.ogg | | 166878 | spells/sinisterstrike_impact_chest.m2 | | alt fx 166255 gouge_precast_state_hand (hand effect, likely too small) |
| S2 | kidney_shot | Kidney Shot | 569110 | sound/spells/kidneyshot.ogg | | 166438 | spells/kidneyshot_base_cast.m2 | 166988 spells/stunswirl_state_head.m2 | sound identical to Paladin ab_hammer_of_justice |
| T1 | blade_flurry | Blade Flurry | 568202 | sound/spells/warrior_bladestorm.ogg | 1.2 | 166893 | spells/slicedice_impact_chest.m2 | | name suggests a loop/long: keep max 1.2. alt sound 568003 rendtarget (short) |
| T2 | adrenaline_rush | Adrenaline Rush | 568812 | sound/spells/bloodlust_player_cast_head.ogg | | 165554 | spells/adrenalinerush_cast_base.m2 | | cast_base on enemy anchor is odd; alt 166893 slicedice_impact_chest |

## Priest
| slot | variant id | spell | sound id | sound path | max | fx m2 id | fx path | hold | note |
|---|---|---|---|---|---|---|---|---|---|
| A1 | renew | Renew | 569376 | sound/spells/renew.ogg |  | 166696 | spells/renew_base.m2 |  | W1-G2; own sound + model |
| A2 | greater_heal | Greater Heal | 568017 | sound/spells/greaterheal_low_base.ogg |  | 166273 | spells/greaterheal_low_base.m2 |  | W1-G2; own sound + model |
| M1 | psychic_scream | Psychic Scream | 567950 | sound/spells/fear.ogg | | 166065 | spells/fear_impact_chest.m2 | | |
| M2 | mind_control | Mind Control | existing | | | existing | | | canonical |
| E1 | power_word_shield | Power Word: Shield | existing | | | existing | | | canonical |
| E2 | shadow_word_pain | Shadow Word: Pain | 569138 | sound/spells/shadowwordpaintarget.ogg | | 166804 | spells/shadow_nova_area_noprojection.m2 | | alt 166835 shadowwordpain_chest (single target, not area) |
| R1 | holy_fire | Holy Fire | 568618 | sound/spells/exorcism.ogg | | 166328 | spells/holy_impactdd_uber_base.m2 | | no holy fire files; alt fx 166049 exorcism_impact_chest, 166354 holysmite_low_chest |
| R2 | inner_fire | Inner Fire | 568343 | sound/spells/innerfire.ogg | | 166417 | spells/innerfire_base.m2 | | |
| S1 | holy_nova | Holy Nova | 569211 | sound/spells/holy_impactdd_uber_base.ogg | | 166350 | spells/holynova_impact_base.m2 | | no holynova sound; generic holy impact |
| S2 | silence | Silence | 568399 | sound/spells/shadowwordsilence.ogg | | 166821 | spells/shadowfury_impact_base.m2 | 166832 spells/shadowwordbefuddle_head.m2 | WEAK hold: no silence state; alt hold 166891 sleep_state_head or 166988 stunswirl_state_head; alt fx 166836 shadowwordsilence_breath |
| T1 | mind_flay | Mind Flay | 568446 | sound/spells/spell_pr_mindspike_impact_01.ogg | | 166576 | spells/missile_wave_shadow.m2 | | no mindflay files; alt sound 569529 priest_mindshear1, alt fx 166558 mindblast_head |
| T2 | dispel_magic | Dispel Magic | 568392 | sound/spells/dispel_low_base.ogg | | 165955 | spells/dispel_low_base.m2 | | |

## Druid
| slot | variant id | spell | sound id | sound path | max | fx m2 id | fx path | hold | note |
|---|---|---|---|---|---|---|---|---|---|
| A1 | rejuvenation | Rejuvenation | 569594 | sound/spells/rejuvenation.ogg |  | 166694 | spells/rejuvenation_impact_base.m2 |  | W1-G2: canonical Amber skill (player, 240 px, 1.2 s) |
| A2 | healing_touch | Healing Touch | 569570 | sound/spells/heal_low_base.ogg |  | 166292 | spells/heal_low_base.m2 |  | W1-G2; the druid healingtouch_impact files (1687864..6) are post-vanilla, so the nature heal base sound is used |
| M1 | bash | Bash | 569437 | sound/spells/spell_dr_maul_impact_01.ogg | | 166551 | spells/maulimpact.m2 | | alt sound 568288 savageblowtarget; alt fx 166841 shieldbash_impact_chest |
| M2 | faerie_fire | Faerie Fire | 569254 | sound/spells/faeriefire.ogg | | 166061 | spells/faeriefire_impact.m2 | | |
| E1 | barkskin | Barkskin | 568015 | sound/spells/natureresistance.ogg | | 165655 | spells/barkskin_state_base.m2 | | WEAK sound: no barkskin sound. alt 569022 thorns |
| E2 | insect_swarm | Insect Swarm | 568681 | sound/spells/insectswarm_state_chest.ogg | | 166241 | spells/giantinsectswarm_state_ground.m2 | | sound is a state sound (may loop): check, else max 1.2; alt fx 166421 insectswarm_state_chest |
| R1 | swipe | Swipe | 568403 | sound/spells/swipetarget.ogg | | 167005 | spells/swipeimpact.m2 | | alt sound 568398 swipe |
| R2 | thorns | Thorns | 569022 | sound/spells/thorns.ogg | | 167115 | spells/thorns_state_base.m2 | | |
| S1 | hurricane | Hurricane | 568519 | sound/spells/whirlwindshort.ogg | | 165862 | spells/cyclone_state.m2 | | no hurricane files; alt fx 167199 whirlwind_state_base (already Warrior whirlwind) |
| S2 | entangling_roots | Entangling Roots | 568636 | sound/spells/entanglingroots.ogg | | 166042 | spells/entanglingroots_state.m2 | 166042 spells/entanglingroots_state.m2 | one-shot and hold use the same model (no other roots model found) |
| T1 | wrath | Wrath | 568563 | sound/spells/druid_wrath_impact01.ogg | | 167213 | spells/wrath_missile.m2 | | alt fx 167212 wrath_impact_chest; alt sound 569204 druid_wrath_missile |
| T2 | starfire | Starfire | 568008 | sound/spells/starfireimpact.ogg | | 166980 | spells/starshards_impact_base.m2 | | alt fx 166973 starfire_area |

