local addonName, ns = ...
-- Panel kit (W0-P12): the widgets of all four menus (start, pause, result, options) in one WoW dialog style.
-- No game logic. Native Blizzard widgets (UIPanelButtonTemplate, UICheckButtonTemplate, the dialog header plate)
-- are created through a guard: when the template is missing or the object lacks the expected methods, the flat
-- widget below is built instead, never an error. Every template / texture / font / colour name is in ui/assets.lua.
--
-- Label API (native and flat widgets look the same to callers):
--   Panel.set_text(button, text)   sets the label and remembers it in button.dc_text
--   Panel.set_enabled(button, on)  native Enable / Disable, flat dim look; a disabled button ignores clicks
--   Panel.on_click(button, fn)     click sound + fn(), unless disabled
--   check.set_checked(v), check.set_dim(v), segment.select(i), segment.set_enabled(i, on)

local Panel = {}

local HEADER_W, HEADER_H = 256, 64 -- UI-DialogBox-Header plate
local HEADER_RISE = 12 -- the plate sticks out above the dialog
local HEADER_TITLE_Y = -2 -- title y below the dialog's top edge (plate top - 14)
local FLAT_TITLE_Y = -10 -- title y when the plate texture is missing
Panel.CONTENT_TOP = 40 -- y of the first content row below the dialog's top edge
Panel.HEADER_RISE = HEADER_RISE
local SECTION_H = 16
local SEG_H = 22
local SEG_GAP = 4
local CHECK_NATIVE, CHECK_FLAT = 26, 16 -- check box sizes
local CHECK_LABEL_GAP = 4
local LABEL_HIT_W = 180 -- the check's click area reaches over its label
local ICON_BORDER_PX = 1
local DIM_ALPHA = 0.5

Panel.SECTION_H, Panel.SEG_H, Panel.SEG_GAP = SECTION_H, SEG_H, SEG_GAP

local function set_color(tex, c) tex:SetColorTexture(c[1], c[2], c[3], c[4]) end

local function text_color(fs, c) fs:SetTextColor(c[1], c[2], c[3], c[4]) end

-- True when obj[name] is a function (a stub / client object may raise for an unknown method).
local function has(obj, name)
	local ok, v = pcall(function() return obj[name] end)
	return ok and type(v) == "function"
end

-- A frame from a Blizzard template, or nil when CreateFrame fails or the object lacks a method in `needs`.
local function native_frame(ftype, parent, template, needs)
	local ok, f = pcall(CreateFrame, ftype, nil, parent, template)
	if not ok or type(f) ~= "table" then return nil end
	for i = 1, #needs do
		if not has(f, needs[i]) then
			pcall(function() f:Hide() end) -- cannot be released; kept hidden
			return nil
		end
	end
	return f
end

-- A font string; a missing font object falls back to the small HUD font instead of an error.
local function font_string(parent, font)
	local A = ns.Assets
	local ok, fs = pcall(parent.CreateFontString, parent, nil, "OVERLAY", font)
	if ok and fs ~= nil then return fs end
	return parent:CreateFontString(nil, "OVERLAY", A.FONT_HUD_SMALL)
end
Panel.font_string = font_string

---------------------------------------------------------------- tooltip

function Panel.show_tip(owner, title, lines)
	if type(GameTooltip) ~= "table" then return end
	pcall(function()
		GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
		GameTooltip:SetText(title)
		for i = 1, #(lines or {}) do GameTooltip:AddLine(lines[i], 1, 1, 1, true) end
		GameTooltip:Show()
	end)
end

function Panel.hide_tip()
	if type(GameTooltip) == "table" then pcall(GameTooltip.Hide, GameTooltip) end
end

---------------------------------------------------------------- dialog

-- A click-eating dim over `win.content`, `above` frame levels above the board host. Returns the frame.
function Panel.scrim(win, above)
	local A = ns.Assets
	local dim = CreateFrame("Frame", nil, win.frame)
	dim:SetAllPoints(win.content)
	dim:SetFrameLevel(win.host:GetFrameLevel() + above)
	dim:EnableMouse(true)
	local dtex = dim:CreateTexture(nil, "BACKGROUND")
	dtex:SetAllPoints(dim)
	set_color(dtex, A.COLOR.OVERLAY)
	dim:Hide()
	return dim
end

-- The framed dialog with its header plate. frame.title is the title font string (frame.set_title(text, colour?)).
function Panel.dialog(parent, w, h, title)
	local A = ns.Assets
	local f = CreateFrame("Frame", nil, parent, A.TEMPLATE_BACKDROP)
	f:SetBackdrop(A.BACKDROP_DIALOG)
	f:SetSize(w, h)
	f:EnableMouse(true) -- eats clicks over the board
	local plate = f:CreateTexture(nil, "ARTWORK")
	plate:SetTexture(A.TEXTURE_HEADER)
	plate:SetSize(HEADER_W, HEADER_H)
	plate:SetPoint("TOP", f, "TOP", 0, HEADER_RISE)
	local loaded = plate:GetTexture() ~= nil
	if not loaded then plate:Hide() end -- no plate: the title sits on the plain dialog
	f.plate = plate
	f.title = font_string(f, A.FONT_TITLE)
	f.title:SetPoint("TOP", f, "TOP", 0, loaded and HEADER_TITLE_Y or FLAT_TITLE_Y)
	f.title:SetText(title or "")
	f.set_title = function(text, colour)
		f.title:SetText(text)
		local c = colour or A.COLOR.TITLE_GOLD
		text_color(f.title, c)
	end
	return f
end

---------------------------------------------------------------- buttons

-- Flat fallback button: colour quads, a centred font string (b.dc_fs).
local function flat_button(parent, w, h, font)
	local A = ns.Assets
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w, h)
	b:RegisterForClicks("LeftButtonUp")
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(b)
	set_color(bg, A.COLOR.BUTTON_BG)
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints(b)
	set_color(hl, A.COLOR.BUTTON_HL)
	b.dc_fs = font_string(b, font)
	b.dc_fs:SetPoint("CENTER", b, "CENTER", 0, 0)
	return b
end

-- font: optional font object name for the label (primary buttons).
function Panel.button(parent, w, h, label, font)
	local A = ns.Assets
	local b = native_frame("Button", parent, A.TEMPLATE_BUTTON, { "SetText", "Enable", "Disable" })
	if b ~= nil then
		b:SetSize(w, h)
		b:RegisterForClicks("LeftButtonUp")
		b.dc_native = true
		if font ~= nil and has(b, "GetFontString") then
			local ok, fs = pcall(b.GetFontString, b)
			if ok and fs ~= nil then pcall(fs.SetFontObject, fs, font) end
		end
	else
		b = flat_button(parent, w, h, font or A.FONT_HUD_SMALL)
	end
	Panel.set_text(b, label or "")
	return b
end

-- The big button of a form (Start, Continue, New run): 160 x 28, large label.
Panel.PRIMARY_W, Panel.PRIMARY_H = 160, 28
function Panel.primary(parent, label)
	return Panel.button(parent, Panel.PRIMARY_W, Panel.PRIMARY_H, label, ns.Assets.FONT_PANEL_BIG)
end

function Panel.set_text(b, text)
	b.dc_text = text
	if b.dc_native then
		b:SetText(text)
	elseif b.dc_fs ~= nil then
		b.dc_fs:SetText(text)
	end
end

function Panel.set_enabled(b, on)
	b.dc_disabled = not on
	if b.dc_native then
		pcall(function()
			if on then b:Enable() else b:Disable() end
		end)
	elseif b.dc_fs ~= nil then
		text_color(b.dc_fs, on and ns.Assets.COLOR.SEG_TEXT or ns.Assets.COLOR.SEG_TEXT_OFF)
	end
end

-- Click handler: the click sound, then fn(); nothing while the button is disabled. silent = fn plays its own sound.
function Panel.on_click(b, fn, silent)
	b:SetScript("OnClick", function()
		if b.dc_disabled then return end
		if not silent then ns.Assets.play("click") end
		fn()
	end)
end

---------------------------------------------------------------- check box

-- A labelled check box. Returns the clickable button: set_checked(v), set_dim(v), dc_checked, dc_label (font string).
function Panel.check(parent, label)
	local A = ns.Assets
	local b = native_frame("CheckButton", parent, A.TEMPLATE_CHECK, { "SetChecked", "GetChecked" })
	local size = CHECK_NATIVE
	if b ~= nil then
		b.dc_native = true
	else
		size = CHECK_FLAT
		b = CreateFrame("Button", nil, parent)
		local box = b:CreateTexture(nil, "BACKGROUND")
		box:SetAllPoints(b)
		set_color(box, A.COLOR.CLASS_IDLE)
		local inner = b:CreateTexture(nil, "BORDER")
		inner:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
		inner:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
		set_color(inner, A.COLOR.BUTTON_BG)
		local tick = b:CreateTexture(nil, "ARTWORK")
		tick:SetPoint("TOPLEFT", b, "TOPLEFT", 4, -4)
		tick:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -4, 4)
		set_color(tick, A.COLOR.CLASS_SELECTED)
		tick:Hide()
		b.dc_tick = tick
		local hl = b:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints(b)
		set_color(hl, A.COLOR.BUTTON_HL)
	end
	b:SetSize(size, size)
	b:RegisterForClicks("LeftButtonUp")
	b.dc_label = font_string(b, A.FONT_HUD_SMALL)
	b.dc_label:SetPoint("LEFT", b, "RIGHT", CHECK_LABEL_GAP, 0)
	b.dc_label:SetText(label or "")
	if has(b, "SetHitRectInsets") then pcall(b.SetHitRectInsets, b, 0, -LABEL_HIT_W, 0, 0) end
	b.dc_checked = false
	b.set_checked = function(v)
		b.dc_checked = v and true or false
		if b.dc_native then
			pcall(function() b:SetChecked(b.dc_checked) end)
		else
			if b.dc_checked then b.dc_tick:Show() else b.dc_tick:Hide() end
		end
	end
	-- disabled look only (the check stays clickable): dim label and box
	b.set_dim = function(v)
		b.dc_dim = v and true or false
		b:SetAlpha(v and DIM_ALPHA or 1)
	end
	return b
end

---------------------------------------------------------------- segment row

local function segment_look(b)
	local A = ns.Assets
	local sel = b.dc_selected
	set_color(b.dc_bg, sel and A.COLOR.SEG_SEL or A.COLOR.BUTTON_BG)
	text_color(b.dc_fs, b.dc_disabled and A.COLOR.SEG_TEXT_OFF or (sel and A.COLOR.TITLE_GOLD or A.COLOR.SEG_TEXT))
end

-- A row of small buttons, one selected; width w. seg.buttons[i], seg.select(i), seg.set_enabled(i, on),
-- seg.on_pick = function(i). A disabled segment ignores clicks; its tooltip (button.dc_tip = { title, lines }) stays.
function Panel.segment(parent, labels, w)
	local A = ns.Assets
	local n = #labels
	local seg = CreateFrame("Frame", nil, parent)
	seg:SetSize(w, SEG_H)
	seg.buttons = {}
	local bw = (w - (n - 1) * SEG_GAP) / n
	for i = 1, n do
		local b = CreateFrame("Button", nil, seg)
		b:SetSize(bw, SEG_H)
		b:SetPoint("TOPLEFT", seg, "TOPLEFT", (i - 1) * (bw + SEG_GAP), 0)
		b:RegisterForClicks("LeftButtonUp")
		b.dc_bg = b:CreateTexture(nil, "BACKGROUND")
		b.dc_bg:SetAllPoints(b)
		local hl = b:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints(b)
		set_color(hl, A.COLOR.BUTTON_HL)
		b.dc_fs = font_string(b, A.FONT_LABEL_SMALL)
		b.dc_fs:SetPoint("CENTER", b, "CENTER", 0, 0)
		b.dc_fs:SetText(labels[i])
		b.dc_text, b.dc_index, b.dc_selected, b.dc_disabled = labels[i], i, false, false
		b:SetScript("OnClick", function()
			if b.dc_disabled then return end
			A.play("click")
			if seg.on_pick then seg.on_pick(i) end
		end)
		b:SetScript("OnEnter", function()
			if b.dc_tip ~= nil then Panel.show_tip(b, b.dc_tip[1], b.dc_tip[2] or {}) end
		end)
		b:SetScript("OnLeave", Panel.hide_tip)
		segment_look(b)
		seg.buttons[i] = b
	end
	seg.select = function(i)
		for k = 1, n do
			seg.buttons[k].dc_selected = k == i
			segment_look(seg.buttons[k])
		end
		seg.selected = i
	end
	seg.set_enabled = function(i, on)
		seg.buttons[i].dc_disabled = not on
		segment_look(seg.buttons[i])
	end
	return seg
end

---------------------------------------------------------------- section label, icon

-- A gold small label with a thin divider under it, width w. Returns the frame (.label).
function Panel.section(parent, text, w)
	local A = ns.Assets
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(w, SECTION_H)
	f.label = font_string(f, A.FONT_LABEL_SMALL)
	f.label:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	f.label:SetText(text)
	local line = f:CreateTexture(nil, "ARTWORK")
	line:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
	line:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
	line:SetHeight(1)
	set_color(line, A.COLOR.SECTION_LINE)
	return f
end

-- Square icon button: border (frame.border, set_border(r, g, b, a)) and the icon texture (frame.icon) with the standard crop.
-- inset: border width in px (default 1); crop: false keeps the full texture (class sheet icons set their own coords).
function Panel.icon(parent, size, inset, crop)
	local A = ns.Assets
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size, size)
	local px = inset or ICON_BORDER_PX
	b.border = b:CreateTexture(nil, "BACKGROUND")
	b.border:SetAllPoints(b)
	set_color(b.border, A.COLOR.ICON_BORDER)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", px, -px)
	b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -px, px)
	if crop ~= false then
		local c = A.ICON_CROP
		b.icon:SetTexCoord(c[1], c[2], c[3], c[4])
	end
	b.set_border = function(r, g, bl, a) b.border:SetColorTexture(r, g, bl, a or 1) end
	return b
end

ns.Panel = Panel
