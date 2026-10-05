local _, ns = ...
-- Region matching and move search (port of scenes/board.gd:198-458).
-- Arrays only - every order below is the Godot order, because tie-breaks
-- (spawn cell, partner colour) depend on it.

local Match = {}

local SETTLED = 0 -- Board.SETTLED
local HUGE = math.huge

local function eligible(gem)
	return gem ~= nil and gem.state == SETTLED and not gem.junk and not gem.protected
end

-- Maximal runs >= 3 of eligible gems: horizontal runs row by row (left to
-- right), then vertical runs column by column (top to bottom). A run table is
-- only allocated for runs of 3+ (hot path: called on every swap and pass).
local function collect_runs(board)
	local runs = {}
	local cols, rows = board.cols, board.rows
	for row = 0, rows - 1 do
		local col = 0
		while col < cols do
			local gem = board:get(col, row)
			if not eligible(gem) then
				col = col + 1
			else
				local t = gem.type
				local stop = col + 1
				while stop < cols do
					local g = board:get(stop, row)
					if not eligible(g) or g.type ~= t then break end
					stop = stop + 1
				end
				if stop - col >= 3 then
					local run = {}
					for c = col, stop - 1 do run[#run + 1] = board:get(c, row) end
					runs[#runs + 1] = run
				end
				col = stop
			end
		end
	end
	for col = 0, cols - 1 do
		local row = 0
		while row < rows do
			local gem = board:get(col, row)
			if not eligible(gem) then
				row = row + 1
			else
				local t = gem.type
				local stop = row + 1
				while stop < rows do
					local g = board:get(col, stop)
					if not eligible(g) or g.type ~= t then break end
					stop = stop + 1
				end
				if stop - row >= 3 then
					local run = {}
					for r = row, stop - 1 do run[#run + 1] = board:get(col, r) end
					runs[#runs + 1] = run
				end
				row = stop
			end
		end
	end
	return runs
end
Match.collect_runs = collect_runs

local function find_root(parent, i)
	while parent[i] ~= i do
		parent[i] = parent[parent[i]]
		i = parent[i]
	end
	return i
end

local OFF_C = { 0, 1, -1, 0, 0 }
local OFF_R = { 0, 0, 0, 1, -1 }

-- Region matching (M0-G5): maximal runs, union-find merge of same-colour runs
-- whose gems share a cell or touch orthogonally. Returns an array of regions
-- `{length = n, gems = {...}}` in first-run order; gems in run order (H runs,
-- then V runs), deduplicated - the Godot dictionary insertion order.
function Match.find_matches(board)
	local runs = collect_runs(board)
	local n = #runs
	if n == 0 then return runs end
	local rows, cols = board.rows, board.cols
	-- cell index -> run indices covering it (at most one H + one V), append order.
	local runs_at = {}
	for i = 1, n do
		local run = runs[i]
		for k = 1, #run do
			local gem = run[k]
			local idx = gem.col * rows + gem.row + 1
			local list = runs_at[idx]
			if list == nil then
				list = {}
				runs_at[idx] = list
			end
			list[#list + 1] = i
		end
	end
	local parent = {}
	for i = 1, n do parent[i] = i end
	for i = 1, n do
		local run = runs[i]
		local run_type = run[1].type
		for k = 1, #run do
			local gem = run[k]
			for o = 1, 5 do
				local c, r = gem.col + OFF_C[o], gem.row + OFF_R[o]
				if c >= 0 and c < cols and r >= 0 and r < rows then
					local list = runs_at[c * rows + r + 1]
					if list ~= nil then
						for m = 1, #list do
							local j = list[m]
							if j ~= i and runs[j][1].type == run_type then
								local ra, rb = find_root(parent, i), find_root(parent, j)
								if ra ~= rb then
									if ra < rb then parent[rb] = ra else parent[ra] = rb end
								end
							end
						end
					end
				end
			end
		end
	end
	-- Group by root in first-run order.
	local region_of_root, regions, seen = {}, {}, {}
	for i = 1, n do
		local root = find_root(parent, i)
		local region = region_of_root[root]
		if region == nil then
			region = { length = 0, gems = {} }
			region_of_root[root] = region
			regions[#regions + 1] = region
		end
		local run, gems = runs[i], region.gems
		for k = 1, #run do
			local gem = run[k]
			if not seen[gem] then
				seen[gem] = true
				gems[#gems + 1] = gem
			end
		end
		region.length = #gems
	end
	return regions
end

-- True if some current region contains gem a or b (swap validity, M0-G1).
function Match.involves(board, a, b)
	local regions = Match.find_matches(board)
	for i = 1, #regions do
		local gems = regions[i].gems
		for k = 1, #gems do
			local g = gems[k]
			if g == a or g == b then return true end
		end
	end
	return false
end

-- Godot spawn_tier_for_length: 4 -> skill (1), >= 5 -> ult (2).
function Match.tier_for_length(len)
	if len == 4 then return 1 end
	if len >= 5 then return 2 end
	return 0
end

-- Capped at a skill when the region contains a convert-marked gem (M1-G8).
function Match.tier_for_region(gems, len)
	local tier = Match.tier_for_length(len)
	if tier > 1 then
		for i = 1, #gems do
			local g = gems[i]
			if not g.removed and g.marked then return 1 end
		end
	end
	return tier
end

function Match.damage_multiplier_for_length(len)
	if len >= 7 then return 1.5 end
	if len == 6 then return 1.2 end
	return 1.0
end

-- Gem nearest the region centre; first gem wins ties (strict <).
function Match.center_gem(gems)
	local n = #gems
	local ac, ar = 0, 0
	for i = 1, n do
		ac = ac + gems[i].col
		ar = ar + gems[i].row
	end
	ac, ar = ac / n, ar / n
	local best, best_d = gems[1], HUGE
	for i = 1, n do
		local g = gems[i]
		local dc, dr = g.col - ac, g.row - ar
		local d = dc * dc + dr * dr
		if d < best_d then
			best_d = d
			best = g
		end
	end
	return best
end

-- Godot would_match: simple 3-in-a-line check around (col, row) for type t.
local function would_match(board, col, row, t)
	if board:type_at(col - 1, row) == t and board:type_at(col - 2, row) == t then return true end
	if board:type_at(col - 1, row) == t and board:type_at(col + 1, row) == t then return true end
	if board:type_at(col + 1, row) == t and board:type_at(col + 2, row) == t then return true end
	if board:type_at(col, row - 1) == t and board:type_at(col, row - 2) == t then return true end
	if board:type_at(col, row - 1) == t and board:type_at(col, row + 1) == t then return true end
	if board:type_at(col, row + 1) == t and board:type_at(col, row + 2) == t then return true end
	return false
end
Match.would_match = would_match

-- Would swapping the gems at the two cells create a line (types swapped
-- temporarily, like Godot). W0-G2a fix: a swap involving a junk or an unsettled gem is
-- never a move (junk can't match, a moving gem can't be swapped), so find_possible_move
-- no longer counts junk "moves" (Godot issue #49: a board whose only "moves" were junk
-- swaps never reshuffled). Neighbours already exclude junk via type_at. Spawn protection is
-- deliberately not checked: it is released on board_settled.
function Match.would_swap_match(board, c1, r1, c2, r2)
	local g1, g2 = board:get(c1, r1), board:get(c2, r2)
	-- Empty cell: no swap (Godot would error on null; it only probes full boards).
	if g1 == nil or g2 == nil then return false end
	if g1.junk or g2.junk or g1.state ~= SETTLED or g2.state ~= SETTLED then return false end
	local t1, t2 = g1.type, g2.type
	g1.type, g2.type = t2, t1
	local has = would_match(board, c1, r1, t2) or would_match(board, c2, r2, t1)
	g1.type, g2.type = t1, t2
	return has
end

-- First (col, row) whose right or down swap matches, scanning column by
-- column; nil if none (Godot returns Vector2i or null). Needs a full grid.
function Match.find_possible_move(board)
	local cols, rows = board.cols, board.rows
	for col = 0, cols - 1 do
		for row = 0, rows - 1 do
			if col + 1 < cols and Match.would_swap_match(board, col, row, col + 1, row) then
				return col, row, col + 1, row
			end
			if row + 1 < rows and Match.would_swap_match(board, col, row, col, row + 1) then
				return col, row, col, row + 1
			end
		end
	end
	return nil
end

ns.Match = Match
