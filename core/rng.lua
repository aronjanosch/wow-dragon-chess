local _, ns = ...
-- Seeded PRNG, arithmetic only (no `bit` library, no math.random): MRG32k3a
-- (L'Ecuyer 1999). Every intermediate product stays below 2^53, so plain
-- doubles compute it exactly and identically in Lua 5.1, LuaJIT and WoW.
--
-- Streams: Rng.fork(seed, Rng.SALT.refill) etc. - one stream per system, so one
-- system's extra rolls never shift another's (same salts as RunManager).
--
-- Injectable: board/sim code only calls `stream:range_i(lo, hi)` and
-- `Rng.shuffle_with(array, stream)`, so a tape stub (replaying Godot's draws) only
-- needs a `range_i` method (plus optional `get_state` for snapshots).

local floor = math.floor
local setmetatable = setmetatable
local tonumber = tonumber

local Rng = {}
Rng.__index = Rng

local M1 = 4294967087
local M2 = 4294944443
local A12, A13N = 1403580, 810728
local A21, A23N = 527612, 1370589
local TWO32 = 4294967296

-- Same salts as autoload/run_manager.gd (seed + salt per stream).
Rng.SALT = { refill = 0x5EED0001, effects = 0x5EED0002, combat = 0x5EED0003, draft = 0x5EED0004 }

-- Exact a mod m for integer-valued doubles |a| < 2^53 (a / m may round, so
-- correct the quotient by one step).
local function imod(a, m)
	local r = a - floor(a / m) * m
	if r < 0 then
		r = r + m
	elseif r >= m then
		r = r - m
	end
	return r
end
Rng.imod = imod

function Rng.new(seed)
	local self = setmetatable({}, Rng)
	local x = imod(floor(tonumber(seed) or 0), TWO32)
	local s = {}
	for i = 1, 6 do
		-- 32-bit LCG (Numerical Recipes) to spread the seed over the state.
		x = imod(x * 1664525 + 1013904223, TWO32)
		s[i] = imod(x, i <= 3 and M1 or M2)
	end
	if s[1] == 0 and s[2] == 0 and s[3] == 0 then s[1] = 12345 end
	if s[4] == 0 and s[5] == 0 and s[6] == 0 then s[4] = 12345 end
	self.s0, self.s1, self.s2, self.s3, self.s4, self.s5 = s[1], s[2], s[3], s[4], s[5], s[6]
	for _ = 1, 8 do self:next() end -- warm-up: decorrelate nearby seeds
	return self
end

-- Stream `salt` of a run seeded with `seed` (RunManager: run_seed + SALT_*).
function Rng.fork(seed, salt)
	return Rng.new((tonumber(seed) or 0) + (salt or 0))
end

-- Next raw draw: integer in [0, M1 - 1] (~32 bits).
function Rng:next()
	local p1 = imod(A12 * self.s1 - A13N * self.s0, M1)
	self.s0, self.s1, self.s2 = self.s1, self.s2, p1
	local p2 = imod(A21 * self.s5 - A23N * self.s3, M2)
	self.s3, self.s4, self.s5 = self.s4, self.s5, p2
	local z = p1 - p2
	if z <= 0 then z = z + M1 end
	return z - 1
end

-- Uniform integer in [lo, hi] (inclusive), unbiased (rejection sampling).
-- hi <= lo returns lo without a draw (like RngUtil.range_i).
function Rng:range_i(lo, hi)
	if hi <= lo then return lo end
	local n = hi - lo + 1
	local limit = M1 - imod(M1, n)
	local v = self:next()
	while v >= limit do v = self:next() end
	return lo + imod(v, n)
end

-- Float in [0, 1).
function Rng:float()
	return self:next() / M1
end

-- In-place Fisher-Yates driven by `stream` (port of RngUtil.shuffle: i from
-- n-1 down to 1, j = randi_range(0, i), 0-based - the same draws as Godot, so a
-- tape recorded there replays here).
function Rng.shuffle_with(array, stream)
	for i = #array - 1, 1, -1 do
		local j = stream:range_i(0, i)
		if j ~= i then
			array[i + 1], array[j + 1] = array[j + 1], array[i + 1]
		end
	end
	return array
end

function Rng:shuffle(array)
	return Rng.shuffle_with(array, self)
end

-- Snapshot (plain array, SavedVariables-safe) and restore.
function Rng:get_state()
	return { self.s0, self.s1, self.s2, self.s3, self.s4, self.s5 }
end

function Rng.from_state(state)
	local self = setmetatable({}, Rng)
	self.s0, self.s1, self.s2, self.s3, self.s4, self.s5 =
		state[1], state[2], state[3], state[4], state[5], state[6]
	return self
end

ns.Rng = Rng
