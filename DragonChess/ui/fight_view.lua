local addonName, ns = ...
-- Fight screen (W0-P2; replaces the W0-G1 text HUD ui/hud_min.lua). Port of the
-- Godot game.tscn HUD with WoW assets: enemy panel (stage / name / weakness,
-- PlayerModel enemy with a portrait fallback, vertical attack queue with a
-- Cooldown sweep, enemy stun / slow slots, ability banner, CLEARED, floating
-- damage numbers), bottom strip (player status icons + HP bar, score plaque
-- with count-up, enemy HP bar), red edge vignette on player hits, swap feedback
-- over the board, sounds. W0-G2b adds the enemy-status visuals (Divine Aegis gold glow +
-- icon, Mirror Shield silver glow + icon + crack bar + SHATTERED text, stun / freeze /
-- slow slots), the phase banner, the Sandstorm board tint (+ player status icon), the junk
-- flash, per-kind intent glyphs and the run's stage label. Static chrome (panels, backgrounds, overlay) is
-- ui/window.lua.
--
-- No game rules: every number comes from combat:hud_state(out) (read once per
-- frame into one reused table) and combat events. All fades / pulses / count-ups
-- run on sim time (combat.sim.now), so they freeze with the window like the
-- fight does. The only wall-clock use is the Cooldown widget (it animates on
-- GetTime()): it is re-synced to the sim's attack timer whenever they drift
-- apart and cleared on freeze() (soft pause, error, game over).
--
-- W0-P3: sounds per event (Assets.SOUNDS: gem break on gems_cleared, per-ability sounds by ability id,
-- player hit / blocked / miss, per-enemy creature attack / death sounds from the enemy def; no wound
-- sound, W0-P3.1), spell effects through
-- ui/fx.lua (per ability, enemy hit instead of the red disc, stun stars / freeze / Divine Aegis / Mirror
-- Shield while they last) and creature animation on the enemy model (stand, attack at the wind-up, wound,
-- stun pose, death). halt() = freeze + stop effects and long sounds (hide / pause / menu / game over).
--
-- W0-P6 (juice): ui/juice.lua owns the pooled streaks / shards / rings / shake; this file decides when they fire
-- (event handlers below). A hit on the enemy is a streak flying from the match / ability cell; the damage number,
-- the hit effect and the wound animation (_enemy_hit) wait for its arrival (view only: the sim already dealt the
-- damage). Vignette flashes come in colours (red hit, cyan skill, gold ult, silver Mirror, orange reflect).
--
-- W0-P8 (hit / status readability): ui/hit_fx.lua owns chip bars, low-HP warning, status pop / blink / shatter / aura,
-- the windup telegraph, entrance / death / phase effects, score punch and the damage-number pop; this file only forwards
-- events and hud_state to it (a failing build leaves HitFx.NONE and the plain code paths below).
--
-- Per frame: no table or closure creation; setters only run when a value
-- changed; timer texts come from precreated string caches; pooled damage
-- numbers (string per event, not per frame).

local floor, ceil, abs, sin, pi = math.floor, math.ceil, math.abs, math.sin, math.pi
local upper, tostring, pcall = string.upper, tostring, pcall

local FightView = {}
FightView.__index = FightView

-- View-only timings (sim seconds).
local BANNER_IN, BANNER_HOLD, BANNER_FADE = 0.12, 1.1, 0.4
local FLASH_HOLD, FLASH_FADE = 0.6, 0.3
local VIGNETTE_TIME = 0.35
local HIT_TIME = 0.22 -- enemy hit punch + glow
local HIT_PUNCH = 0.06
local DEATH_FADE = 0.6
local POP_TIME, POP_RISE, POP_HOLD = 0.9, 46, 0.55
local SCORE_COUNT = 0.45
local CLEARED_IN = 0.2
local NOW_PULSE = 12 -- rad/s of the wind-up pulse
local COOLDOWN_RESYNC = 0.08 -- s of drift before the Cooldown is re-set
-- W0-P6 juice tuning (sim s / px; shake strength = trauma 0..1, ui/juice.lua turns it into pixels).
local VIG_FLASH_TIME = 0.27 -- ability flash (Godot 0.05 in + 0.22 out)
local VIG_PEAK_SKILL, VIG_PEAK_ULT, VIG_PEAK_MIRROR, VIG_PEAK_REFLECT = 0.5, 1, 0.6, 0.8
local KNOCK, KNOCK_TIME, KNOCK_OUT = 8, 0.17, 0.05 -- enemy knock-back px (Godot ENEMY_KNOCKBACK_*: 8 px, out 0.05, back 0.12)
local WEIGHT_ULT, WEIGHT_SKILL, WEIGHT_BOMB = 2.0, 1.4, 1.2 -- streak weight of an ability's damage (Godot)
local TRAUMA_SKILL, TRAUMA_ULT, TRAUMA_BOMB = 0.22, 0.55, 0.3
local TRAUMA_MATCH_MIN, TRAUMA_MATCH_MAX = 0.1, 0.65 -- 4-match .. 7-match
local TRAUMA_MIRROR, TRAUMA_CLEARED = 0.35, 0.22
local TRAUMA_HIT_MIN, TRAUMA_HIT_MAX, HIT_FULL = 0.12, 0.6, 0.15 -- player hit: scales with damage / max HP, full at 15 %

-- Layout (px, enemy panel 470 x 524, bottom strip 998 x 30; ui/window.lua).
local SLOT1, SLOT = 52, 40
local STATUS_SIZE, STATUS_GAP = 26, 3
local ENEMY_SIZE_W, ENEMY_SIZE_H = 340, 360 -- H is set from the panel height in _build_enemy (frame up to the top edge)
local ENEMY_X = 45 -- enemy frame offset right of the panel centre (queue column on the left)
local PORTRAIT = 150
local POP_POOL = 8
local MATCH_POOL = 8 -- board floats (match text / ability gem spawn), W0-P5
local BOARD_COLS = 8
local CAST_TIME = 0.4 -- enemy cast flash
local PLAYER_BAR_X, PLAYER_BAR_W = 208, 256 -- room for 7 status icons (2 + 7 x 29)
local PLAQUE_X = 526 -- seam between the panels, from the strip's left edge
local ENEMY_BAR_X = 590

-- Player status strip order (combat:hud_state statuses keys; "sandstorm" = the board's gravity slow).
local PLAYER_STATUS = { "shield", "fire_shield", "lifesteal", "curse", "stun", "heal_block", "sandstorm" }
local ENEMY_ICON = 34 -- Aegis / Mirror icons over the enemy
local PHASE_IN, PHASE_HOLD, PHASE_FADE = 0.15, 1.6, 0.5
local MSG_HOLD, MSG_FADE = 0.9, 0.4 -- "SHATTERED!" text
local JUNK_FLASH_TIME = 0.6
local SAND_FADE = 1.0 -- the sand layer fades out over the last second
-- Enemy pop jitter (px, cycled).
local JITTER = { -40, 30, -12, 52, -58, 14, 40, -26 }

local A -- ns.Assets (resolved in new: files load in TOC order)

---------------------------------------------------------------- string caches

-- "1.8s" for tenths of a second (rounded up), precreated up to 60 s.
local PRECREATED = 600
local tenths_cache, whole_cache, crack_cache = {}, {}, {}
local function precreate()
	if tenths_cache[1] ~= nil then return end
	for k = 0, 100 do crack_cache[k + 1] = "Crack " .. k .. "%" end
	for k = 0, PRECREATED do tenths_cache[k + 1] = ("%.1fs"):format(k / 10) end
	for k = 0, 99 do whole_cache[k + 1] = tostring(k) end
end
local function secs(t)
	local k = ceil(t * 10 - 1e-6)
	if k < 0 then k = 0 end
	return tenths_cache[k + 1] or ("%.1fs"):format(k / 10)
end
local function whole(n)
	return whole_cache[n + 1] or tostring(n)
end

-- Stage label with the stage's place name: "STAGE 1-2 · DIRE MAUL" (W0-P3.1; U+00B7, in the Latin-1
-- range every WoW font has). The dev fight ("DEV") and an unnamed stage keep the bare label.
local STAGE_SEP = " \194\183 "
local function stage_line(label, stage)
	local name = A.STAGE_NAME[stage]
	if name == nil or label == "DEV" then return label end
	return label .. STAGE_SEP .. upper(name)
end

---------------------------------------------------------------- widget helpers

local function set_color(tex, c) tex:SetColorTexture(c[1], c[2], c[3], c[4]) end

local function text_color(fs, c)
	if fs.lcolor ~= c then
		fs.lcolor = c
		fs:SetTextColor(c[1], c[2], c[3], c[4])
	end
end

local function font(parent, template, layer)
	return parent:CreateFontString(nil, layer or "OVERLAY", template)
end

local function set_text(fs, s)
	if fs.ltext ~= s then
		fs.ltext = s
		fs:SetText(s)
	end
end

local function set_alpha(r, a)
	if r.lalpha ~= a then
		r.lalpha = a
		r:SetAlpha(a)
	end
end

local function set_shown(r, v)
	if r.lshown ~= v then
		r.lshown = v
		if v then r:Show() else r:Hide() end
	end
end

local function set_texture(tex, path)
	if tex.lpath ~= path then
		tex.lpath = path
		tex:SetTexture(path)
	end
end

local function masked(parent, layer, sublevel)
	local tex = parent:CreateTexture(nil, layer, nil, sublevel)
	local mask = parent:CreateMaskTexture()
	mask:SetTexture(A.ROUND_MASK, A.MASK_WRAP, A.MASK_WRAP)
	mask:SetAllPoints(tex)
	tex:AddMaskTexture(mask)
	tex.dc_mask, tex.dc_round = mask, true
	return tex
end

local function crop(tex)
	local tc = A.GEM_TEXCOORD
	tex:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
end

-- Anchors f and remembers the anchor (W0-P8: HitFx scales icons / the plaque / the name around it; offsets are
-- divided by the scale there so the centre stays put). pt is the anchor of f itself.
local function home(f, pt, rel, rpt, x, y)
	f:SetPoint(pt, rel, rpt, x, y)
	f.home = { pt, rel, rpt, x, y }
end

-- Alpha 0..1 quantised to 20 steps (fewer setter calls).
local function q20(a)
	if a <= 0 then return 0 end
	if a >= 1 then return 1 end
	return floor(a * 20 + 0.5) / 20
end

-- In / hold / fade alpha of an element started at t0 (nil = hidden).
local function fade_alpha(now, t0, fade_in, hold, fade)
	if t0 == nil then return 0 end
	local t = now - t0
	if t < 0 then return 0 end
	if t < fade_in then return q20(t / fade_in) end
	t = t - fade_in
	if t < hold then return 1 end
	if t >= hold + fade then return 0 end
	return q20(1 - (t - hold) / fade)
end

local function bar(parent, h, c)
	local b = CreateFrame("StatusBar", nil, parent)
	b:SetHeight(h)
	b:SetStatusBarTexture(A.BAR)
	b:SetStatusBarColor(c[1], c[2], c[3], c[4])
	b:SetMinMaxValues(0, 1)
	b:SetValue(0)
	local edge = b:CreateTexture(nil, "BACKGROUND", nil, 0)
	edge:SetPoint("TOPLEFT", b, "TOPLEFT", -1, 1)
	edge:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1)
	set_color(edge, A.COLOR.BAR_EDGE)
	local bg = b:CreateTexture(nil, "BACKGROUND", nil, 1)
	bg:SetAllPoints(b)
	set_color(bg, A.COLOR.BAR_BG)
	b.lmax, b.lval, b.lcolor = 1, 0, c
	b.text = font(b, A.FONT_HUD_SMALL)
	b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
	return b
end

local function bar_set(b, value, maxv)
	if maxv <= 0 then maxv = 1 end
	if maxv ~= b.lmax then
		b.lmax = maxv
		b:SetMinMaxValues(0, maxv)
	end
	if value < 0 then value = 0 end
	if value ~= b.lval then
		b.lval = value
		b:SetValue(value)
	end
end

local function bar_color(b, c)
	if b.lcolor ~= c then
		b.lcolor = c
		b:SetStatusBarColor(c[1], c[2], c[3], c[4])
	end
end

-- "a / b" for HP bars; only formatted when a value changed.
local function hp_text(fs, hp, maxhp)
	if fs.lhp ~= hp or fs.lmax ~= maxhp then
		fs.lhp, fs.lmax = hp, maxhp
		set_text(fs, ("%d / %d"):format(hp, maxhp))
	end
end

-- Status icon: square spell icon, black edge, dark "elapsed" part from the top,
-- number (seconds / stacks) bottom-right.
local function status_icon(parent, size)
	local s = CreateFrame("Frame", nil, parent)
	s:SetSize(size, size)
	local edge = s:CreateTexture(nil, "BACKGROUND")
	edge:SetPoint("TOPLEFT", s, "TOPLEFT", -2, 2) -- W0-P8: 2 px class-coloured edge (HitFx sets the colour)
	edge:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", 2, -2)
	set_color(edge, A.COLOR.BAR_EDGE)
	s.edge = edge
	s.icon = s:CreateTexture(nil, "ARTWORK", nil, 0)
	s.icon:SetAllPoints(s)
	crop(s.icon)
	s.dim = s:CreateTexture(nil, "ARTWORK", nil, 1)
	s.dim:SetPoint("TOP", s, "TOP", 0, 0)
	s.dim:SetWidth(size)
	set_color(s.dim, A.COLOR.STATUS_DIM)
	s.dim:Hide()
	s.num = font(s, A.FONT_HUD_SMALL)
	s.num:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", 2, -1)
	s.size = size
	s.ldim = -1
	s:Hide()
	s.lshown = false
	return s
end

-- Elapsed part (0..1 of remaining / max) as a dark overlay height.
local function status_dim(s, remaining, maxv)
	local h = 0
	if maxv > 0 then
		local r = remaining / maxv
		if r < 0 then r = 0 elseif r > 1 then r = 1 end
		h = floor(s.size * (1 - r) + 0.5)
	end
	if h ~= s.ldim then
		s.ldim = h
		if h <= 0 then
			s.dim:Hide()
		else
			s.dim:SetHeight(h)
			s.dim:Show()
		end
	end
end

-- Intent slot: dark disc, round spell icon, optional ring atlas.
local function intent_slot(parent, size)
	local s = CreateFrame("Frame", nil, parent)
	s:SetSize(size, size)
	s.disc = masked(s, "BACKGROUND", 1)
	s.disc:SetPoint("CENTER", s, "CENTER", 0, 0)
	s.disc:SetSize(size + 6, size + 6)
	set_color(s.disc, A.COLOR.SLOT_DISC)
	s.icon = masked(s, "ARTWORK")
	s.icon:SetAllPoints(s)
	crop(s.icon)
	s.ring = s:CreateTexture(nil, "OVERLAY")
	s.ring:SetPoint("CENTER", s, "CENTER", 0, 0)
	s.ring:SetSize(size * 1.4, size * 1.4)
	s.has_ring = A.apply(s.ring, A.SLOT_RING) ~= nil
	if not s.has_ring then s.ring:Hide() end
	s:Hide()
	s.lshown = false
	return s
end

---------------------------------------------------------------- construction

-- win: the table from ns.Window.create.
function FightView.new(win)
	A = ns.Assets
	precreate()
	local self = setmetatable({}, FightView)
	self.win = win
	self.state = {} -- combat:hud_state(out), reused
	self.combat = nil
	self.stage = nil
	self.run_label = stage_line("STAGE 1-1", 1) -- set from the run (set_run_label)
	self.lphase = ""
	self:_build_enemy(win.enemy_panel)
	self:_build_queue(win.enemy_panel)
	self:_build_fx(win)
	self:_build_bottom(win.bottom)
	-- Spell effect models (W0-P3); a failure leaves the stand-in with no frames (the red hit disc stays).
	local okfx, fx = pcall(ns.Fx.new, win, { enemy = self.enemy_holder, player = self.player_bar, board = win.host })
	self.fx = okfx and fx or ns.Fx.NONE
	-- Streaks / shards / rings / shake (W0-P6); a failure leaves the stand-in (hit reactions then run at once).
	local okj, jc = pcall(ns.Juice.new, win, { player_x = PLAYER_BAR_X + PLAYER_BAR_W / 2 })
	if not okj then
		local handler = geterrorhandler()
		if handler then handler(jc) end
	end
	self.juice = okj and jc or ns.Juice.NONE
	self.juice.on_hit = function(kind, a, b) self:_on_juice_hit(kind, a, b) end
	-- Board ability effects, combo meter, board light (W0-P7); a failure leaves the stand-in (the window still works).
	local okb, bf = pcall(ns.BoardFx.new, win, self.juice)
	if not okb then
		local handler = geterrorhandler()
		if handler then handler(bf) end
	end
	self.boardfx = okb and bf or ns.BoardFx.NONE
	-- Hit / status readability (W0-P8); a failure leaves the stand-in (plain code paths).
	self.layout = {
		enemy_x = ENEMY_X, status_size = STATUS_SIZE, player_bar_x = PLAYER_BAR_X, player_bar_w = PLAYER_BAR_W,
		plaque_x = PLAQUE_X, enemy_w = ENEMY_SIZE_W, panel_w = win.enemy_panel_w, panel_h = win.panel_h,
		queue = { x = 12, y = 92, w = 72, h = 270 }, slot_size = 28, enemy_icon = ENEMY_ICON, player_status = PLAYER_STATUS,
	}
	local okh, hfx = pcall(ns.HitFx.new, self, self.juice)
	if not okh then
		local handler = geterrorhandler()
		if handler then handler(hfx) end
	end
	self.hitfx = okh and hfx or ns.HitFx.NONE
	self:set_stage(1)
	self:_reset_view()

	-- Combat event handlers (bound per combat in bind()).
	self._h = {
		ability_triggered = function(info) self:_on_ability(info) end,
		fight_started = function(enemy) self:_on_fight_started(enemy) end,
		enemy_defeated = function() self:_on_enemy_defeated() end,
		enemy_damaged = function(amount, boosted) self:_on_enemy_damaged(amount, boosted) end,
		enemy_windup = function(ability, windup) self:_on_windup(ability, windup) end,
		player_damaged = function(amount, source) self:_on_player_damaged(amount, source) end,
		enemy_phase_changed = function(label) self:_on_phase(label) end,
		enemy_mirror_changed = function(active, broken) self:_on_mirror(active, broken) end,
		enemy_immune = function() self:_pop_enemy_text("Immune", A.COLOR.POP_INFO) end,
		junk_spawned = function() self:_on_junk() end,
		player_healed = function(amount)
			self:_pop_player("+" .. tostring(amount), A.COLOR.POP_HEAL, "heal")
			self:_streak_to_player(A.COLOR.PROJ_HEAL, 0.85)
			self.hitfx:heal(self:_now())
		end,
		attack_blocked = function()
			self:_pop_player("Blocked", A.COLOR.POP_INFO)
			A.play("blocked")
			self.hitfx:blocked(self:_now())
		end,
		attack_reflected = function()
			self:_pop_player("Reflected", A.COLOR.POP_INFO)
			A.play("blocked")
			self:_on_reflect()
			self.hitfx:reflected(self:_now())
		end,
		score_awarded = function(amount) self.hitfx:score(amount, self:_now()) end,
		heal_blocked = function() self:_pop_player("Heal blocked", A.COLOR.POP_INFO) end,
		match_resolved = function(length, gems, depth, dcol, drow) self:_on_match(length, gems, depth, dcol, drow) end,
		ability_gem_spawned = function(col, row, tier, gem_type) self:_on_gem_spawned(col, row, tier, gem_type) end,
		enemy_ability_executed = function(ability) self:_on_enemy_cast(ability) end,
		swap_rejected = function() A.play("miss") end,
		swap_accepted = function() A.play("swap_ok") end,
		run_lost = function() A.play("defeat") end,
	}
	return self
end

function FightView:_build_enemy(ep)
	local C = A.COLOR
	-- Header: STAGE 1-1 / NAME above the model (plain text, no box); the weakness line stays in a
	-- hidden frame (state + tests). hdr sits above the model frame.
	local hdr = CreateFrame("Frame", nil, ep)
	hdr:SetAllPoints(ep)
	hdr:SetFrameLevel(ep:GetFrameLevel() + 12)
	local hdr_weak = CreateFrame("Frame", nil, ep)
	hdr_weak:SetAllPoints(ep)
	hdr_weak:Hide()
	self.stage_text = font(hdr, A.FONT_LABEL_SMALL)
	self.stage_text:SetPoint("TOP", ep, "TOP", 0, -12)
	text_color(self.stage_text, C.STAGE_TEXT)
	set_text(self.stage_text, self.run_label)
	self.name_text = font(hdr, A.FONT_ENEMY_NAME)
	home(self.name_text, "TOP", self.stage_text, "BOTTOM", 0, -4)
	self.weak_icon = masked(hdr_weak, "OVERLAY")
	self.weak_icon:SetSize(16, 16)
	self.weak_icon:SetPoint("TOP", self.name_text, "BOTTOM", 0, -6)
	crop(self.weak_icon)
	self.weak_label = font(hdr_weak, A.FONT_HUD_SMALL)
	self.weak_label:SetPoint("RIGHT", self.weak_icon, "LEFT", -4, 0)
	text_color(self.weak_label, C.WEAK_TEXT)
	set_text(self.weak_label, "WEAK")
	self.weak_name = font(hdr_weak, A.FONT_HUD_SMALL)
	self.weak_name:SetPoint("LEFT", self.weak_icon, "RIGHT", 4, 0)

	-- Enemy frame: PlayerModel (display ID) or portrait fallback.
	local holder = CreateFrame("Frame", nil, ep)
	-- The model frame is exactly the enemy panel (the background image), so no model is cut off.
	ENEMY_SIZE_W, ENEMY_SIZE_H = self.win.enemy_panel_w or ENEMY_SIZE_W, self.win.panel_h or ENEMY_SIZE_H
	holder:SetSize(ENEMY_SIZE_W, ENEMY_SIZE_H)
	holder:SetPoint("CENTER", ep, "CENTER", 0, 0)
	self.enemy_holder = holder
	self.enemy_ep = ep
	self.knock_x = 0
	self.portrait = masked(holder, "ARTWORK")
	self.portrait:SetSize(PORTRAIT, PORTRAIT)
	self.portrait:SetPoint("CENTER", holder, "CENTER", 0, 0)
	crop(self.portrait)
	self.portrait_ring = holder:CreateTexture(nil, "OVERLAY")
	self.portrait_ring:SetSize(PORTRAIT * 1.3, PORTRAIT * 1.3)
	self.portrait_ring:SetPoint("CENTER", holder, "CENTER", 0, 0)
	self.has_portrait_ring = A.apply(self.portrait_ring, A.PORTRAIT_RING) ~= nil
	self.portrait:Hide()
	self.portrait_ring:Hide()
	local ok, model = pcall(CreateFrame, "PlayerModel", nil, holder)
	if ok and model ~= nil then
		model:SetAllPoints(holder)
		model:Hide()
		self.model = model
		-- The camera set before the model finished loading is dropped by the client (playtest 4: huge
		-- ogre until the debug panel re-framed it): frame again when it is loaded (+ a few timed re-frames).
		pcall(model.SetScript, model, "OnModelLoaded", function()
			if self.enemy_mode == "model" then self:_frame_model(A.ENEMY[self.enemy_key] or A.ENEMY_DEFAULT) end
		end)
		-- Same on the first open of the window: the model is sized / shown only then, and a camera
		-- set while it was hidden or 0-sized is dropped (playtest 5: huge ogre until close + reopen).
		local function reframe_now()
			if self.enemy_mode == "model" then
				self:_frame_model(A.ENEMY[self.enemy_key] or A.ENEMY_DEFAULT)
				self.reframe_n = 300
			end
		end
		pcall(model.SetScript, model, "OnShow", reframe_now)
		pcall(model.SetScript, model, "OnSizeChanged", reframe_now)
	end
	-- Hit glow over the model / portrait (additive red disc).
	local glow_frame = CreateFrame("Frame", nil, holder)
	glow_frame:SetAllPoints(holder)
	glow_frame:SetFrameLevel(holder:GetFrameLevel() + 5)
	self.glow_frame = glow_frame
	self.hit_glow = masked(glow_frame, "OVERLAY")
	self.hit_glow:SetPoint("CENTER", holder, "CENTER", 0, 0)
	self.hit_glow:SetSize(ENEMY_SIZE_W * 0.8, ENEMY_SIZE_W * 0.8)
	set_color(self.hit_glow, C.HIT_TINT)
	self.hit_glow:SetBlendMode("ADD")
	self.hit_glow:SetAlpha(0)
	-- Enemy cast flash (W0-P5): orange additive disc when an enemy ability lands (enemy_ability_executed).
	self.cast_glow = masked(glow_frame, "OVERLAY", 3)
	self.cast_glow:SetPoint("CENTER", holder, "CENTER", 0, 0)
	self.cast_glow:SetSize(ENEMY_SIZE_W * 0.85, ENEMY_SIZE_W * 0.85)
	set_color(self.cast_glow, C.CAST_TINT)
	self.cast_glow:SetBlendMode("ADD")
	self.cast_glow:SetAlpha(0)
	-- Divine Aegis (gold) / Mirror Shield (silver): additive glows over the figure while active.
	self.aegis_glow = masked(glow_frame, "OVERLAY", 1)
	self.aegis_glow:SetPoint("CENTER", holder, "CENTER", 0, 0)
	self.aegis_glow:SetSize(ENEMY_SIZE_W * 0.9, ENEMY_SIZE_W * 0.9)
	set_color(self.aegis_glow, C.AEGIS_GLOW)
	self.aegis_glow:SetBlendMode("ADD")
	self.aegis_glow:Hide()
	self.mirror_glow = masked(glow_frame, "OVERLAY", 2)
	self.mirror_glow:SetPoint("CENTER", holder, "CENTER", 0, 0)
	self.mirror_glow:SetSize(ENEMY_SIZE_W * 0.9, ENEMY_SIZE_W * 0.9)
	set_color(self.mirror_glow, C.MIRROR_GLOW)
	self.mirror_glow:SetBlendMode("ADD")
	self.mirror_glow:Hide()
	self.enemy_key = nil
	self.enemy_mode = nil -- "model" / "portrait"
end

function FightView:_build_queue(ep)
	local C = A.COLOR
	local q = CreateFrame("Frame", nil, ep, A.TEMPLATE_BACKDROP)
	q:SetPoint("TOPLEFT", ep, "TOPLEFT", 12, -92)
	q:SetSize(72, 270)
	q:SetBackdrop(A.BACKDROP_PANEL)
	q:SetBackdropColor(C.QUEUE_BG[1], C.QUEUE_BG[2], C.QUEUE_BG[3], C.QUEUE_BG[4])
	q:SetBackdropBorderColor(C.PANEL_EDGE[1], C.PANEL_EDGE[2], C.PANEL_EDGE[3], C.PANEL_EDGE[4])
	self.queue = q

	local s1 = intent_slot(q, SLOT1)
	s1:SetPoint("TOP", q, "TOP", 0, -14)
	-- wind-up pulse behind slot 1
	s1.now = masked(s1, "BACKGROUND", 0)
	s1.now:SetPoint("CENTER", s1, "CENTER", 0, 0)
	s1.now:SetSize(SLOT1 + 18, SLOT1 + 18)
	set_color(s1.now, C.SLOT_NOW)
	s1.now:SetBlendMode("ADD")
	s1.now:Hide()
	-- timer sweep (Cooldown, wall clock re-synced to sim time; see header)
	local ok, cd = pcall(CreateFrame, "Cooldown", nil, s1)
	if ok and cd ~= nil then
		cd:SetAllPoints(s1)
		if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
		if cd.SetDrawEdge then cd:SetDrawEdge(false) end
		if cd.SetSwipeTexture then cd:SetSwipeTexture(A.ROUND_MASK) end
		if cd.SetSwipeColor then
			local c = C.SWIPE
			cd:SetSwipeColor(c[1], c[2], c[3], c[4])
		end
		self.cooldown = cd
	end
	self.cd_start, self.cd_dur = nil, nil
	self.q_timer = font(q, A.FONT_HUD_SMALL)
	self.q_timer:SetPoint("TOP", s1, "BOTTOM", 0, -6)
	local s2 = intent_slot(q, SLOT)
	s2:SetPoint("TOP", s1, "BOTTOM", 0, -26)
	local s3 = intent_slot(q, SLOT)
	s3:SetPoint("TOP", s2, "BOTTOM", 0, -12)
	self.slots = { s1, s2, s3 }

	-- enemy stun / freeze and slow slots under the queue
	self.enemy_stun = status_icon(q, 28)
	home(self.enemy_stun, "CENTER", q, "BOTTOMLEFT", 6 + 14, 10 + 14)
	self.enemy_slow = status_icon(q, 28)
	home(self.enemy_slow, "CENTER", q, "BOTTOMRIGHT", -6 - 14, 10 + 14)
	set_texture(self.enemy_slow.icon, A.icon("enemy_slow"))
	self.cyc_max, self.cyc_last = 1, -1
end

function FightView:_build_fx(win)
	local C = A.COLOR
	local efx = win.enemy_fx
	-- Ability banner (top of the enemy panel, over the enemy frame).
	local bn = CreateFrame("Frame", nil, efx)
	bn:SetSize(380, 78)
	bn:SetPoint("TOP", efx, "TOP", ENEMY_X, -84)
	local bg = bn:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(bn)
	A.apply(bg, A.BANNER_BG)
	local top = bn:CreateTexture(nil, "ARTWORK", nil, 0)
	top:SetSize(220, 34)
	top:SetPoint("BOTTOM", bn, "TOP", 0, -14)
	if A.apply(top, A.BANNER_TOP) == nil then top:Hide() end
	bn.icon = masked(bn, "ARTWORK", 1)
	bn.icon:SetSize(44, 44)
	bn.icon:SetPoint("LEFT", bn, "LEFT", 30, 0)
	crop(bn.icon)
	bn.title = font(bn, A.FONT_BANNER)
	bn.title:SetPoint("TOPLEFT", bn.icon, "TOPRIGHT", 10, -2)
	bn.blurb = font(bn, A.FONT_HUD_SMALL)
	bn.blurb:SetPoint("TOPLEFT", bn.title, "BOTTOMLEFT", 0, -4)
	bn.blurb:SetWidth(270)
	bn.blurb:SetJustifyH("LEFT")
	text_color(bn.blurb, C.BANNER_BLURB)
	self.banner = bn

	-- CLEARED sting (centre of the enemy panel).
	local cl = CreateFrame("Frame", nil, efx)
	cl:SetSize(380, 96)
	cl:SetPoint("CENTER", efx, "CENTER", ENEMY_X, 20)
	local cbg = cl:CreateTexture(nil, "BACKGROUND")
	cbg:SetAllPoints(cl)
	A.apply(cbg, A.BANNER_BG)
	cl.text = font(cl, A.FONT_CLEARED)
	cl.text:SetPoint("CENTER", cl, "CENTER", 0, 0)
	cl.text:SetText("CLEARED")
	self.cleared = cl

	-- Phase banner (centre-upper part of the enemy panel).
	local ph = CreateFrame("Frame", nil, efx)
	ph:SetSize(380, 84)
	ph:SetPoint("CENTER", efx, "CENTER", ENEMY_X, 90)
	local pbg = ph:CreateTexture(nil, "BACKGROUND")
	pbg:SetAllPoints(ph)
	A.apply(pbg, A.BANNER_BG)
	ph.small = font(ph, A.FONT_LABEL_SMALL)
	ph.small:SetPoint("TOP", ph, "TOP", 0, -12)
	text_color(ph.small, C.PHASE_TEXT)
	ph.small:SetText("PHASE")
	ph.title = font(ph, A.FONT_CLEARED)
	ph.title:SetPoint("TOP", ph.small, "BOTTOM", 0, -4)
	self.phase_banner = ph

	-- Divine Aegis / Mirror Shield icons (bottom of the enemy panel, over the figure's feet):
	-- icon + whole seconds, the Mirror's crack bar and its SHATTERED text.
	self.aegis_icon = status_icon(efx, ENEMY_ICON)
	home(self.aegis_icon, "CENTER", efx, "BOTTOM", ENEMY_X - 28, 46 + ENEMY_ICON / 2)
	set_texture(self.aegis_icon.icon, A.icon("enemy_aegis"))
	self.mirror_icon = status_icon(efx, ENEMY_ICON)
	home(self.mirror_icon, "CENTER", efx, "BOTTOM", ENEMY_X + 28, 46 + ENEMY_ICON / 2)
	set_texture(self.mirror_icon.icon, A.icon("enemy_mirror"))
	self.crack_bar = bar(efx, 10, C.MIRROR_BAR)
	self.crack_bar:SetPoint("BOTTOM", efx, "BOTTOM", ENEMY_X, 32)
	self.crack_bar:SetWidth(150)
	self.crack_bar:SetMinMaxValues(0, 100)
	self.crack_bar.lmax = 100
	self.crack_bar:Hide()
	self.crack_bar.lshown = false
	self.mirror_msg = font(efx, A.FONT_BANNER)
	self.mirror_msg:SetPoint("CENTER", efx, "CENTER", ENEMY_X, -70)
	text_color(self.mirror_msg, C.PHASE_TEXT)
	self.mirror_msg:SetText("SHATTERED!")

	-- Board tints over the gems (the fx layer has no mouse): Sandstorm layer + junk flash.
	self.sand_tint = win.fx:CreateTexture(nil, "BACKGROUND")
	self.sand_tint:SetAllPoints(win.fx)
	set_color(self.sand_tint, C.SAND_TINT)
	self.sand_tint:Hide()
	self.junk_tint = win.fx:CreateTexture(nil, "BACKGROUND", nil, 1)
	self.junk_tint:SetAllPoints(win.fx)
	set_color(self.junk_tint, C.JUNK_FLASH)
	self.junk_tint:Hide()

	-- Floating damage numbers: enemy (enemy fx layer) and player (board fx).
	self.pops_enemy = self:_pool(efx, POP_POOL)
	self.pops_player = self:_pool(win.fx, 4)
	self.pops_match = self:_pool(win.fx, MATCH_POOL) -- match text / ability gem floats on the board (W0-P5)
	self.pops_match.plain = true -- W0-P8: no pop scale / stacking on these (HitFx)
	self.jitter_i = 0

	-- Swap feedback over the board ("Stunned!").
	self.flash_text = font(win.fx, A.FONT_BANNER)
	self.flash_text:SetPoint("BOTTOM", win.fx, "BOTTOM", 0, 110)
	text_color(self.flash_text, C.TEXT_WARN)

	-- Red edge vignette on player hits (whole content area).
	local vig = CreateFrame("Frame", nil, win.content)
	vig:SetAllPoints(win.content)
	self.vignette = vig
	local edges = {}
	self.vig_edges = edges
	local function edge(p1, p2, w, h, c, a)
		local t = vig:CreateTexture(nil, "OVERLAY")
		edges[#edges + 1] = { tex = t, a = a }
		t:SetPoint(p1, vig, p1, 0, 0)
		t:SetPoint(p2, vig, p2, 0, 0)
		if w then t:SetWidth(w) else t:SetHeight(h) end
		t:SetColorTexture(c[1], c[2], c[3], c[4] * a)
	end
	local vc = C.VIGNETTE
	for _, th in ipairs({ { 14, 1 }, { 40, 0.45 } }) do
		edge("TOPLEFT", "TOPRIGHT", nil, th[1], vc, th[2])
		edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, th[1], vc, th[2])
		edge("TOPLEFT", "BOTTOMLEFT", th[1], nil, vc, th[2])
		edge("TOPRIGHT", "BOTTOMRIGHT", th[1], nil, vc, th[2])
	end
	vig:SetAlpha(0)
	vig.lalpha = 0
	self.vig_color = vc
end

function FightView:_pool(parent, n)
	local pool = {}
	for i = 1, n do
		local fs = font(parent, A.FONT_POP)
		fs:Hide()
		fs.t0 = nil
		pool[i] = fs
	end
	pool.parent = parent
	pool.next = 1
	return pool
end

function FightView:_build_bottom(bottom)
	local C = A.COLOR
	-- player status strip (left), packed in PLAYER_STATUS order
	self.status = {}
	for i = 1, #PLAYER_STATUS do
		local id = PLAYER_STATUS[i]
		local s = status_icon(bottom, STATUS_SIZE)
		set_texture(s.icon, A.icon("status_" .. id))
		s.lwhole = -1
		home(s, "CENTER", bottom, "LEFT", 2 + STATUS_SIZE / 2 + (i - 1) * (STATUS_SIZE + STATUS_GAP), 0)
		self.status[id] = s
	end
	self.status_layout_dirty = true

	self.player_bar = bar(bottom, 18, C.HP_PLAYER)
	self.player_bar:SetPoint("LEFT", bottom, "LEFT", PLAYER_BAR_X, 0)
	self.player_bar:SetWidth(PLAYER_BAR_W)
	self.player_hp = self.player_bar.text

	self.enemy_bar = bar(bottom, 18, C.HP_ENEMY)
	self.enemy_bar:SetPoint("LEFT", bottom, "LEFT", ENEMY_BAR_X, 0)
	self.enemy_bar:SetWidth(998 - ENEMY_BAR_X - 4)
	self.enemy_hp = self.enemy_bar.text

	-- Score plaque at the seam (parchment + gold border).
	local plaque = CreateFrame("Frame", nil, bottom, A.TEMPLATE_BACKDROP)
	plaque:SetSize(120, 48)
	home(plaque, "CENTER", bottom, "LEFT", PLAQUE_X, 6)
	plaque:SetFrameLevel(bottom:GetFrameLevel() + 4)
	local fill = plaque:CreateTexture(nil, "BACKGROUND")
	fill:SetPoint("TOPLEFT", plaque, "TOPLEFT", 4, -4)
	fill:SetPoint("BOTTOMRIGHT", plaque, "BOTTOMRIGHT", -4, 4)
	A.apply(fill, A.PLAQUE)
	plaque:SetBackdrop(A.BACKDROP_PLAQUE)
	self.plaque = plaque
	local label = font(plaque, A.FONT_LABEL_SMALL)
	label:SetPoint("TOP", plaque, "TOP", 0, -7)
	text_color(label, C.SCORE_TEXT)
	label:SetText("SCORE")
	self.score_text = font(plaque, A.FONT_SCORE)
	self.score_text:SetPoint("TOP", label, "BOTTOM", 0, -2)
	text_color(self.score_text, C.SCORE_TEXT)
	self.score_from, self.score_to, self.score_t0, self.score_shown = 0, 0, nil, nil
end

-- Background art of a stage (enemy panel full, board panel under its dim layer).
-- The gem set changed: redraw the weakness icon now (the menu pauses the HUD update).
function FightView:refresh_gem_icons()
	local weak = self.lweak
	if weak ~= nil and ns.Combat.COLOR_NAMES[weak] ~= nil then A.apply_gem(self.weak_icon, weak) end
end

function FightView:set_stage(stage)
	if stage == self.stage then return end
	self.stage = stage
	self.bg_atlas = A.STAGE_BG_NAME[stage] or A.STAGE_BG_NAME[1]
	self.bg_color = A.STAGE_BG_COLOR[stage] or A.STAGE_BG_COLOR[1]
	self.bg_file = A.STAGE_BG_FILE[stage]
	self.bg_w, self.bg_h = nil, nil -- the constants BG_FILE_W / H
	self.bg_name = self.bg_file ~= nil and A.STAGE_NAME[stage] or self.bg_atlas
	self:_apply_bg()
end

local bg_spec = { atlas = nil, file = nil, file_w = nil, file_h = nil, color = nil } -- reused (dev command / stage change only)

-- Cover-fit the current background on both panels (crop, never stretch): the LFG background
-- file (bg_file, assumed A.BG_FILE_W x A.BG_FILE_H unless the shortlist entry has its own w / h) if
-- set, else the stage atlas; colour last.
function FightView:_apply_bg()
	local win = self.win
	local file = self.bg_file
	if file ~= nil then
		bg_spec.atlas, bg_spec.file = nil, file
		bg_spec.file_w, bg_spec.file_h = self.bg_w or A.BG_FILE_W, self.bg_h or A.BG_FILE_H
	else
		bg_spec.atlas, bg_spec.file, bg_spec.file_w, bg_spec.file_h = self.bg_atlas, nil, nil, nil
	end
	bg_spec.color = self.bg_color
	local ok = pcall(A.cover, win.enemy_bg, bg_spec, win.enemy_panel_w, win.panel_h, A.BG_TINT_ENEMY)
	if ok and file ~= nil then
		-- A file the client cannot load leaves the texture empty: fall back to the atlas.
		local get = win.enemy_bg.GetTexture
		if type(get) == "function" then
			local okg, tex = pcall(get, win.enemy_bg)
			if okg and tex == nil then ok = false end
		end
	end
	if not ok and file ~= nil then
		bg_spec.atlas, bg_spec.file, bg_spec.file_w, bg_spec.file_h = self.bg_atlas, nil, nil, nil
	end
	A.cover(win.enemy_bg, bg_spec, win.enemy_panel_w, win.panel_h, A.BG_TINT_ENEMY)
	A.cover(win.board_bg, bg_spec, win.board_panel_w, win.panel_h, A.BG_TINT_BOARD)
end

-- Dev (/dcbg, debug panel): next (dir = 1, default) or previous (-1) background of the A.BG_LIST
-- shortlist for both panels; returns its name and FileDataID.
function FightView:cycle_bg(dir)
	local list = A.BG_LIST
	local n = #list
	dir = dir or 1
	local i = ((self.bg_index or (dir < 0 and 1 or 0)) + dir - 1) % n + 1
	self.bg_index = i
	self.bg_name = list[i].name
	self.bg_file = list[i].id
	self.bg_w, self.bg_h = list[i].w, list[i].h
	self:_apply_bg()
	return self.bg_name, self.bg_file
end

-- Hide transient elements (bind / reset).
function FightView:_reset_view()
	self.banner_t0, self.flash_t0, self.vig_t0, self.hit_t0, self.death_t0 = nil, nil, nil, nil, nil
	self.cleared_t0 = nil
	self.phase_t0, self.msg_t0, self.junk_t0 = nil, nil, nil
	self.cast_t0 = nil
	self.vig_dur, self.vig_peak, self.knock_t0, self.reflect_t = VIGNETTE_TIME, 1, nil, nil
	self.origin_x, self.origin_y = (self.juice.board_w or 512) / 2, (self.juice.board_h or 512) / 2
	self.proj_type, self.proj_weight = nil, 1
	self:_set_knock(0)
	set_alpha(self.cast_glow, 0)
	self.hit_fx = false
	self.anim_cur, self.anim_temp, self.anim_until, self.wound_next = 0, nil, 0, -1
	set_alpha(self.phase_banner, 0)
	set_alpha(self.mirror_msg, 0)
	set_shown(self.sand_tint, false)
	set_shown(self.junk_tint, false)
	set_shown(self.aegis_glow, false)
	set_shown(self.mirror_glow, false)
	set_shown(self.aegis_icon, false)
	set_shown(self.mirror_icon, false)
	set_shown(self.crack_bar, false)
	set_alpha(self.banner, 0)
	set_alpha(self.flash_text, 0)
	set_alpha(self.cleared, 0)
	set_alpha(self.vignette, 0)
	set_alpha(self.enemy_holder, 1)
	set_alpha(self.hit_glow, 0)
	self.punch = 1
	self.enemy_holder:SetSize(ENEMY_SIZE_W, ENEMY_SIZE_H)
	for _, pool in ipairs({ self.pops_enemy, self.pops_player, self.pops_match }) do
		for i = 1, #pool do
			pool[i].t0 = nil
			pool[i]:Hide()
		end
	end
	self.cyc_last = -1
	self.li1, self.li2, self.li3 = false, false, false
	self.score_t0, self.score_shown = nil, nil
	self:halt()
end

---------------------------------------------------------------- binding

local HANDLER_ORDER = {
	"ability_triggered", "fight_started", "enemy_defeated", "enemy_damaged", "enemy_windup",
	"player_damaged", "player_healed", "attack_blocked", "attack_reflected", "heal_blocked",
	"gems_cleared", "swap_rejected", "swap_accepted", "run_lost", "enemy_phase_changed", "enemy_mirror_changed", "enemy_immune",
	"junk_spawned", "match_resolved", "ability_gem_spawned", "enemy_ability_executed", "score_awarded",
}

function FightView:bind(combat)
	self:unbind()
	self.combat = combat
	for i = 1, #HANDLER_ORDER do
		local name = HANDLER_ORDER[i]
		combat:on(name, self._h[name])
	end
	self.boardfx:bind(combat.sim)
	self:_reset_view()
	local st = combat:hud_state(self.state)
	self.score_from, self.score_to, self.score_shown = st.score, st.score, nil
	if combat.enemy ~= nil then self:_show_enemy(combat.enemy.def.display) end
	self:update()
end

function FightView:unbind()
	self.boardfx:unbind()
	local combat = self.combat
	if combat ~= nil then
		for i = 1, #HANDLER_ORDER do
			local name = HANDLER_ORDER[i]
			combat:off(name, self._h[name])
		end
	end
	self.combat = nil
end

local function now_of(self)
	local c = self.combat
	return c ~= nil and c.sim.now or 0
end

function FightView:_now()
	return now_of(self)
end

-- Window shown again: models set while hidden may not render, re-apply.
function FightView:on_show()
	local key = self.enemy_key
	self.enemy_key = nil
	if key ~= nil then self:_show_enemy(key) end
	self:halt()
end

-- Stop wall-clock widgets (the queue's Cooldown); the next update re-syncs them to sim time.
function FightView:freeze()
	local cd = self.cooldown
	if cd ~= nil and self.cd_start ~= nil then cd:SetCooldown(0, 0) end
	self.cd_start, self.cd_dur = nil, nil
end

-- Soft pause / error / game over / hide / menu / reset: freeze + hide every effect model and stop long
-- sounds (both run on engine time and would play on while the sim is frozen). The next update brings
-- the status effects back. (freeze() alone is also called every frame while the enemy is held.)
function FightView:halt()
	self:freeze()
	self.fx:stop_all()
	self.juice:halt()
	self.boardfx:halt()
	self.hitfx:halt()
	if self.on_halt ~= nil then self.on_halt() end -- the board view hides its auras / dragged halo (set by ui/main.lua)
	A.stop_sounds()
end

---------------------------------------------------------------- enemy

local function model_call(model, method, a, b, c)
	local fn = model[method]
	if fn == nil then return false end
	return (pcall(fn, model, a, b, c))
end

-- Model framing from the enemy entry over A.MODEL_DEFAULT (each call guarded;
-- a missing method just leaves the engine default). Also used by /dcbg cam.
function FightView:_frame_model(e)
	local model, d = self.model, A.MODEL_DEFAULT
	local pos = e.pos or d.pos
	model_call(model, "SetCamDistanceScale", e.cam_scale or d.cam_scale)
	model_call(model, "SetPosition", pos[1], pos[2], pos[3])
	model_call(model, "SetRotation", e.rot or d.rot)
	model_call(model, "SetModelScale", e.scale or d.scale)
	if e.portrait_zoom ~= nil then model_call(model, "SetPortraitZoom", e.portrait_zoom) end
end

-- Re-frames the current enemy's model from its Assets.ENEMY entry (debug panel: after editing the
-- table). Returns true when a model is showing.
function FightView:reframe()
	if self.enemy_mode ~= "model" then return false end
	-- Reload the model and frame it exactly like a fresh fight start: incremental setters on a model that is
	-- already framed did not match what a /reload showed (playtest 5: tuning preview != result after reload).
	local key = self.enemy_key
	self.enemy_key = nil
	self:_show_enemy(key)
	return true
end

-- Creature display ID (textured) first, then the model FileDataID (a model the client cannot load
-- reports file ID nil / 0; renders untextured), else the portrait icon (W0-P3.1).
function FightView:_show_enemy(key)
	if key == self.enemy_key then return end
	self.enemy_key = key
	local e = A.ENEMY[key] or A.ENEMY_DEFAULT
	local model = self.model
	local mode = "portrait"
	if model ~= nil and (e.display_id ~= nil or e.model_id ~= nil) then
		model:Show()
		model_call(model, "ClearModel") -- a display that fails to load must not leave the previous enemy showing
		local shown = false
		if e.display_id ~= nil and model_call(model, "SetDisplayInfo", e.display_id) then shown = true end
		if not shown and e.model_id ~= nil and model_call(model, "SetModel", e.model_id) then
			shown = true
			local get = model.GetModelFileID
			if type(get) == "function" then
				local okg, fid = pcall(get, model)
				if okg and (fid == nil or fid == 0) then shown = false end
			end
		end
		if shown then
			mode = "model"
			model_call(model, "SetAnimation", A.ANIM.stand) -- stand / idle
			self.anim_cur, self.anim_temp = A.ANIM.stand, nil
			self:_frame_model(e)
			self.reframe_n = 300
		end
	end
	self.enemy_mode = mode
	if mode == "model" then
		self.portrait:Hide()
		self.portrait_ring:Hide()
	else
		if model ~= nil then model:Hide() end
		set_texture(self.portrait, A.ICON_DIR .. (e.portrait or A.ENEMY_DEFAULT.portrait))
		self.portrait:Show()
		if self.has_portrait_ring then self.portrait_ring:Show() end
	end
end

function FightView:_on_fight_started(enemy)
	self.cleared_t0, self.death_t0, self.hit_t0 = nil, nil, nil
	self.phase_t0, self.msg_t0 = nil, nil
	self.cast_t0 = nil
	self.anim_temp = nil
	set_alpha(self.cleared, 0)
	set_alpha(self.enemy_holder, 1)
	self.cyc_last = -1
	if enemy ~= nil and enemy.def ~= nil then self:_show_enemy(enemy.def.display) end
	self.hitfx:enter(now_of(self)) -- W0-P8: slide / fade in, ring at the feet, name punch
end

-- The creature sound file `field` (attack_sound / death_sound) of the current enemy def.
local function creature_sound(self, slot, field)
	local c = self.combat
	local e = c ~= nil and c.enemy or nil
	local def = e ~= nil and e.def or nil
	local file = def ~= nil and def[field] or nil
	if file ~= nil then A.play(slot, file) end
end

function FightView:_on_enemy_defeated()
	local now = now_of(self)
	self.cleared_t0 = now
	self.death_t0 = now
	creature_sound(self, "enemy_death", "death_sound")
	A.play("cleared")
	self.juice:add_trauma(TRAUMA_CLEARED)
	local c = self.combat
	local def = c ~= nil and c.enemy ~= nil and c.enemy.def or nil
	self.hitfx:death(def ~= nil and def.is_boss == true, now) -- W0-P8: motes, flash, ring (boss: more)
end

-- The enemy winds up its next attack: attack animation + creature sound (the hit lands after `windup`).
function FightView:_on_windup(ability, windup)
	local now = now_of(self)
	self.hitfx:windup(ability, windup, now) -- W0-P8: glow + vignette in the intent colour
	self.anim_temp = A.ANIM.attack
	self.anim_until = now + (windup or 0) + A.ANIM.attack_tail
	creature_sound(self, "enemy_attack", "attack_sound")
end

-- kind (W0-P8): nil / "crit" / "heal" / "player"; power = 0..1 hit size (player hits).
function FightView:_spawn_pop(pool, text, c, x, y, big, kind, power)
	local fs = pool[pool.next]
	pool.next = pool.next % #pool + 1
	fs:SetFontObject(big and A.FONT_POP_BIG or A.FONT_POP)
	fs:SetText(text)
	fs:SetTextColor(c[1], c[2], c[3], c[4])
	fs.x0, fs.y0, fs.ly = x, y, nil
	fs.t0 = now_of(self)
	fs:SetAlpha(1)
	fs.lalpha = 1
	fs:SetPoint("CENTER", pool.parent, "CENTER", x, y)
	fs:Show()
	self.hitfx:pop_start(pool, fs, kind, power, big, fs.t0)
end

-- The player's damage reaches the enemy: a streak from the match / ability cell (colour by gem, thicker for an
-- ability), the reaction (_enemy_hit) runs when it lands. Without a juice layer the reaction is immediate.
function FightView:_on_enemy_damaged(amount, boosted)
	local juice = self.juice
	if juice == ns.Juice.NONE then
		self:_enemy_hit(amount, boosted)
		return
	end
	local C = A.COLOR
	local x0, y0, w = self.origin_x, self.origin_y, self.proj_weight
	local c = C.GEM_FX[self.proj_type] or C.PROJ_DEFAULT
	if self.reflect_t == now_of(self) then -- the Fire Shield's returned hit flies from the player (same sim instant)
		x0, y0, w, c = juice.px, juice.py, 1.2, C.PROJ_REFLECT
		self.reflect_t = nil
	end
	juice:projectile(x0, y0, juice.ex, juice.ey, w, c[1], c[2], c[3], ns.Juice.HIT_ENEMY, amount, boosted and 1 or 0)
end

function FightView:_on_juice_hit(kind, a, b)
	if kind == ns.Juice.HIT_ENEMY then self:_enemy_hit(a, b == 1) end
end

-- Hit reaction on the enemy (at the streak's arrival): effect model / red disc, wound animation, knock-back, number.
function FightView:_enemy_hit(amount, boosted)
	local now = now_of(self)
	self.hit_t0 = now
	self.knock_t0 = now
	-- hit effect model replaces the red disc (the disc stays when no effect frame can show)
	self.hit_fx = self.fx:play("enemy_hit", nil, nil, now) ~= false -- nil = throttled (last one still showing)
	-- wound: animation (not over an attack in progress), throttled. No creature wound sound (W0-P3.1).
	if now >= self.wound_next then
		self.wound_next = now + A.ANIM.wound_gap
		if self.anim_temp ~= A.ANIM.attack or now >= self.anim_until then
			self.anim_temp = A.ANIM.wound
			self.anim_until = now + A.ANIM.wound_time
		end
	end
	local j = self.jitter_i % #JITTER + 1
	self.jitter_i = j
	local C = A.COLOR
	self:_spawn_pop(self.pops_enemy, "-" .. tostring(amount), boosted and C.POP_BOOSTED or C.POP_ENEMY,
		ENEMY_X + JITTER[j], -20, boosted, boosted and "crit" or nil)
end

function FightView:_pop_player(text, c, kind, power)
	-- above the player HP bar (bottom-left of the board)
	self:_spawn_pop(self.pops_player, text, c, 60, -232, false, kind, power)
end

function FightView:_on_player_damaged(amount, source)
	self:_flash_vignette(A.COLOR.VIGNETTE, 1, VIGNETTE_TIME)
	local c = self.combat
	local maxhp = c ~= nil and c.player_max_health or 0
	local frac = maxhp > 0 and amount / maxhp or 0
	if frac > HIT_FULL then frac = HIT_FULL end
	self.juice:add_trauma(TRAUMA_HIT_MIN + (TRAUMA_HIT_MAX - TRAUMA_HIT_MIN) * frac / HIT_FULL)
	if source == "mirror" then self:_streak_to_player(A.COLOR.PROJ_MIRROR, 1.3, true) end
	-- Mirror Shield true damage says where it came from.
	local text = source == "mirror" and ("-" .. tostring(amount) .. " mirror") or ("-" .. tostring(amount))
	self:_pop_player(text, A.COLOR.POP_PLAYER, "player", frac / HIT_FULL)
	A.play("player_hit")
end

-- Short text on the enemy ("Immune", "Mirror!").
function FightView:_pop_enemy_text(text, c)
	local j = self.jitter_i % #JITTER + 1
	self.jitter_i = j
	self:_spawn_pop(self.pops_enemy, text, c, ENEMY_X + JITTER[j], 40, false)
end

-- HP-threshold rotation swap: banner with the phase name.
function FightView:_on_phase(label)
	set_text(self.phase_banner.title, upper(label or ""))
	self.phase_t0 = now_of(self)
	A.play("ult")
	self.hitfx:phase(self.phase_t0) -- W0-P8: ring, trauma, cast flash, name punch
end

-- Mirror Shield up / gone (broken = shattered by matches, else it expired).
function FightView:_on_mirror(active, broken)
	local now = now_of(self)
	local jc, mc = self.juice, A.COLOR.PROJ_MIRROR
	if active then
		self:_pop_enemy_text("Mirror!", A.COLOR.MIRROR_GLOW)
		jc:impact(jc.ex or 0, jc.ey or 0, 1, mc[1], mc[2], mc[3])
	elseif broken then
		self.msg_t0 = now
		A.play("ability")
		jc:add_trauma(TRAUMA_MIRROR)
		jc:impact(jc.ex or 0, jc.ey or 0, 1.4, mc[1], mc[2], mc[3])
		self:_flash_vignette(A.COLOR.VIG_MIRROR, VIG_PEAK_MIRROR, VIG_FLASH_TIME)
		self.knock_t0 = now
	end
end

-- Bandage junk was put on the board.
function FightView:_on_junk()
	self.junk_t0 = now_of(self)
end

-- The run's label ("STAGE 2-1") and stage (background art); called before each fight starts.
function FightView:set_run_label(label, stage)
	self.run_label = stage_line(label, stage)
	self:set_stage(stage)
	self.lphase = ""
	set_text(self.stage_text, self.run_label)
end

-- The ability banner: icon texture path, title, blurb; enemy = red title (enemy special cast), else gold.
function FightView:_show_banner(icon_path, title, blurb, enemy)
	local bn = self.banner
	set_texture(bn.icon, icon_path)
	set_text(bn.title, title or "")
	set_text(bn.blurb, blurb or "")
	text_color(bn.title, enemy and A.COLOR.BANNER_TITLE_ENEMY or A.COLOR.BANNER_TITLE)
	self.banner_t0 = now_of(self)
end

function FightView:_on_ability(info)
	local now = now_of(self)
	-- juice: the damage that follows flies from the gem's cell, thicker for an ult; flash + shake by tier
	local tier = info.tier or 0
	if info.col ~= nil and info.row ~= nil then self.origin_x, self.origin_y = ns.Juice.cell_xy(info.col, info.row) end
	self.proj_type = info.gem_type
	if tier == 2 then
		self.proj_weight = WEIGHT_ULT
		self:_flash_vignette(A.COLOR.VIG_ULT, VIG_PEAK_ULT, VIG_FLASH_TIME)
		self.juice:add_trauma(TRAUMA_ULT)
	elseif info.is_bomb then
		self.proj_weight = WEIGHT_BOMB
		self:_flash_vignette(A.COLOR.VIG_SKILL, VIG_PEAK_SKILL, VIG_FLASH_TIME)
		self.juice:add_trauma(TRAUMA_BOMB)
	else
		self.proj_weight = tier == 1 and WEIGHT_SKILL or WEIGHT_BOMB
		self:_flash_vignette(A.COLOR.VIG_SKILL, VIG_PEAK_SKILL, VIG_FLASH_TIME)
		self.juice:add_trauma(TRAUMA_SKILL)
	end
	-- W0-P7: board light, the colour's signature at the gem and (damage abilities) on the enemy when the hit lands
	local bf, jc = self.boardfx, self.juice
	bf:set_cast(info.gem_type)
	bf:light(info.gem_type, tier == 2 and 2 or 1)
	if info.gem_type ~= nil then
		local w = tier == 2 and 2 or 1
		jc:signature(info.gem_type, self.origin_x, self.origin_y, w, 0)
		if not info.is_bomb and jc.ex ~= nil then jc:signature(info.gem_type, jc.ex, jc.ey, w, ns.Juice.FLY) end
	end
	self:_show_banner(A.icon(info.icon), info.toast, info.blurb, false)
	-- the ability's own sound (by id); bombs / abilities without one keep the generic skill / ult sound
	local own = A.ABILITY_KEY[info.id]
	if own ~= nil then
		A.play(own)
	elseif info.is_bomb or info.tier == 2 then
		A.play("ult")
	else
		A.play("ability")
	end
	self.fx:play(info.id, info.col, info.row, now) -- spell effect (nil id / bomb: no entry, nothing)
end

-- Board float at a cell (cell units, 0-based, may be fractional): pool = pops_match.
function FightView:_board_float(text, c, col, row)
	local cell = ns.BoardView.CELL
	local half = BOARD_COLS * cell / 2 -- square board
	self:_spawn_pop(self.pops_match, text, c, (col + 0.5) * cell - half, half - (row + 0.5) * cell, false)
end

-- A match resolved (one per region): text float at its centre ("MATCH" / "4-MATCH", + points) and a sound by
-- length. The per-wave gem_break stays. WoW has no pitch, so the cascade depth only picks a different slot:
-- a 3-match inside a chain (depth >= 2) plays match_cascade, longer matches their own length slot.
function FightView:_on_match(length, gems, depth, dcol, drow)
	local n = gems ~= nil and #gems or 0
	local cx, cy = 3.5, 3.5
	if n > 0 then
		cx, cy = 0, 0
		for i = 1, n do
			cx = cx + gems[i].x
			cy = cy + gems[i].y
		end
		cx, cy = cx / n, cy / n
	end
	-- juice: the gems converge on (dcol, drow) (core payload; the centre when absent) and break there when they
	-- arrive; the damage of this wave flies from the match centre in the gem's colour; 4+ shakes the window.
	local jc = self.juice
	self.origin_x, self.origin_y = ns.Juice.cell_xy(cx, cy)
	local g1 = n > 0 and gems[1] or nil
	local gtype = g1 ~= nil and g1.type or nil
	self.proj_type, self.proj_weight = gtype, 1
	local bx, by = ns.Juice.cell_xy(dcol or cx, drow or cy)
	depth = depth or 1
	jc:match_break(length, bx, by, gtype, ns.Timings.FUSE, depth)
	-- chain escalation (W0-P7 B2): the combo meter, a little more trauma per depth, a gold vignette from depth 4
	self.boardfx:combo(depth)
	local _, _, _, trauma_add, vig_peak = ns.Juice.chain_scale(depth)
	local trauma = 0
	if length >= 4 then
		local t = (length - 3) / 4
		if t > 1 then t = 1 end
		trauma = TRAUMA_MATCH_MIN + (TRAUMA_MATCH_MAX - TRAUMA_MATCH_MIN) * t
	end
	trauma = trauma + trauma_add
	if trauma > TRAUMA_MATCH_MAX then trauma = TRAUMA_MATCH_MAX end
	if trauma > 0 then jc:add_trauma(trauma) end
	if vig_peak > 0 and self.vig_t0 == nil then self:_flash_vignette(A.COLOR.VIG_COMBO, vig_peak, VIG_FLASH_TIME) end
	local pts = ns.Combat.match_score(length)
	local title = length <= 3 and "MATCH" or (tostring(length) .. "-MATCH")
	self:_board_float(title .. "\n|cffffeb59+" .. tostring(pts) .. "|r", A.COLOR.MATCH_TEXT, cx, cy)
	-- sounds (playtest 5): every match plays the same base sound, the length / cascade / double-match sounds
	-- stack on top of it at the same instant (no replacing).
	A.play("gem_break")
	A.play("gem_break_holy")
	if length >= 7 then
		A.play("match_7")
	elseif length == 6 then
		A.play("match_6")
	elseif length == 5 then
		A.play("match_5")
	elseif length == 4 then
		A.play("match_4")
	end
	local t = now_of(self)
	if depth >= 2 or self.match_t == t then A.play("match_cascade") end -- chain, or a 2nd match in the same pass
	self.match_t = t
	-- one light streak per destroyed gem to the enemy, leaving when the gems break
	if jc.ex ~= nil then
		local c = A.COLOR.GEM_FX[gtype] or A.COLOR.PROJ_DEFAULT
		for i = 1, n do
			local gx, gy = ns.Juice.cell_xy(gems[i].x, gems[i].y)
			jc:volley(t + ns.Timings.FUSE + (i - 1) * 0.025, gx, gy, jc.ex, jc.ey, c[1], c[2], c[3])
		end
	end
end

-- The sim put an ability gem on the board (a fused 4+ match, or a dev spawn): float with the ability's name,
-- spawn sound; an ult also shows the banner "<NAME> READY".
function FightView:_on_gem_spawned(col, row, tier, gem_type)
	local combat = self.combat
	local ability = combat ~= nil and combat.kit:get(gem_type, tier) or nil
	local name = ability ~= nil and upper(ability.name) or (tier == 2 and "ULT" or "SKILL")
	self:_board_float(name, A.COLOR.SPAWN_TEXT, col, row)
	self.juice:spawn_fx(col, row, tier)
	self.origin_x, self.origin_y = ns.Juice.cell_xy(col, row)
	if tier == 2 then
		A.play("ability_spawn_ult")
		self:_show_banner(A.icon(ability ~= nil and ability.icon or nil), name .. " READY",
			"Swap it with a gem of the same colour", false)
	else
		A.play("ability_spawn_skill")
	end
end

-- An enemy ability lands (enemy_ability_executed): flash over the figure; a special one also gets the banner
-- (its icon + name + description) and a sound. Plain hits stay quiet here (player_hit plays on the damage).
function FightView:_on_enemy_cast(ability)
	self.cast_t0 = now_of(self)
	-- streak enemy -> player HP bar (junk: the board's right edge); boss casts are chunkier, a curse is purple
	local jc, C = self.juice, A.COLOR
	local c = self.combat
	local e = c ~= nil and c.enemy or nil
	local boss = e ~= nil and e.def ~= nil and e.def.is_boss
	local col, tx, ty = C.PROJ_ENEMY, jc.px, jc.py
	local kind = ability ~= nil and ability.kind or nil
	if kind == "curse" then
		col = C.PROJ_CURSE
	elseif kind == "junk" then
		col, tx, ty = C.PROJ_JUNK, jc.jx, jc.jy
	end
	if tx ~= nil then jc:projectile(jc.ex, jc.ey, tx, ty, boss and 1.6 or 1.15, col[1], col[2], col[3], ns.Juice.HIT_NONE) end
	if ability ~= nil and ability.is_special then
		self:_show_banner(A.intent_icon(ability), upper(ability.name or ""), ability.description, true)
		A.play("enemy_special")
	end
end

-- A streak from the last match / ability cell to the player HP bar (heal) or from the enemy (Mirror bounce).
function FightView:_streak_to_player(c, weight, from_enemy)
	local jc = self.juice
	if jc.px == nil then return end
	local x0, y0 = self.origin_x, self.origin_y
	if from_enemy then x0, y0 = jc.ex, jc.ey end
	jc:projectile(x0, y0, jc.px, jc.py, weight, c[1], c[2], c[3], ns.Juice.HIT_NONE)
end

-- Fire Shield: orange flash, and the enemy_damaged right after it flies from the player (reflect_t = same sim instant).
function FightView:_on_reflect()
	self.reflect_t = now_of(self)
	self:_flash_vignette(A.COLOR.VIG_REFLECT, VIG_PEAK_REFLECT, 0.2)
end

-- Colour vignette flash: edges recoloured only when the colour changes; peak scales the frame alpha.
function FightView:_flash_vignette(c, peak, dur)
	if self.vig_color ~= c then
		self.vig_color = c
		local edges = self.vig_edges
		for i = 1, #edges do edges[i].tex:SetColorTexture(c[1], c[2], c[3], c[4] * edges[i].a) end
	end
	self.vig_t0, self.vig_peak, self.vig_dur = now_of(self), peak, dur
end

-- Enemy knock-back offset (px right) of the figure's frame.
function FightView:_set_knock(x, y)
	y = y or 0
	if x ~= self.knock_x or y ~= self.knock_y then
		self.knock_x, self.knock_y = x, y
		self.enemy_holder:SetPoint("CENTER", self.enemy_ep, "CENTER", x, y)
	end
end

-- The board view reports a landed gem / a rejected swap (ui/main.lua wires BoardView.on_land / on_reject).
function FightView:on_land(col, row)
	self.juice:land_dust(col, row)
end

function FightView:on_reject(c1, r1, c2, r2)
	local jc = self.juice
	jc:reject_puff(c1, r1)
	jc:reject_puff(c2, r2)
end

-- Dev (debug panel): one board effect (BoardFx.DEV_KINDS) now. Returns true when played.
function FightView:dev_boardfx(kind)
	return self.boardfx:dev(kind) == true
end

-- Dev (debug panel): one juice effect now; "cast" = an enemy cast streak. Returns true when played.
function FightView:dev_juice(kind)
	local jc = self.juice
	if kind == "cast" then
		if jc.px == nil then return false end
		local c = A.COLOR.PROJ_ENEMY
		jc:projectile(jc.ex, jc.ey, jc.px, jc.py, 1.15, c[1], c[2], c[3], ns.Juice.HIT_NONE)
		return true
	end
	jc.now = now_of(self)
	return jc:dev(kind) == true
end

-- Dev (debug panel): one hit / status effect now (HitFx.DEV_BUTTONS). Returns true when played.
function FightView:dev_hitfx(kind)
	return self.hitfx:dev(kind, now_of(self)) == true
end

function FightView:set_shake(on)
	self.juice:set_shake(on)
end

-- Short feedback over the board (e.g. a swap rejected while stunned).
function FightView:flash(text)
	set_text(self.flash_text, text)
	self.flash_t0 = now_of(self)
end

---------------------------------------------------------------- per frame

function FightView:_update_header(st)
	local phase = st.enemy_phase_name or ""
	if phase ~= self.lphase then
		self.lphase = phase
		if phase == "" then
			set_text(self.stage_text, self.run_label)
		else
			set_text(self.stage_text, self.run_label .. "  -  " .. upper(phase))
		end
	end
	local name = st.enemy_name
	if name ~= self.lname then
		self.lname = name
		set_text(self.name_text, upper(name))
	end
	local weak = st.enemy_weak_to
	if weak ~= self.lweak then
		self.lweak = weak
		local cname = ns.Combat.COLOR_NAMES[weak]
		if cname ~= nil then
			A.apply_gem(self.weak_icon, weak)
			set_text(self.weak_name, upper(cname))
			self.weak_icon:Show()
			self.weak_label:Show()
		else
			set_text(self.weak_name, "")
			self.weak_icon:Hide()
			self.weak_label:Hide()
		end
	end
end

function FightView:_update_intents(st)
	local intents = st.intents
	local a, b, c = intents[1], intents[2], intents[3]
	if a == self.li1 and b == self.li2 and c == self.li3 then return end
	self.li1, self.li2, self.li3 = a, b, c
	local C = A.COLOR
	for i = 1, 3 do
		local s = self.slots[i]
		local e = intents[i]
		if e == nil then
			set_shown(s, false)
		else
			set_texture(s.icon, A.intent_icon(e))
			set_color(s.disc, e.is_special and C.SLOT_DISC_SPECIAL or C.SLOT_DISC)
			if s.has_ring then
				local rc = e.is_special and C.SLOT_RING_SPECIAL
				if rc then s.ring:SetVertexColor(rc[1], rc[2], rc[3]) else s.ring:SetVertexColor(1, 1, 1) end
			end
			set_shown(s, true)
		end
	end
end

-- Slot 1 timer: Cooldown sweep over the attack cycle (incl. the wind-up),
-- "NOW!" pulse while winding up, STUNNED / FROZEN while the enemy is held.
function FightView:_update_timer(st, now)
	local C = A.COLOR
	local s1 = self.slots[1]
	local kind = st.enemy_stun_kind
	local t = st.enemy_next_hit
	if kind ~= "" or t < 0 or st.fight_over or st.game_over then
		self:freeze()
		self.cyc_last = -1
		set_shown(s1.now, false)
		local desat = kind ~= ""
		if s1.ldesat ~= desat then
			s1.ldesat = desat
			s1.icon:SetDesaturated(desat)
		end
		if kind ~= "" then
			set_text(self.q_timer, kind == "freeze" and "FROZEN" or "STUNNED")
			text_color(self.q_timer, C.ATTACK_STUN)
		else
			set_text(self.q_timer, "")
		end
		return
	end
	if s1.ldesat then
		s1.ldesat = false
		s1.icon:SetDesaturated(false)
	end
	-- A new cycle (the countdown jumped up) sets the sweep's span.
	if t > self.cyc_last + 1e-6 then self.cyc_max = t end
	self.cyc_last = t
	local cd = self.cooldown
	if cd ~= nil then
		local start = GetTime() - (self.cyc_max - t)
		if self.cd_start == nil or self.cd_dur ~= self.cyc_max or abs(start - self.cd_start) > COOLDOWN_RESYNC then
			self.cd_start, self.cd_dur = start, self.cyc_max
			cd:SetCooldown(start, self.cyc_max)
		end
	end
	if st.enemy_winding_up then
		set_text(self.q_timer, "NOW!")
		text_color(self.q_timer, C.TEXT_WARN)
		set_shown(s1.now, true)
		set_alpha(s1.now, q20(0.45 + 0.55 * abs(sin(now * NOW_PULSE))))
	else
		set_text(self.q_timer, secs(t))
		text_color(self.q_timer, C.TEXT_DIM)
		set_shown(s1.now, false)
	end
end

-- Status icon value: seconds (timed) or stacks (shield); -1 = hidden.
local function timed_icon(s, remaining, maxv)
	local w = -1
	if remaining > 0 then w = ceil(remaining - 1e-6) end
	if w ~= s.lwhole then
		s.lwhole = w
		if w >= 0 then set_text(s.num, whole(w)) end
	end
	if w >= 0 then status_dim(s, remaining, maxv) end
	return w >= 0
end

function FightView:_update_statuses(st)
	local s = st.statuses
	local changed = false
	for i = 1, #PLAYER_STATUS do
		local id = PLAYER_STATUS[i]
		local icon = self.status[id]
		local on
		if id == "shield" then
			local stacks = s.shield or 0
			on = stacks > 0
			if stacks ~= icon.lwhole then
				icon.lwhole = stacks
				if on then set_text(icon.num, whole(stacks)) end
			end
		elseif id == "sandstorm" then
			on = timed_icon(icon, st.sand_remaining, st.sand_max)
		else
			local e = s[id]
			on = e ~= nil and timed_icon(icon, e.remaining, e.max)
		end
		if on ~= icon.lshown then
			set_shown(icon, on)
			changed = true
		end
	end
	if changed or self.status_layout_dirty then
		self.status_layout_dirty = false
		local x = 2
		for i = 1, #PLAYER_STATUS do
			local icon = self.status[PLAYER_STATUS[i]]
			if icon.lshown then
				local hf = self.hitfx
				if hf.layout ~= nil then
					hf:layout(icon, x, now_of(self)) -- slides to the new slot (W0-P8)
				else
					icon:SetPoint("CENTER", self.win.bottom, "LEFT", x + STATUS_SIZE / 2, 0)
				end
				x = x + STATUS_SIZE + STATUS_GAP
			end
		end
	end
end

function FightView:_update_enemy_status(st)
	local kind = st.enemy_stun_kind
	local stun = self.enemy_stun
	-- stun stars / freeze model on the enemy while held (not on a dead enemy)
	local held = kind ~= "" and st.enemy_stun_remaining > 0 and not (st.fight_over or st.game_over)
	self.fx:hold("stun", held and kind == "stun")
	self.fx:hold("freeze", held and kind == "freeze")
	if kind ~= "" and st.enemy_stun_remaining > 0 then
		set_texture(stun.icon, A.icon(kind == "freeze" and "enemy_freeze" or "enemy_stun"))
		timed_icon(stun, st.enemy_stun_remaining, st.enemy_stun_max)
		set_shown(stun, true)
	else
		set_shown(stun, false)
	end
	local slow = self.enemy_slow
	if st.enemy_slow_remaining > 0 then
		timed_icon(slow, st.enemy_slow_remaining, st.enemy_slow_max)
		set_shown(slow, true)
	else
		set_shown(slow, false)
	end
end

-- Divine Aegis (gold glow + icon with seconds) and Mirror Shield (silver glow + icon + crack
-- bar that fills as matches hit it) over the enemy. No allocation: strings come from caches.
function FightView:_update_enemy_effects(st, now)
	local ended = st.fight_over or st.game_over -- the dead enemy's shields are gone from the screen
	local ar = ended and 0 or st.enemy_aegis_remaining
	self.fx:hold("aegis", ar > 0)
	if ar > 0 then
		timed_icon(self.aegis_icon, ar, st.enemy_aegis_max)
		set_shown(self.aegis_icon, true)
		set_shown(self.aegis_glow, true)
		set_alpha(self.aegis_glow, q20(0.22 + 0.1 * sin(now * 4)))
	else
		set_shown(self.aegis_icon, false)
		set_shown(self.aegis_glow, false)
	end
	local mr = ended and 0 or st.enemy_mirror_remaining
	self.fx:hold("mirror", mr > 0)
	if mr > 0 then
		timed_icon(self.mirror_icon, mr, st.enemy_mirror_max)
		set_shown(self.mirror_icon, true)
		set_shown(self.mirror_glow, true)
		set_alpha(self.mirror_glow, q20(0.18 + 0.08 * sin(now * 3)))
		local pct = floor(st.enemy_mirror_crack_ratio * 100 + 0.5)
		if pct > 100 then pct = 100 end
		bar_set(self.crack_bar, pct, 100)
		set_text(self.crack_bar.text, crack_cache[pct + 1])
		set_shown(self.crack_bar, true)
	else
		set_shown(self.mirror_icon, false)
		set_shown(self.mirror_glow, false)
		set_shown(self.crack_bar, false)
	end
end

-- Creature animation of the enemy model: death > stun pose > attack / wound (timed) > stand. Calls
-- SetAnimation only when the wanted animation changes; no allocation.
function FightView:_update_anim(st, now)
	if self.enemy_mode ~= "model" then return end
	local an = A.ANIM
	local want = an.stand
	if self.death_t0 ~= nil then
		want = an.death
	elseif st.enemy_stun_kind == "stun" and st.enemy_stun_remaining > 0 then
		want = an.stun
	elseif self.anim_temp ~= nil and now < self.anim_until then
		want = self.anim_temp
	end
	if want == self.anim_cur then return end
	self.anim_cur = want
	local model = self.model
	if not model_call(model, "SetAnimation", want) and want == an.attack then
		model_call(model, "SetAnimation", an.attack_alt) -- the model has no 1H attack: unarmed
	end
end

function FightView:_update_score(st, now)
	local score = st.score
	if score ~= self.score_to then
		local shown = self.score_shown or self.score_to
		self.score_from, self.score_to, self.score_t0 = shown, score, now
	end
	local v = self.score_to
	if self.score_t0 ~= nil then
		local k = (now - self.score_t0) / SCORE_COUNT
		if k >= 1 or k < 0 then
			self.score_t0 = nil
		else
			v = floor(self.score_from + (self.score_to - self.score_from) * k)
		end
	end
	if v ~= self.score_shown then
		self.score_shown = v
		set_text(self.score_text, tostring(v))
	end
end

local function update_pool(pool, now, hf)
	for i = 1, #pool do
		local fs = pool[i]
		local t0 = fs.t0
		if t0 ~= nil then
			local t = now - t0
			if t >= POP_TIME or t < 0 then
				fs.t0 = nil
				fs:Hide()
			else
				if hf.pop_frame ~= nil and not pool.plain then
					hf:pop_frame(fs, pool.parent, t) -- pop scale / shake / stack offset / heal speed (W0-P8)
				else
					local y = floor(fs.y0 + POP_RISE * t / POP_TIME + 0.5)
					if y ~= fs.ly then
						fs.ly = y
						fs:SetPoint("CENTER", pool.parent, "CENTER", fs.x0, y)
					end
				end
				local a = 1
				if t > POP_HOLD then a = q20(1 - (t - POP_HOLD) / (POP_TIME - POP_HOLD)) end
				set_alpha(fs, a)
			end
		end
	end
end

-- Sandstorm layer (fades out over its last second) and the junk flash over the board.
function FightView:_update_board_tints(st, now)
	local sr = st.sand_remaining
	if sr > 0 then
		set_shown(self.sand_tint, true)
		set_alpha(self.sand_tint, sr >= SAND_FADE and 1 or q20(sr / SAND_FADE))
	else
		set_shown(self.sand_tint, false)
	end
	local a = 0
	if self.junk_t0 ~= nil then
		a = q20(1 - (now - self.junk_t0) / JUNK_FLASH_TIME)
		if a <= 0 then self.junk_t0 = nil end
	end
	if a > 0 then
		set_shown(self.junk_tint, true)
		set_alpha(self.junk_tint, a)
	else
		set_shown(self.junk_tint, false)
	end
end

function FightView:_update_fx(now)
	local bn = self.banner
	-- phase banner / SHATTERED text
	local pa = fade_alpha(now, self.phase_t0, PHASE_IN, PHASE_HOLD, PHASE_FADE)
	set_alpha(self.phase_banner, pa)
	if pa == 0 and self.phase_t0 ~= nil and now - self.phase_t0 > PHASE_IN then self.phase_t0 = nil end
	pa = fade_alpha(now, self.msg_t0, 0, MSG_HOLD, MSG_FADE)
	set_alpha(self.mirror_msg, pa)
	if pa == 0 and self.msg_t0 ~= nil and now - self.msg_t0 > 0 then self.msg_t0 = nil end
	local a = fade_alpha(now, self.banner_t0, BANNER_IN, BANNER_HOLD, BANNER_FADE)
	set_alpha(bn, a)
	if a == 0 and self.banner_t0 ~= nil and now - self.banner_t0 > BANNER_IN then self.banner_t0 = nil end
	a = fade_alpha(now, self.flash_t0, 0, FLASH_HOLD, FLASH_FADE)
	set_alpha(self.flash_text, a)
	if a == 0 then self.flash_t0 = nil end
	-- vignette
	a = 0
	if self.vig_t0 ~= nil then
		a = q20(self.vig_peak * (1 - (now - self.vig_t0) / self.vig_dur))
		if a <= 0 then self.vig_t0 = nil end
	end
	set_alpha(self.vignette, a)
	-- enemy knock-back: out fast, back slower
	local kx = 0
	if self.knock_t0 ~= nil then
		local k = (now - self.knock_t0) / KNOCK_TIME
		if k >= 1 or k < 0 then
			self.knock_t0 = nil
		else
			local out = KNOCK_OUT / KNOCK_TIME
			kx = floor(KNOCK * (k < out and k / out or 1 - (k - out) / (1 - out)) + 0.5)
		end
	end
	local hf = self.hitfx
	local dx, dy, ea = 0, 0, 1
	-- death: the death animation plays, then the figure fades
	a = 1
	if self.death_t0 ~= nil then
		a = q20(1 - (now - self.death_t0 - A.ANIM.death_hold) / DEATH_FADE)
	end
	dx, dy, ea = hf:figure(now, a) -- entrance slide / fade + death drift (W0-P8)
	self:_set_knock(kx + dx, dy)
	-- enemy hit punch + glow
	local punch, glow = 1, 0
	if self.hit_t0 ~= nil then
		local k = (now - self.hit_t0) / HIT_TIME
		if k >= 1 or k < 0 then
			self.hit_t0 = nil
		else
			punch = 1 + floor(HIT_PUNCH * sin(pi * k) * 200 + 0.5) / 200
			glow = q20(1 - k)
		end
	end
	if punch ~= self.punch then
		self.punch = punch
		self.enemy_holder:SetSize(ENEMY_SIZE_W * punch, ENEMY_SIZE_H * punch)
	end
	set_alpha(self.hit_glow, self.hit_fx and 0 or glow) -- the hit effect model replaces the red disc
	-- enemy cast flash
	glow = 0
	if self.cast_t0 ~= nil then
		local k = (now - self.cast_t0) / CAST_TIME
		if k >= 1 or k < 0 then self.cast_t0 = nil else glow = q20(1 - k) end
	end
	set_alpha(self.cast_glow, glow)
	set_alpha(self.enemy_holder, ea < a and ea or a)
	-- CLEARED
	a = 0
	if self.cleared_t0 ~= nil then a = q20((now - self.cleared_t0) / CLEARED_IN) end
	set_alpha(self.cleared, a)
	update_pool(self.pops_enemy, now, hf)
	update_pool(self.pops_player, now, hf)
	update_pool(self.pops_match, now, hf)
end

function FightView:update()
	local combat = self.combat
	if combat == nil then return end
	local st = combat:hud_state(self.state)
	local now = combat.sim.now
	local C = A.COLOR

	local rn = self.reframe_n
	if rn ~= nil and rn > 0 then
		self.reframe_n = rn - 1
		if rn % 100 == 0 and self.enemy_mode == "model" then
			self:_frame_model(A.ENEMY[self.enemy_key] or A.ENEMY_DEFAULT)
		end
	end

	if st.has_enemy then
		self:_update_header(st)
		bar_set(self.enemy_bar, st.enemy_health, st.enemy_max_health)
		hp_text(self.enemy_hp, st.enemy_health > 0 and st.enemy_health or 0, st.enemy_max_health)
		self:_update_intents(st)
		self:_update_timer(st, now)
		self:_update_enemy_status(st)
		self:_update_enemy_effects(st, now)
		self:_update_anim(st, now)
	else
		self.fx:hold("stun", false)
		self.fx:hold("freeze", false)
		self.fx:hold("aegis", false)
		self.fx:hold("mirror", false)
	end
	self.fx:update(now)
	self.juice:update(now)
	self.boardfx:update(now)
	A.tick()
	self:_update_board_tints(st, now)

	-- player
	bar_set(self.player_bar, st.player_health, st.player_max_health)
	hp_text(self.player_hp, st.player_health, st.player_max_health)
	local s = st.statuses
	local pc = C.HP_PLAYER
	if st.player_stunned then
		pc = C.ATTACK_STUN
	elseif s.heal_block.remaining > 0 then
		pc = C.HP_HEAL_BLOCK
	elseif s.curse.remaining > 0 then
		pc = C.HP_CURSE
	end
	bar_color(self.player_bar, pc)
	self:_update_statuses(st)
	self.hitfx:update(st, now) -- chips, low HP, status pop / blink / aura, telegraph, figure timers (W0-P8)
	self:_update_score(st, now)
	self:_update_fx(now)
end

-- Dev command (W0-P2.1): /dcbg = next background (name + FileDataID printed in chat; the debug panel
-- has prev / next buttons),
-- /dcbg cam <scale> [x y z [rot]] = re-frame the enemy model live.
SLASH_DCBG1 = "/dcbg"
SlashCmdList.DCBG = function(msg)
	local hud = ns.App and ns.App.hud
	if hud == nil then return end
	local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	if cmd == "cam" and hud.model ~= nil then
		local sc, x, y, z, rot = rest:match("^(%S+)%s*(%S*)%s*(%S*)%s*(%S*)%s*(%S*)")
		local e = { cam_scale = tonumber(sc), pos = { tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0 }, rot = tonumber(rot) }
		hud:_frame_model(e)
		print("DragonChess: model cam " .. tostring(sc) .. " pos " .. tostring(x) .. "," .. tostring(y) .. "," .. tostring(z))
	else
		local name, id = hud:cycle_bg()
		print("DragonChess: background " .. name .. " (FileDataID " .. tostring(id) .. "; Assets: "
			.. A.format_bg(hud.stage, id, name) .. ")")
	end
end

ns.FightView = FightView
