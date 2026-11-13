-- W1-G1 class kits: core/classes.lua (9 classes x 12 spell variants of the 12 effect templates), Kit.for_class,
-- and the asset data of the variants (ui/assets.lua). A variant is a skin: the parity test plays one scripted fight
-- with every one of the 12 slots forced for each class kit and the default kit and demands an identical result.
local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "."
local H = dofile(dir .. "/helpers.lua")
local Stubs = dofile(dir .. "/wow_stubs.lua")
local T, ns = H.T, H.ns
local Kit, Classes = ns.Kit, ns.Classes
T.start("class_test")

local SLOTS = { "A1", "A2", "M1", "M2", "E1", "E2", "R1", "R2", "S1", "S2", "T1", "T2" }
local PRESENTATION = { id = true, template = true, name = true, icon = true, description = true, blurb = true }

-- slot index (1..12) of a kit entry: colour 0..5, tier 1 (skill) / 2 (ult)
local function slot_of(color, tier) return color * 2 + tier end

---------------------------------------------------------------- structure

T.case("structure: 9 classes x 12 slots, templates match the slot", function()
	T.eq(#Classes.ORDER, 9, "nine classes")
	local tokens = {}
	for _, id in ipairs(Classes.ORDER) do
		tokens[id] = true
		local cls = Classes[id]
		T.ok(type(cls) == "table" and cls.id == id and type(cls.name) == "string" and cls.name ~= "", id .. ": id + name")
		for color = 0, 5 do
			local entry = cls.kit[color]
			T.ok(type(entry) == "table" and #entry == 2, id .. ": colour " .. color .. " has skill + ult")
			for tier = 1, 2 do
				local ab = ns.Abilities[entry[tier]]
				T.ok(ab ~= nil, id .. ": ability exists " .. tostring(entry[tier]))
				if ab ~= nil then
					T.eq(ab.color, color, entry[tier] .. ": colour of the slot")
					T.eq(ab.tier, tier, entry[tier] .. ": tier of the slot")
					T.eq(ab.template, Kit.DEFAULT[color][tier], entry[tier] .. ": template of the slot")
				end
			end
		end
	end
	local extra = 0
	for k in pairs(Classes) do
		if k ~= "ORDER" and not tokens[k] then extra = extra + 1 end
	end
	T.eq(extra, 0, "no class outside ORDER")

	-- 108 distinct abilities: 12 canonical (each owned by exactly one class) + 96 variants
	local owners, canon, total = {}, 0, 0
	for _, id in ipairs(Classes.ORDER) do
		for color = 0, 5 do
			for tier = 1, 2 do
				local aid = Classes[id].kit[color][tier]
				owners[aid] = (owners[aid] or 0) + 1
			end
		end
	end
	for aid, n in pairs(owners) do
		total = total + 1
		T.eq(n, 1, aid .. ": owned by exactly one class")
		if ns.Abilities[aid].template == aid then canon = canon + 1 end
	end
	T.eq(total, 108, "108 distinct spells")
	T.eq(canon, 12, "12 canonical definitions, one per slot")
	local n_defs, n_variants = 0, 0
	for id, ab in pairs(ns.Abilities) do
		if type(ab) == "table" and ab.tier ~= nil then
			n_defs = n_defs + 1
			if ab.template ~= id then n_variants = n_variants + 1 end
		end
	end
	T.eq(n_defs, 108, "ns.Abilities holds exactly the kit spells")
	T.eq(n_variants, 96, "96 variants")
end)

T.case("W1-G2: Amber mapping, Mage M2 = Polymorph, the removed variants are gone", function()
	local want = {
		DRUID = { "rejuvenation", "healing_touch" }, PRIEST = { "renew", "greater_heal" },
		PALADIN = { "seal_of_light", "lay_on_hands" }, SHAMAN = { "healing_stream_totem", "chain_heal" },
		MAGE = { "conjure_food", "evocation" }, WARLOCK = { "drain_life", "healthstone" },
		WARRIOR = { "bloodthirst", "last_stand" }, HUNTER = { "mend_pet", "revive_pet" },
		ROGUE = { "first_aid", "healing_potion" },
	}
	for cid, ids in pairs(want) do
		T.eq(Classes[cid].kit[0][1], ids[1], cid .. ": A1")
		T.eq(Classes[cid].kit[0][2], ids[2], cid .. ": A2")
		T.eq(ns.Abilities[ids[1]].template, "rejuvenation", ids[1] .. ": HoT template")
		T.eq(ns.Abilities[ids[2]].template, "lay_on_hands", ids[2] .. ": heal template")
	end
	T.eq(Kit.DEFAULT[0][1], "rejuvenation", "default A1")
	T.eq(Kit.DEFAULT[0][2], "lay_on_hands", "default A2")
	T.eq(Classes.MAGE.kit[1][2], "polymorph", "Mage M2 = Polymorph")
	T.eq(ns.Abilities.polymorph.template, "mind_control", "Polymorph is a variant of Mind Control")
	T.eq(ns.Abilities.polymorph.tier, 2, "a ult")
	for _, gone in ipairs({ "battle_shout", "blessing_of_kings", "hunters_mark", "instant_poison", "power_infusion",
		"flametongue_weapon", "corruption", "mark_of_the_wild", "hemorrhage", "vampiric_embrace", "arcane_power" }) do
		T.eq(ns.Abilities[gone], nil, gone .. ": removed")
	end
	T.eq(ns.Abilities.rejuvenation.template, "rejuvenation", "Rejuvenation is canonical")
	T.eq(ns.Abilities.lay_on_hands.template, "lay_on_hands", "Lay on Hands is canonical")
	T.eq(ns.Combat.TIMED_STATUSES[2], "hot", "status lifesteal -> hot")
end)

T.case("Kit.for_class: class kit, fallbacks", function()
	for _, id in ipairs(Classes.ORDER) do
		local kit = Kit.for_class(id)
		T.eq(kit.class_id, id, id .. ": kit.class_id")
		for color = 0, 5 do
			T.eq(kit:get(color, 1).id, Classes[id].kit[color][1], id .. ": skill " .. color)
			T.eq(kit:get(color, 2).id, Classes[id].kit[color][2], id .. ": ult " .. color)
		end
	end
	for _, bad in ipairs({ "NOPE", "ORDER", "" }) do
		local kit = Kit.for_class(bad)
		T.eq(kit.class_id, nil, "unknown class '" .. bad .. "' -> default kit")
		T.eq(kit:get(3, 1).id, "flamestrike", "default Ruby skill")
	end
	local nilkit = Kit.for_class(nil)
	T.eq(nilkit.class_id, nil, "nil class -> default kit")
	T.eq(Kit.default().class_id, nil, "Kit.default has no class")
	T.ok(Kit.for_class("MAGE"):get(1, 1) ~= ns.Abilities[Classes.MAGE.kit[1][1]], "kit holds copies")
end)

T.case("field whitelist: a variant changes presentation keys only", function()
	for id, v in pairs(ns.Abilities) do
		if type(v) == "table" and v.tier ~= nil then
			local tpl = ns.Abilities[v.template]
			T.ok(tpl ~= nil and tpl.template == tpl.id, id .. ": template is a canonical definition")
			if tpl ~= nil and v ~= tpl then
				T.eq(v.template, tpl.id, id .. ": template id")
				T.eq(v.icon, id, id .. ": icon key = id")
				T.ok(type(v.name) == "string" and v.name ~= "", id .. ": name")
				for k, val in pairs(v) do
					if not PRESENTATION[k] then
						T.ok(rawequal(val, tpl[k]), id .. "." .. tostring(k) .. " is the template's (number / execute / helper)")
					end
				end
				for k in pairs(tpl) do
					T.ok(v[k] ~= nil, id .. ": keeps template key " .. tostring(k))
				end
				T.ok(type(v.blurb) == "string" and v.blurb ~= "", id .. ": has a blurb")
			end
		end
	end
end)

T.case("texts: every blurb and description resolves its placeholders", function()
	local bad, longest = {}, 0
	for id, v in pairs(ns.Abilities) do
		if type(v) == "table" and v.tier ~= nil then
			local blurb = Kit.format_text(v, v.blurb)
			local desc = Kit.format_text(v, v.description)
			if blurb:find("{", 1, true) or desc:find("{", 1, true) then bad[#bad + 1] = id end
			-- length in characters (the arrows / dots are multi-byte)
			local len = #blurb:gsub("[\128-\191]", "")
			if len > longest then longest = len end
			T.ok(len <= 40, id .. ": blurb fits the banner (" .. len .. " chars)")
		end
	end
	T.ok(#bad == 0, "unresolved placeholders: " .. table.concat(bad, ","))
	T.ok(longest > 0, "blurbs measured")
end)

T.case("W1-G4: every Power Word: Shield skin names the stack cap", function()
	local n = 0
	for id, v in pairs(ns.Abilities) do
		if type(v) == "table" and v.template == "power_word_shield" then
			n = n + 1
			local desc = Kit.format_text(v, v.description)
			T.ok(desc:find("up to " .. ns.Combat.SHIELD_MAX_STACKS .. " stacks", 1, true) ~= nil, id .. ": " .. desc)
		end
	end
	T.ok(n >= 9, "all skins checked (" .. n .. ")")
end)

T.case("W1-G3: every Fire Shield skin shows the bonus and the 12 s window", function()
	local n = 0
	for id, v in pairs(ns.Abilities) do
		if type(v) == "table" and v.template == "fire_shield" then
			n = n + 1
			local desc = Kit.format_text(v, v.description)
			T.ok(desc:find("+100", 1, true) ~= nil and desc:find("12s", 1, true) ~= nil, id .. ": " .. desc)
			T.eq(v.reflect_bonus, 100, id .. " reflect_bonus (inherited from the template)")
		end
	end
	T.eq(n, 9, "template + eight skins")
end)

---------------------------------------------------------------- forced parity

-- Plays one scripted fight with `kit` (nil = default) and returns a string that must not depend on the kit:
-- every sim / combat event (presentation fields of ability_triggered stripped), the numeric hud_state and the
-- RNG states. All 12 slots are forced one after the other, with the enemy attacking in between.
local EVENTS = {
	"match_resolved", "gems_cleared", "swap_rejected", "board_settled", "board_shuffled", "ability_activated",
	"ability_gem_spawned", "gems_cleared_by_effect", "junk_spawned", "gravity_slow_changed", "need_ability_drain",
	"abilities_drained", "gem_created", "gem_removed", "flash", "gameplay_unpaused", "swap_accepted",
	"ability_triggered", "attack_blocked", "attack_reflected", "damage_dealt", "enemy_damaged", "enemy_defeated",
	"enemy_health_changed", "enemy_immune", "fight_started", "heal_blocked", "heal_lost", "player_damaged", "player_healed",
	"player_health_changed", "run_lost", "score_awarded", "score_changed", "status_changed",
	"enemy_ability_executed", "enemy_mirror_changed", "enemy_phase_changed", "enemy_status_changed", "enemy_windup",
}
local STRIP = { id = true, icon = true, toast = true, blurb = true } -- ability_triggered presentation fields

local function ser(v, depth, strip)
	local t = type(v)
	if t == "number" then return ("%.6g"):format(v) end
	if t == "string" or t == "boolean" or t == "nil" then return tostring(v) end
	if t == "function" then return "fn" end
	if depth > 1 then return "T" end -- nested tables: scalar fields of the first two levels only
	local keys = {}
	for k in pairs(v) do
		if not (strip and STRIP[k]) then keys[#keys + 1] = k end
	end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	local parts = {}
	for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. ser(v[k], depth + 1, strip) end
	return "{" .. table.concat(parts, ",") .. "}"
end

local function drain_like_pass(sim, c)
	sim:spawn(function()
		sim.awaiting_drain, sim.defer_gravity = true, true
		c:_drain_ability_queue()
		sim.awaiting_drain, sim.defer_gravity = false, false
		sim:_animate_gravity_and_spawn()
		sim:mark_resolve_needed()
	end)
end

local function play(kit)
	local b = H.board(H.grid(nil), { seed = 11 })
	local sim = ns.Sim.new({ board = b })
	local c = ns.Combat.new({ sim = sim, seed = 11, kit = kit })
	local log = {}
	for _, name in ipairs(EVENTS) do
		sim:on(name, function(...)
			local args = { ... }
			local parts = {}
			for i = 1, select("#", ...) do parts[i] = ser(args[i], 0, name == "ability_triggered") end
			log[#log + 1] = ("%.4f %s %s"):format(sim.now, name, table.concat(parts, " "))
		end)
	end
	-- an enemy that hits every 2.5 s so shield stacks / fire shield / HoT / stun all matter
	c:start_fight(H.enemy_def({ hp = 1000000, dmg = 200, cooldown = 2.5 }))
	local forced = 0
	for color = 0, 5 do
		for tier = 1, 2 do
			local info = {
				col = 1 + (color % 5) + tier, row = 2 + (color % 4), gem_type = color, tier = tier,
				source = "chain", partner_color = (color + 2) % 6, match_length = 3 + tier, is_bomb = false,
			}
			c.queue[#c.queue + 1] = info
			drain_like_pass(sim, c)
			H.run(sim, 1 / 60, 120)
			H.tick_to(sim, sim.now + 3.2) -- let the enemy hit / statuses run
			forced = forced + 1
		end
	end
	-- W1-G2 extras: a HoT that is extended, one that runs across a fight boundary, a heal ult under Heal Block
	c.player_health = 3000
	for _ = 1, 2 do
		c.queue[#c.queue + 1] = { col = 2, row = 2, gem_type = 0, tier = 1, source = "chain", partner_color = -1, match_length = 3, is_bomb = false }
		drain_like_pass(sim, c)
		H.run(sim, 1 / 60, 120)
		H.tick_to(sim, sim.now + 1.2) -- the second cast extends the first
	end
	H.tick_to(sim, sim.now + 3.3)
	c:deal_damage_to_enemy(c.enemy.current_health) -- the kill pauses gameplay: the HoT waits
	H.tick_to(sim, sim.now + 4)
	c:start_fight(H.enemy_def({ hp = 1000000, dmg = 200, cooldown = 2.5 })) -- ... and goes on in the next fight
	H.tick_to(sim, sim.now + 8)
	c:apply_heal_block(6)
	c.queue[#c.queue + 1] = { col = 3, row = 3, gem_type = 0, tier = 2, source = "chain", partner_color = -1, match_length = 3, is_bomb = false }
	drain_like_pass(sim, c)
	H.run(sim, 1 / 60, 120)
	H.tick_to(sim, sim.now + 9) -- blocked ticks, then free ones
	forced = forced + 3
	H.tick_to(sim, sim.now + 12)
	local hud = c:hud_state({})
	hud.intents = nil -- enemy ability tables
	log[#log + 1] = "hud " .. ser(hud, 0, false)
	log[#log + 1] = "rng_combat " .. ser(c.rng_combat:get_state(), 0, false)
	log[#log + 1] = "rng_refill " .. ser(b.rng_refill:get_state(), 0, false)
	log[#log + 1] = "rng_effects " .. ser(b.rng_effects:get_state(), 0, false)
	log[#log + 1] = "forced " .. forced
	local ok, err = b:check_integrity(true)
	T.ok(ok, "board integrity: " .. tostring(err))
	return table.concat(log, "\n"), #log
end

T.case("forced parity: every class plays the default kit's fight, all 12 slots forced", function()
	local base, n = play(nil)
	T.ok(n > 200, "the scripted fight produced events: " .. n)
	T.ok(base:find("ability_triggered", 1, true) ~= nil, "abilities fired")
	local _, trig = base:gsub("ability_triggered", "")
	T.ok(trig >= 15, "all 12 slots and the three Amber extras triggered (" .. trig .. ")")
	T.ok(base:find("heal_lost", 1, true) ~= nil, "the extras lost a heal to Heal Block")
	T.ok(base:find("player_healed 50 hot", 1, true) ~= nil, "HoT ticks healed")
	T.eq(play(nil), base, "the scripted fight is deterministic")
	for _, id in ipairs(Classes.ORDER) do
		local log = play(Kit.for_class(id))
		if log ~= base then
			-- first differing line, for the failure message
			local a, b = {}, {}
			for l in (log .. "\n"):gmatch("(.-)\n") do a[#a + 1] = l end
			for l in (base .. "\n"):gmatch("(.-)\n") do b[#b + 1] = l end
			local at = 1
			while a[at] == b[at] and at <= #a do at = at + 1 end
			T.ok(false, id .. ": diverges from the default kit at line " .. at .. ": '" .. tostring(a[at]) .. "' vs '" .. tostring(b[at]) .. "'")
		else
			T.ok(true, id .. ": identical fight")
		end
	end
end)

---------------------------------------------------------------- assets

local function load_assets()
	local W = Stubs.new()
	local ans = H.loader.load()
	W.load(H.loader.wow_dir() .. "/ui/assets.lua", "DragonChess", ans)
	return ans.Assets, ans
end

T.case("assets: every spell has an icon, a sound and an effect; variants inherit from their template", function()
	local A, ans = load_assets()
	local n = 0
	for id, ab in pairs(ans.Abilities) do
		if type(ab) == "table" and ab.tier ~= nil then
			n = n + 1
			T.ok(type(A.ICONS[id]) == "string" and A.ICONS[id]:match("^[%w_]+$"), id .. ": icon file name")
			local skey = A.ABILITY_KEY[id]
			local slot = skey and A.SOUNDS[skey]
			T.ok(slot ~= nil and type(slot.file) == "number", id .. ": sound slot with a file id")
			T.eq(slot ~= nil and slot.key == true, ab.tier == 2, id .. ": ults are key sounds")
			local fx = A.FX[id]
			T.ok(fx ~= nil and type(fx.m2) == "number" and type(fx.at) == "string", id .. ": effect with a model and a target")
			if ab.template ~= id and slot ~= nil and fx ~= nil then
				local tslot, tfx = A.SOUNDS["ab_" .. ab.template], A.FX[ab.template]
				T.ok(rawequal(slot.fallback, tslot), id .. ": sound falls back to the template slot")
				T.eq(fx.at, tfx.at, id .. ": effect target is the template's")
				T.eq(fx.size, tfx.size, id .. ": effect size is the template's")
				T.eq(fx.duration, tfx.duration, id .. ": effect duration is the template's")
			end
		end
	end
	T.eq(n, 108, "108 spells checked")
	T.eq(A.SOUNDS.ab_hammer_of_justice.file, 569344, "canonical Hammer of Justice: fistofjustice")
	T.eq(A.SOUNDS.ab_kidney_shot.file, 569110, "Kidney Shot keeps kidneyshot")
	T.eq(A.SOUNDS.ab_whirlwind.file, 568519, "canonical Whirlwind: whirlwindshort")
	T.ok(A.FX.feign_death.m2 == A.FX.power_word_shield.m2, "Feign Death inherits the template effect")
end)

T.case("assets: a variant sound that does not play falls back to the template's file", function()
	local W = Stubs.new()
	local ans = H.loader.load()
	W.load(H.loader.wow_dir() .. "/ui/assets.lua", "DragonChess", ans)
	local A = ans.Assets
	local vfile, tfile = A.SOUNDS.ab_thunder_clap.file, A.SOUNDS.ab_arcane_explosion.file
	T.ok(vfile ~= tfile, "variant and template sounds differ")
	local orig = W.stubs.PlaySoundFile
	W.stubs.PlaySoundFile = function(id, channel)
		if id == vfile then return false end -- the client does not know this file
		return orig(id, channel)
	end
	local n = #W.sounds
	T.ok(A.play("ab_thunder_clap", nil, true), "play reports a started sound")
	T.eq(W.sounds[n + 1], tfile, "the template's file played instead")
	T.eq(#W.sounds, n + 1, "exactly one sound")
	W.stubs.PlaySoundFile = orig
	n = #W.sounds
	A.play("ab_thunder_clap", nil, true)
	T.eq(W.sounds[n + 1], vfile, "a file that exists plays the variant's own sound")
end)

T.case("assets: id and icon hygiene", function()
	local A, ans = load_assets()
	local enemy_ids = ans.EnemyData.abilities
	local function non_ability_key(k)
		return k == "bomb" or k == "unknown" or k:find("^kind_") ~= nil or k:find("^status_") ~= nil
			or k:find("^enemy_") ~= nil or enemy_ids[k] ~= nil
	end
	for k in pairs(A.ICONS) do
		T.ok(ans.Abilities[k] ~= nil or non_ability_key(k), "icon key is a spell or a known glyph: " .. k)
	end
	for id, ab in pairs(ans.Abilities) do
		if type(ab) == "table" and ab.tier ~= nil then
			T.ok(not non_ability_key(id), id .. ": variant id is disjoint from enemy ability ids and glyph keys")
		end
	end
	-- a kit icon must not look like a glyph of another meaning. status_shield / status_fire_shield /
	-- status_hot are the default-kit spells' own icons (the strip shows the class's spell instead).
	local KIT_STATUS = { status_shield = true, status_fire_shield = true, status_hot = true }
	local glyph_files = {}
	for k, file in pairs(A.ICONS) do
		if (k:find("^kind_") or k:find("^status_") or k:find("^enemy_") or k == "bomb") and not KIT_STATUS[k] then
			glyph_files[file] = k
		end
	end
	for id, ab in pairs(ans.Abilities) do
		if type(ab) == "table" and ab.tier ~= nil then
			T.ok(glyph_files[A.ICONS[id]] == nil, id .. ": icon " .. tostring(A.ICONS[id]) .. " clashes with glyph " .. tostring(glyph_files[A.ICONS[id]]))
		end
	end
	for _, k in ipairs({ "kind_curse", "status_curse" }) do T.eq(A.ICONS[k], "Spell_Shadow_CurseOfMannoroth", k) end
	T.eq(A.ICONS.kind_stagger, "Ability_Smash", "kind_stagger")
	T.eq(A.ICONS.kind_sand, "Spell_Nature_Earthquake", "kind_sand")
	T.eq(A.ICONS.bomb, "INV_Misc_Bomb_04", "bomb")
	-- within one class all 12 icons are distinct
	for _, cid in ipairs(Classes.ORDER) do
		local seen, dup = {}, {}
		for color = 0, 5 do
			for tier = 1, 2 do
				local file = A.ICONS[Classes[cid].kit[color][tier]]
				if seen[file] then dup[#dup + 1] = file end
				seen[file] = true
			end
		end
		T.ok(#dup == 0, cid .. ": 12 distinct icons (duplicates: " .. table.concat(dup, ",") .. ")")
	end
	-- the six corrected canonical icons
	local want = {
		hammer_of_justice = "Spell_Holy_SealOfMight", mind_control = "Spell_Shadow_ShadowWordDominate",
		arcane_explosion = "Spell_Nature_WispSplode", whirlwind = "Ability_Whirlwind",
		flamestrike = "Spell_Fire_SelfDestruct", rain_of_fire = "Spell_Shadow_RainOfFire",
	}
	for id, file in pairs(want) do T.eq(A.ICONS[id], file, id .. ": corrected icon") end
end)

T.case("assets: M1 / S2 spells carry status_text and a hold effect that exists", function()
	local A, ans = load_assets()
	local seen = 0
	for _, cid in ipairs(Classes.ORDER) do
		for _, color in ipairs({ 1, 4 }) do
			local id = Classes[cid].kit[color][color == 1 and 1 or 2]
			local fx = A.FX[id]
			seen = seen + 1
			T.ok(type(fx.status_text) == "string" and fx.status_text ~= "", id .. ": status_text")
			T.ok(type(fx.hold_fx) == "string" and A.FX[fx.hold_fx] ~= nil and A.FX[fx.hold_fx].at == "enemy", id .. ": hold_fx names an enemy FX key")
		end
	end
	T.eq(seen, 18, "18 M1 / S2 spells")
	T.eq(A.FX.frost_nova.status_text, "FROZEN", "Frost Nova")
	T.eq(A.FX.frost_shock.hold_fx, "freeze", "Frost Shock holds the ice block")
	T.eq(A.FX.freezing_trap.status_text, "FROZEN", "Freezing Trap")
	T.eq(A.FX.silence.status_text, "SILENCED", "Silence")
	T.eq(A.FX.silence.hold_fx, "stun_stars", "Silence holds the stun swirl")
	T.eq(A.FX.entangling_roots.status_text, "ROOTED", "Entangling Roots")
	T.eq(A.FX.entangling_roots.hold_fx, "roots_hold", "Entangling Roots holds the roots")
	T.eq(A.FX.concussion_blow.status_text, "STUNNED", "Concussion Blow")
	T.eq(A.FX.hammer_of_justice.hold_fx, "stun_stars", "Hammer of Justice")
	T.eq(A.FX.concussion_blow.m2, 166890, "Concussion Blow: slam_impact_chest")
	T.eq(A.SOUNDS.ab_insect_swarm.max, 1.2, "Insect Swarm sound cut at 1.2 s")
end)

T.done()
