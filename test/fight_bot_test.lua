-- A tiny scripted bot plays one seeded fight against the stub enemy (Hellhound)
-- headless and prints the combat event log (W0-G1 acceptance). Not a
-- probe port: it swaps the first legal move every 1.5 s of sim time (the Godot
-- mouse pace). Checks: the fight ends, the grid stays consistent, and the same
-- seed gives the same log. Env: BOT_SEED, BOT_QUIET=1.
local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "."
local H = dofile(dir .. "/helpers.lua")
local T, ns = H.T, H.ns
local Sim, Combat, Match, Enemy = ns.Sim, ns.Combat, ns.Match, ns.Enemy
T.start("fight_bot_test")

local SEED = tonumber(os.getenv("BOT_SEED") or "") or 20261004
local PACE = 1.5
local LIMIT = 600

local function play(seed)
	local sim = Sim.new({ seed = seed })
	local c = Combat.new({ sim = sim, seed = seed })
	local log = {}
	local function add(s) log[#log + 1] = ("%7.3f %s"):format(sim.now, s) end
	c:on("fight_started", function(e) add("fight " .. e.name .. " hp=" .. e.max_health) end)
	c:on("damage_dealt", function(a, t, src) add(("dmg %d %s c%d"):format(a, src, t)) end)
	c:on("ability_triggered", function(i) add("ability " .. i.toast .. " @" .. i.col .. "," .. i.row) end)
	c:on("enemy_ability_executed", function(a) add("enemy " .. a.name) end)
	c:on("player_damaged", function(a) add("player -" .. a .. " hp=" .. c.player_health) end)
	c:on("attack_blocked", function() add("blocked") end)
	c:on("attack_reflected", function(a) add("reflected " .. a) end)
	c:on("player_healed", function(a) add("healed " .. a) end)
	c:on("enemy_defeated", function() add("enemy defeated, score=" .. c.score) end)
	c:on("run_lost", function() add("run lost") end)
	c:start_fight(Enemy.STUBS.hellhound)

	local next_swap, swaps, integrity = PACE, 0, true
	while sim.now < LIMIT and not c.fight_over and not c.game_over do
		if sim.now >= next_swap and c:can_player_swap() == "" then
			local c1, r1, c2, r2 = Match.find_possible_move(sim.board)
			local res = c1 and c:try_swap(sim.board:get(c1, r1), sim.board:get(c2, r2)) or "none"
			if res == "ok" then
				swaps = swaps + 1
				next_swap = sim.now + PACE
			else
				next_swap = sim.now + 0.1 -- busy board: look again shortly
			end
		end
		sim:tick(1 / 60)
		local ok = sim.board:check_integrity(false)
		if not ok then integrity = false end
	end
	add(("end swaps=%d player=%d enemy=%d"):format(swaps, c.player_health, c.enemy.current_health))
	return log, c, sim, integrity
end

T.case("bot plays one seeded fight", function()
	local log, c, _, integrity = play(SEED)
	if os.getenv("BOT_QUIET") ~= "1" then
		print(("-- fight_bot seed %d: %d events"):format(SEED, #log))
		for _, l in ipairs(log) do print(l) end
	end
	T.ok(c.fight_over or c.game_over, "the fight ended within " .. LIMIT .. " s")
	T.ok(integrity, "grid consistent every tick")
	local log2 = play(SEED)
	T.eq(table.concat(log2, "\n"), table.concat(log, "\n"), "same seed, same log")
end)

T.done()
