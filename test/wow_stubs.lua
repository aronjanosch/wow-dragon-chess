-- Stubbed WoW API for headless UI tests (ui_smoke). Frames record their state
-- (shown, points, size, scripts, events); unknown methods raise, so a typo in
-- an API name fails the test instead of silently doing nothing. The method set
-- below is what the addon uses; check new ones against
-- docs/design/wow-forever-api.md before adding them here.
--
-- local W = dofile("test/wow_stubs.lua").new()
--   W.env           strict global environment for addon chunks (setfenv)
--   W.load(path, addonName, ns)
--   W.fire(event, ...), W.update(dt)  (OnUpdate on every visible frame)
--   W.cursor_x/y, W.button_down, W.errors, W.written (globals set by the addon)
local M = {}

-- Globals the addon may read before setting them (SavedVariables).
local NIL_OK = { DragonChessDB = true, DragonChessCharDB = true }

function M.new()
	local W = {
		frames = {}, errors = {}, written = {}, cursor_x = 0, cursor_y = 0, button_down = false, printed = {},
		wall = 1000, -- GetTime() (wall clock, advanced by W.update)
		sounds = {}, -- PlaySound / PlaySoundFile ids in order
		sound_kinds = {}, stopped = {}, next_handle = 0, -- see PlaySound below
		error_models = {}, -- model FileDataIDs SetModel raises for (W0-P3)
		error_displays = {}, -- display IDs SetDisplayInfo raises for (W0-P3.1)
		missing_atlas = {}, -- names GetAtlasExists reports as missing
		bad_textures = {}, -- texture FileDataIDs / paths SetTexture cannot load (GetTexture -> nil)
		bad_models = {}, -- model FileDataIDs SetModel cannot load (GetModelFileID -> 0)
		fail_frame_types = {}, -- CreateFrame(type) raises (e.g. PlayerModel unavailable)
		missing_templates = {}, -- template names CreateFrame raises for ("Couldn't find inherited node"), W0-P12
		bare_templates = {}, -- template names that create a frame WITHOUT the template's methods (SetText, SetChecked, ...)
	}

	---------------------------------------------------------------- regions

	local Region = {}
	Region.__index = function(_, k)
		local v = Region[k]
		if v == nil and type(k) == "string" and k:find("^%u") then error("stub: unknown region method " .. tostring(k), 2) end
		return v
	end
	local function new_region(kind, parent)
		W.regions = (W.regions or 0) + 1 -- textures / masks / font strings ever created (pool tests)
		return setmetatable({ kind = kind, parent = parent, shown = true, alpha = 1 }, Region)
	end
	function Region:SetTexture(path)
		self.texture = (not W.bad_textures[path]) and path or nil -- a file the client cannot load leaves it empty
		self.atlas = nil; return true
	end
	function Region:GetTexture() return self.texture end
	-- SetAtlas raises for an unknown atlas here (the client may not): callers
	-- must pcall it (ui/assets.lua Assets.apply).
	function Region:SetAtlas(name)
		if W.missing_atlas[name] then error("stub: unknown atlas " .. tostring(name)) end
		self.atlas = name; self.texture = nil
	end
	function Region:SetFontObject(f) self.font = f end
	function Region:SetColorTexture(r, g, b, a) self.r, self.g, self.b, self.a = r, g, b, a end
	function Region:SetTexCoord(l, r, t, b) self.tc_l, self.tc_r, self.tc_t, self.tc_b = l, r, t, b end
	-- 8-value form like the client: UL, LL, UR, LR (x, y each). Atlas rect after SetAtlas = 0.1..0.9 / 0.2..0.8 (fake).
	function Region:GetTexCoord()
		local l, r, t, b = self.tc_l or 0.1, self.tc_r or 0.9, self.tc_t or 0.2, self.tc_b or 0.8
		return l, t, l, b, r, t, r, b
	end
	function Region:SetVertexColor(r, g, b) self.vr, self.vg, self.vb = r, g, b end
	function Region:SetDesaturated(v) self.desat = v end
	function Region:SetRotation(r) self.rotation = r end -- Texture:SetRotation (W0-P6; the addon guards it with pcall)
	function Region:SetBlendMode(m) self.blend = m end
	function Region:AddMaskTexture(m) self.mask = m end
	function Region:RemoveMaskTexture(m) if self.mask == m then self.mask = nil end end
	function Region:SetAllPoints(rel) self.allpoints = rel or true end
	function Region:SetPoint(p, rel, rp, x, y) self.point, self.rel, self.rpoint, self.x, self.y = p, rel, rp, x, y end
	function Region:ClearAllPoints() self.point = nil end
	function Region:SetSize(w, h) self.w, self.h = w, h end
	function Region:SetWidth(w) self.w = w end
	function Region:SetHeight(h) self.h = h end
	function Region:Show() self.shown = true end
	function Region:Hide() self.shown = false end
	function Region:IsShown() return self.shown end
	function Region:SetAlpha(a) self.alpha = a end
	function Region:SetText(t) self.text = t end
	function Region:GetText() return self.text end
	function Region:SetTextColor(r, g, b, a) self.tr, self.tg, self.tb, self.ta = r, g, b, a end
	function Region:SetJustifyH(j) self.justify = j end
	-- W0-P8: FontString:SetScale is unverified live (the addon probes it with pcall); W.no_region_scale = true makes it raise.
	function Region:SetScale(s)
		if W.no_region_scale then error("stub: Region:SetScale unavailable") end
		self.scale = s
	end

	---------------------------------------------------------------- frames

	local Frame = {}
	-- W0-P12: methods only frames made from UIPanelButtonTemplate / UICheckButtonTemplate have (a bare Frame or a
	-- template listed in W.bare_templates lacks them: the kit's guard must fall back).
	local NATIVE_METHODS = {
		SetText = true, GetText = true, GetFontString = true, Enable = true, Disable = true, IsEnabled = true,
		SetChecked = true, GetChecked = true,
	}
	local frame_mt = {
		__index = function(f, k)
			local v = Frame[k]
			if v == nil and type(k) == "string" and k:find("^%u") then error("stub: unknown frame method " .. tostring(k), 2) end
			if (k == "SetBackdrop" or k == "SetBackdropColor" or k == "SetBackdropBorderColor") and not f.backdrop_template then
				error("stub: " .. k .. " needs BackdropTemplate", 2)
			end
			if v ~= nil and NATIVE_METHODS[k] and not f.native then error("stub: unknown frame method " .. tostring(k), 2) end
			return v
		end,
	}

	local function new_frame(ftype, name, parent, template)
		local f = setmetatable({
			ftype = ftype, name = name, parent = parent, shown = true, scripts = {}, events = {},
			alpha = 1, scale = 1, level = parent and (parent.level + 1) or 0, children = {},
			backdrop_template = template ~= nil and template:find("BackdropTemplate") ~= nil,
			template = template,
			native = template ~= nil and (template:find("UIPanelButtonTemplate") ~= nil or template:find("UICheckButtonTemplate") ~= nil)
				and not W.bare_templates[template],
			enabled = true,
		}, frame_mt)
		if parent then parent.children[#parent.children + 1] = f end
		W.frames[#W.frames + 1] = f
		return f
	end
	W.new_frame = new_frame

	function Frame:IsVisible()
		local f = self
		while f do
			if not f.shown then return false end
			f = f.parent
		end
		return true
	end
	function Frame:IsShown() return self.shown end
	function Frame:Show()
		if self.shown then return end
		self.shown = true
		if self.scripts.OnShow and (self.parent == nil or self.parent:IsVisible()) then self.scripts.OnShow(self) end
	end
	function Frame:Hide()
		if not self.shown then return end
		self.shown = false
		if self.scripts.OnHide and (self.parent == nil or self.parent:IsVisible()) then self.scripts.OnHide(self) end
	end
	function Frame:SetShown(v) if v then self:Show() else self:Hide() end end
	function Frame:SetScript(name, fn) self.scripts[name] = fn end
	function Frame:GetScript(name) return self.scripts[name] end
	function Frame:RegisterEvent(e)
		if e:find("^UNKNOWN") then error("stub: unknown event " .. e) end
		self.events[e] = true
	end
	function Frame:UnregisterEvent(e) self.events[e] = nil end
	function Frame:SetSize(w, h) self.w, self.h = w, h end
	function Frame:SetWidth(w) self.w = w end
	function Frame:SetHeight(h) self.h = h end
	function Frame:GetWidth() return self.w or 0 end
	function Frame:GetHeight() return self.h or 0 end
	function Frame:SetPoint(p, rel, rp, x, y) self.point, self.rel, self.rpoint, self.x, self.y = p, rel, rp, x, y end
	function Frame:GetPoint() return self.point, self.rel, self.rpoint, self.x, self.y end
	function Frame:ClearAllPoints() self.point = nil end
	function Frame:SetAllPoints(rel) self.allpoints = rel or true end
	function Frame:EnableMouse(v) self.mouse = v end
	function Frame:SetMovable(v) self.movable = v end
	function Frame:SetClampedToScreen(v) self.clamped = v end
	function Frame:SetDontSavePosition(v) self.dont_save = v end
	function Frame:RegisterForDrag(b) self.drag_button = b end
	function Frame:RegisterForClicks(b) self.click_button = b end
	function Frame:StartMoving() self.moving = true end
	function Frame:StopMovingOrSizing() self.moving = false end
	function Frame:SetScale(s) self.scale = s end
	function Frame:GetScale() return self.scale end
	function Frame:GetEffectiveScale()
		local s, f = 1, self
		while f do s = s * (f.scale or 1); f = f.parent end
		return s * (W.ui_scale or 1)
	end
	-- Geometry: tests set f.geo_left / f.geo_bottom (in the frame's own scale).
	function Frame:GetLeft() return self.geo_left end
	function Frame:GetBottom() return self.geo_bottom end
	-- W0-P4: centre from the test-set geometry (geo_left / geo_bottom + size).
	function Frame:GetCenter()
		if self.geo_left == nil or self.geo_bottom == nil then return nil end
		return self.geo_left + (self.w or 0) / 2, self.geo_bottom + (self.h or 0) / 2
	end
	function Frame:GetTop() return self.geo_bottom and self.geo_bottom + (self.h or 0) end
	function Frame:GetRight() return self.geo_left and self.geo_left + (self.w or 0) end
	function Frame:SetFrameStrata(s) self.strata = s end
	function Frame:SetToplevel(v) self.toplevel = v end
	function Frame:SetFrameLevel(l) self.level = l end
	function Frame:GetFrameLevel() return self.level end
	function Frame:SetClipsChildren(v) self.clips = v end
	function Frame:SetAlpha(a) self.alpha = a end
	function Frame:GetParent() return self.parent end
	function Frame:CreateTexture(_, layer) local r = new_region("Texture", self); r.layer = layer; return r end
	function Frame:CreateMaskTexture() return new_region("MaskTexture", self) end
	function Frame:CreateFontString(_, layer, font)
		local r = new_region("FontString", self); r.layer = layer; r.font = font; return r
	end
	function Frame:SetBackdrop(b) self.backdrop = b end
	function Frame:SetBackdropColor() end
	function Frame:SetBackdropBorderColor() end
	-- StatusBar (frame type verified live, probe 2026-10-04)
	local function statusbar_only(f, name)
		if f.ftype ~= "StatusBar" then error("stub: " .. name .. " on a " .. f.ftype, 3) end
	end
	function Frame:SetStatusBarTexture(path) statusbar_only(self, "SetStatusBarTexture"); self.bar_texture = path end
	function Frame:SetStatusBarColor(r, g, b, a)
		statusbar_only(self, "SetStatusBarColor"); self.br, self.bg, self.bb, self.ba = r, g, b, a
	end
	function Frame:SetMinMaxValues(lo, hi) statusbar_only(self, "SetMinMaxValues"); self.min_value, self.max_value = lo, hi end
	function Frame:SetValue(v) statusbar_only(self, "SetValue"); self.value = v end
	function Frame:GetValue() statusbar_only(self, "GetValue"); return self.value end
	function Frame:GetMinMaxValues() statusbar_only(self, "GetMinMaxValues"); return self.min_value, self.max_value end
	-- Cooldown (frame type verified live, probe 2026-10-04)
	local function only(f, ftype, name)
		if f.ftype ~= ftype then error("stub: " .. name .. " on a " .. f.ftype, 3) end
	end
	function Frame:SetCooldown(start, dur) only(self, "Cooldown", "SetCooldown"); self.cd_start, self.cd_dur = start, dur; W.cd_sets = (W.cd_sets or 0) + 1 end
	function Frame:SetHideCountdownNumbers(v) only(self, "Cooldown", "SetHideCountdownNumbers"); self.hide_numbers = v end
	function Frame:SetDrawEdge(v) only(self, "Cooldown", "SetDrawEdge"); self.draw_edge = v end
	function Frame:SetSwipeTexture(p) only(self, "Cooldown", "SetSwipeTexture"); self.swipe_texture = p end
	function Frame:SetSwipeColor(r, g, b, a) only(self, "Cooldown", "SetSwipeColor"); self.swipe = { r, g, b, a } end
	-- PlayerModel (verified live: SetDisplayInfo(1000) showed a creature)
	function Frame:ClearModel() only(self, "PlayerModel", "ClearModel"); self.model_cleared = true end
	function Frame:SetDisplayInfo(id)
		only(self, "PlayerModel", "SetDisplayInfo")
		if W.error_displays and W.error_displays[id] then error("stub: SetDisplayInfo rejected " .. tostring(id)) end -- W0-P3.1
		self.display_id = id; self.model_file = nil
	end
	-- SetModel(FileDataID): a file in W.bad_models loads nothing (GetModelFileID reports 0), like the client.
	function Frame:SetModel(id)
		only(self, "PlayerModel", "SetModel")
		if W.error_models[id] then error("stub: SetModel rejected " .. tostring(id)) end
		self.model_file = (not W.bad_models[id]) and id or 0
		self.display_id = nil
	end
	function Frame:GetModelFileID() only(self, "PlayerModel", "GetModelFileID"); return self.model_file end
	function Frame:SetRotation(r) only(self, "PlayerModel", "SetRotation"); self.rotation = r end
	function Frame:SetAnimation(a)
		only(self, "PlayerModel", "SetAnimation")
		if W.error_animations and W.error_animations[a] then error("stub: SetAnimation rejected " .. tostring(a)) end
		self.animation = a
		self.anim_log = self.anim_log or {}
		self.anim_log[#self.anim_log + 1] = a
	end
	function Frame:SetCamDistanceScale(v) only(self, "PlayerModel", "SetCamDistanceScale"); self.cam_scale = v end
	function Frame:SetPosition(x, y, z) only(self, "PlayerModel", "SetPosition"); self.pos = { x, y, z } end
	function Frame:SetModelScale(v) only(self, "PlayerModel", "SetModelScale"); self.model_scale = v end
	-- Template methods (W0-P12). The check button's label is NOT part of the template: the addon makes its own font string.
	function Frame:SetText(t) self.text = t end
	function Frame:GetText() return self.text end
	function Frame:GetFontString()
		self.fontstring = self.fontstring or new_region("FontString", self)
		return self.fontstring
	end
	function Frame:Enable() self.enabled = true end
	function Frame:Disable() self.enabled = false end
	function Frame:IsEnabled() return self.enabled end
	function Frame:SetChecked(v) self.checked = v and true or false end
	function Frame:GetChecked() return self.checked == true end
	function Frame:SetHitRectInsets(l, r, t, b) self.hit_insets = { l, r, t, b } end
	function Frame:Click()
		if self.scripts.OnClick then self.scripts.OnClick(self, "LeftButton", false) end
	end

	---------------------------------------------------------------- globals

	local UIParent = new_frame("Frame", "UIParent", nil)
	local stubs = {
		UIParent = UIParent,
		UISpecialFrames = {},
		SlashCmdList = {},
		CreateFrame = function(ftype, name, parent, template)
			if ftype ~= "Frame" and ftype ~= "Button" and ftype ~= "StatusBar" and ftype ~= "Cooldown"
				and ftype ~= "PlayerModel" and ftype ~= "CheckButton" then
				error("stub: frame type " .. tostring(ftype))
			end
			if W.fail_frame_types[ftype] then error("stub: frame type unavailable " .. ftype) end
			if template ~= nil and W.missing_templates[template] then error("stub: template not found " .. template) end
			local f = new_frame(ftype, name, parent, template)
			if name then W.named = W.named or {}; W.named[name] = f; W.store[name] = f end
			return f
		end,
		GetCursorPosition = function() return W.cursor_x, W.cursor_y end,
		IsMouseButtonDown = function(b) return b == "LeftButton" and W.button_down end,
		geterrorhandler = function() return function(err) W.errors[#W.errors + 1] = tostring(err) end end,
		debugstack = function() return "stack" end,
		debugprofilestop = function() return 1234.5 end,
		GetFramerate = function() return W.fps or 60 end, -- W0-D1 (debug panel footer)
		time = function() return 1700000000 end,
		GetBattlefieldStatus = function(i) return W.bg_status and W.bg_status[i] end,
		GetTime = function() return W.wall end,
		C_Texture = {
			GetAtlasExists = function(name) return not W.missing_atlas[name] end,
			-- fake atlas size (W.atlas_size, default 160 x 100, whole-file coords)
			GetAtlasInfo = function(name)
				if W.missing_atlas[name] then return nil end
				local sz = W.atlas_size or { 160, 100 }
				return { width = sz[1], height = sz[2], leftTexCoord = 0, rightTexCoord = 1,
					topTexCoord = 0, bottomTexCoord = 1 }
			end,
		},
		SOUNDKIT = {
			IG_MAINMENU_OPEN = 850, IG_MAINMENU_CLOSE = 851, IG_CHARACTER_INFO_TAB = 841,
			UI_BNET_TOAST = 18019, GS_TITLE_OPTION_OK = 798, IG_ABILITY_ICON_DROP = 838,
		},
		-- Both record the id in W.sounds (W.sound_kinds[i] = "kit" / "file") and return (willPlay, handle)
		-- like the client. W.fail_sound_file makes PlaySoundFile raise; W.stopped lists StopSound handles.
		PlaySound = function(id, channel)
			W.sounds[#W.sounds + 1] = id; W.sound_kinds[#W.sounds] = "kit"; W.sound_channel = channel
			W.next_handle = W.next_handle + 1
			return true, W.next_handle
		end,
		PlaySoundFile = function(id, channel)
			if W.fail_sound_file then error("stub: PlaySoundFile unavailable") end
			W.sounds[#W.sounds + 1] = id; W.sound_kinds[#W.sounds] = "file"; W.sound_channel = channel
			W.next_handle = W.next_handle + 1
			return true, W.next_handle
		end,
		StopSound = function(handle, fade) W.stopped[#W.stopped + 1] = handle; W.stop_fade = fade end,
		print = function(...) W.printed[#W.printed + 1] = table.concat({ tostring((...)) }, " ") end,
	}
	-- W0-P4: minimap, tooltip, addon compartment (all exist in the client; GameTooltip calls are recorded).
	local minimap = new_frame("Frame", "Minimap", UIParent)
	minimap:SetSize(140, 140)
	minimap.geo_left, minimap.geo_bottom = 1000, 600
	stubs.Minimap = minimap
	W.tooltip = { lines = {}, shown = false }
	stubs.GameTooltip = {
		SetOwner = function(_, owner) W.tooltip.owner = owner end,
		SetText = function(_, t) W.tooltip.lines = { t } end,
		AddLine = function(_, t) W.tooltip.lines[#W.tooltip.lines + 1] = t end,
		Show = function() W.tooltip.shown = true end,
		Hide = function() W.tooltip.shown = false end,
	}
	-- W1-G1 class picker: UnitClass("player") returns name, token (token = W.unit_class, nil = no class known);
	-- the icon sheet coords and class colours exist for every token (tests delete the stub to test the fallbacks).
	stubs.UnitClass = function() return "Hero", W.unit_class end
	stubs.CLASS_ICON_TCOORDS, stubs.RAID_CLASS_COLORS = {}, {}
	for i, token in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
		stubs.CLASS_ICON_TCOORDS[token] = { (i - 1) / 4, i / 4, 0, 0.25 }
		stubs.RAID_CLASS_COLORS[token] = { r = i / 10, g = 0.5, b = 1 - i / 10 }
	end
	W.compartment = {}
	stubs.AddonCompartmentFrame = {
		RegisterAddon = function(_, info) W.compartment[#W.compartment + 1] = info end,
	}
	W.stubs = stubs
	W.UIParent = UIParent

	local LUA = {
		assert = assert, error = error, ipairs = ipairs, next = next, pairs = pairs, pcall = pcall,
		rawget = rawget, rawset = rawset, select = select, setmetatable = setmetatable,
		getmetatable = getmetatable, tonumber = tonumber, tostring = tostring, type = type,
		unpack = unpack, xpcall = xpcall, collectgarbage = collectgarbage, _VERSION = _VERSION,
		math = math, string = string, table = table, coroutine = coroutine,
	}

	-- Globals the addon writes (and SavedVariables the test injects).
	W.store = {}
	W.env = setmetatable({}, {
		__index = function(_, k)
			local v = W.store[k]
			if v ~= nil then return v end
			v = stubs[k]
			if v ~= nil then return v end
			v = LUA[k]
			if v ~= nil then return v end
			if NIL_OK[k] then return nil end
			error("addon reads undeclared global '" .. tostring(k) .. "'", 2)
		end,
		__newindex = function(_, k, v)
			W.written[k] = true
			W.store[k] = v
		end,
	})

	function W.load(path, addon_name, ns)
		local chunk = assert(loadfile(path))
		setfenv(chunk, W.env)
		chunk(addon_name, ns)
	end

	function W.fire(event, ...)
		for i = 1, #W.frames do
			local f = W.frames[i]
			if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
		end
	end

	function W.update(dt)
		W.wall = W.wall + dt
		for i = 1, #W.frames do
			local f = W.frames[i]
			if f.scripts.OnUpdate and f:IsVisible() then f.scripts.OnUpdate(f, dt) end
		end
	end

	return W
end

return M
