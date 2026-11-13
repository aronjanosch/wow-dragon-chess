-- ui/ smoke test (W0-P1, combat flow W0-G1): loads the addon in TOC order under a stubbed WoW API
-- (test/wow_stubs.lua) and drives it like a player: ADDON_LOADED, /dchess,
-- OnUpdates, drag + click swaps, hide/show, soft pause, PLAYER_LOGOUT, a
-- restore from the saved snapshot, a corrupt snapshot and /dchess reset.
local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "."
local T = dofile(dir .. "/t.lua")
local loader = dofile(dir .. "/loader.lua")
local Stubs = dofile(dir .. "/wow_stubs.lua")
T.start("ui_smoke")

local ADDON = "DragonChess"
local addon_dir = loader.wow_dir() .. "/"
local DT = 1 / 60

-- Globals the addon may create (documented in ui/main.lua).
local ALLOWED_GLOBALS = {
	DragonChessDB = true, DragonChessCharDB = true,
	SLASH_DRAGONCHESS1 = true, SLASH_DRAGONCHESS2 = true, SLASH_DCBG1 = true, SLASH_DCFX1 = true, SLASH_DCSND1 = true,
}
local ALLOWED_NAMED_FRAMES = { DragonChessFrame = true, DragonChessEsc = true }

---------------------------------------------------------------- TOC

local function read_toc()
	local f = assert(io.open(addon_dir .. "DragonChess.toc"))
	local meta, files = {}, {}
	for line in f:lines() do
		line = line:gsub("\r", "")
		local k, v = line:match("^##%s*([%w_]+)%s*:%s*(.-)%s*$")
		if k then
			meta[k] = v
		elseif line:match("%S") and not line:match("^#") then
			files[#files + 1] = line:match("^%s*(.-)%s*$")
		end
	end
	f:close()
	return meta, files
end

local meta, toc_files = read_toc()
T.eq(meta.Interface, "16001", "TOC interface")
T.eq(meta.SavedVariables, "DragonChessDB", "TOC SavedVariables")
T.eq(meta.SavedVariablesPerCharacter, "DragonChessCharDB", "TOC SavedVariablesPerCharacter")
for i, f in ipairs(loader.CORE_FILES) do
	T.eq(toc_files[i], f, "TOC core order matches loader.CORE_FILES #" .. i)
end
for i = #loader.CORE_FILES + 1, #toc_files do
	T.ok(toc_files[i]:match("^ui/") ~= nil, "after core only ui/ files: " .. toc_files[i])
end
do -- every ui/*.lua is listed
	local p = io.popen('ls "' .. addon_dir .. 'ui/"*.lua 2>/dev/null')
	local listed = {}
	for _, f in ipairs(toc_files) do listed[f] = true end
	for line in p:lines() do
		local rel = "ui/" .. line:match("[^/]+$")
		T.ok(listed[rel], "TOC lists " .. rel)
	end
	p:close()
end

---------------------------------------------------------------- harness

-- Fresh client session: load every TOC file, inject SavedVariables, ADDON_LOADED.
local function session(saved)
	local W = Stubs.new()
	local ns = {}
	for _, f in ipairs(toc_files) do W.load(addon_dir .. f, ADDON, ns) end
	if saved then
		for k, v in pairs(saved) do W.store[k] = v end
	end
	W.fire("ADDON_LOADED", "SomeOtherAddon")
	W.fire("ADDON_LOADED", ADDON)
	W.ns, W.App = ns, ns.App
	return W
end

local function slash(W, msg)
	local list = W.store.SlashCmdList or W.stubs.SlashCmdList
	list.DRAGONCHESS(msg or "")
	-- W0-P10: opening the window shows the start / resume panel (game paused); these tests want a running game.
	if W.App ~= nil and W.App.start_open then W.App.close_start() end
end

local function frames(W, n)
	for _ = 1, n do W.update(DT) end
end

local function settle(W, max_frames)
	for _ = 1, max_frames or 2000 do
		W.update(DT)
		if W.App.sim:is_at_rest() then return true end
	end
	return false
end

-- Deep copy (simulates SavedVariables written to disk and read back).
local function copy(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in pairs(v) do out[copy(k)] = copy(x) end
	return out
end

local function dump(sim) return sim.board:dump(true) end

-- Put the cursor on the centre of a cell (+ px offset) of the board host.
local HOST_LEFT, HOST_BOTTOM = 120, 80
local function cursor_at(W, col, row, dx, dy)
	local host = W.App.win.host
	local cell = W.ns.BoardView.CELL
	local s = host:GetEffectiveScale()
	local lx = (col + 0.5) * cell + (dx or 0)
	local ly_top = (row + 0.5) * cell + (dy or 0)
	W.cursor_x = (HOST_LEFT + lx) * s
	W.cursor_y = (HOST_BOTTOM + 8 * cell - ly_top) * s
end

local function mouse(W, name)
	local host = W.App.win.host
	W.button_down = name == "OnMouseDown"
	host.scripts[name](host, "LeftButton")
end

local function no_errors(W, label)
	T.eq(#W.errors, 0, label .. ": no errors " .. tostring(W.errors[1]))
end

local function leaks(W, label)
	for k in pairs(W.written) do
		T.ok(ALLOWED_GLOBALS[k], label .. ": undocumented global written: " .. k)
	end
	for k in pairs(W.named or {}) do
		T.ok(ALLOWED_NAMED_FRAMES[k], label .. ": undocumented named frame: " .. k)
	end
	for k in pairs(W.stubs.SlashCmdList) do
		T.ok(k == "DRAGONCHESS" or k == "DCBG" or k == "DCFX" or k == "DCSND", label .. ": slash command key " .. k)
	end
end

-- Frames until pred() (max n); true when it became true.
local function frames_until(W, pred, n)
	for _ = 1, n or 2000 do
		if pred() then return true end
		W.update(DT)
	end
	return pred()
end

-- KB allocated by fn over `n` calls, GC stopped. LuaJIT's trace compiler
-- allocates GC objects of its own, so the JIT is off while measuring (WoW runs
-- PUC Lua 5.1, which is what the budget is about).
local function alloc_kb(fn, n)
	if jit then jit.off(); jit.flush() end
	collectgarbage("collect")
	collectgarbage("stop")
	local kb = collectgarbage("count")
	for _ = 1, n do fn() end
	local grown = collectgarbage("count") - kb
	collectgarbage("restart")
	if jit then jit.on() end
	return grown
end

local HELLHOUND_HP = 2250
local OGRE_HP = 3750
local PLAYER_HP = 10000

---------------------------------------------------------------- first run

local saved -- SavedVariables carried between sessions
T.case("first run: empty DB, open, fight starts, swaps, hide, HUD", function()
	local W = session(nil)
	local App = W.App
	T.eq(W.ns.Assets.gem_set, "jewels", "default gem set")
	App.set_gem_set("wow") -- the checks below are about the WoW icon set (menu test covers the others)
	T.ok(type(W.store.DragonChessDB) == "table", "DB created on ADDON_LOADED")
	T.eq(W.store.SLASH_DRAGONCHESS1, "/dchess", "/dchess")
	T.eq(W.store.SLASH_DRAGONCHESS2, "/dragonchess", "/dragonchess")
	T.ok(App.win == nil, "window created lazily")
	slash(W, "")
	local win = App.win
	T.ok(win ~= nil and win.frame:IsShown(), "/dchess opens the window")
	T.ok(W.stubs.UISpecialFrames[1] == "DragonChessEsc", "Esc closes it (Esc catcher in UISpecialFrames)")
	T.ok(App.sim ~= nil and App.combat ~= nil, "sim + combat created on show")
	T.ok(App.combat.sim == App.sim, "combat drives this sim")
	T.eq(#App.view.active, 64, "64 gem frames bound")
	T.ok(#App.view.free == 0, "pool of exactly 64")
	local first = App.view.active[1]
	T.ok(first.icon.texture:find("INV_Misc_Gem_") ~= nil, "gem icon texture: " .. tostring(first.icon.texture))
	T.eq(first.icon.tc_l, 0.08, "gem icon cropped")
	T.ok(first.icon.mask ~= nil, "gem icon masked")
	win.host.geo_left, win.host.geo_bottom = HOST_LEFT, HOST_BOTTOM
	W.ui_scale = 0.8 -- cursor maths must divide by the effective scale

	-- the fight started against the Hellhound, the boundary snapshot is stored
	local combat = App.combat
	T.ok(combat.enemy ~= nil and combat.enemy.name == "Hellhound", "fight started vs Hellhound")
	T.ok(not combat.fight_over and not combat.game_over, "fight live")
	local db = W.store.DragonChessDB
	T.ok(type(db.run) == "table" and db.run.v == App.RUN_VERSION, "fight-start snapshot stored")
	T.ok(type(db.run.combat) == "table" and type(db.run.board) == "table", "snapshot has combat + board (fresh board at rest)")
	local start_board = dump(App.sim)

	-- fight screen (W0-P2)
	local hud = App.hud
	local A = W.ns.Assets
	T.eq(hud.stage_text.text, "STAGE 1-1 \194\183 DIRE MAUL", "stage label with the stage name")
	T.eq(hud.name_text.text, "HELLHOUND", "enemy name in capitals")
	T.eq(hud.weak_name.text, "TOPAZ", "weakness colour")
	T.eq(hud.weak_icon.texture, A.GEM_ICON[5], "weakness gem icon (Topaz)")
	T.ok(hud.weak_icon.mask ~= nil, "weakness icon round-masked")
	T.eq(hud.enemy_hp.text, HELLHOUND_HP .. " / " .. HELLHOUND_HP, "HUD enemy HP text")
	T.eq(hud.enemy_bar.value, HELLHOUND_HP, "HUD enemy HP bar")
	T.eq(hud.enemy_bar.bar_texture, A.BAR, "HP bars use the WoW bar texture")
	T.eq(hud.player_hp.text, PLAYER_HP .. " / " .. PLAYER_HP, "HUD player HP text")
	for i = 1, 3 do
		local slot = hud.slots[i]
		T.ok(slot:IsShown(), "queue slot " .. i .. " shown")
		T.eq(slot.icon.texture, A.icon("hellhound_bite"), "queue slot " .. i .. " shows the bite icon")
	end
	T.ok(hud.slots[1].w > hud.slots[2].w, "first slot larger")
	T.eq(hud.q_timer.text, "3.8s", "HUD hit timer (first cooldown 1.4 x pace 2.2 + wind-up 8/12)")
	T.eq(hud.score_text.text, "0", "score plaque")
	T.ok(hud.model ~= nil and hud.model:IsShown() and hud.model.display_id == 12168, "enemy model (Hellhound display ID)")
	T.ok(not hud.portrait:IsShown(), "no portrait while the model works")
	T.eq(win.enemy_bg.texture, 340663, "stage 1 background: Dire Maul LFG art (enemy panel)")
	T.eq(win.board_bg.texture, 340663, "stage 1 background: Dire Maul LFG art (board panel)")
	T.ok(win.board_dim.a ~= nil and win.board_dim.a > 0.5, "board panel art dimmed")
	-- cover-fit: the 2:1 LFG background into the (taller) panel crops the sides, no stretch
	do
		local el, er, et, eb = W.ns.Assets.cover_coords(A.BG_FILE_W, A.BG_FILE_H, 0, 1, 0, 1, win.enemy_panel_w, win.panel_h)
		T.ok(math.abs(win.enemy_bg.tc_l - el) < 1e-6 and math.abs(win.enemy_bg.tc_r - er) < 1e-6, "enemy bg cropped to the panel aspect")
		T.ok(win.enemy_bg.tc_t == et and win.enemy_bg.tc_b == eb, "file crop: top / bottom as computed")
	end
	-- model framing + idle animation
	T.eq(hud.model.animation, 0, "model idle animation")
	T.ok(hud.model.cam_scale ~= nil and hud.model.pos ~= nil and hud.model.model_scale == 1, "model framed")
	-- OnSizeChanged: a hit punch resize does not reframe the model, a real size change does
	do
		local model, calls = hud.model, 0
		local orig = model.SetCamDistanceScale
		model.SetCamDistanceScale = function(self, v) calls = calls + 1; return orig(self, v) end
		local on_size = model.scripts.OnSizeChanged
		hud.punch = 1.03
		on_size(model)
		T.eq(calls, 0, "model: no reframe while a hit punch resizes the holder")
		hud.punch = 1
		on_size(model)
		T.ok(calls >= 1, "model: a real size change reframes")
		model.SetCamDistanceScale = orig
	end
	-- late model load (/reload): the display is set a second time, once per enemy
	do
		local model, sets = hud.model, 0
		local orig = model.SetDisplayInfo
		model.SetDisplayInfo = function(self, id) sets = sets + 1; return orig(self, id) end
		hud.reshown_key = nil
		model.scripts.OnModelLoaded(model)
		T.eq(sets, 1, "model: first OnModelLoaded sets the display again")
		model.scripts.OnModelLoaded(model)
		T.eq(sets, 1, "model: only once per enemy")
		-- fallback without OnModelLoaded: the timed re-show, also while the game is paused behind a menu
		hud.reshown_key = nil
		hud.reframe_n = 300
		for _ = 1, 80 do hud:settle_model() end
		T.eq(sets, 2, "model: timed re-show when OnModelLoaded never came")
		for _ = 1, 400 do hud:settle_model() end
		T.eq(sets, 2, "model: no further re-shows")
		T.ok(hud.model.display_id == 12168 and hud.model.cam_scale ~= nil, "model: still the Hellhound, framed")
		model.SetDisplayInfo = orig
	end
	-- /dcbg cycles the background shortlist and prints name + FileDataID
	do
		local name, id = hud:cycle_bg()
		T.eq(name, "lfg diremaul", "cycle_bg starts at the list head")
		T.eq(id, 340663, "cycle_bg returns the FileDataID")
		T.eq(win.enemy_bg.texture, id, "cycle_bg applies to the enemy panel")
		T.eq(win.board_bg.texture, id, "cycle_bg applies to the board panel")
		W.stubs.SlashCmdList.DCBG("")
		T.eq(win.enemy_bg.texture, 340705, "/dcbg advances")
		T.ok(W.printed[#W.printed]:find("zulgurub", 1, true) and W.printed[#W.printed]:find("340705", 1, true), "/dcbg prints name + ID")
		for _ = 1, #W.ns.Assets.BG_LIST - 2 do hud:cycle_bg() end
		local last, last_id = hud:cycle_bg()
		T.ok(last == "lfg diremaul" and last_id == 340663, "the shortlist wraps")
		T.eq(#W.ns.Assets.BG_LIST, 13, "13-item shortlist (10 LFG + 3 encounter journal)")
		W.stubs.SlashCmdList.DCBG("cam 0.5 0 0 0.1")
		T.eq(hud.model.cam_scale, 0.5, "/dcbg cam re-frames the model")
	end
	-- layout: panels side by side, board in the left panel, bars along the bottom
	T.eq(win.frame.w, 1010, "window width")
	T.eq(win.board_panel.rel, win.frame, "board panel anchored to the window")
	T.eq(win.enemy_panel.rel, win.board_panel, "enemy panel right of the board panel")
	T.eq(win.enemy_panel.point, "TOPLEFT", "enemy panel anchor")
	T.eq(win.enemy_panel.rpoint, "TOPRIGHT", "enemy panel anchor (relative)")
	T.eq(win.host.rel, win.board_panel, "board inside the board panel")
	T.eq(win.host.w, 8 * W.ns.BoardView.CELL, "board 8 cells wide")
	T.eq(W.ns.BoardView.CELL, 64, "64 px cells")
	T.eq(win.bottom.rel, win.board_panel, "bottom strip under the panels")
	T.eq(hud.player_bar.rel, win.bottom, "player bar on the bottom strip")
	T.eq(hud.enemy_bar.rel, win.bottom, "enemy bar on the bottom strip")
	T.ok(hud.player_bar.x < hud.enemy_bar.x, "player bar left, enemy bar right")
	T.eq(hud.plaque.parent, win.bottom, "score plaque on the bottom strip")
	T.eq(hud.queue.parent, win.enemy_panel, "attack queue in the enemy panel")
	T.ok(hud.enemy_holder.parent == win.enemy_panel, "enemy frame in the enemy panel")
	T.eq(win.overlay.allpoints, win.content, "overlay covers the content")
	T.ok(hud.cooldown ~= nil and hud.cooldown.ftype == "Cooldown", "queue timer sweep (Cooldown)")
	frames(W, 1) -- W0-P10: the start panel halted the HUD; the first running frame re-syncs the sweep
	T.ok(hud.cooldown.cd_dur ~= nil and math.abs(hud.cooldown.cd_dur - 3.7466) < 0.01, "sweep spans the attack cycle: " .. tostring(hud.cooldown.cd_dur))
	T.ok(W.sounds[1] == 850, "open sound (IG_MAINMENU_OPEN)")

	frames(W, 5)
	T.ok(App.sim.now > 0, "sim advances while shown")
	T.ok(settle(W), "settles")

	-- drag swap on a real move damages the enemy
	local Match = W.ns.Match
	local c1, r1, c2, r2 = Match.find_possible_move(App.sim.board)
	T.ok(c1 ~= nil, "board has a move")
	local matched = 0
	App.sim:on("match_resolved", function() matched = matched + 1 end)
	local enemy_hp = combat.enemy.current_health
	local cell = W.ns.BoardView.CELL
	cursor_at(W, c1, r1)
	mouse(W, "OnMouseDown")
	T.ok(App.input.press_gem ~= nil, "press picks a gem")
	cursor_at(W, c1, r1, (c2 - c1) * cell * 0.4, (r2 - r1) * cell * 0.4)
	frames(W, 1)
	T.ok(App.input.dragging, "dragging past the deadzone")
	T.ok(App.input.hx ~= 0 or App.input.hy ~= 0, "view-side drag offset")
	mouse(W, "OnMouseUp")
	T.eq(App.input.last_result, "ok", "drag release past 28 % swaps (through combat:try_swap)")
	T.ok(settle(W), "settles after drag swap")
	T.ok(matched >= 1, "drag swap matched")
	T.ok(combat.enemy.current_health < enemy_hp, "the swap damaged the enemy")
	frames(W, 1)
	T.eq(hud.enemy_bar.value, combat.enemy.current_health, "HUD enemy bar follows")
	frames(W, 30) -- count-up (0.45 sim s)
	T.ok(combat.score > 0 and hud.score_text.text == tostring(combat.score), "score plaque counts up to the score: " .. tostring(hud.score_text.text))

	-- auto-commit while held past 52 %
	c1, r1, c2, r2 = Match.find_possible_move(App.sim.board)
	App.input.last_result = nil
	cursor_at(W, c1, r1)
	mouse(W, "OnMouseDown")
	cursor_at(W, c1, r1, (c2 - c1) * cell * 0.7, (r2 - r1) * cell * 0.7)
	frames(W, 1)
	T.eq(App.input.last_result, "ok", "auto-commit past 52 %")
	mouse(W, "OnMouseUp")
	T.ok(settle(W), "settles after auto-commit")

	-- release fallback: button released without OnMouseUp
	c1, r1 = Match.find_possible_move(App.sim.board)
	cursor_at(W, c1, r1)
	mouse(W, "OnMouseDown")
	W.button_down = false
	frames(W, 1)
	T.ok(App.input.press_gem == nil, "IsMouseButtonDown poll releases")
	T.ok(App.input.selected ~= nil, "a press without drag is a tap (selects)")
	App.input:cancel()

	-- click-select + click-neighbour
	c1, r1, c2, r2 = Match.find_possible_move(App.sim.board)
	matched = 0
	cursor_at(W, c1, r1); mouse(W, "OnMouseDown"); mouse(W, "OnMouseUp")
	T.ok(App.input.selected ~= nil, "click selects")
	frames(W, 1)
	T.ok(App.view.sel:IsShown(), "selection glow shown")
	cursor_at(W, c2, r2); mouse(W, "OnMouseDown"); mouse(W, "OnMouseUp")
	T.eq(App.input.last_result, "ok", "click neighbour swaps")
	T.ok(App.input.selected == nil, "selection cleared")
	T.ok(settle(W), "settles after click swap")
	T.ok(matched >= 1, "click swap matched")

	-- click a non-neighbour moves the selection
	cursor_at(W, 0, 0); mouse(W, "OnMouseDown"); mouse(W, "OnMouseUp")
	cursor_at(W, 5, 5); mouse(W, "OnMouseDown"); mouse(W, "OnMouseUp")
	T.eq(App.input.last_result, "not_adjacent", "non-neighbour click")
	T.ok(App.input.selected == App.sim.board:get(5, 5), "selection moved")
	App.input:cancel()

	-- player stun: the combat gate rejects the swap, the HUD says so
	T.ok(settle(W), "rest before the stun check")
	combat:apply_player_stun(1.0)
	c1, r1, c2, r2 = Match.find_possible_move(App.sim.board)
	cursor_at(W, c1, r1); mouse(W, "OnMouseDown"); mouse(W, "OnMouseUp")
	cursor_at(W, c2, r2); mouse(W, "OnMouseDown"); mouse(W, "OnMouseUp")
	T.eq(App.input.last_result, "stunned", "swap rejected while stunned")
	frames(W, 1)
	T.eq(hud.flash_text.text, "Stunned!", "stun feedback text")
	T.eq(hud.flash_text.alpha, 1, "stun feedback shown")
	T.ok(hud.status.stun:IsShown(), "stun status icon shown")
	T.eq(hud.status.stun.num.text, "1", "stun icon shows whole seconds")
	T.eq(hud.status.stun.icon.texture, A.icon("status_stun"), "stun status icon texture")
	T.eq(hud.player_bar.lcolor, A.COLOR.ATTACK_STUN, "player bar violet while stunned")
	T.ok(frames_until(W, function() return combat:status_remaining("stun") <= 0 end, 120), "stun runs out on sim time")
	frames(W, 60)
	T.eq(hud.flash_text.alpha, 0, "feedback faded")
	T.ok(not hud.status.stun:IsShown(), "stun icon hidden again")
	T.eq(hud.player_bar.lcolor, A.COLOR.HP_PLAYER, "player bar green again")

	-- statuses show / hide with status_changed (hot + shield stacks)
	combat:apply_hot(5, 3.0, 1)
	combat:add_shield_stack(0)
	combat:add_shield_stack(0)
	frames(W, 1)
	T.ok(hud.status.hot:IsShown() and hud.status.hot.num.text == "3", "hot icon with seconds")
	T.ok(hud.status.shield:IsShown() and hud.status.shield.num.text == "2", "shield icon with stacks")
	T.ok(hud.status.shield.x < hud.status.hot.x, "status strip packed in order")
	frames(W, 60)
	T.ok(hud.status.hot.dim:IsShown(), "elapsed part dims the icon")
	T.ok(frames_until(W, function() return not hud.status.hot:IsShown() end, 200), "hot icon hides on expiry")
	combat.status.shield.stacks = 0
	frames(W, 1)
	T.ok(not hud.status.shield:IsShown(), "shield icon hides at 0 stacks")

	-- ability banner (handler of ability_triggered): fades in, holds, fades on sim time
	local n_sounds = #W.sounds
	App.sim:emit("ability_triggered", { toast = "FLAMESTRIKE", blurb = "Deal 150 damage", icon = "flamestrike", tier = 1 })
	frames(W, 10)
	T.eq(hud.banner.title.text, "FLAMESTRIKE", "banner title")
	T.eq(hud.banner.blurb.text, "Deal 150 damage", "banner blurb")
	T.eq(hud.banner.icon.texture, A.icon("flamestrike"), "banner icon")
	T.eq(hud.banner.alpha, 1, "banner shown")
	T.eq(W.sounds[n_sounds + 1], 841, "ability sound")
	win.frame:Hide()
	frames(W, 300)
	T.eq(hud.banner.alpha, 1, "banner frozen while hidden (sim time)")
	slash(W, "")
	frames(W, 120)
	T.eq(hud.banner.alpha, 0, "banner faded out (sim time)")

	-- the enemy attacks on its timer while shown
	local hp = combat.player_health
	T.ok(frames_until(W, function() return combat.player_health < hp end, 400), "an enemy hit lands while shown")
	frames(W, 1)
	T.eq(hud.player_hp.text, combat.player_health .. " / " .. PLAYER_HP, "HUD player HP follows")
	T.ok(hud.vignette.alpha > 0, "hit flash on player damage")
	local pop_on = false
	for i = 1, #hud.pops_player do
		if hud.pops_player[i].t0 ~= nil and (hud.pops_player[i].text or ""):find("^%-") then pop_on = true end
	end
	T.ok(pop_on, "player damage number")
	frames(W, 30)
	T.eq(hud.vignette.alpha, 0, "hit flash faded")

	-- hide = pause: board, enemy timer and statuses all freeze
	c1, r1, c2, r2 = Match.find_possible_move(App.sim.board)
	App.input:cancel()
	T.eq(App.sim:try_swap_cells(c1, r1, c2, r2), "ok", "swap started")
	combat:apply_hot(5, 5.0, 1)
	frames(W, 3)
	win.frame:Hide()
	T.ok(not App.running, "hidden: driver stopped")
	local now, board = App.sim.now, dump(App.sim)
	local next_attack = combat.enemy:get_time_to_next_attack()
	local hot = combat:status_remaining("hot")
	hp = combat.player_health
	frames(W, 600)
	win.frame.scripts.OnUpdate(win.frame, DT) -- even a stray OnUpdate
	T.eq(App.sim.now, now, "sim frozen while hidden")
	T.eq(dump(App.sim), board, "board unchanged while hidden")
	T.eq(combat.enemy:get_time_to_next_attack(), next_attack, "enemy attack timer frozen while hidden")
	T.eq(combat:status_remaining("hot"), hot, "status timer frozen while hidden")
	T.eq(combat.player_health, hp, "no hit while hidden")
	slash(W, "")
	T.ok(win.frame:IsShown(), "/dchess reopens")
	frames(W, 2)
	T.ok(App.sim.now > now, "resumes on show")
	T.ok(combat.enemy:get_time_to_next_attack() ~= next_attack, "enemy timer runs again")
	T.ok(settle(W), "settles after resume")

	-- soft pause: ready check pauses with an overlay, click resumes
	W.fire("READY_CHECK")
	T.ok(App.soft and win.overlay:IsShown(), "READY_CHECK soft-pauses with overlay")
	T.eq(hud.cooldown.cd_dur, 0, "Cooldown sweep cleared while soft-paused")
	now = App.sim.now
	frames(W, 20)
	T.eq(App.sim.now, now, "sim frozen while soft-paused")
	T.ok(win.frame:IsShown(), "window stays open")
	win.overlay:Click()
	T.ok(not App.soft and not win.overlay:IsShown(), "click resumes")
	frames(W, 2)
	T.ok(App.sim.now > now, "ticks again")
	T.ok(hud.cooldown.cd_dur > 0, "Cooldown sweep re-synced after the pause")
	win.pause:Click()
	T.ok(App.soft and win.overlay.text.text:find("Paused %(paused%)") ~= nil, "pause button soft-pauses")
	win.overlay:Click()
	T.ok(not App.soft, "click resumes after the pause button")
	-- entering combat hides the window (= paused), leaving combat reopens it at the resume panel
	now = App.sim.now
	W.fire("PLAYER_REGEN_DISABLED")
	T.ok(not win.frame:IsShown(), "combat hides the window by default")
	frames(W, 10)
	T.eq(App.sim.now, now, "sim frozen while hidden for combat")
	W.fire("PLAYER_REGEN_ENABLED")
	T.ok(win.frame:IsShown() and App.start_open, "leaving combat reopens at the resume panel")
	frames(W, 5)
	T.eq(App.sim.now, now, "still paused behind the resume panel")
	App.start.buttons.continue:Click()
	T.ok(not App.start_open, "continue closes the panel")
	W.fire("PLAYER_REGEN_ENABLED")
	T.ok(win.frame:IsShown(), "a stray PLAYER_REGEN_ENABLED changes nothing")
	-- closed by hand during combat: stays closed after combat
	W.fire("PLAYER_REGEN_DISABLED")
	slash(W, "")
	T.ok(win.frame:IsShown(), "reopened by hand in combat")
	win.frame:Hide()
	W.fire("PLAYER_REGEN_ENABLED")
	T.ok(not win.frame:IsShown(), "closed by hand in combat: stays closed")
	slash(W, "")
	App.start.buttons.continue:Click()
	-- option off: combat does nothing
	slash(W, "combat")
	T.eq(App.db.options.combat_hide, false, "/dchess combat turns it off")
	W.fire("PLAYER_REGEN_DISABLED")
	T.ok(win.frame:IsShown() and not App.soft, "option off: combat leaves the window alone")
	W.fire("PLAYER_REGEN_ENABLED")
	slash(W, "combat")
	T.eq(App.db.options.combat_hide, true, "/dchess combat turns it on again")
	W.bg_status = { "queued" }
	W.fire("UPDATE_BATTLEFIELD_STATUS", 1)
	T.ok(not App.soft, "battlefield queue status does not pause")
	W.bg_status = { "confirm" }
	W.fire("UPDATE_BATTLEFIELD_STATUS", 1)
	T.ok(App.soft, "battleground confirm pauses")
	win.frame:Hide()
	slash(W, "")
	T.ok(not App.soft, "reopening clears the soft pause")
	W.fire("LFG_PROPOSAL_SHOW")
	T.ok(App.soft, "LFG_PROPOSAL_SHOW pauses")
	win.overlay:Click()

	-- allocation: HUD + board view per frame during a live fight (the enemy
	-- attacking), measured apart from the sim tick (core timers allocate a
	-- coroutine per attack-cycle step; that is core, not the view).
	T.ok(settle(W), "rest before GC check")
	combat.player_health = PLAYER_HP -- survive 300 frames of hits
	local function view_frame()
		App.hud:update()
		App.view:update(App.input)
	end
	local ui_kb = 0
	local grown = alloc_kb(function()
		App.sim:tick(DT)
		local k = collectgarbage("count")
		view_frame()
		ui_kb = ui_kb + collectgarbage("count") - k
	end, 300)
	T.ok(ui_kb < 1, ("fight view + board view allocate < 1 KB per 300 fight frames (got %.2f KB; whole frame %.2f KB)"):format(ui_kb, grown))
	-- whole driver frames while the enemy is frozen (no timer restarts)
	combat.enemy:apply_stun(10, "freeze")
	frames(W, 2)
	grown = alloc_kb(function() W.update(DT) end, 300)
	T.ok(grown < 4, ("idle driver frames allocate < 4 KB per 300 frames (got %.2f KB)"):format(grown))
	T.eq(App.hud.q_timer.text, "FROZEN", "queue shows the enemy freeze")
	T.ok(App.hud.enemy_stun:IsShown(), "enemy freeze slot shown")
	T.eq(App.hud.enemy_stun.icon.texture, A.icon("frost_nova"), "enemy freeze icon")

	-- logout mid-fight keeps the fight-start snapshot (a reload restarts the fight)
	c1, r1, c2, r2 = Match.find_possible_move(App.sim.board)
	T.eq(App.sim:try_swap_cells(c1, r1, c2, r2), "ok", "swap before logout")
	frames(W, 4)
	W.fire("PLAYER_LOGOUT")
	db = W.store.DragonChessDB
	T.ok(type(db.run) == "table" and db.run.v == App.RUN_VERSION, "snapshot kept on mid-fight logout")
	T.eq(db.run.combat.player_health, PLAYER_HP, "it is the fight-start state")
	saved = { DragonChessDB = copy(db), DragonChessCharDB = copy(W.store.DragonChessCharDB) }
	saved.board = start_board
	no_errors(W, "first run")
	leaks(W, "first run")
end)

---------------------------------------------------------------- restore

T.case("restore after /reload restarts the fight", function()
	T.ok(saved ~= nil, "have a saved session")
	local W = session({ DragonChessDB = copy(saved.DragonChessDB), DragonChessCharDB = copy(saved.DragonChessCharDB) })
	slash(W, "")
	local App = W.App
	T.eq(dump(App.sim), saved.board, "fight-start board round-trips through SavedVariables")
	T.eq(App.combat.player_health, PLAYER_HP, "fight-start HP restored")
	T.eq(App.combat.score, 0, "fight-start score restored")
	T.ok(App.combat.enemy ~= nil and App.combat.enemy.current_health == HELLHOUND_HP, "fight restarted vs a fresh Hellhound")
	T.eq(#App.view.active, 64, "64 frames bound after restore")
	frames(W, 10)
	no_errors(W, "restore")
	leaks(W, "restore")

	-- /dchess reset: new run, snapshot replaced by the new fight's
	local old = App.sim
	W.stubs.debugprofilestop = function() return 98765.25 end -- a later moment: another seed
	slash(W, "reset")
	T.ok(App.sim ~= old, "reset starts a new run")
	T.ok(dump(App.sim) ~= saved.board, "with a new board")
	T.ok(W.store.DragonChessDB.run ~= nil and W.store.DragonChessDB.run.combat.score == 0, "snapshot = the new run's first fight")
	T.eq(#App.view.active, 64, "64 frames after reset")
	T.eq(#App.view.free, 0, "no frame leaked by reset")
	frames(W, 10)
	no_errors(W, "reset")
end)

T.case("logout without opening keeps the stored run", function()
	local W = session({ DragonChessDB = copy(saved.DragonChessDB) })
	W.fire("PLAYER_LOGOUT")
	T.ok(W.store.DragonChessDB.run ~= nil, "stored run kept")
	no_errors(W, "no-open logout")
end)

T.case("corrupt / old snapshot starts a new run silently", function()
	local bad = {
		{ run = { v = 1, board = "garbage" } },
		{ run = { v = 99 } },
		-- W0-P1 board-only snapshot (v = Sim.SNAPSHOT_VERSION, no combat)
		{ run = { v = 1, board = { v = 1, cols = 8, rows = 8, colors = 6, gems = {}, rng_refill = {}, rng_effects = {} } } },
		{ run = { v = 2, combat = { v = 99 } } },
		{ run = { v = 2, combat = "x", board = "y" } },
		{ run = { v = 3, combat = "x", board = "y", ladder = "z" } },
		{ run = "x", window = "y" },
	}
	for i, db in ipairs(bad) do
		local W = session({ DragonChessDB = db })
		slash(W, "")
		T.ok(W.App.sim ~= nil and #W.App.view.active == 64, "new board for bad snapshot #" .. i)
		T.ok(W.App.combat ~= nil and W.App.combat.enemy ~= nil, "fight started for bad snapshot #" .. i)
		T.eq(W.App.combat.player_health, PLAYER_HP, "fresh HP for bad snapshot #" .. i)
		frames(W, 5)
		no_errors(W, "bad snapshot #" .. i)
	end
end)

---------------------------------------------------------------- fight flow

T.case("enemy defeated -> CLEARED -> next fight", function()
	local W = session(nil)
	slash(W, "")
	local App = W.App
	local combat, hud = App.combat, App.hud
	T.ok(settle(W), "settles")
	local first = combat.enemy
	combat.player_health = 7000 -- HP carries into the next fight
	combat.score = 1234
	first:take_damage(first.current_health) -- the kill (core path: pauses gameplay)
	T.ok(combat.fight_over, "fight over")
	T.ok(App.run.next_at ~= nil, "next fight scheduled")
	T.eq(App.run.index, 2, "the run advanced")
	frames(W, 15)
	T.eq(hud.cleared.alpha, 0, "W0-P11: CLEARED not shown at the kill (the death plays alone for 1.0 s)")
	T.ok(not hud.name_text:IsShown() and not hud.enemy_hp:IsShown() and not hud.queue:IsShown(),
		"enemy name / HP text / attack queue hidden during the beat")
	T.eq(hud.enemy_hp.text, "0 / " .. HELLHOUND_HP, "HUD enemy HP at 0")
	T.eq(hud.q_timer.text, "", "no attack timer between fights")
	T.eq(hud.enemy_holder.alpha, 1, "dead enemy still shown while the death animation plays")
	frames(W, 50) -- 65 frames = 1.08 s since the kill
	T.ok(hud.cleared.alpha > 0, "CLEARED fading in at kill + 1.0 s")
	T.eq(hud.cleared.sub.text, "Next challenger approaches", "with its subtitle")
	frames(W, 15) -- 80 frames since the kill: death hold 0.7 s + fade 0.6 s
	T.eq(hud.enemy_holder.alpha, 0, "dead enemy faded out")

	-- logout between fights refreshes the snapshot (HP after the kill)
	W.fire("PLAYER_LOGOUT")
	local db = W.store.DragonChessDB
	T.ok(db.run ~= nil and db.run.combat.player_health == 7000, "between-fight snapshot on logout")
	T.eq(db.run.combat.score, 1234, "with the score")
	T.eq(db.run.ladder.index, 2, "and the advanced ladder position (the next fight)")
	T.eq(db.run.ladder.difficulty, 1, "and the difficulty")

	-- the transition runs on sim time: hiding freezes it
	App.win.frame:Hide()
	frames(W, 300)
	T.ok(combat.enemy == first, "no new fight while hidden")
	slash(W, "")
	local half = math.floor((App.FIGHT_TRANSITION / DT - 80) / 2) -- 80 frames of the transition are used up
	frames(W, half)
	T.ok(combat.enemy == first, "still in the transition after half of what is left")
	T.ok(frames_until(W, function() return combat.enemy ~= first end, half + 10), "next fight starts")
	T.ok(not combat.fight_over, "fight live again")
	T.eq(combat.enemy.def.id, "gordok_ogre", "fight 2 of the ladder: the Gordok Ogre")
	T.eq(combat.enemy.current_health, OGRE_HP, "fresh Gordok Ogre")
	T.eq(hud.stage_text.text, "STAGE 1-2 \194\183 DIRE MAUL", "stage label from the run")
	T.eq(hud.banner.title.text, "GORDOK OGRE", "W0-P11 spawn banner: the enemy name")
	T.eq(hud.banner.blurb.text, "STAGE 1-2 \194\183 DIRE MAUL", "and the stage")
	T.ok(hud.banner_t0 ~= nil, "banner running")
	T.ok(hud.name_text:IsShown() and hud.enemy_hp:IsShown() and hud.queue:IsShown(), "chrome back after the spawn")
	T.eq(combat.player_health, 7000, "player HP carried over")
	T.ok(combat.score >= 1234, "score keeps accumulating")
	frames(W, 1)
	T.eq(hud.cleared.alpha, 0, "CLEARED hidden")
	T.ok(hud.enemy_holder.alpha < 1, "the new enemy fades in (W0-P8 entrance)")
	frames(W, 30) -- the entrance lasts 0.35 s
	T.eq(hud.enemy_holder.alpha, 1, "new enemy visible")
	T.eq(hud.enemy_hp.text, OGRE_HP .. " / " .. OGRE_HP, "HUD shows the new enemy")
	T.eq(hud.name_text.text, "GORDOK OGRE", "HUD names the new enemy")
	T.ok(db.run ~= nil and W.store.DragonChessDB.run.combat.player_health == 7000, "fight-start snapshot of the 2nd fight")

	-- a swap between fights is gated
	T.ok(settle(W), "settles in fight 2")
	local second = combat.enemy
	second:take_damage(second.current_health)
	local Match = W.ns.Match
	local c1, r1, c2, r2 = Match.find_possible_move(App.sim.board)
	if c1 ~= nil then
		T.eq(App.swap(App.sim.board:get(c1, r1), App.sim.board:get(c2, r2)), "not_in_fight", "swap gated between fights")
		frames(W, 1)
		T.eq(hud.flash_text.text, "Wait for the next enemy", "between-fight feedback")
	end
	T.ok(frames_until(W, function() return combat.enemy ~= second end, 200), "third fight starts")
	no_errors(W, "fight flow")
	leaks(W, "fight flow")
end)

T.case("run lost -> overlay -> click restarts", function()
	local W = session(nil)
	slash(W, "")
	local App = W.App
	local win = App.win
	local combat = App.combat
	T.ok(settle(W), "settles")
	combat.player_health = 1
	combat.score = 500
	T.ok(frames_until(W, function() return combat.game_over end, 400), "an enemy hit kills the player")
	T.ok(App.lost, "run lost")
	-- W0-P12: the result screen replaces the text overlay for a lost run
	local rs = App.result_menu
	T.ok(rs.frame:IsShown() and not win.overlay:IsShown(), "result screen, no text overlay")
	T.eq(rs.box.title.text, "Defeated", "header Defeated")
	T.eq(rs.score.text, "500", "result shows the score")
	T.eq(rs.best.text, "Best (D1): 500", "result shows the best score")
	T.ok(rs.new_best:IsShown() and not rs.unlock:IsShown(), "new best flag, no unlock line")
	T.ok(rs.who_line.text:find("^Fell to ") ~= nil, "who line: " .. tostring(rs.who_line.text))
	T.eq(W.store.DragonChessDB.records[1].best, 500, "a lost run records its score (best on loss too)")
	T.eq(W.store.DragonChessDB.records[1].wins, nil, "no win counted")
	T.eq(W.store.DragonChessDB.unlocked, nil, "a loss unlocks nothing")
	T.ok(not App.can_input(), "input blocked")
	T.ok(W.store.DragonChessDB.run == nil, "lost run not saved")
	W.fire("PLAYER_LOGOUT")
	T.ok(W.store.DragonChessDB.run == nil, "logout after loss saves nothing")
	frames(W, 30)

	-- a soft pause on top, then resume: the result screen comes back
	W.fire("READY_CHECK")
	T.ok(win.overlay.text.text:find("Paused") ~= nil and not rs.frame:IsShown(), "soft pause overlay wins over the result")
	win.overlay:Click()
	T.ok(App.lost and rs.frame:IsShown() and not win.overlay:IsShown(), "result screen back")

	-- New run: the start screen (picker) first, then Start = new run (new combat, score 0, fight started)
	local old_sim = App.sim
	rs.buttons.new_run:Click()
	T.ok(not App.lost and not rs.frame:IsShown(), "result closed")
	T.ok(App.start_open and App.start.form == "start" and App.sim ~= old_sim, "new run waits behind the start form")
	App.start.buttons.start:Click()
	T.ok(App.sim ~= old_sim and App.combat ~= combat, "new run")
	T.eq(App.combat.score, 0, "score reset")
	T.eq(App.combat.player_health, PLAYER_HP, "HP reset")
	T.ok(App.combat.enemy ~= nil and not App.combat.game_over, "fight started")
	frames(W, 1)
	T.eq(App.hud.score_text.text, "0", "score plaque reset")
	T.ok(W.store.DragonChessDB.run ~= nil, "new run's fight-start snapshot")
	frames(W, 30)
	no_errors(W, "run lost")
	leaks(W, "run lost")
end)

T.case("fight screen: fallbacks, gem spell icons, hit FX", function()
	-- no PlayerModel, no atlases, no SOUNDKIT: portrait + colour fallbacks, silent
	local W = Stubs.new()
	W.fail_frame_types.PlayerModel = true
	for _, n in ipairs({ "groupfinder-background-dungeons", "UI-Frame-Neutral-CardParchment",
		"BossBanner-BgBanner-Mid", "GarrMission_EncounterBar-PortraitRing", "BossBanner-PortraitBorder",
		"BossBanner-TopFillagree" }) do
		W.missing_atlas[n] = true
	end
	W.bad_textures[340663] = true -- the stage file does not load: atlas (missing too) then colour
	W.stubs.SOUNDKIT = {} -- none of the picked keys exist
	local ns = {}
	for _, f in ipairs(toc_files) do W.load(addon_dir .. f, ADDON, ns) end
	W.fire("ADDON_LOADED", ADDON)
	W.ns, W.App = ns, ns.App
	slash(W, "")
	local App, A = W.App, ns.Assets
	local hud, win = App.hud, App.win
	T.ok(hud.model == nil, "no model frame")
	T.ok(hud.portrait:IsShown(), "portrait fallback shown")
	T.eq(hud.portrait.texture, A.ICON_DIR .. "Ability_Hunter_Pet_Wolf", "Hellhound portrait icon")
	T.ok(win.enemy_bg.atlas == nil and win.enemy_bg.r ~= nil, "background falls back to a colour")
	T.ok(win.enemy_bg.tc_l == 0 and win.enemy_bg.tc_r == 1, "colour fallback keeps full tex coords")
	do -- pure crop maths, fake atlas sizes
		local l, r, tt, b = A.cover_coords(160, 100, 0, 1, 0, 1, 500, 500) -- wide image, square panel
		T.ok(math.abs((r - l) - 0.625) < 1e-9 and math.abs((l + r) / 2 - 0.5) < 1e-9 and tt == 0 and b == 1, "wide image: crop sides, centred")
		l, r, tt, b = A.cover_coords(100, 160, 0, 1, 0, 1, 500, 500) -- tall image
		T.ok(math.abs((b - tt) - 0.625) < 1e-9 and l == 0 and r == 1, "tall image: crop top / bottom")
		l, r, tt, b = A.cover_coords(100, 100, 0.25, 0.75, 0, 0.5, 80, 80) -- same aspect, sub-rect
		T.ok(l == 0.25 and r == 0.75 and tt == 0 and b == 0.5, "equal aspect: coords unchanged")
		l, r = A.cover_coords(160, 100, 0.5, 1, 0, 1, 500, 500) -- sub-rect of a bigger file
		T.ok(math.abs((r - l) - 0.3125) < 1e-9 and math.abs((l + r) / 2 - 0.75) < 1e-9, "atlas sub-rect cropped inside its rect")
	end
	T.ok(not hud.slots[1].ring:IsShown(), "missing ring atlas hidden")
	T.eq(#W.sounds, 0, "no SOUNDKIT: silent, no error")
	T.ok(settle(W), "settles")

	-- enemy hit: punch, glow, damage number
	App.combat:deal_damage_to_enemy(100)
	frames(W, math.ceil(W.ns.Juice.FLY / DT) + 2) -- the streak (Juice.FLY) lands first (W0-P6): the reaction waits for it
	T.ok(hud.hit_glow.alpha > 0, "enemy hit glow")
	T.ok(hud.punch > 1, "enemy hit punch")
	local pop
	for i = 1, #hud.pops_enemy do
		if hud.pops_enemy[i].t0 ~= nil then pop = hud.pops_enemy[i] end
	end
	T.ok(pop ~= nil and pop.text == "-100", "enemy damage number: " .. tostring(pop and pop.text))
	frames(W, 60)
	T.ok(pop.t0 == nil and not pop.shown, "damage number recycled")
	T.eq(hud.hit_glow.alpha, 0, "glow faded")
	T.eq(hud.punch, 1, "punch settled")

	-- ability gem: spell icon overlay from the kit (tier 1 Ruby = Flamestrike)
	local gem = App.sim.board:get(3, 3)
	local f = App.view.frame_of[gem]
	T.ok(not f.spell:IsShown(), "plain gem: no spell icon")
	gem.type, gem.tier = 3, 1
	frames(W, 1)
	T.ok(f.spell:IsShown() and f.spell.texture == A.icon("flamestrike"), "skill gem shows its spell icon: " .. tostring(f.spell.texture))
	T.ok(f.spell.mask ~= nil, "spell icon round-masked")
	gem.tier = 2
	frames(W, 1)
	T.eq(f.spell.texture, A.icon("fire_shield"), "ult gem shows the ult icon")
	gem.tier, gem.bomb = 0, true
	frames(W, 1)
	T.eq(f.spell.texture, A.icon("bomb"), "bomb gem shows the bomb icon")
	gem.bomb = false
	frames(W, 1)
	T.ok(not f.spell:IsShown(), "back to a plain gem")

	-- Cooldown re-sync: hidden -> wall clock runs on, the sweep is re-set on show
	local cd = hud.cooldown
	local start = cd.cd_start
	T.ok(start ~= nil, "sweep running")
	win.frame:Hide()
	W.wall = W.wall + 30
	slash(W, "")
	frames(W, 1)
	T.ok(cd.cd_start > start + 29, "sweep re-anchored after hide (sim time, not wall time)")
	local sets = W.cd_sets
	frames(W, 20)
	T.ok(W.cd_sets <= sets + 1, "no per-frame SetCooldown while in sync")
	no_errors(W, "fallbacks")
	leaks(W, "fallbacks")
end)

T.case("/dchess fight <id> starts any enemy (dev command, W0-G2a)", function()
	local W = session(nil)
	slash(W, "")
	local App = W.App
	frames(W, 2)
	T.eq(App.combat.enemy.def.id, "hellhound", "default enemy")
	slash(W, "fight nefarian")
	T.eq(App.combat.enemy.def.id, "nefarian", "dev fight started")
	frames(W, 5)
	slash(W, "fight nobody")
	T.eq(App.combat.enemy.def.id, "nefarian", "unknown id changes nothing")
	slash(W, "reset")
	T.eq(App.combat.enemy.def.id, "hellhound", "reset clears the dev enemy")
	no_errors(W, "dev fight")
	leaks(W, "dev fight")
end)

---------------------------------------------------------------- W0-G2b: run, difficulty, enemy-status UI

local function last_print(W)
	return W.printed[#W.printed] or ""
end

local function hud_cleared_alpha(App) return App.hud.cleared.alpha end

local function kill_enemy(combat)
	combat.enemy:take_damage(combat.enemy.current_health)
end

T.case("ladder in the UI: stage label + background per stage, boss heal, scaled enemy", function()
	local W = session(nil)
	slash(W, "")
	local App = W.App
	local combat, hud, win, run = App.combat, App.hud, App.win, App.run
	T.eq(hud.stage_text.text, "STAGE 1-1 \194\183 DIRE MAUL", "stage 1-1")
	T.eq(win.enemy_bg.texture, 340663, "stage 1 art")
	run.index = 3
	run:begin_fight()
	frames(W, 2)
	T.eq(hud.stage_text.text, "STAGE 1-3 \194\183 DIRE MAUL", "stage 1-3 (the boss)")
	T.eq(hud.name_text.text, "BASILISK MATRIARCH", "Basilisk Matriarch")
	combat.player_health = 5000
	kill_enemy(combat)
	T.eq(combat.player_health, 7500, "core: boss heal +25 % applied at the kill")
	local function pop_live(text)
		for i = 1, #hud.pops_player do
			if hud.pops_player[i].text == text and hud.pops_player[i].t0 ~= nil then return true end
		end
		return false
	end
	frames(W, 1)
	T.eq(hud.player_hp.text, "5000 / 10000", "W0-P11: the HP bar still shows the pre-heal value at the kill")
	T.ok(not pop_live("+2500") and not pop_live("+2500 HP"), "no heal number at the kill")
	frames(W, 60 * 2) -- 2.0 s: the heal moment started at 1.75 s
	T.ok(pop_live("+2500 HP"), "heal number at the HP bar when the heal moment starts")
	T.ok(W.ns.Assets.SOUNDS.heal_moment ~= nil, "heal sound slot")
	frames(W, 60 * 2) -- 4.0 s: 2.25 s into the 5 s heal
	local mid = tonumber(hud.player_hp.text:match("^(%d+)"))
	T.ok(mid > 5000 and mid < 7500, "HP bar between old and new mid-beat: " .. hud.player_hp.text)
	T.ok(frames_until(W, function() return hud.player_hp.text == "7500 / 10000" end, 400), "HP bar reaches the new value")
	T.ok(frames_until(W, function() return combat.enemy.def.id == "forest_troll" end, 200), "stage 2 starts after the beat (kill + 6.75 s)")
	frames(W, 1)
	T.eq(hud.stage_text.text, "STAGE 2-1 \194\183 ZUL'GURUB", "stage 2-1")
	T.eq(win.enemy_bg.texture, 340705, "stage 2 art (enemy panel): Zul'Gurub")
	T.eq(win.board_bg.texture, 340705, "stage 2 art (board panel)")
	T.eq(W.store.DragonChessDB.run.ladder.index, 4, "fight-start snapshot holds the ladder position")
	T.eq(hud.q_timer.text, "11.7s", "Forest Troll first attack: cooldown 5 x pace 2.2 + wind-up 8/12 (timers run on the ladder's enemy)")
	T.eq(hud.slots[1].icon.texture, W.ns.Assets.intent_icon(run:base_def().rotation[1]), "queue glyph of the Forest Troll's axe")
	T.eq(hud.slots[1].icon.texture, W.ns.Assets.icon("kind_plain"), "(a plain hit)")
	no_errors(W, "ladder")
	leaks(W, "ladder")
end)

T.case("difficulty chooser: button, /dchess difficulty, locks, scaling, mid-run rule", function()
	local W = session({ DragonChessDB = { unlocked = 3 } })
	slash(W, "")
	local App = W.App
	local win, Run = App.win, W.ns.Run
	local function hellhound_hp(d) return Run.scale_def(W.ns.EnemyData.by_id.hellhound, d).max_health end
	T.eq(win.difficulty.text.text, "D1", "button shows D1")
	T.eq(App.combat.enemy.max_health, hellhound_hp(1), "D1 HP")
	-- the button cycles the unlocked levels; at the start of a run it restarts at once
	local old = App.sim
	win.difficulty:Click()
	T.ok(App.sim ~= old and App.run.difficulty == 2, "button: new run on D2")
	T.eq(win.difficulty.text.text, "D2", "button shows D2")
	T.eq(App.combat.enemy.max_health, hellhound_hp(2), "D2 enemy HP scaled")
	T.eq(App.combat.enemy_def.rotation[1].damage_min, Run.scale_def(W.ns.EnemyData.by_id.hellhound, 2).rotation[1].damage_min, "D2 damage scaled")
	T.eq(W.store.DragonChessDB.difficulty, 2, "choice stored")
	slash(W, "difficulty 3")
	T.eq(App.run.difficulty, 3, "/dchess difficulty 3 starts a D3 run")
	T.eq(App.combat.enemy.max_health, hellhound_hp(3), "D3 HP")
	slash(W, "difficulty 4")
	T.ok(last_print(W):find("locked") ~= nil, "D4 is locked: " .. last_print(W))
	T.eq(App.run.difficulty, 3, "unchanged")
	slash(W, "difficulty 9")
	T.ok(last_print(W):find("1%-5") ~= nil, "out of range: " .. last_print(W))
	slash(W, "difficulty x")
	T.ok(last_print(W):find("1%-5") ~= nil, "not a number")
	slash(W, "difficulty")
	T.ok(last_print(W):find("difficulty 3") ~= nil and last_print(W):find("unlocked up to 3") ~= nil, "status line: " .. last_print(W))
	win.difficulty:Click() -- wraps 3 -> 1
	T.eq(App.run.difficulty, 1, "button wraps to D1")
	-- mid-run: nothing is replaced, the choice waits for the next run
	App.combat.score = 100
	local sim = App.sim
	slash(W, "difficulty 2")
	T.ok(App.sim == sim and App.run.difficulty == 1, "mid-run: the running run is kept")
	T.ok(last_print(W):find("next run") ~= nil, "says so: " .. last_print(W))
	T.eq(win.difficulty.text.text, "D1>2", "button shows run>next")
	slash(W, "reset")
	T.eq(App.run.difficulty, 2, "reset starts the chosen difficulty")
	T.eq(win.difficulty.text.text, "D2", "button shows D2")
	-- only D1 unlocked: the button explains
	local W2 = session(nil)
	slash(W2, "")
	W2.App.win.difficulty:Click()
	T.ok(last_print(W2):find("only difficulty 1") ~= nil, "locked button: " .. last_print(W2))
	T.eq(W2.App.run.difficulty, 1, "stays on D1")
	-- a stored choice above the unlocked level is clamped
	local W3 = session({ DragonChessDB = { difficulty = 5, unlocked = 2 } })
	slash(W3, "")
	T.eq(W3.App.run.difficulty, 2, "stored D5 clamped to the unlocked D2")
	no_errors(W, "difficulty")
	no_errors(W2, "difficulty 2")
	leaks(W, "difficulty")
end)

T.case("run won: overlay, records, unlock, persistence, new run", function()
	local W = session(nil)
	slash(W, "")
	local App = W.App
	local win, combat = App.win, App.combat
	App.run.index = 10
	App.run:begin_fight()
	frames(W, 1)
	T.eq(App.hud.stage_text.text, "STAGE 4-1 \194\183 BLACKWING LAIR", "final stage label")
	T.eq(App.hud.name_text.text, "NEFARIAN", "Nefarian")
	combat.score = 4242
	kill_enemy(combat)
	T.ok(App.won, "run won at the kill")
	frames(W, 30)
	T.ok(not win.overlay:IsShown(), "W0-P11: no victory overlay during the 1.0 s death beat")
	T.eq(hud_cleared_alpha(App), 0, "and no CLEARED sting after the last boss")
	frames(W, 40)
	local rs = App.result_menu
	T.ok(rs.frame:IsShown() and not win.overlay:IsShown(), "victory result screen")
	T.eq(rs.box.title.text, "Victory", "header Victory")
	T.eq(rs.score.text, "4242", "shows the score")
	T.eq(rs.best.text, "Best (D1): 4242", "best line")
	T.ok(rs.new_best:IsShown(), "new best flag")
	T.ok(rs.unlock:IsShown() and rs.unlock.text == "Difficulty 2 unlocked", "unlock announced: " .. tostring(rs.unlock.text))
	T.ok(rs.who_line.text:find("enemies defeated") ~= nil, "who line: " .. tostring(rs.who_line.text))
	local db = W.store.DragonChessDB
	T.eq(db.records[1].best, 4242, "best score stored")
	T.eq(db.records[1].wins, 1, "win stored")
	T.eq(db.unlocked, 2, "D2 unlocked")
	T.eq(db.run, nil, "the won run is not kept")
	T.ok(not App.can_input(), "input blocked on the result screen")
	frames(W, 120)
	T.ok(combat.fight_over and combat.enemy.def.id == "nefarian", "no further fight after the win")
	W.fire("PLAYER_LOGOUT")
	T.eq(W.store.DragonChessDB.run, nil, "logout after a win saves no run")
	-- soft pause on top, then back to the result screen
	W.fire("READY_CHECK")
	T.ok(win.overlay.text.text:find("Paused") ~= nil and not rs.frame:IsShown(), "soft pause wins")
	win.overlay:Click()
	T.ok(App.won and rs.frame:IsShown(), "result screen back")
	-- New run -> start form -> Start
	local old_sim = App.sim
	rs.buttons.new_run:Click()
	T.ok(not App.won and App.sim ~= old_sim and App.start_open, "new run behind the start form")
	App.start.buttons.start:Click()
	T.eq(App.run.index, 1, "back at fight 1")
	T.eq(App.combat.score, 0, "score reset")
	T.eq(App.hud.stage_text.text, "STAGE 1-1 \194\183 DIRE MAUL", "stage 1-1 again")
	T.ok(App.can_input(), "input back")
	frames(W, 10)
	-- records survive a new session
	local db2 = copy(W.store.DragonChessDB)
	db2.run = nil -- (the new run's fight-start snapshot would be restored)
	local W2 = session({ DragonChessDB = db2 })
	slash(W2, "difficulty")
	T.ok(last_print(W2):find("unlocked up to 2") ~= nil and last_print(W2):find("best 4242") ~= nil, "records read after a restart: " .. last_print(W2))
	slash(W2, "difficulty 2")
	slash(W2, "")
	T.eq(W2.App.run.difficulty, 2, "D2 is choosable after the unlock")
	no_errors(W, "run won")
	no_errors(W2, "run won (2)")
	leaks(W, "run won")
end)

T.case("old-version / ladder-less snapshots are discarded, a good one restores the ladder", function()
	T.ok(saved ~= nil, "have a saved session")
	local function with(mut)
		local db = copy(saved.DragonChessDB)
		mut(db)
		local W = session({ DragonChessDB = db })
		slash(W, "")
		frames(W, 3)
		no_errors(W, "snapshot variant")
		return W
	end
	local W = with(function(db) db.run.ladder.index = 5 end)
	T.eq(W.App.run.index, 5, "a v3 snapshot restores the ladder position")
	T.eq(W.App.combat.enemy.def.id, "harpy", "fight 5 restarts")
	T.eq(W.App.hud.stage_text.text, "STAGE 2-2 \194\183 ZUL'GURUB", "with its label")
	W = with(function(db) db.run.v = 2 end)
	T.eq(W.App.run.index, 1, "a v2 snapshot (before the ladder) is discarded: new run")
	W = with(function(db) db.run.ladder = nil end)
	T.eq(W.App.run.index, 1, "no ladder: new run")
	W = with(function(db) db.run.ladder.index = 99 end)
	T.eq(W.App.run.index, 1, "bad ladder index: new run")
	W = with(function(db) db.run.ladder.difficulty = 4 end)
	T.eq(W.App.run.difficulty, 4, "the run's difficulty is restored")
	T.eq(W.App.combat.enemy.max_health, W.ns.Run.scale_def(W.ns.EnemyData.by_id.hellhound, 4).max_health, "and applied to the restarted fight")
end)

T.case("enemy status visuals: Aegis, Mirror, phases, Sandstorm, junk, intent glyphs, stun", function()
	local W = session(nil)
	slash(W, "")
	local App = W.App
	local A = W.ns.Assets
	local combat, hud, sim = App.combat, App.hud, App.sim
	local function pop_text(text)
		for i = 1, #hud.pops_enemy do
			if hud.pops_enemy[i].t0 ~= nil and hud.pops_enemy[i].text == text then return true end
		end
		return false
	end

	slash(W, "fight hakkar")
	frames(W, 2)
	T.eq(hud.stage_text.text, "DEV", "dev fight label")
	-- per-kind intent glyphs (Hakkar: Blood Strike plain, Cause Insanity stagger, Divine Aegis)
	T.eq(hud.slots[1].icon.texture, A.icon("kind_plain"), "plain hit glyph")
	T.eq(hud.slots[2].icon.texture, A.icon("kind_stagger"), "stagger glyph")
	T.eq(hud.slots[3].icon.texture, A.icon("kind_aegis"), "Aegis glyph")
	T.ok(hud.slots[1].icon.texture ~= A.icon("unknown"), "no question marks in the queue")
	-- Divine Aegis
	T.ok(not hud.aegis_icon:IsShown() and not hud.aegis_glow:IsShown(), "no Aegis before it is cast")
	combat.enemy:apply_spell_immunity(5)
	frames(W, 1)
	T.ok(hud.aegis_icon:IsShown() and hud.aegis_glow:IsShown(), "Aegis: icon + gold glow")
	T.eq(hud.aegis_icon.num.text, "5", "Aegis seconds")
	T.eq(hud.aegis_icon.icon.texture, A.icon("enemy_aegis"), "Aegis icon")
	T.ok(hud.aegis_glow.r == A.COLOR.AEGIS_GLOW[1] and hud.aegis_glow.g == A.COLOR.AEGIS_GLOW[2], "gold glow colour")
	T.eq(hud.aegis_glow.blend, "ADD", "additive glow")
	T.ok(hud.aegis_glow.alpha > 0, "glow visible")
	combat.enemy:apply_stun(2, "stun")
	frames(W, 1)
	T.ok(pop_text("Immune"), "a bounced stun pops 'Immune'")
	T.ok(not hud.enemy_stun:IsShown(), "no stun while immune")
	T.ok(frames_until(W, function() return not hud.aegis_icon:IsShown() end, 400), "Aegis ends on sim time")
	T.ok(not hud.aegis_glow:IsShown(), "glow gone")

	-- the effects below run against the Hellhound (a plain bite only: nothing casts its own Aegis)
	slash(W, "fight hellhound")
	combat = App.combat
	frames(W, 2)
	T.ok(not hud.aegis_icon:IsShown(), "new enemy: no Aegis")
	-- stun / freeze slot (enemy status)
	combat.enemy:apply_stun(2, "freeze")
	frames(W, 1)
	T.ok(hud.enemy_stun:IsShown() and hud.enemy_stun.icon.texture == A.icon("frost_nova"), "freeze icon")
	T.eq(hud.q_timer.text, "FROZEN", "FROZEN text")

	-- Mirror Shield: icon, silver glow, crack bar, shatter
	combat.enemy:apply_mirror_shield(8, 0.6, 500, 1)
	frames(W, 1)
	T.ok(hud.mirror_icon:IsShown() and hud.mirror_glow:IsShown() and hud.crack_bar:IsShown(), "Mirror: icon + glow + crack bar")
	T.eq(hud.mirror_icon.num.text, "8", "Mirror seconds")
	T.eq(hud.crack_bar.text.text, "Crack 0%", "crack text at 0")
	T.ok(hud.mirror_glow.b == A.COLOR.MIRROR_GLOW[3], "silver glow colour")
	T.ok(pop_text("Mirror!"), "'Mirror!' pop")
	combat.enemy:add_mirror_crack(250)
	frames(W, 1)
	T.eq(hud.crack_bar.value, 50, "crack bar at 50 %")
	T.eq(hud.crack_bar.text.text, "Crack 50%", "crack text")
	combat.enemy:add_mirror_crack(300) -- shatters
	frames(W, 1)
	T.eq(hud.mirror_msg.text, "SHATTERED!", "shatter text")
	T.eq(hud.mirror_msg.alpha, 1, "shatter text shown")
	T.ok(not hud.mirror_icon:IsShown() and not hud.crack_bar:IsShown() and not hud.mirror_glow:IsShown(), "Mirror visuals gone")
	frames(W, 90)
	T.eq(hud.mirror_msg.alpha, 0, "shatter text faded")
	-- expiry shows no shatter text
	combat.enemy:apply_mirror_shield(1, 0.6, 500, 1)
	frames(W, 80)
	T.ok(not hud.mirror_icon:IsShown() and hud.mirror_msg.alpha == 0, "an expired Mirror just disappears")
	-- a mirror reflect hit says where it came from
	combat:take_true_damage(100, "mirror")
	frames(W, 1)
	local rpop
	for i = 1, #hud.pops_player do
		if hud.pops_player[i].t0 ~= nil and hud.pops_player[i].text == "-100 mirror" then rpop = true end
	end
	T.ok(rpop, "mirror damage number is labelled")

	-- Sandstorm: board tint + player strip icon
	T.ok(not hud.sand_tint:IsShown() and not hud.status.sandstorm:IsShown(), "no Sandstorm yet")
	sim:set_gravity_slow(0.3, 8)
	frames(W, 1)
	T.ok(hud.sand_tint:IsShown() and hud.sand_tint.alpha == 1, "sand layer over the board")
	T.ok(hud.status.sandstorm:IsShown() and hud.status.sandstorm.num.text == "8", "Sandstorm status icon with seconds")
	T.eq(hud.status.sandstorm.icon.texture, A.icon("status_sandstorm"), "Sandstorm icon")
	frames(W, 60 * 7 + 30) -- 7.5 s: inside the last second
	T.ok(hud.sand_tint:IsShown() and hud.sand_tint.alpha < 1, "sand layer fades out in the last second: " .. tostring(hud.sand_tint.alpha))
	frames(W, 60)
	T.ok(not hud.sand_tint:IsShown() and not hud.status.sandstorm:IsShown(), "Sandstorm over")
	-- junk flash
	T.ok(not hud.junk_tint:IsShown(), "no junk flash")
	sim:emit("junk_spawned", {})
	frames(W, 1)
	T.ok(hud.junk_tint:IsShown() and hud.junk_tint.alpha > 0, "junk flash over the board")
	frames(W, 60)
	T.ok(not hud.junk_tint:IsShown(), "junk flash faded")

	-- phases (Nefarian): banner + the phase in the stage line
	slash(W, "fight nefarian")
	frames(W, 2)
	T.eq(hud.stage_text.text, "DEV", "no phase yet")
	T.eq(hud.phase_banner.alpha, 0, "no phase banner yet")
	combat.enemy:take_damage(math.floor(combat.enemy.max_health * 0.4)) -- 60 %: below 66 %
	frames(W, 4)
	T.eq(hud.phase_banner.title.text, "SHADOW FLAME", "phase banner names the phase")
	T.ok(hud.phase_banner.alpha > 0, "phase banner shown")
	T.ok(hud.stage_text.text:find("SHADOW FLAME") ~= nil, "stage line shows the phase: " .. tostring(hud.stage_text.text))
	T.eq(hud.slots[1].icon.texture, A.icon("kind_flurry"), "phase rotation glyphs (Claw Flurry)")
	T.eq(hud.slots[2].icon.texture, A.icon("kind_heal_block"), "heal-block glyph")
	frames(W, 150)
	T.eq(hud.phase_banner.alpha, 0, "phase banner faded")
	combat.enemy:take_damage(math.floor(combat.enemy.max_health * 0.3)) -- below 33 %
	frames(W, 4)
	T.eq(hud.phase_banner.title.text, "CORRUPTED", "second phase")
	T.eq(hud.slots[3].icon.texture, A.icon("kind_mirror"), "mirror glyph in Corrupted's rotation")
	T.eq(hud.slots[1].icon.texture, A.icon("kind_sand"), "sand glyph")
	T.eq(hud.slots[2].icon.texture, A.icon("kind_nuke"), "nuke glyph")

	-- no per-frame allocation with every effect running
	combat.enemy:apply_spell_immunity(30)
	combat.enemy:apply_mirror_shield(30, 0.6, 500, 1)
	sim:set_gravity_slow(0.3, 30)
	combat.enemy.invincible = true
	combat.god_mode = true
	frames(W, 5)
	local kb = alloc_kb(function() App.hud:update() end, 300)
	T.ok(kb < 1, ("fight view with Aegis + Mirror + Sandstorm allocates < 1 KB per 300 frames (got %.2f KB)"):format(kb))
	no_errors(W, "status visuals")
	leaks(W, "status visuals")
end)

T.case("enemy model: display ID first, model file when it is rejected, portrait last (W0-P3.1)", function()
	local W = Stubs.new()
	W.error_displays[12168] = true -- the Hellhound display is rejected: SetModel(file) next
	local ns = {}
	for _, f in ipairs(toc_files) do W.load(addon_dir .. f, ADDON, ns) end
	W.fire("ADDON_LOADED", ADDON)
	W.ns, W.App = ns, ns.App
	slash(W, "")
	local hud = W.App.hud
	T.ok(hud.model:IsShown() and hud.model.model_file == 123878, "SetDisplayInfo failed: SetModel(Hellhound file) fallback")
	T.ok(not hud.portrait:IsShown(), "no portrait while a fallback model works")
	slash(W, "fight nefarian")
	T.eq(hud.model.display_id, 11380, "the next enemy shows its own display ID first")
	T.ok(hud.model.model_file == nil, "display ID applied, no model file")
	-- both rejected: the portrait icon
	W.error_displays[11380] = true
	W.error_models[123461] = true
	slash(W, "fight harpy")
	slash(W, "fight nefarian")
	T.ok(hud.portrait:IsShown() and not hud.model:IsShown(), "display and file rejected: the portrait icon")
	no_errors(W, "model fallback")
end)

local WANT_DISPLAY = {
	hellhound = 12168, gordok_ogre = 415, basilisk_matriarch = 141, forest_troll = 298, harpy = 148, hakkar = 15295,
	qiraji_scarab = 7469, anubisath_sentinel = 5965, ouro = 15509, nefarian = 11380,
}

T.case("assets: every enemy, ability kind and glyph is covered; /dchess bg routes to /dcbg", function()
	local W = session(nil)
	local A = W.ns.Assets
	local Data = W.ns.EnemyData
	local portraits, n = {}, 0
	for i = 1, #Data.list do
		local def = Data.list[i]
		local e = A.ENEMY[def.display]
		T.ok(e ~= nil, def.id .. ": ENEMY entry")
		T.eq(e.display_id, WANT_DISPLAY[def.id], def.id .. ": display ID (primary)")
		T.ok(type(e.model_id) == "number" and e.model_id > 100000, def.id .. ": model FileDataID (last fallback)")
		T.ok(e.portrait ~= nil and e.portrait ~= "INV_Misc_QuestionMark", def.id .. ": own portrait icon")
		if e.portrait ~= nil and not portraits[e.portrait] then
			portraits[e.portrait] = true
			n = n + 1
		end
	end
	T.eq(n, 10, "ten distinct stand-in portraits")
	local kinds = {}
	for _, ab in pairs(Data.abilities) do kinds[ab.kind] = true end
	for kind in pairs(kinds) do
		local key = A.KIND_ICON[kind]
		T.ok(key ~= nil and A.ICONS[key] ~= nil, "kind " .. kind .. " has a glyph")
	end
	for _, ab in pairs(Data.abilities) do
		T.ok(A.intent_icon(ab) ~= A.icon("unknown"), ab.id .. ": intent icon is not a question mark")
	end
	-- /dchess bg = /dcbg
	slash(W, "")
	local hud = W.App.hud
	local before = hud.bg_name
	slash(W, "bg")
	T.ok(hud.bg_name ~= before, "/dchess bg cycles the background like /dcbg")
	slash(W, "bg cam 0.4 0 0 0")
	T.eq(hud.model.cam_scale, 0.4, "/dchess bg cam re-frames the model")
	no_errors(W, "assets")
end)

T.case("core error is forwarded and stops the driver", function()
	local W = session(nil)
	slash(W, "")
	local sim = W.App.sim
	sim.tick = function() error("boom") end
	frames(W, 3)
	T.eq(#W.errors, 1, "error forwarded once to geterrorhandler")
	T.ok(W.App.crashed and W.App.win.overlay:IsShown(), "driver stopped, overlay shown")
	W.App.win.overlay:Click()
	T.ok(not W.App.crashed and W.App.sim ~= sim, "overlay click starts a new run")
	frames(W, 3)
	T.eq(#W.errors, 1, "no further errors")
end)

T.done()
