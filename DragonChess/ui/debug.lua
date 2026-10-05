local addonName, ns = ...
-- Debug panel (W0-D1): one movable window that reaches any fight, status, board cheat, effect or sound
-- in a click (the model is Godot's scenes/debug/debug_cheats.gd: F1 kill ... F8 ult spawn + the debug
-- menu). Opened with `/dchess debug` (the first use enables it: DragonChessDB.debug.enabled; `/dchess
-- debug off` disables it again). Tabs: Fights, Board, Status, Effects, Sounds, Tuning, Live (W0-P5: status dump); a footer shows FPS and
-- the cost of one game frame (ms, smoothed + peak; ui/main.lua measures it while the panel is shown).
--
-- No game rules here: every game action calls ns.Debug (core/debug.lua), which marks the run as a dev
-- run (run.dev = true: no records, nothing saved; ui/main.lua checks it). Cosmetic actions (effects,
-- sounds, backgrounds, model framing) never touch the run. Effects obey pause (their models run on
-- engine time): they need the window shown and not paused, like /dcfx. Game actions also work while the
-- window is hidden or paused (the board / fight simply advances once it ticks again).
--
-- Tuning values (model framing, sound channels, backgrounds) are edited IN the Assets tables and printed
-- in copy-paste form (Assets.format_enemy / format_channels / format_bg). Every action prints one line
-- to the chat; errors are forwarded to the error handler and never swallowed.
--
-- Everything is created once on first open (no frames or tables per frame); the OnUpdate only runs
-- while the panel is shown, cuts finished sounds (Assets.tick, the HUD does not tick while paused) and
-- refreshes the footer twice a second.

local pcall, type, tostring, tonumber, floor = pcall, type, tostring, tonumber, math.floor
local sort, concat = table.sort, table.concat

local DebugPanel = {}
DebugPanel.__index = DebugPanel

local PANEL_W, PANEL_H = 484, 372
local PAD = 10
local BH, GAP = 20, 4
local TITLE_H, TAB_H = 24, 20
local BODY_H = PANEL_H - TITLE_H - TAB_H - 4 - 38
local FOOTER_REFRESH = 0.5

-- (no camera row: the position is relative to the camera distance, changing both made values inconsistent)
-- Tuning rows of the Tuning tab: label, ENEMY field (or pos index), step.
local MODEL_FIELDS = {
	{ label = "x", idx = 1, step = 0.1 },
	{ label = "y", idx = 2, step = 0.1 },
	{ label = "z", idx = 3, step = 0.1 },
	{ label = "rot", key = "rot", step = 0.1 },
	{ label = "scale", key = "scale", step = 0.1 },
}

local TABS = { "Fights", "Board", "Status", "Effects", "Sounds", "Tuning", "Live", "Board FX", "Hit FX" }
local BOARDFX_TAB = 8
local HITFX_TAB = 9
local LIVE_TAB = 7
local LIVE_LINES = 14
local LIVE_REFRESH = 0.25

local A -- ns.Assets (resolved in create)

local function say(msg)
	print("|cffffcc00Dragon Chess|r debug: " .. tostring(msg))
end

local function report(err)
	local handler = geterrorhandler()
	if handler then handler(err) end
	say("error - " .. tostring(err))
end

local function set_color(tex, c) tex:SetColorTexture(c[1], c[2], c[3], c[4]) end

local function button(parent, label, w, onclick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w, BH)
	b:RegisterForClicks("LeftButtonUp")
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(b)
	set_color(bg, A.COLOR.BUTTON_BG)
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints(b)
	set_color(hl, A.COLOR.BUTTON_HL)
	local fs = b:CreateFontString(nil, "OVERLAY", A.FONT_HUD_SMALL)
	fs:SetPoint("CENTER", b, "CENTER", 0, 0)
	fs:SetText(label)
	b.text = fs
	b:SetScript("OnClick", onclick)
	return b
end

local function put(widget, parent, x, y)
	widget:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
end

local function heading(parent, text, x, y)
	local fs = parent:CreateFontString(nil, "OVERLAY", A.FONT_LABEL_SMALL)
	fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
	fs:SetText(text)
	return fs
end

local function sorted_keys(t)
	local out = {}
	for k in pairs(t) do out[#out + 1] = k end
	sort(out)
	return out
end

local function round2(v) return floor(v * 100 + 0.5) / 100 end

-- Model framing value of an ENEMY entry (the default when the entry has none).
local function field_get(e, f)
	local d = A.MODEL_DEFAULT
	if f.idx ~= nil then return (e.pos or d.pos)[f.idx] end
	local v = e[f.key]
	if v == nil then v = d[f.key] end
	return v
end

local function field_set(e, f, v)
	if f.idx ~= nil then
		if e.pos == nil then
			local p = A.MODEL_DEFAULT.pos
			e.pos = { p[1], p[2], p[3] } -- an own copy: never edit the shared default table
		end
		e.pos[f.idx] = v
	else
		e[f.key] = v
	end
end

---------------------------------------------------------------- game context

-- run, combat, sim of the running game (the window is opened when there is none yet); nil + reason otherwise.
function DebugPanel:_ctx()
	local app = self.app
	if app.sim == nil and app.db ~= nil then app.show() end
	if app.sim == nil or app.run == nil or app.combat == nil then return nil, "no running game (open it with /dchess)" end
	if app.crashed or app.lost or app.won or app.stuck then return nil, "the run is over: Restart run first" end
	return app.run, app.combat, app.sim
end

-- Runs fn(...) guarded; prints its message (ok, message convention of core/debug.lua) and refreshes.
function DebugPanel:_do(fn, ...)
	local called, ok, msg = pcall(fn, ...)
	if not called then
		report(ok)
		return false
	end
	if msg ~= nil then
		say(msg)
	elseif ok == false then
		say("failed")
	end
	local hud = self.app.hud
	if hud ~= nil and hud.combat ~= nil then
		local okh, err = pcall(hud.update, hud) -- a state change shows at once, also while paused
		if not okh then report(err) end
	end
	self:refresh()
	return ok
end

-- fn(run, combat, sim) guarded, with the context.
function DebugPanel:_game(fn)
	local run, combat, sim = self:_ctx()
	if run == nil then
		say(combat)
		return false
	end
	return self:_do(fn, run, combat, sim)
end

---------------------------------------------------------------- cosmetic actions

function DebugPanel:_fx(key)
	local app = self.app
	local hud = app.hud
	local fx = hud ~= nil and hud.fx or nil
	if fx == nil or not fx.available then return false, "effects: open the window first (no effect models available)" end
	if not app.running or app.soft or app.menu_open then
		return false, "effects: open and unpause the window first (they run on game time)"
	end
	local now = app.combat ~= nil and app.combat.sim.now or fx.now
	if fx:play(key, nil, nil, now, ns.Fx.DEV_DURATION) then
		local cfg = A.FX[key]
		return true, ("%s: m2 %s at '%s'"):format(key, tostring(cfg.m2), tostring(cfg.at))
	end
	return false, key .. " could not be shown (model failed to load?)"
end

-- W0-P6 juice (match break, spawn rings, streaks, shake): one effect now, for tuning (constants: ui/juice.lua top).
local JUICE_BUTTONS = {
	{ "Break 3", "break" }, { "Break 5", "break5" }, { "Skill spawn", "spawn" }, { "Ult spawn", "ult" },
	{ "Streak", "shot" }, { "Ult streak", "shot_ult" }, { "Enemy cast", "cast" }, { "Shake", "shake" },
	{ "Big shake", "shake_big" },
}

function DebugPanel:_juice(kind)
	local app = self.app
	local hud = app.hud
	if hud == nil or app.combat == nil or not app.running or app.soft or app.menu_open then
		return false, "juice: open and unpause the window first (it runs on game time)"
	end
	if hud:dev_juice(kind) then return true, "juice: " .. kind end
	return false, "juice: " .. kind .. " could not be played (no juice layer, or shake is off in the Menu)"
end

-- W0-P7 board effects (ui/board_fx.lua): one effect now on a fixed spot; the same gates as the juice buttons.
local BOARDFX_BUTTONS = {
	{ "Row sweep", "row_sweep" }, { "Wave", "wave" }, { "Chain bolt", "chain" }, { "Telegraph", "telegraph" },
	{ "Tele from", "telegraph_from" }, { "Area flash", "area" }, { "Color flash", "color" }, { "Light skill", "light_skill" },
	{ "Light ult", "light_ult" }, { "Combo x2", "combo2" }, { "Combo x3", "combo3" }, { "Combo x4", "combo4" },
	{ "Combo x5", "combo5" }, { "Combo x6", "combo6" },
}
local JUICE2_BUTTONS = {
	{ "Land dust", "dust" }, { "Sig Amber", "sig0" }, { "Sig Amethyst", "sig1" }, { "Sig Emerald", "sig2" },
	{ "Sig Ruby", "sig3" }, { "Sig Sapphire", "sig4" }, { "Sig Topaz", "sig5" },
}

function DebugPanel:_boardfx(kind)
	local app = self.app
	local hud = app.hud
	if hud == nil or app.combat == nil or not app.running or app.soft or app.menu_open then
		return false, "board fx: open and unpause the window first (it runs on game time)"
	end
	if hud:dev_boardfx(kind) then return true, "board fx: " .. kind end
	return false, "board fx: " .. kind .. " could not be played"
end

-- W0-P8 hit / status effects (ui/hit_fx.lua HitFx.DEV_BUTTONS); pop / shatter / aura buttons show best with the status
-- active (Status tab), chip buttons with HP below full.
function DebugPanel:_hitfx(kind)
	local app = self.app
	local hud = app.hud
	if hud == nil or app.combat == nil or not app.running or app.soft or app.menu_open then
		return false, "hit fx: open and unpause the window first (it runs on game time)"
	end
	if hud:dev_hitfx(kind) then return true, "hit fx: " .. kind end
	return false, "hit fx: " .. kind .. " could not be played"
end

function DebugPanel:_build_hitfx(p)
	local buttons = ns.HitFx.DEV_BUTTONS
	for i = 1, #buttons do
		local entry = buttons[i]
		local b = button(p, entry[1], 112, function() self:_do(self._hitfx, self, entry[2]) end)
		put(b, p, ((i - 1) % 4) * 116, floor((i - 1) / 4) * 24)
	end
	local rows = floor((#buttons + 3) / 4)
	local fs = p:CreateFontString(nil, "OVERLAY", A.FONT_HUD_SMALL)
	fs:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -(rows * 24 + 6))
	fs:SetWidth(PANEL_W - 2 * PAD)
	fs:SetJustifyH("LEFT")
	fs:SetText("Pop / shatter / aura show best with the status active (Status tab); chips need HP below full (Hurt player).")
end

function DebugPanel:_reject_shake()
	local app = self.app
	if app.view == nil or app.combat == nil or not app.running or app.soft or app.menu_open then
		return false, "reject: open and unpause the window first"
	end
	if app.view:dev_reject() then return true, "rejected swap shake" end
	return false, "reject: no gems to shake"
end

function DebugPanel:_texture_test()
	local app = self.app
	local hud = app.hud
	if hud == nil or app.win == nil then return false, "texture test: open the window first" end
	local on = hud.boardfx:texture_test(app.win.frame)
	self:refresh()
	return true, "texture test " .. (on and "shown" or "hidden") .. " (" .. A.soft_report() .. ")"
end

function DebugPanel:_build_boardfx(p)
	local n = 0
	local function add(label, fn)
		local b = button(p, label, 112, fn)
		put(b, p, (n % 4) * 116, floor(n / 4) * 24)
		n = n + 1
		return b
	end
	for i = 1, #BOARDFX_BUTTONS do
		local entry = BOARDFX_BUTTONS[i]
		add(entry[1], function() self:_do(self._boardfx, self, entry[2]) end)
	end
	add("Rejected shake", function() self:_do(self._reject_shake, self) end)
	for i = 1, #JUICE2_BUTTONS do
		local entry = JUICE2_BUTTONS[i]
		add(entry[1], function() self:_do(self._juice, self, entry[2]) end)
	end
	add("Texture test", function() self:_do(self._texture_test, self) end)
	local rows = floor((n + 3) / 4)
	local fs = p:CreateFontString(nil, "OVERLAY", A.FONT_HUD_SMALL)
	fs:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -(rows * 24 + 6))
	fs:SetWidth(PANEL_W - 2 * PAD)
	fs:SetJustifyH("LEFT")
	self.glow_text = fs
end

function DebugPanel:_sound(key)
	if not A.sound_enabled then return false, "sound is off (Menu)" end
	local slot = A.SOUNDS[key]
	local file
	if slot.creature then -- enemy_attack / enemy_death: the sound of the current enemy
		local combat = self.app.combat
		local e = combat ~= nil and combat.enemy or nil
		local field = (key:gsub("^enemy_", "")) .. "_sound"
		file = e ~= nil and e.def[field] or nil
		if file == nil then return false, key .. ": no enemy with a " .. field .. " right now" end
	end
	local played = A.play(key, file, true)
	return played, ("%s on %s%s"):format(key, A.channel_of(key), played and "" or " (silent: not playable)")
end

-- Tuning: enemy model framing --------------------------------------------------------------------

-- The ENEMY entry of the model on screen, or nil + reason.
function DebugPanel:_model_entry()
	local hud = self.app.hud
	if hud == nil or hud.model == nil or hud.enemy_mode ~= "model" then return nil, "no enemy model on screen (open the window; the portrait fallback has no framing)" end
	local key = hud.enemy_key
	local e = A.ENEMY[key]
	if e == nil then return nil, "no Assets.ENEMY entry for " .. tostring(key) end
	return e, key
end

function DebugPanel:_step_model(f, dir)
	local e, key = self:_model_entry()
	if e == nil then return false, key end
	if self.orig[key] == nil then -- remember the file's values for Reset
		local o = { cam_scale = e.cam_scale, rot = e.rot, scale = e.scale }
		if e.pos ~= nil then o.pos = { e.pos[1], e.pos[2], e.pos[3] } end
		self.orig[key] = o
	end
	field_set(e, f, round2(field_get(e, f) + dir * f.step))
	self:_store_tuning(key)
	self.app.hud:reframe()
	return true, A.format_enemy(key)
end

-- Keeps the edited entry in DragonChessDB (written at /reload or logout) so it can be read from the SavedVariables file.
function DebugPanel:_store_tuning(key)
	local dbg = self.app.db.debug
	if type(dbg) ~= "table" then return end
	if type(dbg.enemy_tuning) ~= "table" then dbg.enemy_tuning = {} end
	A.enemy_tuning_store(dbg.enemy_tuning, key)
end

-- Tries a creature display ID on the enemy on screen (kept in the entry + the saved tuning).
function DebugPanel:_try_display(n)
	local e, key = self:_model_entry()
	if e == nil then return false, key end
	if n == nil then return false, "type a creature display ID first" end
	e.display_id = n
	self:_store_tuning(key)
	local hud = self.app.hud
	hud.enemy_key = nil
	hud:_show_enemy(key)
	return true, A.format_enemy(key) .. (hud.enemy_mode == "model" and "" or "  (did not load, portrait fallback)")
end

-- Tries a model FileDataID alone (no display, so it may render untextured) on the enemy on screen.
function DebugPanel:_try_model(n)
	local e, key = self:_model_entry()
	if e == nil then return false, key end
	if n == nil then return false, "type a model FileDataID first" end
	e.display_id, e.model_id = nil, n
	self:_store_tuning(key)
	local hud = self.app.hud
	hud.enemy_key = nil
	hud:_show_enemy(key)
	return true, A.format_enemy(key) .. (hud.enemy_mode == "model" and "" or "  (did not load, portrait fallback)")
end

-- Scans creature display IDs for the ones that use model FileDataID `fid` (a hidden PlayerModel is cycled through
-- the IDs, GetModelFileID tells which model each resolved to); matches are printed. Runs 300 IDs per frame.
function DebugPanel:_scan_start(fid, from, to)
	if fid == nil then return false, "type the model FileDataID first (e.g. 123388 = direwolf)" end
	local m = self.scan_model
	if m == nil then
		local ok, model = pcall(CreateFrame, "PlayerModel", nil, self.frame)
		if not ok or model == nil then return false, "PlayerModel not available" end
		model:SetSize(16, 16)
		model:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 0, 0)
		model:SetAlpha(0)
		self.scan_model = model
		m = model
	end
	self.scan = { fid = fid, id = from or 1, last = to or 60000, found = 0, seen = 0 }
	return true, ("scanning display IDs %d-%d for model %d ..."):format(self.scan.id, self.scan.last, fid)
end

function DebugPanel:_scan_step()
	local s, m = self.scan, self.scan_model
	for _ = 1, 300 do
		local id = s.id
		if id > s.last then
			say(("scan done: %d display(s) use model %d (%d IDs resolved a model)%s"):format(s.found, s.fid, s.seen,
				s.seen == 0 and " - GetModelFileID returned nothing, the scan cannot work in this client" or ""))
			self.scan = nil
			return
		end
		s.id = id + 1
		if pcall(m.SetDisplayInfo, m, id) then
			local ok, f = pcall(m.GetModelFileID, m)
			if ok and type(f) == "number" and f > 0 then
				s.seen = s.seen + 1
				if f == s.fid then
					s.found = s.found + 1
					if s.found <= 25 then say("display " .. id .. " uses model " .. s.fid) end
				end
			end
		end
	end
end

function DebugPanel:_reset_model()
	local e, key = self:_model_entry()
	if e == nil then return false, key end
	local o = self.orig[key]
	if o == nil then return true, key .. ": nothing changed" end
	e.cam_scale, e.rot, e.scale = o.cam_scale, o.rot, o.scale
	e.pos = o.pos ~= nil and { o.pos[1], o.pos[2], o.pos[3] } or nil
	self:_store_tuning(key)
	self.app.hud:reframe()
	return true, A.format_enemy(key)
end

function DebugPanel:_print_enemy()
	local e, key = self:_model_entry()
	if e == nil then return false, key end
	return true, A.format_enemy(key)
end

function DebugPanel:_print_all_enemies()
	for _, key in ipairs(sorted_keys(A.ENEMY)) do say(A.format_enemy(key)) end
	return true
end

function DebugPanel:_cycle_bg(dir)
	local hud = self.app.hud
	if hud == nil then return false, "open the window first" end
	local name, id = hud:cycle_bg(dir)
	return true, "background " .. name .. " (FileDataID " .. tostring(id) .. ")"
end

function DebugPanel:_print_bg()
	local hud = self.app.hud
	if hud == nil then return false, "open the window first" end
	return true, A.format_bg(hud.stage, hud.bg_file, hud.bg_name)
end

---------------------------------------------------------------- pages

function DebugPanel:_page(i)
	local p = CreateFrame("Frame", nil, self.body)
	p:SetAllPoints(self.body)
	p:Hide()
	self.pages[i] = p
	return p
end

function DebugPanel:_build_fights(p)
	local Debug = ns.Debug
	local ids = Debug.enemy_ids()
	local app = self.app
	for i = 1, #ids do
		local id = ids[i]
		local col, row = (i - 1) % 4, floor((i - 1) / 4)
		local b = button(p, (id:gsub("_", " ")), 112, function() self:_do(app.dev_fight, id) end)
		put(b, p, col * 116, row * 24)
	end
	local y = 3 * 24 + 8
	local function add(i, label, fn)
		local b = button(p, label, 112, fn)
		put(b, p, ((i - 1) % 4) * 116, y + floor((i - 1) / 4) * 24)
		return b
	end
	add(1, "Difficulty -", function() self:_game(function(run) return Debug.difficulty(run, -1) end) end)
	add(2, "Difficulty +", function() self:_game(function(run) return Debug.difficulty(run, 1) end) end)
	add(3, "Kill enemy", function() self:_game(Debug.kill_enemy) end)
	add(4, "Next fight", function() self:_game(Debug.next_fight) end)
	add(5, "Heal player", function() self:_game(function(run, combat) return Debug.heal_player(run, combat) end) end)
	add(6, "Hurt player", function() self:_game(function(run, combat) return Debug.hurt_player(run, combat) end) end)
	self.god_button = add(7, "God mode: off", function() self:_game(Debug.toggle_god) end)
	add(8, "Restart run", function()
		self:_do(function()
			app.reset()
			return true, "new run"
		end)
	end)
	self.invincible_button = add(9, "Invincible: off", function() self:_game(Debug.toggle_invincible) end)
	self.timers_button = add(10, "Enemy timers: run", function() self:_game(Debug.toggle_enemy_timers) end)
	heading(p, "Dev run: no records, nothing saved. Difficulty applies to the next fight.", 0, y + 3 * 24 + 6)
end

function DebugPanel:_build_board(p)
	local Debug = ns.Debug
	local names = ns.Combat.COLOR_NAMES
	local function row(block, title, fn)
		heading(p, title, 0, block * 46)
		for c = 0, 5 do
			local b = button(p, names[c], 74, function() self:_game(function(run, combat, sim) return fn(run, sim, c) end) end)
			put(b, p, c * 78 + 0, block * 46 + 14)
			local icon = b:CreateTexture(nil, "ARTWORK")
			icon:SetSize(14, 14)
			icon:SetPoint("LEFT", b, "LEFT", 3, 0)
			A.apply_gem(icon, c) -- unmasked: set at build time (reopen the panel after a set change)
			b.text:SetPoint("CENTER", b, "CENTER", 7, 0)
		end
	end
	row(0, "Spawn a SKILL gem (random free cell)", function(run, sim, c) return Debug.spawn_gem(run, sim, c, 1) end)
	row(1, "Spawn an ULT gem (random free cell)", function(run, sim, c) return Debug.spawn_gem(run, sim, c, 2) end)
	row(2, "Convert " .. Debug.CONVERT_COUNT .. " random gems to...", function(run, sim, c)
		return Debug.convert(run, sim, c, Debug.CONVERT_COUNT)
	end)
	put(button(p, "Junk x" .. Debug.JUNK_COUNT, 112, function()
		self:_game(function(run, _, sim) return Debug.junk(run, sim, Debug.JUNK_COUNT) end)
	end), p, 0, 3 * 46 + 4)
	put(button(p, "Shuffle board", 112, function()
		self:_game(function(run, _, sim) return Debug.shuffle(run, sim) end)
	end), p, 116, 3 * 46 + 4)
end

function DebugPanel:_build_status(p)
	local Debug = ns.Debug
	local list = Debug.STATUS_LIST
	for i = 1, #list do
		local entry = list[i]
		local b = button(p, entry.label, 112, function()
			self:_game(function(run, combat) return Debug.status(run, combat, entry.id) end)
		end)
		put(b, p, ((i - 1) % 4) * 116, floor((i - 1) / 4) * 24)
	end
	heading(p, "Numbers: Debug.STATUS (core/debug.lua). Enemy ones need a live enemy.", 0, 2 * 24 + 6)
	put(button(p, "Print values", 112, function()
		self:_do(function()
			for _, k in ipairs(sorted_keys(Debug.STATUS)) do say("Debug.STATUS." .. k .. " = " .. tostring(Debug.STATUS[k])) end
			return true
		end)
	end), p, 0, 2 * 24 + 24)
end

function DebugPanel:_build_effects(p)
	local keys = sorted_keys(A.FX)
	for i = 1, #keys do
		local key = keys[i]
		local b = button(p, (key:gsub("_", " ")), 112, function() self:_do(self._fx, self, key) end)
		put(b, p, ((i - 1) % 4) * 116, floor((i - 1) / 4) * 24)
	end
	local rows = floor((#keys + 3) / 4)
	put(button(p, "Stop effects", 112, function()
		self:_do(function()
			local hud = self.app.hud
			if hud ~= nil then hud.fx:stop_all() end
			return true, "effects stopped"
		end)
	end), p, 0, rows * 24 + 6)
	heading(p, "Needs the window open and not paused.", 120, rows * 24 + 10)
	heading(p, "Juice (W0-P6): match break, spawn, streaks, shake", 0, rows * 24 + 36)
	for i = 1, #JUICE_BUTTONS do
		local entry = JUICE_BUTTONS[i]
		local b = button(p, entry[1], 112, function() self:_do(self._juice, self, entry[2]) end)
		put(b, p, ((i - 1) % 4) * 116, rows * 24 + 52 + floor((i - 1) / 4) * 24)
	end
end

local CHANNEL_SHORT = { SFX = "SFX", Ambience = "Amb", Dialog = "Dlg", Master = "Mst", Music = "Mus" }

function DebugPanel:_build_sounds(p)
	local keys = sorted_keys(A.SOUNDS)
	local rows = floor((#keys + 2) / 3)
	self.channel_buttons = {}
	for i = 1, #keys do
		local key = keys[i]
		local col, row = (i - 1) % 3, floor((i - 1) / 3)
		local x = col * 156
		local play = button(p, (key:gsub("_", " ")), 104, function() self:_do(self._sound, self, key) end)
		put(play, p, x, row * 22)
		local ch = button(p, CHANNEL_SHORT[A.channel_of(key)] or A.channel_of(key), 46, function()
			self:_do(function()
				local name = A.next_channel(key)
				return true, key .. ": channel = \"" .. name .. "\""
			end)
		end)
		put(ch, p, x + 106, row * 22)
		self.channel_buttons[key] = ch
	end
	put(button(p, "Print channels", 112, function()
		self:_do(function()
			local lines = A.format_channels()
			if #lines == 0 then return true, "all slots on the default channel (" .. A.SOUND_CHANNEL .. ")" end
			for i = 1, #lines do say(lines[i]) end
			return true
		end)
	end), p, 0, rows * 22 + 6)
	heading(p, "Click = play; small button = next channel.", 120, rows * 22 + 10)
	-- Try any id: type a FileDataID (PlaySoundFile) or a SoundKit id (PlaySound) and press the button.
	local y = rows * 22 + 34
	heading(p, "Test id:", 0, y + 4)
	local ok, eb = pcall(CreateFrame, "EditBox", nil, p, "InputBoxTemplate")
	if ok and eb ~= nil then
		eb:SetSize(90, 20)
		eb:SetAutoFocus(false)
		eb:SetNumeric(true)
		eb:SetMaxLetters(9)
		eb:SetPoint("TOPLEFT", p, "TOPLEFT", 64, -y)
		eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
		eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
		self.sound_box = eb
		local function id() return tonumber(eb:GetText()) end
		put(button(p, "Play file", 70, function()
			self:_do(function()
				local n = id()
				if n == nil then return false, "type a FileDataID first" end
				return A.play("match_cascade", n, true), "PlaySoundFile " .. n
			end)
		end), p, 164, y)
		put(button(p, "Play kit", 70, function()
			self:_do(function()
				local n = id()
				if n == nil then return false, "type a SoundKit id first" end
				return (pcall(PlaySound, n)), "PlaySound " .. n
			end)
		end), p, 238, y)
	end
end

-- Live tab: one text line per live status / timer (Debug.status_lines), refreshed 4 x a second while shown.
function DebugPanel:_build_live(p)
	self.live_lines = {}
	self.live_fs = {}
	for i = 1, LIVE_LINES do
		local fs = p:CreateFontString(nil, "OVERLAY", A.FONT_HUD_SMALL)
		fs:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -((i - 1) * 16))
		fs:SetJustifyH("LEFT")
		fs:SetText("")
		self.live_fs[i] = fs
	end
end

function DebugPanel:_refresh_live()
	local n = ns.Debug.status_lines(self.app.combat, self.live_lines)
	if n > LIVE_LINES then n = LIVE_LINES end
	for i = 1, LIVE_LINES do self.live_fs[i]:SetText(i <= n and self.live_lines[i] or "") end
end

function DebugPanel:_build_tuning(p)
	heading(p, "Background", 0, 0)
	self.bg_text = heading(p, "", 80, 0)
	put(button(p, "< prev", 80, function() self:_do(self._cycle_bg, self, -1) end), p, 0, 14)
	put(button(p, "next >", 80, function() self:_do(self._cycle_bg, self, 1) end), p, 84, 14)
	put(button(p, "Print bg", 80, function() self:_do(self._print_bg, self) end), p, 168, 14)

	heading(p, "Enemy model framing (edits Assets.ENEMY, prints the line to paste)", 0, 48)
	self.model_text = heading(p, "", 0, 62)
	self.field_text = {}
	for i = 1, #MODEL_FIELDS do
		local f = MODEL_FIELDS[i]
		local col, row = (i - 1) % 2, floor((i - 1) / 2)
		local x, y = col * 232, 80 + row * 24
		heading(p, f.label, x, y + 4)
		local value = p:CreateFontString(nil, "OVERLAY", A.FONT_HUD_SMALL)
		value:SetPoint("TOPLEFT", p, "TOPLEFT", x + 50, -(y + 4))
		self.field_text[i] = value
		put(button(p, "-", 24, function() self:_do(self._step_model, self, f, -1) end), p, x + 110, y)
		put(button(p, "+", 24, function() self:_do(self._step_model, self, f, 1) end), p, x + 138, y)
	end
	local y = 80 + 3 * 24 + 6
	put(button(p, "Print enemy", 112, function() self:_do(self._print_enemy, self) end), p, 0, y)
	put(button(p, "Print all", 112, function() self:_do(self._print_all_enemies, self) end), p, 116, y)
	put(button(p, "Reset enemy", 112, function() self:_do(self._reset_model, self) end), p, 232, y)
	put(button(p, "Reset peak", 112, function()
		self.app.frame_peak = 0
		self:refresh()
	end), p, 348, y)
	-- Display ID test for the enemy on screen (e.g. to find a model that loads).
	heading(p, "ID (display / model):", 0, y + 34)
	local ok, eb = pcall(CreateFrame, "EditBox", nil, p, "InputBoxTemplate")
	if ok and eb ~= nil then
		eb:SetSize(60, 20)
		eb:SetAutoFocus(false)
		eb:SetNumeric(true)
		eb:SetMaxLetters(9)
		eb:SetPoint("TOPLEFT", p, "TOPLEFT", 100, -(y + 30))
		eb:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
		eb:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
		put(button(p, "Try display", 90, function()
			self:_do(self._try_display, self, tonumber(eb:GetText()))
		end), p, 164, y + 28)
		put(button(p, "Try model", 80, function()
			self:_do(self._try_model, self, tonumber(eb:GetText()))
		end), p, 258, y + 28)
		put(button(p, "Scan displays", 96, function()
			self:_do(self._scan_start, self, tonumber(eb:GetText()))
		end), p, 342, y + 28)
	end
	heading(p, "Edits are saved to DragonChessDB.debug.enemy_tuning (file written on /reload or logout).", 0, y + 56)
end

---------------------------------------------------------------- panel

function DebugPanel:select(i)
	for k = 1, #self.pages do
		if k == i then self.pages[k]:Show() else self.pages[k]:Hide() end
	end
	self.tab = i
	local dbg = self.app.db.debug
	if type(dbg) == "table" then dbg.tab = i end
	self:refresh()
end

-- Labels that mirror state (god mode, channels, tuning values, background) + the footer.
function DebugPanel:refresh()
	local app = self.app
	local combat = app.combat
	if self.god_button ~= nil then
		self.god_button.text:SetText("God mode: " .. ((combat ~= nil and combat.god_mode) and "on" or "off"))
	end
	if self.invincible_button ~= nil then
		self.invincible_button.text:SetText("Invincible: " .. ((combat ~= nil and combat.enemy_invincible) and "ON" or "off"))
		self.timers_button.text:SetText("Enemy timers: " .. ((combat ~= nil and combat.enemy_timers_held) and "PAUSED" or "run"))
	end
	if self.tab == LIVE_TAB then
		self:_refresh_live()
	elseif self.tab == BOARDFX_TAB then
		self.glow_text:SetText("Soft textures (Assets.GLOW): " .. A.soft_report())
	elseif self.tab == 5 then
		for key, b in pairs(self.channel_buttons) do
			local ch = A.channel_of(key)
			b.text:SetText(CHANNEL_SHORT[ch] or ch)
		end
	elseif self.tab == 6 then
		local hud = app.hud
		self.bg_text:SetText(hud ~= nil and hud.bg_name ~= nil and (hud.bg_name .. " (" .. tostring(hud.bg_file) .. ")") or "-")
		local e, key = self:_model_entry()
		if e ~= nil then
			self.model_text:SetText(key .. " (display " .. tostring(e.display_id) .. ")")
			for i = 1, #MODEL_FIELDS do self.field_text[i]:SetText(tostring(round2(field_get(e, MODEL_FIELDS[i])))) end
		else
			self.model_text:SetText("(no model on screen)")
			for i = 1, #MODEL_FIELDS do self.field_text[i]:SetText("-") end
		end
	end
	self:_footer()
end

function DebugPanel:_footer()
	local app = self.app
	local fps = type(GetFramerate) == "function" and GetFramerate() or 0
	local run = app.run
	local info = "no run"
	if run ~= nil then
		info = (run.dev and "DEV run" or "run") .. " D" .. run.difficulty .. " fight " .. run.index .. "/" .. ns.Run.fight_count()
	end
	self.footer:SetText(("fps %d | frame %.2f ms (peak %.1f) | %s"):format(fps, app.frame_ms, app.frame_peak, info))
end

local function on_update(self, elapsed)
	if self.scan ~= nil then self:_scan_step() end
	A.tick() -- cut-offs of the sounds played from here (the HUD does not tick while paused / hidden)
	if self.tab == LIVE_TAB then
		self.live_acc = self.live_acc + elapsed
		if self.live_acc >= LIVE_REFRESH then
			self.live_acc = 0
			self:_refresh_live()
		end
	end
	self.acc = self.acc + elapsed
	if self.acc < FOOTER_REFRESH then return end
	self.acc = 0
	self:_footer()
end

function DebugPanel.create(app)
	A = ns.Assets
	local self = setmetatable({ app = app, pages = {}, orig = {}, acc = 0, live_acc = 0, tab = 1, channel_buttons = {} }, DebugPanel)
	local dbg = app.db.debug
	local f = CreateFrame("Frame", nil, UIParent, A.TEMPLATE_BACKDROP)
	f:Hide()
	f:SetSize(PANEL_W, PANEL_H)
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetBackdrop(A.BACKDROP_DIALOG)
	self.frame = f
	f:ClearAllPoints()
	if type(dbg) == "table" and type(dbg.point) == "string" and type(dbg.x) == "number" and type(dbg.y) == "number" then
		f:SetPoint(dbg.point, UIParent, type(dbg.rel) == "string" and dbg.rel or dbg.point, dbg.x, dbg.y)
	else
		f:SetPoint("CENTER", UIParent, "CENTER", 360, 0)
	end

	local title = CreateFrame("Frame", nil, f)
	title:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -4)
	title:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, -4)
	title:SetHeight(TITLE_H - 4)
	title:EnableMouse(true)
	title:RegisterForDrag("LeftButton")
	title:SetScript("OnDragStart", function() f:StartMoving() end)
	title:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
		if type(app.db.debug) == "table" then
			local point, _, rel, x, y = f:GetPoint(1)
			local d = app.db.debug
			d.point, d.rel, d.x, d.y = point, rel, x, y
		end
	end)
	local label = title:CreateFontString(nil, "OVERLAY", A.FONT_TITLE)
	label:SetPoint("LEFT", title, "LEFT", 6, 0)
	label:SetText("Dragon Chess - debug")
	local close = CreateFrame("Button", nil, f, A.TEMPLATE_CLOSE)
	close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	close:SetScript("OnClick", function() f:Hide() end)

	-- tabs
	local tab_w = (PANEL_W - 2 * PAD - (#TABS - 1) * GAP) / #TABS
	self.tabs = {}
	for i = 1, #TABS do
		local b = button(f, TABS[i], tab_w, function() self:select(i) end)
		b:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + (i - 1) * (tab_w + GAP), -TITLE_H)
		self.tabs[i] = b
	end

	local body = CreateFrame("Frame", nil, f)
	body:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(TITLE_H + TAB_H + 8))
	body:SetSize(PANEL_W - 2 * PAD, BODY_H)
	self.body = body

	self.footer = f:CreateFontString(nil, "OVERLAY", A.FONT_HUD_SMALL)
	self.footer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD + 2, 12)

	self:_build_fights(self:_page(1))
	self:_build_board(self:_page(2))
	self:_build_status(self:_page(3))
	self:_build_effects(self:_page(4))
	self:_build_sounds(self:_page(5))
	self:_build_tuning(self:_page(6))
	self:_build_live(self:_page(LIVE_TAB))
	self:_build_boardfx(self:_page(BOARDFX_TAB))
	self:_build_hitfx(self:_page(HITFX_TAB))

	f:SetScript("OnShow", function()
		app.profile = true
		app.frame_peak = 0
		self.acc = 0
		self:refresh()
	end)
	f:SetScript("OnHide", function() app.profile = false end)
	f:SetScript("OnUpdate", function(_, elapsed) on_update(self, elapsed) end)

	local tab = type(dbg) == "table" and tonumber(dbg.tab) or 1
	if tab == nil or tab < 1 or tab > #TABS or tab ~= floor(tab) then tab = 1 end
	self:select(tab)
	return self
end

-- /dchess debug [on|off]: the first use enables the panel (DragonChessDB.debug.enabled) and opens it;
-- afterwards it toggles; `off` disables it and hides it.
function DebugPanel.command(app, arg)
	if type(app.db.debug) ~= "table" then app.db.debug = {} end
	local dbg = app.db.debug
	if arg == "off" then
		dbg.enabled = false
		if app.debug_panel ~= nil then app.debug_panel.frame:Hide() end
		say("panel disabled (/dchess debug enables it again)")
		return
	end
	if arg ~= nil and arg ~= "on" then
		say("/dchess debug [on|off]")
		return
	end
	local fresh = not dbg.enabled
	dbg.enabled = true
	if app.debug_panel == nil then app.debug_panel = DebugPanel.create(app) end
	local f = app.debug_panel.frame
	if fresh then say("panel enabled: /dchess debug toggles it, /dchess debug off disables it") end
	if arg == "on" or fresh or not f:IsShown() then f:Show() else f:Hide() end
end

ns.DebugPanel = DebugPanel
