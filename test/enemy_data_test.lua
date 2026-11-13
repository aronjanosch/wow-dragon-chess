-- data/enemies.lua: shape, ladder order, the cycle-overlap invariant, and the golden table
-- dumped once from the Godot .tres (tools/export_enemy_golden.gd ->
-- test/golden_enemies.lua; the golden part is skipped silently when the file is absent).
local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "."
local H = dofile(dir .. "/helpers.lua")
local T, ns = H.T, H.ns
local Enemy, Data, K = ns.Enemy, ns.EnemyData, ns.EnemyAbilities
T.start("enemy_data_test")

local LADDER = { "hellhound", "gordok_ogre", "basilisk_matriarch", "forest_troll", "harpy", "hakkar",
	"qiraji_scarab", "anubisath_sentinel", "ouro", "nefarian" }

-- W0-G2c: the Godot ids the golden table (and the Godot .tres numbers) are keyed by. Numbers are compared
-- through this map; names are NOT compared (the roster was renamed to WoW Classic).
local GODOT_ID = {
	hellhound = "cerberus_puppy", gordok_ogre = "cyclops", basilisk_matriarch = "medusa", forest_troll = "troll",
	harpy = "valkyrie", hakkar = "thor", qiraji_scarab = "mummy", anubisath_sentinel = "anubis",
	ouro = "sphinx", nefarian = "world_dragon",
}

-- Godot script class -> data `kind`.
local KIND_OF_TYPE = {
	EnemyAbility = "plain", MultiHitAbility = "flurry", StunAbility = "stagger",
	HealBlockAbility = "heal_block", ChargeNukeAbility = "nuke", SpawnJunkAbility = "junk",
	DamageDebuffAbility = "curse", HealSelfAbility = "heal", SpellImmunityAbility = "aegis",
	MirrorShieldAbility = "mirror", BoardSlowAbility = "sand",
}

-- Every ability of an enemy (base rotation + phases), in order.
local function all_abilities(def)
	local out = {}
	for _, a in ipairs(def.rotation) do out[#out + 1] = a end
	for _, p in ipairs(def.phases or {}) do
		for _, a in ipairs(p.rotation) do out[#out + 1] = a end
	end
	return out
end

T.case("roster shape and ladder order", function()
	T.eq(#Data.list, 10, "10 enemies")
	for i, id in ipairs(LADDER) do
		T.eq(Data.list[i].id, id, "ladder position " .. i)
		T.ok(Data.by_id[id] == Data.list[i], "by_id " .. id)
		T.ok(Enemy.STUBS[id] == Data.list[i], "Enemy.STUBS aliases the data: " .. id)
	end
	for _, legacy in ipairs({ "dragon", "slime", "slime_king", "goblin" }) do
		T.ok(Data.by_id[legacy] == nil, "legacy enemy skipped: " .. legacy)
	end
	T.ok(Data.abilities.grid_rip == nil, "grid_rip not ported")
	local bosses = 0
	for _, def in ipairs(Data.list) do
		T.eq(def.windup, 8 / 12, def.id .. " wind-up constant 8/12")
		T.eq(def.display_id, 1000, def.id .. " placeholder display id")
		T.ok(GODOT_ID[def.id] ~= nil, def.id .. " maps to a Godot id")
		T.ok(type(def.display) == "string", def.id .. " display key")
		T.ok(#def.rotation > 0, def.id .. " has a rotation")
		if def.is_boss then bosses = bosses + 1 end
		for _, a in ipairs(all_abilities(def)) do
			T.ok(K[a.kind] ~= nil, a.id .. " kind " .. tostring(a.kind) .. " has a handler")
			T.eq(a.icon, a.id, a.id .. " icon key = id")
			T.ok(type(a.is_special) == "boolean", a.id .. " effective is_special")
			T.ok(a.damage_max >= a.damage_min and a.cooldown > 0, a.id .. " sane ranges")
		end
	end
	T.eq(bosses, 4, "4 bosses (3 stage bosses + Nefarian)")
	-- shared ability tables: Nefarian reuses Wing Buffet in a phase
	local wd = Data.by_id.nefarian
	T.ok(wd.rotation[1] == wd.phases[1].rotation[3], "shared ability table, not a copy")
	T.eq(wd.phases[1].hp_fraction, 0.66, "phase 1 at 66 % (script default, not in the .tres)")
	T.eq(wd.phases[2].hp_fraction, 0.33, "phase 2 at 33 %")
end)

T.case("effective is_special and kind params", function()
	local A = Data.abilities
	T.eq(A.hellhound_bite.is_special, false, "plain hit not special")
	T.eq(A.ouro_blast.is_special, true, "authored special plain hit")
	T.eq(A.nefarian_strike.is_special, true, "authored special plain hit (Nefarian)")
	T.eq(A.harpy_flurry.is_special, true, "subclasses are always special")
	T.eq(A.harpy_flurry.hit_interval, 0.12, "hit_interval script default")
	T.eq(A.ogre_smash.stun_duration, 2.5, "stagger duration")
	T.eq(A.scarab_web.junk_count, 3, "junk_count script default")
	T.eq(A.sentinel_curse.damage_multiplier, 0.7, "curse multiplier")
	T.eq(A.hakkar_aegis.duration, 7.0, "aegis duration")
	T.eq(A.ouro_sandstorm.factor, 0.3, "sandstorm factor")
	T.eq(A.matriarch_mirror.break_damage, 500, "mirror break damage")
end)

T.case("data invariant: windup + execute max < every cooldown (the attack overlap can't occur)", function()
	local worst, min_cd = 0, math.huge
	for _, def in ipairs(Data.list) do
		for _, a in ipairs(all_abilities(def)) do
			local t = def.windup + Enemy.execute_time_max(a)
			if t > worst then worst = t end
			if a.cooldown < min_cd then min_cd = a.cooldown end
		end
	end
	T.ok(worst < min_cd, ("max(windup + execute) %.3f < min(cooldown) %.3f"):format(worst, min_cd))
	T.ok(Enemy.execute_time_max(Data.abilities.harpy_flurry) == 4 * 0.12 + 0, "flurry max: (5 - 1) gaps")
	T.ok(math.abs(Enemy.execute_time_expected(Data.abilities.harpy_flurry) - 3.5 * 0.12) < 1e-9, "flurry expected 3.5 gaps")
	T.ok(math.abs(Enemy.execute_time_max(Data.abilities.scarab_web) - 0.62) < 1e-9, "junk telegraph 0.62 s")
end)

-- W1-G3: the three fast attackers differ from the Godot golden on purpose (golden_enemies.lua stays untouched).
-- rotation = the expected rotation in order; { from = golden index, set = fields replaced } or { new = all fields }.
-- Everything not listed here (HP, boss flag, weakness, phases, every other field) still compares against the golden.
local W1_OVERRIDES = {
	hellhound = { rotation = {
		{ from = 1, set = { damage_min = 75, damage_max = 95, cooldown = 1.4 } },
	} },
	harpy = { rotation = {
		{ new = { type = "EnemyAbility", is_special = false, damage_min = 70, damage_max = 92, cooldown = 1.6 } },
		{ new = { type = "EnemyAbility", is_special = false, damage_min = 70, damage_max = 92, cooldown = 1.6 } },
		{ from = 1, set = { damage_min = 52, damage_max = 72, cooldown = 5.5 } },
	} },
	qiraji_scarab = { rotation = {
		{ from = 1, set = {} }, -- Web Spray unchanged
		{ from = 2, set = { damage_min = 70, damage_max = 89, cooldown = 1.6 } },
		{ from = 2, set = { damage_min = 70, damage_max = 89, cooldown = 1.6 } },
		{ from = 2, set = { damage_min = 70, damage_max = 89, cooldown = 1.6 } },
	} },
}

-- The expected golden-style rotation of `id`: the override list applied on the golden rotation.
local function expected_rotation(id, golden_rotation)
	local o = W1_OVERRIDES[id]
	if o == nil then return golden_rotation end
	local out = {}
	for i, e in ipairs(o.rotation) do
		local want = {}
		if e.new ~= nil then
			for k, v in pairs(e.new) do want[k] = v end
		else
			for k, v in pairs(golden_rotation[e.from]) do want[k] = v end
			for k, v in pairs(e.set) do want[k] = v end
		end
		want.name = want.name or ("W1 " .. id .. " " .. i)
		out[i] = want
	end
	return out
end

T.case("W1-G3: fast attackers keep their old DPS (+-2 %, difficulty 1, old values hard-coded)", function()
	local Run = ns.Run
	-- DPS of a rotation = average damage per cycle / (sum of cooldowns + wind-up per ability + expected execute time)
	local function dps(def)
		local d = Run.scale_def(def, 1)
		local dmg, time = 0, 0
		for _, a in ipairs(d.rotation) do
			local hits = a.kind == "flurry" and (a.hit_count_min + a.hit_count_max) / 2 or 1
			dmg = dmg + (a.damage_min + a.damage_max) / 2 * hits
			time = time + a.cooldown + d.windup + Enemy.execute_time_expected(a)
		end
		return dmg / time
	end
	local W = 8 / 12
	local old = {
		hellhound = { windup = W, rotation = {
			{ kind = "plain", damage_min = 120, damage_max = 160, cooldown = 2.5 } } },
		harpy = { windup = W, rotation = {
			{ kind = "flurry", damage_min = 80, damage_max = 110, cooldown = 9.0, hit_count_min = 4, hit_count_max = 5,
				hit_interval = 0.12 } } },
		qiraji_scarab = { windup = W, rotation = {
			{ kind = "junk", damage_min = 0, damage_max = 0, cooldown = 6.0, junk_count = 3 },
			{ kind = "plain", damage_min = 200, damage_max = 260, cooldown = 5.0 } } },
	}
	for id, def in pairs(old) do
		def.max_health = 1 -- scale_def needs one
		local want, got = dps(def), dps(Data.by_id[id])
		T.ok(math.abs(got / want - 1) <= 0.02, ("%s DPS %.1f vs old %.1f (%+.2f %%)"):format(id, got, want, (got / want - 1) * 100))
	end
	T.ok(Data.abilities.harpy_rake ~= nil and Data.abilities.harpy_rake.icon == "harpy_rake", "Talon Rake exists")
	local hr = Data.by_id.harpy.rotation
	T.ok(hr[1] == hr[2] and hr[1] == Data.abilities.harpy_rake and hr[3] == Data.abilities.harpy_flurry, "harpy: rake, rake, flurry")
	local sr = Data.by_id.qiraji_scarab.rotation
	T.ok(sr[1] == Data.abilities.scarab_web and sr[2] == sr[3] and sr[3] == sr[4], "scarab: web, bite, bite, bite")
end)

T.case("golden table from Godot (.tres)", function()
	local path = dir .. "/golden_enemies.lua"
	local f = io.open(path)
	if f == nil then return end -- skipped silently when absent
	f:close()
	local golden = dofile(path)
	local n = 0
	for _, id in ipairs(LADDER) do
		local g, def = golden[GODOT_ID[id]], Data.by_id[id]
		T.ok(g ~= nil, "golden has " .. id .. " (Godot " .. tostring(GODOT_ID[id]) .. ")")
		if g ~= nil then
			n = n + 1
			T.eq(def.max_health, g.max_health, id .. " HP")
			T.eq(def.is_boss, g.is_boss, id .. " is_boss")
			T.eq(def.weak_to_color, g.weak_to_color, id .. " weakness")
			local function same_rotation(have, want, label)
				T.eq(#have, #want, label .. " length")
				for i = 1, math.min(#have, #want) do
					local a, w = have[i], want[i]
					local l = label .. "[" .. i .. "] " .. tostring(w.name)
					T.eq(a.kind, KIND_OF_TYPE[w.type], l .. " kind")
					for k, v in pairs(w) do -- compare every exported key (order irrelevant)
						if k ~= "type" and k ~= "name" then T.eq(a[k], v, l .. " " .. k) end
					end
				end
			end
			same_rotation(def.rotation, expected_rotation(id, g.rotation), id .. " rotation")
			local dp = def.phases or {}
			T.eq(#dp, #g.phases, id .. " phase count")
			for i = 1, math.min(#dp, #g.phases) do
				T.eq(dp[i].hp_fraction, g.phases[i].hp_fraction, id .. " phase " .. i .. " hp_fraction")
				same_rotation(dp[i].rotation, g.phases[i].rotation, id .. " phase " .. i)
			end
		end
	end
	T.eq(n, 10, "all 10 enemies compared")
end)

T.done()
