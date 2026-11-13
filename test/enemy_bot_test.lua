-- Bot acceptance (W0-G2a): for each of the 10 enemies, N seeds, the scripted bot (first legal
-- move every PACE sim seconds, like fight_bot_test) plays in god mode (the player can't die;
-- every enemy mechanic still runs). Pass = the enemy reaches 0 HP within CAP sim seconds, the
-- board never goes REST_LIMIT seconds without coming to rest (no stuck state), the grid stays
-- consistent, and data/enemies.lua is never mutated. Env: BOT_SEEDS (default 5), BOT_VERBOSE=1.
local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "."
local H = dofile(dir .. "/helpers.lua")
local T, ns = H.T, H.ns
local Sim, Combat, Match, Data = ns.Sim, ns.Combat, ns.Match, ns.EnemyData
T.start("enemy_bot_test")

local SEEDS = tonumber(os.getenv("BOT_SEEDS") or "") or 5
local PACE = 1.5 -- the Godot mouse pace (as fight_bot_test); the bot is no strategist
local CAP = 600 -- sim seconds per fight
local REST_LIMIT = 30 -- "stuck" = the board didn't come to rest for this long
local DT = 1 / 30 -- <= Timings.MAX_DT
local INTEGRITY_EVERY = 15 -- ticks

local function deep_copy(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do out[k] = deep_copy(v) end -- order irrelevant (copy)
	return out
end

local function deep_equal(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	for k, v in pairs(a) do
		if not deep_equal(v, b[k]) then return false end
	end
	for k in pairs(b) do
		if a[k] == nil then return false end
	end
	return true
end

-- Plays one fight; returns result table.
local function play(def, seed)
	local sim = Sim.new({ seed = seed })
	local c = Combat.new({ sim = sim, seed = seed })
	c.god_mode = true
	local r = { phases = 0, mirrors = 0, aegis = 0, executed = 0, integrity = true }
	c:on("enemy_phase_changed", function() r.phases = r.phases + 1 end)
	c:on("enemy_mirror_changed", function(active) if active then r.mirrors = r.mirrors + 1 end end)
	c:on("enemy_ability_executed", function() r.executed = r.executed + 1 end)
	c:on("enemy_immune", function() r.aegis = r.aegis + 1 end)
	c:start_fight(def)

	local next_swap, ticks, last_rest = PACE, 0, 0
	while sim.now < CAP and not c.fight_over do
		if sim.now >= next_swap and c:can_player_swap() == "" then
			local c1, r1, c2, r2 = Match.find_possible_move(sim.board)
			local res = c1 and c:try_swap(sim.board:get(c1, r1), sim.board:get(c2, r2)) or "none"
			next_swap = sim.now + (res == "ok" and PACE or 0.1)
		end
		sim:tick(DT)
		ticks = ticks + 1
		if sim:is_at_rest() or sim:is_gameplay_paused() then last_rest = sim.now end
		if sim.now - last_rest > REST_LIMIT then
			r.stuck = true
			break
		end
		if ticks % INTEGRITY_EVERY == 0 and not sim.board:check_integrity(false) then r.integrity = false end
	end
	r.time, r.killed, r.hp = sim.now, c.fight_over, c.enemy.current_health
	return r
end

local before = deep_copy(Data.list)
local total_t, worst = 0, 0
local seen = { phases = 0, mirrors = 0 }
for _, def in ipairs(Data.list) do
	for s = 1, SEEDS do
		local seed = 4000 + 17 * s
		local r = play(def, seed)
		total_t = total_t + r.time
		if r.time > worst then worst = r.time end
		seen.phases = seen.phases + r.phases
		seen.mirrors = seen.mirrors + r.mirrors
		local label = ("%s seed %d"):format(def.id, seed)
		if os.getenv("BOT_VERBOSE") == "1" then
			print(("%-15s seed %d: %s in %6.1f s, enemy attacks %d, phases %d, mirrors %d, immune bounces %d"):format(
				def.id, seed, r.killed and "dead" or "ALIVE", r.time, r.executed, r.phases, r.mirrors, r.aegis))
		end
		T.ok(r.killed, label .. ": enemy dead within " .. CAP .. " s (hp left " .. tostring(r.hp) .. ")")
		T.ok(not r.stuck, label .. ": no stuck state")
		T.ok(r.integrity, label .. ": grid consistent")
	end
end
T.ok(seen.phases >= 2 * SEEDS, "Nefarian's phases fired (" .. seen.phases .. ")")
T.ok(seen.mirrors >= SEEDS, "Mirror Shields were cast (" .. seen.mirrors .. ")")
T.ok(deep_equal(before, Data.list), "data/enemies.lua unchanged by all fights")
if os.getenv("BOT_VERBOSE") == "1" then
	print(("total sim time %.0f s, slowest fight %.0f s"):format(total_t, worst))
end

T.done()
