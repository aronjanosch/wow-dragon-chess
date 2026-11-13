local addonName, ns = ...
-- Result screen (W0-P12): shown instead of the text overlay when a run is lost or won. Presentation only: ui/main.lua
-- writes the records and hands over a table (App.result):
--   { won, score, best, new_best, unlocked, difficulty, class_id, enemy, stage, fight, dev, fights }
-- The button leads to the start screen (App.new_run_from_result). Same level as the start panel (never both shown),
-- below the in-window menu; ui/main.lua hides it while an error / soft-pause / stuck overlay is up.

local ResultMenu = {}
ResultMenu.__index = ResultMenu

local LEVEL_ABOVE_HOST = 35
local PAD = 20
local W = 340
local Y_CLASS = 40
local Y_WHO = Y_CLASS + 24
local Y_DIFF = Y_WHO + 18
local Y_SCORE_LABEL = Y_DIFF + 26
local Y_SCORE = Y_SCORE_LABEL + 14
local Y_BEST = Y_SCORE + 36
local Y_NEW_BEST = Y_BEST + 22
local Y_UNLOCK = Y_NEW_BEST + 24
local Y_BUTTON = Y_UNLOCK + 30
local H = Y_BUTTON + 28 + PAD

ResultMenu.W, ResultMenu.H = W, H

local function label(parent, font, justify)
	local fs = ns.Panel.font_string(parent, font)
	if justify ~= nil then fs:SetJustifyH(justify) end
	return fs
end

-- win: Window.create's table; app: the App table (new_run_from_result). Returns the screen (frame, buttons).
function ResultMenu.create(win, app)
	local A, P = ns.Assets, ns.Panel
	local self = setmetatable({ app = app }, ResultMenu)
	self.frame = P.scrim(win, LEVEL_ABOVE_HOST)
	local box = P.dialog(self.frame, W, H, "Defeated")
	box:SetPoint("CENTER", self.frame, "CENTER", 0, 20)
	box:SetFrameLevel(self.frame:GetFrameLevel() + 1)
	self.box = box
	self.class_line = label(box, A.FONT_PANEL_BIG)
	self.class_line:SetPoint("TOP", box, "TOP", 0, -Y_CLASS)
	self.who_line = label(box, A.FONT_PANEL_TEXT)
	self.who_line:SetPoint("TOP", box, "TOP", 0, -Y_WHO)
	self.diff_line = label(box, A.FONT_HUD_SMALL)
	self.diff_line:SetPoint("TOP", box, "TOP", 0, -Y_DIFF)
	local dim = A.COLOR.TEXT_DIM
	self.diff_line:SetTextColor(dim[1], dim[2], dim[3], dim[4])
	self.score_label = label(box, A.FONT_LABEL_SMALL)
	self.score_label:SetPoint("TOP", box, "TOP", 0, -Y_SCORE_LABEL)
	self.score_label:SetText("Score")
	self.score = label(box, A.FONT_PANEL_HUGE)
	self.score:SetPoint("TOP", box, "TOP", 0, -Y_SCORE)
	self.best = label(box, A.FONT_PANEL_TEXT)
	self.best:SetPoint("TOP", box, "TOP", 0, -Y_BEST)
	self.new_best = label(box, A.FONT_PANEL_BIG)
	self.new_best:SetPoint("TOP", box, "TOP", 0, -Y_NEW_BEST)
	self.new_best:SetText("New best!")
	local gold = A.COLOR.TITLE_GOLD
	self.new_best:SetTextColor(gold[1], gold[2], gold[3], gold[4])
	self.unlock = label(box, A.FONT_PANEL_TEXT)
	self.unlock:SetPoint("TOP", box, "TOP", 0, -Y_UNLOCK)
	local good = A.COLOR.TEXT_GOOD
	self.unlock:SetTextColor(good[1], good[2], good[3], good[4])
	self.buttons = { new_run = P.primary(box, "New run") }
	self.buttons.new_run:SetPoint("TOP", box, "TOP", 0, -Y_BUTTON)
	P.on_click(self.buttons.new_run, function() app.new_run_from_result() end)
	return self
end

-- r: the result table (missing fields are tolerated: a result screen must never fail).
function ResultMenu:refresh(r)
	local A = ns.Assets
	r = r or {}
	local won = r.won == true
	self.box.set_title(won and "Victory" or "Defeated", won and A.COLOR.TITLE_GOLD or A.COLOR.TITLE_LOSS)
	local class = r.class_id ~= nil and ns.Classes[r.class_id] or nil
	if class ~= nil then
		local cr, cg, cb = A.class_color(r.class_id)
		self.class_line:SetTextColor(cr, cg, cb, 1)
		self.class_line:SetText(class.name)
	else
		self.class_line:SetTextColor(1, 1, 1, 1)
		self.class_line:SetText("Classic")
	end
	local who
	if won then
		who = "All " .. tostring(r.fights or 10) .. " enemies defeated"
	else
		who = "Fell to " .. tostring(r.enemy or "the enemy")
		if r.stage ~= nil and r.fight ~= nil and not r.dev then who = who .. " (" .. r.stage .. "-" .. r.fight .. ")" end
	end
	self.who_line:SetText(who)
	self.diff_line:SetText("Difficulty " .. tostring(r.difficulty or 1))
	self.score:SetText(tostring(r.score or 0))
	self.best:SetText("Best (D" .. tostring(r.difficulty or 1) .. "): " .. tostring(r.best or 0))
	if r.new_best then self.new_best:Show() else self.new_best:Hide() end
	if r.unlocked ~= nil then
		self.unlock:SetText("Difficulty " .. r.unlocked .. " unlocked")
		self.unlock:Show()
	else
		self.unlock:Hide()
	end
	ns.Panel.set_text(self.buttons.new_run, "New run")
end

function ResultMenu:open(r)
	self:refresh(r)
	self.frame:Show()
end

function ResultMenu:close()
	self.frame:Hide()
end

function ResultMenu:is_open()
	return self.frame:IsShown()
end

ns.ResultMenu = ResultMenu
