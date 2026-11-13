local addonName, ns = ...
-- Start / pause panel (W0-P10, dialog style W0-P12): shown over the content area every time the window opens. No game
-- rules (ui/main.lua decides the form and owns the pause: App.start_open blocks tick and input like App.menu_open).
--   "start"  no run in progress: header "Dragon Chess", section Class (9 icons, the chosen class's name), section Spells
--            (6 gem colours x skill / ultimate, tooltips), section Difficulty (5 segments, locked ones greyed, the
--            best score of the selected one), Start, a hint line.
--   "resume" a run is in progress: header "Paused", class / stage / difficulty / score, Continue, Options (opens the
--            options panel, ui/menu.lua), New run (inline confirm, the first click arms it).
-- All widgets come from ui/panel.lua and are created once; refresh only re-reads state.
-- Level: above the result screen's dim, below the in-window menu (so the Menu button stays usable).

local StartMenu = {}
StartMenu.__index = StartMenu

local LEVEL_ABOVE_HOST = 35
local PAD = 20
local SEP = " \194\183 " -- middle dot (in the range every WoW font has)

-- Start form (all sizes in px; y is measured from the dialog's top edge).
local W_START = 440
local INNER_W = W_START - 2 * PAD -- 400
local CLASS_SIZE, CLASS_PITCH = 36, 44
local CLASS_BORDER = 2
local CLASS_NAME_H = 18
local PREVIEW_COLS, SPELL_SIZE, SPELL_PITCH, GEM_SIZE = 6, 36, 56, 18
local TAG_W, TAG_GAP = 24, 6 -- "4" / "5+" tags left of the two spell rows
local DIFF_SEG_W = 216 -- 5 x 40 + 4 x 4
local DIFFS = 5
local HINT_H = 12
local ROW_GAP = 4
local Y_SEC_CLASS = 40
local Y_CLASS = Y_SEC_CLASS + 20
local Y_CLASS_NAME = Y_CLASS + CLASS_SIZE + 4
local Y_SEC_SPELLS = Y_CLASS_NAME + CLASS_NAME_H + 8
local Y_GEM = Y_SEC_SPELLS + 22
local Y_SKILL = Y_GEM + GEM_SIZE + 4
local Y_ULT = Y_SKILL + SPELL_SIZE + ROW_GAP
local Y_SEC_DIFF = Y_ULT + SPELL_SIZE + 8
local Y_DIFF = Y_SEC_DIFF + 22
local Y_START = Y_DIFF + 22 + 12
local Y_HINT = Y_START + 28 + 8
local H_START = Y_HINT + HINT_H + PAD

-- Pause form.
local W_RESUME = 300
local WIDE_BTN_W, WIDE_BTN_H = 220, 24
local Y_R_CLASS = 40
local Y_R_STAGE = Y_R_CLASS + 24
local Y_R_SCORE = Y_R_STAGE + 20
local Y_R_CONTINUE = Y_R_SCORE + 28
local Y_R_OPTIONS = Y_R_CONTINUE + 28 + 10
local Y_R_NEW = Y_R_OPTIONS + WIDE_BTN_H + 6
local H_RESUME = Y_R_NEW + WIDE_BTN_H + PAD

StartMenu.W_START, StartMenu.H_START, StartMenu.W_RESUME, StartMenu.H_RESUME = W_START, H_START, W_RESUME, H_RESUME

local function label(parent, font, justify)
	local fs = ns.Panel.font_string(parent, font)
	if justify ~= nil then fs:SetJustifyH(justify) end
	return fs
end

-- Class icons + name, the 6 x 2 spell preview, the difficulty row, Start, the hint (start form).
function StartMenu:_build_start(box, A)
	local P = ns.Panel
	local g = CreateFrame("Frame", nil, box)
	g:SetAllPoints(box)
	self.start_group = g

	local sec = P.section(g, "Class", INNER_W)
	sec:SetPoint("TOPLEFT", g, "TOPLEFT", PAD, -Y_SEC_CLASS)
	local order = ns.Classes.ORDER
	local row_w = (#order - 1) * CLASS_PITCH + CLASS_SIZE
	local left = (W_START - row_w) / 2
	self.class_buttons = {}
	for i = 1, #order do
		local id = order[i]
		local b = P.icon(g, CLASS_SIZE, CLASS_BORDER, false)
		b:SetPoint("TOPLEFT", g, "TOPLEFT", left + (i - 1) * CLASS_PITCH, -Y_CLASS)
		b:RegisterForClicks("LeftButtonUp")
		b.class_id = id
		local r, gr, bl = A.class_color(id)
		b.cr, b.cg, b.cb = r, gr, bl
		local l, rr, t, bb = A.class_coords(id)
		if l ~= nil then
			b.icon:SetTexture(A.CLASS_ICONS)
			b.icon:SetTexCoord(l, rr, t, bb)
		else -- no icon sheet / coords: a plain coloured button with the class initial
			b.icon:SetColorTexture(r, gr, bl, 0.8)
			local init = label(b, A.FONT_HUD_SMALL)
			init:SetPoint("CENTER", b, "CENTER", 0, 0)
			init:SetText(ns.Classes[id].name:sub(1, 1))
			b.initial = init
		end
		P.on_click(b, function()
			self.app.set_class(id)
			self:refresh()
		end)
		b:SetScript("OnEnter", function() P.show_tip(b, ns.Classes[id].name, {}) end)
		b:SetScript("OnLeave", P.hide_tip)
		self.class_buttons[i] = b
	end
	self.class_name = label(g, A.FONT_PANEL_BIG)
	self.class_name:SetPoint("TOP", g, "TOP", 0, -Y_CLASS_NAME)

	local sec2 = P.section(g, "Spells", INNER_W)
	sec2:SetPoint("TOPLEFT", g, "TOPLEFT", PAD, -Y_SEC_SPELLS)
	-- per colour: the gem on top, the skill and the ultimate icon below (buttons, for the tooltip)
	local grid_w = (PREVIEW_COLS - 1) * SPELL_PITCH + SPELL_SIZE
	local x0 = math.floor((W_START - (TAG_W + TAG_GAP + grid_w)) / 2) + TAG_W + TAG_GAP
	for tier = 1, 2 do
		local tag = label(g, A.FONT_LABEL_SMALL, "RIGHT")
		tag:SetSize(TAG_W, 12)
		local y = tier == 1 and Y_SKILL or Y_ULT
		tag:SetPoint("RIGHT", g, "TOPLEFT", x0 - TAG_GAP, -(y + SPELL_SIZE / 2))
		tag:SetText(tier == 1 and "4" or "5+")
	end
	self.preview, self.preview_gems = {}, {}
	for color = 0, PREVIEW_COLS - 1 do
		local x = x0 + color * SPELL_PITCH
		local gem = g:CreateTexture(nil, "ARTWORK")
		gem:SetSize(GEM_SIZE, GEM_SIZE)
		gem:SetPoint("TOP", g, "TOPLEFT", x + SPELL_SIZE / 2, -Y_GEM)
		self.preview_gems[color] = gem -- texture set in _refresh_picker (follows the chosen gem set)
		for tier = 1, 2 do
			local b = P.icon(g, SPELL_SIZE)
			b:SetPoint("TOPLEFT", g, "TOPLEFT", x, -(tier == 1 and Y_SKILL or Y_ULT))
			b.color, b.tier = color, tier
			b:SetScript("OnEnter", function() self:_spell_tip(b) end)
			b:SetScript("OnLeave", P.hide_tip)
			self.preview[color * 2 + tier] = b
		end
	end

	local sec3 = P.section(g, "Difficulty", INNER_W)
	sec3:SetPoint("TOPLEFT", g, "TOPLEFT", PAD, -Y_SEC_DIFF)
	local labels = {}
	for d = 1, DIFFS do labels[d] = tostring(d) end
	self.diff = P.segment(g, labels, DIFF_SEG_W)
	self.diff:SetPoint("TOPLEFT", g, "TOPLEFT", PAD, -Y_DIFF)
	self.diff.on_pick = function(d)
		self.app.set_difficulty(d)
		self:refresh()
	end
	self.best = label(g, A.FONT_HUD_SMALL, "RIGHT")
	self.best:SetPoint("TOPRIGHT", g, "TOPRIGHT", -PAD, -(Y_DIFF + 5))

	self.buttons.start = P.primary(g, "Start")
	self.buttons.start:SetPoint("TOP", g, "TOP", 0, -Y_START)
	P.on_click(self.buttons.start, function() self.app.close_start() end)

	self.hint = label(g, A.FONT_HUD_SMALL)
	self.hint:SetPoint("TOP", g, "TOP", 0, -Y_HINT)
	local d = A.COLOR.TEXT_DIM
	self.hint:SetTextColor(d[1], d[2], d[3], d[4])
	self.hint:SetText("Match 3 to attack" .. SEP .. "4 makes a skill gem" .. SEP .. "5+ an ultimate")
end

-- Class / stage / difficulty / score lines, Continue, Options, New run (pause form).
function StartMenu:_build_resume(box, A)
	local P = ns.Panel
	local g = CreateFrame("Frame", nil, box)
	g:SetAllPoints(box)
	self.resume_group = g
	self.class_line = label(g, A.FONT_PANEL_BIG)
	self.class_line:SetPoint("TOP", g, "TOP", 0, -Y_R_CLASS)
	self.stage_line = label(g, A.FONT_PANEL_TEXT)
	self.stage_line:SetPoint("TOP", g, "TOP", 0, -Y_R_STAGE)
	self.score_line = label(g, A.FONT_PANEL_TEXT)
	self.score_line:SetPoint("TOP", g, "TOP", 0, -Y_R_SCORE)
	local b = self.buttons
	b.continue = P.primary(g, "Continue")
	b.continue:SetPoint("TOP", g, "TOP", 0, -Y_R_CONTINUE)
	P.on_click(b.continue, function() self.app.close_start() end)
	b.options = P.button(g, WIDE_BTN_W, WIDE_BTN_H, "Options")
	b.options:SetPoint("TOP", g, "TOP", 0, -Y_R_OPTIONS)
	P.on_click(b.options, function() self.app.open_menu() end)
	b.new_run = P.button(g, WIDE_BTN_W, WIDE_BTN_H, "New run")
	b.new_run:SetPoint("TOP", g, "TOP", 0, -Y_R_NEW)
	P.on_click(b.new_run, function()
		if not self.confirming then
			self.confirming = true
			self:refresh()
			return
		end
		self.confirming = false
		self.app.new_run_from_start()
	end)
end

-- Tooltip of a preview icon: spell name, "Skill" / "Ultimate" + colour, the description with its numbers.
function StartMenu:_spell_tip(b)
	local ability = self.preview_kit ~= nil and self.preview_kit:get(b.color, b.tier) or nil
	if ability == nil then return end
	local colour = ns.Combat.COLOR_NAMES[b.color] or ""
	local kind = b.tier == 2 and "Ultimate" or "Skill"
	ns.Panel.show_tip(b, ability.name, { kind .. " - " .. colour, ns.Kit.format_text(ability, ability.description or "") })
end

-- win: Window.create's table; app: the App table (selected_class, set_class, selected_difficulty, set_difficulty, db, run,
-- combat, close_start, open_menu, new_run_from_start). Returns the panel (frame, buttons, form).
function StartMenu.create(win, app)
	local A = ns.Assets
	local self = setmetatable({ app = app, confirming = false, form = "start", buttons = {} }, StartMenu)
	self.frame = ns.Panel.scrim(win, LEVEL_ABOVE_HOST)
	local box = ns.Panel.dialog(self.frame, W_START, H_START, "Dragon Chess")
	box:SetPoint("CENTER", self.frame, "CENTER", 0, 20)
	box:SetFrameLevel(self.frame:GetFrameLevel() + 1)
	self.box, self.title = box, box.title
	self:_build_start(box, A)
	self:_build_resume(box, A)
	return self
end

-- Class picker state: highlight, name, preview icons (start form only).
function StartMenu:_refresh_picker()
	local A = ns.Assets
	local sel = self.app.selected_class()
	for i = 1, #self.class_buttons do
		local b = self.class_buttons[i]
		local on = b.class_id == sel
		if on then
			b.set_border(b.cr, b.cg, b.cb, 1) -- class-coloured frame
		else
			local c = A.COLOR.CLASS_IDLE
			b.set_border(c[1], c[2], c[3], c[4])
		end
		local d = on and 1 or A.COLOR.CLASS_DIM
		b.icon:SetVertexColor(d, d, d)
	end
	local class = sel ~= nil and ns.Classes[sel] or nil
	if class ~= nil then
		local r, g, bl = A.class_color(sel)
		self.class_name:SetTextColor(r, g, bl, 1)
		self.class_name:SetText(class.name)
	else
		self.class_name:SetTextColor(1, 1, 1, 1)
		self.class_name:SetText("Classic")
	end
	self.preview_kit = ns.Kit.for_class(sel)
	for color = 0, PREVIEW_COLS - 1 do A.apply_gem(self.preview_gems[color], color) end
	for i = 1, #self.preview do
		local b = self.preview[i]
		local ability = self.preview_kit:get(b.color, b.tier)
		b.icon:SetTexture(A.icon(ability ~= nil and ability.icon or nil))
	end
end

-- Difficulty row: selection, locked levels, the best score of the selected level.
function StartMenu:_refresh_difficulty()
	local db = self.app.db
	local sel = self.app.selected_difficulty()
	self.diff.select(sel)
	for d = 1, DIFFS do
		local can = ns.Run.can_choose(db, d)
		self.diff.set_enabled(d, can)
		self.diff.buttons[d].dc_tip = (not can) and { "Difficulty " .. d, { "Win difficulty " .. (d - 1) .. " to unlock" } } or nil
	end
	local best = ns.Run.best_score(db, sel)
	self.best:SetText("Best: " .. (best > 0 and tostring(best) or "-"))
end

-- Pause form lines from the live run.
function StartMenu:_refresh_resume()
	local A = ns.Assets
	local app = self.app
	local combat, run = app.combat, app.run
	local class = combat ~= nil and combat.kit.class_id ~= nil and ns.Classes[combat.kit.class_id] or nil
	if class ~= nil then
		local r, g, bl = A.class_color(combat.kit.class_id)
		self.class_line:SetTextColor(r, g, bl, 1)
		self.class_line:SetText(class.name)
	else
		self.class_line:SetTextColor(1, 1, 1, 1)
		self.class_line:SetText("Classic")
	end
	if run ~= nil then
		local name = A.STAGE_NAME[run:stage()]
		local where = run.forced ~= nil and "Dev fight" or ((name ~= nil and name .. " " or "") .. run:stage() .. "-" .. run:fight_in_stage())
		self.stage_line:SetText(where .. SEP .. "Difficulty " .. run.difficulty)
	else
		self.stage_line:SetText("")
	end
	self.score_line:SetText("Score " .. tostring(combat ~= nil and combat.score or 0))
end

function StartMenu:refresh()
	local resume = self.form == "resume"
	self.box.set_title(resume and "Paused" or "Dragon Chess")
	local b = self.buttons
	ns.Panel.set_text(b.new_run, self.confirming and "Abandon this run? Click again" or "New run")
	if resume then
		self.start_group:Hide()
		self:_refresh_resume()
		self.resume_group:Show()
		self.box:SetSize(W_RESUME, H_RESUME)
	else
		self.resume_group:Hide()
		self:_refresh_picker()
		self:_refresh_difficulty()
		self.start_group:Show()
		self.box:SetSize(W_START, H_START)
	end
end

-- form: "start" | "resume"
function StartMenu:open(form)
	self.form = form == "resume" and "resume" or "start"
	self.confirming = false
	self:refresh()
	self.frame:Show()
end

function StartMenu:close()
	self.confirming = false
	ns.Panel.hide_tip()
	self.frame:Hide()
end

function StartMenu:is_open()
	return self.frame:IsShown()
end

ns.StartMenu = StartMenu
