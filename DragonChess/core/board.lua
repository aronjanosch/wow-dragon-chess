local _, ns = ...
-- Pure grid state (port of the data half of scenes/board.gd + scenes/gem.gd).
-- No rendering, no time: the sim (core/sim.lua) drives motion and resolution.
--
-- Cells: flat array `cells[col * rows + row + 1]` (col/row are 0-based like
-- Godot; use board:get / board:set). Gem tables:
--   id, type (0..colors-1), tier (0 plain / 1 skill / 2 ult), bomb, junk,
--   protected (spawn protection), marked (convert mark), state (Board.SETTLED..),
--   col, row (logical cell), x, y (float cell position for the view, written by
--   the sim), fx / fx_t (current visual effect + progress 0..1), removed (freed).

local setmetatable = setmetatable
local concat = table.concat
local type = type

local Board = {}
Board.__index = Board

-- Gem states, same order as Gem.State in scenes/gem.gd.
Board.SETTLED = 0
Board.SWAPPING = 1
Board.FALLING = 2
Board.CLEARING = 3

local SETTLED = Board.SETTLED

Board.SNAPSHOT_VERSION = 1

-- opts: cols (8), rows (8), colors (6), seed, rng_refill, rng_effects
-- (injectable streams; default Rng.fork(seed, SALT.*)), bombs_trigger_adjacent
-- (false), spawn_ability_gems (true).
function Board.new(opts)
	opts = opts or {}
	local self = setmetatable({}, Board)
	self.cols = opts.cols or 8
	self.rows = opts.rows or 8
	self.colors = opts.colors or 6
	local Rng = ns.Rng
	local seed = opts.seed or 0
	self.rng_refill = opts.rng_refill or Rng.fork(seed, Rng.SALT.refill)
	self.rng_effects = opts.rng_effects or Rng.fork(seed, Rng.SALT.effects)
	-- Run rule kept because Godot has it (Wildcard Bombs boon); default off.
	self.bombs_trigger_adjacent = opts.bombs_trigger_adjacent or false
	self.spawn_ability_gems = opts.spawn_ability_gems ~= false
	self.cells = {}
	self.next_id = 1
	return self
end

function Board:in_bounds(col, row)
	return col >= 0 and col < self.cols and row >= 0 and row < self.rows
end

function Board:get(col, row)
	return self.cells[col * self.rows + row + 1]
end

function Board:set(col, row, gem)
	self.cells[col * self.rows + row + 1] = gem
end

-- New gem table (not placed in the grid).
function Board:new_gem(col, row, gem_type)
	local id = self.next_id
	self.next_id = id + 1
	return {
		id = id, type = gem_type, tier = 0, bomb = false, junk = false,
		protected = false, marked = false, state = SETTLED,
		col = col, row = row, x = col, y = row, fx = nil, fx_t = 0, removed = false,
	}
end

-- Random plain colour from the refill stream (Godot _roll_gem_type).
function Board:roll_type()
	return self.rng_refill:range_i(0, self.colors - 1)
end

-- Gem mutators (scenes/gem.gd setters: the junk/tier/bomb interplay matters).
function Board.set_gem_type(gem, t)
	gem.type = t
	if gem.junk then Board.set_junk(gem, false) end
end

function Board.set_tier(gem, tier)
	if tier > 0 then gem.junk = false end
	gem.tier = tier
end

function Board.set_bomb(gem, value)
	gem.bomb = value
	if value then gem.junk = false end
end

function Board.set_junk(gem, value)
	gem.junk = value
	if value then
		gem.tier = 0
		gem.bomb = false
	end
end

function Board.is_ability_gem(gem)
	return gem.tier > 0 or gem.bomb
end

-- Colour for matching at a cell, -1 if out of bounds / empty / unsettled / junk
-- (Godot get_type_at; note: spawn protection is NOT checked here).
function Board:type_at(col, row)
	if col < 0 or col >= self.cols or row < 0 or row >= self.rows then return -1 end
	local gem = self.cells[col * self.rows + row + 1]
	if gem == nil or gem.state ~= SETTLED or gem.junk then return -1 end
	return gem.type
end

function Board.are_adjacent(a, b)
	local dc, dr = a.col - b.col, a.row - b.row
	if dc < 0 then dc = -dc end
	if dr < 0 then dr = -dr end
	return (a.col == b.col and dr == 1) or (a.row == b.row and dc == 1)
end

function Board:is_fully_settled()
	local cells = self.cells
	for i = 1, self.cols * self.rows do
		local gem = cells[i]
		if gem == nil or gem.state ~= SETTLED then return false end
	end
	return true
end

-- Initial fill (Godot _init_grid): column by column, then clear initial matches,
-- reshuffle if there is no move.
function Board:fill()
	for col = 0, self.cols - 1 do
		for row = 0, self.rows - 1 do
			self:set(col, row, self:new_gem(col, row, self:roll_type()))
		end
	end
	self:clear_initial_matches()
	if ns.Match.find_possible_move(self) == nil then
		self:shuffle_board()
	end
	return self
end

-- Re-roll plain gems of every match until none is left (max 100 attempts).
function Board:clear_initial_matches()
	local Match = ns.Match
	for _ = 1, 100 do
		local regions = Match.find_matches(self)
		if #regions == 0 then return true end
		for i = 1, #regions do
			local gems = regions[i].gems
			for k = 1, #gems do
				local gem = gems[k]
				if gem.tier == 0 and not gem.bomb and not gem.junk then
					Board.set_gem_type(gem, self:roll_type())
				end
			end
		end
	end
	return false
end

-- No-moves reshuffle (Godot shuffle_board): re-roll every plain gem until a
-- move exists. Needs a full grid. DIVERGENCE: Godot loops without a bound, which
-- never ends when the plain gems can't form a move (e.g. a board almost full of
-- junk / ability gems) - a client freeze in WoW. Capped at MAX_SHUFFLES rounds;
-- returns false if no move could be made (identical result whenever Godot ends).
Board.MAX_SHUFFLES = 1000

function Board:shuffle_board()
	local Match = ns.Match
	local rounds = 0
	while Match.find_possible_move(self) == nil do
		rounds = rounds + 1
		if rounds > Board.MAX_SHUFFLES then return false end
		for col = 0, self.cols - 1 do
			for row = 0, self.rows - 1 do
				local gem = self:get(col, row)
				if gem.tier == 0 and not gem.bomb and not gem.junk then
					Board.set_gem_type(gem, self:roll_type())
				end
			end
		end
		self:clear_initial_matches()
	end
	return true
end

-- Settled non-junk gem counts per colour. Returns counts (counts[type] = n)
-- and the colours in board scan order (column by column) - Godot count_colors()
-- key order, which decides random partner picks.
function Board:count_colors()
	local counts, order = {}, {}
	for col = 0, self.cols - 1 do
		for row = 0, self.rows - 1 do
			local gem = self:get(col, row)
			if gem ~= nil and gem.state == SETTLED and not gem.junk then
				local t = gem.type
				if counts[t] == nil then
					counts[t] = 0
					order[#order + 1] = t
				end
				counts[t] = counts[t] + 1
			end
		end
	end
	return counts, order
end

function Board:clear_convert_marks()
	local cells = self.cells
	for i = 1, self.cols * self.rows do
		local gem = cells[i]
		if gem ~= nil then gem.marked = false end
	end
end

function Board:clear_spawn_protection()
	local cells = self.cells
	for i = 1, self.cols * self.rows do
		local gem = cells[i]
		if gem ~= nil then gem.protected = false end
	end
end

-- Compact text of the grid (tests, hashes). One token per cell, column-major:
-- type, tier, b(omb) / j(unk) / p(rotected) / m(arked), state.
function Board:dump(with_ids)
	local out = {}
	for col = 0, self.cols - 1 do
		for row = 0, self.rows - 1 do
			local gem = self:get(col, row)
			if gem == nil then
				out[#out + 1] = "."
			else
				out[#out + 1] = gem.type .. ":" .. gem.tier
					.. (gem.bomb and "b" or "") .. (gem.junk and "j" or "")
					.. (gem.protected and "p" or "") .. (gem.marked and "m" or "")
					.. "/" .. gem.state .. (with_ids and ("#" .. gem.id) or "")
			end
		end
	end
	return concat(out, " ")
end

-- Consistency check: every gem in exactly one cell, gem.col/row = its cell, no
-- freed gem in the grid. `need_full`: every cell occupied.
function Board:check_integrity(need_full)
	local seen = {}
	for col = 0, self.cols - 1 do
		for row = 0, self.rows - 1 do
			local gem = self:get(col, row)
			if gem == nil then
				if need_full then return false, "empty cell " .. col .. "," .. row end
			else
				if seen[gem] then
					return false, "gem #" .. gem.id .. " in two cells (" .. seen[gem] .. " and " .. col .. "," .. row .. ")"
				end
				seen[gem] = col .. "," .. row
				if gem.removed then return false, "freed gem #" .. gem.id .. " at " .. col .. "," .. row end
				if gem.col ~= col or gem.row ~= row then
					return false, "gem #" .. gem.id .. " at " .. col .. "," .. row .. " thinks it is at " .. gem.col .. "," .. gem.row
				end
			end
		end
	end
	return true
end

-- Snapshot of a board at rest (every gem settled; positions are implied).
-- Plain tables only (SavedVariables-safe). RNG streams must offer get_state().
function Board:serialize()
	if not self:is_fully_settled() then return nil, "board not at rest" end
	local gems = {}
	for i = 1, self.cols * self.rows do
		local g = self.cells[i]
		gems[i] = {
			g.id, g.type, g.tier, g.bomb and 1 or 0, g.junk and 1 or 0,
			g.protected and 1 or 0, g.marked and 1 or 0,
		}
	end
	return {
		v = Board.SNAPSHOT_VERSION, cols = self.cols, rows = self.rows, colors = self.colors,
		next_id = self.next_id, gems = gems,
		bombs_trigger_adjacent = self.bombs_trigger_adjacent,
		spawn_ability_gems = self.spawn_ability_gems,
		rng_refill = self.rng_refill:get_state(),
		rng_effects = self.rng_effects:get_state(),
	}
end

-- Returns a board or nil + reason (corrupt / other version -> caller starts fresh).
function Board.deserialize(data)
	if type(data) ~= "table" or data.v ~= Board.SNAPSHOT_VERSION then return nil, "version" end
	local cols, rows = data.cols, data.rows
	if type(cols) ~= "number" or type(rows) ~= "number" or type(data.gems) ~= "table" then return nil, "corrupt" end
	if type(data.rng_refill) ~= "table" or type(data.rng_effects) ~= "table" then return nil, "corrupt rng" end
	local Rng = ns.Rng
	local self = Board.new({
		cols = cols, rows = rows, colors = data.colors,
		rng_refill = Rng.from_state(data.rng_refill), rng_effects = Rng.from_state(data.rng_effects),
		bombs_trigger_adjacent = data.bombs_trigger_adjacent,
		spawn_ability_gems = data.spawn_ability_gems,
	})
	self.next_id = data.next_id
	for col = 0, cols - 1 do
		for row = 0, rows - 1 do
			local e = data.gems[col * rows + row + 1]
			if type(e) ~= "table" or type(e[2]) ~= "number" or e[2] < 0 or e[2] >= self.colors then
				return nil, "corrupt cell"
			end
			local g = self:new_gem(col, row, e[2])
			self.next_id = data.next_id
			g.id, g.tier = e[1], e[3]
			g.bomb, g.junk, g.protected, g.marked = e[4] == 1, e[5] == 1, e[6] == 1, e[7] == 1
			self:set(col, row, g)
		end
	end
	return self
end

ns.Board = Board
