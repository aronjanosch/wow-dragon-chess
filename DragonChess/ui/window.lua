local addonName, ns = ...
-- Main window (W0-P1; fight-screen layout W0-P2). Static chrome only — the
-- fight widgets are built by ui/fight_view.lua on the frames returned here.
--
--   +--------------------------------------------------------------+
--   | title strip (drag handle)                       [II] [x]     |
--   | +-------------------------+ +-----------------------------+ |
--   | | board panel             | | enemy panel                 | |
--   | | (stage art, dimmed)     | | (stage art, full)           | |
--   | |   8 x 64 px board       | |  stage / name / weakness    | |
--   | |                         | |  queue column | enemy model | |
--   | +-------------------------+ +-----------------------------+ |
--   | [statuses] [ player HP ]  [SCORE]  [      enemy HP       ]  |
--   +--------------------------------------------------------------+
--
-- Movable by the title strip only, clamped, scale + position in
-- DragonChessDB.window (saved on drag stop). Close button / Esc
-- (via the Esc catcher, ui/menu.lua) hides it = pause; the pause button soft-pauses. Layers
-- (frame levels): panels < board (gems) < board fx < enemy fx < vignette <
-- overlay (soft pause / game over / error; eats clicks over the whole content).

local Window = {}

local FRAME_NAME = "DragonChessFrame" -- global name: UISpecialFrames needs it
local W, H = 1010, 588
local INSET = 6 -- content inset from the window edge (gold border)
local TITLE_H = 22
local PANEL_GAP = 4
local BOTTOM_H = 30 -- HP bar strip
local PANEL_PAD = 6 -- board inset inside the board panel

Window.W, Window.H = W, H

local function set_color(tex, c) tex:SetColorTexture(c[1], c[2], c[3], c[4]) end

local function backdrop(f, spec, bg, edge)
	f:SetBackdrop(spec)
	if bg then f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4]) end
	if edge then f:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4]) end
end

-- Small square text button (pause).
local function text_button(parent, A, label, width)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width or 20, 18)
	b:RegisterForClicks("LeftButtonUp")
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(b)
	set_color(bg, A.COLOR.BUTTON_BG)
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints(b)
	set_color(hl, A.COLOR.BUTTON_HL)
	local fs = b:CreateFontString(nil, "OVERLAY", A.FONT_LABEL_SMALL)
	fs:SetPoint("CENTER", b, "CENTER", 0, 0)
	fs:SetText(label)
	b.text = fs
	return b
end

-- db: DragonChessDB.window table; hooks: on_show, on_hide, on_overlay_click, on_pause, on_difficulty, on_menu,
-- on_drag(started) (optional; W0-P6 shake guard).
function Window.create(db, hooks)
	local A = ns.Assets
	local C = A.COLOR
	local cell = ns.BoardView.CELL
	local board_w, board_h = 8 * cell, 8 * cell
	local panel_h = board_h + 2 * PANEL_PAD
	local board_panel_w = board_w + 2 * PANEL_PAD
	local enemy_panel_w = W - 2 * INSET - board_panel_w - PANEL_GAP

	local f = CreateFrame("Frame", FRAME_NAME, UIParent, A.TEMPLATE_BACKDROP)
	f:Hide() -- scripts are set below; the first Show() fires OnShow
	f:SetSize(W, H)
	f:SetFrameStrata("HIGH")
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	if f.SetDontSavePosition then f:SetDontSavePosition(true) end
	f:EnableMouse(true) -- swallow clicks on the frame border
	backdrop(f, A.BACKDROP_WINDOW, C.WINDOW_BG, C.WINDOW_EDGE)

	-- Title strip: the only handle that moves the window.
	local title = CreateFrame("Frame", nil, f)
	title:SetPoint("TOPLEFT", f, "TOPLEFT", INSET, -4)
	title:SetPoint("TOPRIGHT", f, "TOPRIGHT", -156, -4)
	title:SetHeight(TITLE_H - 2)
	title:EnableMouse(true)
	title:RegisterForDrag("LeftButton")
	local label = title:CreateFontString(nil, "OVERLAY", A.FONT_TITLE)
	label:SetPoint("LEFT", title, "LEFT", 6, 0)
	label:SetText("Dragon Chess")
	title:SetScript("OnDragStart", function()
		if hooks.on_drag then hooks.on_drag(true) end -- W0-P6: ends a screen shake before the window moves
		f:StartMoving()
	end)
	title:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
		if hooks.on_drag then hooks.on_drag(false) end
		local point, _, rel, x, y = f:GetPoint(1)
		db.point, db.rel, db.x, db.y = point, rel, x, y
	end)

	local close = CreateFrame("Button", nil, f, A.TEMPLATE_CLOSE)
	close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	close:SetScript("OnClick", function() f:Hide() end)

	local pause = text_button(f, A, "II")
	pause:SetPoint("RIGHT", close, "LEFT", -2, 0)
	pause:SetScript("OnClick", function() hooks.on_pause() end)

	-- Difficulty chooser (W0-G2b): click cycles the unlocked difficulties for the next run
	-- (the label is kept by ui/main.lua; /dchess difficulty N does the same).
	local diff = text_button(f, A, "D1", 44)
	diff:SetPoint("RIGHT", pause, "LEFT", -4, 0)
	diff:SetScript("OnClick", function() hooks.on_difficulty() end)

	-- Menu button (W0-P4): restart, sound, scale (ui/menu.lua).
	local menu_button = text_button(f, A, "Menu", 40)
	menu_button:SetPoint("RIGHT", diff, "LEFT", -4, 0)
	menu_button:SetScript("OnClick", function() hooks.on_menu() end)

	-- Debug panel button (playtest 4: dev builds only; remove for the release, W3).
	local debug_button = text_button(f, A, "Debug", 48)
	debug_button:SetPoint("RIGHT", menu_button, "LEFT", -4, 0)
	debug_button:SetScript("OnClick", function() if hooks.on_debug then hooks.on_debug() end end)

	local top = -(TITLE_H + 2)

	-- Board panel: stage art dimmed by a dark layer, thin frame.
	local board_panel = CreateFrame("Frame", nil, f, A.TEMPLATE_BACKDROP)
	board_panel:SetPoint("TOPLEFT", f, "TOPLEFT", INSET, top)
	board_panel:SetSize(board_panel_w, panel_h)
	local board_bg = board_panel:CreateTexture(nil, "BACKGROUND", nil, 0)
	board_bg:SetAllPoints(board_panel)
	local board_dim = board_panel:CreateTexture(nil, "BACKGROUND", nil, 1)
	board_dim:SetAllPoints(board_panel)
	set_color(board_dim, C.BOARD_DIM)
	board_panel:SetBackdrop({ edgeFile = A.BACKDROP_PANEL.edgeFile, edgeSize = A.BACKDROP_PANEL.edgeSize })
	board_panel:SetBackdropBorderColor(C.PANEL_EDGE[1], C.PANEL_EDGE[2], C.PANEL_EDGE[3], C.PANEL_EDGE[4])

	-- Enemy panel: stage art at full brightness.
	local enemy_panel = CreateFrame("Frame", nil, f, A.TEMPLATE_BACKDROP)
	enemy_panel:SetPoint("TOPLEFT", board_panel, "TOPRIGHT", PANEL_GAP, 0)
	enemy_panel:SetSize(enemy_panel_w, panel_h)
	local enemy_bg = enemy_panel:CreateTexture(nil, "BACKGROUND", nil, 0)
	enemy_bg:SetAllPoints(enemy_panel)
	enemy_panel:SetBackdrop({ edgeFile = A.BACKDROP_PANEL.edgeFile, edgeSize = A.BACKDROP_PANEL.edgeSize })
	enemy_panel:SetBackdropBorderColor(C.PANEL_EDGE[1], C.PANEL_EDGE[2], C.PANEL_EDGE[3], C.PANEL_EDGE[4])

	-- Board frame (input target; never moves the window).
	local host = CreateFrame("Frame", nil, board_panel)
	host:SetPoint("TOPLEFT", board_panel, "TOPLEFT", PANEL_PAD, -PANEL_PAD)
	host:SetSize(board_w, board_h)

	-- FX layer over the board: swap feedback (mouse not enabled, so clicks
	-- reach the board). Above the gems, below the overlay.
	local fx = CreateFrame("Frame", nil, f)
	fx:SetAllPoints(host)
	fx:SetFrameLevel(host:GetFrameLevel() + 15)

	-- FX layer over the enemy panel: banner, CLEARED, damage numbers.
	local enemy_fx = CreateFrame("Frame", nil, f)
	enemy_fx:SetAllPoints(enemy_panel)
	enemy_fx:SetFrameLevel(host:GetFrameLevel() + 16)

	-- Bottom strip: statuses + player HP | score plaque | enemy HP.
	local bottom = CreateFrame("Frame", nil, f)
	bottom:SetPoint("TOPLEFT", board_panel, "BOTTOMLEFT", 0, -PANEL_GAP)
	bottom:SetSize(W - 2 * INSET, BOTTOM_H)
	bottom:SetFrameLevel(host:GetFrameLevel() + 17)

	-- Content area (both panels + bottom strip): vignette + overlay cover it.
	local content = CreateFrame("Frame", nil, f)
	content:SetPoint("TOPLEFT", board_panel, "TOPLEFT", 0, 0)
	content:SetSize(W - 2 * INSET, panel_h + PANEL_GAP + BOTTOM_H)
	content:SetFrameLevel(host:GetFrameLevel() + 18)

	-- Soft-pause / game-over / error overlay (eats clicks; click = resume / retry).
	local overlay = CreateFrame("Button", nil, f)
	overlay:SetAllPoints(content)
	overlay:SetFrameLevel(host:GetFrameLevel() + 30)
	overlay:RegisterForClicks("LeftButtonUp")
	local obg = overlay:CreateTexture(nil, "BACKGROUND")
	obg:SetAllPoints(overlay)
	set_color(obg, C.OVERLAY)
	local box = CreateFrame("Frame", nil, overlay, A.TEMPLATE_BACKDROP)
	box:SetSize(340, 130)
	box:SetPoint("CENTER", overlay, "CENTER", 0, 20)
	backdrop(box, A.BACKDROP_DIALOG)
	local otext = box:CreateFontString(nil, "OVERLAY", A.FONT_OVERLAY)
	otext:SetPoint("CENTER", box, "CENTER", 0, 0)
	overlay.text = otext
	overlay.box = box
	overlay:SetScript("OnClick", function() hooks.on_overlay_click() end)
	overlay:Hide()

	f:SetScript("OnShow", function() hooks.on_show() end)
	f:SetScript("OnHide", function() hooks.on_hide() end)

	-- Restore position / scale (missing values = defaults: an empty DB is a
	-- normal first run).
	f:ClearAllPoints()
	if type(db.point) == "string" and type(db.x) == "number" and type(db.y) == "number" then
		f:SetPoint(db.point, UIParent, type(db.rel) == "string" and db.rel or db.point, db.x, db.y)
	else
		f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end
	local scale = tonumber(db.scale)
	if scale == nil or scale < 0.5 or scale > 2 then scale = 1 end
	f:SetScale(scale)

	-- Esc: not registered here; ui/menu.lua's Esc catcher closes the menu first, then the window.

	return {
		frame = f, title = title, close = close, pause = pause, difficulty = diff, menu_button = menu_button,
		board_panel = board_panel, board_bg = board_bg, board_dim = board_dim,
		enemy_panel = enemy_panel, enemy_bg = enemy_bg,
		host = host, fx = fx, enemy_fx = enemy_fx, bottom = bottom, content = content,
		overlay = overlay,
		panel_h = panel_h, board_panel_w = board_panel_w, enemy_panel_w = enemy_panel_w,
		pad = PANEL_PAD, gap = PANEL_GAP, bottom_h = BOTTOM_H, -- layout numbers (ui/juice.lua works in board-local px)
	}
end

-- Show / hide the overlay with a message.
function Window.set_overlay(win, text)
	if text == nil then
		win.overlay:Hide()
	else
		win.overlay.text:SetText(text)
		-- the box grows with the text (win / loss overlays have several lines)
		local lines = 1
		for _ in text:gmatch("\n") do lines = lines + 1 end
		local h = 36 + 22 * lines
		win.overlay.box:SetSize(360, h < 130 and 130 or h)
		win.overlay:Show()
	end
end

ns.Window = Window
