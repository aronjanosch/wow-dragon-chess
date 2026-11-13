-- Pause semantics: hide-pause (no ticks) and the gameplay-pause gate freeze the
-- board exactly; resuming continues identically to an unpaused run.
local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "."
local H = dofile(dir .. "/helpers.lua")
local T, ns = H.T, H.ns
local Sim, Match = ns.Sim, ns.Match
T.start("pause_test")

-- Full visible state: grid incl. ids, positions, fx progress.
local function state_hash(sim)
	local parts = { sim.board:dump(true), ("g%.9f"):format(sim:gnow()) }
	for i = 1, 64 do
		local g = sim.board.cells[i]
		if g then parts[#parts + 1] = ("%d:%.6f,%.6f,%s,%.6f"):format(g.id, g.x, g.y, tostring(g.fx), g.fx_t or 0) end
	end
	return table.concat(parts, "|")
end

-- Play `swaps` legal moves, ticking at 60 Hz; `hook(sim, frame)` may pause.
local function play(seed, swaps, hook)
	local sim = Sim.new({ seed = seed, release_on_settle = true })
	local log = H.record(sim)
	local frame = 0
	for _ = 1, swaps do
		local c1, r1, c2, r2 = Match.find_possible_move(sim.board)
		sim:try_swap_cells(c1, r1, c2, r2)
		repeat
			frame = frame + 1
			if hook then hook(sim, frame) end
			sim:tick(1 / 60)
		until sim:is_at_rest()
	end
	local events = {}
	for _, l in ipairs(log) do
		local e = l:gsub("^%S+ ", "")
		if e ~= "gameplay_unpaused" then events[#events + 1] = e end
	end
	return sim, table.concat(events, "\n")
end

T.case("hide-pause: no ticks, nothing changes; resume continues identically", function()
	local ref_sim, ref_events = play(31, 6)
	local frozen_ok = true
	local sim, events = play(31, 6, function(s, frame)
		if frame == 20 then
			-- window hidden mid-cascade: the driver stops calling tick
			local before = state_hash(s)
			local now = s.now
			-- (time passes in the real world; the sim is not called)
			if state_hash(s) ~= before or s.now ~= now then frozen_ok = false end
		end
	end)
	T.ok(frozen_ok, "state unchanged while not ticking")
	T.eq(sim.board:dump(true), ref_sim.board:dump(true), "same final board")
	T.ok(events == ref_events, "same event sequence")
	T.eq(sim.now, ref_sim.now, "same sim time (hidden time does not count)")
end)

T.case("gameplay-pause gate mid-cascade: frozen, then identical continuation", function()
	local ref_sim, ref_events = play(32, 6)
	local frozen_ok, paused_frames = true, 0
	local before
	local sim, events = play(32, 6, function(s, frame)
		if frame == 15 then
			s:pause_gameplay()
			before = state_hash(s)
		elseif frame > 15 and frame <= 15 + 180 then
			paused_frames = paused_frames + 1
			if state_hash(s) ~= before then frozen_ok = false end
			if frame == 15 + 180 then s:resume_gameplay() end
		end
	end)
	T.eq(paused_frames, 180, "paused for 3 s of ticks")
	T.ok(frozen_ok, "board, positions and fx frozen while gameplay-paused")
	T.eq(sim.board:dump(true), ref_sim.board:dump(true), "same final board")
	T.ok(events == ref_events, "same event sequence (gameplay_unpaused filtered)")
	T.ok(math.abs((sim.now - ref_sim.now) - 3.0) < 0.02, "sim time longer by the 3 s pause: " .. (sim.now - ref_sim.now))
end)

T.done()
