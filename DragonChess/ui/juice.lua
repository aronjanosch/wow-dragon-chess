local addonName, ns = ...
-- Juice (W0-P6): the pooled "snappy" layer of the fight screen. Purely cosmetic; no game rule, no sim access,
-- no core RNG. Model: Godot scenes/vfx/impact_fx.gd (shards / sparkle / rings), scenes/ui/fight_fx.gd
-- _spawn_projectile (streaks) and autoload/juice.gd (trauma shake), rebuilt from textures only:
--
--   particles   PARTS pooled colour squares (ADD): gem-break shards, 5+ match sparkles, impact sparks. A burst can
--               start in the future (delay), so a match's shards fire when its gems arrive (Timings.FUSE).
--   rings       RINGS pooled expanding rings (the SLOT_RING atlas, else a round disc): ability gem spawn, impacts.
--   streaks     SHOTS pooled projectiles: a head disc + TRAIL dots along the path; they fly FLY sim seconds from a
--               board / enemy / player point to another and then call on_hit(kind, a, b) (the damage number and
--               the enemy hit reaction wait for it) and burst on arrival.
--   shake       Godot's trauma model: Juice:add_trauma(x) (0..1), decays SHAKE_DECAY / s, offset = SHAKE_MAX *
--               trauma^2 px, applied to the window frame; the rest position is captured when a shake starts and
--               restored exactly when it ends (also on halt / hide / pause / drag / option off).
--
-- W0-P7: particles / rings / streak heads use the soft effect textures of Assets.GLOW (glow, flare, ring, smoke) when they
-- load and fall back to colour squares / round discs otherwise; Juice:signature (per-colour ability look), the chain
-- escalation numbers (Juice.chain_scale), landing dust and the rejected-swap puff live here too.
--
-- Everything is created once in Juice.new (a fixed number of textures / masks); update() and the spawn calls
-- allocate nothing, only call setters on active slots and return at once when idle. All time is SIM time
-- (update(now) from the HUD's per-frame update), so a paused game ends nothing early; halt() hides everything and
-- restores the window (the same trigger as FightView:halt: pause, hide, menu, game over, reset).
--
-- Coordinates: px relative to the board's top-left (x right, y down). Cell (c, r) -> ((c + 0.5) * CELL, (r + 0.5) * CELL).
-- Not verified live: Frame:GetPoint(1) / SetPoint round trip for the shake (the same calls ui/window.lua already
-- makes), Texture:SetBlendMode("ADD") on colour textures (already used by the swap hint rings).

local floor, sin, cos, sqrt, pi, min, max = math.floor, math.sin, math.cos, math.sqrt, math.pi, math.min, math.max
local pcall, type, tonumber = pcall, type, tonumber

local Juice = {}
Juice.__index = Juice

-- Pool sizes (fixed at build; a full pool recycles the entry that ends first).
Juice.PARTS, Juice.SHOTS, Juice.TRAIL, Juice.RINGS = 72, 12, 5, 8
Juice.VOLLEY_MAX = 16 -- queued gem streaks (Juice:volley)

-- Tuning (px / sim seconds). All the numbers worth changing while playtesting are here.
Juice.FLY = 0.20 -- streak flight time at weight 1 (Godot PROJECTILE_FLY 0.24)
Juice.FLY_HEAVY = 1.4 -- multiplier at weight >= 2 (an ult is slower and chunkier)
Juice.FADE = 0.10 -- trail fade after the arrival (Godot PROJECTILE_FADE)
Juice.HEAD = 14 -- streak head diameter at weight 1 (scales with the weight)
Juice.TRAIL_STEP = 0.05 -- path fraction between two trail dots
Juice.SHARD_SPEED = 170 -- px / s of a break shard (x 0.5 .. 1.5)
Juice.SHARD_GRAVITY = 420 -- px / s^2 pulling shards down
Juice.SHAKE_MAX = 12 -- window offset in px at trauma 1 (Godot MAX_SHAKE_OFFSET 16)
Juice.SHAKE_DECAY = 2.4 -- trauma per second (Godot TRAUMA_DECAY)
Juice.BURST_N = { 6, 10, 14, 18 } -- shards of a 3- / 4- / 5- / 6+-match break
Juice.SPARKLES = 6 -- extra sparkles from a 5+ match
Juice.SOFT_SCALE = 2.0 -- a soft glow texture is this much bigger than the square it replaces (its edge fades out)
Juice.SOFT_HEAD = 1.8 -- same for streak heads / trail dots
Juice.DUST_GAP = 0.1 -- s between two landing dust puffs of one column
Juice.DUST_ALPHA = 0.5
Juice.CHAIN_MAX = 6 -- chain depth at which the escalation stops growing

-- Per-colour ability signature (Juice:signature), key = gem type: n particles, kind = texture role (glow / flare /
-- smoke), spread = spawn radius px, radial = outward px/s (negative = inward), vy = vertical px/s (negative = up),
-- jx = random sideways px/s, g = gravity px/s^2, oy = vertical spawn offset px, s0 -> s1 px, dur s, ring = { size
-- (cells), dur, alpha } or nil. The colour is A.COLOR.GEM_FX[type].
Juice.SIGNATURE = {
	[3] = { n = 9, kind = "glow", spread = 24, radial = 12, vy = -105, jx = 30, g = 70, oy = 6, s0 = 10, s1 = 2, dur = 0.55, ring = { 1.6, 0.25, 0.6 } }, -- Ruby: rising embers
	[4] = { n = 8, kind = "flare", spread = 28, radial = 0, vy = 70, jx = 20, g = 320, oy = -34, s0 = 11, s1 = 3, dur = 0.5, ring = { 2.0, 0.3, 0.8 } }, -- Sapphire: falling ice shards
	[5] = { n = 12, kind = "flare", spread = 8, radial = 270, vy = 0, jx = 0, g = 0, oy = 0, s0 = 9, s1 = 1, dur = 0.2, ring = nil }, -- Topaz: fast sparks
	[1] = { n = 8, kind = "glow", spread = 38, radial = -28, vy = -16, jx = 8, g = 0, oy = 0, s0 = 12, s1 = 3, dur = 0.75, ring = nil }, -- Amethyst: slow wisps drifting inward
	[2] = { n = 9, kind = "glow", spread = 30, radial = 6, vy = -28, jx = 38, g = -12, oy = 4, s0 = 7, s1 = 4, dur = 0.85, ring = nil }, -- Emerald: drifting leaves / motes
	[0] = { n = 8, kind = "glow", spread = 22, radial = 8, vy = -42, jx = 14, g = 0, oy = 2, s0 = 9, s1 = 3, dur = 0.7, ring = { 1.7, 0.3, 0.8 } }, -- Amber: gold motes
}

-- Hit kinds passed to on_hit.
Juice.HIT_NONE, Juice.HIT_ENEMY = 0, 1

local A -- ns.Assets (resolved in new)
local CELL = 64

-- Park-Miller LCG (view-only randomness, deterministic for tests); state stays below 2^31 so the product is exact.
local function rand(self)
	local s = (self.seed * 16807) % 2147483647
	self.seed = s
	return s / 2147483647
end

local function q20(a)
	if a <= 0 then return 0 end
	if a >= 1 then return 1 end
	return floor(a * 20 + 0.5) / 20
end

---------------------------------------------------------------- construction

local function round_tex(jf, layer, sub, tex)
	tex = tex or jf:CreateTexture(nil, layer, nil, sub)
	local mask = jf:CreateMaskTexture()
	mask:SetTexture(A.ROUND_MASK, A.MASK_WRAP, A.MASK_WRAP)
	mask:SetAllPoints(tex)
	tex:AddMaskTexture(mask)
	tex:SetColorTexture(1, 1, 1, 1)
	tex:SetBlendMode("ADD")
	tex:Hide()
	return tex
end

-- A soft glow texture (Assets.GLOW.glow) when it loads, else the round-masked disc; second result = soft?
local function glow_or_disc(jf, layer, sub)
	local tex = jf:CreateTexture(nil, layer, nil, sub)
	if A.soft(tex, "glow") then
		tex:SetBlendMode("ADD")
		tex:Hide()
		return tex, true
	end
	return round_tex(jf, layer, sub, tex), false
end

-- win: Window.create's table (host, frame, content, layout numbers). opts.player_x = x of the player HP bar's
-- centre in window-content px.
function Juice.new(win, opts)
	A = ns.Assets
	CELL = ns.BoardView.CELL
	opts = opts or {}
	local self = setmetatable({}, Juice)
	self.host = win.host
	self.frame = win.frame
	self.seed = 20261005
	self.now, self.last_now = 0, nil
	self.active_n = 0
	self.on_hit = nil -- fn(kind, a, b): the HUD's reaction when a streak arrives
	self.shake_enabled = true
	self.dragging = false
	self.trauma = 0
	self.shaking = false
	self.rest = { point = nil, rel = nil, rpoint = nil, x = 0, y = 0 }
	self.tint = { 1, 1, 1 } -- scratch colour for impact()

	-- Targets in board-local px (the board's top-left is the origin).
	local pad, gap = win.pad or 6, win.gap or 4
	local bw, bh = win.host:GetWidth(), win.host:GetHeight()
	if bw == nil or bw <= 0 then bw, bh = 8 * CELL, 8 * CELL end
	self.board_w, self.board_h = bw, bh
	self.ex = (win.board_panel_w or bw + 2 * pad) - pad + gap + (win.enemy_panel_w or 470) / 2
	self.ey = (win.panel_h or bh + 2 * pad) / 2 - pad
	self.px = (opts.player_x or 336) - pad
	self.py = (win.panel_h or bh + 2 * pad) + gap + (win.bottom_h or 30) / 2 - pad
	self.jx, self.jy = bw, bh / 2 -- junk lands on the board's right edge

	local jf = CreateFrame("Frame", nil, win.frame)
	jf:SetAllPoints(win.content)
	jf:SetFrameLevel(win.host:GetFrameLevel() + 19)
	self.jf = jf

	self.dust_t = {} -- column + 1 -> sim time of the last landing dust puff (W0-P7)
	self.parts = {}
	for i = 1, Juice.PARTS do
		local tex = jf:CreateTexture(nil, "OVERLAY", nil, 1)
		tex:SetColorTexture(1, 1, 1, 1)
		tex:SetBlendMode("ADD")
		tex:Hide()
		-- kind = the texture role it shows now (nil = the plain square), soft = a soft texture is set
		self.parts[i] = { tex = tex, t0 = nil, shown = false, x = 0, y = 0, vx = 0, vy = 0, g = 0, s0 = 0, s1 = 0, dur = 1, a0 = 1,
			kind = nil, soft = false }
	end
	self.rings = {}
	self.has_ring = false
	for i = 1, Juice.RINGS do
		local tex = jf:CreateTexture(nil, "OVERLAY", nil, 2)
		local soft = A.soft(tex, "ring")
		if soft then
			self.has_ring = true
			tex:SetBlendMode("ADD")
		else
			local kind = A.apply(tex, A.SLOT_RING)
			if kind == nil or kind == "color" then
				-- no ring atlas: a round disc blast instead
				tex = round_tex(jf, "OVERLAY", 2)
				tex:SetAlpha(0.6)
			else
				self.has_ring = true
				tex:SetBlendMode("ADD")
			end
		end
		tex:Hide()
		self.rings[i] = { tex = tex, t0 = nil, shown = false, x = 0, y = 0, s0 = 0, s1 = 0, dur = 1, a0 = 1 }
	end
	self.shots = {}
	self.vol, self.nvol = {}, 0 -- queued decorative streaks { t, x0, y0, x1, y1, r, g, b }
	for i = 1, Juice.SHOTS do
		local head, soft = glow_or_disc(jf, "OVERLAY", 3)
		local s = { head = head, soft = soft, trail = {}, t0 = nil, arrived = false, head_shown = false, nshown = 0 }
		for k = 1, Juice.TRAIL do s.trail[k] = (glow_or_disc(jf, "OVERLAY", 3)) end
		self.shots[i] = s
	end
	return self
end

-- A stand-in with the same methods for a build that failed (nothing to show).
Juice.NONE = setmetatable({ active_n = 0, trauma = 0, seed = 1, now = 0, tint = { 1, 1, 1 }, parts = {}, rings = {}, shots = {}, vol = {}, nvol = 0, board_w = 512, board_h = 512 }, Juice)

---------------------------------------------------------------- helpers

local function place(self, tex, x, y)
	tex:SetPoint("CENTER", self.host, "TOPLEFT", x, -y)
end

local function pick(pool)
	local best
	for i = 1, #pool do
		local p = pool[i]
		if p.t0 == nil then return p, false end
		if best == nil or p.t0 + p.dur < best.t0 + best.dur then best = p end
	end
	return best, true
end

local function kill(self, p)
	if p.t0 ~= nil then
		p.t0 = nil
		self.active_n = self.active_n - 1
	end
	if p.shown then
		p.shown = false
		p.tex:Hide()
	end
end

-- Cell (col, row) -> board-local px.
function Juice.cell_xy(col, row)
	return (col + 0.5) * CELL, (row + 0.5) * CELL
end

---------------------------------------------------------------- particles

-- Texture role of a particle: the soft glow / flare / smoke when it loads (chain: role -> glow -> colour square).
local function apply_kind(p, kind)
	if p.kind == kind then return end
	p.kind = kind
	local tex = p.tex
	local ok = A.soft(tex, kind) or (kind ~= "glow" and A.soft(tex, "glow"))
	p.soft = ok and true or false
	if not ok then tex:SetColorTexture(1, 1, 1, 1) end
end

-- One particle: starts at x, y (px) after `delay` s, moves with (vx, vy) + gravity g, size s0 -> s1, alpha a0 -> 0.
-- kind = "glow" (default) / "flare" / "smoke": the Assets.GLOW role of its texture.
function Juice:particle(x, y, vx, vy, g, s0, s1, dur, r, gg, b, a0, delay, kind)
	local p, replaced = pick(self.parts)
	if p == nil then return end
	if not replaced then self.active_n = self.active_n + 1 end
	if p.shown then
		p.shown = false
		p.tex:Hide()
	end
	p.t0 = self.now + (delay or 0)
	p.x, p.y, p.vx, p.vy, p.g, p.s0, p.s1, p.dur, p.a0 = x, y, vx, vy, g, s0, s1, dur, a0 or 1
	apply_kind(p, kind or "glow")
	if p.soft then p.tex:SetVertexColor(r, gg, b) else p.tex:SetColorTexture(r, gg, b, 1) end
	return p
end

-- A burst of n shards from (x, y): speed scales the radial velocity, size = start px.
function Juice:burst(x, y, n, speed, r, g, b, delay, size)
	size = size or 6
	for i = 1, n do
		local ang = ((i - 1) / n) * 2 * pi + (rand(self) - 0.5) * 0.9
		local sp = speed * (0.5 + rand(self))
		self:particle(x, y, cos(ang) * sp, sin(ang) * sp - speed * 0.25, Juice.SHARD_GRAVITY,
			size * (0.7 + 0.6 * rand(self)), 1.5, 0.26 + 0.14 * rand(self), r, g, b, 1, delay)
	end
end

-- Slow gold twinkles drifting up (5+ matches; Godot CLEAR_SPARKLE 0.45 s).
function Juice:sparkle(x, y, n, delay)
	local c = A.COLOR.SPARKLE
	for i = 1, n do
		local ang = ((i - 1) / n) * 2 * pi + rand(self)
		local d = 8 + 26 * rand(self)
		self:particle(x + cos(ang) * d, y + sin(ang) * d, (rand(self) - 0.5) * 30, -30 - 40 * rand(self), 0,
			8 + 4 * rand(self), 0, 0.35 + 0.15 * rand(self), c[1], c[2], c[3], 1, (delay or 0) + 0.04 * i, "flare")
	end
end

---------------------------------------------------------------- rings

-- An expanding ring (size s0 -> s1 px, alpha a0 -> 0) in colour c.
function Juice:ring(x, y, s0, s1, dur, c, a0, delay)
	local p, replaced = pick(self.rings)
	if p == nil then return end
	if not replaced then self.active_n = self.active_n + 1 end
	if p.shown then
		p.shown = false
		p.tex:Hide()
	end
	p.t0 = self.now + (delay or 0)
	p.x, p.y, p.s0, p.s1, p.dur, p.a0 = x, y, s0, s1, dur, a0 or 1
	p.tex:SetVertexColor(c[1], c[2], c[3])
	return p
end

---------------------------------------------------------------- composed effects

-- Chain escalation by depth (1..CHAIN_MAX+, e = min(depth, 6) - 1): shard multiplier, ring size multiplier, extra ring
-- from depth 3, extra trauma (+0.04 e), gold vignette peak from depth 4 (0.15 + 0.05 e; 0 below). Pure and monotonic.
function Juice.chain_scale(depth)
	local e = depth or 1
	if e < 1 then e = 1 elseif e > Juice.CHAIN_MAX then e = Juice.CHAIN_MAX end
	e = e - 1
	return 1 + 0.25 * e, 1 + 0.15 * e, e >= 2, 0.04 * e, e >= 3 and (0.15 + 0.05 * e) or 0
end

-- Match break at (x, y) px: shards in the gems' colour at `delay` (the gems arrive then), 5+ adds sparkles.
-- depth (W0-P7 B2) = the chain depth of the match: more shards, a bigger ring, an extra ring from depth 3.
function Juice:match_break(length, x, y, gem_type, delay, depth)
	local c = A.COLOR.GEM_FX[gem_type] or A.COLOR.PROJ_DEFAULT
	local sm, rm, extra = Juice.chain_scale(depth)
	local n = Juice.BURST_N[length >= 6 and 4 or length >= 5 and 3 or length >= 4 and 2 or 1]
	self:burst(x, y, floor(n * sm + 0.5), Juice.SHARD_SPEED, c[1], c[2], c[3], delay, 6)
	if length >= 5 then self:sparkle(x, y, Juice.SPARKLES, delay) end
	if length >= 4 or (depth or 1) >= 2 then self:ring(x, y, CELL * 0.4, CELL * 1.3 * rm, 0.22, c, 0.8, delay) end
	if extra then self:ring(x, y, CELL * 0.3, CELL * 1.9 * rm, 0.3, A.COLOR.SPARKLE, 0.7, (delay or 0) + 0.05) end
end

-- Per-colour ability look at (x, y) px (W0-P7 A2); weight >= 2 (an ult) = more particles.
function Juice:signature(gem_type, x, y, weight, delay)
	local sg = Juice.SIGNATURE[gem_type]
	if sg == nil then return false end
	local c = A.COLOR.GEM_FX[gem_type] or A.COLOR.PROJ_DEFAULT
	local n = floor(sg.n * ((weight or 1) >= 2 and 1.6 or 1) + 0.5)
	for i = 1, n do
		local ang = ((i - 1) / n) * 2 * pi + rand(self) * 0.8
		local ca, sa = cos(ang), sin(ang)
		local d = sg.spread * (0.4 + 0.6 * rand(self))
		local rv = sg.radial * (0.6 + 0.8 * rand(self))
		self:particle(x + ca * d, y + sa * d + sg.oy, ca * rv + (rand(self) - 0.5) * sg.jx * 2,
			sa * rv + sg.vy * (0.7 + 0.6 * rand(self)), sg.g, sg.s0 * (0.7 + 0.6 * rand(self)), sg.s1,
			sg.dur * (0.8 + 0.4 * rand(self)), c[1], c[2], c[3], 1, delay, sg.kind)
	end
	local rg = sg.ring
	if rg ~= nil then self:ring(x, y, CELL * 0.4, CELL * rg[1], rg[2], c, rg[3], delay) end
	return true
end

-- Landing dust at the feet of a gem that landed in (col, row): at most one puff per column per DUST_GAP sim seconds.
function Juice:land_dust(col, row)
	local dt = self.dust_t
	if dt == nil then return false end
	local last, now = dt[col + 1], self.now
	if last ~= nil and now >= last and now - last < Juice.DUST_GAP then return false end
	dt[col + 1] = now
	local x, y = (col + 0.5) * CELL, (row + 1) * CELL - 8
	local c = A.COLOR.FX_DUST
	local a = Juice.DUST_ALPHA
	self:particle(x - 8, y, -42, -6, 0, 12, 28, 0.32, c[1], c[2], c[3], a, 0, "smoke")
	self:particle(x + 8, y, 42, -6, 0, 12, 28, 0.32, c[1], c[2], c[3], a, 0, "smoke")
	self:particle(x, y - 4, 0, -14, 0, 10, 22, 0.28, c[1], c[2], c[3], a * 0.8, 0, "smoke")
	return true
end

-- A rejected swap: small red-white cross puff on the cell.
function Juice:reject_puff(col, row)
	local x, y = Juice.cell_xy(col, row)
	local c = A.COLOR.FX_REJECT
	self:ring(x, y, CELL * 0.3, CELL * 0.9, 0.2, c, 0.8)
	for i = 1, 4 do
		local ang = (i - 0.5) * pi / 2
		local white = i % 2 == 0
		self:particle(x, y, cos(ang) * 120, sin(ang) * 120, 0, 8, 1, 0.22, 1, white and 1 or 0.4, white and 1 or 0.35, 1, 0, "flare")
	end
end

-- An ability gem appeared at a cell: ring + sparks; an ult is bigger, golden, with a second ring and sparkles.
function Juice:spawn_fx(col, row, tier)
	local x, y = Juice.cell_xy(col, row)
	if tier == 2 then
		local c = A.COLOR.RING_ULT
		self:ring(x, y, CELL * 0.5, CELL * 2.6, 0.42, c, 1)
		self:ring(x, y, CELL * 0.3, CELL * 1.8, 0.34, A.COLOR.SPARKLE, 0.9, 0.08)
		self:burst(x, y, 14, 190, c[1], c[2], c[3], 0, 7)
		self:sparkle(x, y, 8, 0.05)
	else
		local c = A.COLOR.RING_SKILL
		self:ring(x, y, CELL * 0.4, CELL * 1.9, 0.30, c, 0.9)
		self:burst(x, y, 8, 140, c[1], c[2], c[3], 0, 5)
	end
end

-- Arrival of a streak / a hit on a spot: ring + sparks scaled by the weight.
function Juice:impact(x, y, weight, r, g, b)
	local c = self.tint
	c[1], c[2], c[3] = r, g, b
	self:ring(x, y, 14 * weight, 70 * weight, 0.2, c, 0.9)
	self:burst(x, y, weight >= 1.5 and 12 or 8, 120 * min(weight, 1.8), r, g, b, 0, 5)
end

---------------------------------------------------------------- streaks

local function arrive(self, s)
	s.arrived = true
	self:impact(s.x1, s.y1, s.w, s.r, s.g, s.b)
	local kind = s.hit
	if kind ~= Juice.HIT_NONE and self.on_hit ~= nil then
		s.hit = Juice.HIT_NONE
		self.on_hit(kind, s.ha, s.hb)
	end
end

local function kill_shot(self, s)
	if s.t0 ~= nil then
		s.t0 = nil
		self.active_n = self.active_n - 1
	end
	if s.head_shown then
		s.head_shown = false
		s.head:Hide()
	end
	local tr = s.trail
	for k = 1, s.nshown do tr[k]:Hide() end
	s.nshown = 0
end

-- A glowing streak from (x0, y0) to (x1, y1) px in colour r, g, b; weight >= 1 makes it thicker (an ult: 2.0, slower).
-- hit = Juice.HIT_ENEMY (or NONE): on_hit(hit, ha, hb) runs on the arrival. A full pool recycles the oldest streak and
-- delivers its hit at once, so a reaction is never lost.
function Juice:projectile(x0, y0, x1, y1, weight, r, g, b, hit, ha, hb)
	local pool = self.shots
	local s
	for i = 1, #pool do
		if pool[i].t0 == nil then
			s = pool[i]
			break
		end
		if s == nil or pool[i].t0 < s.t0 then s = pool[i] end
	end
	if s == nil then return end
	if s.t0 ~= nil then
		if not s.arrived then arrive(self, s) end
		kill_shot(self, s)
	end
	weight = weight or 1
	s.t0 = self.now
	self.active_n = self.active_n + 1
	s.arrived = false
	s.x0, s.y0, s.x1, s.y1, s.w, s.r, s.g, s.b = x0, y0, x1, y1, weight, r, g, b
	s.hit, s.ha, s.hb = hit or Juice.HIT_NONE, ha or 0, hb or 0
	local dx, dy = x1 - x0, y1 - y0
	s.fly = Juice.FLY * (weight >= 2 and Juice.FLY_HEAVY or 1 + (Juice.FLY_HEAVY - 1) * max(0, weight - 1))
	local tr = s.trail
	if s.soft then
		s.head:SetVertexColor(r, g, b)
		for k = 1, #tr do tr[k]:SetVertexColor(r, g, b) end
	else
		s.head:SetColorTexture(r, g, b, 1)
		for k = 1, #tr do tr[k]:SetColorTexture(r, g, b, 1) end
	end
	s.size = Juice.HEAD * weight * (s.soft and Juice.SOFT_HEAD or 1)
	-- the length decides nothing (a fixed flight time keeps a streak snappy at any distance); keep dx, dy for reading
	s.len = sqrt(dx * dx + dy * dy)
	return s
end

local function update_shot(self, s, now)
	local t = now - s.t0
	if t < -1 then
		kill_shot(self, s)
		return
	end
	if t < 0 then t = 0 end
	local fly = s.fly
	local u = t / fly
	if not s.arrived and u >= 1 then arrive(self, s) end
	if t >= fly + Juice.FADE then
		kill_shot(self, s)
		return
	end
	local x0, y0, dx, dy = s.x0, s.y0, s.x1 - s.x0, s.y1 - s.y0
	local fade = 1
	if t > fly then fade = 1 - (t - fly) / Juice.FADE end
	local head = s.head
	if u < 1 then
		place(self, head, x0 + dx * u, y0 + dy * u)
		head:SetSize(s.size, s.size)
		head:SetAlpha(1)
		if not s.head_shown then
			s.head_shown = true
			head:Show()
		end
	elseif s.head_shown then
		s.head_shown = false
		head:Hide()
	end
	local tr = s.trail
	local n = #tr
	local shown = 0
	for k = 1, n do
		local pk = u - k * Juice.TRAIL_STEP
		if pk > 0 then
			if pk > 1 then pk = 1 end
			local d = tr[k]
			local sz = s.size * (1 - 0.14 * k)
			place(self, d, x0 + dx * pk, y0 + dy * pk)
			d:SetSize(sz, sz)
			d:SetAlpha(q20((1 - k / (n + 1)) * fade))
			d:Show()
			shown = k
		else
			tr[k]:Hide()
		end
	end
	for k = shown + 1, s.nshown do tr[k]:Hide() end
	s.nshown = shown
end

---------------------------------------------------------------- shake

-- trauma 0..1 (stacks, clamped). Ignored while the option is off or the window is being dragged.
function Juice:add_trauma(amount)
	if not self.shake_enabled or self.dragging or amount <= 0 then return end
	local t = self.trauma + amount
	self.trauma = t > 1 and 1 or t
end

local function restore_window(self)
	if self.shaking then
		self.shaking = false
		local r = self.rest
		if r.point ~= nil then self.frame:SetPoint(r.point, r.rel, r.rpoint, r.x, r.y) end
	end
end

-- The option "Screen shake": off = no trauma, no window offset (a running shake ends at once).
function Juice:set_shake(on)
	self.shake_enabled = on and true or false
	if not self.shake_enabled then
		self.trauma = 0
		restore_window(self)
	end
end

-- The title strip's drag starts / ends: the window is put back before it moves and does not shake while dragged.
function Juice:set_dragging(on)
	self.dragging = on and true or false
	if self.dragging then
		self.trauma = 0
		restore_window(self)
	end
end

local function update_shake(self, dt)
	local trauma = self.trauma
	if trauma > 0 then
		trauma = trauma - Juice.SHAKE_DECAY * dt
		if trauma < 0 then trauma = 0 end
		self.trauma = trauma
	end
	if trauma > 0 then
		local r = self.rest
		if not self.shaking then
			local point, rel, rpoint, x, y = self.frame:GetPoint(1)
			if point == nil then
				self.trauma = 0
				return
			end
			r.point, r.rel, r.rpoint, r.x, r.y = point, rel, rpoint, x or 0, y or 0
			self.shaking = true
		end
		local amount = trauma * trauma * Juice.SHAKE_MAX
		local ox = floor((rand(self) * 2 - 1) * amount + 0.5)
		local oy = floor((rand(self) * 2 - 1) * amount + 0.5)
		self.frame:SetPoint(r.point, r.rel, r.rpoint, r.x + ox, r.y + oy)
	else
		restore_window(self)
	end
end

---------------------------------------------------------------- per frame

local function update_part(self, p, now)
	local t = now - p.t0
	if t < 0 then
		if t < -5 then kill(self, p) end -- time went backwards (a new sim): drop it
		return
	end
	local dur = p.dur
	if t >= dur then
		kill(self, p)
		return
	end
	local k = t / dur
	local tex = p.tex
	place(self, tex, p.x + p.vx * t, p.y + p.vy * t + 0.5 * p.g * t * t)
	local sz = p.s0 + (p.s1 - p.s0) * k
	if p.soft then sz = sz * Juice.SOFT_SCALE end
	tex:SetSize(sz, sz)
	tex:SetAlpha(q20(p.a0 * (1 - k)))
	if not p.shown then
		p.shown = true
		tex:Show()
	end
end

local function update_ring(self, p, now)
	local t = now - p.t0
	if t < 0 then
		if t < -5 then kill(self, p) end
		return
	end
	if t >= p.dur then
		kill(self, p)
		return
	end
	local k = t / p.dur
	local e = 1 - (1 - k) * (1 - k) -- ease out
	local tex = p.tex
	place(self, tex, p.x, p.y)
	local sz = p.s0 + (p.s1 - p.s0) * e
	tex:SetSize(sz, sz)
	tex:SetAlpha(q20(p.a0 * (1 - k)))
	if not p.shown then
		p.shown = true
		tex:Show()
	end
end

-- now = sim time. Returns at once when nothing runs.
function Juice:update(now)
	local last = self.last_now
	self.now = now
	self.last_now = now
	local dt = 0
	if last ~= nil then
		dt = now - last
		if dt < 0 then dt = 0 elseif dt > 0.1 then dt = 0.1 end
	end
	if self.trauma > 0 or self.shaking then update_shake(self, dt) end
	if self.nvol > 0 then
		local vol, n, w = self.vol, self.nvol, 0
		for i = 1, n do
			local v = vol[i]
			if now >= v[1] then
				self:projectile(v[2], v[3], v[4], v[5], 0.55, v[6], v[7], v[8], Juice.HIT_NONE)
			else
				w = w + 1
				vol[w] = v
			end
		end
		for i = w + 1, n do vol[i] = nil end
		self.nvol = w
	end
	if self.active_n <= 0 then return end
	local parts, rings, shots = self.parts, self.rings, self.shots
	for i = 1, #parts do
		local p = parts[i]
		if p.t0 ~= nil then update_part(self, p, now) end
	end
	for i = 1, #rings do
		local p = rings[i]
		if p.t0 ~= nil then update_ring(self, p, now) end
	end
	for i = 1, #shots do
		local s = shots[i]
		if s.t0 ~= nil then update_shot(self, s, now) end
	end
end

-- Hides everything (pause / hide / menu / game over / reset) and puts the window back; pending hit reactions are dropped.
-- A small streak from a destroyed gem at (x0, y0) px to (x1, y1) px, starting at sim time `at` (the gems break
-- after the fuse; Dota Dragon Chess sends one light streak per gem at the enemy).
function Juice:volley(at, x0, y0, x1, y1, r, g, b)
	local n = self.nvol
	if n >= Juice.VOLLEY_MAX then return end
	n = n + 1
	self.nvol = n
	self.vol[n] = { at, x0, y0, x1, y1, r, g, b }
end

function Juice:halt()
	for i = 1, self.nvol do self.vol[i] = nil end
	self.nvol = 0
	local parts, rings, shots = self.parts, self.rings, self.shots
	for i = 1, #parts do kill(self, parts[i]) end
	for i = 1, #rings do kill(self, rings[i]) end
	for i = 1, #shots do kill_shot(self, shots[i]) end
	self.active_n = 0
	self.trauma = 0
	self.last_now = nil
	local dt = self.dust_t
	if dt ~= nil then
		for i = 1, 8 do dt[i] = nil end
	end
	restore_window(self)
end

-- Busy slots across the pools (tests / dev).
function Juice:busy()
	return self.active_n
end

---------------------------------------------------------------- dev

-- Debug panel / tuning: play one effect now. kinds: break, break5, spawn, ult, shot, shot_ult, shake, shake_big.
Juice.DEV_KINDS = { "break", "break5", "spawn", "ult", "shot", "shot_ult", "shake", "shake_big", "dust", "reject",
	"sig0", "sig1", "sig2", "sig3", "sig4", "sig5" }
function Juice:dev(kind)
	local cx, cy = self.board_w / 2, self.board_h / 2
	local c = A.COLOR.GEM_FX[3]
	if kind == "break" or kind == "break5" then
		self:match_break(kind == "break5" and 5 or 3, cx, cy, 3, 0)
	elseif kind == "spawn" then
		self:spawn_fx(3, 3, 1)
	elseif kind == "ult" then
		self:spawn_fx(3, 3, 2)
	elseif kind == "shot" then
		self:projectile(cx, cy, self.ex, self.ey, 1, c[1], c[2], c[3], Juice.HIT_NONE)
	elseif kind == "shot_ult" then
		local g = A.COLOR.GEM_FX[5]
		self:projectile(cx, cy, self.ex, self.ey, 2, g[1], g[2], g[3], Juice.HIT_NONE)
	elseif kind == "dust" then
		self.dust_t = self.dust_t or {}
		for col = 0, 7 do
			self.dust_t[col + 1] = nil
			self:land_dust(col, 6)
		end
	elseif kind == "reject" then
		self:reject_puff(3, 3)
		self:reject_puff(4, 3)
	elseif kind:sub(1, 3) == "sig" and tonumber(kind:sub(4)) ~= nil then
		self:signature(tonumber(kind:sub(4)), cx, cy, 1, 0)
	elseif kind == "shake" or kind == "shake_big" then
		if not self.shake_enabled then return false end
		self:add_trauma(kind == "shake" and 0.45 or 0.9)
	else
		return false
	end
	return true
end

ns.Juice = Juice
