local addonName, ns = ...
-- In-window menu (W0-P4): a small panel on the window's top right, opened by the title strip's
-- "Menu" button or the minimap button's right click. Items: Restart run (inline confirm: the
-- first click arms it), Sound on/off, Quiet mode (only key sounds), Screen shake on/off (W0-P6), Difficulty (cycles, like
-- the title strip button), Window size (small / normal / large), Close (closes the menu).
-- Options live in DragonChessDB.options (sound, quiet, scale); ui/main.lua applies them
-- (Assets.sound_enabled / Assets.quiet, window scale). The addon cannot set a per-addon
-- volume, so only on/off and quiet mode exist.
--
-- Esc: the window is NOT in UISpecialFrames; a tiny invisible "Esc catcher" frame is. Esc hides
-- it, the app's handler closes the menu first (and re-arms the catcher) and the window second.
-- The menu frame sits above the result overlay so Restart stays reachable on game over.

local Menu = {}
Menu.__index = Menu

Menu.SCALES = { { "Small", 0.85 }, { "Normal", 1 }, { "Large", 1.2 } }
local ITEM_W, ITEM_H, GAP, PAD = 190, 22, 4, 10
local ESC_NAME = "DragonChessEsc"
local LEVEL_ABOVE_HOST = 40

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

local function set_color(tex, c) tex:SetColorTexture(c[1], c[2], c[3], c[4]) end

local function item_button(parent, A, label)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(ITEM_W, ITEM_H)
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
	return b
end

-- win: Window.create's table; app: the App table (db, restart_run, cycle_difficulty,
-- difficulty_text, set_option, close_menu). Returns the menu (frame, buttons).
function Menu.create(win, app)
	local A = ns.Assets
	local self = setmetatable({ app = app, confirming = false }, Menu)
	local f = CreateFrame("Frame", nil, win.frame, A.TEMPLATE_BACKDROP)
	f:SetFrameLevel(win.host:GetFrameLevel() + LEVEL_ABOVE_HOST)
	f:EnableMouse(true) -- eats clicks over the board
	f:SetBackdrop(A.BACKDROP_DIALOG)
	f:SetPoint("TOPRIGHT", win.frame, "TOPRIGHT", -8, -28)
	f:Hide()
	self.frame = f

	local title = f:CreateFontString(nil, "OVERLAY", A.FONT_TITLE)
	title:SetPoint("TOP", f, "TOP", 0, -PAD)
	title:SetText("Menu")

	local names = { "restart", "sound", "quiet", "shake", "difficulty", "scale", "gems", "close" }
	self.buttons = {}
	for i = 1, #names do
		local b = item_button(f, A, names[i])
		b:SetPoint("TOP", f, "TOP", 0, -(PAD + 20 + (i - 1) * (ITEM_H + GAP)))
		self.buttons[names[i]] = b
	end
	f:SetSize(ITEM_W + 2 * PAD, PAD + 20 + #names * (ITEM_H + GAP) + PAD - GAP)

	local b = self.buttons
	b.restart:SetScript("OnClick", function() self:_on_restart() end)
	b.sound:SetScript("OnClick", function() self:_toggle("sound", true) end)
	b.quiet:SetScript("OnClick", function() self:_toggle("quiet", false) end)
	b.shake:SetScript("OnClick", function() self:_toggle("shake", true) end)
	b.difficulty:SetScript("OnClick", function()
		A.play("click")
		app.cycle_difficulty()
		self:refresh()
	end)
	b.scale:SetScript("OnClick", function() self:_cycle_scale() end)
	b.gems:SetScript("OnClick", function() self:_cycle_gems() end)
	b.close:SetScript("OnClick", function()
		A.play("click")
		app.close_menu()
	end)
	self:refresh()
	return self
end

local function onoff(v) return v and "On" or "Off" end

function Menu:refresh()
	local opts = self.app.db.options
	local b = self.buttons
	b.restart.text:SetText(self.confirming and "Really restart? Click again" or "Restart run")
	b.sound.text:SetText("Sound: " .. onoff(opts.sound ~= false))
	b.quiet.text:SetText("Quiet mode: " .. onoff(opts.quiet == true))
	b.shake.text:SetText("Screen shake: " .. onoff(opts.shake ~= false))
	b.difficulty.text:SetText("Difficulty: " .. self.app.difficulty_text())
	b.scale.text:SetText("Window: " .. Menu.SCALES[Menu.scale_index(opts.scale)][1])
	local A = ns.Assets
	b.gems.text:SetText("Gems: " .. (A.GEM_SET_LABEL[A.gem_set] or A.gem_set))
	b.close.text:SetText("Close")
end

function Menu:_on_restart()
	if not self.confirming then
		self.confirming = true
		ns.Assets.play("click")
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

function Menu:_cycle_scale()
	local i = Menu.scale_index(self.app.db.options.scale) % #Menu.SCALES + 1
	ns.Assets.play("click")
	self.app.set_option("scale", Menu.SCALES[i][2])
	self:refresh()
end

function Menu:_cycle_gems()
	local A = ns.Assets
	local order, cur = A.GEM_SET_ORDER, 1
	for i = 1, #order do
		if order[i] == A.gem_set then cur = i end
	end
	A.play("click")
	self.app.set_gem_set(order[cur % #order + 1])
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
