local addonName, ns = ...
-- BoardFx (W0-P7): the ability effects ON the board, the chain combo meter and the board light. Purely cosmetic; no game
-- rule, no sim writes, no core RNG. It listens to sim events that nothing else listened to:
--
--   flash(kind, cells, dur)       kinds area / color / convert_to / chain (cells pulse), telegraph / telegraph_from /
--                                 telegraph_to (pulse for the full duration, a short flash at the end), row_sweep (a beam runs
--                                 outward along the row, cells flash as it passes), wave (a wedge unfolds to the right, the
--                                 column slices flash CLEAR_STAGGER_STEP * 2 apart, embers rise)
--   chain_hop(c0, r0, c1, r1)     a jagged lightning bolt (a chain of glow dots) + a spark burst at the target
--   board_settled                 starts the combo meter's fade
--
-- plus, called by ui/fight_view.lua: set_cast(gem_type) (the colour of colour-less flashes), combo(depth) (the "x<depth>"
-- meter near the board's top-right), light(gem_type, tier) (an additive wash over the board, a short darkening for an ult).
--
-- Pools, all created once in new() (nothing is created while playing; a full pool recycles the entry that ends first):
--   CELLS  glow slots (one texture each)     BEAMS  row-sweep arms (trail + core)     BOLTS  bolts (BOLT_DOTS dots + 1 underlay)
--   WEDGE  one cone texture                  plus the light frame (wash + dark) and the combo frame.
-- Textures: Assets.GLOW roles glow / beam / bolt / wedge via Assets.soft; every effect works without them (cells: colour
-- squares, beams: colour quads, bolts: dots, wedge: only the column slices). The event's cell list is COPIED into slots;
-- no reference to it is kept (the core may reuse the table).
--
-- Time: sim time only (update(now) from the HUD); halt() hides everything (FightView:halt: pause, hide, menu, game over).
-- Frame levels (host level + n): light 9, glow 10, combo 11 (gems 3, held gem 8; Fx models 20, juice 19, overlay 30).
--
-- Not verified live: the look of the unverified textures (see ui/assets.lua GLOW), Texture:SetBlendMode("ADD") on them.

local floor, sin, cos, sqrt, abs, min, max = math.floor, math.sin, math.cos, math.sqrt, math.abs, math.min, math.max
local pcall, type, tostring, tonumber = pcall, type, tostring, tonumber

local BoardFx = {}
BoardFx.__index = BoardFx

-- Pools.
BoardFx.CELLS, BoardFx.BEAMS, BoardFx.BOLTS, BoardFx.BOLT_DOTS = 64, 4, 8, 10

-- Tuning (px / sim seconds / alpha). Everything worth changing while playtesting is here.
BoardFx.CELL_PEAK = 0.85 -- peak alpha of a cell flash (soft glow); the colour-square fallback is dimmer
BoardFx.CELL_SQUARE_PEAK = 0.5
BoardFx.CELL_SOFT = 1.4 -- soft glow diameter in cells
BoardFx.CELL_SQUARE = 0.9 -- fallback square side in cells
BoardFx.FLASH_DUR = 0.2 -- default pulse length of a cell flash with no duration
BoardFx.PULSE_W = 18 -- rad/s of the telegraph pulse
BoardFx.TELE_END = 0.1 -- s of the closing flash of a telegraph
BoardFx.SWEEP_CELL = 0.14 -- pulse length of a cell hit by the beam
BoardFx.BEAM_FADE = 0.12 -- s the beam lingers after reaching the end
BoardFx.BEAM_TRAIL = 2.5 -- cells of soft trail behind the beam head
BoardFx.BEAM_H, BoardFx.BEAM_CORE_H = 44, 12 -- px (soft textures); the quad fallback uses a third of it
BoardFx.WEDGE_FADE = 0.1
BoardFx.EMBERS = 2 -- embers per wave column
BoardFx.BOLT_JITTER = 13 -- px perpendicular jitter of a bolt
BoardFx.BOLT_STEP = 0.03 -- s between two re-jitters of a live bolt
BoardFx.SPARKS = 6 -- spark burst at the target of a hop
BoardFx.WASH_SKILL, BoardFx.WASH_ULT, BoardFx.WASH_DUR = 0.18, 0.3, 0.25
BoardFx.DARK_ALPHA, BoardFx.DARK_DUR = 0.35, 0.3
BoardFx.COMBO_HOLD, BoardFx.COMBO_FADE = 1.2, 0.3
BoardFx.COMBO_PUNCH, BoardFx.COMBO_PUNCH_SCALE = 0.2, 0.5
BoardFx.COMBO_MAX = 30 -- precreated "x<n>" strings

local MODE_FLASH, MODE_TELE = 1, 2

local A -- ns.Assets (resolved in new)
local CELL = 64

-- Park-Miller LCG (view-only randomness).
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

local COMBO_STR = {}
for d = 0, BoardFx.COMBO_MAX do COMBO_STR[d] = "x" .. d end

-- Pure: combo meter scale by chain depth (2 -> 0.8 ... 8+ -> 1.7), monotonic.
function BoardFx.combo_scale(depth)
	local d = depth or 2
	if d < 2 then d = 2 elseif d > 8 then d = 8 end
	return 0.8 + 0.15 * (d - 2)
end

---------------------------------------------------------------- construction

-- A texture of `role` (soft) or a colour square; second result = soft?
local function role_tex(frame, layer, sub, role)
	local tex = frame:CreateTexture(nil, layer, nil, sub)
	local soft = A.soft(tex, role)
	if soft then
		tex:SetBlendMode("ADD")
	else
		tex:SetColorTexture(1, 1, 1, 1)
		tex:SetBlendMode("ADD")
	end
	tex:Hide()
	return tex, soft
end

-- win: Window.create's table; juice: the Juice instance (embers / sparks; Juice.NONE is fine).
function BoardFx.new(win, juice)
	A = ns.Assets
	CELL = ns.BoardView.CELL
	local self = setmetatable({}, BoardFx)
	local host = win.host
	self.host = host
	self.juice = juice
	self.seed = 20261006
	self.now = 0
	self.sim = nil
	self.active_n = 0
	self.cast_type = nil
	self.board_w, self.board_h = 8 * CELL, 8 * CELL

	local base = host:GetFrameLevel()
	-- Light frame: the ult darkening (BLEND) under the additive wash.
	local lf = CreateFrame("Frame", nil, host)
	lf:SetAllPoints(host)
	lf:SetFrameLevel(base + 9)
	self.dark = lf:CreateTexture(nil, "ARTWORK", nil, 0)
	self.dark:SetAllPoints(host)
	local dk = A.COLOR.FX_DARK
	self.dark:SetColorTexture(dk[1], dk[2], dk[3], 1)
	self.dark:Hide()
	self.wash = lf:CreateTexture(nil, "ARTWORK", nil, 1)
	self.wash:SetAllPoints(host)
	self.wash:SetColorTexture(1, 1, 1, 1)
	self.wash:SetBlendMode("ADD")
	self.wash:Hide()
	self.lf = lf
	self.wash_t0, self.wash_peak, self.dark_t0 = nil, 0, nil
	self.wash_r, self.wash_g, self.wash_b = 1, 1, 1
	self.wash_shown, self.dark_shown, self.lwash, self.ldark = false, false, 0, 0

	-- Glow frame: cells, beams, bolts, wedge.
	local gf = CreateFrame("Frame", nil, host)
	gf:SetAllPoints(host)
	gf:SetFrameLevel(base + 10)
	self.gf = gf
	self.cells = {}
	for i = 1, BoardFx.CELLS do
		local tex, soft = role_tex(gf, "ARTWORK", 1, "glow")
		self.cells[i] = { tex = tex, soft = soft, t0 = nil, dur = 1, mode = MODE_FLASH, peak = 1, shown = false,
			r = 1, g = 1, b = 1, lsz = 0, la = -1, base = soft and CELL * BoardFx.CELL_SOFT or CELL * BoardFx.CELL_SQUARE }
	end
	self.beams = {}
	for i = 1, BoardFx.BEAMS do
		local trail, soft = role_tex(gf, "ARTWORK", 2, "beam")
		local core = role_tex(gf, "ARTWORK", 3, "beam")
		self.beams[i] = { trail = trail, core = core, soft = soft, t0 = nil, life = 1, shown = false, x0 = 0, x1 = 0, y = 0,
			dir = 1, dur = 1, r = 1, g = 1, b = 1, lx = nil, lw = nil, la = -1 }
	end
	self.bolts = {}
	for i = 1, BoardFx.BOLTS do
		local dots = {}
		local soft
		for k = 1, BoardFx.BOLT_DOTS do dots[k], soft = role_tex(gf, "ARTWORK", 4, "glow") end
		local under, usoft = role_tex(gf, "ARTWORK", 3, "bolt")
		self.bolts[i] = { dots = dots, soft = soft, under = under, usoft = usoft, under_on = false, t0 = nil, life = 1, hold = 0,
			shown = false, x0 = 0, y0 = 0, x1 = 0, y1 = 0, nx = 0, ny = 0, len = 0, r = 1, g = 1, b = 1, step = -1, la = -1,
			ox = {}, oy = {} }
		for k = 1, BoardFx.BOLT_DOTS do
			self.bolts[i].ox[k], self.bolts[i].oy[k] = 0, 0
		end
	end
	local wedge, wsoft = role_tex(gf, "ARTWORK", 0, "wedge")
	if not wsoft then wedge = nil end -- no wedge texture: the column slices alone carry the wave
	self.wedge = { tex = wedge, t0 = nil, life = 1, dur = 1, x0 = 0, y0 = 0, w = 0, h = 0, r = 1, g = 1, b = 1, shown = false,
		lw = 0, la = -1 }

	-- Combo meter: a fixed holder near the top-right, a scaled child frame with the text.
	local ch = CreateFrame("Frame", nil, host)
	ch:SetSize(1, 1)
	ch:SetPoint("CENTER", host, "TOPRIGHT", -52, -34)
	ch:SetFrameLevel(base + 11)
	local cf = CreateFrame("Frame", nil, ch)
	cf:SetSize(110, 44)
	cf:SetPoint("CENTER", ch, "CENTER", 0, 0)
	cf:SetFrameLevel(base + 11)
	local fs = cf:CreateFontString(nil, "OVERLAY", A.FONT_CLEARED)
	fs:SetPoint("CENTER", cf, "CENTER", 0, 0)
	local cc = A.COLOR.COMBO_TEXT
	fs:SetTextColor(cc[1], cc[2], cc[3], cc[4])
	cf:Hide()
	self.combo_frame, self.combo_text = cf, fs
	self.cdepth, self.cmatch_t, self.csettle_t, self.cpunch_t = 0, nil, nil, nil
	self.cshown, self.cscale, self.calpha, self.ctext = false, -1, -1, nil

	self._on_flash = function(kind, cells, dur) self:flash(kind, cells, dur) end
	self._on_hop = function(c0, r0, c1, r1) self:chain_hop(c0, r0, c1, r1) end
	self._on_settled = function() self:on_settled() end
	return self
end

-- A stand-in with the same methods for a build that failed (nothing to show).
BoardFx.NONE = setmetatable({ active_n = 0, cells = {}, beams = {}, bolts = {}, now = 0, seed = 1, board_w = 512, board_h = 512, cdepth = 0,
	juice = { particle = function() end, burst = function() end, ring = function() end } }, BoardFx)

---------------------------------------------------------------- binding

function BoardFx:bind(sim)
	self:unbind()
	if sim == nil or self._on_flash == nil then return end
	self.sim = sim
	sim:on("flash", self._on_flash)
	sim:on("chain_hop", self._on_hop)
	sim:on("board_settled", self._on_settled)
end

function BoardFx:unbind()
	local sim = self.sim
	if sim ~= nil then
		sim:off("flash", self._on_flash)
		sim:off("chain_hop", self._on_hop)
		sim:off("board_settled", self._on_settled)
	end
	self.sim = nil
end

local function now_of(self)
	local s = self.sim
	return s ~= nil and s.now or self.now
end

-- The gem type of the ability that is running (colour of colour-less flashes).
function BoardFx:set_cast(gem_type)
	self.cast_type = gem_type
end

local function cast_color(self)
	local C = A.COLOR
	return C.GEM_FX[self.cast_type] or C.PROJ_DEFAULT
end

---------------------------------------------------------------- pools

local function pick(pool)
	local best
	for i = 1, #pool do
		local p = pool[i]
		if p.t0 == nil then return p, false end
		local e = p.t0 + (p.life or p.dur)
		if best == nil or e < best.t0 + (best.life or best.dur) then best = p end
	end
	return best, true
end

local function kill_cell(self, s)
	if s.t0 ~= nil then
		s.t0 = nil
		self.active_n = self.active_n - 1
	end
	if s.shown then
		s.shown = false
		s.tex:Hide()
	end
end

-- One cell glow: centred on (col, row), starts after `delay`, lasts dur, colour c, mode flash / tele.
local function cell_glow(self, col, row, dur, c, mode, delay, peak)
	local s, replaced = pick(self.cells)
	if s == nil then return end
	if not replaced then self.active_n = self.active_n + 1 elseif s.shown then
		s.shown = false
		s.tex:Hide()
	end
	s.t0 = now_of(self) + (delay or 0)
	s.dur, s.mode = dur, mode
	s.peak = peak or (s.soft and BoardFx.CELL_PEAK or BoardFx.CELL_SQUARE_PEAK)
	s.la, s.lsz = -1, 0
	local tex = s.tex
	if s.soft then tex:SetVertexColor(c[1], c[2], c[3]) else tex:SetColorTexture(c[1], c[2], c[3], 1) end
	tex:ClearAllPoints()
	tex:SetPoint("CENTER", self.host, "TOPLEFT", (col + 0.5) * CELL, -(row + 0.5) * CELL)
	return s
end

---------------------------------------------------------------- events

local function colour_for(self, kind)
	local C = A.COLOR
	if kind == "chain" then return C.FX_CHAIN end
	if kind == "telegraph_from" then return C.FX_TELE_FROM end
	return cast_color(self)
end

-- A core flash event. cells = flat { col, row, ... }; copied into slots, never referenced after this call.
function BoardFx:flash(kind, cells, dur)
	if cells == nil or self.cells == nil then return end
	dur = dur or BoardFx.FLASH_DUR
	local n = #cells
	if n < 2 then return end
	local cap = BoardFx.CELLS * 2
	if n > cap then n = cap end
	local c = colour_for(self, kind)
	if kind == "row_sweep" then
		self:_row_sweep(cells, n, dur, c)
	elseif kind == "wave" then
		self:_wave(cells, n, dur, c)
	elseif kind == "telegraph" or kind == "telegraph_from" or kind == "telegraph_to" then
		for i = 1, n, 2 do cell_glow(self, cells[i], cells[i + 1], dur, c, MODE_TELE, 0) end
	else -- area / color / convert_to / chain
		for i = 1, n, 2 do cell_glow(self, cells[i], cells[i + 1], dur, c, MODE_FLASH, 0) end
	end
end

local function beam_arm(self, x0, x1, y, dir, dur, c)
	local b, replaced = pick(self.beams)
	if b == nil then return end
	if not replaced then self.active_n = self.active_n + 1 elseif b.shown then
		b.shown = false
		b.trail:Hide()
		b.core:Hide()
	end
	b.t0 = now_of(self)
	b.dur, b.life = dur, dur + BoardFx.BEAM_FADE
	b.x0, b.x1, b.y, b.dir = x0, x1, y, dir
	b.r, b.g, b.b = c[1], c[2], c[3]
	b.lx, b.lw, b.la = nil, nil, -1
	local k = b.soft and 1 or 0.5
	if b.soft then
		b.trail:SetVertexColor(c[1], c[2], c[3])
		b.core:SetVertexColor(1, 1, 1)
	else
		b.trail:SetColorTexture(c[1], c[2], c[3], 1)
		b.core:SetColorTexture(1, 1, 1, 1)
	end
	b.k = k
	b.trail:ClearAllPoints()
	b.core:ClearAllPoints()
end

function BoardFx:_row_sweep(cells, n, dur, c)
	local row = cells[2]
	local origin = cells[1]
	local minc, maxc = origin, origin
	for i = 1, n, 2 do
		local col = cells[i]
		if col < minc then minc = col end
		if col > maxc then maxc = col end
	end
	local y = (row + 0.5) * CELL
	local span = max(origin - minc, maxc - origin)
	if span < 1 then span = 1 end
	if maxc > origin then beam_arm(self, (origin + 0.5) * CELL, (maxc + 1) * CELL, y, 1, dur, c) end
	if minc < origin then beam_arm(self, (origin + 0.5) * CELL, minc * CELL, y, -1, dur, c) end
	for i = 1, n, 2 do
		local d = abs(cells[i] - origin)
		cell_glow(self, cells[i], cells[i + 1], BoardFx.SWEEP_CELL, c, MODE_FLASH, dur * d / span)
	end
end

function BoardFx:_wave(cells, n, dur, c)
	local T = ns.Timings
	local step = T.CLEAR_STAGGER_STEP * 2
	local ocol, orow = cells[1], cells[2]
	local minr, maxr, maxc = orow, orow, ocol
	local last_col = -1
	local jc = self.juice
	for i = 1, n, 2 do
		local col, row = cells[i], cells[i + 1]
		if row < minr then minr = row end
		if row > maxr then maxr = row end
		if col > maxc then maxc = col end
		local delay = (col - ocol) * step
		cell_glow(self, col, row, 0.18, c, MODE_FLASH, delay)
		if col ~= last_col then
			last_col = col
			-- embers rise from the slice as it flashes
			for k = 1, BoardFx.EMBERS do
				jc:particle((col + 0.3 + 0.4 * rand(self)) * CELL, (orow + 0.5 + (rand(self) - 0.5) * (maxr - minr + 1)) * CELL,
					(rand(self) - 0.5) * 30, -70 - 50 * rand(self), 60, 8, 1, 0.5, c[1], c[2], c[3], 1, delay, "glow")
			end
		end
	end
	local w = self.wedge
	if w == nil or w.tex == nil then return end
	if w.t0 == nil then self.active_n = self.active_n + 1 elseif w.shown then
		w.shown = false
		w.tex:Hide()
	end
	w.t0 = now_of(self)
	w.dur, w.life = dur, dur + T.WAVE_CONE_FADE + BoardFx.WEDGE_FADE
	w.x0, w.y0 = (ocol + 0.5) * CELL, (orow + 0.5) * CELL
	w.w = (maxc + 1 - ocol - 0.5) * CELL
	-- the cone's rows grow with the distance; the texture spans the whole spread
	local rows = (maxr - minr + 1)
	if rows < 1 then rows = 1 end
	w.h = (rows + 0.5) * CELL
	w.yc = (minr + maxr + 1) * 0.5 * CELL
	w.lw, w.la = 0, -1
	w.tex:SetVertexColor(c[1], c[2], c[3])
	w.tex:ClearAllPoints()
	w.tex:SetPoint("LEFT", self.host, "TOPLEFT", w.x0, -w.yc)
end

-- A chain-lightning hop between two cells (cell units).
function BoardFx:chain_hop(c0, r0, c1, r1)
	local b, replaced = pick(self.bolts)
	if b == nil then return end
	local T = ns.Timings
	if not replaced then self.active_n = self.active_n + 1 elseif b.shown then self:_hide_bolt(b) end
	b.t0 = now_of(self)
	b.hold = T.CHAIN_HOP + T.CHAIN_HOP_HOLD
	b.life = b.hold + T.CHAIN_FADE
	local x0, y0 = (c0 + 0.5) * CELL, (r0 + 0.5) * CELL
	local x1, y1 = (c1 + 0.5) * CELL, (r1 + 0.5) * CELL
	b.x0, b.y0, b.x1, b.y1 = x0, y0, x1, y1
	local dx, dy = x1 - x0, y1 - y0
	local len = sqrt(dx * dx + dy * dy)
	b.len = len
	if len > 0 then b.nx, b.ny = -dy / len, dx / len else b.nx, b.ny = 0, 0 end
	local c = A.COLOR.FX_CHAIN
	b.r, b.g, b.b = c[1], c[2], c[3]
	b.step, b.la = -1, -1
	local dots = b.dots
	local size = b.soft and max(18, len / #dots * 1.6) or 7
	b.size = size
	for k = 1, #dots do
		if b.soft then dots[k]:SetVertexColor(c[1], c[2], c[3]) else dots[k]:SetColorTexture(c[1], c[2], c[3], 1) end
		dots[k]:SetSize(size, size)
	end
	-- near-horizontal hop: the bolt texture (if it loads) lies under the dots as a stretched strip
	b.under_on = b.usoft and abs(dx) >= abs(dy) and abs(dy) < CELL * 0.6 and len > 0
	if b.under_on then
		b.under:SetVertexColor(c[1], c[2], c[3])
		b.under:ClearAllPoints()
		b.under:SetPoint("CENTER", self.host, "TOPLEFT", (x0 + x1) / 2, -(y0 + y1) / 2)
		b.under:SetSize(max(abs(dx), 8), 30)
	end
	-- spark burst where the bolt lands
	local jc = self.juice
	jc:burst(x1, y1, BoardFx.SPARKS, 110, c[1], c[2], c[3], T.CHAIN_HOP, 5)
end

function BoardFx:on_settled()
	if self.cdepth > 0 then self.csettle_t = now_of(self) end
end

-- A match resolved at chain depth `depth`: depth >= 2 shows / punches "x<depth>"; depth 1 = a fresh chain, the meter goes.
function BoardFx:combo(depth)
	if self.combo_frame == nil then return end
	depth = depth or 1
	local now = now_of(self)
	if depth < 2 then
		if self.cdepth > 0 then self:_end_combo() end
		return
	end
	if depth > self.cdepth then self.cpunch_t = now end
	self.cdepth = depth
	self.cmatch_t = now
	self.csettle_t = nil
end

function BoardFx:_end_combo()
	self.cdepth, self.cmatch_t, self.csettle_t, self.cpunch_t = 0, nil, nil, nil
	if self.cshown then
		self.cshown = false
		self.combo_frame:Hide()
	end
	self.cscale, self.calpha = -1, -1
end

-- Board light: a coloured additive wash (0.25 s in-out), an ult also darkens the board (0.3 s) under the effects.
function BoardFx:light(gem_type, tier)
	if self.wash == nil then return end
	local now = now_of(self)
	local c = A.COLOR.GEM_FX[gem_type] or A.COLOR.PROJ_DEFAULT
	self.wash_t0 = now
	self.wash_peak = tier == 2 and BoardFx.WASH_ULT or BoardFx.WASH_SKILL
	if c[1] ~= self.wash_r or c[2] ~= self.wash_g or c[3] ~= self.wash_b then
		self.wash_r, self.wash_g, self.wash_b = c[1], c[2], c[3]
		self.wash:SetColorTexture(c[1], c[2], c[3], 1)
	end
	if tier == 2 then self.dark_t0 = now end
end

---------------------------------------------------------------- per frame

local function update_cell(self, s, now)
	local t = now - s.t0
	if t < 0 then
		if t < -5 then kill_cell(self, s) end
		return
	end
	local dur = s.dur
	if t >= dur then
		kill_cell(self, s)
		return
	end
	local a, sc
	if s.mode == MODE_TELE then
		local tail = dur - BoardFx.TELE_END
		if t < tail then
			local w = sin(t * BoardFx.PULSE_W)
			a, sc = 0.55 + 0.3 * w, 0.95 + 0.08 * w
		else
			local u = (t - tail) / BoardFx.TELE_END
			a, sc = 1 - u, 1 + 0.5 * u
		end
	else
		local u = t / dur
		a = u < 0.2 and u / 0.2 or (1 - u) / 0.8
		sc = 0.8 + 0.5 * u
	end
	a = q20(a * s.peak)
	local sz = floor(s.base * sc + 0.5)
	local tex = s.tex
	if sz ~= s.lsz then
		s.lsz = sz
		tex:SetSize(sz, sz)
	end
	if a ~= s.la then
		s.la = a
		tex:SetAlpha(a)
	end
	if not s.shown then
		s.shown = true
		tex:Show()
	end
end

local function kill_beam(self, b)
	if b.t0 ~= nil then
		b.t0 = nil
		self.active_n = self.active_n - 1
	end
	if b.shown then
		b.shown = false
		b.trail:Hide()
		b.core:Hide()
	end
end

local function update_beam(self, b, now)
	local t = now - b.t0
	if t < 0 then
		if t < -5 then kill_beam(self, b) end
		return
	end
	if t >= b.life then
		kill_beam(self, b)
		return
	end
	local u = t / b.dur
	if u > 1 then u = 1 end
	local head = b.x0 + (b.x1 - b.x0) * u
	local tail = head - b.dir * BoardFx.BEAM_TRAIL * CELL
	if (tail - b.x0) * b.dir < 0 then tail = b.x0 end
	local xa, xb = head, tail
	if xa > xb then xa, xb = xb, xa end
	local w = floor(xb - xa + 0.5)
	if w < 4 then w = 4 end
	local cx = floor((xa + xb) / 2 + 0.5)
	local a = 1
	if t > b.dur then a = 1 - (t - b.dur) / BoardFx.BEAM_FADE end
	a = q20(a)
	if cx ~= b.lx or w ~= b.lw then
		b.lx, b.lw = cx, w
		local k = b.k
		b.trail:SetPoint("CENTER", self.host, "TOPLEFT", cx, -b.y)
		b.trail:SetSize(w, BoardFx.BEAM_H * k)
		b.core:SetPoint("CENTER", self.host, "TOPLEFT", cx, -b.y)
		b.core:SetSize(w, BoardFx.BEAM_CORE_H * k)
	end
	if a ~= b.la then
		b.la = a
		b.trail:SetAlpha(a * 0.6)
		b.core:SetAlpha(a)
	end
	if not b.shown then
		b.shown = true
		b.trail:Show()
		b.core:Show()
	end
end

function BoardFx:_hide_bolt(b)
	if b.shown then
		b.shown = false
		local dots = b.dots
		for k = 1, #dots do dots[k]:Hide() end
		b.under:Hide()
	end
end

local function kill_bolt(self, b)
	if b.t0 ~= nil then
		b.t0 = nil
		self.active_n = self.active_n - 1
	end
	self:_hide_bolt(b)
end

local function update_bolt(self, b, now)
	local t = now - b.t0
	if t < 0 then
		if t < -5 then kill_bolt(self, b) end
		return
	end
	if t >= b.life then
		kill_bolt(self, b)
		return
	end
	local dots = b.dots
	local n = #dots
	local step = floor(t / BoardFx.BOLT_STEP)
	if step ~= b.step then
		b.step = step
		local x0, y0, dx, dy = b.x0, b.y0, b.x1 - b.x0, b.y1 - b.y0
		local nx, ny = b.nx, b.ny
		local ox, oy = b.ox, b.oy
		for k = 1, n do
			local f = (k - 1) / (n - 1)
			local j = (rand(self) * 2 - 1) * BoardFx.BOLT_JITTER * sin(3.14159265 * f)
			ox[k], oy[k] = x0 + dx * f + nx * j, y0 + dy * f + ny * j
			local d = dots[k]
			d:ClearAllPoints()
			d:SetPoint("CENTER", self.host, "TOPLEFT", floor(ox[k] + 0.5), -floor(oy[k] + 0.5))
		end
	end
	local a = 1
	if t > b.hold then a = 1 - (t - b.hold) / (b.life - b.hold) end
	a = q20(a)
	if a ~= b.la then
		b.la = a
		for k = 1, n do dots[k]:SetAlpha(a) end
		if b.under_on then b.under:SetAlpha(a * 0.8) end
	end
	if not b.shown then
		b.shown = true
		for k = 1, n do dots[k]:Show() end
		if b.under_on then b.under:Show() end
	end
end

local function update_wedge(self, w, now)
	local t = now - w.t0
	if t < 0 then
		if t < -5 then
			w.t0 = nil
			self.active_n = self.active_n - 1
			if w.shown then
				w.shown = false
				w.tex:Hide()
			end
		end
		return
	end
	if t >= w.life then
		w.t0 = nil
		self.active_n = self.active_n - 1
		if w.shown then
			w.shown = false
			w.tex:Hide()
		end
		return
	end
	local u = t / w.dur
	if u > 1 then u = 1 end
	local width = floor(w.w * u + 0.5)
	if width < 2 then width = 2 end
	local a = 0.7
	if t > w.dur then
		a = 0.7 * (1 - (t - w.dur) / (w.life - w.dur))
	end
	a = q20(a)
	if width ~= w.lw then
		w.lw = width
		w.tex:SetSize(width, w.h)
	end
	if a ~= w.la then
		w.la = a
		w.tex:SetAlpha(a)
	end
	if not w.shown then
		w.shown = true
		w.tex:Show()
	end
end

local function update_light(self, now)
	local a = 0
	if self.wash_t0 ~= nil then
		local k = (now - self.wash_t0) / BoardFx.WASH_DUR
		if k < 0 or k >= 1 then
			self.wash_t0 = nil
		else
			a = q20(self.wash_peak * (k < 0.5 and k * 2 or (1 - k) * 2))
		end
	end
	if a ~= self.lwash then
		self.lwash = a
		self.wash:SetAlpha(a)
	end
	if a > 0 then
		if not self.wash_shown then
			self.wash_shown = true
			self.wash:Show()
		end
	elseif self.wash_shown then
		self.wash_shown = false
		self.wash:Hide()
	end
	local d = 0
	if self.dark_t0 ~= nil then
		local k = (now - self.dark_t0) / BoardFx.DARK_DUR
		if k < 0 or k >= 1 then
			self.dark_t0 = nil
		else
			d = q20(BoardFx.DARK_ALPHA * (k < 0.3 and k / 0.3 or (1 - k) / 0.7))
		end
	end
	if d ~= self.ldark then
		self.ldark = d
		self.dark:SetAlpha(d)
	end
	if d > 0 then
		if not self.dark_shown then
			self.dark_shown = true
			self.dark:Show()
		end
	elseif self.dark_shown then
		self.dark_shown = false
		self.dark:Hide()
	end
end

local function update_combo(self, now)
	local depth = self.cdepth
	if depth < 2 then return end
	local last = self.cmatch_t
	local ref = last
	local st = self.csettle_t
	if st ~= nil and st > ref then ref = st end
	local over = now - ref - BoardFx.COMBO_HOLD
	if over < 0 and now < last - 5 then over = 1 end -- time went backwards
	if over >= BoardFx.COMBO_FADE then
		self:_end_combo()
		return
	end
	local a = over > 0 and 1 - over / BoardFx.COMBO_FADE or 1
	a = q20(a)
	local sc = BoardFx.combo_scale(depth)
	local p = self.cpunch_t
	if p ~= nil then
		local k = (now - p) / BoardFx.COMBO_PUNCH
		if k < 0 or k >= 1 then
			self.cpunch_t = nil
		else
			sc = sc * (1 + BoardFx.COMBO_PUNCH_SCALE * (1 - k))
		end
	end
	sc = floor(sc * 50 + 0.5) / 50
	local text = COMBO_STR[depth] or COMBO_STR[BoardFx.COMBO_MAX]
	if text ~= self.ctext then
		self.ctext = text
		self.combo_text:SetText(text)
	end
	if sc ~= self.cscale then
		self.cscale = sc
		self.combo_frame:SetScale(sc)
	end
	if a ~= self.calpha then
		self.calpha = a
		self.combo_frame:SetAlpha(a)
	end
	if not self.cshown then
		self.cshown = true
		self.combo_frame:Show()
	end
end

-- now = sim time. Returns at once when nothing runs.
function BoardFx:update(now)
	self.now = now
	if self.wash_t0 ~= nil or self.dark_t0 ~= nil or self.wash_shown or self.dark_shown then update_light(self, now) end
	if self.cdepth >= 2 then update_combo(self, now) end
	if self.active_n <= 0 then return end
	local cells, beams, bolts = self.cells, self.beams, self.bolts
	for i = 1, #cells do
		local s = cells[i]
		if s.t0 ~= nil then update_cell(self, s, now) end
	end
	for i = 1, #beams do
		local b = beams[i]
		if b.t0 ~= nil then update_beam(self, b, now) end
	end
	for i = 1, #bolts do
		local b = bolts[i]
		if b.t0 ~= nil then update_bolt(self, b, now) end
	end
	local w = self.wedge
	if w ~= nil and w.t0 ~= nil then update_wedge(self, w, now) end
end

-- Hides everything and resets the meter / light (pause / hide / menu / game over / reset).
function BoardFx:halt()
	local cells, beams, bolts = self.cells, self.beams, self.bolts
	for i = 1, #cells do kill_cell(self, cells[i]) end
	for i = 1, #beams do kill_beam(self, beams[i]) end
	for i = 1, #bolts do kill_bolt(self, bolts[i]) end
	local w = self.wedge
	if w ~= nil and w.t0 ~= nil then
		w.t0 = nil
		if w.shown then
			w.shown = false
			w.tex:Hide()
		end
	end
	self.active_n = 0
	if self.wash ~= nil then
		self.wash_t0, self.dark_t0 = nil, nil
		self.wash:Hide()
		self.dark:Hide()
		self.wash_shown, self.dark_shown, self.lwash, self.ldark = false, false, 0, 0
		self:_end_combo()
	end
end

-- Busy slots (tests / dev).
function BoardFx:busy()
	return self.active_n
end

---------------------------------------------------------------- dev

BoardFx.DEV_KINDS = { "row_sweep", "wave", "chain", "telegraph", "telegraph_from", "area", "color", "combo2", "combo3", "combo4",
	"combo5", "combo6", "light_skill", "light_ult" }

-- Debug panel / tuning: play one effect now on a fixed spot. Returns true when played.
function BoardFx:dev(kind)
	if self.cells == nil or self.host == nil or self.wash == nil then return false end
	local T = ns.Timings
	local cells = self.dev_cells
	if cells == nil then
		cells = {}
		self.dev_cells = cells
	end
	local n = 0
	local function add(c, r)
		cells[n + 1], cells[n + 2] = c, r
		n = n + 2
	end
	self.cast_type = self.cast_type or 3
	if kind == "row_sweep" then
		-- nearest-first from column 3, like the core
		add(3, 3)
		for d = 1, 4 do
			if 3 + d < 8 then add(3 + d, 3) end
			if 3 - d >= 0 then add(3 - d, 3) end
		end
		for i = n + 1, #cells do cells[i] = nil end
		self:flash("row_sweep", cells, T.ROW_SWEEP)
	elseif kind == "wave" then
		for c = 1, 7 do
			local half = floor((c - 1) * 0.4)
			for r = 3 - half, 3 + half do add(c, r) end
		end
		for i = n + 1, #cells do cells[i] = nil end
		self:flash("wave", cells, T.WAVE_CONE)
	elseif kind == "chain" then
		local pts = { 1, 1, 4, 2, 6, 5, 2, 6 }
		local pc, pr = 0, 0
		for i = 1, #pts, 2 do
			-- one bolt per hop at once (dev); the core spaces them in time
			self:chain_hop(pc, pr, pts[i], pts[i + 1])
			pc, pr = pts[i], pts[i + 1]
		end
	elseif kind == "telegraph" or kind == "telegraph_from" then
		add(2, 2); add(3, 4); add(5, 3); add(6, 5); add(4, 6)
		for i = n + 1, #cells do cells[i] = nil end
		self:flash(kind, cells, T.CONVERT_TELEGRAPH + T.CONVERT_TELEGRAPH_FADE)
	elseif kind == "area" or kind == "color" then
		if kind == "area" then
			for c = 2, 4 do
				for r = 2, 4 do add(c, r) end
			end
		else
			add(0, 0); add(3, 1); add(7, 2); add(2, 4); add(5, 5); add(1, 7); add(6, 6)
		end
		for i = n + 1, #cells do cells[i] = nil end
		self:flash(kind, cells, T.FLASH_CELLS)
	elseif kind:sub(1, 5) == "combo" then
		local d = tonumber(kind:sub(6))
		if d == nil then return false end
		self:combo(d)
	elseif kind == "light_skill" then
		self:light(self.cast_type, 1)
	elseif kind == "light_ult" then
		self:light(self.cast_type, 2)
	else
		return false
	end
	return true
end

-- Debug panel "Texture test": every candidate of every Assets.GLOW role side by side (toggle). Created on first use.
-- A green square or nothing = that file is not in this client; a hard rectangle = no alpha (not usable with ADD).
function BoardFx:texture_test(parent)
	local tt = self.tt
	if tt == nil then
		local roles = A.GLOW_ROLES
		local f = CreateFrame("Frame", nil, parent)
		f:SetSize(#roles * 70 + 10, 2 * 96 + 36)
		f:SetPoint("CENTER", parent, "CENTER", 0, 0)
		f:SetFrameLevel(self.host:GetFrameLevel() + 40)
		local bg = f:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(f)
		bg:SetColorTexture(0, 0, 0, 0.92)
		local head = f:CreateFontString(nil, "OVERLAY", A.FONT_LABEL_SMALL)
		head:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -6)
		head:SetText("Texture test (A.GLOW candidates; green square / nothing = missing)")
		f.tex = {}
		for i = 1, #roles do
			local spec = A.GLOW[roles[i]]
			for k = 1, 2 do
				local path = type(spec) == "table" and spec[k] or nil
				local t = f:CreateTexture(nil, "ARTWORK")
				t:SetSize(64, 64)
				t:SetPoint("TOPLEFT", f, "TOPLEFT", 8 + (i - 1) * 70, -26 - (k - 1) * 96)
				local ok = false
				if path then ok = pcall(t.SetTexture, t, path) end
				if not ok then t:SetColorTexture(0.2, 0.2, 0.2, 1) end
				t:SetBlendMode("ADD")
				t:SetVertexColor(1, 0.6, 0.2)
				f.tex[#f.tex + 1] = t
				local lab = f:CreateFontString(nil, "OVERLAY", A.FONT_HUD_SMALL)
				lab:SetPoint("TOP", t, "BOTTOM", 0, -2)
				lab:SetWidth(68)
				lab:SetText(roles[i] .. (k == 1 and "" or " (fb)"))
			end
		end
		f:Hide()
		self.tt = f
		tt = f
	end
	if tt:IsShown() then tt:Hide() else tt:Show() end
	return tt:IsShown()
end

ns.BoardFx = BoardFx
