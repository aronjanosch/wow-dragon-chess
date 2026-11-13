-- Dev probe: /dcprobe runs all checks, prints a summary, results land in
-- WTF/.../SavedVariables/DragonChessProbe.lua after /reload or logout.
-- /dcprobe gems   → scans item IDs for gems (classID 3) and stores their icon file IDs
-- /dcprobe mouse  → opens a drag test box (press, drag outside, release; watch the chat)
-- /dcprobe icons  → visual check of candidate icons (gems, spell icons)
-- /dcprobe grid   → shows the stored gem icons (page with /dcprobe grid <n>)
local ADDON, NS = ...
-- SavedVariables replace the global AFTER the files run, so DB must be (re)bound on ADDON_LOADED.
DragonChessProbeDB = DragonChessProbeDB or {}
local DB = DragonChessProbeDB
local evf = CreateFrame("Frame")
evf:RegisterEvent("ADDON_LOADED")
evf:SetScript("OnEvent", function(_, _, name)
	if name == ADDON then
		DragonChessProbeDB = DragonChessProbeDB or {}
		DB = DragonChessProbeDB
	end
end)
local function say(msg) print("|cff66ccffDCProbe|r " .. tostring(msg)) end

ICON_CANDIDATES = {
	"INV_Misc_Gem_Ruby_01", "INV_Misc_Gem_Ruby_02", "INV_Misc_Gem_Sapphire_01", "INV_Misc_Gem_Sapphire_02",
	"INV_Misc_Gem_Emerald_01", "INV_Misc_Gem_Emerald_02", "INV_Misc_Gem_Amethyst_01", "INV_Misc_Gem_Amethyst_02",
	"INV_Misc_Gem_Topaz_01", "INV_Misc_Gem_Topaz_02", "INV_Misc_Gem_Opal_01", "INV_Misc_Gem_Opal_02",
	"INV_Misc_Gem_Pearl_01", "INV_Misc_Gem_Diamond_01", "INV_Misc_Gem_Bloodstone_01", "INV_Misc_Gem_Crystal_01",
	"INV_Misc_Gem_Variety_01", "INV_Misc_Gem_Azuredraenite_01", "INV_Misc_Gem_01", "INV_Misc_Gem_02",
	"INV_Misc_Gem_03", "INV_Misc_Gem_04", "INV_Stone_15", "INV_Stone_16",
	"Spell_Fire_FlameBolt", "Spell_Frost_FrostBolt02", "Spell_Nature_Lightning", "Spell_Shadow_ShadowBolt",
	"Spell_Holy_HolyBolt", "Spell_Nature_HealingTouch", "INV_Misc_QuestionMark",
}
local function runChecks()
	local R = {}
	DB.checks = R
	local version, build, date, interface = GetBuildInfo()
	R.build = { version = version, build = build, date = date, interface = interface }
	R.projectID = WOW_PROJECT_ID
	R.locale = GetLocale()

	-- API presence
	local names = {
		"CreateFrame", "GetCursorPosition", "IsMouseButtonDown", "debugprofilestop", "geterrorhandler",
		"PlaySound", "PlaySoundFile", "GetTime", "JoinChannelByName", "GetChannelName", "SetCVar",
	}
	R.globals = {}
	for _, n in ipairs(names) do R.globals[n] = type(_G[n]) end
	R.tables = {
		SOUNDKIT = type(SOUNDKIT), bit = type(bit), C_ChatInfo = type(C_ChatInfo), C_Timer = type(C_Timer),
		C_Texture = type(C_Texture), C_Item = type(C_Item), C_AddOns = type(C_AddOns), C_Container = type(C_Container),
		BackdropTemplateMixin = type(BackdropTemplateMixin), CreateFromMixins = type(CreateFromMixins),
		AddonCompartmentFrame = type(AddonCompartmentFrame), Settings = type(Settings),
		LibStub = type(LibStub), ChatThrottleLib = type(ChatThrottleLib),
	}
	R.chatinfo = {}
	if C_ChatInfo then
		for _, n in ipairs({ "SendAddonMessage", "RegisterAddonMessagePrefix", "SendAddonMessageLogged", "GetNumActiveChannels" }) do
			R.chatinfo[n] = type(C_ChatInfo[n])
		end
	end
	R.frameTypes = {}
	for _, t in ipairs({ "Frame", "Button", "ModelScene", "PlayerModel", "DressUpModel", "Model", "Cooldown", "StatusBar", "Slider" }) do
		local ok = pcall(CreateFrame, t, nil, UIParent)
		R.frameTypes[t] = ok
	end

	-- Lua semantics: does yield inside pcall work here? (PUC 5.1: no.)
	local co = coroutine.create(function()
		local ok = pcall(function() coroutine.yield("y") end)
		return ok
	end)
	local ok1, v1 = coroutine.resume(co)
	R.yieldInPcall = { firstResume = tostring(v1), status = coroutine.status(co) }
	R.luaVersion = _VERSION
	R.jit = type(jit) == "table" and (jit.version or "jit") or false

	-- Events that must exist
	local f = CreateFrame("Frame")
	R.events = {}
	for _, e in ipairs({
		"PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
		"LFG_PROPOSAL_SHOW", "LFG_PROPOSAL_FAILED", "READY_CHECK", "UPDATE_BATTLEFIELD_STATUS",
		"PVP_ROLE_POPUP_SHOW", "CHAT_MSG_ADDON", "CHAT_MSG_CHANNEL", "CHANNEL_UI_UPDATE", "ADDON_LOADED",
		"GUILD_ROSTER_UPDATE", "LOADING_SCREEN_ENABLED",
	}) do
		R.events[e] = pcall(f.RegisterEvent, f, e)
	end

	-- Textures: GetFileIDFromPath does not exist in Forever; record what a texture reports after
	-- SetTexture (unreliable) and use `/dcprobe icons` for the visual check (missing = green square).
	R.textures = {}
	local probeTex = UIParent:CreateTexture(nil, "BACKGROUND")
	for _, p in ipairs(ICON_CANDIDATES) do
		probeTex:SetTexture(nil)
		local ok = probeTex:SetTexture("Interface\\Icons\\" .. p)
		R.textures[p] = { setOk = ok and true or false, got = tostring(probeTex:GetTexture()), id = tostring(probeTex.GetTextureFileID and probeTex:GetTextureFileID() or "n/a") }
	end
	R.atlases = {}
	for _, a in ipairs({ "UI-HUD-ActionBar-IconFrame", "common-icon-checkmark", "auctionhouse-itemicon-border-purple", "poi-workorders" }) do
		R.atlases[a] = C_Texture and C_Texture.GetAtlasExists and C_Texture.GetAtlasExists(a) or false
	end
	R.sounds = {}
	if SOUNDKIT then
		for _, k in ipairs({ "IG_MAINMENU_OPEN", "IG_MAINMENU_CLOSE", "IG_CHARACTER_INFO_TAB", "UI_BNET_TOAST", "GS_TITLE_OPTION_OK", "IG_ABILITY_ICON_DROP" }) do
			R.sounds[k] = SOUNDKIT[k] or false
		end
	end

	-- Addon namespace passing: `local name, ns = ...` is covered by the toc file loading this chunk
	R.vararg = { name = tostring(ADDON), nsType = type(NS) }

	-- Performance: 64 textured frames, one SetPoint each, 200 iterations
	local parent = CreateFrame("Frame", nil, UIParent)
	parent:SetSize(600, 600)
	local gems = {}
	for i = 1, 64 do
		local g = CreateFrame("Frame", nil, parent)
		g:SetSize(56, 56)
		local t = g:CreateTexture(nil, "ARTWORK"); t:SetAllPoints(); t:SetColorTexture(i / 64, 0.5, 0.5)
		gems[i] = g
	end
	local t0 = debugprofilestop()
	for iter = 1, 200 do
		for i = 1, 64 do
			gems[i]:ClearAllPoints()
			gems[i]:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", ((i - 1) % 8) * 56 + iter % 3, math.floor((i - 1) / 8) * 56)
		end
	end
	R.perfSetPoint64x200_ms = debugprofilestop() - t0
	parent:Hide()

	R.memKB = collectgarbage("count")
	say("checks stored. Build " .. tostring(version) .. " / " .. tostring(build) .. " / interface " .. tostring(interface) .. ". /reload to flush to disk.")
end

local function scanGems()
	DB.gems = {}
	local seen = {}
	local id, MAX, step = 1, 260000, 4000
	local fr = CreateFrame("Frame")
	say("scanning item IDs for gems…")
	fr:SetScript("OnUpdate", function(self)
		local last = math.min(id + step - 1, MAX)
		for i = id, last do
			local _, itype, subtype, _, icon, classID, subClassID = C_Item.GetItemInfoInstant(i)
			if classID == 3 and icon and not seen[icon] then
				seen[icon] = true
				DB.gems[#DB.gems + 1] = { item = i, icon = icon, sub = subClassID, subtype = subtype }
			end
		end
		id = last + 1
		if id > MAX then
			self:SetScript("OnUpdate", nil)
			say("gem scan done: " .. #DB.gems .. " unique icons. /reload to save.")
		end
	end)
end

local function showGrid(page)
	if not DB.gems or #DB.gems == 0 then return say("run /dcprobe gems first") end
	page = tonumber(page) or 1
	local per = 80
	if not DCProbeGrid then
		local g = CreateFrame("Frame", "DCProbeGrid", UIParent, "BackdropTemplate")
		g:SetSize(10 * 56 + 20, 8 * 66 + 40); g:SetPoint("CENTER")
		g:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
		g:SetBackdropColor(0, 0, 0, 0.9); g:EnableMouse(true); g:SetMovable(true)
		g:RegisterForDrag("LeftButton"); g:SetScript("OnDragStart", g.StartMoving); g:SetScript("OnDragStop", g.StopMovingOrSizing)
		g.cells = {}
		for i = 1, per do
			local c = CreateFrame("Frame", nil, g)
			c:SetSize(52, 62)
			c:SetPoint("TOPLEFT", 10 + ((i - 1) % 10) * 56, -30 - math.floor((i - 1) / 10) * 66)
			c.t = c:CreateTexture(nil, "ARTWORK"); c.t:SetSize(40, 40); c.t:SetPoint("TOP")
			c.s = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); c.s:SetPoint("TOP", c.t, "BOTTOM", 0, -2)
			g.cells[i] = c
		end
		g.title = g:CreateFontString(nil, "OVERLAY", "GameFontNormal"); g.title:SetPoint("TOPLEFT", 10, -8)
		local x = CreateFrame("Button", nil, g, "UIPanelCloseButton"); x:SetPoint("TOPRIGHT")
	end
	local g = DCProbeGrid
	local pages = math.ceil(#DB.gems / per)
	g.title:SetText("Gem icons page " .. page .. "/" .. pages .. "  (/dcprobe grid N)")
	for i = 1, per do
		local e = DB.gems[(page - 1) * per + i]
		local c = g.cells[i]
		if e then c.t:SetTexture(e.icon); c.s:SetText(e.icon); c:Show() else c:Hide() end
	end
	g:Show()
end

local function mouseTest()
	local f = CreateFrame("Frame", "DCProbeMouse", UIParent, "BackdropTemplate")
	f:SetSize(300, 200); f:SetPoint("CENTER"); f:EnableMouse(true)
	f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" }); f:SetBackdropColor(0.1, 0.2, 0.4, 0.9)
	local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); fs:SetPoint("CENTER"); fs:SetText("press here, drag out, release")
	DB.mouse = {}
	f:SetScript("OnMouseDown", function() DB.mouse[#DB.mouse + 1] = "down"; say("OnMouseDown") end)
	f:SetScript("OnMouseUp", function() local inside = f:IsMouseOver(); DB.mouse[#DB.mouse + 1] = inside and "up-inside" or "up-OUTSIDE"; say("OnMouseUp " .. (inside and "(cursor inside)" or "(cursor OUTSIDE)")) end)
	f:SetScript("OnUpdate", function()
		if IsMouseButtonDown("LeftButton") and not f.pressed then f.pressed = true
		elseif not IsMouseButtonDown("LeftButton") and f.pressed then
			f.pressed = false; DB.mouse[#DB.mouse + 1] = "poll-release"; say("poll saw release")
		end
	end)
	local x = CreateFrame("Button", nil, f, "UIPanelCloseButton"); x:SetPoint("TOPRIGHT")
	local x1, y1 = GetCursorPosition()
	say("scale " .. f:GetEffectiveScale() .. "  UIParent " .. UIParent:GetEffectiveScale() .. "  cursor " .. x1 .. "," .. y1)
end

local function showIcons()
	if not DCProbeIcons then
		local g = CreateFrame("Frame", "DCProbeIcons", UIParent, "BackdropTemplate")
		g:SetSize(8 * 90 + 20, 4 * 90 + 40); g:SetPoint("CENTER")
		g:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" }); g:SetBackdropColor(0, 0, 0, 0.9)
		g:EnableMouse(true); g:SetMovable(true); g:RegisterForDrag("LeftButton")
		g:SetScript("OnDragStart", g.StartMoving); g:SetScript("OnDragStop", g.StopMovingOrSizing)
		for i, p in ipairs(ICON_CANDIDATES) do
			local c = CreateFrame("Frame", nil, g); c:SetSize(86, 86)
			c:SetPoint("TOPLEFT", 10 + ((i - 1) % 8) * 90, -30 - math.floor((i - 1) / 8) * 90)
			local t = c:CreateTexture(nil, "ARTWORK"); t:SetSize(48, 48); t:SetPoint("TOP")
			t:SetTexture("Interface\\Icons\\" .. p)
			local s2 = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); s2:SetPoint("TOP", t, "BOTTOM", 0, -2)
			s2:SetWidth(86); s2:SetText((p:gsub("INV_Misc_", ""):gsub("Spell_", "S_")))
		end
		local x = CreateFrame("Button", nil, g, "UIPanelCloseButton"); x:SetPoint("TOPRIGHT")
		local h = g:CreateFontString(nil, "OVERLAY", "GameFontNormal"); h:SetPoint("TOPLEFT", 10, -8)
		h:SetText("Icon candidates (green/missing square = file does not exist)")
	end
	DCProbeIcons:Show()
end

local SET02 = { "Ruby_02", "Sapphire_02", "Emerald_02", "Amethyst_02", "Topaz_02", "Opal_02" }
local function showSet()
	if DCProbeSet then DCProbeSet:Show() return end
	local g = CreateFrame("Frame", "DCProbeSet", UIParent, "BackdropTemplate")
	g:SetSize(8 * 64 + 20, 3 * 80 + 8 * 64 + 70); g:SetPoint("CENTER")
	g:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" }); g:SetBackdropColor(0.08, 0.08, 0.1, 0.95)
	g:EnableMouse(true); g:SetMovable(true); g:RegisterForDrag("LeftButton")
	g:SetScript("OnDragStart", g.StartMoving); g:SetScript("OnDragStop", g.StopMovingOrSizing)
	local x = CreateFrame("Button", nil, g, "UIPanelCloseButton"); x:SetPoint("TOPRIGHT")
	local h = g:CreateFontString(nil, "OVERLAY", "GameFontNormal"); h:SetPoint("TOPLEFT", 10, -8)
	h:SetText("Rows: raw / cropped / cropped+round mask. Below: mock 8x8 board (cropped+mask)")
	local function icon(parent, name, size, mode, px, py)
		local t = parent:CreateTexture(nil, "ARTWORK"); t:SetSize(size, size)
		t:SetPoint("TOPLEFT", px, py)
		t:SetTexture("Interface\\Icons\\INV_Misc_Gem_" .. name)
		if mode >= 2 then t:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
		if mode >= 3 then
			local m = parent:CreateMaskTexture(); m:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
			m:SetAllPoints(t); t:AddMaskTexture(m)
		end
		return t
	end
	for mode = 1, 3 do
		for i, n in ipairs(SET02) do icon(g, n, 64, mode, 20 + (i - 1) * 76, -30 - (mode - 1) * 78) end
	end
	local rng = 12345
	for r = 0, 7 do
		for c = 0, 7 do
			rng = (rng * 1103515245 + 12345) % 2147483648
			icon(g, SET02[(math.floor(rng / 65536) % 6) + 1], 56, 3, 10 + c * 62, -30 - 3 * 78 - r * 62)
		end
	end
	g:Show()
end

-- /dcprobe model: can we show creatures? PlayerModel:SetCreature / SetDisplayInfo, ModelScene.
local function showModels()
	if DCProbeModels then DCProbeModels:Show() return end
	local g = CreateFrame("Frame", "DCProbeModels", UIParent, "BackdropTemplate")
	g:SetSize(6 * 150 + 20, 330); g:SetPoint("CENTER")
	g:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" }); g:SetBackdropColor(0.1, 0.1, 0.12, 0.95)
	g:EnableMouse(true); g:SetMovable(true); g:RegisterForDrag("LeftButton")
	g:SetScript("OnDragStart", g.StartMoving); g:SetScript("OnDragStop", g.StopMovingOrSizing)
	local x = CreateFrame("Button", nil, g, "UIPanelCloseButton"); x:SetPoint("TOPRIGHT")
	DB.models = {}
	local tests = {
		{ "creature 448 (Hogger)", function(m) m:SetCreature(448) end },
		{ "creature 3 (Flesh Eater)", function(m) m:SetCreature(3) end },
		{ "creature 46 (Murloc?)", function(m) m:SetCreature(46) end },
		{ "creature 11502 (Ragnaros)", function(m) m:SetCreature(11502) end },
		{ "display 1000", function(m) m:SetDisplayInfo(1000) end },
		{ "display 17000", function(m) m:SetDisplayInfo(17000) end },
		{ "display 30000", function(m) m:SetDisplayInfo(30000) end },
		{ "display 50000", function(m) m:SetDisplayInfo(50000) end },
		{ "unit player", function(m) m:SetUnit("player") end },
		{ "model path wolf", function(m) m:SetModel("Creature\\Wolf\\Wolf.m2") end },
		{ "fileID 123 (m2?)", function(m) m:SetModel(123) end },
		{ "ModelScene", nil },
	}
	for i, t in ipairs(tests) do
		local col, row = (i - 1) % 6, math.floor((i - 1) / 6)
		local holder = CreateFrame("Frame", nil, g)
		holder:SetSize(146, 140); holder:SetPoint("TOPLEFT", 10 + col * 150, -30 - row * 150)
		local fs = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); fs:SetPoint("BOTTOM"); fs:SetText(t[1])
		if t[2] then
			local ok, err = pcall(function()
				local m = CreateFrame("PlayerModel", nil, holder)
				m:SetAllPoints(); t[2](m)
			end)
			DB.models[t[1]] = ok and "ok" or tostring(err)
		else
			local ok, err = pcall(function()
				local ms = CreateFrame("ModelScene", nil, holder, "ModelSceneMixinTemplate")
				ms:SetAllPoints()
			end)
			DB.models[t[1]] = ok and "ok" or tostring(err)
		end
	end
	DB.models.methods = {}
	local m = CreateFrame("PlayerModel", nil, UIParent); m:Hide()
	for _, n in ipairs({ "SetCreature", "SetDisplayInfo", "SetUnit", "SetModel", "SetPortraitZoom", "SetCamDistanceScale", "SetRotation", "SetAnimation", "SetModelScale", "SetPosition", "RefreshUnit", "SetLight", "SetCamera" }) do
		DB.models.methods[n] = type(m[n])
	end
	g:Show()
end

-- /dcprobe ui: UI texture candidates + atlas dump (names matching patterns) into the DB.
local UI_TEX = {
	"Interface\\TargetingFrame\\UI-StatusBar", "Interface\\Tooltips\\UI-Tooltip-Background",
	"Interface\\Tooltips\\UI-Tooltip-Border", "Interface\\DialogFrame\\UI-DialogBox-Background",
	"Interface\\DialogFrame\\UI-DialogBox-Border", "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
	"Interface\\FrameGeneral\\UI-Background-Marble", "Interface\\FrameGeneral\\UI-Background-Rock",
	"Interface\\Buttons\\UI-Quickslot2", "Interface\\Buttons\\UI-ActionButton-Border",
	"Interface\\PVPFrame\\PvPBackground", "Interface\\Spellbook\\Spellbook-Page-1",
	"Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal",
	"Interface\\Icons\\Spell_Holy_PowerWordShield", "Interface\\Icons\\Spell_Fire_FireArmor",
	"Interface\\Icons\\Spell_Shadow_LifeDrain02", "Interface\\Icons\\Spell_Shadow_CurseOfTounge",
	"Interface\\Icons\\Spell_Frost_Stun", "Interface\\Icons\\Ability_Warrior_Sunder",
	"Interface\\Icons\\Ability_Warrior_Rampage", "Interface\\Icons\\Ability_Druid_Maul",
	"Interface\\Icons\\Ability_Hunter_Pet_Wolf", "Interface\\Icons\\Spell_Nature_Slow",
}
local function showUI()
	local patterns = { "background", "bg", "frame", "bar", "border", "panel", "parchment", "ornate", "loading", "banner", "plaque", "nameplate" }
	DB.atlases = { total = 0, byPattern = {} }
	local okE, elems = pcall(C_Texture.GetAtlasElements)
	if okE and type(elems) == "table" then
		DB.atlases.total = #elems
		for _, p in ipairs(patterns) do DB.atlases.byPattern[p] = {} end
		for _, name in ipairs(elems) do
			local low = tostring(name):lower()
			for _, p in ipairs(patterns) do
				local list = DB.atlases.byPattern[p]
				if #list < 150 and low:find(p, 1, true) then list[#list + 1] = name end
			end
		end
	else
		DB.atlases.err = tostring(elems)
	end
	if not DCProbeUI then
		local g = CreateFrame("Frame", "DCProbeUI", UIParent, "BackdropTemplate")
		g:SetSize(8 * 100 + 20, 3 * 110 + 40); g:SetPoint("CENTER")
		g:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" }); g:SetBackdropColor(0.2, 0.2, 0.25, 0.95)
		g:EnableMouse(true); g:SetMovable(true); g:RegisterForDrag("LeftButton")
		g:SetScript("OnDragStart", g.StartMoving); g:SetScript("OnDragStop", g.StopMovingOrSizing)
		local x = CreateFrame("Button", nil, g, "UIPanelCloseButton"); x:SetPoint("TOPRIGHT")
		for i, p in ipairs(UI_TEX) do
			local c = CreateFrame("Frame", nil, g); c:SetSize(96, 104)
			c:SetPoint("TOPLEFT", 10 + ((i - 1) % 8) * 100, -30 - math.floor((i - 1) / 8) * 110)
			local t = c:CreateTexture(nil, "ARTWORK"); t:SetSize(80, 80); t:SetPoint("TOP"); t:SetTexture(p)
			local fs = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); fs:SetPoint("TOP", t, "BOTTOM", 0, -2); fs:SetWidth(96)
			fs:SetText(p:match("([^\\]+)$"))
		end
	end
	DCProbeUI:Show()
	say("atlas dump: " .. tostring(DB.atlases.total) .. " names (err: " .. tostring(DB.atlases.err) .. "). /reload to save.")
end

-- /dcprobe atlas: render candidate atlases (backgrounds, bars, frames, banners) to judge them.
local ATLAS_BG = { "groupfinder-background", "groupfinder-background-dungeons", "groupfinder-background-raids-warlords",
	"groupfinder-background-raids-legion", "groupfinder-background-battlegrounds", "groupfinder-background-questing",
	"groupfinder-background-scenarios", "groupfinder-background-arenas", "groupfinder-background-ashran",
	"groupfinder-background-custom-pve", "collections-background-tile", "Garr_WoodFrame-BackgroundTile" }
local ATLAS_UI = { "UI-Frame-Neutral-CardParchment", "UI-Frame-Neutral-CardParchmentWider", "parchmentpopup-background",
	"PetJournal-HealthBar-Background", "PetJournal-HealthBar-Mid", "MainPet-HealthBarFrame", "MainPet-HealthBarFill",
	"MainPet-HealthBarBG", "GarrMission_EncounterBar-BG", "GarrMission_EncounterBar-Fill", "GarrMission_EncounterBar-PortraitRing",
	"nameplates-bar-fill", "nameplates-bar-background-white", "BossBanner-BgBanner-Mid", "BossBanner-BgBanner-Top",
	"BossBanner-SkullCircle", "BossBanner-PortraitBorder", "BossBanner-TopFillagree", "house-upgrade-reward-level-plaque-active",
	"Portrait-Frame-Nameplate", "GarrMission_PortraitRing_LevelBorder", "ZoneAbility-Generic-IconBorder",
	"PetJournal-BattleSlot-IconBorder", "BattleBar-Button-Highlight" }
local function showAtlas()
	if DCProbeAtlas then DCProbeAtlas:Show() return end
	local g = CreateFrame("Frame", "DCProbeAtlas", UIParent, "BackdropTemplate")
	g:SetSize(6 * 170 + 20, 2 * 125 + 4 * 105 + 70); g:SetPoint("CENTER")
	g:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" }); g:SetBackdropColor(0.25, 0.25, 0.3, 0.97)
	g:EnableMouse(true); g:SetMovable(true); g:RegisterForDrag("LeftButton")
	g:SetScript("OnDragStart", g.StartMoving); g:SetScript("OnDragStop", g.StopMovingOrSizing)
	local x = CreateFrame("Button", nil, g, "UIPanelCloseButton"); x:SetPoint("TOPRIGHT")
	DB.atlasRender = {}
	local function cell(list, i, w, h, top, per)
		local n = list[i]
		local c = CreateFrame("Frame", nil, g); c:SetSize(w, h + 14)
		c:SetPoint("TOPLEFT", 10 + ((i - 1) % per) * (w + 6), top - math.floor((i - 1) / per) * (h + 22))
		local t = c:CreateTexture(nil, "ARTWORK"); t:SetSize(w, h); t:SetPoint("TOP")
		local ok = pcall(t.SetAtlas, t, n)
		DB.atlasRender[n] = ok and "ok" or "ERR"
		local fs = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); fs:SetPoint("TOP", t, "BOTTOM", 0, -1); fs:SetWidth(w); fs:SetText(n)
	end
	for i = 1, #ATLAS_BG do cell(ATLAS_BG, i, 160, 100, -28, 6) end
	for i = 1, #ATLAS_UI do cell(ATLAS_UI, i, 160, 70, -28 - 2 * 122 - 10, 6) end
	g:Show()
end

-- /dcprobe sound: browse SoundKit IDs. Prev/Next/jump, Play, Fav (stores id + note in DB.favs).
local function showSound()
	if DCProbeSound then DCProbeSound:Show() return end
	local g = CreateFrame("Frame", "DCProbeSound", UIParent, "BackdropTemplate")
	g:SetSize(560, 180); g:SetPoint("CENTER", 0, -250)
	g:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" }); g:SetBackdropColor(0.1, 0.1, 0.14, 0.95)
	g:EnableMouse(true); g:SetMovable(true); g:RegisterForDrag("LeftButton")
	g:SetScript("OnDragStart", g.StartMoving); g:SetScript("OnDragStop", g.StopMovingOrSizing)
	local x = CreateFrame("Button", nil, g, "UIPanelCloseButton"); x:SetPoint("TOPRIGHT")
	local cur, handle = 1, nil
	local title = g:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); title:SetPoint("TOP", 0, -10)
	local eb = CreateFrame("EditBox", nil, g, "InputBoxTemplate"); eb:SetSize(100, 24); eb:SetPoint("TOPLEFT", 20, -40)
	eb:SetAutoFocus(false); eb:SetNumeric(true)
	local note = CreateFrame("EditBox", nil, g, "InputBoxTemplate"); note:SetSize(260, 24); note:SetPoint("TOPLEFT", 200, -40)
	note:SetAutoFocus(false)
	local function refresh() title:SetText("SoundKit ID " .. cur); eb:SetText(tostring(cur)) end
	local function play()
		if handle and StopSound then pcall(StopSound, handle) end
		local ok, willPlay, h = pcall(PlaySound, cur, "SFX")
		handle = ok and h or nil
		say("play " .. cur .. " -> " .. tostring(ok and willPlay))
	end
	local function btn(label, dx, dy, fn)
		local b = CreateFrame("Button", nil, g, "UIPanelButtonTemplate"); b:SetSize(62, 24); b:SetText(label)
		b:SetPoint("TOPLEFT", 20 + dx, -80 - dy); b:SetScript("OnClick", fn); return b
	end
	local function step(d) return function() cur = math.max(1, cur + d); refresh(); play() end end
	btn("-1000", 0, 0, step(-1000)); btn("-100", 66, 0, step(-100)); btn("-10", 132, 0, step(-10)); btn("-1", 198, 0, step(-1))
	btn("+1", 264, 0, step(1)); btn("+10", 330, 0, step(10)); btn("+100", 396, 0, step(100)); btn("+1000", 462, 0, step(1000))
	btn("Play", 0, 34, play)
	btn("Go", 66, 34, function() cur = tonumber(eb:GetText()) or cur; refresh(); play() end)
	btn("FAV", 132, 34, function()
		DB.favs = DB.favs or {}
		DB.favs[#DB.favs + 1] = { id = cur, note = note:GetText() }
		say("saved fav " .. cur .. " (" .. note:GetText() .. ")")
	end)
	eb:SetScript("OnEnterPressed", function() cur = tonumber(eb:GetText()) or cur; refresh(); play(); eb:ClearFocus() end)
	refresh(); g:Show()
end

-- /dcprobe anim: AnimationGroup demo, FlipBook with a found atlas, atlas names for effects (dump), ModelScene actor spell visual.
local function showAnim()
	DB.anim = DB.anim or {}
	local pats = { "flipbook", "fire", "spark", "lightning", "frost", "explosion", "swirl", "burst", "impact", "slash", "shield", "heal", "glow", "ring", "smoke", "star" }
	DB.animAtlas = {}
	local okE, elems = pcall(C_Texture.GetAtlasElements)
	if okE and type(elems) == "table" then
		for _, p in ipairs(pats) do DB.animAtlas[p] = {} end
		for _, name in ipairs(elems) do
			local low = tostring(name):lower()
			for _, p in ipairs(pats) do
				local l = DB.animAtlas[p]
				if #l < 120 and low:find(p, 1, true) then l[#l + 1] = name end
			end
		end
	end
	if DCProbeAnim then DCProbeAnim:Show() return end
	local g = CreateFrame("Frame", "DCProbeAnim", UIParent, "BackdropTemplate")
	g:SetSize(640, 330); g:SetPoint("CENTER")
	g:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" }); g:SetBackdropColor(0.12, 0.12, 0.16, 0.95)
	g:EnableMouse(true); g:SetMovable(true); g:RegisterForDrag("LeftButton")
	g:SetScript("OnDragStart", g.StartMoving); g:SetScript("OnDragStop", g.StopMovingOrSizing)
	local x = CreateFrame("Button", nil, g, "UIPanelCloseButton"); x:SetPoint("TOPRIGHT")
	-- 1) AnimationGroup: pop + shake + fade of a gem icon
	local ic = g:CreateTexture(nil, "ARTWORK"); ic:SetSize(64, 64); ic:SetPoint("TOPLEFT", 40, -50)
	ic:SetTexture("Interface\\Icons\\INV_Misc_Gem_Ruby_02")
	local ag = ic:CreateAnimationGroup()
	local ok1, err1 = pcall(function()
		local sc = ag:CreateAnimation("Scale"); sc:SetScaleFrom(1, 1); sc:SetScaleTo(1.5, 1.5); sc:SetDuration(0.15); sc:SetOrder(1)
		local sc2 = ag:CreateAnimation("Scale"); sc2:SetScaleFrom(1, 1); sc2:SetScaleTo(0.667, 0.667); sc2:SetDuration(0.15); sc2:SetOrder(2)
		local tr = ag:CreateAnimation("Translation"); tr:SetOffset(30, 0); tr:SetDuration(0.2); tr:SetOrder(3)
		local al = ag:CreateAnimation("Alpha"); al:SetFromAlpha(1); al:SetToAlpha(0.2); al:SetDuration(0.3); al:SetOrder(4)
	end)
	DB.anim.animationGroup = ok1 and "ok" or tostring(err1)
	local b1 = CreateFrame("Button", nil, g, "UIPanelButtonTemplate"); b1:SetSize(90, 24); b1:SetPoint("TOPLEFT", 30, -125); b1:SetText("AnimGroup")
	b1:SetScript("OnClick", function() ag:Stop(); ag:Play() end)
	-- 2) FlipBook: first atlas containing "flipbook"
	local flipName = DB.animAtlas.flipbook and DB.animAtlas.flipbook[1]
	local ft = g:CreateTexture(nil, "ARTWORK"); ft:SetSize(128, 128); ft:SetPoint("TOPLEFT", 200, -40)
	local fg = ft:CreateAnimationGroup(); fg:SetLooping("REPEAT")
	local ok2, err2 = pcall(function()
		ft:SetAtlas(flipName or "shop-loading-sparkle-flipbook")
		local fa = fg:CreateAnimation("FlipBook")
		fa:SetFlipBookRows(4); fa:SetFlipBookColumns(4); fa:SetFlipBookFrames(16); fa:SetDuration(1)
		fa:SetFlipBookFrameWidth(0); fa:SetFlipBookFrameHeight(0)
	end)
	DB.anim.flipbook = ok2 and ("ok " .. tostring(flipName)) or tostring(err2)
	local b2 = CreateFrame("Button", nil, g, "UIPanelButtonTemplate"); b2:SetSize(90, 24); b2:SetPoint("TOPLEFT", 200, -175); b2:SetText("FlipBook")
	b2:SetScript("OnClick", function() if fg:IsPlaying() then fg:Stop() else fg:Play() end end)
	-- 3) PlayerModel animation ids
	local pm = CreateFrame("PlayerModel", nil, g); pm:SetSize(150, 150); pm:SetPoint("TOPLEFT", 360, -40)
	pcall(pm.SetDisplayInfo, pm, 1000)
	local aid = 0
	local b3 = CreateFrame("Button", nil, g, "UIPanelButtonTemplate"); b3:SetSize(120, 24); b3:SetPoint("TOPLEFT", 360, -200); b3:SetText("Model anim +1")
	local lab = g:CreateFontString(nil, "OVERLAY", "GameFontNormal"); lab:SetPoint("TOPLEFT", 500, -204)
	b3:SetScript("OnClick", function() aid = aid + 1; local ok = pcall(pm.SetAnimation, pm, aid); lab:SetText("anim " .. aid .. (ok and "" or " ERR")) end)
	-- 4) ModelScene actor with a spell visual kit
	local ok4, err4 = pcall(function()
		local ms = CreateFrame("ModelScene", nil, g, "ModelSceneMixinTemplate")
		ms:SetSize(150, 120); ms:SetPoint("TOPLEFT", 40, -190)
		DB.anim.sceneMethods = {}
		for _, n in ipairs({ "CreateActor", "AcquireAndInitializeActor", "SetFromModelSceneID", "TransitionToModelSceneID", "GetActorByTag" }) do
			DB.anim.sceneMethods[n] = type(ms[n])
		end
		local actor = ms.CreateActor and ms:CreateActor() or nil
		DB.anim.actorMethods = {}
		if actor then
			for _, n in ipairs({ "SetModelByCreatureDisplayID", "SetModelByFileID", "SetSpellVisualKit", "PlayAnimationKit", "SetAnimation" }) do
				DB.anim.actorMethods[n] = type(actor[n])
			end
		end
	end)
	DB.anim.modelScene = ok4 and "ok" or tostring(err4)
	local hint = g:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); hint:SetPoint("BOTTOMLEFT", 20, 14); hint:SetWidth(600); hint:SetJustifyH("LEFT")
	hint:SetText("AnimGroup = pop/shake/fade (gem icon); FlipBook = atlas flipbook; Model anim +1 = step model animation ids. /reload to save results (flipbook + effect atlas names are dumped to DB).")
	g:Show()
	say("anim probe open; atlas lists dumped. /reload to save.")
end

-- /dcprobe snd <text> [offset]: auditions every SOUNDKIT constant whose name contains <text>, one per
-- second, naming each in chat (the named list instead of clicking through numbers).
local function sndAudition(rest)
	local text, off = (rest or ""):match("^(%S*)%s*(%d*)$")
	off = tonumber(off) or 0
	text = (text or ""):upper()
	local names = {}
	if type(SOUNDKIT) == "table" then
		for k, v in pairs(SOUNDKIT) do
			if type(v) == "number" and (text == "" or k:upper():find(text, 1, true)) then names[#names + 1] = k end
		end
	end
	table.sort(names)
	DB.soundkit = DB.soundkit or {}
	if #DB.soundkit == 0 and type(SOUNDKIT) == "table" then
		for k, v in pairs(SOUNDKIT) do if type(v) == "number" then DB.soundkit[#DB.soundkit + 1] = k .. "=" .. v end end
		table.sort(DB.soundkit)
	end
	say(#names .. " SOUNDKIT names match '" .. text .. "' (playing from " .. off .. ", 1 per second, max 40)")
	local i, last = off + 1, math.min(#names, off + 40)
	local function nextOne()
		if i > last then say("done; continue with: /dcprobe snd " .. text .. " " .. last); return end
		local n = names[i]; say(i .. ": " .. n .. " = " .. SOUNDKIT[n])
		pcall(PlaySound, SOUNDKIT[n], "SFX")
		i = i + 1
		C_Timer.After(1.1, nextOne)
	end
	nextOne()
end

-- /dcprobe flip <atlas> <rows> <cols> <frames>: shows the sheet and plays it as a FlipBook.
local function flipTest(rest)
	local name, r, c, f = (rest or ""):match("^(%S+)%s*(%d*)%s*(%d*)%s*(%d*)$")
	if not name then return say("usage: /dcprobe flip <atlas> <rows> <cols> <frames>") end
	r, c, f = tonumber(r) or 4, tonumber(c) or 4, tonumber(f) or ((tonumber(r) or 4) * (tonumber(c) or 4))
	if not DCProbeFlip then
		local g = CreateFrame("Frame", "DCProbeFlip", UIParent, "BackdropTemplate")
		g:SetSize(620, 300); g:SetPoint("CENTER")
		g:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" }); g:SetBackdropColor(0.1, 0.1, 0.14, 0.95)
		g:EnableMouse(true); g:SetMovable(true); g:RegisterForDrag("LeftButton")
		g:SetScript("OnDragStart", g.StartMoving); g:SetScript("OnDragStop", g.StopMovingOrSizing)
		local x = CreateFrame("Button", nil, g, "UIPanelCloseButton"); x:SetPoint("TOPRIGHT")
		g.sheet = g:CreateTexture(nil, "ARTWORK"); g.sheet:SetSize(280, 250); g.sheet:SetPoint("TOPLEFT", 20, -30)
		g.anim = g:CreateTexture(nil, "ARTWORK"); g.anim:SetSize(200, 200); g.anim:SetPoint("TOPLEFT", 340, -40)
		g.label = g:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); g.label:SetPoint("BOTTOMLEFT", 20, 8)
	end
	local g = DCProbeFlip
	g.sheet:SetAtlas(name)
	local info = C_Texture.GetAtlasInfo(name)
	g.anim:SetAtlas(name)
	if g.ag then g.ag:Stop() end
	g.ag = g.anim:CreateAnimationGroup(); g.ag:SetLooping("REPEAT")
	local ok, err = pcall(function()
		local a = g.ag:CreateAnimation("FlipBook")
		a:SetFlipBookRows(r); a:SetFlipBookColumns(c); a:SetFlipBookFrames(f); a:SetDuration(1.2)
		a:SetFlipBookFrameWidth(0); a:SetFlipBookFrameHeight(0)
	end)
	g.ag:Play()
	g.label:SetText(name .. "  size " .. tostring(info and info.width) .. "x" .. tostring(info and info.height) .. "  grid " .. r .. "x" .. c .. " frames " .. f .. (ok and "" or ("  ERR " .. tostring(err))))
	g:Show()
end

-- ---- listfile-based assets (FileDataIDs from the community listfile) -------------------------------
local SFX_TESTS = {
	{ "Fire Wave: flamestrike", 568641 }, { "Fire Shield: fireshield", 569485 }, { "Area Clear: arcaneexplosion", 568678 },
	{ "Freeze: frostnova", 569378 }, { "Row Clear: cleavetarget", 568227 }, { "Row Clear alt: whirlwindloop", 568214 },
	{ "Color Chain: lightningboltimpact", 568516 }, { "Color Chain alt: calllightning", 568555 }, { "Lifesteal: lifedrainloop", 569031 },
	{ "Convert: polymorphtarget", 569526 }, { "Stun: kidneyshot", 569110 }, { "Stun alt: hammerofjustice", 1250591 },
	{ "Color Swap: shadowwordpain_chest", 568353 }, { "Color Swap alt: curseoftounges", 567957 }, { "Shield: shieldwalltarget", 569473 },
	{ "Shield alt: divineshield", 569738 }, { "Bombs: firebombimpact1", 568733 }, { "Bombs alt: firebombimpact3", 568315 },
	{ "Heal: heal_low_base", 569570 }, { "Block (metal shield)", 567860 }, { "Sword hit (metal shield)", 567865 },
	{ "Hellhound attack", 600668 }, { "Hellhound wound", 600671 }, { "Hellhound death", 600677 }, { "Shield break", 568121 },
}
local function sfxAudition(rest)
	local from = tonumber(rest) or 1
	local i = from
	say("sound-file audition " .. from .. ".." .. #SFX_TESTS .. " (PlaySoundFile with FileDataIDs), 1.6 s each")
	local function nextOne()
		local t = SFX_TESTS[i]
		if not t then say("done"); return end
		say(i .. ": " .. t[1] .. "  (" .. t[2] .. ")")
		local ok, err = pcall(PlaySoundFile, t[2], "SFX")
		if not ok then say("  ERR " .. tostring(err)) end
		i = i + 1
		C_Timer.After(1.6, nextOne)
	end
	nextOne()
end

local FX_MODELS = {
	{ "frost_nova_area", 166210 }, { "frost_nova_state", 166211 }, { "stunswirl_state_head", 166988 },
	{ "chainlightning_impact_chest", 165780 }, { "divineshield_low_base", 165961 }, { "heal_low_base", 166292 },
	{ "polymorph_impact", 166649 }, { "arcaneexplosion_base", 165576 }, { "whirlwind_state_base", 167199 },
	{ "lifedrain_missile", 166469 }, { "fel_flamestrike_impact_base", 166085 }, { "hellhound (creature)", 511081 },
}
local function showFx()
	if DCProbeFx then DCProbeFx:Show() return end
	local g = CreateFrame("Frame", "DCProbeFx", UIParent, "BackdropTemplate")
	g:SetSize(6 * 150 + 20, 2 * 190 + 50); g:SetPoint("CENTER")
	g:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" }); g:SetBackdropColor(0.08, 0.08, 0.1, 0.96)
	g:EnableMouse(true); g:SetMovable(true); g:RegisterForDrag("LeftButton")
	g:SetScript("OnDragStart", g.StartMoving); g:SetScript("OnDragStop", g.StopMovingOrSizing)
	local x = CreateFrame("Button", nil, g, "UIPanelCloseButton"); x:SetPoint("TOPRIGHT")
	DB.fx = {}
	for i, t in ipairs(FX_MODELS) do
		local col, row = (i - 1) % 6, math.floor((i - 1) / 6)
		local h = CreateFrame("Frame", nil, g); h:SetSize(146, 180); h:SetPoint("TOPLEFT", 10 + col * 150, -30 - row * 190)
		local m = CreateFrame("PlayerModel", nil, h); m:SetAllPoints()
		local ok, err = pcall(function() m:SetModel(t[2]); m:SetAnimation(0) end)
		DB.fx[t[1]] = ok and "ok" or tostring(err)
		local fs = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); fs:SetPoint("BOTTOM"); fs:SetWidth(146); fs:SetText(t[1] .. (ok and "" or " ERR"))
	end
	g:Show()
end

-- /dcprobe screens [page]: loading-screen art (Interface\Glues\LoadingScreens, FileDataIDs) as background candidates.
local function showScreens(rest)
	local list = NS.screens or {}
	local page = tonumber(rest) or 1
	local per = 12
	if not DCProbeScreens then
		local g = CreateFrame("Frame", "DCProbeScreens", UIParent, "BackdropTemplate")
		g:SetSize(4 * 250 + 20, 3 * 175 + 50); g:SetPoint("CENTER")
		g:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" }); g:SetBackdropColor(0.08, 0.08, 0.1, 0.96)
		g:EnableMouse(true); g:SetMovable(true); g:RegisterForDrag("LeftButton")
		g:SetScript("OnDragStart", g.StartMoving); g:SetScript("OnDragStop", g.StopMovingOrSizing)
		local x = CreateFrame("Button", nil, g, "UIPanelCloseButton"); x:SetPoint("TOPRIGHT")
		g.cells = {}
		for i = 1, per do
			local c = CreateFrame("Frame", nil, g); c:SetSize(240, 170)
			c:SetPoint("TOPLEFT", 10 + ((i - 1) % 4) * 250, -30 - math.floor((i - 1) / 4) * 175)
			c.t = c:CreateTexture(nil, "ARTWORK"); c.t:SetSize(240, 150); c.t:SetPoint("TOP")
			c.s = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); c.s:SetPoint("BOTTOM")
			g.cells[i] = c
		end
		g.title = g:CreateFontString(nil, "OVERLAY", "GameFontNormal"); g.title:SetPoint("TOPLEFT", 10, -8)
	end
	local g = DCProbeScreens
	g.title:SetText("Loading screens page " .. page .. "/" .. math.ceil(#list / per) .. "   (/dcprobe screens N)")
	for i = 1, per do
		local e = list[(page - 1) * per + i]
		local c = g.cells[i]
		if e then c.t:SetTexture(e[1]); c.s:SetText(e[2] .. " " .. e[1]); c:Show() else c:Hide() end
	end
	g:Show()
end

local function fileSound(rest) local id = tonumber(rest); if id then say("PlaySoundFile " .. id); pcall(PlaySoundFile, id, "SFX") end end
local function modelBig(rest)
	local id = tonumber(rest); if not id then return end
	if not DCProbeModelBig then
		local g = CreateFrame("Frame", "DCProbeModelBig", UIParent, "BackdropTemplate")
		g:SetSize(400, 400); g:SetPoint("CENTER")
		g:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" }); g:SetBackdropColor(0.08, 0.08, 0.1, 0.96)
		g:EnableMouse(true); g:SetMovable(true); g:RegisterForDrag("LeftButton")
		g:SetScript("OnDragStart", g.StartMoving); g:SetScript("OnDragStop", g.StopMovingOrSizing)
		local x = CreateFrame("Button", nil, g, "UIPanelCloseButton"); x:SetPoint("TOPRIGHT")
		g.m = CreateFrame("PlayerModel", nil, g); g.m:SetPoint("TOPLEFT", 10, -30); g.m:SetPoint("BOTTOMRIGHT", -10, 10)
	end
	local ok, err = pcall(function() DCProbeModelBig.m:SetModel(id); DCProbeModelBig.m:SetAnimation(0) end)
	say("model " .. id .. (ok and " ok" or (" ERR " .. tostring(err))))
	DCProbeModelBig:Show()
end

SLASH_DCPROBE1 = "/dcprobe"
SlashCmdList.DCPROBE = function(arg)
	local cmd, rest = (arg or ""):match("^(%S*)%s*(.-)$")
	if cmd == "gems" then scanGems()
	elseif cmd == "grid" then showGrid(rest)
	elseif cmd == "mouse" then mouseTest()
	elseif cmd == "icons" then showIcons()
	elseif cmd == "set" then showSet()
	elseif cmd == "model" then showModels()
	elseif cmd == "ui" then showUI()
	elseif cmd == "atlas" then showAtlas()
	elseif cmd == "sound" then showSound()
	elseif cmd == "anim" then showAnim()
	elseif cmd == "snd" then sndAudition(rest)
	elseif cmd == "flip" then flipTest(rest)
	elseif cmd == "sfx" then sfxAudition(rest)
	elseif cmd == "fx" then showFx()
	elseif cmd == "screens" then showScreens(rest)
	elseif cmd == "file" then fileSound(rest)
	elseif cmd == "m2" then modelBig(rest)
	else runChecks() end
end
say("loaded. Commands: /dcprobe, /dcprobe gems, /dcprobe grid [n], /dcprobe mouse")
