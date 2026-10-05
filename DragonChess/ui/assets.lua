local addonName, ns = ...
-- Every asset reference of the addon (textures, atlases, masks, fonts, templates,
-- sounds, colours). Native WoW assets only, referenced from the installed game,
-- never copied into the package (docs/design/wow-addon.md "Art/sound"). One
-- place to fix when a patch moves a path. core/ stays asset-free; game data
-- carries asset keys (ability / intent `icon`, enemy `display`).
--
-- Verification marks: (live) = rendered in the live client probe 2026-10-04
-- (/dcprobe icons|ui|atlas|model); (vanilla) = a classic file name that was not
-- probed (if it is missing the slot shows an empty / default texture; fix here).
--
-- Helpers (W0-P2):
--   Assets.apply(tex, spec)  spec = { atlas = name, file = path, color = {r,g,b,a} }:
--                            atlas (exists check + pcall(SetAtlas)) -> file -> colour.
--                            Returns "atlas" / "file" / "color" / nil (nothing applied).
--   Assets.icon(key)         ability / intent / status icon key -> texture path.
--   Assets.intent_icon(ab)   enemy ability table -> texture path: its own ICONS[ab.icon] if it has one,
--                            else the per-kind glyph (KIND_ICON[ab.kind]) (W0-G2b).
--   Assets.play(key[, file]) plays a sound slot of Assets.SOUNDS (SoundKit via PlaySound, or a FileDataID
--                            via PlaySoundFile; W0-P3). One gate: Assets.sound_enabled / Assets.quiet, a
--                            per-slot rate limit (slot.gap) and a cut-off (StopSound after slot.max s,
--                            driven by Assets.tick()). Returns true when a sound was started.
--   Assets.FX / Assets.ANIM  spell effect models + creature animation ids (ui/fx.lua, ui/fight_view.lua).

local ICON = "Interface\\Icons\\INV_Misc_Gem_"
local SPELL = "Interface\\Icons\\"

local Assets = {
	-- Gem type (core 0..5, Godot order Amber, Amethyst, Emerald, Ruby, Sapphire,
	-- Topaz) -> vanilla gem icon. Decided look (live client 2026-10-04): the _02
	-- variants, cropped + round-masked. Amber uses Opal_02 (orange). The user
	-- plans own gem art later: swap these paths only.
	GEM_ICON = {
		[0] = ICON .. "Opal_02",
		[1] = ICON .. "Amethyst_02",
		[2] = ICON .. "Emerald_02",
		[3] = ICON .. "Ruby_02",
		[4] = ICON .. "Sapphire_02",
		[5] = ICON .. "Topaz_02",
	},
	-- SetTexCoord(left, right, top, bottom): crops the icon's black frame.
	GEM_TEXCOORD = { 0.08, 0.92, 0.08, 0.92 },
	-- Round alpha mask (+ wrap mode) for gems, badges, glows, queue / status icons.
	ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask",
	MASK_WRAP = "CLAMPTOBLACKADDITIVE",
	-- Plain white texture for backdrops (colour via SetBackdropColor).
	WHITE = "Interface\\Buttons\\WHITE8X8",

	-- Frame templates / fonts (Blizzard UI objects).
	TEMPLATE_BACKDROP = "BackdropTemplate",
	TEMPLATE_CLOSE = "UIPanelCloseButton",
	FONT_TITLE = "GameFontNormal",
	FONT_OVERLAY = "GameFontHighlightLarge",
	FONT_HUD = "GameFontNormal",
	FONT_HUD_SMALL = "GameFontHighlightSmall",
	FONT_LABEL_SMALL = "GameFontNormalSmall", -- gold small caps-ish labels (stage, SCORE)
	FONT_ENEMY_NAME = "GameFontNormalHuge",
	FONT_BANNER = "GameFontNormalLarge", -- ability banner title, swap feedback
	FONT_BANNER_SUB = "GameFontHighlight",
	FONT_CLEARED = "GameFontNormalHuge",
	FONT_SCORE = "GameFontNormalLarge",
	FONT_POP = "GameFontNormalLarge", -- floating damage numbers
	FONT_POP_BIG = "GameFontNormalHuge", -- boosted (weakness) hits

	-- HP bar fill (live: renders), tinted per bar.
	BAR = "Interface\\TargetingFrame\\UI-StatusBar",

	-- Backdrops (live as textures; classic BackdropTemplate edge files).
	BACKDROP_PANEL = {
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
	},
	BACKDROP_WINDOW = {
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
		edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 },
	},
	BACKDROP_DIALOG = { -- game-over / pause box, score plaque frame
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
		edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 },
	},
	BACKDROP_PLAQUE = {
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
		edgeSize = 14,
	},

	-- Texture specs for Assets.apply / Assets.cover (atlas first, then file, then
	-- colour). Stage backgrounds: groupfinder-background-* (live, /dcprobe atlas).
	-- CHANGE THE LOOK HERE: stage -> STAGE_BG_FILE (or the atlas fallback in STAGE_BG_NAME). The
	-- colour is the fallback when the atlas is missing. Pick live with /dcbg
	-- (cycles BG_LIST, prints name + FileDataID in chat).
	-- W0-P3.1: logo-free scenic art. The loading screens (Interface/Glues/LoadingScreens) have the
	-- "World of Warcraft" logo baked in and are dropped. LFG dungeon backgrounds
	-- (Interface\LFGFrame\UI-LFG-BACKGROUND-<dungeon>) first, then the encounter-journal backgrounds
	-- (ui-ej-background-*; their aspect is unverified: give an entry w / h to override BG_FILE_W / H).
	BG_LIST = {
		{ name = "lfg diremaul", id = 340663 }, { name = "lfg zulgurub", id = 340705 },
		{ name = "lfg aqtemple", id = 340650 }, { name = "lfg blackwinglair", id = 340659 },
		{ name = "lfg aqruins", id = 340649 }, { name = "lfg maraudon", id = 340677 },
		{ name = "lfg zulfarak", id = 340704 }, { name = "lfg sunkentemple", id = 340690 },
		{ name = "lfg moltencore", id = 340678 }, { name = "lfg naxxramas", id = 340679 },
		{ name = "ej diremaul", id = 608161 }, { name = "ej zulgurub", id = 522348 },
		{ name = "ej blackwinglair", id = 1396454 },
	},
	-- Stage -> LFG background file (primary); STAGE_BG_NAME atlases are the fallback. The LFG files are
	-- assumed 2:1 (BG_FILE_W x BG_FILE_H = 512 x 256; confirm in game, change the two constants):
	-- cover-fit crops, never stretches.
	STAGE_BG_FILE = { 340663, 340705, 340650, 340659 },
	BG_FILE_W = 512,
	BG_FILE_H = 256,
	STAGE_NAME = { "Dire Maul", "Zul'Gurub", "Ahn'Qiraj", "Blackwing Lair" },
	STAGE_BG_NAME = {
		[1] = "groupfinder-background-dungeons",
		[2] = "groupfinder-background-raids-warlords",
		[3] = "groupfinder-background-raids-legion",
		[4] = "groupfinder-background-battlegrounds",
	},
	STAGE_BG_COLOR = {
		[1] = { 0.10, 0.12, 0.16, 1 },
		[2] = { 0.14, 0.10, 0.08, 1 },
		[3] = { 0.08, 0.13, 0.09, 1 },
		[4] = { 0.15, 0.08, 0.08, 1 },
	},
	-- Vertex colour (brightness) of the art: enemy panel / board panel (the board
	-- additionally sits under COLOR.BOARD_DIM).
	BG_TINT_ENEMY = { 1, 1, 1, 1 },
	BG_TINT_BOARD = { 1, 1, 1, 1 },
	-- Score plaque fill (live): parchment atlas, else the achievement parchment file.
	PLAQUE = {
		atlas = "UI-Frame-Neutral-CardParchment",
		file = "Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal",
		color = { 0.85, 0.72, 0.42, 1 },
	},
	-- Ability banner / CLEARED background (live).
	BANNER_BG = { atlas = "BossBanner-BgBanner-Mid", color = { 0.05, 0.04, 0.03, 0.8 } },
	BANNER_TOP = { atlas = "BossBanner-TopFillagree" }, -- no fallback: hidden if missing
	-- W0-P7 (D1): soft effect textures for ui/juice.lua + ui/board_fx.lua + the ability aura (ui/board_view.lua). One role
	-- = { primary candidate, fallback candidate } (path or FileDataID), see docs/design/wow-effect-textures.md. ONLY
	-- Interface\Cooldown\star4 / ping4 / starburst are known to exist (live); every other candidate is UNVERIFIED:
	-- a missing file shows nothing / a green square in the client. Swap the entries here after the in-game check
	-- (debug panel > Board FX > "Texture test" shows all candidates side by side). A role set to false / {} (or whose
	-- candidates cannot be loaded) makes its effects fall back to the colour squares / round discs / cell quads.
	-- Roles: glow (soft spot), flare (4-point sparkle), ring (shock ring), beam (horizontal strip), bolt (lightning
	-- piece), smoke (dust puff), wedge (cone / fan pointing right).
	GLOW = {
		glow = { "Spells\\GenericGlow2b", "Spells\\White_Glow2" },
		flare = { "Interface\\Cooldown\\star4", "Interface\\Cooldown\\starburst" },
		ring = { "Interface\\Cooldown\\ping4", "Interface\\Minimap\\Ping\\ping2" },
		beam = { "Spells\\Beam1", "Spells\\GradiantBeam_02" },
		bolt = { "Spells\\Lightning2", "Spells\\Lightning4" },
		smoke = { "Spells\\Dust1_a", "Spells\\SmokeFlat1" },
		wedge = { "Spells\\EnergyWedge_h", "Spells\\ShockRingCrescent256" },
	},
	GLOW_ROLES = { "glow", "flare", "ring", "beam", "bolt", "smoke", "wedge" }, -- display order
	GLOW_CHECK = true, -- false = trust the paths (skip the GetTexture() "did it load" check after SetTexture)
	-- Ring around queue slots / the portrait (live); hidden if missing.
	SLOT_RING = { atlas = "GarrMission_EncounterBar-PortraitRing" },
	PORTRAIT_RING = { atlas = "BossBanner-PortraitBorder" },

	-- Ability / intent / status icon keys -> Interface\Icons file names.
	ICONS = {
		-- player abilities (core/abilities/*.lua `icon`)
		drain_life = "Spell_Shadow_LifeDrain02", -- (live)
		polymorph = "Spell_Nature_Polymorph", -- (vanilla)
		hammer_of_justice = "Spell_Frost_Stun", -- (live)
		mind_control = "Spell_Shadow_ShadowBolt", -- (live)
		power_word_shield = "Spell_Holy_PowerWordShield", -- (live)
		rain_of_fire = "Spell_Fire_SelfDestruct", -- (vanilla)
		flamestrike = "Spell_Fire_FlameBolt", -- (live)
		fire_shield = "Spell_Fire_FireArmor", -- (live)
		arcane_explosion = "Spell_Frost_FrostBolt02", -- (live)
		frost_nova = "Spell_Frost_FrostNova", -- (vanilla)
		whirlwind = "Spell_Nature_Lightning", -- (live)
		chain_lightning = "Spell_Nature_ChainLightning", -- (vanilla)
		bomb = "Spell_Fire_SelfDestruct", -- (vanilla) bomb gem / BOMB banner
		-- enemy intents (core/enemy.lua rotation `icon` = the ability id). Abilities without an entry
		-- of their own use the glyph of their `kind` (KIND_ICON -> kind_* below).
		hellhound_bite = "Ability_Druid_Maul", -- (live)
		kind_plain = "Ability_MeleeDamage", -- (vanilla) plain hit
		kind_flurry = "Ability_DualWield", -- (vanilla) rapid hits
		kind_stagger = "Ability_ThunderBolt", -- (vanilla) heavy hit that staggers
		kind_heal_block = "Ability_Warrior_Sunder", -- (live) wound: no healing
		kind_nuke = "Spell_Fire_Fireball02", -- (vanilla) charged big hit
		kind_junk = "INV_Misc_Bandage_01", -- (vanilla) bandage junk on the board
		kind_curse = "Spell_Shadow_ShadowBolt", -- (live) your damage weakened
		kind_heal = "Spell_Holy_Heal", -- (vanilla) enemy heals itself
		kind_aegis = "Spell_Holy_DivineIntervention", -- (vanilla) Divine Aegis
		kind_mirror = "Spell_Shadow_AntiMagicShell", -- (vanilla) Mirror Shield
		kind_sand = "Spell_Nature_Cyclone", -- (vanilla) Sandstorm
		-- enemy statuses over the enemy figure (Divine Aegis / Mirror Shield)
		enemy_aegis = "Spell_Holy_DivineIntervention", -- (vanilla)
		enemy_mirror = "Spell_Shadow_AntiMagicShell", -- (vanilla)
		-- statuses (player strip: combat:hud_state statuses; enemy: stun / freeze / slow)
		status_shield = "Spell_Holy_PowerWordShield", -- (live)
		status_fire_shield = "Spell_Fire_FireArmor", -- (live)
		status_lifesteal = "Spell_Shadow_LifeDrain02", -- (live)
		status_curse = "Spell_Shadow_ShadowBolt", -- (live; CurseOfTounge is missing)
		status_stun = "Spell_Frost_Stun", -- (live)
		status_heal_block = "Ability_Warrior_Sunder", -- (live, placeholder)
		status_sandstorm = "Spell_Nature_Slow", -- (live, W0-G2)
		enemy_stun = "Spell_Frost_Stun", -- (live)
		enemy_freeze = "Spell_Frost_FrostBolt02", -- (live)
		enemy_slow = "Spell_Nature_Slow", -- (live)
		unknown = "INV_Misc_QuestionMark", -- (live)
	},

	-- Enemy presentation by enemy `display` key (= enemy id). W0-P3.1: display_id = creature display
	-- (PlayerModel:SetDisplayInfo; textured; picked from wago.tools CreatureDisplayInfo x CreatureModelData)
	-- first, then model_id = creature model FileDataID (SetModel renders white / untextured: last resort),
	-- then the portrait icon when neither can be set. Set display_id / model_id = nil to skip a step.
	-- Optional per-enemy model framing (all pcall-guarded, defaults MODEL_DEFAULT; tune it live in the
	-- debug panel, which edits this table and prints the line to paste back here): cam_scale
	-- (SetCamDistanceScale, <1 = closer / bigger), pos {x,y,z} (SetPosition; z = up), rot (SetRotation,
	-- radians), scale (SetModelScale).
	ENEMY = {
		hellhound = { display_id = 12168, model_id = 123878, portrait = "Ability_Hunter_Pet_Wolf", rot = -0.5 }, -- Core Hound (wowhead npc 11671 displayId); the old felhound / hellhound displays do not exist in the client
		gordok_ogre = { display_id = 415, model_id = 125263, portrait = "Ability_Hunter_Pet_Gorilla", pos = { -0.5, 0.2, -0.1 }, rot = -0.5, scale = 1 },
		basilisk_matriarch = { display_id = 141, model_id = 123020, portrait = "Ability_Hunter_Pet_WindSerpent", pos = { -0.8, 0.9, -0.4 }, rot = -0.6 },
		-- foresttroll.m2 has no display rows: creature/troll/troll
		forest_troll = { display_id = 298, model_id = 126249, portrait = "Ability_Hunter_Pet_Bear", pos = { -2.6, -0.1, -0.4 }, rot = -0.5, scale = 1 }, -- trollmelee (textured); 167 (foresttroll.m2) stayed white
		harpy = { display_id = 148, model_id = 124329, portrait = "Ability_Hunter_Pet_Owl", rot = -0.5, cam_scale = 1.05, pos = { -1.2, 0.2, 0.3 }, scale = 1 }, -- tuned live (playtest 4)
		-- Hakkar's display has no texture variation rows: it may stay white; then try another Hakkar display
		hakkar = { display_id = 15295, model_id = 124317, portrait = "Ability_Hunter_Pet_Raptor", rot = -0.5 }, -- bloodgod (textured); 25634 (hakkar.m2) did not load
		qiraji_scarab = { display_id = 7469, model_id = 125892, portrait = "Ability_Hunter_Pet_Scorpid", rot = -0.5, cam_scale = 0.95, pos = { -1.3, 0.3, -0.7 } }, -- silithscarab2; tuned live
		anubisath_sentinel = { display_id = 5965, model_id = 122906, portrait = "Ability_Hunter_Pet_Cat", pos = { -0.3, 0.4, -0.2 }, rot = -0.5 },
		ouro = { display_id = 15509, model_id = 125795, portrait = "Ability_Hunter_Pet_Vulture", pos = { 0, 0.3, -0.1 }, rot = -0.5 },
		nefarian = { display_id = 11380, model_id = 123461, portrait = "INV_Misc_Head_Dragon_01", rot = -0.3, cam_scale = 0.7, pos = { 0, 2.3, 1.7 } }, -- tuned live
	},
	-- Enemy ability `kind` (data/enemies.lua) -> ICONS key of its intent glyph.
	KIND_ICON = {
		plain = "kind_plain", flurry = "kind_flurry", stagger = "kind_stagger", heal_block = "kind_heal_block",
		nuke = "kind_nuke", junk = "kind_junk", curse = "kind_curse", heal = "kind_heal", aegis = "kind_aegis",
		mirror = "kind_mirror", sand = "kind_sand",
	},
	MODEL_DEFAULT = { cam_scale = 0.9, pos = { 0, 0, 0 }, rot = 0, scale = 1 },
	ENEMY_DEFAULT = { portrait = "INV_Misc_QuestionMark" },
	ICON_DIR = SPELL, -- Interface\Icons\ (portrait names above are file names in it)

	-- Sounds (W0-P3): one table of slots. A slot is { kit = <SoundKit id | SOUNDKIT name | list of those,
	-- first resolvable wins> } (PlaySound) or { file = <FileDataID> } (PlaySoundFile; ids from
	-- wow/tools/wow_asset.sh, sound/**/*.ogg). Optional fields: gap = min seconds between plays of the
	-- slot (rate limit), max = cut-off in seconds via StopSound (default DEFAULT_MAX for files; spell
	-- sounds can be channel loops), key = true plays in quiet mode too (else KEY_SOUND by slot name),
	-- fallback = a kit slot used when PlaySoundFile is unavailable / fails. A missing slot is silent.
	-- No pitch tricks: bigger events use deeper sounds. Verified live: kit 101 (gem break), 129, 132,
	-- 139 / 235 (user, SoundKit browser) and IG_MAINMENU_OPEN 850, IG_MAINMENU_CLOSE 851,
	-- IG_CHARACTER_INFO_TAB 841, UI_BNET_TOAST 18019, GS_TITLE_OPTION_OK 798; every other file id is a
	-- director pick from the listfile, to be confirmed in game with /dcsnd <slot> (docs/design/audio.md).
	SOUNDS = {
		-- UI
		open = { kit = { "IG_MAINMENU_OPEN" } },
		close = { kit = { "IG_MAINMENU_CLOSE" } },
		click = { kit = { "GS_TITLE_OPTION_OK" } },
		-- generic fight sounds (ability / ult: used when an ability has no sound of its own)
		ability = { kit = { "IG_CHARACTER_INFO_TAB" } },
		ult = { kit = { "RAID_WARNING", "UI_BNET_TOAST" } }, -- ult / bomb / phase change: deeper horn
		cleared = { kit = { "IG_QUEST_LIST_COMPLETE", "UI_BNET_TOAST" } },
		defeat = { kit = { "IG_QUEST_FAILED", "IG_QUEST_LOG_ABANDON_QUEST", "IG_MAINMENU_CLOSE" } },
		-- board / combat feedback (W0-P3)
		gem_break = { kit = 2561, gap = 0.03 }, -- Nature Cast (wowhead sound=2561); was 101, -- gems_cleared (one per wave, not per gem)
		gem_break_holy = { kit = 2562, gap = 0.03 }, -- Holy Cast (wowhead sound=2562), layered on gem_break
		swap_ok = { file = 567484, gap = 0.05, max = 0.5 }, -- igtextpopupping02: short bling on a valid swap
		miss = { kit = 139 }, -- swap_rejected
		blocked = { kit = 132 }, -- attack_blocked / attack_reflected
		-- enemy hits the player: sword on plate (quieter than kit 129, which PlaySound cannot lower);
		-- fallback = kit 129 cut after 0.6 s when PlaySoundFile is unavailable.
		-- channel = "Ambience" (W0-P3.1): PlaySound has no volume, but each channel has its own slider and the
		-- Ambience default is 60 % (about -40 %). Playtest 3: attack sounds too loud. If the user switched
		-- Ambience off in WoW's sound options these play silent (docs/design/audio.md).
		player_hit = {
			file = 567867, max = 0.8, channel = "Ambience",
			fallback = { kit = { 129, "IG_CREATURE_AGGRO_SELECT" }, max = 0.6 },
		},
		-- per-enemy creature sounds: the file comes from the enemy def (attack_sound / death_sound in
		-- data/enemies.lua); the slots only carry the rate limit + cut-off. W0-P3.1: no wound ("hurt") sound
		-- (user: annoying; the wound_sound fields stay in the data, unused) and the attack sound goes through
		-- the Ambience channel (see player_hit).
		enemy_attack = { gap = 0.2, max = 1.5, creature = true, channel = "Ambience" },
		enemy_death = { gap = 0.2, max = 2.5, creature = true },
		-- W0-P5 feel: matches of 4+ gems (the per-wave gem_break stays and plays too), deeper / bigger with the
		-- length (no pitch in WoW: different files), a quiet cascade tick for 3-matches in a chain (depth >= 2),
		-- ability gem spawns and the enemy's special cast. File ids are listfile picks, unconfirmed in game:
		-- audition with /dcsnd <slot> or the debug panel's Sounds tab (docs/design/audio.md).
		match_4 = { file = 569631, gap = 0.15, max = 1.0 }, -- sound/spells/arcanemissileimpact1a
		match_5 = { file = 569402, gap = 0.15, max = 1.2 }, -- holybolt
		match_6 = { file = 569383, gap = 0.15, max = 1.5 }, -- holylight_low_head
		match_7 = { file = 567966, gap = 0.15, max = 1.8 }, -- holy_impactdd_uber_chest (deepest)
		match_cascade = { file = 569565, gap = 0.12, max = 0.8 }, -- arcanemissileimpact1b
		ability_spawn_skill = { file = 642843, gap = 0.1, max = 1.0 }, -- sound/interface/ui_quest_objectivecomplete_01
		ability_spawn_ult = { file = 567431, key = true, max = 2.0 }, -- sound/interface/levelup
		enemy_special = { file = 568054, key = true, max = 1.2, channel = "Ambience" }, -- arcane_form_precast
		-- player abilities, fired on ability_triggered by ability id ("ab_" .. id, ABILITY_KEY). Skills are
		-- filtered in quiet mode, ults (key = true) are key sounds.
		ab_flamestrike = { file = 568641 }, -- sound/spells/flamestrike
		ab_fire_shield = { file = 569485, key = true }, -- fireshield
		ab_arcane_explosion = { file = 568678 }, -- arcaneexplosion
		ab_frost_nova = { file = 569378, key = true }, -- frostnova
		ab_whirlwind = { file = 568227 }, -- cleavetarget
		ab_chain_lightning = { file = 568516, key = true }, -- lightningboltimpact
		ab_drain_life = { file = 568353, max = 1.2 }, -- shadowwordpain_chest (lifedrainloop is a loop: avoided)
		ab_polymorph = { file = 569526, key = true }, -- polymorphtarget
		ab_hammer_of_justice = { file = 569110 }, -- kidneyshot
		ab_mind_control = { file = 567957, key = true }, -- curseoftounges
		ab_power_word_shield = { file = 569738 }, -- divineshield
		ab_rain_of_fire = { file = 568733, key = true }, -- firebombimpact1
	},
	SOUND_CHANNEL = "SFX", -- default; a slot's own `channel` field overrides it
	-- Channels the debug panel cycles a slot through (each has its own user volume slider in WoW's options).
	SOUND_CHANNELS = { "SFX", "Ambience", "Dialog", "Master" },
	DEFAULT_MAX = 1.5, -- cut-off (s) of a file sound without its own max
	STOP_FADE_MS = 150,
	-- Quiet mode (menu): only these slots (and slots with key = true) play.
	KEY_SOUND = { ult = true, player_hit = true, cleared = true, defeat = true, blocked = true },

	-- Spell effect models (ui/fx.lua), played on events by key. m2 = FileDataID of spells/*.m2 (PlayerModel:
	-- SetModel); at = where (enemy | player | board | cell | cone | row); size = apparent px of the effect inside its unified frame (board effects: frame = the play area, centred; enemy: the enemy frame; player: 256 px); scale =
	-- SetModelScale; offset = SetPosition {x, y, z}; px = frame offset {dx, dy} from the anchor; cam_scale
	-- = SetCamDistanceScale; rot = SetRotation; anim = SetAnimation id; duration = seconds (sim time) a
	-- one-shot stays; gap = min seconds between plays. Models render in the live client (/dcprobe fx);
	-- sizes / pivots are guesses to tune live with /dcfx cam. Ability keys equal the ability ids.
	FX = {
		flamestrike = { m2 = 166187, at = "cone", size = 280, duration = 1.4 }, -- flamestrike_area
		fire_shield = { m2 = 166156, at = "player", size = 240, duration = 1.2 }, -- fireshield_impact_head
		arcane_explosion = { m2 = 165576, at = "cell", size = 240, duration = 1.0 }, -- arcaneexplosion_base
		frost_nova = { m2 = 166210, at = "board", size = 340, duration = 1.4 }, -- frost_nova_area
		whirlwind = { m2 = 167199, at = "row", size = 280, duration = 1.2 }, -- whirlwind_state_base
		chain_lightning = { m2 = 165780, at = "enemy", size = 300, duration = 1.0 }, -- chainlightning_impact_chest
		drain_life = { m2 = 166469, at = "player", size = 240, duration = 1.2 }, -- lifedrain_missile
		polymorph = { m2 = 166649, at = "board", size = 320, duration = 1.2 }, -- polymorph_impact
		hammer_of_justice = { m2 = 166175, at = "enemy", size = 300, duration = 1.0 }, -- fistofjustice_impact_chest
		-- Mind Control: shadowworddominate_chest (no model is named mind control; searched spells/*shadow*|*curse*)
		mind_control = { m2 = 166833, at = "board", size = 320, duration = 1.4 },
		power_word_shield = { m2 = 165961, at = "player", size = 240, duration = 1.4 }, -- divineshield_low_base
		rain_of_fire = { m2 = 166677, at = "board", size = 340, duration = 1.6 }, -- rainoffire_impact_base
		-- event effects
		enemy_hit = { m2 = 165559, at = "enemy", size = 240, duration = 0.5, gap = 0.15 }, -- aimedshot_impact_chest
		-- state effects, held while a status lasts (Fx:hold, polled from the HUD state)
		stun_stars = { m2 = 166988, at = "enemy", size = 180, px = { 0, 100 } }, -- stunswirl_state_head
		freeze = { m2 = 166211, at = "enemy", size = 360 }, -- frost_nova_state
		aegis = { m2 = 165961, at = "enemy", size = 390 }, -- divineshield_low_base (Divine Aegis)
		mirror = { m2 = 166940, at = "enemy", size = 390 }, -- spellreflection_state_shield (Mirror Shield)
	},
	-- Fx:hold(name) -> FX key.
	FX_HOLD = { stun = "stun_stars", freeze = "freeze", aegis = "aegis", mirror = "mirror" },
	-- Creature animation ids (PlayerModel:SetAnimation, standard WoW ids) + view timings (sim s).
	ANIM = {
		stand = 0, death = 1, wound = 8, stun = 14, attack = 17, attack_alt = 16,
		attack_tail = 0.35, wound_time = 0.45, wound_gap = 0.6, death_hold = 0.7,
	},

	-- Colours {r, g, b, a} (generated colour textures, no files).
	-- W0-P8: status class colours (the 2 px edge of every status icon, player strip + enemy slots). buff = gold,
	-- debuff = violet / red, enemy buffs gold / silver, enemy debuffs (the player's stun / slow on it) cyan.
	STATUS_EDGE = {
		shield = { 1, 0.82, 0.25, 1 }, fire_shield = { 1, 0.82, 0.25, 1 }, lifesteal = { 1, 0.82, 0.25, 1 },
		curse = { 0.62, 0.25, 0.85, 1 }, heal_block = { 0.85, 0.2, 0.3, 1 }, stun = { 0.75, 0.45, 0.95, 1 },
		sandstorm = { 0.85, 0.3, 0.25, 1 },
		enemy_aegis = { 1, 0.82, 0.25, 1 }, enemy_mirror = { 0.82, 0.88, 0.96, 1 },
		enemy_stun = { 0.45, 0.8, 1, 1 }, enemy_freeze = { 0.45, 0.8, 1, 1 }, enemy_slow = { 0.45, 0.8, 1, 1 },
	},
	-- Player aura (halo around the HP bar), highest priority first; the colour of each.
	AURA_ORDER = { "stun", "curse", "fire_shield", "shield", "lifesteal" },
	STATUS_AURA = {
		stun = { 0.78, 0.68, 1 }, curse = { 0.62, 0.25, 0.85 }, fire_shield = { 1, 0.5, 0.12 },
		shield = { 0.7, 0.85, 1 }, lifesteal = { 0.3, 1, 0.45 },
	},
	-- Enemy windup telegraph colour by ability kind (glow on the figure + the edge vignette).
	INTENT_TINT = {
		plain = { 1, 0.25, 0.2 }, stagger = { 1, 0.25, 0.2 }, flurry = { 1, 0.25, 0.2 }, nuke = { 1, 0.25, 0.2 },
		curse = { 0.7, 0.25, 0.9 }, junk = { 0.65, 0.4, 0.2 },
		mirror = { 0.82, 0.88, 1 }, aegis = { 0.82, 0.88, 1 },
		special = { 1, 0.55, 0.15 }, -- everything else (heal_block, sand, heal)
	},
	COLOR = {
		CHIP_PLAYER = { 1, 0.5, 0.45, 0.9 }, -- W0-P8: the lagging chip behind the HP fill
		CHIP_ENEMY = { 1, 0.93, 0.85, 0.9 },
		HEAL_FLASH = { 0.4, 1, 0.5, 1 },
		LOW_HP = { 1, 0.15, 0.1, 1 },
		VIG_BLOCK = { 0.8, 0.95, 1, 0.55 }, -- block flash (cyan-white)
		RING_BLOCK = { 0.8, 0.92, 1, 1 },
		RING_HEAL = { 0.4, 1, 0.55, 1 },
		DEATH_GOLD = { 1, 0.85, 0.3, 1 },
		DEATH_FLASH = { 1, 1, 1, 1 },
		SCORE_GLINT = { 1, 0.85, 0.3, 1 },
		WINDOW_BG = { 0.04, 0.04, 0.05, 0.96 },
		WINDOW_EDGE = { 1, 0.85, 0.5, 1 },
		TITLE_BG = { 0, 0, 0, 0 }, -- title strip is transparent over the window bg
		PANEL_EDGE = { 0.55, 0.47, 0.3, 1 },
		BOARD_DIM = { 0.02, 0.02, 0.04, 0.55 }, -- over the board panel's background art
		TILE_LIGHT = { 0.16, 0.16, 0.2, 0.55 },
		TILE_DARK = { 0.08, 0.08, 0.11, 0.55 },
		OVERLAY = { 0, 0, 0, 0.65 },
		SELECT = { 1, 1, 1, 0.55 }, -- click-selected gem glow
		PROTECTED = { 1, 0.85, 0.35, 0.45 }, -- spawn-protection glow (additive)
		TIER1_RIM = { 0.95, 0.95, 1, 1 }, -- skill badge
		TIER1_PIP = { 0.55, 0.75, 1, 1 },
		TIER2_RIM = { 1, 0.82, 0.25, 1 }, -- ult badge
		TIER2_PIP = { 1, 0.55, 0.1, 1 },
		BOMB_RIM = { 0.9, 0.15, 0.1, 1 },
		BOMB_PIP = { 0.08, 0.08, 0.08, 1 },
		JUNK_TINT = { 0.45, 0.45, 0.45, 1 }, -- desaturated + darkened gem
		SPELL_RING = { 0, 0, 0, 0.55 }, -- dark disc behind a gem's spell icon
		-- HUD
		BAR_BG = { 0, 0, 0, 0.7 },
		BAR_EDGE = { 0, 0, 0, 1 },
		HP_ENEMY = { 0.8, 0.12, 0.1, 1 },
		HP_PLAYER = { 0.15, 0.7, 0.2, 1 },
		HP_CURSE = { 0.5, 0.18, 0.55, 1 }, -- Godot CURSE_BAR_COLOR
		HP_HEAL_BLOCK = { 0.32, 0.28, 0.3, 1 }, -- Godot HEAL_BLOCK_BAR_COLOR
		ATTACK_STUN = { 0.6, 0.45, 1, 1 }, -- player stunned bar / enemy stunned
		QUEUE_BG = { 0, 0, 0, 0.55 },
		SLOT_DISC = { 0.08, 0.1, 0.16, 0.9 },
		SLOT_DISC_SPECIAL = { 0.35, 0.12, 0.05, 0.9 },
		SLOT_RING_SPECIAL = { 1, 0.55, 0.3, 1 },
		SLOT_NOW = { 1, 0.25, 0.15, 0.9 }, -- wind-up pulse (additive)
		SWIPE = { 0, 0, 0, 0.65 },
		STATUS_DIM = { 0, 0, 0, 0.6 }, -- elapsed part of a status icon
		STAGE_TEXT = { 0.85, 0.75, 0.5, 1 },
		WEAK_TEXT = { 0.8, 0.8, 0.8, 1 },
		SCORE_TEXT = { 0.25, 0.14, 0.04, 1 },
		BANNER_BLURB = { 0.95, 0.92, 0.85, 1 },
		HIT_TINT = { 1, 0.15, 0.1, 0.55 }, -- enemy hit glow (additive)
		AEGIS_GLOW = { 1, 0.8, 0.25, 1 }, -- Divine Aegis: gold glow over the enemy (additive, alpha animated)
		MIRROR_GLOW = { 0.78, 0.88, 1, 1 }, -- Mirror Shield: silver glow
		MIRROR_BAR = { 0.75, 0.85, 1, 1 }, -- crack progress bar
		SAND_TINT = { 0.85, 0.66, 0.3, 0.3 }, -- Sandstorm: sandy layer over the board
		JUNK_FLASH = { 0.55, 0.45, 0.32, 0.45 }, -- bandage junk spawned: brown flash over the board
		PHASE_TEXT = { 1, 0.6, 0.25, 1 }, -- phase banner / shatter text
		VIGNETTE = { 0.85, 0.05, 0.03, 0.55 }, -- player hit edge flash
		POP_ENEMY = { 1, 1, 1, 1 },
		POP_BOOSTED = { 1, 0.85, 0.2, 1 },
		POP_PLAYER = { 1, 0.3, 0.25, 1 },
		POP_HEAL = { 0.45, 1, 0.45, 1 },
		POP_INFO = { 0.8, 0.85, 1, 1 },
		TEXT_WARN = { 1, 0.3, 0.25, 1 }, -- wind-up, swap rejected
		MATCH_TEXT = { 1, 1, 1, 1 }, -- match float "4-MATCH"
		MATCH_POINTS = { 1, 0.92, 0.35, 1 }, -- match float "+125" (Godot MATCH_FLOAT_COLOR)
		SPAWN_TEXT = { 0.55, 0.9, 1, 1 }, -- ability gem spawned float
		HINT_RING = { 1, 0.95, 0.5, 0.8 }, -- swap hint ring around a gem that would activate the selected ability gem
		HINT_TEXT = { 1, 0.95, 0.6, 1 },
		BANNER_TITLE = { 1, 0.82, 0, 1 }, -- ability banner title (player abilities; GameFontNormalLarge gold)
		BANNER_TITLE_ENEMY = { 1, 0.45, 0.3, 1 }, -- same banner for an enemy special cast
		CAST_TINT = { 1, 0.45, 0.1, 1 }, -- enemy cast flash (additive disc over the figure)
		-- W0-P6 juice (ui/juice.lua): gem-colour shards / streaks (Godot board.gd GEM_TRAIL_COLORS), streak colours by
		-- source, vignette flash colours (alpha = the edge strength; the flash peak is in ui/fight_view.lua).
		GEM_FX = {
			[0] = { 1, 0.7, 0.2, 1 }, [1] = { 0.75, 0.35, 1, 1 }, [2] = { 0.3, 0.95, 0.45, 1 },
			[3] = { 1, 0.3, 0.3, 1 }, [4] = { 0.35, 0.65, 1, 1 }, [5] = { 1, 0.85, 0.25, 1 },
		},
		PROJ_DEFAULT = { 0.75, 0.95, 1, 1 }, -- a match / ability hit without a colour
		PROJ_ENEMY = { 1, 0.35, 0.35, 1 }, -- enemy cast -> player
		PROJ_CURSE = { 0.75, 0.25, 0.85, 1 },
		PROJ_JUNK = { 0.85, 0.3, 0.2, 1 }, -- junk lands on the board
		PROJ_HEAL = { 0.4, 1, 0.55, 1 }, -- lifesteal / heal
		PROJ_REFLECT = { 1, 0.45, 0.15, 1 }, -- Fire Shield sends the hit back
		PROJ_MIRROR = { 0.85, 0.92, 1, 1 }, -- Mirror Shield bounce
		-- W0-P7 board effects / chain escalation (ui/board_fx.lua, ui/fight_view.lua)
		VIG_COMBO = { 1, 0.85, 0.2, 0.55 }, -- gold vignette from chain depth 4
		COMBO_TEXT = { 1, 0.82, 0.15, 1 },
		FX_CHAIN = { 1, 0.95, 0.55, 1 }, -- chain lightning bolt / cell flashes (Topaz)
		FX_TELE_FROM = { 0.6, 0.72, 0.85, 1 }, -- convert telegraph, cells that will change (cool, desaturated)
		FX_REJECT = { 1, 0.35, 0.3, 1 }, -- rejected swap puff
		FX_DARK = { 0, 0, 0, 1 }, -- ult board darkening (alpha set by ui/board_fx.lua)
		FX_DUST = { 0.8, 0.74, 0.62, 1 }, -- landing dust
		HELD_SHADOW = { 1, 0.95, 0.8, 1 }, -- halo under the dragged gem
		AURA_SKILL = { 0.45, 0.85, 1, 1 }, -- skill gem halo
		AURA_ULT = { 1, 0.8, 0.25, 1 }, -- ult gem halo / flare
		AURA_BOMB = { 1, 0.25, 0.15, 1 }, -- bomb flicker
		SPARKLE = { 1, 0.95, 0.7, 1 }, -- 5+ match sparkles
		RING_SKILL = { 0.5, 0.9, 1, 1 }, -- ability gem spawn ring
		RING_ULT = { 1, 0.82, 0.2, 1 },
		VIG_SKILL = { 0.3, 0.8, 1, 0.55 }, -- ability flash (Godot: cyan skill, gold ult)
		VIG_ULT = { 1, 0.85, 0.2, 0.55 },
		VIG_MIRROR = { 0.85, 0.92, 1, 0.55 },
		VIG_REFLECT = { 1, 0.45, 0.1, 0.55 },
		TEXT_DIM = { 0.75, 0.75, 0.75, 1 },
		TEXT_GOOD = { 0.45, 1, 0.45, 1 },
		BUTTON_BG = { 0.15, 0.12, 0.08, 0.9 },
		BUTTON_HL = { 1, 0.85, 0.4, 0.25 },
	},
}

---------------------------------------------------------------- helpers

local pcall, type = pcall, type

local function atlas_exists(name)
	local CT = C_Texture
	if type(CT) == "table" and type(CT.GetAtlasExists) == "function" then
		local ok, exists = pcall(CT.GetAtlasExists, name)
		if ok then return exists and true or false end
	end
	return true -- unknown: let pcall(SetAtlas) decide
end

-- Applies a texture spec; never raises (a missing atlas falls back).
function Assets.apply(tex, spec)
	if spec == nil then return nil end
	if spec.atlas ~= nil and tex.SetAtlas ~= nil and atlas_exists(spec.atlas) then
		local ok, res = pcall(tex.SetAtlas, tex, spec.atlas)
		if ok and res ~= false then return "atlas" end
	end
	if spec.file ~= nil then
		tex:SetTexture(spec.file)
		return "file"
	end
	local c = spec.color
	if c ~= nil then
		tex:SetColorTexture(c[1], c[2], c[3], c[4])
		return "color"
	end
	return nil
end

---------------------------------------------------------------- soft effect textures (W0-P7 D1)

-- Resolved path per role: false = no candidate loads (cached after the first probe so new() calls stay cheap).
local soft_cache, soft_status = {}, {}

-- Tries the candidates of A.GLOW[role] on `tex` (pcall-guarded; with GLOW_CHECK a candidate whose GetTexture() is
-- nil after SetTexture counts as not loaded, like the background art check in fight_view). Returns true and leaves
-- the texture set on success, else false (the caller keeps / applies its colour square or round-mask disc).
function Assets.soft(tex, role)
	local spec = Assets.GLOW and Assets.GLOW[role]
	if type(spec) ~= "table" then
		soft_status[role] = "missing"
		return false
	end
	local known = soft_cache[role]
	if known == false then return false end
	if known ~= nil then
		return (pcall(tex.SetTexture, tex, known)) and true or false
	end
	for i = 1, #spec do
		local path = spec[i]
		if path and path ~= false then
			local ok = pcall(tex.SetTexture, tex, path)
			if ok and Assets.GLOW_CHECK then
				local get = tex.GetTexture
				if type(get) == "function" then
					local okg, cur = pcall(get, tex)
					if okg and cur == nil then ok = false end
				end
			end
			if ok then
				soft_cache[role] = path
				soft_status[role] = i == 1 and "ok" or "ok (fallback candidate)"
				return true
			end
		end
	end
	soft_cache[role] = false
	soft_status[role] = "missing"
	return false
end

-- The resolved path of a role (nil until a texture probed it, or when missing).
function Assets.soft_path(role)
	local p = soft_cache[role]
	if p == false then return nil end
	return p
end

-- Forget the probe results (tests / after editing A.GLOW live).
function Assets.soft_reset()
	soft_cache, soft_status = {}, {}
end

-- "glow ok, flare missing, ..." for the debug panel (roles never probed show "?").
function Assets.soft_report()
	local out = {}
	local roles = Assets.GLOW_ROLES
	for i = 1, #roles do
		out[#out + 1] = roles[i] .. " " .. (soft_status[roles[i]] or "?")
	end
	return table.concat(out, ", ")
end

-- Pure: the SetTexCoord rectangle that makes an image (aw x ah pixels, occupying
-- l..r / t..b of its file) cover a pw x ph panel without distortion (centred
-- crop of the overflowing axis).
function Assets.cover_coords(aw, ah, l, r, t, b, pw, ph)
	if not (aw > 0 and ah > 0 and pw > 0 and ph > 0) then return l, r, t, b end
	local img, pan = aw / ah, pw / ph
	if img > pan then -- too wide: crop left / right
		local half = (r - l) * (pan / img) / 2
		local cx = (l + r) / 2
		return cx - half, cx + half, t, b
	elseif img < pan then -- too tall: crop top / bottom
		local half = (b - t) * (img / pan) / 2
		local cy = (t + b) / 2
		return l, r, cy - half, cy + half
	end
	return l, r, t, b
end

-- Assets.apply + cover-fit crop for atlases (needs the panel size) + optional
-- vertex colour tint. Never raises.
function Assets.cover(tex, spec, pw, ph, tint)
	local mode = Assets.apply(tex, spec)
	local l, r, t, b = 0, 1, 0, 1
	if mode == "atlas" then
		-- Crop INSIDE the rectangle SetAtlas just applied: read it back from the texture
		-- (robust against GetAtlasInfo field names / sheet coordinates), size from GetAtlasInfo.
		local CT = C_Texture
		if type(CT) == "table" and type(CT.GetAtlasInfo) == "function" then
			local ok, info = pcall(CT.GetAtlasInfo, spec.atlas)
			if ok and type(info) == "table" and type(info.width) == "number" and type(info.height) == "number" then
				local okc, ulx, uly, llx, lly, urx, ury = pcall(tex.GetTexCoord, tex)
				if okc and type(ulx) == "number" and type(urx) == "number" and type(uly) == "number" and type(lly) == "number" then
					l, r, t, b = ulx, urx, uly, lly
				else
					l, r = info.leftTexCoord or 0, info.rightTexCoord or 1
					t, b = info.topTexCoord or 0, info.bottomTexCoord or 1
				end
				l, r, t, b = Assets.cover_coords(info.width, info.height, l, r, t, b, pw, ph)
				Assets.last_cover = Assets.last_cover or {}
				local lc = Assets.last_cover
				lc.name, lc.w, lc.h, lc.l, lc.r, lc.t, lc.b, lc.pw, lc.ph = spec.atlas, info.width, info.height, l, r, t, b, pw, ph
			end
		end
	end
	if mode == "file" and spec.file_w ~= nil and spec.file_h ~= nil then -- whole-file image of known size
		l, r, t, b = Assets.cover_coords(spec.file_w, spec.file_h, 0, 1, 0, 1, pw, ph)
	end
	if mode ~= nil and mode ~= "atlas" or l ~= 0 or r ~= 1 or t ~= 0 or b ~= 1 then
		pcall(tex.SetTexCoord, tex, l, r, t, b)
	end
	if mode == "color" or tint == nil then
		tex:SetVertexColor(1, 1, 1, 1)
	else
		tex:SetVertexColor(tint[1], tint[2], tint[3], tint[4])
	end
	return mode
end

-- Gem sets (W0-P5). Entries: [type] = { texture path, { l, r, t, b } }; round = round-masked.
local RT = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
local FULL = { 0, 1, 0, 1 }
local JW = "Interface\\AddOns\\DragonChess\\media\\gems\\"
Assets.GEM_SETS = {
	wow = { round = true },
	-- The Godot version's gem art (assets/bejewled, frame 0 as 128 px TGA with alpha). Licence of the
	-- source unknown (CREDITS.md): replace before a public release.
	jewels = {
		round = false,
		[0] = { JW .. "Amber", FULL },
		[1] = { JW .. "Amethyst", FULL },
		[2] = { JW .. "Emerald", FULL },
		[3] = { JW .. "Ruby", FULL },
		[4] = { JW .. "Sapphire", FULL },
		[5] = { JW .. "Topaz", FULL },
	},
	shapes = {
		round = false,
		[0] = { RT .. "2", FULL }, -- Amber: circle (orange)
		[1] = { RT .. "3", FULL }, -- Amethyst: diamond (purple)
		[2] = { RT .. "4", FULL }, -- Emerald: triangle (green)
		[3] = { RT .. "7", FULL }, -- Ruby: cross (red)
		[4] = { RT .. "6", FULL }, -- Sapphire: square (blue)
		[5] = { RT .. "1", FULL }, -- Topaz: star (yellow)
	},
}
for t = 0, 5 do Assets.GEM_SETS.wow[t] = { Assets.GEM_ICON[t], Assets.GEM_TEXCOORD } end
Assets.GEM_SET_ORDER = { "jewels", "wow", "shapes" }
Assets.GEM_SET_LABEL = { jewels = "Jewels", wow = "WoW", shapes = "Shapes" }
Assets.gem_set = "jewels"

-- Gem type -> texture path, texcoords, round? in the active set (wow entry as fallback).
function Assets.gem(t)
	local set = Assets.GEM_SETS[Assets.gem_set] or Assets.GEM_SETS.wow
	local e = set[t]
	if e == nil then
		set = Assets.GEM_SETS.wow
		e = set[t] or set[0]
	end
	return e[1], e[2], set.round
end

-- Apply gem type t to a texture. The round mask (tex.dc_mask, set by the view that built it)
-- is added / removed to match the set; guarded, the client may lack RemoveMaskTexture.
function Assets.apply_gem(tex, t)
	local path, tc, round = Assets.gem(t)
	tex:SetTexture(path)
	tex:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
	local mask = tex.dc_mask
	if mask ~= nil and tex.dc_round ~= round then
		tex.dc_round = round
		if round then
			tex:AddMaskTexture(mask)
		elseif tex.RemoveMaskTexture then
			tex:RemoveMaskTexture(mask)
		end
	end
end

-- Icon key -> texture path (cached per key; unknown keys -> question mark).
local icon_cache = {}
function Assets.icon(key)
	if key == nil then key = "unknown" end
	local path = icon_cache[key]
	if path == nil then
		local name = Assets.ICONS[key] or Assets.ICONS.unknown
		path = SPELL .. name
		icon_cache[key] = path
	end
	return path
end

-- Enemy ability -> texture path of its intent icon (queue slots): its own ICONS entry, else the
-- glyph of its kind.
function Assets.intent_icon(ability)
	local key = ability.icon
	if key == nil or Assets.ICONS[key] == nil then key = Assets.KIND_ICON[ability.kind] end
	return Assets.icon(key)
end

---------------------------------------------------------------- sounds (W0-P3)

-- Ability id -> its sound slot key ("ab_" .. id), built once from the SOUNDS table.
Assets.ABILITY_KEY = {}
for key in pairs(Assets.SOUNDS) do
	local id = key:match("^ab_(.+)$")
	if id ~= nil then Assets.ABILITY_KEY[id] = key end
end

-- SoundKit value of a slot entry: a number, or a SOUNDKIT name (nil when unknown on this client).
local function kit_value(v)
	if type(v) == "number" then return v end
	if type(v) == "string" and type(SOUNDKIT) == "table" then return SOUNDKIT[v] end
	return nil
end

-- Slot -> SoundKit id (first resolvable), cached; false = none.
local kit_cache = {}
local function resolve_kit(slot)
	local id = kit_cache[slot]
	if id ~= nil then return id end
	id = false
	local k = slot.kit
	if type(k) == "table" then
		for i = 1, #k do
			local v = kit_value(k[i])
			if v ~= nil then
				id = v
				break
			end
		end
	elseif k ~= nil then
		id = kit_value(k) or false
	end
	kit_cache[slot] = id
	return id
end

-- Cut-offs: sound handles to StopSound at a time (GetTime: sounds run on engine time). A fixed ring,
-- no allocation after load.
local PENDING = 8
local pend_h, pend_t, pend_i = {}, {}, 0
for i = 1, PENDING do pend_h[i], pend_t[i] = false, 0 end

local function stop_handle(h)
	if type(StopSound) == "function" then pcall(StopSound, h, Assets.STOP_FADE_MS) end
end

local function schedule_stop(handle, secs)
	if handle == nil or handle == false then return end
	pend_i = pend_i % PENDING + 1
	local old = pend_h[pend_i]
	if old then stop_handle(old) end
	pend_h[pend_i] = handle
	pend_t[pend_i] = GetTime() + secs
end

-- Every HUD frame: stops sounds past their cut-off.
function Assets.tick()
	local now = GetTime()
	for i = 1, PENDING do
		local h = pend_h[i]
		if h and now >= pend_t[i] then
			pend_h[i] = false
			stop_handle(h)
		end
	end
end

-- Pause / hide / menu: stops every sound that has a cut-off pending (long spell sounds).
function Assets.stop_sounds()
	for i = 1, PENDING do
		local h = pend_h[i]
		if h then
			pend_h[i] = false
			stop_handle(h)
		end
	end
end

-- `inherit` = the channel of the slot this one is a fallback of.
local function play_slot(slot, file, inherit)
	file = file or slot.file
	local channel = slot.channel or inherit or Assets.SOUND_CHANNEL
	if file ~= nil then
		if type(PlaySoundFile) == "function" then
			local ok, will_play, handle = pcall(PlaySoundFile, file, channel)
			if ok and will_play ~= false then
				schedule_stop(handle, slot.max or Assets.DEFAULT_MAX)
				return true
			end
		end
		local fb = slot.fallback
		if fb ~= nil then return play_slot(fb, nil, channel) end
		return false
	end
	local id = resolve_kit(slot)
	if id and type(PlaySound) == "function" then
		local ok, _, handle = pcall(PlaySound, id, channel)
		if ok then
			if slot.max ~= nil then schedule_stop(handle, slot.max) end
			return true
		end
	end
	return false
end

-- The single sound gate (W0-P4 menu): Assets.sound_enabled = false mutes everything; Assets.quiet plays
-- only key sounds (KEY_SOUND by slot name, or slot.key). Set from DragonChessDB.options by ui/main.lua.
Assets.sound_enabled = true
Assets.quiet = false

local last_at = {}

-- Plays a slot; `file` overrides the slot's file (per-enemy creature sounds); `force` (/dcsnd) skips
-- quiet mode and the rate limit but not the sound-off option. True when a sound was started.
function Assets.play(key, file, force)
	if not Assets.sound_enabled then return false end
	local slot = Assets.SOUNDS[key]
	if slot == nil then return false end
	if file == nil and slot.file == nil and slot.kit == nil then return false end -- creature slot, no file
	if not force then
		if Assets.quiet and not (slot.key or Assets.KEY_SOUND[key]) then return false end
		local gap = slot.gap
		if gap ~= nil then
			local now = GetTime()
			local last = last_at[key]
			if last ~= nil and now - last < gap then return false end
			last_at[key] = now
		end
	end
	return play_slot(slot, file)
end

-- Dev (/dcsnd): sorted slot keys.
function Assets.sound_keys()
	local out = {}
	for key in pairs(Assets.SOUNDS) do out[#out + 1] = key end
	table.sort(out)
	return out
end

-- Channel a slot plays on (its own, else the default).
function Assets.channel_of(key)
	local slot = Assets.SOUNDS[key]
	return slot ~= nil and slot.channel or Assets.SOUND_CHANNEL
end

-- Moves a slot to `channel` (a name of SOUND_CHANNELS; the default channel clears the field). Debug panel.
function Assets.set_channel(key, channel)
	local slot = Assets.SOUNDS[key]
	if slot == nil then return false end
	if channel == Assets.SOUND_CHANNEL then slot.channel = nil else slot.channel = channel end
	return true
end

-- Next channel of SOUND_CHANNELS after the slot's current one (wraps); returns its name.
function Assets.next_channel(key)
	local list = Assets.SOUND_CHANNELS
	local cur = Assets.channel_of(key)
	local at = 0
	for i = 1, #list do
		if list[i] == cur then at = i end
	end
	local nxt = list[at % #list + 1]
	Assets.set_channel(key, nxt)
	return nxt
end

---------------------------------------------------------------- copy-paste lines (debug panel)

local function num(v) return ("%g"):format(v) end

-- The ENEMY line of `key` as it would read in this file (live-tuned values included).
function Assets.format_enemy(key)
	local e = Assets.ENEMY[key]
	if e == nil then return nil end
	local parts = {}
	if e.display_id ~= nil then parts[#parts + 1] = "display_id = " .. e.display_id end
	if e.model_id ~= nil then parts[#parts + 1] = "model_id = " .. e.model_id end
	if e.portrait ~= nil then parts[#parts + 1] = ('portrait = "%s"'):format(e.portrait) end
	if e.cam_scale ~= nil then parts[#parts + 1] = "cam_scale = " .. num(e.cam_scale) end
	if e.pos ~= nil then parts[#parts + 1] = ("pos = { %s, %s, %s }"):format(num(e.pos[1]), num(e.pos[2]), num(e.pos[3])) end
	if e.rot ~= nil then parts[#parts + 1] = "rot = " .. num(e.rot) end
	if e.scale ~= nil then parts[#parts + 1] = "scale = " .. num(e.scale) end
	return key .. " = { " .. table.concat(parts, ", ") .. " },"
end

-- Live enemy tuning survives /reload: the debug panel copies an edited entry into DragonChessDB.debug.enemy_tuning
-- (readable in WTF/.../SavedVariables/DragonChess.lua); on load it is laid over Assets.ENEMY.
local TUNING_FIELDS = { "display_id", "model_id", "cam_scale", "rot", "scale" }

function Assets.enemy_tuning_store(tuning, key)
	local e = Assets.ENEMY[key]
	if type(tuning) ~= "table" or e == nil then return false end
	local t = {}
	for i = 1, #TUNING_FIELDS do t[TUNING_FIELDS[i]] = e[TUNING_FIELDS[i]] end
	if e.display_id == nil then t.display_id = false end -- explicit: the model file is used alone
	if e.pos ~= nil then t.pos = { e.pos[1], e.pos[2], e.pos[3] } end
	tuning[key] = t
	return true
end

function Assets.enemy_tuning_apply(tuning)
	if type(tuning) ~= "table" then return end
	for key, t in pairs(tuning) do
		local e = Assets.ENEMY[key]
		if e ~= nil and type(t) == "table" then
			for i = 1, #TUNING_FIELDS do
				local f = TUNING_FIELDS[i]
				if type(t[f]) == "number" then e[f] = t[f] end
			end
			if t.display_id == false then e.display_id = nil end
			local p = t.pos
			if type(p) == "table" and type(p[1]) == "number" and type(p[2]) == "number" and type(p[3]) == "number" then
				e.pos = { p[1], p[2], p[3] }
			end
		end
	end
end

-- "STAGE_BG_FILE[stage] = id" line for a picked background.
function Assets.format_bg(stage, id, name)
	return ("STAGE_BG_FILE[%d] = %s -- %s"):format(stage or 1, tostring(id), tostring(name))
end

-- Sorted "SOUNDS.<slot>.channel = <name>" lines of every slot that is not on the default channel.
function Assets.format_channels()
	local out = {}
	for _, key in ipairs(Assets.sound_keys()) do
		local ch = Assets.SOUNDS[key].channel
		if ch ~= nil then out[#out + 1] = ("%s: channel = \"%s\""):format(key, ch) end
	end
	return out
end

ns.Assets = Assets
