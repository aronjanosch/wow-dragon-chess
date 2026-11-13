-- core/match.lua: region matching (hand-written boards + golden boards exported
-- from Godot's find_all_matches), tiers, multipliers, swap validity, move search.
local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "."
local H = dofile(dir .. "/helpers.lua")
local T, ns = H.T, H.ns
local Match, Board = ns.Match, ns.Board
T.start("match_test")

-- "c,r c,r ..." of a region's gems in order.
local function cells_of(gems)
	local out = {}
	for i = 1, #gems do out[i] = gems[i].col .. "," .. gems[i].row end
	return table.concat(out, " ")
end

local function lens(regions)
	local out = {}
	for i = 1, #regions do out[i] = regions[i].length end
	return table.concat(out, ",")
end

T.case("simple lines and tiers", function()
	local b = H.board({
		"11123450",
		"23451234",
		"34512345",
		"45123451",
		"51234512",
		"02345123",
		"03451234",
		"04512345",
	})
	local r = Match.find_matches(b)
	-- row 0: 111 (3); col 0: 0,0,0 rows 5..7 (3)
	T.eq(lens(r), "3,3", "region sizes")
	T.eq(cells_of(r[1].gems), "0,0 1,0 2,0", "row run order")
	T.eq(cells_of(r[2].gems), "0,5 0,6 0,7", "column run order")
	T.eq(Match.tier_for_length(3), 0, "3 -> plain")
	T.eq(Match.tier_for_length(4), 1, "4 -> skill")
	T.eq(Match.tier_for_length(5), 2, "5 -> ult")
	T.eq(Match.tier_for_length(29), 2, "29 -> ult")
	T.eq(Match.damage_multiplier_for_length(5), 1.0, "x1.0 at 5")
	T.eq(Match.damage_multiplier_for_length(6), 1.2, "x1.2 at 6")
	T.eq(Match.damage_multiplier_for_length(7), 1.5, "x1.5 at 7")
	T.eq(Match.damage_multiplier_for_length(12), 1.5, "x1.5 at 12")
end)

T.case("L, T and + are one region", function()
	local L = H.board({
		"1000",
		"1000",
		"1110",
		"0000",
	}, { colors = 2 })
	-- zeros form big regions too; look at colour 1 only
	local found
	for _, reg in ipairs(Match.find_matches(L)) do
		if reg.gems[1].type == 1 then found = reg end
	end
	T.eq(found and found.length, 5, "L size")
	T.eq(found and cells_of(found.gems), "0,2 1,2 2,2 0,0 0,1", "L gem order (H runs first, dedup)")
	T.eq(found and Match.center_gem(found.gems).col .. "," .. Match.center_gem(found.gems).row, "0,1", "L centre (nearest the average, first wins ties)")

	local plus = H.board({
		"20202",
		"21112",
		"02120",
		"20102",
		"02020",
	})
	local reg
	for _, x in ipairs(Match.find_matches(plus)) do
		if x.gems[1].type == 1 then reg = x end
	end
	T.eq(reg and reg.length, 5, "+ size")
	T.eq(reg and Match.tier_for_region(reg.gems, reg.length), 2, "+ spawns ult")
	local c = Match.center_gem(reg.gems)
	T.eq(c.col .. "," .. c.row, "2,2", "+ centre is the cross")
end)

T.case("parallel rows merge into one region", function()
	local b = H.board({
		"023450",
		"111012",
		"111234",
		"234501",
	})
	local reg
	for _, x in ipairs(Match.find_matches(b)) do
		if x.gems[1].type == 1 then reg = x end
	end
	T.eq(reg and reg.length, 6, "two touching 3-runs = one region of 6")
	T.eq(Match.damage_multiplier_for_length(reg.length), 1.2, "6-region multiplier")
end)

T.case("protected gems split regions, junk and unsettled are not matchable", function()
	local b = H.board({ "1111111", "0230230" })
	b:get(3, 0).protected = true
	local r = Match.find_matches(b)
	T.eq(lens(r), "3,3", "protected middle splits a 7 into two 3s")
	b:get(3, 0).protected = false
	T.eq(lens(Match.find_matches(b)), "7", "unprotected: one 7")

	local j = H.board({ "11J11", "02302" })
	T.eq(#Match.find_matches(j), 0, "junk breaks the line")
	local j2 = H.board({ "111J", "0230" })
	T.eq(lens(Match.find_matches(j2)), "3", "junk next to a line is not part of it")

	local f = H.board({ "11111", "02302" })
	f:get(2, 0).state = Board.FALLING
	T.eq(#Match.find_matches(f), 0, "falling gem breaks the line")
end)

T.case("touching gem outside any run is not matched; other colours stay separate", function()
	local b = H.board({
		"11102",
		"20112",
		"22202",
	})
	local r = Match.find_matches(b)
	-- 111 (row 0); 222 (row 2, cols 0-2); col 4: 2,2,2 -> merges with row-2 run?
	-- (2,2) and (4,2) are not adjacent; col-4 run touches (3,2)? no -> separate.
	local types = {}
	for i, reg in ipairs(r) do types[i] = reg.gems[1].type .. ":" .. reg.length end
	T.eq(table.concat(types, " "), "1:3 2:3 2:3", "regions")
	-- (2,1)=1 and (3,1)=1 touch the 111 run but are in no run >= 3
	T.eq(cells_of(r[1].gems), "0,0 1,0 2,0", "outside gems not included")
end)

T.case("convert mark caps a region at a skill", function()
	local b = H.board({ "11111", "02302" })
	local r = Match.find_matches(b)
	T.eq(Match.tier_for_region(r[1].gems, r[1].length), 2, "unmarked 5 -> ult")
	b:get(4, 0).marked = true
	T.eq(Match.tier_for_region(r[1].gems, r[1].length), 1, "marked 5 -> skill")
	local b4 = H.board({ "1111", "0230" })
	b4:get(0, 0).marked = true
	local r4 = Match.find_matches(b4)
	T.eq(Match.tier_for_region(r4[1].gems, r4[1].length), 1, "marked 4 stays skill")
end)

T.case("swap validity and move search", function()
	local b = H.board({
		"0123",
		"1023",
		"0451",
		"2345",
	})
	-- swapping (0,1)<->(1,1) gives column 0 = 0,0,0
	T.ok(Match.would_swap_match(b, 0, 1, 1, 1), "would_swap_match finds the column")
	T.ok(not Match.would_swap_match(b, 2, 3, 3, 3), "no match for an unrelated swap")
	local c, r = Match.find_possible_move(b)
	T.eq(c .. "," .. r, "0,1", "first move in scan order (column-major)")
	T.eq(b:get(0, 1).type, 1, "types restored after the probe")

	-- involves: only regions containing a swapped gem count
	local v = H.board({ "1110", "0201", "2323" })
	local g1, g2 = v:get(3, 0), v:get(3, 1)
	T.ok(not Match.involves(v, g1, g2), "unrelated pending match does not validate a swap")
	T.ok(Match.involves(v, v:get(0, 0), g2), "a gem in a region validates")
end)

-- Godot's move search before the W0-G2a junk fix (state of the gems not checked).
local function legacy_would_swap(board, c1, r1, c2, r2)
	local g1, g2 = board:get(c1, r1), board:get(c2, r2)
	local t1, t2 = g1.type, g2.type
	g1.type, g2.type = t2, t1
	local has = Match.would_match(board, c1, r1, t2) or Match.would_match(board, c2, r2, t1)
	g1.type, g2.type = t1, t2
	return has
end
local function legacy_move(board)
	for col = 0, board.cols - 1 do
		for row = 0, board.rows - 1 do
			if col + 1 < board.cols and legacy_would_swap(board, col, row, col + 1, row) then return col .. "," .. row end
			if row + 1 < board.rows and legacy_would_swap(board, col, row, col, row + 1) then return col .. "," .. row end
		end
	end
end

T.case("swaps with junk or unsettled gems are no moves (W0-G2a, Godot #49)", function()
	-- swapping the junk (0,1) with (1,1) would line up column 0 (0,0,0): not a move any more
	local b = H.board({ "0123", "J023", "0451", "2345" })
	T.ok(not Match.would_swap_match(b, 0, 1, 1, 1), "a swap involving a junk gem is no move")
	T.ok(not Match.would_swap_match(b, 1, 1, 0, 1), "either order")
	-- the same board with a plain gem there is a move
	local p = H.board({ "0123", "1023", "0451", "2345" })
	T.ok(Match.would_swap_match(p, 0, 1, 1, 1), "plain control")
	-- an unsettled gem is no move
	p:get(1, 1).state = Board.FALLING
	T.ok(not Match.would_swap_match(p, 0, 1, 1, 1), "a swap involving an unsettled gem is no move")
	-- junk-only moves: no move at all -> nil (the sim then reshuffles / fires board_shuffled, see sim_test)
	local jb = H.board({ "J0J1", "0J2J", "J1J2", "2J4J" })
	T.ok(Match.find_possible_move(jb) == nil, "no move on a junk-checkerboard")
end)

T.case("golden boards from Godot find_all_matches", function()
	local golden = dofile(dir .. "/golden_boards.lua")
	T.ok(#golden >= 5, "at least 5 golden boards")
	for _, case in ipairs(golden) do
		local b = Board.new({ cols = 8, rows = 8, colors = 6, seed = 1 })
		for i, tok in ipairs(case.cells) do
			local col, row = math.floor((i - 1) / 8), (i - 1) % 8
			local g = b:new_gem(col, row, tonumber(tok:sub(1, 1)))
			g.tier = tonumber(tok:match("t(%d)") or "0")
			g.protected = tok:find("p") ~= nil
			g.junk = tok:find("j") ~= nil
			if tok:find("f") then g.state = Board.FALLING end
			b:set(col, row, g)
		end
		local regions = Match.find_matches(b)
		T.eq(#regions, #case.regions, "seed " .. case.seed .. " region count")
		for k, want in ipairs(case.regions) do
			local got = regions[k]
			if got then
				local label = "seed " .. case.seed .. " region " .. k
				T.eq(got.length, want.len, label .. " length")
				T.eq(cells_of(got.gems), want.gems, label .. " gem order")
				local c = Match.center_gem(got.gems)
				T.eq(c.col .. "," .. c.row, want.center, label .. " centre gem")
				T.eq(Match.tier_for_region(got.gems, got.length), want.tier, label .. " tier")
			end
		end
		local mc, mr, mc2, mr2 = Match.find_possible_move(b)
		local got = mc and (mc .. "," .. mr) or nil
		if got ~= case.move and legacy_move(b) == case.move then
			-- W0-G2a junk fix: Godot's search counted a swap with a junk / unsettled gem; ours must not.
			T.ok(mc == nil or (not b:get(mc, mr).junk and b:get(mc, mr).state == Board.SETTLED
				and not b:get(mc2, mr2).junk and b:get(mc2, mr2).state == Board.SETTLED),
				"seed " .. case.seed .. " Lua move uses settled non-junk gems")
		else
			T.eq(got, case.move, "seed " .. case.seed .. " find_possible_move")
		end
	end
end)

T.case("fresh board: full, no matches, has a move, deterministic", function()
	local a = Board.new({ seed = 4242 }):fill()
	local b = Board.new({ seed = 4242 }):fill()
	T.ok(a:is_fully_settled(), "full and settled")
	T.eq(#Match.find_matches(a), 0, "no initial matches")
	T.ok(Match.find_possible_move(a) ~= nil, "has a move")
	T.eq(a:dump(true), b:dump(true), "same seed -> same board")
	local c = Board.new({ seed = 4243 }):fill()
	T.ok(a:dump() ~= c:dump(), "other seed -> other board")
	local ok, err = a:check_integrity(true)
	T.ok(ok, err)
end)

T.done()
