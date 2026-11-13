-- Shared test helpers: core loading, boards from text grids, RNG tape stub,
-- event recorder.
local H = {}

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "."
H.T = dofile(here .. "/t.lua")
H.loader = dofile(here .. "/loader.lua")
H.ns = H.loader.load()

-- Cell tokens: '0'-'5' plain gem of that colour, 'a'-'f' skill (tier 1) of
-- colour 0-5, 'A'-'F' ult (tier 2), 'u'-'z' bomb of colour 0-5, 'J' junk
-- (colour 0), '.' empty. `rows` = array of strings, row 0 first.
function H.board(rows, opts)
	local ns = H.ns
	opts = opts or {}
	local b = ns.Board.new({
		cols = #rows[1], rows = #rows, colors = opts.colors or 6,
		seed = opts.seed or 1,
		rng_refill = opts.rng_refill, rng_effects = opts.rng_effects,
		bombs_trigger_adjacent = opts.bombs_trigger_adjacent,
	})
	for r = 0, #rows - 1 do
		local line = rows[r + 1]
		for c = 0, #line - 1 do
			local ch = line:sub(c + 1, c + 1)
			if ch ~= "." then
				local byte = ch:byte()
				local gem
				if ch:match("%d") then
					gem = b:new_gem(c, r, byte - 48)
				elseif ch:match("[a-f]") then
					gem = b:new_gem(c, r, byte - 97)
					gem.tier = 1
				elseif ch:match("[A-F]") then
					gem = b:new_gem(c, r, byte - 65)
					gem.tier = 2
				elseif ch:match("[u-z]") then
					gem = b:new_gem(c, r, byte - 117)
					gem.bomb = true
				elseif ch == "J" then
					gem = b:new_gem(c, r, 0)
					gem.junk = true
				else
					error("bad cell token " .. ch)
				end
				b:set(c, r, gem)
			end
		end
	end
	return b
end

-- Inverse of H.board (protection / marks not shown).
function H.rows(b)
	local out = {}
	for r = 0, b.rows - 1 do
		local line = {}
		for c = 0, b.cols - 1 do
			local g = b:get(c, r)
			local ch
			if g == nil then
				ch = "."
			elseif g.junk then
				ch = "J"
			elseif g.bomb then
				ch = string.char(117 + g.type)
			elseif g.tier == 1 then
				ch = string.char(97 + g.type)
			elseif g.tier == 2 then
				ch = string.char(65 + g.type)
			else
				ch = tostring(g.type)
			end
			line[#line + 1] = ch
		end
		out[#out + 1] = table.concat(line)
	end
	return out
end

-- RNG tape stub: replays recorded range_i results (a Godot exporter will write
-- these); `fallback` stream once the tape runs out (nil = error).
function H.tape(values, fallback)
	local t = { i = 0, values = values, fallback = fallback, draws = 0 }
	function t:range_i(lo, hi)
		self.draws = self.draws + 1
		self.i = self.i + 1
		local v = self.values[self.i]
		if v == nil then
			if self.fallback then return self.fallback:range_i(lo, hi) end
			error("rng tape exhausted")
		end
		assert(v >= lo and v <= hi, "tape value out of range")
		return v
	end
	function t:get_state() return { self.i } end
	return t
end

-- Records every event (with a short argument summary) in order.
local EVENTS = {
	"match_resolved", "gems_cleared", "swap_rejected", "board_settled", "board_shuffled",
	"ability_activated", "ability_gem_spawned", "gems_cleared_by_effect", "junk_spawned",
	"gravity_slow_changed", "need_ability_drain", "abilities_drained", "gem_created",
	"gem_removed", "flash", "gameplay_unpaused",
}
function H.record(sim)
	local log = {}
	for _, name in ipairs(EVENTS) do
		sim:on(name, function(a, b, c, d)
			local s = name
			if name == "match_resolved" then
				s = s .. " len=" .. a .. " depth=" .. c
			elseif name == "gems_cleared" then
				local parts = {}
				for _, t in ipairs(b) do parts[#parts + 1] = t .. "x" .. a[t] end
				s = s .. " " .. table.concat(parts, ",")
			elseif name == "ability_activated" then
				s = s .. " " .. a.col .. "," .. a.row .. " t" .. a.gem_type .. " tier" .. a.tier
					.. (a.is_bomb and " bomb" or "") .. " " .. a.source .. " p" .. a.partner_color
			elseif name == "ability_gem_spawned" then
				s = s .. " " .. a .. "," .. b .. " tier" .. c .. " t" .. d
			elseif name == "gem_created" or name == "gem_removed" then
				s = s .. " #" .. a.id
			elseif name == "flash" then
				s = s .. " " .. a .. " n=" .. (#b / 2)
			elseif name == "gravity_slow_changed" then
				s = s .. " " .. tostring(a)
			end
			log[#log + 1] = ("%.4f %s"):format(sim.now, s)
		end)
	end
	return log
end

-- Tick until at rest (or max_t seconds), fixed dt.
function H.run(sim, dt, max_t)
	dt = dt or 1 / 60
	max_t = max_t or 60
	local t = 0
	while t < max_t do
		sim:tick(dt)
		t = t + dt
		if sim:is_at_rest() then return true end
	end
	return false
end

-- Inject a test-local drain: executes activations FIFO through `exec(sim, info)`
-- (like battle_controller's queue), lifts spawn protection on settle.
function H.attach_combat_stub(sim, exec)
	local queue, draining = {}, false
	local function drain(s)
		if draining or #queue == 0 then return end
		draining = true
		while #queue > 0 do
			s:wait_if_paused()
			local info = table.remove(queue, 1)
			if exec then exec(s, info) end
			s:wait_if_paused()
		end
		draining = false
	end
	sim:on("ability_activated", function(info) queue[#queue + 1] = info end)
	sim:set_drain(drain)
	sim:on("board_settled", function()
		sim:spawn(function()
			drain(sim)
			sim:release_spawn_protection()
		end)
	end)
	return queue
end

---------------------------------------------------------------- combat fixtures (W0-G1)

-- 8x8 base pattern without lines: type (c + 3r) % 6; overrides {"c,r" = token}.
function H.grid(over)
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

-- Plain-hit test enemy (fields as Enemy data); opts override.
function H.enemy_def(opts)
	opts = opts or {}
	return {
		id = "dummy", name = opts.name or "Dummy", display = "dummy",
		max_health = opts.hp or 100000, weak_to_color = opts.weak or -1,
		windup = opts.windup or 0,
		rotation = opts.rotation or {
			{ id = "poke", name = "Poke", damage_min = opts.dmg or 100, damage_max = opts.dmg or 100,
				cooldown = opts.cooldown or 1000, is_special = false, execute_time = 0 },
		},
	}
end

-- Sim + Combat on a known board (H.grid(over)), fight started against `def`
-- (default: a harmless dummy). opts: seed, rng_combat, def, no_fight.
function H.fight(over, opts)
	local ns = H.ns
	opts = opts or {}
	local b = H.board(H.grid(over), { seed = opts.seed or 7, rng_effects = opts.rng_effects })
	local sim = ns.Sim.new({ board = b })
	local combat = ns.Combat.new({ sim = sim, seed = opts.seed or 7, rng_combat = opts.rng_combat })
	if not opts.no_fight then combat:start_fight(opts.def or H.enemy_def()) end
	return sim, combat
end

-- Tick (<= 0.05 s steps) until sim time reaches t.
function H.tick_to(sim, t)
	while sim.now < t - 1e-9 do
		local dt = t - sim.now
		if dt > 0.05 then dt = 0.05 end
		sim:tick(dt)
	end
end

-- Collect (time, args...) of every emit of `name`.
function H.collect(sim, name)
	local list = {}
	sim:on(name, function(...) list[#list + 1] = { t = sim.now, ... } end)
	return list
end

return H
