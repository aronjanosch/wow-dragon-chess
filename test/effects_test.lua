-- core/board_effects.lua: every ability primitive on a known board.
local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "."
local H = dofile(dir .. "/helpers.lua")
local T, ns = H.T, H.ns
local Sim, Board, Match, Rng = ns.Sim, ns.Board, ns.Match, ns.Rng
T.start("effects_test")
local unpack = unpack or table.unpack

-- 8x8 base pattern without lines: (c + 3r) % 6; overrides {"c,r" = token}.
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

local function new_sim(over, opts)
	opts = opts or {}
	local b = H.board(grid(over), { seed = opts.seed or 11, bombs_trigger_adjacent = opts.bombs_trigger_adjacent })
	return Sim.new({ board = b })
end

-- Run fn(sim) as a sim coroutine until the board is at rest; returns fn's results.
local function run_effect(sim, fn)
	local res
	sim:spawn(function() res = { fn(sim) } end)
	T.ok(H.run(sim, 1 / 60, 120), "reached rest")
	local ok, err = sim.board:check_integrity(true)
	T.ok(ok, err)
	return unpack(res or {})
end

local function first_event(sim, name)
	local box = {}
	sim:on(name, function(...) if box.args == nil then box.args = { ... } end end)
	return box
end

local function cells_str(info)
	local out = {}
	for i, e in ipairs(info) do out[i] = e.col .. "," .. e.row end
	return table.concat(out, " ")
end

T.case("clear_area: 3x3, edge clipping, protection, chain activation", function()
	local sim = new_sim({ ["4,4"] = "b" }) -- skill gem inside the area
	sim.board:get(2, 2).protected = true -- protected: survives
	local by_effect = first_event(sim, "gems_cleared_by_effect")
	local flash = first_event(sim, "flash")
	local acts = {}
	sim:on("ability_activated", function(info) acts[#acts + 1] = info end)
	local res = run_effect(sim, function(s) return s:clear_area(3, 3, 1) end)
	T.eq(res.count, 8, "9 cells minus the protected gem")
	T.eq(flash.args[1], "area", "flash kind")
	T.eq(#flash.args[2] / 2, 9, "flash covers 9 cells")
	T.eq(#by_effect.args[1], 8, "gems_cleared_by_effect entries")
	T.eq(#acts >= 1 and acts[1].source, "chain", "ability gem in the area chains")
	T.eq(acts[1] and (acts[1].col .. "," .. acts[1].row .. " t" .. acts[1].gem_type .. " tier" .. acts[1].tier), "4,4 t1 tier1",
		"chain activation info")

	local corner = new_sim(nil)
	local r2 = run_effect(corner, function(s) return s:clear_area(0, 0, 1) end)
	T.eq(r2.count, 4, "corner area clipped to 4")
end)

T.case("clear_row sweeps outward from the origin", function()
	local sim = new_sim(nil)
	local t0
	sim:on("gems_cleared_by_effect", function() t0 = sim.now end)
	local removed_at = {}
	sim:on("gem_removed", function() removed_at[#removed_at + 1] = sim.now end)
	local res = run_effect(sim, function(s) return s:clear_row(2, 3) end)
	T.eq(res.count, 8, "whole row")
	T.eq(cells_str(res.cleared), "3,2 4,2 2,2 5,2 1,2 6,2 0,2 7,2", "outward order, right first")
	T.ok(math.abs(removed_at[1] - t0 - (7 * 0.025 + 0.12)) < 1e-9, "staggered pop: (n-1)*step + CLEAR_ROW")
	local sim2 = new_sim(nil)
	local res2 = run_effect(sim2, function(s) return s:clear_row(5) end)
	T.eq(cells_str(res2.cleared), "0,5 1,5 2,5 3,5 4,5 5,5 6,5 7,5", "no origin: left to right")
end)

T.case("clear_wave: cone toward the right", function()
	local sim = new_sim(nil)
	local res = run_effect(sim, function(s) return s:clear_wave(4, 2, 0.4) end)
	-- dist 0..5 -> half widths 0,0,0,1,1,2 -> 1+1+1+3+3+5
	T.eq(res.count, 14, "cone size")
	local sim2 = new_sim(nil)
	local res2 = run_effect(sim2, function(s) return s:clear_wave(0, 0, 0.4) end)
	-- top row clips the upper half
	T.eq(res2.count, 1 + 1 + 1 + 2 + 2 + 3 + 3 + 3, "clipped at the top")
end)

T.case("clear_color and clear_color_chained", function()
	local sim = new_sim(nil)
	local n2 = 0
	for i = 1, 64 do if sim.board.cells[i].type == 2 then n2 = n2 + 1 end end
	local res = run_effect(sim, function(s) return s:clear_color(2) end)
	T.eq(res.count, n2, "every colour-2 gem")

	local sim2 = new_sim(nil)
	local hops = {}
	sim2:on("chain_hop", function(fc, fr, tc, tr) hops[#hops + 1] = tc .. "," .. tr end)
	local res2 = run_effect(sim2, function(s) return s:clear_color_chained(2, 0, 0) end)
	T.eq(res2.count, n2, "chain clears every colour-2 gem")
	T.eq(#hops, n2, "one hop per gem")
	-- colour 2 in (c+3r)%6: (2,0) is the nearest to (0,0)
	T.eq(hops[1], "2,0", "first hop = nearest")
	T.eq(cells_str(res2.cleared):match("^%S+"), "2,0", "cleared in hop order")
	local empty = new_sim(nil)
	local r3 = run_effect(empty, function(s) return s:clear_color_chained(9, 0, 0) end)
	T.eq(r3.count, 0, "no gems of that colour")
end)

T.case("convert_color: ability gems convert too, bombs/junk don't; marks", function()
	local sim = new_sim({ ["0,0"] = "a", ["2,0"] = "u" }) -- skill colour 0, bomb colour 0
	local from = {}
	for i = 1, 64 do
		local g = sim.board.cells[i]
		if g.type == 0 and not g.bomb and not g.junk then from[#from + 1] = g end
	end
	local converted
	sim:spawn(function() converted = sim:convert_color(0, 4, true) end)
	-- poll until every pick changed colour (morph_in still running): all marked
	local marks_ok, seen_all = false, false
	for _ = 1, 400 do
		sim:tick(1 / 120)
		local all4, all_marked = true, true
		for _, g in ipairs(from) do
			if g.type ~= 4 then all4 = false end
			if not g.marked then all_marked = false end
		end
		if all4 then
			seen_all, marks_ok = true, all_marked
			break
		end
	end
	T.ok(seen_all, "all picks converted to colour 4")
	T.ok(marks_ok, "converted gems carry the convert mark")
	T.ok(H.run(sim, 1 / 60, 120), "rest")
	T.eq(converted, #from, "all colour-0 gems (incl. the skill gem, not the bomb)")
	T.eq(sim.board:get(0, 0) and sim.board:get(0, 0).id ~= nil, true, "board intact")
	local marked_left = false
	for i = 1, 64 do if sim.board.cells[i].marked then marked_left = true end end
	T.ok(not marked_left, "marks clear on settle")
end)

T.case("convert_random_gems: deterministic picks, filters, brake", function()
	local function picks(seed)
		local sim = new_sim(nil, { seed = seed })
		local cells
		sim:on("flash", function(kind, c) if kind == "telegraph_to" then cells = table.concat(c, ",") end end)
		local n = run_effect(sim, function(s) return s:convert_random_gems(3, 5) end)
		return n, cells
	end
	local n1, c1 = picks(5)
	local n2, c2 = picks(5)
	T.eq(n1, 5, "5 converted")
	T.eq(c1, c2, "same seed -> same picks")
	local _, c3 = picks(6)
	T.ok(c1 ~= c3, "other seed -> other picks")

	-- from_type filter + exclude_adjacent_to_type brake
	local sim = new_sim({ ["1,1"] = "b" }) -- skill gem of colour 1 at (1,1)
	local targets = sim:pick_convert_targets(3, 64, 0, 1)
	local ok_filter, ok_brake = true, true
	for _, g in ipairs(targets) do
		if g.type ~= 0 then ok_filter = false end
		local dc, dr = math.abs(g.col - 1), math.abs(g.row - 1)
		if dc + dr == 1 then ok_brake = false end
	end
	T.ok(ok_filter, "only from_type gems")
	T.ok(ok_brake, "none next to the colour-1 skill gem")
	-- (0,1) is colour 3 ... count colour-0 gems adjacent to (1,1): (1,0)? (1,0)=1, (0,1)=3, (2,1)=5, (1,2)=1+6=1 -> none
	T.ok(#targets > 0, "some targets")
end)

T.case("convert_random_to_bombs and set_gems_junk", function()
	local sim = new_sim(nil)
	local made = run_effect(sim, function(s) return s:convert_random_to_bombs(3) end)
	T.eq(made, 3, "3 bombs")
	local bombs = 0
	for i = 1, 64 do if sim.board.cells[i].bomb then bombs = bombs + 1 end end
	T.eq(bombs, 3, "3 bombs on the board")

	local sim2 = new_sim(nil)
	local spawned = first_event(sim2, "junk_spawned")
	local n = run_effect(sim2, function(s) return s:set_gems_junk(4) end)
	T.eq(n, 4, "4 junk")
	T.eq(spawned.args and #spawned.args[1], 4, "junk_spawned with 4 gems")
	local junk = 0
	for i = 1, 64 do if sim2.board.cells[i].junk then junk = junk + 1 end end
	T.eq(junk, 4, "4 junk on the board")
end)

T.case("junk next to a clear pops with it (0 damage)", function()
	-- junk at (3,1) under a row-0 line made by swapping (2,1) up
	local sim = new_sim({ ["0,0"] = "1", ["1,0"] = "1", ["2,1"] = "1", ["1,1"] = "J" })
	local junk = sim.board:get(1, 1)
	local counts = first_event(sim, "gems_cleared")
	sim:try_swap(sim.board:get(2, 1), sim.board:get(2, 0))
	T.ok(H.run(sim), "rest")
	T.ok(junk.removed, "adjacent junk cleared")
	local total = 0
	for _, t in ipairs(counts.args[2]) do total = total + counts.args[1][t] end
	T.eq(total, 3, "junk adds no damage count")

	-- effect clear: junk outside the 3x3 but adjacent pops too
	local sim2 = new_sim({ ["5,3"] = "J" })
	local res = run_effect(sim2, function(s) return s:clear_area(3, 3, 1) end)
	T.eq(res.count, 10, "9 + adjacent junk")
	local has_junk = false
	for _, e in ipairs(res.cleared) do if e.is_junk then has_junk = true end end
	T.ok(has_junk, "info marks the junk")
end)

T.case("bombs_trigger_adjacent (default off)", function()
	local off = new_sim({ ["5,3"] = "u" })
	local r1 = run_effect(off, function(s) return s:clear_area(3, 3, 1) end)
	T.eq(r1.count, 9, "flag off: adjacent bomb untouched")
	local on = new_sim({ ["5,3"] = "u" }, { bombs_trigger_adjacent = true })
	local acts = {}
	on:on("ability_activated", function(i) acts[#acts + 1] = i end)
	local r2 = run_effect(on, function(s) return s:clear_area(3, 3, 1) end)
	T.eq(r2.count, 10, "flag on: adjacent bomb pops")
	T.ok(acts[1] and acts[1].is_bomb and acts[1].source == "chain", "and activates as a chain bomb")
end)

T.case("set_gravity_slow: factor, window, pause-safe", function()
	local sim = new_sim(nil)
	local changes = {}
	sim:on("gravity_slow_changed", function(active) changes[#changes + 1] = tostring(active) end)
	T.eq(sim:_fall_duration(4), 0.36, "normal fall 4 cells")
	T.eq(sim:_fall_duration(8), 0.38, "capped")
	sim:set_gravity_slow(0.4, 2.0)
	T.ok(math.abs(sim:_fall_duration(4) - 0.9) < 1e-12, "slowed x2.5")
	T.ok(math.abs(sim:_fall_duration(8) - 0.95) < 1e-12, "cap slowed too")
	T.eq(sim:get_gravity_slow_factor(), 0.4, "factor")
	sim:tick(0.05)
	sim:pause_gameplay()
	for _ = 1, 100 do sim:tick(0.05) end
	T.ok(math.abs(sim:get_gravity_slow_remaining() - 1.95) < 1e-9, "frozen while gameplay-paused")
	sim:resume_gameplay()
	for _ = 1, 39 do sim:tick(0.05) end
	T.ok(sim:get_gravity_slow_remaining() > 0, "still active just before the end")
	sim:tick(0.05)
	T.eq(sim:get_gravity_slow_remaining(), 0, "expired")
	T.eq(sim:get_gravity_slow_factor(), 1.0, "factor back to 1")
	T.eq(table.concat(changes, " "), "true false", "changed events")
	sim:set_gravity_slow(0.5, 0) -- ignored
	T.eq(#changes, 2, "zero duration ignored")
end)

T.case("convert re-validates targets changed mid-telegraph", function()
	local function setup()
		local sim = new_sim(nil, { seed = 21 })
		local first
		sim:on("flash", function(kind, c) if kind == "telegraph_to" and not first then first = { c[1], c[2] } end end)
		local box = {}
		sim:spawn(function() box.converted = sim:convert_random_gems(3, 3) end)
		T.ok(first ~= nil, "telegraph started")
		sim:tick(0.05)
		return sim, first, box
	end
	-- a pick turned to junk while the telegraph holds is dropped
	local sim, first, box = setup()
	Board.set_junk(sim.board:get(first[1], first[2]), true)
	T.ok(H.run(sim, 1 / 60, 60), "rest")
	T.eq(box.converted, 2, "junked pick skipped, the other two converted")
	-- a pick cleared mid-telegraph (its column then falls, so neighbours above
	-- may still be FALLING at re-validation and are dropped too, like Godot)
	local sim2, first2, box2 = setup()
	sim2:spawn(function() sim2:clear_area(first2[1], first2[2], 0) end)
	T.ok(H.run(sim2, 1 / 60, 60), "rest")
	T.ok(box2.converted >= 1 and box2.converted <= 2, "cleared pick skipped: " .. tostring(box2.converted))
end)

T.done()
