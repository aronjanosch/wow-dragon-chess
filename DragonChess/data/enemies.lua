local _, ns = ...
-- Enemy roster (W0-G2a). Generated ONCE by wow/tools/convert_enemies.py from the Godot
-- scenes/enemies/*.tres (difficulty-1 values) - hand-owned from now on. Never mutate (G2b copies
-- per fight): abilities are shared tables, referenced from rotations and phases.
-- Ability fields: id name icon kind is_special damage_min damage_max cooldown + kind params
--   flurry: hit_count_min/max hit_interval (damage = per hit)   stagger: stun_duration
--   heal_block / aegis / curse / sand: duration   curse: damage_multiplier   heal: heal_percent
--   junk: junk_count   mirror: reflect_fraction break_damage break_stun   sand: factor
-- kind: plain flurry stagger heal_block nuke junk curse heal aegis mirror sand
-- windup = 8/12 s (sprite attack clip: 8 frames at 12 fps; per-enemy override field).
-- display = asset key (ui/assets.lua ENEMY); display_id = placeholder creature display.
-- attack_sound / wound_sound / death_sound (W0-P3, optional) = FileDataID of a creature sound
-- (PlaySoundFile; ui/fight_view.lua plays them on the wind-up / on damage / on defeat); absent = silent.

local AB = {}
AB.sentinel_curse = { id = "sentinel_curse", name = "Curse of Weakness", icon = "sentinel_curse", kind = "curse", is_special = true, damage_min = 0, damage_max = 0, cooldown = 10.0, damage_multiplier = 0.7, duration = 8.0, description = "Player match damage −30% for a while" }
AB.sentinel_strike = { id = "sentinel_strike", name = "Sentinel Strike", icon = "sentinel_strike", kind = "plain", is_special = false, damage_min = 280, damage_max = 340, cooldown = 5.0, description = "Medium hit" }
AB.sentinel_mortal_strike = { id = "sentinel_mortal_strike", name = "Mortal Strike", icon = "sentinel_mortal_strike", kind = "heal_block", is_special = true, damage_min = 540, damage_max = 660, cooldown = 6.0, duration = 15.0, description = "Heavy hit - no healing for a while" }
AB.nefarian_mirror = { id = "nefarian_mirror", name = "Mirror Scales", icon = "nefarian_mirror", kind = "mirror", is_special = true, damage_min = 0, damage_max = 0, cooldown = 3.0, break_damage = 500, break_stun = 1.0, duration = 8.0, reflect_fraction = 0.6, description = "Reflects half your spell damage - break it with matches" }
AB.nefarian_shadow_flame = { id = "nefarian_shadow_flame", name = "Shadow Flame Breath", icon = "nefarian_shadow_flame", kind = "nuke", is_special = true, damage_min = 900, damage_max = 1100, cooldown = 9.0, description = "Dragon breath finale" }
AB.nefarian_ash = { id = "nefarian_ash", name = "Blinding Ash", icon = "nefarian_ash", kind = "sand", is_special = true, damage_min = 0, damage_max = 0, cooldown = 4.0, duration = 8.0, factor = 0.3, description = "Dragon-breath ash - gems fall slowly" }
AB.hellhound_bite = { id = "hellhound_bite", name = "Hellhound Bite", icon = "hellhound_bite", kind = "plain", is_special = false, damage_min = 120, damage_max = 160, cooldown = 2.5, description = "A fast weak bite" }
AB.ogre_smash = { id = "ogre_smash", name = "Ogre Smash", icon = "ogre_smash", kind = "stagger", is_special = true, damage_min = 480, damage_max = 580, cooldown = 8.0, stun_duration = 2.5, description = "Slow heavy smash - staggers you if it lands" }
AB.ogre_punch = { id = "ogre_punch", name = "Ogre Punch", icon = "ogre_punch", kind = "plain", is_special = false, damage_min = 180, damage_max = 240, cooldown = 3.0, description = "Quick jab between smashes" }
AB.matriarch_gaze = { id = "matriarch_gaze", name = "Stone Gaze", icon = "matriarch_gaze", kind = "stagger", is_special = true, damage_min = 420, damage_max = 520, cooldown = 7.0, stun_duration = 2.5, description = "Heavy gaze - staggers you if it lands" }
AB.matriarch_bite = { id = "matriarch_bite", name = "Basilisk Bite", icon = "matriarch_bite", kind = "plain", is_special = false, damage_min = 180, damage_max = 240, cooldown = 3.5, description = "Fast low damage jab" }
AB.matriarch_mirror = { id = "matriarch_mirror", name = "Mirror Shield", icon = "matriarch_mirror", kind = "mirror", is_special = true, damage_min = 0, damage_max = 0, cooldown = 2.0, break_damage = 500, break_stun = 1.0, duration = 8.0, reflect_fraction = 0.6, description = "Reflects half your spell damage - break it with matches" }
AB.scarab_strike = { id = "scarab_strike", name = "Scarab Bite", icon = "scarab_strike", kind = "plain", is_special = false, damage_min = 200, damage_max = 260, cooldown = 5.0, description = "A medium hit" }
AB.scarab_web = { id = "scarab_web", name = "Web Spray", icon = "scarab_web", kind = "junk", is_special = true, damage_min = 0, damage_max = 0, cooldown = 6.0, junk_count = 3, description = "Webs gems into junk" }
AB.nefarian_flurry = { id = "nefarian_flurry", name = "Claw Flurry", icon = "nefarian_flurry", kind = "flurry", is_special = true, damage_min = 120, damage_max = 160, cooldown = 7.0, hit_count_max = 4, hit_count_min = 3, hit_interval = 0.12, description = "Rapid claw strikes" }
AB.nefarian_veil = { id = "nefarian_veil", name = "Veil of Shadow", icon = "nefarian_veil", kind = "heal_block", is_special = true, damage_min = 600, damage_max = 720, cooldown = 6.0, duration = 15.0, description = "Heavy hit - no healing for a while" }
AB.ouro_trap = { id = "ouro_trap", name = "Sand Trap", icon = "ouro_trap", kind = "junk", is_special = true, damage_min = 0, damage_max = 0, cooldown = 7.0, junk_count = 4, description = "Traps gems in junk" }
AB.ouro_sandstorm = { id = "ouro_sandstorm", name = "Sandstorm", icon = "ouro_sandstorm", kind = "sand", is_special = true, damage_min = 0, damage_max = 0, cooldown = 3.0, duration = 8.0, factor = 0.3, description = "Gems fall slowly for a while" }
AB.ouro_blast = { id = "ouro_blast", name = "Sand Blast", icon = "ouro_blast", kind = "plain", is_special = true, damage_min = 450, damage_max = 550, cooldown = 7.0, description = "Heavy telegraphed strike" }
AB.hakkar_aegis = { id = "hakkar_aegis", name = "Divine Aegis", icon = "hakkar_aegis", kind = "aegis", is_special = true, damage_min = 0, damage_max = 0, cooldown = 3.0, duration = 7.0, description = "Immune to spells and stuns for a while" }
AB.hakkar_siphon = { id = "hakkar_siphon", name = "Blood Siphon", icon = "hakkar_siphon", kind = "nuke", is_special = true, damage_min = 750, damage_max = 950, cooldown = 8.5, description = "Long windup nuke — bank an answer or kill first" }
AB.hakkar_strike = { id = "hakkar_strike", name = "Blood Strike", icon = "hakkar_strike", kind = "plain", is_special = false, damage_min = 220, damage_max = 280, cooldown = 4.0, description = "Quick hit between siphons" }
AB.hakkar_insanity = { id = "hakkar_insanity", name = "Cause Insanity", icon = "hakkar_insanity", kind = "stagger", is_special = true, damage_min = 250, damage_max = 300, cooldown = 4.0, stun_duration = 2.5, description = "Staggers you if it lands" }
AB.forest_troll_axe = { id = "forest_troll_axe", name = "Axe Swing", icon = "forest_troll_axe", kind = "plain", is_special = false, damage_min = 240, damage_max = 300, cooldown = 5.0, description = "A heavy axe swing" }
AB.forest_troll_regen = { id = "forest_troll_regen", name = "Regenerate", icon = "forest_troll_regen", kind = "heal", is_special = true, damage_min = 0, damage_max = 0, cooldown = 7.0, heal_percent = 0.08, description = "Heals a chunk of max HP" }
AB.forest_troll_rend = { id = "forest_troll_rend", name = "Rend", icon = "forest_troll_rend", kind = "heal_block", is_special = true, damage_min = 360, damage_max = 432, cooldown = 5.0, duration = 15.0, description = "Deep wound - no healing for a while" }
AB.nefarian_roar = { id = "nefarian_roar", name = "Bellowing Roar", icon = "nefarian_roar", kind = "stagger", is_special = true, damage_min = 300, damage_max = 360, cooldown = 5.0, stun_duration = 2.5, description = "Roar - staggers you if it lands" }
AB.nefarian_strike = { id = "nefarian_strike", name = "Wing Buffet", icon = "nefarian_strike", kind = "plain", is_special = true, damage_min = 400, damage_max = 500, cooldown = 6.5, description = "Heavy telegraphed strike" }
AB.harpy_flurry = { id = "harpy_flurry", name = "Wing Flurry", icon = "harpy_flurry", kind = "flurry", is_special = true, damage_min = 80, damage_max = 110, cooldown = 9.0, hit_count_max = 5, hit_count_min = 4, hit_interval = 0.12, description = "4–5 rapid hits, then rest" }

local list = {
	{
		id = "hellhound", name = "Hellhound", display = "hellhound", display_id = 1000,
		attack_sound = 600668, wound_sound = 600671, death_sound = 600677, -- sound/creature/hellhound
		max_health = 2250, weak_to_color = 5, is_boss = false,
		windup = 8 / 12,
		rotation = { AB.hellhound_bite },
	},
	{
		id = "gordok_ogre", name = "Gordok Ogre", display = "gordok_ogre", display_id = 1000,
		attack_sound = 557659, wound_sound = 557652, death_sound = 557653, -- sound/creature/ogre
		max_health = 3750, weak_to_color = 4, is_boss = false,
		windup = 8 / 12,
		rotation = { AB.ogre_punch, AB.ogre_smash },
	},
	{
		id = "basilisk_matriarch", name = "Basilisk Matriarch", display = "basilisk_matriarch", display_id = 1000,
		attack_sound = 544938, wound_sound = 544937, death_sound = 544939, -- sound/creature/basilisk
		max_health = 6000, weak_to_color = 3, is_boss = true,
		windup = 8 / 12,
		rotation = { AB.matriarch_bite, AB.matriarch_gaze, AB.matriarch_bite, AB.matriarch_mirror },
	},
	{
		id = "forest_troll", name = "Forest Troll", display = "forest_troll", display_id = 1000,
		attack_sound = 562789, wound_sound = 562786, death_sound = 562783, -- sound/creature/troll
		max_health = 5000, weak_to_color = 3, is_boss = false,
		windup = 8 / 12,
		rotation = { AB.forest_troll_axe, AB.forest_troll_rend, AB.forest_troll_regen },
	},
	{
		id = "harpy", name = "Harpy", display = "harpy", display_id = 1000,
		attack_sound = 551590, wound_sound = 551591, death_sound = 551593, -- sound/creature/harpy
		max_health = 4250, weak_to_color = 2, is_boss = false,
		windup = 8 / 12,
		rotation = { AB.harpy_flurry },
	},
	{
		id = "hakkar", name = "Hakkar the Soulflayer", display = "hakkar", display_id = 1000,
		attack_sound = 551411, wound_sound = 551410, death_sound = 551407, -- sound/creature/hakkar
		max_health = 7500, weak_to_color = 1, is_boss = true,
		windup = 8 / 12,
		rotation = { AB.hakkar_strike, AB.hakkar_insanity, AB.hakkar_aegis, AB.hakkar_siphon },
	},
	{
		id = "qiraji_scarab", name = "Qiraji Scarab", display = "qiraji_scarab", display_id = 1000,
		attack_sound = 560307, wound_sound = 560305, -- sound/creature/silithidwasp (stand-in; no death sound)
		max_health = 4500, weak_to_color = 3, is_boss = false,
		windup = 8 / 12,
		rotation = { AB.scarab_web, AB.scarab_strike },
	},
	{
		id = "anubisath_sentinel", name = "Anubisath Sentinel", display = "anubisath_sentinel", display_id = 1000,
		attack_sound = 544038, wound_sound = 544040, -- sound/creature/arcanegolem (stand-in; no death sound)
		max_health = 5000, weak_to_color = 4, is_boss = false,
		windup = 8 / 12,
		rotation = { AB.sentinel_strike, AB.sentinel_curse, AB.sentinel_mortal_strike },
	},
	{
		id = "ouro", name = "Ouro", display = "ouro", display_id = 1000,
		wound_sound = 553651, -- sound/creature/lavaworm (stand-in; no attack / death sound: none found for worms)
		max_health = 8500, weak_to_color = 0, is_boss = true,
		windup = 8 / 12,
		rotation = { AB.ouro_trap, AB.ouro_blast, AB.ouro_sandstorm },
	},
	{
		id = "nefarian", name = "Nefarian", display = "nefarian", display_id = 1000,
		attack_sound = 556312, wound_sound = 556330, death_sound = 556356, -- sound/creature/nefarian
		max_health = 13750, weak_to_color = -1, is_boss = true,
		windup = 8 / 12,
		rotation = { AB.nefarian_strike, AB.nefarian_roar },
		phases = {
			{ hp_fraction = 0.66, phase_name = "Shadow Flame", rotation = { AB.nefarian_flurry, AB.nefarian_veil, AB.nefarian_strike } },
			{ hp_fraction = 0.33, phase_name = "Corrupted", rotation = { AB.nefarian_ash, AB.nefarian_shadow_flame, AB.nefarian_mirror } },
		},
	},
}

local by_id = {}
for i = 1, #list do by_id[list[i].id] = list[i] end

-- list = ladder order of the roster; by_id[id] = enemy def; abilities = AB (read-only).
ns.EnemyData = { list = list, by_id = by_id, abilities = AB }
