local addonName, ns = ...
-- Options panel (W0-P4, dialog style W0-P12): a dialog on the window's top right, opened by the title strip's "Menu"
-- button, the minimap button's right click or the pause form's Options button. Sections (widgets from ui/panel.lua):
--   Sound    Sound on / off, Quiet mode (only key sounds; dim while Sound is off)
--   Display  Screen shake, Window size (Small / Normal / Large), Gems (Jewels / WoW / Shapes)
--   Game     Hide in combat
--   Restart run (inline confirm: the first click arms it), Close.
-- The difficulty is chosen on the start screen. Options live in DragonChessDB.options (sound, quiet, scale, shake,
-- combat_hide) and DragonChessDB.gem_set; ui/main.lua applies them (Assets.sound_enabled / Assets.quiet, window scale,
-- gem set). The addon cannot set a per-addon volume, so only on/off and quiet mode exist.
--
-- Esc: the window is NOT in UISpecialFrames; a tiny invisible "Esc catcher" frame is. Esc hides
-- it, the app's handler closes the menu first (and re-arms the catcher) and the window second.
-- The menu frame sits above the result screen and the start panel so Restart stays reachable.

local Menu = {}
Menu.__index = Menu

Menu.SCALES = { { "Small", 0.85 }, { "Normal", 1 }, { "Large", 1.2 } }
local ESC_NAME = "DragonChessEsc"
local LEVEL_ABOVE_HOST = 40
local PAD = 16
local W = 280
local INNER_W = W - 2 * PAD -- 248
local CHECK_ROW = 24 -- one check box row
local CHECK_X = PAD - 2 -- the native check box has a transparent margin
local LABEL_W = 70 -- "Window size" / "Gems" label column
local SEG_W = INNER_W - LABEL_W -- 178
local BUTTON_W, BUTTON_H = INNER_W, 24
local ANCHOR_X, ANCHOR_Y = -8, -28 -- from the window's top right (+ the header plate's rise)
-- y positions below the dialog's top edge
local Y_SEC_SOUND = 40
local Y_SOUND = Y_SEC_SOUND + 22
local Y_QUIET = Y_SOUND + CHECK_ROW
local Y_SEC_DISPLAY = Y_QUIET + CHECK_ROW + 6
local Y_SHAKE = Y_SEC_DISPLAY + 22
local Y_SCALE = Y_SHAKE + CHECK_ROW + 2
local Y_GEMS = Y_SCALE + 22 + 6
local Y_SEC_GAME = Y_GEMS + 22 + 8
local Y_COMBAT = Y_SEC_GAME + 22
local Y_RESTART = Y_COMBAT + CHECK_ROW + 10
local Y_CLOSE = Y_RESTART + BUTTON_H + 6
local H = Y_CLOSE + BUTTON_H + PAD

Menu.W, Menu.H = W, H

-- Index into Menu.SCALES nearest to a scale value (default Normal).
function Menu.scale_index(v)
	if type(v) ~= "number" then return 2 end
	local best, bd = 2, math.huge
	for i = 1, #Menu.SCALES do
		local d = math.abs(Menu.SCALES[i][2] - v)
		if d < bd then best, bd = i, d end
	end
	return best
end

-- win: Window.create's table; app: the App table (db, restart_run, set_option, set_gem_set, close_menu).
-- Returns the menu (frame, checks, scale / gems segments, buttons).
function Menu.create(win, app)
	local A, P = ns.Assets, ns.Panel
	local self = setmetatable({ app = app, confirming = false }, Menu)
	local f = P.dialog(win.frame, W, H, "Options")
	f:SetFrameLevel(win.host:GetFrameLevel() + LEVEL_ABOVE_HOST)
	f:SetPoint("TOPRIGHT", win.frame, "TOPRIGHT", ANCHOR_X, ANCHOR_Y - P.HEADER_RISE)
	f:Hide()
	self.frame = f

	local function section(text, y)
		local s = P.section(f, text, INNER_W)
		s:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
	end
	local function check(text, y, name, default_on)
		local c = P.check(f, text)
		c:SetPoint("TOPLEFT", f, "TOPLEFT", CHECK_X, -(y - 1))
		P.on_click(c, function() self:_toggle(name, default_on) end, true)
		return c
	end
	section("Sound", Y_SEC_SOUND)
	section("Display", Y_SEC_DISPLAY)
	section("Game", Y_SEC_GAME)
	self.checks = {
		sound = check("Sound", Y_SOUND, "sound", true),
		quiet = check("Quiet mode (key sounds only)", Y_QUIET, "quiet", false),
		shake = check("Screen shake", Y_SHAKE, "shake", true),
		combat_hide = check("Hide in combat", Y_COMBAT, "combat_hide", true),
	}

	local function segment_row(text, y, labels)
		local l = P.font_string(f, A.FONT_HUD_SMALL)
		l:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(y + 5))
		l:SetText(text)
		local seg = P.segment(f, labels, SEG_W)
		seg:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + LABEL_W, -y)
		return seg
	end
	local scale_labels, gem_labels = {}, {}
	for i = 1, #Menu.SCALES do scale_labels[i] = Menu.SCALES[i][1] end
	for i = 1, #A.GEM_SET_ORDER do gem_labels[i] = A.GEM_SET_LABEL[A.GEM_SET_ORDER[i]] or A.GEM_SET_ORDER[i] end
	self.scale_seg = segment_row("Window size", Y_SCALE, scale_labels)
	self.scale_seg.on_pick = function(i) self:_set_scale(i) end
	self.gems_seg = segment_row("Gems", Y_GEMS, gem_labels)
	self.gems_seg.on_pick = function(i) self:_set_gems(i) end

	self.buttons = {
		restart = P.button(f, BUTTON_W, BUTTON_H, "Restart run"),
		close = P.button(f, BUTTON_W, BUTTON_H, "Close"),
	}
	self.buttons.restart:SetPoint("TOP", f, "TOP", 0, -Y_RESTART)
	self.buttons.close:SetPoint("TOP", f, "TOP", 0, -Y_CLOSE)
	P.on_click(self.buttons.restart, function() self:_on_restart() end)
	P.on_click(self.buttons.close, function() app.close_menu() end)
	self:refresh()
	return self
end

function Menu:refresh()
	local opts = self.app.db.options
	local c = self.checks
	c.sound.set_checked(opts.sound ~= false)
	c.quiet.set_checked(opts.quiet == true)
	c.quiet.set_dim(opts.sound == false)
	c.shake.set_checked(opts.shake ~= false)
	c.combat_hide.set_checked(opts.combat_hide ~= false)
	self.scale_seg.select(Menu.scale_index(opts.scale))
	local A = ns.Assets
	local gi = 1
	for i = 1, #A.GEM_SET_ORDER do
		if A.GEM_SET_ORDER[i] == A.gem_set then gi = i end
	end
	self.gems_seg.select(gi)
	ns.Panel.set_text(self.buttons.restart, self.confirming and "Really restart? Click again" or "Restart run")
	ns.Panel.set_text(self.buttons.close, "Close")
end

function Menu:_on_restart()
	if not self.confirming then
		self.confirming = true
		self:refresh()
		return
	end
	self.confirming = false
	self.app.restart_run()
end

function Menu:_toggle(name, default_on)
	local opts = self.app.db.options
	local cur = opts[name]
	if cur == nil then cur = default_on end
	-- the click is played before a mute and after an unmute: always audible feedback
	if name == "sound" and cur then ns.Assets.play("click") end
	self.app.set_option(name, not cur)
	if name ~= "sound" or not cur then ns.Assets.play("click") end
	self:refresh()
end

function Menu:_set_scale(i)
	self.app.set_option("scale", Menu.SCALES[i][2])
	self:refresh()
end

function Menu:_set_gems(i)
	self.app.set_gem_set(ns.Assets.GEM_SET_ORDER[i])
	self:refresh()
end

function Menu:open()
	self.confirming = false
	self:refresh()
	self.frame:Show()
end

function Menu:close()
	self.confirming = false
	self.frame:Hide()
end

function Menu:is_open()
	return self.frame:IsShown()
end

-- Esc catcher: a named, invisible frame in UISpecialFrames (a named global frame, documented).
-- show() arms it while the window is shown; hide() disarms it silently (the window closed).
-- on_escape() runs when Esc (or any CloseSpecialWindows) hid it.
function Menu.create_escape(on_escape)
	local esc = CreateFrame("Frame", ESC_NAME, UIParent)
	esc:SetSize(1, 1)
	esc:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	esc:Hide()
	local silent = false
	esc:SetScript("OnHide", function()
		if not silent then on_escape() end
	end)
	if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = ESC_NAME end
	return {
		frame = esc,
		arm = function() esc:Show() end,
		disarm = function()
			silent = true
			esc:Hide()
			silent = false
		end,
	}
end

ns.Menu = Menu
