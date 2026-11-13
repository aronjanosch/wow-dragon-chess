local _, ns = ...
-- Class kits (W1-G1): 9 classes x 12 spells. Every spell is a variant of one of the 12 effect templates
-- (core/abilities/*.lua): a shallow copy with its own id / name / icon / text. Numbers and `execute`
-- stay the template's, so a class changes the fantasy, never the balance (test/class_test.lua proves it).
-- Presentation (icon file, sound, effect) is keyed by the variant id in ui/assets.lua.
-- Slots: A1 Amber skill, A2 Amber ult, M1 / M2 Amethyst, E1 / E2 Emerald, R1 / R2 Ruby, S1 / S2 Sapphire,
-- T1 / T2 Topaz. Canonical definitions (the template ids) are the variant of the class that owns the spell.
local A = ns.Abilities or {}
ns.Abilities = A

local pairs, error = pairs, error

local Classes = {}

-- Registers ns.Abilities[id] = copy of template `template_id` + id / template / name / icon (= id) and the
-- optional text overrides { description = ..., blurb = ... }.
local function variant(template_id, id, name, overrides)
	local tpl = A[template_id]
	if tpl == nil then error("classes: unknown template " .. template_id) end
	if A[id] ~= nil then error("classes: duplicate ability id " .. id) end
	local v = {}
	for k, val in pairs(tpl) do v[k] = val end -- field copy; order irrelevant
	v.id, v.template, v.name, v.icon = id, template_id, name, id
	if overrides ~= nil then
		for k, val in pairs(overrides) do v[k] = val end
	end
	A[id] = v
end

-- Description texts for templates whose own text names a different effect.
local DESC_CONE = "{damage} dmg, cone from gem toward enemy"
local DESC_REFLECT = "Nullifies enemy attacks and reflects the damage +{reflect_bonus} back for {fire_shield_duration}s"
local DESC_CHAIN = "Clear all gems of the partner color in a chain"
local DESC_STUN = "{damage} dmg, stun the enemy for {stun_duration}s"
local DESC_SILENCE = "{damage} dmg, silence the enemy for {stun_duration}s"
local DESC_ROOT = "{damage} dmg, root the enemy for {stun_duration}s"


-- A1 Amber skill: heal over time (canonical: rejuvenation, core/abilities/amber.lua)
variant("rejuvenation", "renew", "Renew", { blurb = "Renew {hot_total} over {hot_seconds}s" })
variant("rejuvenation", "seal_of_light", "Seal of Light", { blurb = "Light heals {hot_total} over {hot_seconds}s" })
variant("rejuvenation", "healing_stream_totem", "Healing Stream Totem", { blurb = "Stream heals {hot_total} over {hot_seconds}s" })
variant("rejuvenation", "conjure_food", "Conjure Food", { blurb = "Eat: heal {hot_total} over {hot_seconds}s" })
variant("rejuvenation", "drain_life", "Drain Life", { blurb = "Drain {hot_total} over {hot_seconds}s" })
variant("rejuvenation", "bloodthirst", "Bloodthirst", { blurb = "Thirst heals {hot_total} over {hot_seconds}s" })
variant("rejuvenation", "mend_pet", "Mend Pet", { blurb = "Mend {hot_total} over {hot_seconds}s" })
variant("rejuvenation", "first_aid", "First Aid", { blurb = "Bandage {hot_total} over {hot_seconds}s" })

-- A2 Amber ult: instant heal (canonical: lay_on_hands)
variant("lay_on_hands", "healing_touch", "Healing Touch", { blurb = "Touch heals {heal_total} health" })
variant("lay_on_hands", "greater_heal", "Greater Heal", { blurb = "Heal {heal_total} health" })
variant("lay_on_hands", "chain_heal", "Chain Heal", { blurb = "Chain heals {heal_total} health" })
variant("lay_on_hands", "evocation", "Evocation", { blurb = "Evoke: restore {heal_total} health" })
variant("lay_on_hands", "healthstone", "Healthstone", { blurb = "Stone heals {heal_total} health" })
variant("lay_on_hands", "last_stand", "Last Stand", { blurb = "Stand: heal {heal_total} health" })
variant("lay_on_hands", "revive_pet", "Revive Pet", { blurb = "Revive: heal {heal_total} health" })
variant("lay_on_hands", "healing_potion", "Healing Potion", { blurb = "Potion heals {heal_total} health" })

-- M1 Amethyst skill: damage + stun
variant("hammer_of_justice", "intercept", "Intercept", { blurb = "Charge · damage · stun enemy" })
variant("hammer_of_justice", "scatter_shot", "Scatter Shot", { blurb = "Damage · daze enemy" })
variant("hammer_of_justice", "cheap_shot", "Cheap Shot", { blurb = "Damage · stun enemy" })
variant("hammer_of_justice", "psychic_scream", "Psychic Scream", { blurb = "Damage · terrify enemy" })
variant("hammer_of_justice", "earth_shock", "Earth Shock", { blurb = "Damage · interrupt enemy" })
variant("hammer_of_justice", "counterspell", "Counterspell", { blurb = "Damage · interrupt enemy" })
variant("hammer_of_justice", "death_coil", "Death Coil", { blurb = "Damage · horrify enemy" })
variant("hammer_of_justice", "bash", "Bash", { blurb = "Damage · bash enemy" })

-- M2 Amethyst ult: convert one colour to Amethyst
variant("mind_control", "challenging_shout", "Challenging Shout", { blurb = "Taunt partner color → Amethyst" })
variant("mind_control", "redemption", "Redemption", { blurb = "Redeem partner color → Amethyst" })
variant("mind_control", "tame_beast", "Tame Beast", { blurb = "Tame partner color → Amethyst" })
variant("mind_control", "blind", "Blind", { blurb = "Blind partner color → Amethyst" })
variant("mind_control", "purge", "Purge", { blurb = "Purge partner color → Amethyst" })
variant("mind_control", "polymorph", "Polymorph", { blurb = "Hex partner color → Amethyst" })
variant("mind_control", "enslave_demon", "Enslave Demon", { blurb = "Enslave partner color → Amethyst" })
variant("mind_control", "faerie_fire", "Faerie Fire", { blurb = "Mark partner color → Amethyst" })

-- E1 Emerald skill: block the next hit
variant("power_word_shield", "shield_block", "Shield Block", { blurb = "Block next enemy hit · stacks" })
variant("power_word_shield", "blessing_of_protection", "Blessing of Protection", { blurb = "Block next enemy hit · stacks" })
variant("power_word_shield", "feign_death", "Feign Death", { blurb = "Feign: next hit misses · stacks" })
variant("power_word_shield", "evasion", "Evasion", { blurb = "Dodge next enemy hit · stacks" })
variant("power_word_shield", "lightning_shield", "Lightning Shield", { blurb = "Charge blocks next hit · stacks" })
variant("power_word_shield", "ice_barrier", "Ice Barrier", { blurb = "Barrier blocks next hit · stacks" })
variant("power_word_shield", "shadow_ward", "Shadow Ward", { blurb = "Ward blocks next hit · stacks" })
variant("power_word_shield", "barkskin", "Barkskin", { blurb = "Block next enemy hit · stacks" })

-- E2 Emerald ult: gems become bombs
variant("rain_of_fire", "recklessness", "Recklessness", { blurb = "Spawn {bomb_count} bombs" })
variant("rain_of_fire", "seal_of_command", "Seal of Command", { blurb = "Spawn {bomb_count} bombs" })
variant("rain_of_fire", "explosive_trap", "Explosive Trap", { blurb = "Arm {bomb_count} trap bombs" })
variant("rain_of_fire", "ambush", "Ambush", { blurb = "Spawn {bomb_count} bombs" })
variant("rain_of_fire", "shadow_word_pain", "Shadow Word: Pain", { blurb = "Spawn {bomb_count} bombs" })
variant("rain_of_fire", "fire_nova_totem", "Fire Nova Totem", { blurb = "Plant {bomb_count} bombs" })
variant("rain_of_fire", "blast_wave", "Blast Wave", { blurb = "Spawn {bomb_count} bombs" })
variant("rain_of_fire", "insect_swarm", "Insect Swarm", { blurb = "Swarm {bomb_count} bombs" })

-- R1 Ruby skill: damage + cone clear
variant("flamestrike", "cleave", "Cleave", { description = DESC_CONE, blurb = "Cleave a cone toward the enemy" })
variant("flamestrike", "holy_wrath", "Holy Wrath", { description = DESC_CONE, blurb = "Cone-clear toward the enemy" })
variant("flamestrike", "multi_shot", "Multi-Shot", { description = DESC_CONE, blurb = "Shots clear a cone to the enemy" })
variant("flamestrike", "eviscerate", "Eviscerate", { description = DESC_CONE, blurb = "Cone-clear toward the enemy" })
variant("flamestrike", "holy_fire", "Holy Fire", { description = DESC_CONE, blurb = "Cone-clear toward the enemy" })
variant("flamestrike", "flame_shock", "Flame Shock", { description = DESC_CONE, blurb = "Cone-clear toward the enemy" })
variant("flamestrike", "hellfire", "Hellfire", { description = DESC_CONE, blurb = "Cone-clear toward the enemy" })
variant("flamestrike", "swipe", "Swipe", { description = DESC_CONE, blurb = "Swipe a cone toward the enemy" })

-- R2 Ruby ult: nullify + reflect
variant("fire_shield", "retaliation", "Retaliation", { description = DESC_REFLECT, blurb = "Strike back at attacks — {fire_shield_duration}s" })
variant("fire_shield", "retribution_aura", "Retribution Aura", { description = DESC_REFLECT, blurb = "Strike back at attacks — {fire_shield_duration}s" })
variant("fire_shield", "deterrence", "Deterrence", { description = DESC_REFLECT, blurb = "Deflect attacks back — {fire_shield_duration}s" })
variant("fire_shield", "riposte", "Riposte", { description = DESC_REFLECT, blurb = "Riposte attacks — {fire_shield_duration}s" })
variant("fire_shield", "inner_fire", "Inner Fire", { description = DESC_REFLECT, blurb = "Reflect attacks — {fire_shield_duration}s" })
variant("fire_shield", "grounding_totem", "Grounding Totem", { description = DESC_REFLECT, blurb = "Ground attacks back — {fire_shield_duration}s" })
variant("fire_shield", "fire_ward", "Fire Ward", { description = DESC_REFLECT, blurb = "Reflect attacks — {fire_shield_duration}s" })
variant("fire_shield", "thorns", "Thorns", { description = DESC_REFLECT, blurb = "Thorns hit back — {fire_shield_duration}s" })

-- S1 Sapphire skill: damage + 3x3 clear + delay
variant("arcane_explosion", "thunder_clap", "Thunder Clap", { blurb = "Slow attack · clear {clear_size}x{clear_size}" })
variant("arcane_explosion", "consecration", "Consecration", { blurb = "Clear {clear_size}x{clear_size} · delay attack" })
variant("arcane_explosion", "frost_trap", "Frost Trap", { blurb = "Clear {clear_size}x{clear_size} · delay attack" })
variant("arcane_explosion", "gouge", "Gouge", { blurb = "Clear {clear_size}x{clear_size} · delay attack" })
variant("arcane_explosion", "holy_nova", "Holy Nova", { blurb = "Clear {clear_size}x{clear_size} · delay attack" })
variant("arcane_explosion", "earthbind_totem", "Earthbind Totem", { blurb = "Clear {clear_size}x{clear_size} · delay attack" })
variant("arcane_explosion", "howl_of_terror", "Howl of Terror", { blurb = "Clear {clear_size}x{clear_size} · delay attack" })
variant("arcane_explosion", "hurricane", "Hurricane", { blurb = "Clear {clear_size}x{clear_size} · delay attack" })

-- S2 Sapphire ult: heavy damage + enemy status
variant("frost_nova", "concussion_blow", "Concussion Blow", { description = DESC_STUN, blurb = "Heavy damage · stun enemy" })
variant("frost_nova", "repentance", "Repentance", { description = DESC_STUN, blurb = "Heavy damage · stun enemy" })
variant("frost_nova", "freezing_trap", "Freezing Trap", { blurb = "Heavy damage · freeze enemy" })
variant("frost_nova", "kidney_shot", "Kidney Shot", { description = DESC_STUN, blurb = "Heavy damage · stun enemy" })
variant("frost_nova", "silence", "Silence", { description = DESC_SILENCE, blurb = "Heavy damage · silence enemy" })
variant("frost_nova", "frost_shock", "Frost Shock", { blurb = "Heavy damage · freeze enemy" })
variant("frost_nova", "inferno", "Inferno", { description = DESC_STUN, blurb = "Heavy damage · stun enemy" })
variant("frost_nova", "entangling_roots", "Entangling Roots", { description = DESC_ROOT, blurb = "Heavy damage · root enemy" })

-- T1 Topaz skill: damage + row clear
variant("whirlwind", "hammer_of_wrath", "Hammer of Wrath", { blurb = "Clear entire row" })
variant("whirlwind", "aimed_shot", "Aimed Shot", { blurb = "Clear entire row" })
variant("whirlwind", "blade_flurry", "Blade Flurry", { blurb = "Clear entire row" })
variant("whirlwind", "mind_flay", "Mind Flay", { blurb = "Clear entire row" })
variant("whirlwind", "lightning_bolt", "Lightning Bolt", { blurb = "Clear entire row" })
variant("whirlwind", "arcane_missiles", "Arcane Missiles", { blurb = "Missiles clear the row" })
variant("whirlwind", "shadow_bolt", "Shadow Bolt", { blurb = "Clear entire row" })
variant("whirlwind", "wrath", "Wrath", { blurb = "Clear entire row" })

-- T2 Topaz ult: chain-clear the partner colour
variant("chain_lightning", "sweeping_strikes", "Sweeping Strikes", { description = DESC_CHAIN, blurb = "Chain-clear partner color" })
variant("chain_lightning", "judgement", "Judgement", { description = DESC_CHAIN, blurb = "Chain-clear partner color" })
variant("chain_lightning", "volley", "Volley", { description = DESC_CHAIN, blurb = "Chain-clear partner color" })
variant("chain_lightning", "adrenaline_rush", "Adrenaline Rush", { description = DESC_CHAIN, blurb = "Chain-clear partner color" })
variant("chain_lightning", "dispel_magic", "Dispel Magic", { description = DESC_CHAIN, blurb = "Chain-clear partner color" })
variant("chain_lightning", "blizzard", "Blizzard", { description = DESC_CHAIN, blurb = "Chain-clear partner color" })
variant("chain_lightning", "curse_of_agony", "Curse of Agony", { description = DESC_CHAIN, blurb = "Chain-clear partner color" })
variant("chain_lightning", "starfire", "Starfire", { description = DESC_CHAIN, blurb = "Chain-clear partner color" })

---------------------------------------------------------------- classes

-- Keys = WoW class tokens (UnitClass 2nd return). kit[colour] = { skill id, ult id }, colours 0..5
-- (Amber, Amethyst, Emerald, Ruby, Sapphire, Topaz; core/kit.lua).
Classes.ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

Classes.WARRIOR = {
	id = "WARRIOR", name = "Warrior",
	kit = {
		[0] = { "bloodthirst", "last_stand" },
		[1] = { "intercept", "challenging_shout" },
		[2] = { "shield_block", "recklessness" },
		[3] = { "cleave", "retaliation" },
		[4] = { "thunder_clap", "concussion_blow" },
		[5] = { "whirlwind", "sweeping_strikes" },
	},
}
Classes.PALADIN = {
	id = "PALADIN", name = "Paladin",
	kit = {
		[0] = { "seal_of_light", "lay_on_hands" },
		[1] = { "hammer_of_justice", "redemption" },
		[2] = { "blessing_of_protection", "seal_of_command" },
		[3] = { "holy_wrath", "retribution_aura" },
		[4] = { "consecration", "repentance" },
		[5] = { "hammer_of_wrath", "judgement" },
	},
}
Classes.HUNTER = {
	id = "HUNTER", name = "Hunter",
	kit = {
		[0] = { "mend_pet", "revive_pet" },
		[1] = { "scatter_shot", "tame_beast" },
		[2] = { "feign_death", "explosive_trap" },
		[3] = { "multi_shot", "deterrence" },
		[4] = { "frost_trap", "freezing_trap" },
		[5] = { "aimed_shot", "volley" },
	},
}
Classes.ROGUE = {
	id = "ROGUE", name = "Rogue",
	kit = {
		[0] = { "first_aid", "healing_potion" },
		[1] = { "cheap_shot", "blind" },
		[2] = { "evasion", "ambush" },
		[3] = { "eviscerate", "riposte" },
		[4] = { "gouge", "kidney_shot" },
		[5] = { "blade_flurry", "adrenaline_rush" },
	},
}
Classes.PRIEST = {
	id = "PRIEST", name = "Priest",
	kit = {
		[0] = { "renew", "greater_heal" },
		[1] = { "psychic_scream", "mind_control" },
		[2] = { "power_word_shield", "shadow_word_pain" },
		[3] = { "holy_fire", "inner_fire" },
		[4] = { "holy_nova", "silence" },
		[5] = { "mind_flay", "dispel_magic" },
	},
}
Classes.SHAMAN = {
	id = "SHAMAN", name = "Shaman",
	kit = {
		[0] = { "healing_stream_totem", "chain_heal" },
		[1] = { "earth_shock", "purge" },
		[2] = { "lightning_shield", "fire_nova_totem" },
		[3] = { "flame_shock", "grounding_totem" },
		[4] = { "earthbind_totem", "frost_shock" },
		[5] = { "lightning_bolt", "chain_lightning" },
	},
}
Classes.MAGE = {
	id = "MAGE", name = "Mage",
	kit = {
		[0] = { "conjure_food", "evocation" },
		[1] = { "counterspell", "polymorph" },
		[2] = { "ice_barrier", "blast_wave" },
		[3] = { "flamestrike", "fire_ward" },
		[4] = { "arcane_explosion", "frost_nova" },
		[5] = { "arcane_missiles", "blizzard" },
	},
}
Classes.WARLOCK = {
	id = "WARLOCK", name = "Warlock",
	kit = {
		[0] = { "drain_life", "healthstone" },
		[1] = { "death_coil", "enslave_demon" },
		[2] = { "shadow_ward", "rain_of_fire" },
		[3] = { "hellfire", "fire_shield" },
		[4] = { "howl_of_terror", "inferno" },
		[5] = { "shadow_bolt", "curse_of_agony" },
	},
}
Classes.DRUID = {
	id = "DRUID", name = "Druid",
	kit = {
		[0] = { "rejuvenation", "healing_touch" },
		[1] = { "bash", "faerie_fire" },
		[2] = { "barkskin", "insect_swarm" },
		[3] = { "swipe", "thorns" },
		[4] = { "hurricane", "entangling_roots" },
		[5] = { "wrath", "starfire" },
	},
}

ns.Classes = Classes
