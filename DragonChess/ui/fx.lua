local addonName, ns = ...
-- Spell effects (W0-P3): a small pool of PlayerModel frames that show spells/*.m2 effect models (by
-- FileDataID, Assets.FX) over the board, the enemy and the player bar. Purely cosmetic: no game rule,
-- no sim access. Created once (no frame creation or table allocation while playing), hard-capped:
--
--   SHOTS one-shot frames   Fx:play(key, col, row, now)  an effect for FX[key].duration sim seconds;
--                           a full pool recycles the oldest one.
--   HOLDS state frames      Fx:hold(name, on)  one frame per status (stun stars, freeze, Divine Aegis,
--                           Mirror Shield) shown while the status lasts; polled from the HUD state.
--
-- Time: one-shot lifetimes count in SIM time (Fx:update(now) from the HUD's per-frame update), so a
-- paused game ends nothing early. The models animate on engine time by themselves, which is why
-- Fx:stop_all() hides every frame on pause / hide / menu / game over (FightView:halt) and why nothing
-- plays while the sim is frozen (no sim event fires, the HUD update does not run). Every model call is
-- pcall-guarded: a model the client cannot load (SetModel error / GetModelFileID 0) just shows nothing,
-- and the caller keeps its non-model feedback (the red hit disc).
--
-- Dev: /dcfx <key> plays an effect now, /dcfx cam <scale> [x y z [rot]] re-frames the last played one
-- (print the values, copy them into Assets.FX), /dcsnd <slot> auditions a sound slot.

local pcall, type, tostring, tonumber, floor = pcall, type, tostring, tonumber, math.floor

local Fx = {}
Fx.__index = Fx

Fx.SHOTS = 6
Fx.CONE_SHIFT = 0.45 -- cone effects: the frame centre sits this fraction of the effect size right of the gem cell
Fx.DEV_DURATION = 6 -- seconds a dev-played effect stays (/dcfx, debug panel)
local COLS, ROWS = 8, 8 -- the board (ui/main.lua)
local DEFAULT_SIZE = 192
local PLAYER_AREA = 256 -- px side of the frame for effects on the player bar (a thin strip itself)
local DEV_DURATION = Fx.DEV_DURATION
local LEVEL_ABOVE_HOST = 20 -- over the enemy fx layer, the bottom strip and the vignette; below the overlay

local A -- ns.Assets (resolved in new)

local function model_call(model, method, ...)
	local fn = model[method]
	if fn == nil then return false end
	return (pcall(fn, model, ...))
end

local function new_model(root)
	local ok, f = pcall(CreateFrame, "PlayerModel", nil, root)
	if not ok or f == nil then return nil end
	f:Hide()
	f.t_end, f.key, f.on = nil, nil, false
	return f
end

-- win: the table from ns.Window.create. anchors: { enemy = frame, player = frame, board = frame } the
-- effects are placed against (board = the 8 x 8 gem host).
function Fx.new(win, anchors)
	A = ns.Assets
	local self = setmetatable({}, Fx)
	self.anchors = anchors
	self.now = 0
	self.last_at = {} -- key -> sim time of the last play (gap)
	self.last = nil -- the frame played last (/dcfx cam)
	self.last_key = nil
	local root = CreateFrame("Frame", nil, win.frame)
	root:SetSize(1, 1)
	root:SetPoint("CENTER", win.frame, "CENTER", 0, 0)
	root:SetFrameLevel(win.host:GetFrameLevel() + LEVEL_ABOVE_HOST)
	self.root = root
	self.shots = {}
	self.holds = {} -- name -> frame
	for i = 1, Fx.SHOTS do
		local f = new_model(root)
		if f == nil then break end
		self.shots[i] = f
	end
	for name in pairs(A.FX_HOLD) do
		local f = new_model(root)
		if f ~= nil then self.holds[name] = f end
	end
	self.available = #self.shots > 0
	return self
end

-- Stand-in when no effect frames can be made (same methods, nothing to show).
Fx.NONE = setmetatable({ available = false, shots = {}, holds = {}, anchors = {}, now = 0, last_at = {} }, Fx)

---------------------------------------------------------------- placement

-- Anchor + show + model set-up of one frame for an FX entry. col / row = the ability's gem cell (board
-- targets). Returns true when the model loaded.
local function setup(self, f, key, cfg, col, row)
	local at = cfg.at or "enemy"
	local size = cfg.size or DEFAULT_SIZE
	local a = self.anchors
	-- Unified frames (playtest 4): board effects get a frame exactly as big as the play area, enemy
	-- effects one as big as the enemy frame; the model fits to its frame and the camera scale shrinks
	-- it to `size` px, so nothing is cut off by the frame edge. Board effects sit at the board centre.
	local w, h
	if at == "enemy" then
		w, h = a.enemy:GetWidth(), a.enemy:GetHeight()
	elseif at == "player" then
		w, h = PLAYER_AREA, PLAYER_AREA
	else
		w, h = a.board:GetWidth(), a.board:GetHeight()
	end
	f:SetSize(w, h)
	f:ClearAllPoints()
	local px = cfg.px
	local dx, dy = px and px[1] or 0, px and px[2] or 0
	local anchor = a[at == "enemy" and "enemy" or at == "player" and "player" or "board"]
	-- W0-P7 (A3): with the ability's gem cell, "cell" is centred on that cell, "row" on that row (full board width kept,
	-- so only the vertical centre moves) and "cone" starts at the cell and points right (centre shifted right by
	-- CONE_SHIFT of the effect size). No col / row (or a non-board target) = the old centred placement.
	if col ~= nil and row ~= nil and (at == "cell" or at == "row" or at == "cone") then
		local cell = ns.BoardView.CELL
		local cx, cy = (col + 0.5) * cell, (row + 0.5) * cell
		if at == "row" then
			cx = w / 2
		elseif at == "cone" then
			cx = cx + size * Fx.CONE_SHIFT
		end
		f:SetPoint("CENTER", anchor, "TOPLEFT", cx + dx, -cy + dy)
	else
		f:SetPoint("CENTER", anchor, "CENTER", dx, dy)
	end
	local short = w < h and w or h
	f.dc_cam = (cfg.cam_scale or 1) * size / short
	f:Show()
	if not model_call(f, "SetModel", cfg.m2) then
		f:Hide()
		return false
	end
	local get = f.GetModelFileID
	if type(get) == "function" then
		local ok, fid = pcall(get, f)
		if ok and (fid == nil or fid == 0) then
			f:Hide()
			return false
		end
	end
	local pos = cfg.offset
	model_call(f, "SetAnimation", cfg.anim or 0)
	model_call(f, "SetCamDistanceScale", f.dc_cam)
	model_call(f, "SetPosition", pos and pos[1] or 0, pos and pos[2] or 0, pos and pos[3] or 0)
	model_call(f, "SetRotation", cfg.rot or 0)
	model_call(f, "SetModelScale", cfg.scale or 1)
	f.key = key
	self.last, self.last_key = f, key
	return true
end

---------------------------------------------------------------- one-shots

-- Plays the one-shot effect `key` (Assets.FX) at its target. now = sim time. Returns true when shown,
-- false when it cannot be (no entry / no frames / model failed), nil when throttled by the entry's gap.
function Fx:play(key, col, row, now, duration)
	local cfg = A.FX[key]
	if cfg == nil or not self.available then return false end
	now = now or self.now
	local gap = cfg.gap
	if gap ~= nil then
		local last = self.last_at[key]
		if last ~= nil and now - last >= 0 and now - last < gap then return nil end -- throttled
		self.last_at[key] = now
	end
	-- a free frame, else the one that ends first
	local shots, pick = self.shots, nil
	for i = 1, #shots do
		local f = shots[i]
		if f.t_end == nil then
			pick = f
			break
		end
		if pick == nil or f.t_end < pick.t_end then pick = f end
	end
	pick.t_end = nil
	if not setup(self, pick, key, cfg, col, row) then return false end
	pick.t_end = now + (duration or cfg.duration or 1)
	return true
end

-- Per frame (sim time): ends one-shots that ran out.
function Fx:update(now)
	self.now = now
	local shots = self.shots
	for i = 1, #shots do
		local f = shots[i]
		local t = f.t_end
		if t ~= nil and (now >= t or t - now > 60) then
			f.t_end = nil
			f:Hide()
		end
	end
end

---------------------------------------------------------------- holds

-- Shows / hides the state effect `name` (Assets.FX_HOLD); no-op when unchanged.
function Fx:hold(name, on)
	local f = self.holds[name]
	if f == nil or f.on == on then return end
	if not on then
		f.on = false
		f:Hide()
		return
	end
	if f.failed then return end -- a model that did not load is not retried every frame
	local key = A.FX_HOLD[name]
	local cfg = A.FX[key]
	if cfg == nil then
		f.failed = true
		return
	end
	f.on = setup(self, f, key, cfg, nil, nil)
	if not f.on then f.failed = true end
end

-- Pause / hide / menu / game over / new run: hides everything (models keep animating on engine time
-- otherwise). Holds are re-shown by the next HUD update.
function Fx:stop_all()
	local shots = self.shots
	for i = 1, #shots do
		local f = shots[i]
		f.t_end = nil
		f:Hide()
	end
	for _, f in pairs(self.holds) do
		f.on = false
		f:Hide()
	end
end

-- Number of visible effect frames (tests / dev).
function Fx:active_count()
	local n = 0
	for i = 1, #self.shots do
		if self.shots[i].t_end ~= nil then n = n + 1 end
	end
	for _, f in pairs(self.holds) do
		if f.on then n = n + 1 end
	end
	return n
end

---------------------------------------------------------------- dev commands

local function say(msg)
	print("|cffffcc00Dragon Chess|r " .. tostring(msg))
end

local function sorted_keys(t)
	local out = {}
	for k in pairs(t) do out[#out + 1] = k end
	table.sort(out)
	return table.concat(out, ", ")
end

-- /dcfx <key>            play an effect now (stays DEV_DURATION s) at its target
-- /dcfx cam <scale> [x y z [rot]]   re-frame the last played effect, print the values for Assets.FX
SLASH_DCFX1 = "/dcfx"
SlashCmdList.DCFX = function(msg)
	local App = ns.App
	local hud = App and App.hud
	local fx = hud and hud.fx
	if fx == nil or not fx.available then
		say("/dcfx: open the window first (no effect models available)")
		return
	end
	local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	if cmd == "" then
		say("/dcfx <key> | /dcfx cam <scale> [x y z [rot]]. Keys: " .. sorted_keys(A.FX))
		return
	end
	if cmd == "cam" then
		local f = fx.last
		if f == nil then
			say("/dcfx cam: play an effect first")
			return
		end
		local sc, x, y, z, rot = rest:match("^(%S+)%s*(%S*)%s*(%S*)%s*(%S*)%s*(%S*)")
		model_call(f, "SetCamDistanceScale", (tonumber(sc) or 1) * (f.dc_cam or 1)) -- relative to the entry (cam_scale multiplier)
		model_call(f, "SetPosition", tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0)
		if rot ~= nil and rot ~= "" then model_call(f, "SetRotation", tonumber(rot) or 0) end
		say(("%s: cam_scale = %s, offset = { %s, %s, %s }%s"):format(tostring(fx.last_key), tostring(tonumber(sc)),
			tostring(tonumber(x) or 0), tostring(tonumber(y) or 0), tostring(tonumber(z) or 0),
			(rot ~= nil and rot ~= "") and (", rot = " .. rot) or ""))
		return
	end
	if A.FX[cmd] == nil then
		say("/dcfx: unknown effect '" .. cmd .. "'. Keys: " .. sorted_keys(A.FX))
		return
	end
	if not App.running or App.soft or App.menu_open then
		say("/dcfx: open and unpause the window first")
		return
	end
	local combat = App.combat
	local now = combat and combat.sim.now or fx.now
	if fx:play(cmd, nil, nil, now, DEV_DURATION) then
		say(("%s: m2 %d at '%s' (frame %dpx). /dcfx cam <scale> [x y z [rot]] tunes it"):format(cmd, A.FX[cmd].m2,
			tostring(A.FX[cmd].at), A.FX[cmd].size or DEFAULT_SIZE))
	else
		say("/dcfx: " .. cmd .. " could not be shown (model failed to load?)")
	end
end

-- /dcsnd file <id> | kit <id> plays any FileDataID / SoundKit id.
-- /dcsnd <slot> auditions a sound slot (ignores quiet mode and the rate limit); no argument lists them.
SLASH_DCSND1 = "/dcsnd"
SlashCmdList.DCSND = function(msg)
	local key, file = (msg or ""):match("^%s*(%S+)%s*(%d*)")
	if (key == "file" or key == "kit") and tonumber(file) ~= nil then -- /dcsnd file 569565 | /dcsnd kit 101
		if key == "kit" then
			say("/dcsnd kit " .. file .. ((pcall(PlaySound, tonumber(file))) and "" or " (not playable)"))
		else
			say("/dcsnd file " .. file .. (A.play("match_cascade", tonumber(file), true) and "" or " (not playable)"))
		end
		return
	end
	if key == nil then
		say("/dcsnd <slot> [FileDataID]: " .. table.concat(A.sound_keys(), ", "))
		return
	end
	file = tonumber(file)
	if A.SOUNDS[key] == nil then
		say("/dcsnd: unknown slot '" .. key .. "'")
		return
	end
	if not A.sound_enabled then
		say("/dcsnd: sound is off (Menu)")
		return
	end
	say("/dcsnd " .. key .. (A.play(key, file, true) and "" or " (silent: no file / not playable)"))
end

ns.Fx = Fx
