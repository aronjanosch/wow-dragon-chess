local addonName, ns = ...
-- HitFx (W0-P8): hit / status readability. Purely cosmetic; no game rule, no sim writes, no core RNG. Everything is
-- derived from combat:hud_state (read once per frame by ui/fight_view.lua, passed to update) and from the events the
-- view forwards (windup, blocked, reflected, heal, death, enter, phase, score).
--
--   chip bars      a dim layer behind the HP fill holds the old value CHIP_HOLD s after a drop, then slides down in
--                  CHIP_SLIDE s (player + enemy); heals flash the player bar green
--   low HP         <= LOW_PCT of the player's HP: a red glow around the bar + a heartbeat on the edge vignette
--                  (faster below CRIT_PCT); off when stunned / dead / halted
--   status icons   pop in (1.5 -> 1), a ring (Juice ring at the icon), blink in the last seconds, shatter when they
--                  expire (Juice burst), shield stacks pop on a block, the strip slides to its new layout instead of
--                  snapping; every icon has a class-coloured 2 px edge (Assets.STATUS_EDGE)
--   player aura    a pulsing halo around the HP bar in the colour of the highest-priority buff / debuff
--   telegraph      while the enemy winds up an attack: a growing tinted glow on the figure and a faint edge vignette in
--                  the intent colour over the last 40 % of the windup
--   figure         enemy entrance (slide + fade + ring), death (motes, white flash, upward drift)
--   score          plaque punch + gold glint; phase change: impact ring + trauma + name punch
--   damage numbers pop scale, crit shake, stacked offsets, slower heal numbers (FontString:SetScale is unverified: a
--                  pcall probe in new() decides; without it the pop uses the big font for the first 0.12 s)
--
-- Pools / frames, all created once in new() (nothing is created while playing): 2 chip textures, 1 heal flash, 3 halo
-- textures on the bottom strip, 1 vignette frame (8 edges), the figure's glow / flash textures, the plaque glint. Soft
-- textures come from Assets.soft(tex, "glow"); without them a round-masked disc (colour) is used.
--
-- Time: sim time only (update(now) from the HUD); halt() hides and resets everything (FightView:halt: pause, hide,
-- menu, game over, reset, new fight, rebind). A failing build leaves HitFx.NONE (the window still works).
-- Not verified live: FontString:SetScale (pcall probe), the look of the halos.

local floor, abs, sin, pi, min, max = math.floor, math.abs, math.sin, math.pi, math.min, math.max
local pcall, type = pcall, type

local HitFx = {}
HitFx.__index = HitFx

-- Tuning (px / sim seconds / alpha). Everything worth changing while playtesting is here.
HitFx.CHIP_HOLD, HitFx.CHIP_SLIDE = 0.35, 0.25
HitFx.HEAL_DUR, HitFx.HEAL_PEAK = 0.25, 0.45
HitFx.LOW_PCT, HitFx.CRIT_PCT = 0.25, 0.10 -- HP fractions
HitFx.LOW_HZ, HitFx.CRIT_HZ = 1.2, 2.2
HitFx.HEART_MIN, HitFx.HEART_MAX = 0.08, 0.2 -- edge vignette alpha of the heartbeat
HitFx.LOW_GLOW_MIN, HitFx.LOW_GLOW_MAX = 0.15, 0.5
HitFx.POP_PEAK, HitFx.POP_TIME = 1.5, 0.18 -- status icon appears
HitFx.REFRESH_POP = 1.25 -- a status was re-applied (remaining jumped up) / a shield stack was eaten
HitFx.PUNCH_PEAK = 1.4 -- block / reflect icon punch
HitFx.WARN_ABS, HitFx.WARN_FRAC = 2, 0.25 -- blink when remaining <= max(2 s, 25 % of max)
HitFx.BLINK_HZ, HitFx.BLINK_LOW = 4, 0.55
HitFx.EXPIRE_EPS = 0.35 -- an icon that vanishes with <= this remaining expired (shatter) instead of being cleared
HitFx.SLIDE_TIME = 0.12
HitFx.SHARDS, HitFx.SHARDS_SHIELD = 5, 3
HitFx.RING_FROM, HitFx.RING_TO, HitFx.RING_DUR = 10, 46, 0.28
HitFx.AURA_MIN, HitFx.AURA_MAX = 0.12, 0.38 -- halo alpha range (reduce first when the strip gets noisy)
HitFx.AURA_HZ, HitFx.AURA_HZ_SLOW = 1.0, 0.5 -- curse pulses slowly
HitFx.NUM_PEAK, HitFx.NUM_PEAK_CRIT, HitFx.NUM_POP = 1.6, 1.9, 0.12 -- damage number pop scale / time
HitFx.NUM_SHAKE_TIME = 0.15
HitFx.NUM_LIFE, HitFx.NUM_RISE = 0.9, 46 -- = fight_view POP_TIME / POP_RISE
HitFx.NUM_STACK_GAP, HitFx.NUM_STACK_DY, HitFx.NUM_STACK_MAX = 0.12, 14, 2 -- extra numbers within 0.12 s: +14 px each, max 3 stacked
HitFx.HEAL_RISE = 0.6 -- heal numbers rise at this fraction of the normal speed
HitFx.TELE_GLOW, HitFx.TELE_VIG, HitFx.TELE_VIG_FROM = 0.5, 0.2, 0.6
HitFx.ENTER_TIME, HitFx.ENTER_DX = 0.35, 24
HitFx.ENTER_RING_TIME, HitFx.ENTER_RING_FROM, HitFx.ENTER_RING_TO = 0.45, 20, 160
HitFx.DEATH_MOTES, HitFx.DEATH_MOTES_BOSS = 14, 20
HitFx.DEATH_FLASH, HitFx.DEATH_FLASH_PEAK, HitFx.DEATH_DRIFT = 0.15, 0.6, 6
HitFx.SCORE_TIME, HitFx.SCORE_MIN, HitFx.SCORE_CAP, HitFx.SCORE_REF = 0.2, 1.08, 1.18, 200
HitFx.GLINT_TIME, HitFx.GLINT_PEAK = 0.3, 0.6
HitFx.NAME_PEAK, HitFx.NAME_TIME = 1.35, 0.25
HitFx.PHASE_TRAUMA = 0.3

local A -- ns.Assets (resolved in new)

---------------------------------------------------------------- pure helpers

local function qn(a, n)
	if a <= 0 then return 0 end
	if a >= 1 then return 1 end
	return floor(a * n + 0.5) / n
end

-- Remaining time at which an icon starts to blink.
function HitFx.warn_threshold(maxv)
	local frac = (maxv or 0) * HitFx.WARN_FRAC
	return frac > HitFx.WARN_ABS and frac or HitFx.WARN_ABS
end

-- Chip value `t` s after a drop from `from` to `target`: holds, then slides (ease out), then rests.
function HitFx.chip_value(from, target, t)
	local hold, slide = HitFx.CHIP_HOLD, HitFx.CHIP_SLIDE
	if t < hold then return from end
	if t >= hold + slide then return target end
	local k = (t - hold) / slide
	return from + (target - from) * (1 - (1 - k) * (1 - k))
end

-- Telegraph glow envelope (monotone in k = elapsed / windup).
function HitFx.telegraph_env(k)
	if k <= 0 then return 0 end
	if k >= 1 then k = 1 end
	return HitFx.TELE_GLOW * k
end

-- Edge vignette of the telegraph: 0 until TELE_VIG_FROM, then a ramp up to TELE_VIG (monotone).
function HitFx.telegraph_vig(k)
	local from = HitFx.TELE_VIG_FROM
	if k <= from then return 0 end
	if k >= 1 then k = 1 end
	return HitFx.TELE_VIG * (k - from) / (1 - from)
end

-- Plaque punch peak by the awarded amount (capped).
function HitFx.score_peak(amount)
	local f = (amount or 0) / HitFx.SCORE_REF
	if f > 1 then f = 1 elseif f < 0 then f = 0 end
	local p = HitFx.SCORE_MIN + (HitFx.SCORE_CAP - HitFx.SCORE_MIN) * f
	return p
end

-- Highest-priority aura of a hud state (nil = none): stun > curse > fire_shield > shield > lifesteal.
function HitFx.aura_pick(st)
	local s = st.statuses
	if st.player_stunned then return "stun" end
	if s.curse.remaining > 0 then return "curse" end
	if s.fire_shield.remaining > 0 then return "fire_shield" end
	if (s.shield or 0) > 0 then return "shield" end
	if s.lifesteal.remaining > 0 then return "lifesteal" end
	return nil
end

-- Telegraph tint of an ability kind.
function HitFx.intent_tint(kind)
	local T = ns.Assets.INTENT_TINT
	return T[kind] or T.special
end

local function set_scale(r, s) r:SetScale(s) end

---------------------------------------------------------------- texture helpers

-- A soft glow (Assets.GLOW.glow) or, without it, a round-masked disc. Additive, hidden. 2nd result = soft?
local function soft_tex(parent, layer, sub)
	local tex = parent:CreateTexture(nil, layer, nil, sub)
	if A.soft(tex, "glow") then
		tex:SetBlendMode("ADD")
		tex:Hide()
		tex.hf_soft = true
		return tex
	end
	local mask = parent:CreateMaskTexture()
	mask:SetTexture(A.ROUND_MASK, A.MASK_WRAP, A.MASK_WRAP)
	mask:SetAllPoints(tex)
	tex:AddMaskTexture(mask)
	tex:SetColorTexture(1, 1, 1, 1)
	tex:SetBlendMode("ADD")
	tex:Hide()
	tex.hf_soft = false
	return tex
end

-- Tint only when the colour table changes (shared A.* tables, compared by reference).
local function tint(tex, c)
	if tex.hf_c == c then return end
	tex.hf_c = c
	if tex.hf_soft then tex:SetVertexColor(c[1], c[2], c[3]) else tex:SetColorTexture(c[1], c[2], c[3], 1) end
end

local function set_alpha(r, a)
	if r.hf_a ~= a then
		r.hf_a = a
		r:SetAlpha(a)
	end
end

local function set_shown(r, v)
	if r.hf_shown ~= v then
		r.hf_shown = v
		if v then r:Show() else r:Hide() end
	end
end

---------------------------------------------------------------- construction

local function make_chip(bar, c)
	local w = bar:GetWidth()
	if w == nil or w <= 0 then w = 100 end
	local chip = bar:CreateTexture(nil, "BACKGROUND", nil, 2)
	chip:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
	chip:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
	chip:SetWidth(1)
	chip:SetColorTexture(c[1], c[2], c[3], c[4])
	chip:Hide()
	return { bar = bar, chip = chip, w = w, lpx = -1, init = false, last = 0, target = 0, from = 0, t0 = nil, val = 0, mx = 1 }
end

local function vignette_edges(frame)
	local edges = {}
	local function edge(p1, p2, w, h, a)
		local t = frame:CreateTexture(nil, "OVERLAY")
		edges[#edges + 1] = { tex = t, a = a }
		t:SetPoint(p1, frame, p1, 0, 0)
		t:SetPoint(p2, frame, p2, 0, 0)
		if w then t:SetWidth(w) else t:SetHeight(h) end
		t:SetColorTexture(1, 1, 1, a)
	end
	for _, th in ipairs({ { 14, 1 }, { 40, 0.45 } }) do
		edge("TOPLEFT", "TOPRIGHT", nil, th[1], th[2])
		edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, th[1], th[2])
		edge("TOPLEFT", "BOTTOMLEFT", th[1], nil, th[2])
		edge("TOPRIGHT", "BOTTOMRIGHT", th[1], nil, th[2])
	end
	return edges
end

-- view: the FightView being built (its widgets exist), jc: the Juice layer (or Juice.NONE).
function HitFx.new(view, jc)
	A = ns.Assets
	local win = view.win
	local L = view.layout
	local self = setmetatable({}, HitFx)
	self.view, self.jc, self.L = view, jc, L
	self.now = 0
	self.seed = 20261006
	self.pad = win.pad or 6
	self.resync = true
	self.dev_low, self.dev_aura_until, self.dev_aura = false, nil, nil
	self.can_scale = pcall(set_scale, view.pops_enemy[1], 1)
	if not self.can_scale then self.can_scale = false end

	-- chip bars + heal flash
	self.bars = {
		player = make_chip(view.player_bar, A.COLOR.CHIP_PLAYER),
		enemy = make_chip(view.enemy_bar, A.COLOR.CHIP_ENEMY),
	}
	local hf = view.player_bar:CreateTexture(nil, "OVERLAY")
	hf:SetAllPoints(view.player_bar)
	local hc = A.COLOR.HEAL_FLASH
	hf:SetColorTexture(hc[1], hc[2], hc[3], 1)
	hf:SetBlendMode("ADD")
	hf:SetAlpha(0)
	hf:Hide()
	self.heal_tex, self.heal_t0 = hf, nil

	-- halos around the player bar (bottom strip, under the bar and the icons)
	local bottom = win.bottom
	local cx = L.player_bar_x + L.player_bar_w / 2
	local bw = L.player_bar_w
	self.aura_out = soft_tex(bottom, "BACKGROUND", 1)
	self.aura_out:SetPoint("CENTER", bottom, "LEFT", cx, 0)
	self.aura_out:SetSize(bw + 56, 50)
	self.aura_in = soft_tex(bottom, "BACKGROUND", 2)
	self.aura_in:SetPoint("CENTER", bottom, "LEFT", cx, 0)
	self.aura_in:SetSize(bw + 20, 32)
	self.low_glow = soft_tex(bottom, "BACKGROUND", 3)
	self.low_glow:SetPoint("CENTER", bottom, "LEFT", cx, 0)
	self.low_glow:SetSize(bw + 36, 44)
	self.aura_id = nil

	-- edge vignette (telegraph colour / low-HP heartbeat), above the view's own flash vignette
	local vig = CreateFrame("Frame", nil, win.content)
	vig:SetAllPoints(win.content)
	if view.vignette ~= nil then vig:SetFrameLevel(view.vignette:GetFrameLevel()) end
	self.vig = vig
	self.vig_edges = vignette_edges(vig)
	vig:SetAlpha(0)
	self.vig_c = nil
	self.heart_a, self.tele_a = 0, 0

	-- the figure: telegraph glow, death flash
	local gf = view.glow_frame
	local ew = L.enemy_w
	self.tele_glow = soft_tex(gf, "OVERLAY", 4)
	self.tele_glow:SetPoint("CENTER", view.enemy_holder, "CENTER", 0, 0)
	self.tele_glow:SetSize(ew * 0.95, ew * 0.95)
	self.death_flash = soft_tex(gf, "OVERLAY", 5)
	self.death_flash:SetPoint("CENTER", view.enemy_holder, "CENTER", 0, 0)
	self.death_flash:SetSize(ew * 1.1, ew * 1.1)
	tint(self.death_flash, A.COLOR.DEATH_FLASH)
	-- soft ring at the feet on entrance (own texture: Juice's ring pool is not touched by a fight start)
	local rg = gf:CreateTexture(nil, "OVERLAY", nil, 3)
	if A.soft(rg, "ring") then
		rg:SetBlendMode("ADD")
		rg.hf_soft = true
	else
		local mask = gf:CreateMaskTexture()
		mask:SetTexture(A.ROUND_MASK, A.MASK_WRAP, A.MASK_WRAP)
		mask:SetAllPoints(rg)
		rg:AddMaskTexture(mask)
		rg:SetColorTexture(1, 1, 1, 1)
		rg:SetBlendMode("ADD")
		rg.hf_soft = false
	end
	rg:Hide()
	rg:SetPoint("CENTER", view.enemy_holder, "CENTER", 0, -(L.panel_h or 524) * 0.3)
	tint(rg, A.COLOR.DEATH_GOLD)
	self.enter_ring = rg
	self.tele_t0, self.tele_dur, self.tele_c, self.tele_dev = nil, 0, nil, false
	self.enter_t0, self.death_t0 = nil, nil

	-- plaque glint
	self.glint = soft_tex(view.plaque, "OVERLAY", 4)
	self.glint:SetPoint("CENTER", view.plaque, "CENTER", 0, 0)
	self.glint:SetSize(150, 70)
	tint(self.glint, A.COLOR.SCORE_GLINT)
	self.plaque = { f = view.plaque, home = view.plaque.home, s = 1 }
	self.score_t0, self.score_peak, self.glint_t0 = nil, 1, nil

	-- the enemy's name text (punch)
	self.name = { f = view.name_text, home = view.name_text.home, s = 1 }
	self.name_t0 = nil

	-- status icons
	self.icons, self.icon_by_id = {}, {}
	local jx = jc.ex
	local function add_icon(f, id, strip, bx, by)
		if f == nil then return end
		local rec = { f = f, id = id, strip = strip, bx = bx, by = by, home = f.home, on = false, lrem = -1, lstacks = 0,
			s = 1, ls = 1, la = 1, pop_t0 = nil, pop_peak = 1, sl_t0 = nil, sl_from = 0,
			cx = strip and f.home[4] or nil, tx = strip and f.home[4] or nil, lx = nil, edge = A.STATUS_EDGE[id] }
		f.fxrec = rec
		local e = rec.edge
		if f.edge ~= nil and e ~= nil then f.edge:SetColorTexture(e[1], e[2], e[3], e[4]) end
		self.icons[#self.icons + 1] = rec
		self.icon_by_id[id] = rec
	end
	local py = jc.py
	for i = 1, #L.player_status do
		local id = L.player_status[i]
		local f = view.status[id]
		add_icon(f, id, true, f.home[4] - self.pad, py)
	end
	local ex, ey = jx, jc.ey
	local pw, ph = L.panel_w, L.panel_h
	local ix, iy, ey2 = nil, nil, nil
	if ex ~= nil and ey ~= nil and pw ~= nil and ph ~= nil then
		local q = L.queue
		local qy = ey - ph / 2 + q.y + q.h - 10 - L.slot_size / 2 -- queue bottom (y grows down), minus the slot margin
		local qx = ex - pw / 2 + q.x
		add_icon(view.enemy_stun, "enemy_stun", false, qx + 6 + L.slot_size / 2, qy)
		add_icon(view.enemy_slow, "enemy_slow", false, qx + q.w - 6 - L.slot_size / 2, qy)
		ix, iy = ex + L.enemy_x, ey + ph / 2 - 46 - L.enemy_icon / 2
		add_icon(view.aegis_icon, "enemy_aegis", false, ix - 28, iy)
		add_icon(view.mirror_icon, "enemy_mirror", false, ix + 28, iy)
	else
		add_icon(view.enemy_stun, "enemy_stun", false, nil, nil)
		add_icon(view.enemy_slow, "enemy_slow", false, nil, nil)
		add_icon(view.aegis_icon, "enemy_aegis", false, nil, nil)
		add_icon(view.mirror_icon, "enemy_mirror", false, nil, nil)
	end
	return self
end

-- A stand-in for a build that failed (no effects; the view falls back to its plain code paths).
local function noop() end
HitFx.NONE = setmetatable({
	update = noop, halt = noop, windup = noop, blocked = noop, reflected = noop, heal = noop, death = noop, enter = noop,
	phase = noop, score = noop, pop_start = noop, dev = function() return false end,
	figure = function() return 0, 0, 1 end,
	bars = {}, icons = {}, icon_by_id = {},
}, nil) -- no metatable: the view tests `hf.layout` / `hf.pop_frame` for nil to pick its plain code path

---------------------------------------------------------------- icons

-- Places an icon at its home anchor, scaled around its centre.
local function place(rec)
	local h = rec.home
	local x = rec.strip and rec.cx or h[4]
	local rx = floor(x + 0.5)
	local s = rec.s
	if s ~= rec.ls then
		rec.ls = s
		rec.f:SetScale(s)
	end
	rec.lx = rx
	rec.f:SetPoint(h[1], h[2], h[3], rx / s, h[5] / s)
end

-- The view's layout of the player strip: icon `f` wants its left edge at x_left. Slides there (snaps for an icon that
-- is not on yet).
function HitFx:layout(f, x_left, now)
	local rec = f.fxrec
	if rec == nil then
		f:SetPoint("CENTER", self.view.win.bottom, "LEFT", x_left + self.L.status_size / 2, 0)
		return
	end
	local tx = x_left + self.L.status_size / 2
	if rec.tx == tx and rec.cx == tx then return end
	rec.tx = tx
	if rec.on and rec.cx ~= nil and rec.cx ~= tx then
		rec.sl_from, rec.sl_t0 = rec.cx, now
	else
		rec.cx, rec.sl_t0 = tx, nil
		place(rec)
	end
end

-- Scale pop of an icon (the larger peak wins at the same instant).
local function pop(rec, peak, now)
	if rec.pop_t0 == now and rec.pop_peak >= peak then return end
	rec.pop_t0, rec.pop_peak = now, peak
end

local function shatter(self, rec, n)
	local jc = self.jc
	if rec.bx == nil or jc.host == nil then return end
	local c = rec.edge or A.STATUS_EDGE.shield
	jc:burst(rec.bx, rec.by, n, 60, c[1], c[2], c[3], 0, 4)
end

local function ring_at(self, rec)
	local jc = self.jc
	if rec.bx == nil or jc.host == nil then return end
	local c = rec.edge or A.STATUS_EDGE.shield
	jc:ring(rec.bx, rec.by, HitFx.RING_FROM, HitFx.RING_TO, HitFx.RING_DUR, c, 0.8)
end

-- on, remaining (-1 = not timed), max, stacks of a status id in a hud state.
local function read_status(id, st, ended)
	local s = st.statuses
	if id == "shield" then
		local n = s.shield or 0
		return n > 0, -1, 0, n
	elseif id == "sandstorm" then
		local r = st.sand_remaining
		return r > 0, r, st.sand_max, 0
	elseif id == "enemy_aegis" then
		local r = (ended or not st.has_enemy) and 0 or st.enemy_aegis_remaining
		return r > 0, r, st.enemy_aegis_max, 0
	elseif id == "enemy_mirror" then
		local r = (ended or not st.has_enemy) and 0 or st.enemy_mirror_remaining
		return r > 0, r, st.enemy_mirror_max, 0
	elseif id == "enemy_stun" then
		local r = st.has_enemy and st.enemy_stun_kind ~= "" and st.enemy_stun_remaining or 0
		return r > 0, r, st.enemy_stun_max, 0
	elseif id == "enemy_slow" then
		local r = st.has_enemy and st.enemy_slow_remaining or 0
		return r > 0, r, st.enemy_slow_max, 0
	end
	local e = s[id]
	if e == nil then return false, 0, 0, 0 end
	return e.remaining > 0, e.remaining, e.max, 0
end

function HitFx:_icons(st, now)
	local ended = st.fight_over or st.game_over
	local resync = self.resync
	self.resync = false
	local icons = self.icons
	for i = 1, #icons do
		local rec = icons[i]
		local on, rem, mx, stacks = read_status(rec.id, st, ended)
		if resync then
			rec.on = on
			if on and rec.tx ~= nil then rec.cx = rec.tx end
		elseif on and not rec.on then
			rec.on = true
			rec.sl_t0 = nil
			if rec.tx ~= nil then rec.cx = rec.tx end
			pop(rec, HitFx.POP_PEAK, now)
			ring_at(self, rec)
		elseif not on and rec.on then
			rec.on = false
			if rec.id == "shield" then
				shatter(self, rec, HitFx.SHARDS_SHIELD)
			elseif rec.lrem >= 0 and rec.lrem <= HitFx.EXPIRE_EPS then
				shatter(self, rec, HitFx.SHARDS)
			end
			rec.pop_t0, rec.sl_t0, rec.s = nil, nil, 1
			if rec.la ~= 1 then
				rec.la = 1
				rec.f:SetAlpha(1)
			end
			if rec.ls ~= 1 then place(rec) end
		elseif on then
			if rec.id == "shield" then
				if stacks < rec.lstacks then pop(rec, HitFx.REFRESH_POP, now) end
			elseif rem > rec.lrem + 0.25 and rec.lrem >= 0 then
				pop(rec, HitFx.REFRESH_POP, now) -- re-applied
			end
		end
		rec.lrem, rec.lstacks = rem, stacks
		if on then
			-- blink in the last seconds (timed statuses only)
			local a = 1
			if rem >= 0 and rem <= HitFx.warn_threshold(mx) and floor(now * HitFx.BLINK_HZ * 2) % 2 == 1 then a = HitFx.BLINK_LOW end
			if a ~= rec.la then
				rec.la = a
				rec.f:SetAlpha(a)
			end
			-- pop scale
			local s = 1
			if rec.pop_t0 ~= nil then
				local k = (now - rec.pop_t0) / HitFx.POP_TIME
				if k >= 1 or k < 0 then
					rec.pop_t0 = nil
				else
					s = floor((1 + (rec.pop_peak - 1) * (1 - k) * (1 - k)) * 50 + 0.5) / 50
				end
			end
			-- slide to the new layout slot
			local moved = false
			if rec.sl_t0 ~= nil then
				local k = (now - rec.sl_t0) / HitFx.SLIDE_TIME
				if k >= 1 or k < 0 then
					rec.sl_t0 = nil
					rec.cx = rec.tx
				else
					rec.cx = rec.sl_from + (rec.tx - rec.sl_from) * (1 - (1 - k) * (1 - k))
				end
				moved = floor(rec.cx + 0.5) ~= rec.lx
			end
			if s ~= rec.s then
				rec.s = s
				moved = true
			end
			if moved then place(rec) end
			if rec.strip and rec.bx ~= nil then rec.bx = rec.cx - self.pad end
		end
	end
end

-- Punch on a status icon (block / reflect).
function HitFx:punch_icon(id, peak, now)
	local rec = self.icon_by_id[id]
	if rec ~= nil then pop(rec, peak, now) end
end

---------------------------------------------------------------- chip bars + low HP

local function chip_cur(c, now)
	if c.t0 == nil then return c.target end
	local t = now - c.t0
	if t < 0 then
		c.t0 = nil
		return c.target
	end
	if t >= HitFx.CHIP_HOLD + HitFx.CHIP_SLIDE then
		c.t0 = nil
		return c.target
	end
	return HitFx.chip_value(c.from, c.target, t)
end

local function chip_step(c, hp, mx, now)
	if mx <= 0 then mx = 1 end
	if hp < 0 then hp = 0 end
	c.mx = mx
	if not c.init then
		c.init, c.last, c.target, c.t0 = true, hp, hp, nil
	elseif hp < c.last then
		local cur = chip_cur(c, now)
		c.from = cur > c.last and cur or c.last
		c.target, c.t0 = hp, now
	elseif hp > c.last then
		local cur = chip_cur(c, now)
		if c.t0 == nil or cur <= hp then c.t0 = nil end
		c.target = hp
	end
	c.last = hp
	local v = chip_cur(c, now)
	c.val = v
	local px = floor(v / mx * c.w + 0.5)
	if px > c.w then px = c.w elseif px < 0 then px = 0 end
	if px ~= c.lpx then
		c.lpx = px
		if px <= 0 then
			c.chip:Hide()
		else
			c.chip:SetWidth(px)
			c.chip:Show()
		end
	end
end

function HitFx:_bars(st, now)
	chip_step(self.bars.player, st.player_health, st.player_max_health, now)
	if st.has_enemy then
		local hp = st.enemy_health
		chip_step(self.bars.enemy, hp > 0 and hp or 0, st.enemy_max_health, now)
	end
	-- heal flash
	local a = 0
	if self.heal_t0 ~= nil then
		local k = (now - self.heal_t0) / HitFx.HEAL_DUR
		if k >= 1 or k < 0 then self.heal_t0 = nil else a = qn(HitFx.HEAL_PEAK * (1 - k), 40) end
	end
	set_alpha(self.heal_tex, a)
	set_shown(self.heal_tex, a > 0)
end

-- Low HP: red glow around the bar + the heartbeat value of the edge vignette (self.heart_a, applied in _vig).
function HitFx:_low(st, now)
	local hp, mx = st.player_health, st.player_max_health
	local frac = mx > 0 and hp / mx or 1
	local over = st.game_over or st.fight_over
	local low
	if self.dev_low then
		low = not over
		if frac > HitFx.LOW_PCT then frac = HitFx.LOW_PCT end
	else
		low = hp > 0 and frac <= HitFx.LOW_PCT and not over and not st.player_stunned
	end
	local glow, heart = 0, 0
	if low then
		local hz = frac <= HitFx.CRIT_PCT and HitFx.CRIT_HZ or HitFx.LOW_HZ
		local p = 0.5 + 0.5 * sin(2 * pi * hz * now)
		glow = qn(HitFx.LOW_GLOW_MIN + (HitFx.LOW_GLOW_MAX - HitFx.LOW_GLOW_MIN) * p, 50)
		heart = qn(HitFx.HEART_MIN + (HitFx.HEART_MAX - HitFx.HEART_MIN) * p, 100)
		tint(self.low_glow, A.COLOR.LOW_HP)
	end
	set_alpha(self.low_glow, glow)
	set_shown(self.low_glow, glow > 0)
	self.heart_a = heart
end

---------------------------------------------------------------- aura

function HitFx:_aura(st, now)
	local id = HitFx.aura_pick(st)
	if self.dev_aura_until ~= nil then
		if now < self.dev_aura_until then id = self.dev_aura else self.dev_aura_until, self.dev_aura = nil, nil end
	end
	if id == nil or st.game_over then
		set_shown(self.aura_out, false)
		set_shown(self.aura_in, false)
		self.aura_id = nil
		return
	end
	local c = A.STATUS_AURA[id]
	if id ~= self.aura_id then
		self.aura_id = id
		tint(self.aura_out, c)
		tint(self.aura_in, c)
	end
	local hz = id == "curse" and HitFx.AURA_HZ_SLOW or HitFx.AURA_HZ
	local p = 0.5 + 0.5 * sin(2 * pi * hz * now)
	local a = qn(HitFx.AURA_MIN + (HitFx.AURA_MAX - HitFx.AURA_MIN) * p, 50)
	set_alpha(self.aura_out, a)
	set_alpha(self.aura_in, qn(a * 0.8, 50))
	set_shown(self.aura_out, true)
	set_shown(self.aura_in, true)
end

---------------------------------------------------------------- telegraph + vignette

-- The enemy starts winding up `ability` for `windup` s (view: enemy_windup).
function HitFx:windup(ability, windup, now)
	if windup == nil or windup <= 0.05 then
		self.tele_t0 = nil
		return
	end
	self.tele_t0, self.tele_dur, self.tele_dev = now, windup, false
	self.tele_c = HitFx.intent_tint(ability ~= nil and ability.kind or nil)
end

function HitFx:_tele(st, now)
	local t0 = self.tele_t0
	local glow, vig = 0, 0
	if t0 ~= nil then
		local k = (now - t0) / self.tele_dur
		local ended = k < 0
		if not self.tele_dev then
			if not st.has_enemy or not st.enemy_winding_up or st.enemy_stun_kind ~= "" or st.fight_over or st.game_over then
				ended = true
			end
		elseif k >= 1 then
			ended = true
		end
		if ended then
			self.tele_t0 = nil
		else
			if k > 1 then k = 1 end
			local pulse = 1 + 0.15 * sin(2 * pi * (3 + 7 * k) * now)
			glow = qn(HitFx.telegraph_env(k) * pulse, 50)
			local v = HitFx.telegraph_vig(k)
			if v > 0 then vig = qn(v * (0.85 + 0.15 * sin(2 * pi * (3 + 7 * k) * now)), 100) end
			tint(self.tele_glow, self.tele_c)
		end
	end
	set_alpha(self.tele_glow, glow)
	set_shown(self.tele_glow, glow > 0)
	self.tele_a = vig
end

-- One vignette frame: the telegraph (intent colour) wins over the low-HP heartbeat (red).
function HitFx:_vig()
	local a, c = 0, nil
	if self.tele_a > 0 then
		a, c = self.tele_a, self.tele_c
	elseif self.heart_a > 0 then
		a, c = self.heart_a, A.COLOR.LOW_HP
	end
	if c ~= nil and c ~= self.vig_c then
		self.vig_c = c
		local edges = self.vig_edges
		for i = 1, #edges do edges[i].tex:SetColorTexture(c[1], c[2], c[3], edges[i].a) end
	end
	set_alpha(self.vig, a)
end

---------------------------------------------------------------- figure (entrance / death), score, name

local function rand(self)
	local s = (self.seed * 16807) % 2147483647
	self.seed = s
	return s / 2147483647
end

function HitFx:_scale_rec(rec, s)
	if s == rec.s then return end
	rec.s = s
	pcall(set_scale, rec.f, s)
	local h = rec.home
	rec.f:SetPoint(h[1], h[2], h[3], h[4] / s, h[5] / s)
end

-- New fight: the figure slides in from the right while fading in, a soft ring at the feet, the name punches.
function HitFx:enter(now)
	self.enter_t0, self.ring_t0 = now, now
	self.name_t0 = now
end

-- Offset (dx, dy px) and alpha multiplier of the enemy figure. `death_a` = the view's death-fade alpha (1 = alive).
function HitFx:figure(now, death_a)
	local dx, ea = 0, 1
	if self.enter_t0 ~= nil then
		local k = (now - self.enter_t0) / HitFx.ENTER_TIME
		if k >= 1 or k < 0 then
			self.enter_t0 = nil
		else
			dx = floor(HitFx.ENTER_DX * (1 - k) * (1 - k) + 0.5)
			ea = qn(k, 20)
		end
	end
	-- ring at the feet: grows 20 -> 160 px while fading (the figure's own timer)
	local rg = self.enter_ring
	if self.ring_t0 ~= nil then
		local k = (now - self.ring_t0) / HitFx.ENTER_RING_TIME
		if k < 1 and k >= 0 then
			local sz = floor(HitFx.ENTER_RING_FROM + (HitFx.ENTER_RING_TO - HitFx.ENTER_RING_FROM) * k + 0.5)
			if sz ~= rg.hf_sz then
				rg.hf_sz = sz
				rg:SetSize(sz, sz)
			end
			set_alpha(rg, qn(0.7 * (1 - k), 20))
			set_shown(rg, true)
		else
			self.ring_t0 = nil
			set_shown(rg, false)
		end
	else
		set_shown(rg, false)
	end
	local dy = 0
	if death_a < 1 then dy = floor(HitFx.DEATH_DRIFT * (1 - death_a) + 0.5) end
	return dx, dy, ea
end

-- The enemy was defeated (view: enemy_defeated): rising motes, a white flash, a ring; bosses get more of each.
function HitFx:death(boss, now)
	self.death_t0 = now
	self.enter_t0 = nil -- a figure killed during its entrance fades out from full alpha
	local jc = self.jc
	if jc.host == nil or jc.ex == nil then return end
	local n = boss and HitFx.DEATH_MOTES_BOSS or HitFx.DEATH_MOTES
	local gold, hit = A.COLOR.DEATH_GOLD, A.COLOR.HIT_TINT
	for i = 1, n do
		local c = i % 2 == 0 and gold or hit
		local spread = boss and 150 or 100
		jc:particle(jc.ex + (rand(self) - 0.5) * spread, jc.ey + (rand(self) - 0.2) * 70,
			(rand(self) - 0.5) * 36, -(50 + 70 * rand(self)), -25, 10 + 6 * rand(self), 2, 0.8 + 0.5 * rand(self),
			c[1], c[2], c[3], 1, 0.05 + 0.02 * i, i % 3 == 0 and "flare" or "glow")
	end
	if boss then
		jc:ring(jc.ex, jc.ey, 50, 420, 0.55, gold, 0.9)
	else
		jc:ring(jc.ex, jc.ey, 30, 170, 0.4, gold, 0.8)
	end
end

-- Phase change: impact ring on the enemy (weight 2), trauma, the cast-tint flash, the name punch.
function HitFx:phase(now)
	local jc, view = self.jc, self.view
	if jc.host ~= nil and jc.ex ~= nil then
		local c = A.COLOR.CAST_TINT
		jc:impact(jc.ex, jc.ey, 2, c[1], c[2], c[3])
	end
	jc:add_trauma(HitFx.PHASE_TRAUMA)
	view.cast_t0 = now
	self.name_t0 = now
end

-- score_awarded(amount): plaque punch + gold glint.
function HitFx:score(amount, now)
	self.score_t0, self.score_peak = now, HitFx.score_peak(amount)
	self.glint_t0 = now
end

function HitFx:_timers(now)
	-- death flash
	local a = 0
	if self.death_t0 ~= nil then
		local k = (now - self.death_t0) / HitFx.DEATH_FLASH
		if k >= 1 or k < 0 then self.death_t0 = nil else a = qn(HitFx.DEATH_FLASH_PEAK * (1 - k), 40) end
	end
	set_alpha(self.death_flash, a)
	set_shown(self.death_flash, a > 0)
	-- plaque punch + glint
	local s = 1
	if self.score_t0 ~= nil then
		local k = (now - self.score_t0) / HitFx.SCORE_TIME
		if k >= 1 or k < 0 then
			self.score_t0 = nil
		else
			s = floor((1 + (self.score_peak - 1) * sin(pi * k)) * 100 + 0.5) / 100
		end
	end
	if self.plaque.home ~= nil then self:_scale_rec(self.plaque, s) end
	a = 0
	if self.glint_t0 ~= nil then
		local k = (now - self.glint_t0) / HitFx.GLINT_TIME
		if k >= 1 or k < 0 then self.glint_t0 = nil else a = qn(HitFx.GLINT_PEAK * (1 - k), 40) end
	end
	set_alpha(self.glint, a)
	set_shown(self.glint, a > 0)
	-- name punch (needs FontString:SetScale)
	if self.can_scale and self.name.home ~= nil then
		s = 1
		if self.name_t0 ~= nil then
			local k = (now - self.name_t0) / HitFx.NAME_TIME
			if k >= 1 or k < 0 then
				self.name_t0 = nil
			else
				s = floor((1 + (HitFx.NAME_PEAK - 1) * (1 - k) * (1 - k)) * 50 + 0.5) / 50
			end
		end
		self:_scale_rec(self.name, s)
	end
end

---------------------------------------------------------------- block / reflect / heal

function HitFx:blocked(now)
	local jc, view = self.jc, self.view
	if jc.host ~= nil and jc.px ~= nil then jc:ring(jc.px, jc.py, 20, 90, 0.3, A.COLOR.RING_BLOCK, 0.9) end
	view:_flash_vignette(A.COLOR.VIG_BLOCK, 0.35, 0.27)
	self:punch_icon("shield", HitFx.PUNCH_PEAK, now)
end

function HitFx:reflected(now)
	self:punch_icon("fire_shield", HitFx.PUNCH_PEAK, now)
end

function HitFx:heal(now)
	self.heal_t0 = now
	local jc = self.jc
	if jc.host ~= nil and jc.px ~= nil then jc:ring(jc.px, jc.py, 20, 90, 0.3, A.COLOR.RING_HEAL, 0.9) end
end

---------------------------------------------------------------- damage numbers

local SHAKE = { 1, -1, 0.7, -0.7, 0.4, -0.4 }

-- A number was just started on `fs` in `pool` (the view set text / colour / position): kind = nil / "crit" / "heal" /
-- "player", power = 0..1 (player hit size).
function HitFx:pop_start(pool, fs, kind, power, base_big, now)
	if pool.plain then return end -- match / spawn floats on the board keep the old look
	local last = pool.hf_last
	local stack = 0
	if last ~= nil and now - last <= HitFx.NUM_STACK_GAP and now >= last then
		stack = (pool.hf_stack or 0) + 1
		if stack > HitFx.NUM_STACK_MAX then stack = HitFx.NUM_STACK_MAX end
	end
	pool.hf_last, pool.hf_stack = now, stack
	fs.y0 = fs.y0 + stack * HitFx.NUM_STACK_DY
	fs.stack = stack
	fs.peak = kind == "crit" and HitFx.NUM_PEAK_CRIT or (kind == "heal" and 1 or HitFx.NUM_PEAK)
	fs.shake = nil
	if kind == "crit" then
		fs.shake = 3
	elseif kind == "player" then
		fs.shake = 1 + 2 * min(1, max(0, power or 0))
	end
	fs.rise = kind == "heal" and (HitFx.NUM_RISE * HitFx.HEAL_RISE) or HitFx.NUM_RISE
	fs.base_big = base_big
	fs.ls, fs.lx, fs.ly = nil, nil, nil
	if not self.can_scale and fs.peak > 1 and not base_big then
		fs:SetFontObject(A.FONT_POP_BIG) -- no SetScale: the big font for the pop, back to normal when it ends
		fs.fb_big = true
	else
		fs.fb_big = false
	end
	self:pop_frame(fs, pool.parent, 0)
end

-- Placement of a number `t` s after its start (called per frame while it shows). Setters only on change.
function HitFx:pop_frame(fs, parent, t)
	local rise = fs.rise or HitFx.NUM_RISE
	local y = floor(fs.y0 + rise * t / HitFx.NUM_LIFE + 0.5)
	local x = fs.x0
	local amp = fs.shake
	if amp ~= nil and t < HitFx.NUM_SHAKE_TIME then
		x = floor(x + SHAKE[floor(t / 0.03) % 6 + 1] * amp + 0.5)
	end
	local s = 1
	local peak = fs.peak or 1
	if t < HitFx.NUM_POP and peak > 1 then
		local k = t / HitFx.NUM_POP
		s = floor((1 + (peak - 1) * (1 - k) * (1 - k)) * 20 + 0.5) / 20
	elseif fs.fb_big then
		fs.fb_big = false
		fs:SetFontObject(A.FONT_POP)
	end
	if not self.can_scale then s = 1 end
	if y ~= fs.ly or x ~= fs.lx or s ~= fs.ls then
		if s ~= fs.ls and self.can_scale then
			fs.ls = s
			fs:SetScale(s)
		end
		fs.ls, fs.lx, fs.ly = s, x, y
		fs:SetPoint("CENTER", parent, "CENTER", x / s, y / s)
	end
end

---------------------------------------------------------------- per frame / halt

-- st: the reused hud state; now: sim time.
function HitFx:update(st, now)
	self.now = now
	self:_bars(st, now)
	self:_low(st, now)
	self:_icons(st, now)
	self:_aura(st, now)
	self:_tele(st, now)
	self:_vig()
	self:_timers(now)
end

-- Everything off / back to rest (FightView:halt). The next update adopts the current statuses without popping them.
function HitFx:halt()
	for _, c in pairs(self.bars) do
		c.init, c.t0, c.lpx = false, nil, -1
		c.chip:Hide()
	end
	self.heal_t0, self.tele_t0, self.enter_t0, self.death_t0, self.ring_t0 = nil, nil, nil, nil, nil
	set_shown(self.enter_ring, false)
	self.score_t0, self.glint_t0, self.name_t0 = nil, nil, nil
	self.dev_aura_until, self.dev_aura = nil, nil
	self.heart_a, self.tele_a = 0, 0
	self.aura_id = nil
	self.resync = true
	set_shown(self.heal_tex, false)
	set_alpha(self.heal_tex, 0)
	set_shown(self.aura_out, false)
	set_shown(self.aura_in, false)
	set_shown(self.low_glow, false)
	set_alpha(self.low_glow, 0)
	set_shown(self.tele_glow, false)
	set_alpha(self.tele_glow, 0)
	set_shown(self.death_flash, false)
	set_alpha(self.death_flash, 0)
	set_shown(self.glint, false)
	set_alpha(self.glint, 0)
	set_alpha(self.vig, 0)
	local icons = self.icons
	for i = 1, #icons do
		local rec = icons[i]
		rec.pop_t0, rec.sl_t0, rec.s = nil, nil, 1
		if rec.strip and rec.tx ~= nil then rec.cx = rec.tx end
		if rec.la ~= 1 then
			rec.la = 1
			rec.f:SetAlpha(1)
		end
		if rec.ls ~= 1 or (rec.strip and rec.lx ~= nil and rec.lx ~= floor(rec.cx + 0.5)) then place(rec) end
	end
	if self.plaque.home ~= nil then self:_scale_rec(self.plaque, 1) end
	if self.can_scale and self.name.home ~= nil then self:_scale_rec(self.name, 1) end
	local view = self.view
	local pools = { view.pops_enemy, view.pops_player, view.pops_match }
	for p = 1, #pools do
		local pool = pools[p]
		pool.hf_last, pool.hf_stack = nil, 0
		for i = 1, #pool do
			local fs = pool[i]
			if fs.ls ~= nil and fs.ls ~= 1 and self.can_scale then
				fs.ls = 1
				fs:SetScale(1)
			end
			if fs.fb_big then
				fs.fb_big = false
				fs:SetFontObject(A.FONT_POP)
			end
		end
	end
end

---------------------------------------------------------------- dev (debug panel)

HitFx.DEV_BUTTONS = {
	{ "Chip player", "chip_player" }, { "Chip enemy", "chip_enemy" }, { "Heal flash", "heal" }, { "Low HP on/off", "low" },
	{ "Pop shield", "pop_shield" }, { "Pop fire shld", "pop_fire_shield" }, { "Pop lifesteal", "pop_lifesteal" },
	{ "Pop curse", "pop_curse" }, { "Pop stun", "pop_stun" }, { "Pop heal blk", "pop_heal_block" },
	{ "Pop sand", "pop_sandstorm" }, { "Pop aegis", "pop_enemy_aegis" }, { "Pop mirror", "pop_enemy_mirror" },
	{ "Pop e stun", "pop_enemy_stun" }, { "Pop e slow", "pop_enemy_slow" },
	{ "Shatter buff", "shatter_lifesteal" }, { "Shatter debuff", "shatter_curse" }, { "Shatter shield", "shatter_shield" },
	{ "Aura stun", "aura_stun" }, { "Aura curse", "aura_curse" }, { "Aura fire", "aura_fire_shield" },
	{ "Aura shield", "aura_shield" }, { "Aura lifesteal", "aura_lifesteal" },
	{ "Block", "block" }, { "Reflect", "reflect" },
	{ "Tele attack", "tele_plain" }, { "Tele curse", "tele_curse" }, { "Tele junk", "tele_junk" },
	{ "Tele mirror", "tele_mirror" }, { "Tele special", "tele_special" },
	{ "Entrance", "enter" }, { "Death", "death" }, { "Death boss", "death_boss" }, { "Phase change", "phase" },
	{ "Score punch", "score" }, { "Score big", "score_big" }, { "Number stack", "numbers" },
}

-- Plays one effect now (no sim write). Returns true when played.
function HitFx:dev(kind, now)
	local jc, view, L = self.jc, self.view, self.L
	if jc.host ~= nil then jc.now = now end
	if kind == "chip_player" or kind == "chip_enemy" then
		local c = self.bars[kind == "chip_player" and "player" or "enemy"]
		if not c.init then return false end
		local from = c.last + 0.3 * c.mx
		if from > c.mx then from = c.mx end
		c.from, c.target, c.t0 = from, c.last, now
		return true
	elseif kind == "heal" then
		self:heal(now)
		return true
	elseif kind == "low" then
		self.dev_low = not self.dev_low
		return true
	elseif kind:sub(1, 4) == "pop_" then
		local rec = self.icon_by_id[kind:sub(5)]
		if rec == nil then return false end
		pop(rec, HitFx.POP_PEAK, now)
		ring_at(self, rec)
		return true
	elseif kind:sub(1, 8) == "shatter_" then
		local id = kind:sub(9)
		local rec = self.icon_by_id[id]
		if rec == nil then return false end
		shatter(self, rec, id == "shield" and HitFx.SHARDS_SHIELD or HitFx.SHARDS)
		return true
	elseif kind:sub(1, 5) == "aura_" then
		local id = kind:sub(6)
		if A.STATUS_AURA[id] == nil then return false end
		self.dev_aura, self.dev_aura_until = id, now + 3
		return true
	elseif kind == "block" then
		self:blocked(now)
		return true
	elseif kind == "reflect" then
		self:reflected(now)
		view:_on_reflect()
		return true
	elseif kind:sub(1, 5) == "tele_" then
		self.tele_t0, self.tele_dur, self.tele_dev = now, 1.6, true
		self.tele_c = HitFx.intent_tint(kind:sub(6))
		return true
	elseif kind == "enter" then
		self:enter(now)
		return true
	elseif kind == "death" or kind == "death_boss" then
		self:death(kind == "death_boss", now)
		return true
	elseif kind == "phase" then
		self:phase(now)
		return true
	elseif kind == "score" or kind == "score_big" then
		self:score(kind == "score" and 40 or 400, now)
		return true
	elseif kind == "numbers" then
		local C = A.COLOR
		local x = L.enemy_x
		for i = 1, 3 do view:_spawn_pop(view.pops_enemy, "-" .. tostring(100 + i), C.POP_ENEMY, x + (i - 2) * 30, -20, false) end
		view:_spawn_pop(view.pops_enemy, "-999", C.POP_BOOSTED, x, -20, true, "crit")
		view:_spawn_pop(view.pops_player, "+120", C.POP_HEAL, 60, -232, false, "heal")
		view:_spawn_pop(view.pops_player, "-300", C.POP_PLAYER, 60, -232, false, "player", 1)
		return true
	end
	return false
end

ns.HitFx = HitFx
