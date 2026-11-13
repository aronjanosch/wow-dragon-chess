local _, ns = ...
-- Ability board primitives (port of scenes/board.gd:1334-1830 + set_gravity_slow
-- in sim.lua). Logic only: telegraphs / morphs are gameplay-time waits plus a
-- `flash` event (and gem.fx) for the view. Installed as Sim methods, so call
-- them on the sim from inside a sim coroutine (they wait):
--   sim:clear_area(col, row, radius)            -> {cleared = info[], count}
--   sim:clear_row(row, origin_col)              -> {cleared, count}
--   sim:clear_wave(row, from_col, cone_spread)  -> {cleared, count}
--   sim:clear_color(type)                       -> {cleared, count}
--   sim:clear_color_chained(type, col, row)     -> {cleared, count}
--   sim:convert_color(from, to, mark)           -> converted count
--   sim:convert_random_gems(to, count, from, exclude_adjacent_to_type) -> count
--   sim:convert_random_to_bombs(count)          -> count
--   sim:set_gems_junk(count)                    -> count
-- Cell lists are flat arrays {c1, r1, c2, r2, ...}. Random picks use the
-- board's `rng_effects` stream.

local floor = math.floor
local HUGE = math.huge

local Effects = {}

local SETTLED, CLEARING = 0, 3

local function board_of(sim) return sim.board end

local function in_bounds(board, c, r)
	return c >= 0 and c < board.cols and r >= 0 and r < board.rows
end

---------------------------------------------------------------- shared clear path

-- Settled orthogonal neighbours in the order left, right, up, down.
function Effects:_adjacent_settled(gem, out)
	local board = board_of(self)
	local c, r = gem.col, gem.row
	local n = 0
	for k = 1, 4 do
		local nc, nr = c, r
		if k == 1 then nc = c - 1 elseif k == 2 then nc = c + 1 elseif k == 3 then nr = r - 1 else nr = r + 1 end
		if in_bounds(board, nc, nr) then
			local other = board:get(nc, nr)
			if other ~= nil and other.state == SETTLED then
				n = n + 1
				out[n] = other
			end
		end
	end
	for k = n + 1, 4 do out[k] = nil end
	return n
end

-- Junk clears when an orthogonally adjacent gem clears (match or effect).
function Effects:_expand_with_adjacent_junk(gems)
	local result, set = {}, {}
	for i = 1, #gems do
		local g = gems[i]
		if not set[g] then
			set[g] = true
			result[#result + 1] = g
		end
	end
	local nb = {}
	for i = 1, #gems do
		local n = self:_adjacent_settled(gems[i], nb)
		for k = 1, n do
			local other = nb[k]
			if other.junk and not set[other] then
				set[other] = true
				result[#result + 1] = other
			end
		end
	end
	return result
end

-- Wildcard Bombs rule (off by default): settled, unprotected bombs next to `gems`.
function Effects:_adjacent_triggered_bombs(gems, exclude)
	local out = {}
	if not board_of(self).bombs_trigger_adjacent then return out end
	local seen, nb = {}, {}
	for i = 1, #gems do
		local gem = gems[i]
		if not gem.removed then
			local n = self:_adjacent_settled(gem, nb)
			for k = 1, n do
				local other = nb[k]
				if other.bomb and not other.protected and not exclude[other] and not seen[other] then
					seen[other] = true
					out[#out + 1] = other
				end
			end
		end
	end
	return out
end

-- gems_cleared(counts, order): damaging clears only (junk = 0).
function Effects:_emit_gems_cleared(gems)
	local counts, order = {}, {}
	for i = 1, #gems do
		local gem = gems[i]
		if not gem.junk then
			local t = gem.type
			if counts[t] == nil then
				counts[t] = 0
				order[#order + 1] = t
			end
			counts[t] = counts[t] + 1
		end
	end
	self:emit("gems_cleared", counts, order)
end

local function cleared_entry(gem, with_junk)
	return {
		col = gem.col, row = gem.row, gem_type = gem.type, ability_tier = gem.tier,
		is_bomb = gem.bomb, is_junk = with_junk and gem.junk or nil,
	}
end

function Effects:_scan_cells(cells)
	local board = board_of(self)
	local gems, info, chain, seen = {}, {}, {}, {}
	for i = 1, #cells, 2 do
		local c, r = cells[i], cells[i + 1]
		if in_bounds(board, c, r) then
			local gem = board:get(c, r)
			-- Same-wave spawns survive sibling ability AOEs (spawn protection).
			if gem ~= nil and gem.state == SETTLED and not gem.protected and not seen[gem] then
				seen[gem] = true
				gems[#gems + 1] = gem
				info[#info + 1] = cleared_entry(gem, false)
				if gem.tier > 0 or gem.bomb then
					chain[#chain + 1] = self._activation(gem, "chain", -1, 0)
				end
			end
		end
	end
	return gems, info, chain
end

-- board.gd _clear_cells: scan -> damage events -> pop -> (gravity) -> chains.
function Effects:_clear_cells(cells, staggered, dur)
	dur = dur or self.T.CLEAR
	-- A killing blow from the ability's direct damage pauses first: the
	-- leftover board work then hits the next enemy.
	self:wait_if_paused()

	local gems, info, chain = self:_scan_cells(cells)
	if #gems == 0 then return { cleared = info, count = 0 } end

	gems = self:_expand_with_adjacent_junk(gems)
	local clearing = {}
	for i = 1, #gems do clearing[gems[i]] = true end
	local bombs = self:_adjacent_triggered_bombs(gems, clearing)
	for i = 1, #bombs do
		local bomb = bombs[i]
		bomb.state = CLEARING -- no other clear may trigger it meanwhile
		gems[#gems + 1] = bomb
		chain[#chain + 1] = self._activation(bomb, "chain", -1, 0)
	end
	info = {}
	for i = 1, #gems do info[i] = cleared_entry(gems[i], true) end

	self:_emit_gems_cleared(gems)
	self:emit("gems_cleared_by_effect", info)

	self:wait_if_paused()

	if staggered then
		self:_animate_clear_staggered(gems, dur)
	else
		self:_animate_clear(gems, dur)
	end
	self:_remove_cleared(gems)

	-- During the match+ability window, gravity is shared after the queue drains.
	if not self.defer_gravity then self:_animate_gravity_and_spawn() end

	self:wait_if_paused()

	for i = 1, #chain do self:emit("ability_activated", chain[i]) end

	if not self.defer_gravity then self:mark_resolve_needed() end

	return { cleared = info, count = #info }
end

-- Telegraph flash: waits `dur` if any cell is on the board (flash_cells).
function Effects:_flash(kind, cells, dur)
	local board = board_of(self)
	local any = false
	for i = 1, #cells, 2 do
		if in_bounds(board, cells[i], cells[i + 1]) then
			any = true
			break
		end
	end
	if not any then return end
	self:emit("flash", kind, cells, dur)
	self:wait(dur)
end

---------------------------------------------------------------- clears

function Effects:clear_area(col, row, radius)
	radius = radius or 1
	local cells = {}
	for c = col - radius, col + radius do
		for r = row - radius, row + radius do
			cells[#cells + 1] = c
			cells[#cells + 1] = r
		end
	end
	self:_flash("area", cells, self.T.FLASH_CELLS)
	return self:_clear_cells(cells)
end

-- Row cells nearest-first from origin_col (right before left per distance);
-- origin_col < 0 / off-board -> left to right.
function Effects:_row_cells_outward(row, origin_col)
	local cols = board_of(self).cols
	local cells = {}
	if origin_col == nil or origin_col < 0 or origin_col >= cols then
		for c = 0, cols - 1 do
			cells[#cells + 1] = c
			cells[#cells + 1] = row
		end
		return cells
	end
	cells[1], cells[2] = origin_col, row
	local left, right = origin_col - 1, origin_col + 1
	while left >= 0 or right < cols do
		if right < cols then
			cells[#cells + 1] = right
			cells[#cells + 1] = row
			right = right + 1
		end
		if left >= 0 then
			cells[#cells + 1] = left
			cells[#cells + 1] = row
			left = left - 1
		end
	end
	return cells
end

-- Topaz skill: staggered sweep outward from the swapped-in gem.
function Effects:clear_row(row, origin_col)
	local cells = self:_row_cells_outward(row, origin_col or -1)
	self:emit("flash", "row_sweep", cells, self.T.ROW_SWEEP) -- fire-and-forget beam
	return self:_clear_cells(cells, true, self.T.CLEAR_ROW)
end

-- Cone toward the enemy (right): half width floor(dist * spread) per column.
function Effects:_cone_cells(origin_col, origin_row, spread)
	local board = board_of(self)
	local cells = {}
	for c = origin_col, board.cols - 1 do
		local half = floor((c - origin_col) * spread)
		for r = origin_row - half, origin_row + half do
			if r >= 0 and r < board.rows then
				cells[#cells + 1] = c
				cells[#cells + 1] = r
			end
		end
	end
	return cells
end

-- Ruby skill: cone wave from the gem, then the wedge pops together.
function Effects:clear_wave(row, from_col, cone_spread)
	local board = board_of(self)
	local T = self.T
	local start = from_col or 0
	if start < 0 then start = 0 elseif start > board.cols - 1 then start = board.cols - 1 end
	local origin_row = row
	if origin_row < 0 then origin_row = 0 elseif origin_row > board.rows - 1 then origin_row = board.rows - 1 end
	local spread = cone_spread or 0.4
	if spread < 0 then spread = 0 end
	local cells = self:_cone_cells(start, origin_row, spread)
	if #cells > 0 then
		-- _animate_cone_wave: cone expand (WAVE_CONE) alongside per-column slice
		-- flashes (CLEAR_STAGGER_STEP * 2 apart), then the cone fades.
		self:wait_if_paused()
		local ncols = board.cols - start
		self:emit("flash", "wave", cells, T.WAVE_CONE)
		self:wait(T.WAVE_CONE)
		local rest = ncols * T.CLEAR_STAGGER_STEP * 2 - T.WAVE_CONE
		if rest > 0 then self:wait(rest) end
		self:wait(T.WAVE_CONE_FADE)
	end
	return self:_clear_cells(cells, false, T.CLEAR_ROW)
end

function Effects:_cells_of_type(gem_type)
	local board = board_of(self)
	local cells = {}
	for c = 0, board.cols - 1 do
		for r = 0, board.rows - 1 do
			local gem = board:get(c, r)
			if gem ~= nil and gem.state == SETTLED and gem.type == gem_type then
				cells[#cells + 1] = c
				cells[#cells + 1] = r
			end
		end
	end
	return cells
end

function Effects:clear_color(gem_type)
	local cells = self:_cells_of_type(gem_type)
	self:_flash("color", cells, self.T.FLASH_CELLS)
	return self:_clear_cells(cells)
end

-- Greedy nearest-neighbour path from the origin (first index wins ties).
function Effects:_chain_order(cells, oc, orow)
	local rc, rr = {}, {}
	for i = 1, #cells, 2 do
		rc[#rc + 1] = cells[i]
		rr[#rr + 1] = cells[i + 1]
	end
	local ordered = {}
	local cc, cr = oc, orow
	while #rc > 0 do
		local best_i, best_d = 1, HUGE
		for i = 1, #rc do
			local dc, dr = rc[i] - cc, rr[i] - cr
			local d = dc * dc + dr * dr
			if d < best_d then
				best_d = d
				best_i = i
			end
		end
		cc, cr = rc[best_i], rr[best_i]
		table.remove(rc, best_i)
		table.remove(rr, best_i)
		ordered[#ordered + 1] = cc
		ordered[#ordered + 1] = cr
	end
	return ordered
end

-- Topaz ult: chain lightning hop by hop, a flash, then every struck gem pops.
function Effects:clear_color_chained(gem_type, origin_col, origin_row)
	local T = self.T
	local cells = self:_cells_of_type(gem_type)
	if #cells == 0 then return { cleared = {}, count = 0 } end
	local ordered = self:_chain_order(cells, origin_col, origin_row)
	-- _animate_chain_lightning
	self:wait_if_paused()
	local pc, pr = origin_col, origin_row
	for i = 1, #ordered, 2 do
		self:emit("chain_hop", pc, pr, ordered[i], ordered[i + 1])
		self:wait(T.CHAIN_HOP + T.CHAIN_HOP_HOLD)
		pc, pr = ordered[i], ordered[i + 1]
	end
	self:wait(T.CHAIN_FADE)
	self:_flash("chain", ordered, T.FLASH_CONVERT)
	return self:_clear_cells(ordered, false, T.CLEAR_ROW)
end

---------------------------------------------------------------- converts

-- Hold + pulse on the targets (CONVERT_TELEGRAPH), then the highlight fades.
function Effects:_telegraph(gems, kind)
	if #gems == 0 then return end
	local T = self.T
	local cells = {}
	for i = 1, #gems do
		local gem = gems[i]
		if not gem.removed then
			self:_fx(gem, "telegraph", T.CONVERT_TELEGRAPH + T.CONVERT_TELEGRAPH_FADE)
			cells[#cells + 1] = gem.col
			cells[#cells + 1] = gem.row
		end
	end
	self:emit("flash", kind or "telegraph", cells, T.CONVERT_TELEGRAPH + T.CONVERT_TELEGRAPH_FADE)
	self:wait(T.CONVERT_TELEGRAPH)
	self:wait(T.CONVERT_TELEGRAPH_FADE)
end

local function morph_alive(gem)
	return not gem.removed and gem.state ~= CLEARING
end

function Effects._morph_one(self, gem, to_type, pending, mark)
	local T = self.T
	self:_fx(gem, "morph_out", T.CONVERT_MORPH_OUT)
	self:wait(T.CONVERT_MORPH_OUT)
	if gem.removed then
		pending.n = pending.n > 0 and pending.n - 1 or 0
		return
	end
	if mark then gem.marked = true end
	ns.Board.set_gem_type(gem, to_type)
	self:_fx(gem, "morph_in", T.CONVERT_MORPH_IN)
	self:wait(T.CONVERT_MORPH_IN)
	if gem.fx == "morph_in" then gem.fx = nil end
	pending.n = pending.n > 0 and pending.n - 1 or 0
end

-- Overlapping staggered morphs (CONVERT_STAGGER real-time apart). Returns how
-- many gems were morphed (a pick cleared mid-stagger is skipped).
function Effects:_morph_staggered(gems, to_type, mark)
	local n = #gems
	if n == 0 then return 0 end
	local pending = { n = 0 }
	local morphed = 0
	for i = 1, n do
		local gem = gems[i]
		if morph_alive(gem) then
			pending.n = pending.n + 1
			morphed = morphed + 1
			self:spawn(Effects._morph_one, self, gem, to_type, pending, mark)
		end
		-- Godot: get_tree().create_timer(CONVERT_STAGGER, false) - a SceneTree
		-- timer, not stopped by the board's gameplay pause.
		if i < n then self:wait_real(self.T.CONVERT_STAGGER) end
	end
	self:wait_until(function() return pending.n <= 0 end)
	return morphed
end

-- Re-validate picks after the telegraph (#32): still live, settled at their own
-- cell and eligible.
function Effects:_still_eligible(targets, allow_ability, from_type)
	local board = board_of(self)
	local out = {}
	from_type = from_type or -1
	for i = 1, #targets do
		local gem = targets[i]
		if not gem.removed then
			local ok = gem.state == SETTLED and board:get(gem.col, gem.row) == gem
				and not gem.bomb and not gem.junk
				and (allow_ability or gem.tier == 0)
				and (from_type < 0 or gem.type == from_type)
			if ok then
				out[#out + 1] = gem
			elseif gem.state ~= CLEARING and gem.fx == "telegraph" then
				gem.fx = nil -- dropped pick loses the telegraph pop
			end
		end
	end
	return out
end

local function gems_to_cells(gems)
	local cells = {}
	for i = 1, #gems do
		local gem = gems[i]
		if not gem.removed then
			cells[#cells + 1] = gem.col
			cells[#cells + 1] = gem.row
		end
	end
	return cells
end

-- Nether Swap style: every settled `from` gem (ability gems too, not bombs /
-- junk) becomes `to`. mark: convert mark (Mind Control: caps the next region).
function Effects:convert_color(from_type, to_type, mark)
	self:wait_if_paused()
	local board = board_of(self)
	local targets = {}
	for c = 0, board.cols - 1 do
		for r = 0, board.rows - 1 do
			local gem = board:get(c, r)
			if gem ~= nil and gem.state == SETTLED and gem.type == from_type and not gem.bomb and not gem.junk then
				targets[#targets + 1] = gem
			end
		end
	end
	if #targets == 0 then return 0 end
	self:_telegraph(targets, "telegraph_from")
	self:_flash("convert_to", gems_to_cells(targets), self.T.FLASH_CONVERT)
	targets = self:_still_eligible(targets, true, from_type)
	local converted = self:_morph_staggered(targets, to_type, mark)
	self:mark_resolve_needed()
	return converted
end

local function next_to_ability_gem_of_type(board, gem, gem_type)
	local c, r = gem.col, gem.row
	for k = 1, 4 do
		local nc, nr = c, r
		if k == 1 then nc = c + 1 elseif k == 2 then nc = c - 1 elseif k == 3 then nr = r + 1 else nr = r - 1 end
		if in_bounds(board, nc, nr) then
			local other = board:get(nc, nr)
			if other ~= nil and not other.removed and other.type == gem_type and other.tier > 0 then
				return true
			end
		end
	end
	return false
end

-- Random picks of convert_random_gems (rng_effects, no animation).
function Effects:pick_convert_targets(to_type, count, from_type, exclude_adjacent_to_type)
	from_type = from_type or -1
	exclude_adjacent_to_type = exclude_adjacent_to_type or -1
	local board = board_of(self)
	local candidates = {}
	for c = 0, board.cols - 1 do
		for r = 0, board.rows - 1 do
			local gem = board:get(c, r)
			if gem ~= nil and gem.state == SETTLED and gem.tier == 0 and not gem.bomb and not gem.junk
				and gem.type ~= to_type
				and (from_type < 0 or gem.type == from_type)
				and not (exclude_adjacent_to_type >= 0 and next_to_ability_gem_of_type(board, gem, exclude_adjacent_to_type)) then
				candidates[#candidates + 1] = gem
			end
		end
	end
	ns.Rng.shuffle_with(candidates, board.rng_effects)
	local targets = {}
	for i = 1, math.min(count, #candidates) do targets[i] = candidates[i] end
	return targets
end

-- Spiderlings style: up to `count` random plain gems not already `to_type`.
function Effects:convert_random_gems(to_type, count, from_type, exclude_adjacent_to_type)
	from_type = from_type or -1
	self:wait_if_paused()
	local targets = self:pick_convert_targets(to_type, count, from_type, exclude_adjacent_to_type)
	if #targets == 0 then return 0 end
	self:_telegraph(targets, "telegraph_to")
	targets = self:_still_eligible(targets, false, from_type)
	local converted = self:_morph_staggered(targets, to_type, false)
	self:mark_resolve_needed()
	return converted
end

local function plain_settled_candidates(board)
	local candidates = {}
	for c = 0, board.cols - 1 do
		for r = 0, board.rows - 1 do
			local gem = board:get(c, r)
			if gem ~= nil and gem.state == SETTLED and gem.tier == 0 and not gem.bomb and not gem.junk then
				candidates[#candidates + 1] = gem
			end
		end
	end
	return candidates
end

-- Up to `count` random plain settled gems become bombs (instant, no telegraph).
function Effects:convert_random_to_bombs(count)
	self:wait_if_paused()
	local board = board_of(self)
	local candidates = plain_settled_candidates(board)
	ns.Rng.shuffle_with(candidates, board.rng_effects)
	local made = 0
	for i = 1, math.min(count, #candidates) do
		ns.Board.set_bomb(candidates[i], true)
		made = made + 1
	end
	return made
end

-- Up to `count` random plain settled gems become bandage junk (after a telegraph).
function Effects:set_gems_junk(count)
	self:wait_if_paused()
	local board = board_of(self)
	local candidates = plain_settled_candidates(board)
	ns.Rng.shuffle_with(candidates, board.rng_effects)
	local targets = {}
	for i = 1, math.min(count, #candidates) do targets[i] = candidates[i] end
	if #targets == 0 then return 0 end
	self:_telegraph(targets, "telegraph_junk")
	local made = {}
	local eligible = self:_still_eligible(targets, false)
	for i = 1, #eligible do
		local gem = eligible[i]
		ns.Board.set_junk(gem, true)
		if gem.fx == "telegraph" then gem.fx = nil end
		made[#made + 1] = gem
	end
	if #made > 0 then self:emit("junk_spawned", made) end
	return #made
end

ns.BoardEffects = Effects
