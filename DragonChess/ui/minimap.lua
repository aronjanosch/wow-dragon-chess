local addonName, ns = ...
-- Minimap button (W0-P4): our own round button (LibStub / LibDBIcon don't exist in the client).
-- Ruby gem icon, round-masked; drag it around the minimap edge (angle in degrees saved in
-- DragonChessDB.minimap.angle); left click = toggle the window, right click = menu; tooltip.
-- Also registers with AddonCompartmentFrame when the client has it. Everything that touches a
-- global the client may lack goes through type checks / pcall.
--
-- Pure maths (tested headless): MinimapButton.position(angle, radius) -> x, y offset from the
-- minimap centre; MinimapButton.angle_from(cx, cy, mx, my) -> angle in [0, 360).

local pcall, type, select = pcall, type, select
local cos, sin, rad, deg, atan2 = math.cos, math.sin, math.rad, math.deg, math.atan2

local MinimapButton = {}

local ICON = "Interface\\Icons\\INV_Misc_Gem_Ruby_02"
-- Classic minimap button art (vanilla file names, not probed: missing = an empty ring only).
local BORDER = "Interface\\Minimap\\MiniMap-TrackingBorder"
local BACKGROUND = "Interface\\Minimap\\UI-Minimap-Background"
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local MASK_WRAP = "CLAMPTOBLACKADDITIVE"
local SIZE = 31
local DEFAULT_ANGLE = 225 -- bottom-left of the minimap
local EDGE_PAD = 5 -- px outside the minimap radius

MinimapButton.DEFAULT_ANGLE = DEFAULT_ANGLE

function MinimapButton.position(angle, radius)
	local a = rad(angle)
	return cos(a) * radius, sin(a) * radius
end

function MinimapButton.angle_from(cx, cy, mx, my)
	local a = deg(atan2(cy - my, cx - mx))
	if a < 0 then a = a + 360 end
	return a
end

local function valid_angle(a)
	return type(a) == "number" and a == a and a >= 0 and a < 360
end

local function is_right_click(...)
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		if v == "RightButton" then return true end
		if type(v) == "table" and v.buttonName == "RightButton" then return true end
	end
	return false
end

-- db: DragonChessDB.minimap table (angle); hooks: on_left(), on_right().
-- Returns the button, or nil when there is no minimap.
function MinimapButton.create(db, hooks)
	local mm = Minimap
	if type(mm) ~= "table" or type(CreateFrame) ~= "function" then return nil end
	if not valid_angle(db.angle) then db.angle = DEFAULT_ANGLE end

	local b = CreateFrame("Button", nil, mm)
	b:SetSize(SIZE, SIZE)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")

	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture(BACKGROUND)
	bg:SetSize(20, 20)
	bg:SetPoint("TOPLEFT", b, "TOPLEFT", 7, -5)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ICON)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon:SetSize(19, 19)
	icon:SetPoint("TOPLEFT", b, "TOPLEFT", 6, -5)
	local mask = b:CreateMaskTexture()
	mask:SetTexture(MASK, MASK_WRAP, MASK_WRAP)
	mask:SetAllPoints(icon)
	icon:AddMaskTexture(mask)
	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetTexture(BORDER)
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetTexture(ICON)
	hl:SetAllPoints(icon)
	hl:SetBlendMode("ADD")
	hl:SetAlpha(0.35)
	b.icon, b.border = icon, border

	local function place()
		local r = (mm:GetWidth() or 140) / 2 + EDGE_PAD
		local x, y = MinimapButton.position(db.angle, r)
		b:ClearAllPoints()
		b:SetPoint("CENTER", mm, "CENTER", x, y)
	end
	b.place = place

	local function on_drag_update()
		local mx, my = mm:GetCenter()
		if mx == nil or my == nil then return end
		local s = mm:GetEffectiveScale()
		local cx, cy = GetCursorPosition()
		db.angle = MinimapButton.angle_from(cx / s, cy / s, mx, my)
		place()
	end
	b:SetScript("OnDragStart", function(self)
		self.dragging = true
		self:SetScript("OnUpdate", on_drag_update)
		if type(GameTooltip) == "table" then pcall(GameTooltip.Hide, GameTooltip) end
	end)
	b:SetScript("OnDragStop", function(self)
		self.dragging = false
		self:SetScript("OnUpdate", nil)
	end)
	b:SetScript("OnClick", function(_, button)
		if button == "RightButton" then hooks.on_right() else hooks.on_left() end
	end)
	b:SetScript("OnEnter", function(self)
		if self.dragging or type(GameTooltip) ~= "table" then return end
		pcall(function()
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:SetText("Dragon Chess")
			GameTooltip:AddLine("Left click: play", 1, 1, 1)
			GameTooltip:AddLine("Right click: menu", 1, 1, 1)
			GameTooltip:AddLine("Drag: move this button", 0.7, 0.7, 0.7)
			GameTooltip:Show()
		end)
	end)
	b:SetScript("OnLeave", function()
		if type(GameTooltip) == "table" then pcall(GameTooltip.Hide, GameTooltip) end
	end)

	place()
	return b
end

-- Addon compartment entry (the client's addon dropdown). Returns true when registered.
function MinimapButton.register_compartment(hooks)
	local ok, done = pcall(function()
		local c = AddonCompartmentFrame
		if type(c) ~= "table" or type(c.RegisterAddon) ~= "function" then return false end
		c:RegisterAddon({
			text = "Dragon Chess",
			icon = ICON,
			notCheckable = true,
			registerForAnyClick = true,
			func = function(...)
				if is_right_click(...) then hooks.on_right() else hooks.on_left() end
			end,
		})
		return true
	end)
	return ok and done == true
end

ns.MinimapButton = MinimapButton
