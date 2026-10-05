local addonName, ns = ...
-- Board view (W0-P1): renders the core board into a host frame. Read-only on
-- core state: positions come from gem.x / gem.y (float cells, row 0 = top),
-- effects from gem.fx / gem.fx_t (written by the sim each tick). The input's
-- drag offsets are view-side and added on top (they never touch the board).
--
-- 64 gem frames are created once and pooled; gem_created / gem_removed bind and
-- release them. update() creates no tables and only calls frame setters for
-- values that changed.
--
-- W0-P2: 8 x 64 px cells; translucent tiles over the board panel's dimmed
-- background art; ability gems (tier 1 / 2 / bomb) show their ability's spell
-- icon as a round overlay. The icon key comes from set_icon_source(fn) (the app
-- asks the combat kit: fn(gem_type, tier, bomb) -> icon key), so the view knows
-- no abilities; it only runs when a gem's look changes.
--
-- W0-P6 match break: a gem whose sim effect is "fuse" (match: converges on the spawn / centre cell in
-- Timings.FUSE) or "clear" (ability / junk clears) swells with an additive flash (a second copy of its icon,
-- ADD blend), then shrinks, spins (Texture:SetRotation, guarded, only for full-texcoord gem sets) and fades;
-- "pop" (fresh ability gem) flashes too. All curves are pure functions of gem.fx_t (sim time).

-- W0-P7 gem motion and charge (all view-only, pure functions of sim time / gem.fx_t): a falling gem stretches a little,
-- a landing one squashes and springs back (fx_curve returns two extra multipliers sx, sy; the frame is SetSize(w, h));
-- landing fires on_land(col, row) (the HUD's dust puff); swapping gems flash at the swap start; a rejected swap shakes
-- both gems sideways (+-REJECT_AMP cells, 2 cycles in 2 * SWAP, offset 0 again afterwards) and fires on_reject(c1, r1, c2,
-- r2); ability gems get a pooled aura (halo + orbiting dots, ult: slow flare) while they are on the board; the
-- selection glow breathes and the dragged gem gets a soft halo. The core is never written.

local floor, sin, cos, pi = math.floor, math.sin, math.cos, math.pi
local pcall = pcall
local SWAPPING = 1 -- Board.SWAPPING (resolved in new)

local BoardView = {}
BoardView.__index = BoardView

BoardView.CELL = 64 -- px per cell (W0-P2 open decision 2: board 8 x 64 px, scale 1.0)
local GEM_FILL = 0.92 -- gem size as a fraction of the cell
local SPELL_FILL = 0.56 -- spell icon overlay, fraction of the gem size
local POOL = 64
-- Idle hint wiggle (W0-P4; Godot HINT_WIGGLE_*: out 0.12 + swing 0.24 + back 0.12, rest 0.85 s) as a
-- sideways nudge of the pair toward / away from each other; shuffle pop (view-only scale pulse).
local HINT_ACTIVE, HINT_PERIOD, HINT_AMP = 0.48, 1.33, 0.12
local POP_DUR, POP_STAGGER, POP_AMP = 0.28, 0.015, 0.3
local LEVEL_SELECT, LEVEL_GEM, LEVEL_HELD = 2, 3, 8
-- Swap hint (W0-P5, Godot board_input.gd _refresh_swap_hints): a selected skill / ult gem rings the neighbours it
-- would activate with (same colour) and shows a text over the bottom row. Pooled: at most 4 neighbours.
local HINT_RINGS, LEVEL_HINT = 4, 6
local TWO_PI = 2 * pi
-- W0-P7 tuning.
local SPELL_ALPHA = 0.75 -- the skill icon shows through the gem
local FALL_STRETCH, LAND_SQUASH = 0.06, 0.12 -- fall: up to 1.06 tall; land: 1.12 wide / 0.88 tall, springs back with one overshoot
local SWAP_FLASH_PEAK = 0.7
local REJECT_AMP = 0.1 -- cells
local AURA_SLOTS, AURA_LEVEL_BACK, AURA_LEVEL_FRONT = 12, 2, 4
local AURA_DOTS = 3
local BREATHE_HZ, BREATHE_LO, BREATHE_HI = 1.6, 0.35, 0.65
local HELD_HALO_SIZE, HELD_HALO_ALPHA = 1.6, 0.45 -- cells, alpha
BoardView.AURA_SLOTS = AURA_SLOTS
BoardView.can_rotate = true -- cleared when Texture:SetRotation is missing / raises (the spin is skipped then)
local HINT_DC = { 1, -1, 0, 0 }
local HINT_DR = { 0, 0, 1, -1 }
BoardView.HINT_SKILL = "SKILL - swap with same colour to activate"
BoardView.HINT_ULT = "ULT - swap with same colour to activate"

local A -- ns.Assets (resolved in new: files load in TOC order)

local function masked_texture(frame, layer, sublevel)
	local tex = frame:CreateTexture(nil, layer, nil, sublevel)
	local mask = frame:CreateMaskTexture()
	mask:SetTexture(A.ROUND_MASK, A.MASK_WRAP, A.MASK_WRAP)
	mask:SetAllPoints(tex)
	tex:AddMaskTexture(mask)
	tex.dc_mask, tex.dc_round = mask, true
	return tex
end

local function color(tex, c)
	tex:SetColorTexture(c[1], c[2], c[3], c[4])
end

-- A soft glow texture (Assets.GLOW.glow) or, if it does not load, a round-masked colour disc; second result = soft?
local function soft_or_disc(frame, layer, sub, role)
	local tex = frame:CreateTexture(nil, layer, nil, sub)
	if A.soft(tex, role or "glow") then
		tex:SetBlendMode("ADD")
		tex:Hide()
		return tex, true
	end
	local mask = frame:CreateMaskTexture()
	mask:SetTexture(A.ROUND_MASK, A.MASK_WRAP, A.MASK_WRAP)
	mask:SetAllPoints(tex)
	tex:AddMaskTexture(mask)
	tex:SetColorTexture(1, 1, 1, 1)
	tex:SetBlendMode("ADD")
	tex:Hide()
	return tex, false
end

-- host: the board frame (owned by the window); cols/rows of the board.
function BoardView.new(host, cols, rows)
	A = ns.Assets
	SWAPPING = ns.Board.SWAPPING
	local self = setmetatable({}, BoardView)
	self.host = host
	self.cols, self.rows = cols, rows
	self.active = {} -- bound frames, dense array
	self.free = {} -- unbound frames (stack)
	self.frame_of = {} -- gem -> frame (lookup only, never iterated)
	self.sim = nil
	self.icon_source = nil -- fn(gem_type, tier, bomb) -> icon key (set_icon_source)
	self.base_level = host:GetFrameLevel()
	local cell = BoardView.CELL
	host:SetSize(cols * cell, rows * cell)
	-- Refills spawn above the board (y < 0): clip them to the board.
	self.clips = host.SetClipsChildren ~= nil
	if self.clips then host:SetClipsChildren(true) end

	-- Checkerboard tiles (created once).
	for c = 0, cols - 1 do
		for r = 0, rows - 1 do
			local t = host:CreateTexture(nil, "BACKGROUND")
			t:SetSize(cell, cell)
			t:SetPoint("TOPLEFT", host, "TOPLEFT", c * cell, -r * cell)
			color(t, ((c + r) % 2 == 0) and A.COLOR.TILE_LIGHT or A.COLOR.TILE_DARK)
		end
	end

	-- Selection glow (one frame, moved to the selected gem).
	local sel = CreateFrame("Frame", nil, host)
	sel:SetFrameLevel(self.base_level + LEVEL_SELECT)
	sel:SetSize(cell, cell)
	sel.tex = masked_texture(sel, "ARTWORK")
	sel.tex:SetAllPoints(sel)
	local sc = A.COLOR.SELECT
	sel.tex:SetColorTexture(sc[1], sc[2], sc[3], 1) -- the alpha breathes (SetAlpha, BREATHE_LO .. HI)
	sel.tex:SetAlpha(BREATHE_LO)
	sel.la = BREATHE_LO
	sel:Hide()
	self.sel = sel
	self.sel_gem = nil

	-- Dragged gem: soft halo under it (one frame between the gems and the held gem).
	local hh = CreateFrame("Frame", nil, host)
	hh:SetAllPoints(host)
	hh:SetFrameLevel(self.base_level + LEVEL_HELD - 1)
	hh.tex, hh.soft = soft_or_disc(hh, "ARTWORK", 0)
	local hc = A.COLOR.HELD_SHADOW
	if hh.soft then hh.tex:SetVertexColor(hc[1], hc[2], hc[3]) else hh.tex:SetColorTexture(hc[1], hc[2], hc[3], 1) end
	hh.tex:SetSize(cell * HELD_HALO_SIZE, cell * HELD_HALO_SIZE)
	hh.shown = false
	hh.tex:SetAlpha(hh.soft and HELD_HALO_ALPHA or HELD_HALO_ALPHA * 0.5)
	self.held_halo = hh

	-- Ability gem auras (pooled; halo + flare behind the gems, orbiting dots in front).
	self.auras = {}
	local back = CreateFrame("Frame", nil, host)
	back:SetAllPoints(host)
	back:SetFrameLevel(self.base_level + AURA_LEVEL_BACK)
	local front = CreateFrame("Frame", nil, host)
	front:SetAllPoints(host)
	front:SetFrameLevel(self.base_level + AURA_LEVEL_FRONT)
	for i = 1, AURA_SLOTS do
		local halo, soft = soft_or_disc(back, "ARTWORK", 1)
		local flare = back:CreateTexture(nil, "ARTWORK", nil, 0)
		local fsoft = A.soft(flare, "flare")
		if not fsoft then flare = nil else flare:SetBlendMode("ADD"); flare:Hide() end
		local dots = {}
		for k = 1, AURA_DOTS do
			local d = front:CreateTexture(nil, "OVERLAY", nil, 1)
			if not A.soft(d, "glow") then d:SetColorTexture(1, 1, 1, 1) end
			d:SetBlendMode("ADD")
			d:Hide()
			dots[k] = d
		end
		self.auras[i] = { halo = halo, soft = soft, flare = flare, dots = dots, f = nil, kind = 0, shown = false, ndots = 0,
			lx = nil, ly = nil, lhs = 0, lha = -1, lfa = -1, lfr = nil, dx = {}, dy = {} }
		for k = 1, AURA_DOTS do self.auras[i].dx[k], self.auras[i].dy[k] = nil, nil end
	end
	self.rej_a, self.rej_b, self.rej_t0 = nil, nil, nil
	self.on_land, self.on_reject = nil, nil -- fn(col, row) / fn(c1, r1, c2, r2) set by the HUD (dust, puff)

	-- Swap hint rings (pooled) + text.
	self.rings = {}
	for i = 1, HINT_RINGS do
		local r = CreateFrame("Frame", nil, host)
		r:SetFrameLevel(self.base_level + LEVEL_HINT)
		r:SetSize(cell, cell)
		r.tex = masked_texture(r, "ARTWORK")
		r.tex:SetAllPoints(r)
		color(r.tex, A.COLOR.HINT_RING)
		r.tex:SetBlendMode("ADD")
		r:Hide()
		self.rings[i] = r
	end
	local hf = CreateFrame("Frame", nil, host)
	hf:SetFrameLevel(self.base_level + LEVEL_HINT + 1)
	hf:SetAllPoints(host)
	self.hint_text = hf:CreateFontString(nil, "OVERLAY", A.FONT_BANNER_SUB)
	self.hint_text:SetPoint("BOTTOM", host, "BOTTOM", 0, 6)
	local hc = A.COLOR.HINT_TEXT
	self.hint_text:SetTextColor(hc[1], hc[2], hc[3], hc[4])
	self.hint_text:Hide()
	self.hint_kind = nil -- 1 / 2 (tier of the hinted gem) or nil
	self.hint_n = 0

	for _ = 1, POOL do self.free[#self.free + 1] = self:_create_gem_frame() end

	self._on_created = function(gem) self:_acquire(gem) end
	self._on_removed = function(gem) self:_release(gem) end
	self._on_rejected = function(a, b) self:_reject(a, b) end
	return self
end

function BoardView:_create_gem_frame()
	local f = CreateFrame("Frame", nil, self.host)
	f:SetFrameLevel(self.base_level + LEVEL_GEM)
	f:SetSize(BoardView.CELL, BoardView.CELL)
	-- Protected glow behind the gem (additive, slightly larger).
	local glow = masked_texture(f, "BACKGROUND")
	glow:SetPoint("TOPLEFT", f, "TOPLEFT", -3, 3)
	glow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 3, -3)
	color(glow, A.COLOR.PROTECTED)
	glow:SetBlendMode("ADD")
	glow:Hide()
	f.glow = glow
	-- Gem icon (cropped + round mask).
	local icon = masked_texture(f, "ARTWORK")
	icon:SetAllPoints(f)
	local tc = A.GEM_TEXCOORD
	icon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
	f.icon = icon
	-- Match-break flash: a second copy of the icon, additive (brightens exactly the gem's shape).
	local flash = masked_texture(f, "ARTWORK", 1)
	flash:SetAllPoints(f)
	flash:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
	flash:SetBlendMode("ADD")
	flash:Hide()
	f.flash = flash
	f.lfl, f.lrot, f.fshown = 0, 0, false
	-- Ability spell icon overlay (tier 1 / 2 / bomb): dark disc + round icon.
	local disc = masked_texture(f, "OVERLAY", 0)
	disc:SetPoint("CENTER", f, "CENTER", 0, 0)
	color(disc, A.COLOR.SPELL_RING)
	disc:Hide()
	f.spell_disc = disc
	local spell = masked_texture(f, "OVERLAY", 1)
	spell:SetPoint("CENTER", f, "CENTER", 0, 0)
	spell:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
	spell:Hide()
	f.spell = spell
	local base = BoardView.CELL * GEM_FILL * SPELL_FILL
	disc:SetSize(base + 4, base + 4)
	spell:SetSize(base, base)
	-- Badge: rim + pip in the top-right corner (tier 1 / tier 2 / bomb).
	local rim = masked_texture(f, "OVERLAY", 2)
	rim:SetPoint("CENTER", f, "TOPRIGHT", -9, -9)
	rim:SetSize(18, 18)
	rim:Hide()
	f.rim = rim
	local pip = masked_texture(f, "OVERLAY", 3)
	pip:SetPoint("CENTER", rim, "CENTER", 0, 0)
	pip:SetSize(11, 11)
	pip:Hide()
	f.pip = pip
	f:Hide()
	return f
end

---------------------------------------------------------------- binding

-- fn(gem_type, tier, bomb) -> icon key (ns.Assets.icon) for ability gems, or nil.
function BoardView:set_icon_source(fn)
	self.icon_source = fn
	local active = self.active
	for i = 1, #active do active[i].ltype = nil end -- refresh looks on the next update
end

-- The gem set changed (App.set_gem_set): every gem frame redraws its look now.
function BoardView:refresh_looks()
	local active = self.active
	for i = 1, #active do
		local f = active[i]
		f.ltype = nil
		if f.gem ~= nil then self:_refresh_look(f, f.gem) end -- at once: the menu pauses update
	end
end

-- Bind to a sim (also after reset/restore): every grid gem gets a frame.
function BoardView:bind(sim)
	self:unbind()
	self.sim = sim
	sim:on("gem_created", self._on_created)
	sim:on("gem_removed", self._on_removed)
	sim:on("swap_rejected", self._on_rejected)
	local board = sim.board
	for i = 1, board.cols * board.rows do
		local gem = board.cells[i]
		if gem ~= nil and not gem.removed then self:_acquire(gem) end
	end
	self:update(nil)
end

-- Idle hint: wiggle gem a toward / away from b (dc, dr = the swap direction in cells).
function BoardView:set_hint(a, b, dc, dr)
	self.hint_a, self.hint_b, self.hint_dc, self.hint_dr = a, b, dc, dr
	self.hint_t0 = self.sim ~= nil and self.sim.now or 0
end

function BoardView:clear_hint()
	self.hint_a, self.hint_b = nil, nil
end

-- Shuffle feedback: every gem pops once (staggered across the board).
function BoardView:pop()
	if self.sim ~= nil then self.pop_t0 = self.sim.now end
end

function BoardView:unbind()
	self.hint_a, self.hint_b, self.pop_t0 = nil, nil, nil
	local sim = self.sim
	if sim ~= nil then
		sim:off("gem_created", self._on_created)
		sim:off("gem_removed", self._on_removed)
		sim:off("swap_rejected", self._on_rejected)
	end
	self.sim = nil
	self.rej_a, self.rej_b, self.rej_t0 = nil, nil, nil
	local active = self.active
	for i = #active, 1, -1 do self:_release(active[i].gem) end
	self.sel:Hide()
	self.sel_gem = nil
	self:_update_swap_hints(nil)
	self:halt_fx()
end

-- A swap was rejected (sim event, payload = the two gems): they shake sideways for 2 * SWAP, view-only; the HUD puffs.
function BoardView:_reject(a, b)
	if a == nil or b == nil or self.sim == nil then return end
	self.rej_a, self.rej_b, self.rej_t0 = a, b, self.sim.now
	local cb = self.on_reject
	if cb ~= nil then cb(a.col, a.row, b.col, b.row) end
end

-- Debug panel: shake the gems at (3,3) / (4,3) as a rejected swap would. Returns true when played.
function BoardView:dev_reject()
	if self.sim == nil then return false end
	local board = self.sim.board
	local a, b = board:get(3, 3), board:get(4, 3)
	if a == nil or b == nil then return false end
	self:_reject(a, b)
	return true
end

-- Pause / hide / menu / game over: the view-only effects go (auras, dragged halo, shake, swap flashes). The next update
-- brings back what still applies.
function BoardView:halt_fx()
	self.rej_a, self.rej_b, self.rej_t0 = nil, nil, nil
	local auras = self.auras
	for i = 1, #auras do self:_free_aura(auras[i]) end
	local active = self.active
	for i = 1, #active do
		local f = active[i]
		f.aura, f.sw_t0 = nil, nil
	end
	local hh = self.held_halo
	if hh ~= nil and hh.shown then
		hh.shown = false
		hh.tex:Hide()
	end
end

function BoardView:_acquire(gem)
	if self.frame_of[gem] ~= nil then return end
	local free = self.free
	local f = free[#free]
	if f ~= nil then
		free[#free] = nil
	else
		-- Safety net only: the grid never holds more than cols * rows live gems.
		f = self:_create_gem_frame()
	end
	f.gem = gem
	f.lx, f.ly, f.ls, f.la = nil, nil, nil, nil
	self:_clear_break(f)
	f.ltype, f.ltier, f.lbomb, f.ljunk, f.lprot = nil, nil, nil, nil, nil
	f.raised = false
	f.aura, f.sw_t0, f.lfx, f.lsx, f.lsy = nil, nil, nil, nil, nil
	f:SetFrameLevel(self.host:GetFrameLevel() + LEVEL_GEM)
	local active = self.active
	active[#active + 1] = f
	f.idx = #active
	self.frame_of[gem] = f
	f:Show()
end

-- Flash off, rotation back to 0 (a frame is re-bound or a gem's effect ended).
function BoardView:_clear_break(f)
	if f.fshown then
		f.fshown = false
		f.flash:Hide()
	end
	f.lfl = 0
	if f.lrot ~= 0 then
		f.lrot = 0
		if BoardView.can_rotate then
			local ok = pcall(f.icon.SetRotation, f.icon, 0)
			if ok then pcall(f.flash.SetRotation, f.flash, 0) end
		end
	end
end

function BoardView:_release(gem)
	local f = self.frame_of[gem]
	if f == nil then return end
	self.frame_of[gem] = nil
	local active = self.active
	local last = active[#active]
	active[f.idx] = last
	last.idx = f.idx
	active[#active] = nil
	f.gem = nil
	if f.aura ~= nil then self:_free_aura(f.aura) end
	f.aura, f.sw_t0 = nil, nil
	self:_clear_break(f)
	f:Hide()
	self.free[#self.free + 1] = f
	if self.sel_gem == gem then
		self.sel:Hide()
		self.sel_gem = nil
	end
end

---------------------------------------------------------------- per frame

function BoardView:_refresh_look(f, gem)
	local t, tier, bomb, junk, prot = gem.type, gem.tier, gem.bomb, gem.junk, gem.protected
	f.ltype, f.ltier, f.lbomb, f.ljunk, f.lprot = t, tier, bomb, junk, prot
	local icon = f.icon
	A.apply_gem(icon, t)
	A.apply_gem(f.flash, t)
	f.lrot = 0 -- SetTexCoord (apply_gem) resets a rotation
	icon:SetDesaturated(junk)
	f.flash:SetDesaturated(junk)
	local C = A.COLOR
	if junk then
		local c = C.JUNK_TINT
		icon:SetVertexColor(c[1], c[2], c[3])
	else
		icon:SetVertexColor(1, 1, 1)
	end
	local rim_c, pip_c
	if bomb then
		rim_c, pip_c = C.BOMB_RIM, C.BOMB_PIP
	elseif tier == 2 then
		rim_c, pip_c = C.TIER2_RIM, C.TIER2_PIP
	elseif tier == 1 then
		rim_c, pip_c = C.TIER1_RIM, C.TIER1_PIP
	end
	if false and rim_c ~= nil then -- playtest 5: no corner badge, the spell icon inside the gem tells the tier
		color(f.rim, rim_c)
		color(f.pip, pip_c)
		f.rim:Show()
		f.pip:Show()
	else
		f.rim:Hide()
		f.pip:Hide()
	end
	local key
	if (bomb or tier > 0) and self.icon_source ~= nil then key = self.icon_source(t, tier, bomb) end
	if key ~= nil then
		f.spell:SetTexture(A.icon(key))
		f.spell:SetDesaturated(junk)
		f.spell:SetAlpha(SPELL_ALPHA)
		f.spell:Show()
		f.spell_disc:Hide()
	else
		f.spell:Hide()
		f.spell_disc:Hide()
	end
	if prot then f.glow:Show() else f.glow:Hide() end
end

-- Effect curves (view-only): scale, alpha, rotation (rad) and flash strength (0..1) from gem.fx / gem.fx_t.
-- Match break ("fuse", FUSE s): flash + swell, then shrink / spin / fade as the gem arrives. "clear" (ability /
-- junk clears) is the same shape on a longer swell. No flash before the effect really started (stagger delay).
local SWELL, BREAK_ROT, CLEAR_ROT = 0.18, 1.2 * pi, pi
local function fx_curve(fx, t)
	if fx == "fuse" then
		local s
		if t < 0.3 then
			s = 1 + SWELL * (t / 0.3)
		else
			local u = (t - 0.3) / 0.7
			s = 1 + SWELL - 1.08 * u * u
		end
		local a = t < 0.5 and 1 or 1 - (t - 0.5) / 0.5
		local fl = (t > 0 and t < 0.35) and 0.9 * (1 - t / 0.35) or 0
		return s, a, BREAK_ROT * t * t, fl
	end
	if fx == "clear" then
		local s
		if t < 0.25 then
			s = 1 + 0.25 * (t / 0.25)
		else
			local u = (t - 0.25) / 0.75
			s = 1.25 - 1.05 * u * u
		end
		local a = t < 0.3 and 1 or 1 - (t - 0.3) / 0.7
		local fl = (t > 0 and t < 0.4) and 0.9 * (1 - t / 0.4) or 0
		return s, a, CLEAR_ROT * t * t, fl
	end
	if fx == "pop" then return 1 + 0.3 * sin(pi * t), 1, 0, t > 0 and 0.8 * (1 - t) or 0 end
	-- W0-P7: fall = a tiny vertical stretch growing to the landing; land = squash (wide / flat) that springs back with one
	-- overshoot (amp(t) = sin(2.5 pi t) (1 - t): 0 -> +1 -> 0 -> -1 -> 0). The two extra results multiply width / height.
	if fx == "fall" then return 1, 1, 0, 0, 1, 1 + FALL_STRETCH * t end
	if fx == "land" then
		local amp = sin(2.5 * pi * t) * (1 - t)
		return 1 - 0.03 * sin(pi * t), 1, 0, 0, 1 + LAND_SQUASH * amp, 1 - LAND_SQUASH * amp
	end
	if fx == "telegraph" then return 1, 0.65 + 0.35 * cos(t * pi * 6), 0, 0 end
	if fx == "morph_out" then return 1 - 0.5 * t, 1, 0, 0 end
	if fx == "morph_in" then return 0.5 + 0.5 * t, 1, 0, 0 end
	return 1, 1, 0, 0
end
BoardView.fx_curve = fx_curve -- tests

-- Alpha / flash quantised to 20 steps (fewer setter calls).
local function q20(a)
	if a <= 0 then return 0 end
	if a >= 1 then return 1 end
	return floor(a * 20 + 0.5) / 20
end

-- input: ns.Input instance or nil (held / neighbour gem offsets in cells,
-- selected gem).
function BoardView:update(input)
	local held, hx, hy, nb, nx, ny, selected
	if input ~= nil then
		held, hx, hy = input.held, input.hx, input.hy
		nb, nx, ny = input.nb, input.nx, input.ny
		selected = input.selected
	end
	local cell = BoardView.CELL
	local host = self.host
	local clips = self.clips
	local active = self.active
	-- hint wiggle offset of the pair (cells) and shuffle pop clock
	local ha, hb, hox, hoy = self.hint_a, self.hint_b, 0, 0
	local now = self.sim ~= nil and self.sim.now or 0
	if ha ~= nil then
		local phase = (now - self.hint_t0) % HINT_PERIOD
		if phase < HINT_ACTIVE then
			local w = HINT_AMP * sin(2 * pi * phase / HINT_ACTIVE)
			hox, hoy = w * self.hint_dc, w * self.hint_dr
		end
	end
	-- spin only for full-texcoord gem sets (SetRotation replaces the crop of a cropped icon)
	local spin = BoardView.can_rotate
	if spin then
		local _, tc = A.gem(0)
		spin = tc[1] == 0 and tc[2] == 1 and tc[3] == 0 and tc[4] == 1
	end
	local pop_t0 = self.pop_t0
	if pop_t0 ~= nil and now - pop_t0 > POP_DUR + 2 * POP_STAGGER * 8 then
		pop_t0 = nil
		self.pop_t0 = nil
	end
	-- rejected swap: sideways shake of the two gems (cells), back to 0 after 2 * SWAP
	local ra, rb, rox = self.rej_a, self.rej_b, 0
	if ra ~= nil then
		local swap_t = ns.Timings.SWAP
		local u = (now - self.rej_t0) / (swap_t * 2)
		if u < 0 or u >= 1 then
			self.rej_a, self.rej_b, self.rej_t0 = nil, nil, nil
			ra, rb = nil, nil
		else
			rox = REJECT_AMP * sin(4 * pi * u)
		end
	end
	local swap_dur = ns.Timings.SWAP
	local on_land = self.on_land
	for i = 1, #active do
		local f = active[i]
		local gem = f.gem
		local x, y = gem.x, gem.y
		local s, a, rot, fl, sx, sy = 1, 1, 0, 0, 1, 1
		local fxk = gem.fx
		if fxk ~= nil then
			s, a, rot, fl, sx, sy = fx_curve(fxk, gem.fx_t)
			sx, sy = sx or 1, sy or 1
		end
		if fxk == "land" and f.lfx ~= "land" and on_land ~= nil then on_land(gem.col, gem.row) end
		f.lfx = fxk
		if gem.state == SWAPPING then
			local t0 = f.sw_t0
			if t0 == nil then
				t0 = now
				f.sw_t0 = now
			end
			local k = (now - t0) / swap_dur
			if k >= 0 and k < 1 then
				local v = SWAP_FLASH_PEAK * (1 - k)
				if v > fl then fl = v end
			end
		elseif f.sw_t0 ~= nil then
			f.sw_t0 = nil
		end
		local raise = false
		if gem == held then
			x, y = x + hx, y + hy
			s = s * 1.08
			raise = true
		elseif gem == nb then
			x, y = x + nx, y + ny
		end
		if gem == ra or gem == rb then x = x + rox end
		if gem == ha then
			x, y = x + hox, y + hoy
		elseif gem == hb then
			x, y = x - hox, y - hoy
		end
		if pop_t0 ~= nil then
			local p = (now - pop_t0 - (gem.x + gem.y) * POP_STAGGER) / POP_DUR
			if p > 0 and p < 1 then s = s * (1 + POP_AMP * sin(pi * p)) end
		end
		if not clips and y < -0.5 then a = 0 end
		if raise ~= f.raised then
			f.raised = raise
			f:SetFrameLevel(host:GetFrameLevel() + (raise and LEVEL_HELD or LEVEL_GEM))
		end
		if x ~= f.lx or y ~= f.ly or s ~= f.ls or sx ~= f.lsx or sy ~= f.lsy then
			f.lx, f.ly = x, y
			f:SetPoint("CENTER", host, "TOPLEFT", (x + 0.5) * cell, -(y + 0.5) * cell)
			if s ~= f.ls or sx ~= f.lsx or sy ~= f.lsy then
				f.ls, f.lsx, f.lsy = s, sx, sy
				local size = cell * GEM_FILL * s
				f:SetSize(size * sx, size * sy)
				local ss = size * SPELL_FILL
				f.spell:SetSize(ss, ss)
				f.spell_disc:SetSize(ss + 4, ss + 4)
			end
		end
		if a ~= f.la then
			f.la = a
			f:SetAlpha(a)
		end
		fl = q20(fl)
		if fl ~= f.lfl then
			f.lfl = fl
			if fl > 0 then
				f.flash:SetAlpha(fl)
				if not f.fshown then
					f.fshown = true
					f.flash:Show()
				end
			elseif f.fshown then
				f.fshown = false
				f.flash:Hide()
			end
		end
		if spin then
			rot = floor(rot * 20 + 0.5) / 20
			if rot ~= f.lrot then
				f.lrot = rot
				local ok = pcall(f.icon.SetRotation, f.icon, rot % TWO_PI)
				if ok then
					pcall(f.flash.SetRotation, f.flash, rot % TWO_PI)
				else
					BoardView.can_rotate = false
				end
			end
		end
		if gem.type ~= f.ltype or gem.tier ~= f.ltier or gem.bomb ~= f.lbomb
			or gem.junk ~= f.ljunk or gem.protected ~= f.lprot then
			self:_refresh_look(f, gem)
		end
		-- ability aura (pooled): skill / ult / bomb gems
		local ak = gem.bomb and 3 or (gem.tier == 2 and 2) or (gem.tier == 1 and 1) or 0
		local au = f.aura
		if ak > 0 then
			if au == nil then au = self:_alloc_aura(f, ak) end
			if au ~= nil then self:_update_aura(au, x, y, s, a, now, gem.id, ak) end
		elseif au ~= nil then
			self:_free_aura(au)
		end
	end
	self:_update_swap_hints(selected)
	-- Selection glow follows the selected gem.
	local sel = self.sel
	if selected ~= nil and self.frame_of[selected] ~= nil then
		if self.sel_gem ~= selected or sel.lx ~= selected.x or sel.ly ~= selected.y then
			self.sel_gem = selected
			sel.lx, sel.ly = selected.x, selected.y
			sel:SetPoint("CENTER", host, "TOPLEFT", (selected.x + 0.5) * cell, -(selected.y + 0.5) * cell)
			sel:Show()
		end
		-- breathing glow
		local ba = q20(BREATHE_LO + (BREATHE_HI - BREATHE_LO) * (0.5 + 0.5 * sin(TWO_PI * BREATHE_HZ * now)))
		if ba ~= sel.la then
			sel.la = ba
			sel.tex:SetAlpha(ba)
		end
	elseif self.sel_gem ~= nil then
		self.sel_gem = nil
		sel:Hide()
	end
	-- soft halo under the dragged gem
	local hh = self.held_halo
	if held ~= nil and self.frame_of[held] ~= nil then
		local px, py = floor((held.x + hx + 0.5) * cell + 0.5), floor((held.y + hy + 0.5) * cell + 0.5)
		if px ~= hh.lx or py ~= hh.ly then
			hh.lx, hh.ly = px, py
			hh.tex:SetPoint("CENTER", host, "TOPLEFT", px, -py)
		end
		if not hh.shown then
			hh.shown = true
			hh.tex:Show()
		end
	elseif hh.shown then
		hh.shown = false
		hh.tex:Hide()
	end
end

---------------------------------------------------------------- ability auras (W0-P7 B5)

local function aura_color(kind)
	local C = A.COLOR
	return kind == 3 and C.AURA_BOMB or kind == 2 and C.AURA_ULT or C.AURA_SKILL
end

function BoardView:_set_aura_kind(au, kind)
	au.kind = kind
	local c = aura_color(kind)
	if au.soft then au.halo:SetVertexColor(c[1], c[2], c[3]) else au.halo:SetColorTexture(c[1], c[2], c[3], 1) end
	local dots = au.dots
	au.ndots = 0 -- playtest 5: a glow only, no orbiting dots
	for k = 1, #dots do
		local d = dots[k]
		d:SetVertexColor(c[1] * 0.5 + 0.5, c[2] * 0.5 + 0.5, c[3] * 0.5 + 0.5)
		if k > au.ndots then d:Hide() end
		au.dx[k], au.dy[k] = nil, nil
	end
	if au.flare ~= nil then
		au.flare:SetVertexColor(c[1], c[2], c[3])
		if kind ~= 2 then au.flare:Hide() end
	end
	au.lhs, au.lha, au.lfa, au.lfr, au.lx, au.ly = 0, -1, -1, nil, nil, nil
	if au.shown then
		for k = 1, au.ndots do dots[k]:Show() end
		if au.flare ~= nil and kind == 2 then au.flare:Show() end
	end
end

function BoardView:_alloc_aura(f, kind)
	local auras = self.auras
	for i = 1, #auras do
		local au = auras[i]
		if au.f == nil then
			au.f = f
			f.aura = au
			self:_set_aura_kind(au, kind)
			return au
		end
	end
	return nil
end

function BoardView:_free_aura(au)
	if au.f ~= nil then
		au.f.aura = nil
		au.f = nil
	end
	if au.shown then
		au.shown = false
		au.halo:Hide()
		if au.flare ~= nil then au.flare:Hide() end
		local dots = au.dots
		for k = 1, #dots do dots[k]:Hide() end
	end
	au.lx, au.ly, au.lhs, au.lha, au.lfa, au.lfr = nil, nil, 0, -1, -1, nil
	au.kind = 0
end

-- skill: cyan halo pulsing 0.8 -> 1.0 at 1.4 Hz + 2 orbiting dots; ult: golden halo 0.85 -> 1.15 at 1.0 Hz, a slow
-- rotating flare behind it + 3 dots; bomb: red flicker. Phase offset by the gem id; every setter only on a changed
-- quantised value (size int px, alpha 20 steps, pulse 0.04 steps, dot angle 24 steps).
function BoardView:_update_aura(au, x, y, s, a, now, id, kind)
	if au.kind ~= kind then self:_set_aura_kind(au, kind) end
	local cell = BoardView.CELL
	local host = self.host
	local px, py = floor((x + 0.5) * cell + 0.5), floor((y + 0.5) * cell + 0.5)
	local gs = cell * GEM_FILL * s
	local ph = id * 0.37
	local pulse
	if kind == 2 then
		pulse = 1.0 + 0.15 * sin(TWO_PI * 1.0 * now + ph)
	elseif kind == 3 then
		local v = 0.5 + 0.5 * sin(now * 31 + ph) * sin(now * 13.7 + ph * 2)
		pulse = 0.8 + 0.3 * v
	else
		pulse = 0.9 + 0.1 * sin(TWO_PI * 1.4 * now + ph)
	end
	pulse = floor(pulse * 25 + 0.5) / 25
	local hs = floor(gs * (au.soft and 1.5 or 1.2) * pulse + 0.5)
	local ha = q20(a * (au.soft and 0.45 or 0.22) * pulse)
	local halo = au.halo
	local moved = px ~= au.lx or py ~= au.ly
	if moved then
		au.lx, au.ly = px, py
		halo:SetPoint("CENTER", host, "TOPLEFT", px, -py)
		if au.flare ~= nil then au.flare:SetPoint("CENTER", host, "TOPLEFT", px, -py) end
	end
	if hs ~= au.lhs then
		au.lhs = hs
		halo:SetSize(hs, hs)
	end
	if ha ~= au.lha then
		au.lha = ha
		halo:SetAlpha(ha)
	end
	local fl = nil -- playtest 5: no rotating flare
	if fl ~= nil and kind == 2 then
		local fs = floor(gs * 2.2 + 0.5)
		if fs ~= au.lfs then
			au.lfs = fs
			fl:SetSize(fs, fs)
		end
		local fa = q20(a * 0.5)
		if fa ~= au.lfa then
			au.lfa = fa
			fl:SetAlpha(fa)
		end
		if BoardView.can_rotate then
			local r = floor((now * 0.6 + ph) * 10 + 0.5) / 10
			if r ~= au.lfr then
				au.lfr = r
				if not pcall(fl.SetRotation, fl, r % TWO_PI) then BoardView.can_rotate = false end
			end
		end
	end
	local n = au.ndots
	if n > 0 then
		local dots = au.dots
		local radius = gs * 0.52
		local speed = kind == 2 and -0.3 or 0.5 -- turns per second
		local dsz = au.soft and 16 or 6
		local da = q20(a)
		for k = 1, n do
			local ang = TWO_PI * (now * speed + (k - 1) / n) + ph
			ang = floor(ang / (TWO_PI / 24) + 0.5) * (TWO_PI / 24)
			local dx, dy = px + floor(cos(ang) * radius + 0.5), py + floor(sin(ang) * radius + 0.5)
			if dx ~= au.dx[k] or dy ~= au.dy[k] then
				au.dx[k], au.dy[k] = dx, dy
				dots[k]:SetPoint("CENTER", host, "TOPLEFT", dx, -dy)
			end
		end
		if au.ldsz ~= dsz then
			au.ldsz = dsz
			for k = 1, n do dots[k]:SetSize(dsz, dsz) end
		end
		if da ~= au.lda then
			au.lda = da
			for k = 1, n do dots[k]:SetAlpha(da) end
		end
	end
	if not au.shown then
		au.shown = true
		halo:Show()
		if fl ~= nil and kind == 2 then fl:Show() end
		for k = 1, n do au.dots[k]:Show() end
	end
end

-- Swap hints for the selected gem: rings on the settled neighbours that swapping would activate (selected is
-- a skill / ult gem and the neighbour has its colour, or the neighbour is a skill / ult gem of the selected
-- gem's colour); the text only when the selected gem itself is a skill / ult. Reads the board, never writes.
function BoardView:_update_swap_hints(selected)
	local rings = self.rings
	local used, kind = 0, nil
	local sim = self.sim
	if selected ~= nil and sim ~= nil and not selected.removed and self.frame_of[selected] ~= nil then
		local board = sim.board
		local Board = ns.Board
		local sel_ab = selected.tier > 0 and not selected.bomb
		if sel_ab then kind = selected.tier == 2 and 2 or 1 end
		local cell = BoardView.CELL
		for i = 1, 4 do
			local nc, nr = selected.col + HINT_DC[i], selected.row + HINT_DR[i]
			local nb = board:in_bounds(nc, nr) and board:get(nc, nr) or nil
			if nb ~= nil and not nb.removed and nb.state == Board.SETTLED and nb.type == selected.type
				and (sel_ab or (nb.tier > 0 and not nb.bomb)) then
				used = used + 1
				local r = rings[used]
				if r.lc ~= nc or r.lr ~= nr then
					r.lc, r.lr = nc, nr
					r:ClearAllPoints()
					r:SetPoint("CENTER", self.host, "TOPLEFT", (nc + 0.5) * cell, -(nr + 0.5) * cell)
				end
				if not r.on then
					r.on = true
					r:Show()
				end
			end
		end
	end
	for i = used + 1, #rings do
		local r = rings[i]
		if r.on then
			r.on = false
			r.lc, r.lr = nil, nil
			r:Hide()
		end
	end
	self.hint_n = used
	if kind ~= self.hint_kind then
		self.hint_kind = kind
		if kind == nil then
			self.hint_text:Hide()
		else
			self.hint_text:SetText(kind == 2 and BoardView.HINT_ULT or BoardView.HINT_SKILL)
			self.hint_text:Show()
		end
	end
end

-- Cell under a board-local point (px from the top-left), or nil.
function BoardView:cell_at(lx, ly_top)
	local cell = BoardView.CELL
	if lx < 0 or ly_top < 0 then return nil end
	local c, r = floor(lx / cell), floor(ly_top / cell)
	if c >= self.cols or r >= self.rows then return nil end
	return c, r
end

ns.BoardView = BoardView
