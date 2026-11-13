local _, ns = ...
-- Board simulation: a direct port of the scenes/board.gd await chain (swap ->
-- resolve passes -> fuse -> ability drain hook -> gravity/refill -> cascade) onto
-- the event-driven scheduler (core/scheduler.lua). Board primitives used by
-- abilities live in core/board_effects.lua and are installed as Sim methods.
--
-- Time: every board animation is a gameplay-time wait (frozen by the
-- gameplay-pause gate). Motion is computed in core from gameplay time and
-- written to gem.x / gem.y (float cell coordinates) and gem.fx / gem.fx_t at
-- the end of each tick, so the view only reads.
--
-- Events (sim:on(name, fn)): match_resolved(length, gems, depth, dest_col, dest_row, spawn_tier)
-- (dest = where the gems converge, W0-P6),
-- gems_cleared(counts, order) (counts[type] = n, order = types in first-cleared
-- order), swap_rejected(a, b), board_settled, board_shuffled(ok), ability_activated(info),
-- ability_gem_spawned(col, row, tier, type), gems_cleared_by_effect(info),
-- junk_spawned(gems), gravity_slow_changed(active, remaining, max),
-- need_ability_drain, abilities_drained, gameplay_unpaused,
-- gem_created(gem), gem_removed(gem), flash(kind, cells, duration) (cells =
-- flat {c1, r1, c2, r2, ...}), chain_hop(from_c, from_r, to_c, to_r).

local setmetatable, pairs, type, tonumber = setmetatable, pairs, type, tonumber
local min, max = math.min, math.max

local Sim = {}
Sim.__index = Sim

local Board, Match, T
local SETTLED, SWAPPING, FALLING, CLEARING = 0, 1, 2, 3

-- Easing ids for gem motion.
local LINEAR, CUBIC_OUT, QUAD_IN, CUBIC_IN = 0, 1, 2, 3

local linked = false
-- Resolve module references and install Scheduler + BoardEffects methods
-- (lazy: files load in TOC order, and the globals lint loads each file alone).
local function link()
	if linked then return end
	Board, Match, T = ns.Board, ns.Match, ns.Timings
	-- Method install only; iteration order is irrelevant (no name clashes decide outcomes).
	for k, v in pairs(ns.Scheduler) do
		if Sim[k] == nil and k ~= "__index" then Sim[k] = v end
	end
	for k, v in pairs(ns.BoardEffects) do
		if Sim[k] == nil then Sim[k] = v end
	end
	linked = true
end

-- opts: seed, cols, rows, colors, rng_refill, rng_effects (injectable streams),
-- board (prebuilt/deserialized Board; otherwise a fresh filled board),
-- bombs_trigger_adjacent, timings (default ns.Timings), traceback, max_dt,
-- release_on_settle (standalone rule until combat exists: lift spawn
-- protection on board_settled, like battle_controller.on_board_settled with an
-- empty ability queue).
function Sim.new(opts)
	link()
	opts = opts or {}
	local self = setmetatable({}, Sim)
	ns.Scheduler.init(self, opts)
	self.T = opts.timings or T
	local board = opts.board
	if board == nil then
		board = Board.new(opts)
		board:fill()
	end
	self.board = board
	self.resolving = false
	self.dirty = false
	self.awaiting_drain = false
	self.drain_completed = false
	self.defer_gravity = false
	self.swap_a, self.swap_b = nil, nil
	self.drain_fn = nil
	self.slow_factor = 1.0
	self.slow_until = nil -- gameplay time the gravity slow ends (nil = inactive)
	self.slow_max = 0
	self.slow_gen = 0
	self.on_tick_end = Sim.update_visuals
	if opts.release_on_settle then
		self:on("board_settled", function() self:release_spawn_protection() end)
	end
	return self
end

---------------------------------------------------------------- motion (core-owned)

local function ease(kind, p)
	if kind == CUBIC_OUT then
		local q = 1 - p
		return 1 - q * q * q
	elseif kind == QUAD_IN then
		return p * p
	elseif kind == CUBIC_IN then
		return p * p * p
	end
	return p
end

-- Current visual position of a gem at the exact gameplay time.
function Sim:gem_pos(gem)
	if not gem.moving then return gem.x, gem.y end
	local p = (self:gnow() - gem.mt0) / gem.mdur
	if p >= 1 then return gem.mx1, gem.my1 end
	if p < 0 then p = 0 end
	local e = ease(gem.mease, p)
	return gem.mx0 + (gem.mx1 - gem.mx0) * e, gem.my0 + (gem.my1 - gem.my0) * e
end

-- Start a motion from the gem's current position (a new motion replaces a
-- running one - see "gravity race" in docs/design/wow-addon.md).
function Sim:_move(gem, tx, ty, dur, kind)
	local x, y = self:gem_pos(gem)
	gem.x, gem.y = x, y
	gem.mx0, gem.my0, gem.mx1, gem.my1 = x, y, tx, ty
	gem.mt0, gem.mdur, gem.mease = self:gnow(), dur, kind
	gem.moving = dur > 0
	if not gem.moving then gem.x, gem.y = tx, ty end
end

function Sim:_place(gem, x, y)
	gem.moving = false
	gem.x, gem.y = x, y
end

-- Visual effect with progress (view maps kind -> scale/alpha curve).
function Sim:_fx(gem, kind, dur, delay)
	gem.fx = kind
	gem.fx_t0 = self:gnow() + (delay or 0)
	gem.fx_dur = dur
	gem.fx_t = 0
end

-- Write x/y/fx_t of every gem in the grid (tick end; allocation-free).
function Sim:update_visuals()
	local board = self.board
	local cells = board.cells
	local g = self:gnow()
	for i = 1, board.cols * board.rows do
		local gem = cells[i]
		if gem ~= nil then
			if gem.moving then
				local p = (g - gem.mt0) / gem.mdur
				if p >= 1 then
					gem.moving = false
					gem.x, gem.y = gem.mx1, gem.my1
				else
					if p < 0 then p = 0 end
					local e = ease(gem.mease, p)
					gem.x = gem.mx0 + (gem.mx1 - gem.mx0) * e
					gem.y = gem.my0 + (gem.my1 - gem.my0) * e
				end
			end
			if gem.fx ~= nil then
				local d = gem.fx_dur
				local p = d > 0 and (g - gem.fx_t0) / d or 1
				if p < 0 then p = 0 elseif p > 1 then p = 1 end
				gem.fx_t = p
			end
		end
	end
end

---------------------------------------------------------------- helpers

local function contains(list, x)
	if x == nil then return false end
	for i = 1, #list do
		if list[i] == x then return true end
	end
	return false
end

function Sim:_free_gem(gem)
	gem.removed = true
	gem.moving = false
	self:emit("gem_removed", gem)
end

---------------------------------------------------------------- swap

-- Single swap entry point (Godot request_swap + BoardInput gate subset).
-- Returns "ok" (the swap runs; it may still be rejected -> swap_rejected) or a
-- reason: "invalid", "paused", "unsettled", "not_adjacent".
function Sim:try_swap(a, b)
	if a == nil or b == nil or a.removed or b.removed then return "invalid" end
	if self.gameplay_paused then return "paused" end
	if a.state ~= SETTLED or b.state ~= SETTLED then return "unsettled" end
	if not Board.are_adjacent(a, b) then return "not_adjacent" end
	self:spawn(Sim._swap_co, self, a, b)
	return "ok"
end

function Sim:try_swap_cells(c1, r1, c2, r2)
	local board = self.board
	if not board:in_bounds(c1, r1) or not board:in_bounds(c2, r2) then return "invalid" end
	return self:try_swap(board:get(c1, r1), board:get(c2, r2))
end

function Sim:_swap_slots(a, b)
	local board = self.board
	local c1, r1, c2, r2 = a.col, a.row, b.col, b.row
	board:set(c1, r1, b)
	board:set(c2, r2, a)
	a.col, a.row = c2, r2
	b.col, b.row = c1, r1
end

function Sim:_tween_swap(a, b)
	local d = self.T.SWAP
	self:_move(a, a.col, a.row, d, CUBIC_OUT)
	self:_move(b, b.col, b.row, d, CUBIC_OUT)
	self:wait(d)
end

function Sim._swap_co(self, a, b)
	-- Player swap overrides spawn protection (Dota: deliberately firing a fresh ult).
	a.protected = false
	b.protected = false
	self:_swap_slots(a, b)
	local created = Match.involves(self.board, a, b)
	a.state, b.state = SWAPPING, SWAPPING
	self:_tween_swap(a, b)
	if created then
		self:emit("swap_accepted", a, b) -- valid swap (view: short bling)
		a.state, b.state = SETTLED, SETTLED
		self.swap_a, self.swap_b = a, b
		self:_request_resolve()
	else
		self:emit("swap_rejected", a, b) -- W0-P7: the two gems (additive payload; the view shakes them)
		self:_swap_slots(a, b)
		self:_tween_swap(a, b)
		a.state, b.state = SETTLED, SETTLED
		self:_request_resolve()
	end
end

---------------------------------------------------------------- resolve driver

function Sim:_request_resolve()
	self.dirty = true
	if self.resolving then return end
	self.resolving = true
	self:spawn(Sim._resolve_loop, self)
end

function Sim._resolve_loop(self)
	local depth = 1
	while self.dirty do
		self.dirty = false
		self:wait_if_paused()
		if self:_resolve_pass(depth) then
			self.dirty = true
			depth = depth + 1
		end
	end
	self.resolving = false
	self:_on_driver_idle()
end

-- Ability clears/converts call this; cascades run after the ability queue drains.
function Sim:mark_resolve_needed()
	self.dirty = true
	if self.resolving or self.awaiting_drain then return end
	self:_request_resolve()
end

-- Combat drain hook: fn(sim) runs as a sim coroutine when a pass queued
-- activations; the board continues when it returns (if it returns a function,
-- also until that predicate is true). nil = drained immediately.
function Sim:set_drain(fn)
	self.drain_fn = fn
end

function Sim._run_drain(self)
	local cond = self.drain_fn(self)
	if type(cond) == "function" then self:wait_until(cond) end
	self:notify_abilities_drained()
end

function Sim:_need_ability_drain()
	self:emit("need_ability_drain")
	if self.drain_fn then
		self:spawn(Sim._run_drain, self)
	else
		self:notify_abilities_drained()
	end
end

function Sim:notify_abilities_drained()
	self.drain_completed = true
	self:emit("abilities_drained")
end

function Sim:_on_driver_idle()
	local board = self.board
	if not board:is_fully_settled() then return end
	-- Before the emit: a settle handler's convert (leftover drain) marks anew.
	board:clear_convert_marks()
	self:emit("board_settled")
	-- A settle handler may have started a new resolve (release_spawn_protection).
	if self.resolving or not board:is_fully_settled() then return end
	if Match.find_possible_move(board) == nil then
		-- false: no move could be made (bounded loop, see Board:shuffle_board)
		self:emit("board_shuffled", board:shuffle_board())
	end
end

local function activation(gem, source, partner, match_length)
	return {
		col = gem.col, row = gem.row, gem_type = gem.type, tier = gem.tier,
		is_bomb = gem.bomb, partner_color = partner, source = source, match_length = match_length,
	}
end
Sim._activation = activation

-- One resolve pass (board.gd _resolve_pass). Returns true if matches were found.
function Sim:_resolve_pass(depth)
	local board = self.board
	local regions = Match.find_matches(board)
	if #regions == 0 then return false end

	local sa, sb = self.swap_a, self.swap_b
	local is_swap_pass = sa ~= nil or sb ~= nil
	local unique, unique_set = {}, {}
	local jobs, activations = {}, {}

	for i = 1, #regions do
		local region = regions[i]
		local gems = region.gems
		local color = gems[1].type
		local tier = Match.tier_for_region(gems, region.length)
		local spawn
		if tier > 0 and board.spawn_ability_gems then
			local sg
			if is_swap_pass then
				if contains(gems, sa) then
					sg = sa
				elseif contains(gems, sb) then
					sg = sb
				end
			end
			if sg == nil then sg = Match.center_gem(gems) end
			spawn = { col = sg.col, row = sg.row, tier = tier, type = color, keep = sg }
		end
		local center = Match.center_gem(gems)
		jobs[#jobs + 1] = { gems = gems, spawn = spawn, center = center }
		-- W0-P6: where the gems converge (the ability spawn cell, else the centre gem's cell) and the spawned
		-- tier (0 = none), as extra trailing payload for the view; the pass itself is unchanged.
		local dest = spawn ~= nil and spawn.keep or center
		self:emit("match_resolved", region.length, gems, depth, dest.col, dest.row, spawn ~= nil and spawn.tier or 0)

		for k = 1, #gems do
			local gem = gems[k]
			if not unique_set[gem] then
				unique_set[gem] = true
				unique[#unique + 1] = gem
			end
			if Board.is_ability_gem(gem) then
				local partner = -1
				if gem == sa and sb ~= nil then
					partner = sb.type
				elseif gem == sb and sa ~= nil then
					partner = sa.type
				end
				activations[#activations + 1] = activation(gem, "match", partner, region.length)
			end
		end
	end

	self.swap_a, self.swap_b = nil, nil

	local to_clear = self:_expand_with_adjacent_junk(unique)
	local adjacent = {}
	for i = 1, #to_clear do
		local gem = to_clear[i]
		if gem.junk and not unique_set[gem] then
			-- Claim it now: the fuse/drain waits let ability clears run (#32).
			gem.state = CLEARING
			adjacent[#adjacent + 1] = gem
		end
	end
	local bombs = self:_adjacent_triggered_bombs(unique, unique_set)
	for i = 1, #bombs do
		local bomb = bombs[i]
		bomb.state = CLEARING
		adjacent[#adjacent + 1] = bomb
		to_clear[#to_clear + 1] = bomb
		activations[#activations + 1] = activation(bomb, "adjacent", -1, 0)
	end
	self:_emit_gems_cleared(to_clear)

	-- A killing blow may pause gameplay: hold before animation / cascade work.
	self:wait_if_paused()

	for i = 1, #activations do
		self:emit("ability_activated", activations[i])
	end

	self.defer_gravity = true
	local fuse = self:_begin_match_fuses(jobs)

	if #activations > 0 then
		self.awaiting_drain = true
		self.drain_completed = false
		self:_need_ability_drain()
	end

	if fuse.animated then self:wait(self.T.FUSE) end
	self:_complete_match_fuses(fuse)

	-- Junk next to matched gems pops with the wave (0 damage).
	if #adjacent > 0 then
		self:_animate_clear(adjacent)
		self:_remove_cleared(adjacent)
	end

	if #activations > 0 then
		if not self.drain_completed then self:wait_event("abilities_drained") end
		self.awaiting_drain = false
	end

	self.defer_gravity = false
	self:_animate_gravity_and_spawn()
	self:wait_if_paused()
	return true
end

-- Mark CLEARING + start the fuse motions. Returns the state for completion.
function Sim:_begin_match_fuses(jobs)
	local st = { animated = false, to_free = {}, keep = {}, keep_spawn = {} }
	if #jobs == 0 then return st end
	for i = 1, #jobs do
		local spawn = jobs[i].spawn
		if spawn ~= nil and spawn.keep ~= nil and not st.keep_spawn[spawn.keep] then
			st.keep_spawn[spawn.keep] = spawn
			st.keep[#st.keep + 1] = spawn.keep
		end
	end
	local free_set = {}
	local d = self.T.FUSE
	for i = 1, #jobs do
		local job = jobs[i]
		local dx, dy
		if job.spawn ~= nil then
			dx, dy = job.spawn.col, job.spawn.row
		else
			dx, dy = self:gem_pos(job.center)
		end
		local gems = job.gems
		for k = 1, #gems do
			local gem = gems[k]
			if not gem.removed then
				gem.state = CLEARING
				st.animated = true
				self:_move(gem, dx, dy, d, CUBIC_IN)
				if st.keep_spawn[gem] then
					self:_fx(gem, "fuse_keep", d)
				else
					if not free_set[gem] then
						free_set[gem] = true
						st.to_free[#st.to_free + 1] = gem
					end
					self:_fx(gem, "fuse", d)
				end
			end
		end
	end
	return st
end

function Sim:_complete_match_fuses(st)
	local board = self.board
	local to_free = st.to_free
	for i = 1, #to_free do
		local gem = to_free[i]
		if not gem.removed then
			if board:get(gem.col, gem.row) == gem then board:set(gem.col, gem.row, nil) end
			self:_free_gem(gem)
		end
	end
	local pops
	local keep = st.keep
	for i = 1, #keep do
		local gem = keep[i]
		if not gem.removed then
			local spawn = st.keep_spawn[gem]
			Board.set_bomb(gem, false)
			board:set(spawn.col, spawn.row, gem)
			gem.col, gem.row = spawn.col, spawn.row
			self:_place(gem, spawn.col, spawn.row)
			Board.set_gem_type(gem, spawn.type)
			Board.set_tier(gem, spawn.tier)
			gem.marked = false
			gem.protected = true
			gem.state = SETTLED
			gem.fx = nil
			self:emit("ability_gem_spawned", spawn.col, spawn.row, spawn.tier, spawn.type)
			pops = pops or {}
			pops[#pops + 1] = gem
		end
	end
	if pops ~= nil then
		local d = self.T.ABILITY_POP
		for i = 1, #pops do self:_fx(pops[i], "pop", d) end
		self:wait(d)
	end
end

-- Clear animation (scale up + fade) for all live gems.
function Sim:_animate_clear(gems, dur)
	dur = dur or self.T.CLEAR
	local any = false
	for i = 1, #gems do
		local gem = gems[i]
		if not gem.removed then
			gem.state = CLEARING
			self:_fx(gem, "clear", dur)
			any = true
		end
	end
	if any then self:wait(dur) end
end

-- Staggered pop in input order: total (n - 1) * step + dur.
function Sim:_animate_clear_staggered(gems, dur, step)
	dur = dur or self.T.CLEAR
	step = step or self.T.CLEAR_STAGGER_STEP
	local n = 0
	for i = 1, #gems do
		local gem = gems[i]
		if not gem.removed then
			gem.state = CLEARING
			self:_fx(gem, "clear", dur, n * step)
			n = n + 1
		end
	end
	if n > 0 then self:wait((n - 1) * step + dur) end
end

function Sim:_remove_cleared(gems)
	local board = self.board
	for i = 1, #gems do
		local gem = gems[i]
		if not gem.removed then
			if board:get(gem.col, gem.row) == gem then board:set(gem.col, gem.row, nil) end
			self:_free_gem(gem)
		end
	end
end

---------------------------------------------------------------- gravity

function Sim:_fall_duration(distance)
	local T_ = self.T
	local base = T_.FALL_PER_CELL * distance
	if base < T_.FALL_PER_CELL then base = T_.FALL_PER_CELL end
	if base > T_.FALL_CAP then base = T_.FALL_CAP end
	if self.slow_until ~= nil and self.slow_factor > 0 then
		return base / self.slow_factor
	end
	return base
end

-- Collapse one column bottom-up and spawn refills above the board (no match
-- avoidance; colours from the refill stream, top row first). Appends
-- gem, duration pairs to `moves`. Moves ANY non-nil gem (also SWAPPING /
-- CLEARING) - ported as-is from Godot.
function Sim:_collapse_column(col, moves)
	local board = self.board
	local rows = board.rows
	local write = rows - 1
	for read = rows - 1, 0, -1 do
		local gem = board:get(col, read)
		if gem ~= nil then
			if read ~= write then
				board:set(col, write, gem)
				board:set(col, read, nil)
				local old = gem.row
				gem.col, gem.row = col, write
				moves[#moves + 1] = gem
				moves[#moves + 1] = self:_fall_duration(write - old)
			end
			write = write - 1
		end
	end
	local empty = write + 1
	for i = 0, empty - 1 do
		local gem = board:new_gem(col, i, board:roll_type())
		gem.x, gem.y = col, i - empty
		gem.state = FALLING
		board:set(col, i, gem)
		self:emit("gem_created", gem)
		moves[#moves + 1] = gem
		moves[#moves + 1] = self:_fall_duration(empty)
	end
end

-- board.gd _animate_gravity_and_spawn: all moves fall in parallel (quad
-- ease-in), then a LAND pose; the gems turn SETTLED only after both.
function Sim:_animate_gravity_and_spawn()
	local moves = {}
	for col = 0, self.board.cols - 1 do
		self:_collapse_column(col, moves)
	end
	if #moves == 0 then return end
	local longest = 0
	for i = 1, #moves, 2 do
		local gem, d = moves[i], moves[i + 1]
		gem.state = FALLING
		self:_fx(gem, "fall", d)
		self:_move(gem, gem.col, gem.row, d, QUAD_IN)
		if d > longest then longest = d end
	end
	self:wait(longest)
	local land = self.T.LAND
	for i = 1, #moves, 2 do
		local gem = moves[i]
		if not gem.removed then self:_fx(gem, "land", land) end
	end
	self:wait(land)
	for i = 1, #moves, 2 do
		local gem = moves[i]
		if not gem.removed then
			gem.fx = nil
			gem.state = SETTLED
		end
	end
end

---------------------------------------------------------------- gravity slow (M1-G9)

function Sim._slow_timer(self, gen, duration)
	self:wait(duration)
	if self.slow_gen == gen then self:clear_gravity_slow() end
end

-- Every fall (incl. the cap) takes 1 / factor as long for `duration` s of
-- gameplay time. A new call replaces the running window.
function Sim:set_gravity_slow(factor, duration)
	if duration <= 0 or factor <= 0 then return end
	self.slow_factor = min(factor, 1.0)
	self.slow_until = self:gnow() + duration
	self.slow_max = duration
	self.slow_gen = self.slow_gen + 1
	self:spawn_service(Sim._slow_timer, self, self.slow_gen, duration)
	self:emit("gravity_slow_changed", true, duration, duration)
end

function Sim:clear_gravity_slow()
	local was_active = self.slow_until ~= nil
	self.slow_gen = self.slow_gen + 1
	self.slow_until = nil
	self.slow_max = 0
	self.slow_factor = 1.0
	if was_active then self:emit("gravity_slow_changed", false, 0, 0) end
end

function Sim:get_gravity_slow_remaining()
	if self.slow_until == nil then return 0 end
	return max(self.slow_until - self:gnow(), 0)
end

function Sim:get_gravity_slow_factor()
	return self.slow_until ~= nil and self.slow_factor or 1.0
end

---------------------------------------------------------------- spawn protection

function Sim:clear_spawn_protection()
	self.board:clear_spawn_protection()
end

-- Settle path (battle_controller.on_board_settled): lift protection, then
-- resolve any line it was blocking (M0-G4).
function Sim:release_spawn_protection()
	self.board:clear_spawn_protection()
	if #Match.find_matches(self.board) > 0 then self:mark_resolve_needed() end
end

-- Debug/ability helper (board.gd spawn_ability_gem).
function Sim:spawn_ability_gem(col, row, tier, gem_type)
	local board = self.board
	if not board:in_bounds(col, row) then return end
	local gem = board:get(col, row)
	if gem == nil then return end
	Board.set_bomb(gem, false)
	Board.set_gem_type(gem, gem_type)
	Board.set_tier(gem, tier)
	gem.protected = true
	self:emit("ability_gem_spawned", col, row, tier, gem_type)
end

---------------------------------------------------------------- rest / snapshot

-- Nothing in flight: no board coroutine alive, every gem settled.
function Sim:is_at_rest()
	return not self.resolving and not self:has_work() and self.board:is_fully_settled()
end

-- Run all pending board work with unbounded virtual time (no animation wait).
-- Reaches the same final board as ticking. Returns true when at rest.
function Sim:settle_now()
	if not self:run_until_idle() then return false end
	return self:is_at_rest()
end

Sim.SNAPSHOT_VERSION = 1

-- Snapshot at rest only (coroutines are not serialisable).
function Sim:serialize()
	if not self:is_at_rest() then return nil, "not at rest" end
	local board, err = self.board:serialize()
	if board == nil then return nil, err end
	return {
		v = Sim.SNAPSHOT_VERSION,
		board = board,
		slow_factor = self.slow_factor,
		slow_remaining = self:get_gravity_slow_remaining(),
		slow_max = self.slow_max,
	}
end

-- Returns a sim or nil + reason. opts as Sim.new (board / streams ignored).
function Sim.deserialize(data, opts)
	if type(data) ~= "table" or data.v ~= Sim.SNAPSHOT_VERSION then return nil, "version" end
	link()
	local board, err = Board.deserialize(data.board)
	if board == nil then return nil, err end
	local o = {}
	if opts then
		for k, v in pairs(opts) do o[k] = v end -- copy only; order irrelevant
	end
	o.board = board
	local sim = Sim.new(o)
	local rem = tonumber(data.slow_remaining) or 0
	if rem > 0 then
		sim:set_gravity_slow(data.slow_factor, rem)
		sim.slow_max = data.slow_max
	end
	return sim
end

ns.Sim = Sim
