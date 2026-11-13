-- core/sim.lua: swaps, resolve passes, cascades, spawn rules, drain hook,
-- determinism, settle_now, dt independence, reshuffle, snapshot.
local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "."
local H = dofile(dir .. "/helpers.lua")
local T, ns = H.T, H.ns
local Sim, Board, Match, Rng = ns.Sim, ns.Board, ns.Match, ns.Rng
T.start("sim_test")

-- 8x8 base pattern without lines: type (c + 3r) % 6; overrides {"c,r" = token}.
local function grid(over)
	local rows = {}
	for r = 0, 7 do
		local line = {}
		for c = 0, 7 do
			line[#line + 1] = (over and over[c .. "," .. r]) or tostring((c + 3 * r) % 6)
		end
		rows[#rows + 1] = table.concat(line)
	end
	return rows
end

local function sim_from(over, opts)
	opts = opts or {}
	local b = H.board(grid(over), { seed = opts.seed or 7 })
	assert(#Match.find_matches(b) == 0, "test board has a match")
	return Sim.new({ board = b, release_on_settle = opts.release_on_settle })
end

T.case("valid swap: match, clear, refill, settle", function()
	-- row 0: 1 1 _ 1? no: (0,0)=1 (1,0)=1, swap (2,1)=1 up into (2,0)
	local sim = sim_from({ ["0,0"] = "1", ["1,0"] = "1", ["2,1"] = "1" })
	local log = H.record(sim)
	local counts
	sim:on("gems_cleared", function(c) counts = c end)
	local a, b = sim.board:get(2, 1), sim.board:get(2, 0)
	T.eq(sim:try_swap(a, b), "ok", "swap accepted")
	T.eq(a.state, Board.SWAPPING, "swapping while the tween runs")
	T.eq(sim:try_swap(a, b), "unsettled", "second swap on moving gems refused")
	T.ok(H.run(sim), "reaches rest")
	T.ok(sim.board:is_fully_settled(), "all settled")
	local ok, err = sim.board:check_integrity(true)
	T.ok(ok, err)
	T.ok(counts and counts[1] and counts[1] >= 3, "gems_cleared counted colour 1")
	T.ok(log[1]:find("match_resolved len=3 depth=1") ~= nil, "first event is the match: " .. tostring(log[1]))
	T.eq(#Match.find_matches(sim.board), 0, "no match left at rest")
end)

-- W0-P6: match_resolved carries where the gems converge and the spawned tier as trailing payload.
T.case("match_resolved payload: convergence cell + spawn tier (additive, W0-P6)", function()
	-- 3-match: no spawn, the gems converge on the centre gem's cell
	local sim = sim_from({ ["0,0"] = "1", ["1,0"] = "1", ["2,1"] = "1" })
	local got
	sim:on("match_resolved", function(len, gems, depth, dcol, drow, tier) got = { len, #gems, depth, dcol, drow, tier } end)
	T.eq(sim:try_swap_cells(2, 1, 2, 0), "ok", "swap")
	T.ok(H.run(sim), "rest")
	T.ok(got ~= nil and got[1] == 3 and got[2] == 3 and got[3] == 1, "3-match event")
	T.ok(got[4] == 1 and got[5] == 0 and got[6] == 0, "3-match: centre (1,0), tier 0 (got " .. tostring(got[4]) .. "," .. tostring(got[5]) .. " tier " .. tostring(got[6]) .. ")")
	-- 4-match by a swap: the ability gem spawns at the swapped gem's cell (tier 1)
	sim = sim_from({ ["0,0"] = "1", ["1,0"] = "1", ["3,0"] = "1", ["2,1"] = "1" })
	got = nil
	local spawned
	sim:on("match_resolved", function(len, gems, depth, dcol, drow, tier) got = { len, dcol, drow, tier } end)
	sim:on("ability_gem_spawned", function(c, r, tier) spawned = { c, r, tier } end)
	T.eq(sim:try_swap_cells(2, 1, 2, 0), "ok", "swap 4")
	T.ok(H.run(sim), "rest 4")
	T.ok(got ~= nil and got[1] == 4 and got[4] == 1, "4-match spawns tier 1")
	T.ok(spawned ~= nil and got[2] == spawned[1] and got[3] == spawned[2], "dest = the spawn cell of ability_gem_spawned")
	-- no spawn when the board does not spawn ability gems: tier 0, dest = the centre
	sim = sim_from({ ["0,0"] = "1", ["1,0"] = "1", ["3,0"] = "1", ["2,1"] = "1" })
	sim.board.spawn_ability_gems = false
	got = nil
	sim:on("match_resolved", function(len, gems, depth, dcol, drow, tier) got = { len, dcol, drow, tier } end)
	sim:try_swap_cells(2, 1, 2, 0)
	T.ok(H.run(sim), "rest no spawn")
	T.ok(got ~= nil and got[4] == 0, "spawn off: tier 0")
end)

T.case("invalid swap is rejected and swapped back", function()
	-- a legal move elsewhere (row 7), so the idle check does not reshuffle
	local sim = sim_from({ ["0,7"] = "5", ["1,6"] = "5" })
	T.ok(Match.find_possible_move(sim.board) ~= nil, "precondition: board has a move")
	local before = sim.board:dump(true)
	local rejected = 0
	local rej_a, rej_b
	sim:on("swap_rejected", function(a, b) rejected = rejected + 1; rej_a, rej_b = a, b end)
	local ga, gb = sim.board:get(0, 0), sim.board:get(1, 0)
	T.eq(sim:try_swap(ga, gb), "ok", "accepted for animation")
	T.ok(H.run(sim), "rest")
	T.eq(rejected, 1, "swap_rejected emitted")
	T.ok(rej_a == ga and rej_b == gb, "swap_rejected carries the two swapped gems (W0-P7, additive payload)")
	T.eq(sim.board:dump(true), before, "board unchanged")
	T.ok(math.abs(sim.now - 0.28) < 0.02, "two swap tweens (~0.28 s): " .. sim.now)
	T.eq(sim:try_swap(sim.board:get(0, 0), sim.board:get(2, 0)), "not_adjacent", "not adjacent")
	sim:pause_gameplay()
	T.eq(sim:try_swap(sim.board:get(0, 0), sim.board:get(1, 0)), "paused", "paused gate")
	sim:resume_gameplay()
end)

T.case("swap-created 4 spawns a skill at the swapped-in gem", function()
	local sim = sim_from({ ["0,0"] = "1", ["1,0"] = "1", ["3,0"] = "1", ["2,1"] = "1" })
	local mover = sim.board:get(2, 1)
	local spawned
	sim:on("ability_gem_spawned", function(c, r, tier, t)
		spawned = spawned or (c .. "," .. r .. " tier" .. tier .. " t" .. t)
	end)
	sim:try_swap(mover, sim.board:get(2, 0))
	T.ok(H.run(sim), "rest")
	T.eq(spawned, "2,0 tier1 t1", "spawn event")
	T.eq(mover.removed, false, "the swapped-in gem was kept")
	T.eq(mover.tier, 1, "it became the skill gem")
	T.eq(sim.board:get(mover.col, mover.row), mover, "kept gem is in the grid")
	T.ok(mover.protected, "fresh ability gem is spawn-protected (no combat lifts it)")
end)

T.case("matched ability gem on the spawn cell fires, then becomes the new ability gem", function()
	-- 'b' = skill gem of colour 1 at (2,1); swap it up into a row of four 1s -> 5
	local sim = sim_from({ ["0,0"] = "1", ["1,0"] = "1", ["3,0"] = "1", ["4,0"] = "1", ["2,1"] = "b" })
	local skill = sim.board:get(2, 1)
	local partner_type = sim.board:get(2, 0).type
	local acts = {}
	sim:on("ability_activated", function(info) acts[#acts + 1] = info end)
	local order = {}
	sim:on("gems_cleared", function() order[#order + 1] = "cleared" end)
	sim:on("ability_activated", function() order[#order + 1] = "activated" end)
	sim:try_swap(skill, sim.board:get(2, 0))
	T.ok(H.run(sim), "rest")
	T.eq(#acts >= 1 and acts[1].tier, 1, "the old skill fired (tier 1)")
	T.eq(acts[1] and acts[1].source, "match", "source match")
	T.eq(acts[1] and acts[1].partner_color, partner_type, "partner = the other swapped gem's colour")
	T.eq(acts[1] and acts[1].match_length, 5, "match_length 5")
	T.eq(acts[1] and (acts[1].col .. "," .. acts[1].row), "2,0", "fired at the spawn cell")
	T.eq(order[1] .. " " .. tostring(order[2]), "cleared activated", "gems_cleared before ability_activated")
	T.eq(skill.removed, false, "gem kept")
	T.eq(skill.tier, 2, "now the ult")
	T.ok(skill.protected, "protected")
	T.eq(sim.board:get(2, 0), skill, "at the spawn cell")
end)

T.case("drain hook holds the cascade until it returns", function()
	local sim = sim_from({ ["0,0"] = "1", ["1,0"] = "1", ["3,0"] = "1", ["4,0"] = "1", ["2,1"] = "b" })
	local t_act, t_done, t_created
	sim:on("ability_activated", function() t_act = t_act or sim.now end)
	sim:on("gem_created", function() t_created = t_created or sim.now end)
	sim:set_drain(function(s)
		s:wait(1.0)
		t_done = s.now
	end)
	sim:try_swap(sim.board:get(2, 1), sim.board:get(2, 0))
	T.ok(H.run(sim), "rest")
	T.ok(t_done and math.abs(t_done - t_act - 1.0) < 1e-9, "drain ran 1 s after activation")
	T.ok(t_created and t_created >= t_done, "gravity/refill only after the drain")
	-- without abilities the drain is not called
	local sim2 = sim_from({ ["0,0"] = "1", ["1,0"] = "1", ["2,1"] = "1" })
	local called = false
	sim2:set_drain(function() called = true end)
	sim2:try_swap(sim2.board:get(2, 1), sim2.board:get(2, 0))
	H.run(sim2)
	T.ok(not called, "no activation -> no drain")
end)

T.case("spawn protection lifts on settle (standalone rule) and resolves blocked lines", function()
	local sim = sim_from({ ["0,0"] = "1", ["1,0"] = "1", ["3,0"] = "1", ["2,1"] = "1" }, { release_on_settle = true })
	local settled = 0
	sim:on("board_settled", function() settled = settled + 1 end)
	sim:try_swap(sim.board:get(2, 1), sim.board:get(2, 0))
	T.ok(H.run(sim), "rest")
	T.ok(settled >= 1, "board_settled emitted")
	local any_protected = false
	for i = 1, 64 do if sim.board.cells[i].protected then any_protected = true end end
	T.ok(not any_protected, "no protection left at rest")
	T.eq(#Match.find_matches(sim.board), 0, "no line left")
	-- a protected gem blocking a line: releasing it resolves the line
	local b = H.board(grid({ ["0,0"] = "1", ["1,0"] = "1", ["2,0"] = "1" }), { seed = 3 })
	b:get(1, 0).protected = true
	T.eq(#Match.find_matches(b), 0, "protected gem blocks the line")
	local s3 = Sim.new({ board = b, release_on_settle = true })
	local resolved = 0
	s3:on("match_resolved", function() resolved = resolved + 1 end)
	s3:release_spawn_protection()
	T.ok(H.run(s3), "rest")
	T.ok(resolved >= 1, "released line resolved")
end)

-- Scripted play: a fixed seed, the first legal move each time the board is at rest.
local function scripted(seed, dts, opts)
	opts = opts or {}
	local sim = Sim.new({ seed = seed, release_on_settle = true })
	local log = H.record(sim)
	local k = 0
	for _ = 1, opts.swaps or 12 do
		local c1, r1, c2, r2 = Match.find_possible_move(sim.board)
		if not c1 then break end
		sim:try_swap_cells(c1, r1, c2, r2)
		if opts.settle then
			assert(sim:settle_now(), "settle_now did not reach rest")
		else
			local guard = 0
			while not sim:is_at_rest() do
				k = k + 1
				sim:tick(dts[(k - 1) % #dts + 1])
				guard = guard + 1
				assert(guard < 100000, "no rest")
			end
		end
	end
	return sim.board:dump(true), table.concat(log, "\n"), sim
end

T.case("determinism: same seed -> same board and same event sequence", function()
	local b1, l1 = scripted(99, { 1 / 60 })
	local b2, l2 = scripted(99, { 1 / 60 })
	T.eq(b1, b2, "final boards")
	T.ok(l1 == l2, "event logs identical")
	local b3 = scripted(100, { 1 / 60 })
	T.ok(b1 ~= b3, "another seed differs")
end)

T.case("results do not depend on frame rate; settle_now equals ticking", function()
	local ref_b, ref_l = scripted(1234, { 1 / 60 })
	local b144, l144 = scripted(1234, { 1 / 144 })
	local bodd, lodd = scripted(1234, { 0.003, 0.017, 0.041, 0.05, 0.011 })
	local bset, lset = scripted(1234, nil, { settle = true })
	T.eq(b144, ref_b, "144 Hz board")
	T.eq(bodd, ref_b, "irregular dt board")
	T.eq(bset, ref_b, "settle_now board")
	-- Event times are exact wake times, so even the timestamps agree, except
	-- that swaps start at tick boundaries (rest is detected after a tick).
	local function strip(l) return (l:gsub("%d+%.%d+ ", "")) end
	T.ok(strip(l144) == strip(ref_l), "144 Hz event order")
	T.ok(strip(lodd) == strip(ref_l), "irregular dt event order")
	T.ok(strip(lset) == strip(ref_l), "settle_now event order")
end)

T.case("no moves left -> reshuffle", function()
	-- (c + 3r) % 6 has no move? verify, else craft
	local rows = {}
	for r = 0, 7 do
		local line = {}
		for c = 0, 7 do line[#line + 1] = tostring((c + 2 * r) % 6 + 0) end
		rows[#rows + 1] = table.concat(line)
	end
	local b = H.board(rows, { seed = 5 })
	local nomove = Match.find_possible_move(b) == nil
	T.ok(nomove, "precondition: pattern has no move")
	local sim = Sim.new({ board = b })
	local shuffled = 0
	sim:on("board_shuffled", function() shuffled = shuffled + 1 end)
	-- any swap is rejected; the idle check then reshuffles
	sim:try_swap(b:get(0, 0), b:get(1, 0))
	T.ok(H.run(sim), "rest")
	T.eq(shuffled, 1, "reshuffled once")
	T.ok(Match.find_possible_move(b) ~= nil, "a move exists now")
	T.eq(#Match.find_matches(b), 0, "and no match")

	-- nothing can ever form a move (all junk): the reshuffle gives up instead of
	-- looping forever (Godot's unbounded loop would hang here)
	local junk_rows = {}
	for r = 1, 8 do junk_rows[r] = "JJJJJJJJ" end
	local jb = H.board(junk_rows, { seed = 5 })
	local sim2 = Sim.new({ board = jb })
	local result
	sim2:on("board_shuffled", function(ok) result = ok end)
	sim2:try_swap(jb:get(0, 0), jb:get(1, 0))
	T.ok(H.run(sim2), "rest")
	T.eq(result, false, "board_shuffled(false): no move possible")

	-- W0-G2a (Godot #49): a junk gem swapped in would line up (0,0),(0,1),(0,2) - not a move.
	-- The board is "no move": the (capped) reshuffle fires, plain gems re-roll, junk stays.
	local over = {}
	for r = 0, 7 do
		local line = {}
		for c = 0, 7 do line[#line + 1] = "J" end
		over[r + 1] = table.concat(line)
	end
	over[1] = "0" .. over[1]:sub(2)
	over[2] = "0" .. over[2]:sub(2)
	over[3] = "J0" .. over[3]:sub(3)
	local jb2 = H.board(over, { seed = 5 })
	T.ok(Match.find_possible_move(jb2) == nil, "junk-only 'move' is no move")
	local sim3 = Sim.new({ board = jb2 })
	local fired = 0
	sim3:on("board_shuffled", function() fired = fired + 1 end)
	sim3:try_swap(jb2:get(0, 0), jb2:get(1, 0))
	T.ok(H.run(sim3), "rest")
	T.eq(fired, 1, "board_shuffled fires")
	local junk_left = 0
	for i = 1, 64 do if jb2.cells[i].junk then junk_left = junk_left + 1 end end
	T.eq(junk_left, 61, "junk stays on the board")
end)

T.case("snapshot at rest: serialize -> deserialize continues identically", function()
	local _, _, sim = scripted(77, { 1 / 60 }, { swaps = 5 })
	T.ok(sim:is_at_rest(), "at rest")
	local snap = assert(sim:serialize())
	local copy = assert(Sim.deserialize(snap, { release_on_settle = true }))
	T.eq(copy.board:dump(true), sim.board:dump(true), "same board after load")
	local function play(s)
		for _ = 1, 6 do
			local c1, r1, c2, r2 = Match.find_possible_move(s.board)
			s:try_swap_cells(c1, r1, c2, r2)
			assert(s:settle_now())
		end
		return s.board:dump(true)
	end
	T.eq(play(copy), play(sim), "continuation identical (RNG streams restored)")
	-- busy board refuses
	local c1, r1, c2, r2 = Match.find_possible_move(sim.board)
	sim:try_swap_cells(c1, r1, c2, r2)
	local s, err = sim:serialize()
	T.ok(s == nil and err == "not at rest", "refused while busy")
	T.eq(Sim.deserialize({ v = 999 }), nil, "wrong version refused")
	T.eq(Sim.deserialize({ v = 1, board = { v = 1, cols = 8, rows = 8, gems = {}, rng_refill = {}, rng_effects = {} } }), nil,
		"corrupt board refused")
end)

T.case("rng streams are injectable (tape stub)", function()
	-- the first three refill draws come from the tape (colour 5), then a real stream
	local b = H.board(grid({ ["0,0"] = "1", ["1,0"] = "1", ["2,1"] = "1" }),
		{ rng_refill = H.tape({ 5, 5, 5 }, Rng.new(1)) })
	local sim = Sim.new({ board = b })
	local created = {}
	sim:on("gem_created", function(g) created[#created + 1] = g.type end)
	sim:try_swap(b:get(2, 1), b:get(2, 0))
	H.run(sim)
	T.ok(#created >= 3, "refilled")
	T.eq(table.concat(created, "", 1, 3), "555", "refill colours from the tape (columns 0, 1, 3 top row first)")
end)

T.case("gems move in core: positions interpolate and land on their cells", function()
	local sim = sim_from({ ["0,0"] = "1", ["1,0"] = "1", ["2,1"] = "1" })
	local a = sim.board:get(2, 1)
	sim:try_swap(a, sim.board:get(2, 0))
	sim:tick(0.07)
	T.ok(a.y < 1 and a.y > 0, "mid-swap y between rows: " .. a.y)
	H.run(sim)
	local exact = true
	for c = 0, 7 do
		for r = 0, 7 do
			local g = sim.board:get(c, r)
			if g.x ~= c or g.y ~= r then exact = false end
		end
	end
	T.ok(exact, "every gem at its cell at rest")
end)

T.done()
