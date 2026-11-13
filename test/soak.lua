-- Soak: 10 000 random valid swaps on a seed with a combat stub that fires the
-- board primitives through the drain hook (concurrency like the real game),
-- enemy-style junk / gravity slow and fight-transition pauses. Checks: no error,
-- grid consistent all the time, board full and settled at the end. Then
-- measures garbage per simulated second (GC stopped) and CPU cost.
local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "."
local H = dofile(dir .. "/helpers.lua")
local T, ns = H.T, H.ns
local Sim, Match, Rng = ns.Sim, ns.Match, ns.Rng
T.start("soak")

local SWAPS = tonumber(os.getenv("SOAK_SWAPS") or "") or 10000
local SEED = tonumber(os.getenv("SOAK_SEED") or "") or 20261004

-- Ability stand-ins (shapes of the real kits; colours 0-5).
local function exec(sim, info)
	local c, r, t = info.col, info.row, info.gem_type
	if info.is_bomb then return sim:clear_area(c, r, 1) end
	if info.tier == 1 then
		if t == 0 then return sim:convert_random_gems(t, 4, -1, t)
		elseif t == 1 then return sim:clear_area(c, r, 1)
		elseif t == 3 then return sim:clear_wave(r, c, 0.4)
		elseif t == 5 then return sim:clear_row(r, c)
		end
		return -- 2, 4: status-only (synchronous)
	end
	if t == 0 then return sim:convert_random_gems(t, 8)
	elseif t == 1 then
		local partner = info.partner_color >= 0 and info.partner_color or (t + 1) % 6
		if partner ~= t then return sim:convert_color(partner, t, true) end
	elseif t == 2 then return sim:clear_area(c, r, 2)
	elseif t == 3 then return sim:convert_random_to_bombs(3)
	elseif t == 4 then return sim:clear_color(t)
	elseif t == 5 then return sim:clear_color_chained(t, c, r)
	end
end

-- First valid swap from a random start offset (allocation-free search).
local function pick_swap(sim, rng)
	local b = sim.board
	local start = rng:range_i(0, 63)
	for k = 0, 63 do
		local i = (start + k) % 64
		local col, row = math.floor(i / 8), i % 8
		local g = b:get(col, row)
		if g and g.state == 0 and not g.junk then
			local dir_first = rng:range_i(0, 1)
			for d = 0, 1 do
				local right = (d + dir_first) % 2 == 0
				local c2, r2 = right and col + 1 or col, right and row or row + 1
				if c2 < 8 and r2 < 8 then
					local g2 = b:get(c2, r2)
					if g2 and g2.state == 0 and not g2.junk and Match.would_swap_match(b, col, row, c2, r2) then
						return g, g2
					end
				end
			end
		end
	end
end

local race = { overlaps = 0, moved_busy = 0, junk_dead_ends = 0 }

local function new_soak_sim(seed, instrument)
	local sim = Sim.new({ seed = seed })
	H.attach_combat_stub(sim, exec)
	if instrument then
		-- count the Godot "gravity race" (board.gd:997/1799): overlapping gravity
		-- passes, and collapses that move a SWAPPING / CLEARING gem
		local active = 0
		local grav = sim._animate_gravity_and_spawn
		sim._animate_gravity_and_spawn = function(self)
			active = active + 1
			if active > 1 then race.overlaps = race.overlaps + 1 end
			grav(self)
			active = active - 1
		end
		local collapse = sim._collapse_column
		sim._collapse_column = function(self, col, moves)
			local n = #moves
			collapse(self, col, moves)
			for i = n + 1, #moves, 2 do
				local st = moves[i].state
				if st == 1 or st == 3 then race.moved_busy = race.moved_busy + 1 end
			end
		end
	end
	return sim
end

-- Drive the sim; returns swaps done. `checks` = integrity check every tick.
local function drive(sim, rng, swaps_target, checks, max_ticks)
	local swaps, ticks, next_swap, last_swap = 0, 0, 1, 0
	local no_move_ticks = 0
	local next_enemy = 300
	local problem
	while swaps < swaps_target and ticks < max_ticks do
		ticks = ticks + 1
		if ticks >= next_swap then
			local a, b = pick_swap(sim, rng)
			if a == nil and sim:is_at_rest() and Match.find_possible_move(sim.board) ~= nil then
				no_move_ticks = no_move_ticks + 1
			else
				no_move_ticks = 0
			end
			if no_move_ticks >= 30 then
				-- Godot-parity dead end: only junk "moves" left (find_possible_move
				-- counts a junk gem's colour), so no reshuffle. Unstick like an
				-- ability would: clear around a junk gem.
				race.junk_dead_ends = race.junk_dead_ends + 1
				no_move_ticks = 0
				for i = 1, 64 do
					local g = sim.board.cells[i]
					if g and g.junk then
						local c, r = g.col, g.row
						sim:spawn(function() sim:clear_area(c, r, 1) end)
						break
					end
				end
			end
			if a and sim:try_swap(a, b) == "ok" then
				swaps = swaps + 1
				last_swap = ticks
			end
			next_swap = ticks + rng:range_i(2, 24)
		end
		if ticks >= next_enemy then
			-- enemy turn: junk, sometimes a gravity slow, sometimes a fight-transition pause
			local roll = rng:range_i(0, 9)
			local junk = 0
			for i = 1, 64 do
				local g = sim.board.cells[i]
				if g and g.junk then junk = junk + 1 end
			end
			if roll < 5 then
				-- capped: an unbounded junk stream buries the board (no moves left)
				if junk < 10 then sim:spawn(function() sim:set_gems_junk(2) end) end
			elseif roll < 7 then
				sim:set_gravity_slow(0.4, 3.0)
			elseif roll == 7 then
				sim:pause_gameplay()
			end
			next_enemy = ticks + rng:range_i(120, 480)
		end
		if sim.gameplay_paused and rng:range_i(0, 59) == 0 then sim:resume_gameplay() end
		sim:tick(1 / 60)
		if ticks - last_swap > 6000 then
			local d = { ("stalled at tick %d: rest=%s resolving=%s paused=%s awaiting_drain=%s defer=%s move=%s"):format(
				ticks, tostring(sim:is_at_rest()), tostring(sim.resolving), tostring(sim.gameplay_paused),
				tostring(sim.awaiting_drain), tostring(sim.defer_gravity), tostring(Match.find_possible_move(sim.board))) }
			for _, t in ipairs(sim.tasks) do
				d[#d + 1] = ("task #%d mode=%d event=%s due=%s service=%s"):format(t.seq, t.mode, tostring(t.event),
					tostring(t.due), tostring(t.service))
			end
			d[#d + 1] = table.concat(H.rows(sim.board), " ")
			d[#d + 1] = sim.board:dump()
			problem = table.concat(d, "\n  ")
			break
		end
		if checks then
			local ok, err = sim.board:check_integrity(false)
			if not ok then
				problem = ("tick %d: %s"):format(ticks, err)
				break
			end
		end
	end
	return swaps, ticks, problem
end

local function finish(sim)
	if sim.gameplay_paused then sim:resume_gameplay() end
	local t = 0
	while not sim:is_at_rest() and t < 120 do
		sim:tick(1 / 60)
		t = t + 1 / 60
	end
	return sim:is_at_rest()
end

T.case("10 000 swaps", function()
	local sim = new_soak_sim(SEED, true)
	local rng = Rng.new(SEED + 1)
	local rejected = 0
	sim:on("swap_rejected", function() rejected = rejected + 1 end)
	local created, removed = 64, 0
	sim:on("gem_created", function() created = created + 1 end)
	sim:on("gem_removed", function() removed = removed + 1 end)
	local clock = os.clock()
	local swaps, ticks, problem = drive(sim, rng, SWAPS, true, SWAPS * 200)
	local cpu = os.clock() - clock
	T.ok(problem == nil, "grid consistent during play: " .. tostring(problem))
	T.eq(swaps, SWAPS, "valid swaps done")
	T.ok(finish(sim), "reaches rest after the last swap (nothing stuck)")
	T.ok(sim.board:is_fully_settled(), "board full and settled")
	local ok, err = sim.board:check_integrity(true)
	T.ok(ok, err)
	T.eq(created - removed, 64, "every created gem is in the grid or removed (no lost gems)")
	T.eq(#Match.find_matches(sim.board), 0, "no match left at rest")
	print(("  soak: %d swaps (%d rejected), %d ticks = %.0f sim s, %.2f s CPU (%.3f ms per sim s), %d gems created")
		:format(swaps, rejected, ticks, ticks / 60, cpu, cpu * 1000 / (ticks / 60), created))
	print(("  gravity race: %d overlapping gravity passes, %d swapping/clearing gems moved by a collapse;"
		.. " %d junk-only dead ends unstuck"):format(race.overlaps, race.moved_busy, race.junk_dead_ends))
end)

T.case("garbage per simulated second", function()
	local sim = new_soak_sim(SEED + 7)
	local rng = Rng.new(SEED + 8)
	drive(sim, rng, 50, false, 100000) -- warm up (JIT, tables)
	collectgarbage("collect")
	collectgarbage("stop")
	local before = collectgarbage("count")
	local swaps, ticks = drive(sim, rng, 1000000, false, 60 * 60) -- 60 sim seconds of play
	local play_kb = collectgarbage("count") - before
	finish(sim)
	collectgarbage("collect")
	before = collectgarbage("count")
	for _ = 1, 60 * 60 do sim:tick(1 / 60) end -- 60 s at rest
	local idle_kb = collectgarbage("count") - before
	collectgarbage("restart")
	print(("  garbage: %.1f KB per sim second while playing (%d swaps / 60 s, combat stub), %.2f KB/s idle")
		:format(play_kb / (ticks / 60), swaps, idle_kb / 60))
	T.ok(idle_kb / 60 < 1, "idle board allocates (almost) nothing")
end)

T.done()
