-- core/rng.lua: determinism, stream independence, distribution, shuffle, state.
local H = dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or ".") .. "/helpers.lua")
local T, Rng = H.T, H.ns.Rng
T.start("rng_test")

T.case("same seed -> same sequence", function()
	local a, b = Rng.new(12345), Rng.new(12345)
	local same = true
	for _ = 1, 1000 do
		if a:next() ~= b:next() then same = false end
	end
	T.ok(same, "sequences differ for the same seed")
end)

T.case("known values are stable across runtimes", function()
	-- Pinned output: catches any accidental change of the generator / seeding
	-- and any lua5.1 vs luajit arithmetic difference.
	local r = Rng.new(42)
	local got = {}
	for i = 1, 5 do got[i] = r:next() end
	local s = table.concat(got, ",")
	local r2 = Rng.fork(7, Rng.SALT.refill)
	local got2 = {}
	for i = 1, 5 do got2[i] = r2:range_i(0, 5) end
	-- Values recorded on first implementation (lua5.1); both runtimes must agree.
	T.eq(s, "2191960420,4138895218,1276480789,2417061661,3304051663", "pinned next() values")
	T.eq(table.concat(got2, ","), "1,5,3,0,3", "pinned fork(7, refill) range_i(0, 5)")
end)

T.case("integer outputs in range", function()
	local r = Rng.new(1)
	local ok = true
	for _ = 1, 20000 do
		local v = r:next()
		if v < 0 or v >= 4294967087 or v ~= math.floor(v) then ok = false end
	end
	T.ok(ok, "next() out of [0, M1) or not an integer")
	local lo_hit, hi_hit, bad = false, false, false
	for _ = 1, 20000 do
		local v = r:range_i(-3, 4)
		if v == -3 then lo_hit = true end
		if v == 4 then hi_hit = true end
		if v < -3 or v > 4 or v ~= math.floor(v) then bad = true end
	end
	T.ok(lo_hit and hi_hit and not bad, "range_i(-3, 4) bounds")
	T.eq(r:range_i(5, 5), 5, "range_i(a, a)")
	T.eq(r:range_i(5, 2), 5, "range_i(hi < lo) returns lo")
end)

T.case("different salts / seeds are independent", function()
	local a = Rng.fork(1000, Rng.SALT.refill)
	local b = Rng.fork(1000, Rng.SALT.effects)
	local c = Rng.new(1001)
	local same_ab, same_ac = 0, 0
	for _ = 1, 1000 do
		local x, y, z = a:range_i(0, 5), b:range_i(0, 5), c:range_i(0, 5)
		if x == y then same_ab = same_ab + 1 end
		if x == z then same_ac = same_ac + 1 end
	end
	-- Independent uniform 6-way draws agree ~1/6 of the time (~167 of 1000).
	T.ok(same_ab > 110 and same_ab < 230, "refill vs effects agreement " .. same_ab)
	T.ok(same_ac > 110 and same_ac < 230, "seed vs seed+1 agreement " .. same_ac)
end)

T.case("distribution sanity (chi-square, 6 bins)", function()
	for _, seed in ipairs({ 1, 2, 99, 123456789, 0x5EED0001 }) do
		local r = Rng.new(seed)
		local bins = { 0, 0, 0, 0, 0, 0 }
		local n = 60000
		for _ = 1, n do
			local v = r:range_i(0, 5)
			bins[v + 1] = bins[v + 1] + 1
		end
		local e, chi = n / 6, 0
		for i = 1, 6 do chi = chi + (bins[i] - e) ^ 2 / e end
		-- 5 dof: p = 0.001 at 20.5
		T.ok(chi < 20.5, ("seed %d chi2 = %.2f"):format(seed, chi))
	end
	local r = Rng.new(5)
	local sum, n = 0, 50000
	for _ = 1, n do sum = sum + r:float() end
	T.ok(math.abs(sum / n - 0.5) < 0.01, "float mean " .. sum / n)
end)

T.case("shuffle is a deterministic permutation", function()
	local function arr() local t = {} for i = 1, 20 do t[i] = i end return t end
	local a = Rng.new(9):shuffle(arr())
	local b = Rng.shuffle_with(arr(), Rng.new(9))
	local seen, same, moved = {}, true, false
	for i = 1, 20 do
		seen[a[i]] = true
		if a[i] ~= b[i] then same = false end
		if a[i] ~= i then moved = true end
	end
	local all = true
	for i = 1, 20 do if not seen[i] then all = false end end
	T.ok(all, "shuffle lost an element")
	T.ok(same, "shuffle not deterministic")
	T.ok(moved, "shuffle left the array unchanged")
	-- Godot RngUtil.shuffle draws randi_range(0, i) for i = n-1 .. 1: replay a tape.
	local tape = H.tape({ 0, 0 }) -- n = 3: i = 2 -> j = 0, i = 1 -> j = 0
	local t = Rng.shuffle_with({ "a", "b", "c" }, tape)
	T.eq(table.concat(t), "bca", "tape shuffle order")
	T.eq(tape.draws, 2, "tape draws")
end)

T.case("state round trip", function()
	local a = Rng.new(77)
	for _ = 1, 10 do a:next() end
	local b = Rng.from_state(a:get_state())
	local same = true
	for _ = 1, 100 do if a:next() ~= b:next() then same = false end end
	T.ok(same, "restored stream diverges")
end)

T.done()
