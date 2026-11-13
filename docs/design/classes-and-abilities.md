# Classes and abilities — effect templates + spell variants

Status: implemented in core (W1-G1 part A, 2026-11-11): 9 classes x 12 spells, `core/classes.lua`; spec
[../specs/w1-g1-class-kits.md](../specs/w1-g1-class-kits.md); decisions: [../DECISIONS.md](../DECISIONS.md).
Current numbers/behaviour of the 12 effects: [abilities.md](abilities.md) (Godot values, ported to Lua).

## Model

- **Effect template** = what the ability does on the board/fight (the 12 existing effects: 6 gem colours × skill/ult).
- **Spell variant** = a WoW spell name + icon + sound + visual effect + banner text for a template
  (`core/classes.lua` `variant(template_id, id, name, overrides)`: a shallow copy of the template with its own `id`,
  `template`, `name`, `icon` (= id), `description`, `blurb`). Numbers and `execute` are the template's, by
  construction: **a variant is a skin, never a rule change.** `class_test` proves it (field whitelist with `rawequal`
  + a scripted fight with all 12 slots forced, identical for every class kit and the default kit).
- **Class kit** = per colour one skill + one ult, so **12 spells per class**, for all **9 Classic classes**
  (`ns.Classes`, keys = WoW class tokens; `Kit.for_class(token)`, unknown / nil gives the default kit).
- The 12 canonical definitions (ability id = template id) are the variant of the class that owns the spell and stay
  the default kit (tests, golden files). 108 spells in total: 12 canonical + 96 variants; variant id = snake_case of
  the spell name.
- Icon = the spell's real Classic icon (`ui/assets.lua` `ICONS[id]`); sound and effect per variant inherit from the
  template and are overridden per variant ([class-kit-assets.md](class-kit-assets.md)); M1 / S2 carry `status_text`
  and `hold_fx` in `FX` (what the enemy status reads and which held effect shows).
- Class twists (1-2 rule changes per class so classes also play differently, pillar 4) are a follow-up (W1-G2).

## Canonical names (renamed 2026-10-04; ids in code since W0-G2c)

| Colour | Skill (id → canonical WoW spell) | Ult (id → canonical WoW spell) |
|---|---|---|
| Ruby | `fire_wave` → **Flamestrike** | `fire_shield` → **Fire Shield** |
| Sapphire | `area_clear` → **Arcane Explosion** | `freeze` → **Frost Nova** |
| Topaz | `row_clear` → **Whirlwind** | `color_chain` → **Chain Lightning** |
| Amber | `lifesteal` → `drain_life` → **Rejuvenation** (W1-G2: a HoT) | `convert` → `polymorph` → **Lay on Hands** (W1-G2: a heal) |
| Amethyst | `stun` → **Hammer of Justice** | `color_swap` → **Mind Control** |
| Emerald | `shield` → **Power Word: Shield** | `bombs` → **Rain of Fire** |

User-fixed: Freeze = Frost Nova, Area Clear = Arcane Explosion. The other ten are the director's proposal (user may
rename). Sound/effect candidates per canonical spell are in [audio.md](audio.md) and spec W0-P3.

## The 9 x 12 table (bold = the canonical definition)

Fit rule: the spell's real effect resembles the slot's effect; where a class has nothing close, the nearest fantasy
wins. Thunder Clap / Hurricane really slow attacks (S1 delay); Retaliation / Riposte / Thorns / Retribution Aura really
hit attackers back (R2); the Amber slots are heals since W1-G2 (A1 a 10 s HoT: Rejuvenation, Renew, Mend Pet ...; A2 a 15 % heal: Lay on Hands, Healing Touch, Healthstone ...); Shield Block / Lightning
Shield have charges (E1); Fire Nova Totem / Explosive Trap are armed objects that blow up (E2). Icon file names per
spell: spec W1-G1 section 2 (and `ui/assets.lua`).

| Slot | Template (effect) | Warrior | Paladin | Hunter | Rogue | Priest | Shaman | Mage | Warlock | Druid |
|---|---|---|---|---|---|---|---|---|---|---|
| A1 | `rejuvenation` — Amber skill, heal over time (5 % of max HP over 10 s) | Bloodthirst | Seal of Light | Mend Pet | First Aid | Renew | Healing Stream Totem | Conjure Food | Drain Life | **Rejuvenation** |
| A2 | `lay_on_hands` — Amber ult, instant heal (15 % of max HP) | Last Stand | **Lay on Hands** | Revive Pet | Healing Potion | Greater Heal | Chain Heal | Evocation | Healthstone | Healing Touch |
| M1 | `hammer_of_justice` — Amethyst skill, 200 dmg + stun 3 s | Intercept | **Hammer of Justice** | Scatter Shot | Cheap Shot | Psychic Scream | Earth Shock | Counterspell | Death Coil | Bash |
| M2 | `mind_control` — Amethyst ult, one colour becomes Amethyst | Challenging Shout | Redemption | Tame Beast | Blind | **Mind Control** | Purge | Polymorph | Enslave Demon | Faerie Fire |
| E1 | `power_word_shield` — Emerald skill, block the next hit (stacks) | Shield Block | Blessing of Protection | Feign Death | Evasion | **Power Word: Shield** | Lightning Shield | Ice Barrier | Shadow Ward | Barkskin |
| E2 | `rain_of_fire` — Emerald ult, 5 gems become bombs | Recklessness | Seal of Command | Explosive Trap | Ambush | Shadow Word: Pain | Fire Nova Totem | Blast Wave | **Rain of Fire** | Insect Swarm |
| R1 | `flamestrike` — Ruby skill, 150 dmg + cone clear | Cleave | Holy Wrath | Multi-Shot | Eviscerate | Holy Fire | Flame Shock | **Flamestrike** | Hellfire | Swipe |
| R2 | `fire_shield` — Ruby ult, 12 s nullify + reflect (+100 per hit) | Retaliation | Retribution Aura | Deterrence | Riposte | Inner Fire | Grounding Totem | Fire Ward | **Fire Shield**** | Thorns |
| S1 | `arcane_explosion` — Sapphire skill, 150 dmg + 3x3 clear + delay | Thunder Clap | Consecration | Frost Trap | Gouge | Holy Nova | Earthbind Totem | **Arcane Explosion** | Howl of Terror | Hurricane |
| S2 | `frost_nova` — Sapphire ult, 500 dmg + enemy status 5 s | Concussion Blow | Repentance | Freezing Trap | Kidney Shot | Silence | Frost Shock | **Frost Nova** | Inferno | Entangling Roots |
| T1 | `whirlwind` — Topaz skill, 150 dmg + row clear | **Whirlwind** | Hammer of Wrath | Aimed Shot | Blade Flurry | Mind Flay | Lightning Bolt | Arcane Missiles | Shadow Bolt | Wrath |
| T2 | `chain_lightning` — Topaz ult, chain-clear the partner colour | Sweeping Strikes | Judgement | Volley | Adrenaline Rush | Dispel Magic | **Chain Lightning** | Blizzard | Curse of Agony | Starfire |

Notes: the S2 status label / held effect follows the spell (FROZEN + ice block for Frost Nova / Frost Shock / Freezing
Trap, SILENCED for Silence, ROOTED + roots for Entangling Roots, STUNNED + stun swirl for the rest; the core status
kind stays `freeze` / `stun`). Same icon on two classes is fine (real icon); within a class all 12 are distinct.
