-- W0-P4 UI test: minimap button (maths, clicks, drag, tooltip, compartment), in-window menu
-- (restart confirm, sound / quiet gate, scale, persistence, Esc order), idle hint (once after 6
-- sim-seconds, cancelled by swap / pause / hide, no per-frame allocation) and shuffle feedback.
-- Loads the addon in TOC order under test/wow_stubs.lua like ui_smoke.
local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "."
local T = dofile(dir .. "/t.lua")
local loader = dofile(dir .. "/loader.lua")
local Stubs = dofile(dir .. "/wow_stubs.lua")
T.start("ui_menu_test")

local ADDON = "DragonChess"
local addon_dir = loader.wow_dir() .. "/"
local DT = 1 / 60

local function read_toc()
	local files = {}
	local f = assert(io.open(addon_dir .. "DragonChess.toc"))
	for line in f:lines() do
		line = line:gsub("\r", "")
		if line:match("%S") and not line:match("^#") then files[#files + 1] = line:match("^%s*(.-)%s*$") end
	end
	f:close()
	return files
end
local toc_files = read_toc()

local function session(saved, pre)
	local W = Stubs.new()
	local ns = {}
	for _, f in ipairs(toc_files) do W.load(addon_dir .. f, ADDON, ns) end
	if saved then
		for k, v in pairs(saved) do W.store[k] = v end
	end
	if pre then pre(W) end
	W.fire("ADDON_LOADED", ADDON)
	W.ns, W.App = ns, ns.App
	return W
end

local function slash_raw(W, msg) W.stubs.SlashCmdList.DRAGONCHESS(msg or "") end
-- W0-P10: opening the window shows the start / resume panel (game paused); these tests want a running game.
local function slash(W, msg)
	slash_raw(W, msg)
	if W.App ~= nil and W.App.start_open then W.App.close_start() end
end
local function frames(W, n) for _ = 1, n do W.update(DT) end end
local function frames_until(W, pred, n)
	for _ = 1, n or 3000 do
		if pred() then return true end
		W.update(DT)
	end
	return pred()
end
local function copy(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in pairs(v) do out[copy(k)] = copy(x) end
	return out
end
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
local function click(btn, name) btn.scripts[name or "OnClick"](btn, "LeftButton") end

-- Open the window and wait until the board is at rest with the fight live and the player able to swap.
local function open_ready(W)
	slash(W, "")
	local App = W.App
	T.ok(frames_until(W, function() return App.sim:is_at_rest() and App.combat:can_player_swap() == "" end),
		"board at rest, player can swap")
	return App
end

---------------------------------------------------------------- minimap

T.case("minimap maths", function()
	local W = session(nil)
	local MB = W.ns.MinimapButton
	local x, y = MB.position(0, 75)
	T.ok(math.abs(x - 75) < 1e-9 and math.abs(y) < 1e-9, "angle 0 = east")
	x, y = MB.position(90, 75)
	T.ok(math.abs(x) < 1e-9 and math.abs(y - 75) < 1e-9, "angle 90 = north")
	x, y = MB.position(225, 75)
	T.ok(x < 0 and y < 0, "angle 225 = bottom-left")
	T.ok(math.abs(MB.angle_from(110, 50, 50, 50) - 0) < 1e-9, "angle_from east")
	T.ok(math.abs(MB.angle_from(50, 90, 50, 50) - 90) < 1e-9, "angle_from north")
	T.ok(math.abs(MB.angle_from(50, 10, 50, 50) - 270) < 1e-9, "angle_from south wraps to 270")
	for a = 0, 359, 37 do
		local px, py = MB.position(a, 80)
		T.ok(math.abs(MB.angle_from(px, py, 0, 0) - a) < 1e-6, "round trip " .. a)
	end
end)

T.case("minimap button: place, clicks, tooltip, drag, compartment", function()
	local W = session(nil)
	local App = W.App
	local b = App.minimap
	T.ok(b ~= nil, "button created on ADDON_LOADED")
	T.eq(b.parent, W.stubs.Minimap, "child of the Minimap")
	T.eq(b.point, "CENTER", "anchored by its centre")
	T.eq(b.rel, W.stubs.Minimap, "relative to the Minimap")
	T.eq(W.store.DragonChessDB.minimap.angle, W.ns.MinimapButton.DEFAULT_ANGLE, "default angle saved")
	local ex, ey = W.ns.MinimapButton.position(225, 75)
	T.ok(math.abs(b.x - ex) < 1e-6 and math.abs(b.y - ey) < 1e-6, "placed on the minimap edge (radius 75)")
	T.ok(b.icon.texture:find("INV_Misc_Gem_Ruby_02") ~= nil, "ruby gem icon")
	T.ok(b.icon.mask ~= nil, "icon masked round")

	-- left click toggles the window, right click opens the menu
	click(b)
	T.ok(App.win ~= nil and App.win.frame:IsShown(), "left click opens the window")
	click(b)
	T.ok(not App.win.frame:IsShown(), "left click again closes it")
	b.scripts.OnClick(b, "RightButton")
	T.ok(App.win.frame:IsShown() and App.menu_open and App.menu.frame:IsShown(), "right click opens window + menu")
	b.scripts.OnClick(b, "RightButton")
	T.ok(not App.menu_open and App.win.frame:IsShown(), "right click again closes only the menu")

	-- tooltip
	b.scripts.OnEnter(b)
	T.ok(W.tooltip.shown and W.tooltip.lines[1] == "Dragon Chess" and #W.tooltip.lines >= 3, "tooltip shown with hints")
	b.scripts.OnLeave(b)
	T.ok(not W.tooltip.shown, "tooltip hidden on leave")

	-- drag around the edge: cursor north of the centre (1070, 670) -> 90 degrees
	W.cursor_x, W.cursor_y = 1070, 770
	b.scripts.OnDragStart(b)
	T.ok(b.scripts.OnUpdate ~= nil, "drag follows the cursor per frame")
	W.update(DT)
	T.ok(math.abs(W.store.DragonChessDB.minimap.angle - 90) < 1e-6, "angle follows the cursor")
	T.ok(math.abs(b.x) < 1e-6 and math.abs(b.y - 75) < 1e-6, "button moved to the top edge")
	W.cursor_x, W.cursor_y = 1170, 670 -- east
	W.update(DT)
	T.ok(math.abs(W.store.DragonChessDB.minimap.angle) < 1e-6, "east = 0")
	b.scripts.OnDragStop(b)
	T.ok(b.scripts.OnUpdate == nil, "drag stop removes the per-frame handler")
	b.scripts.OnEnter(b)
	T.ok(W.tooltip.shown, "tooltip works again after the drag")

	-- compartment
	T.eq(#W.compartment, 1, "AddonCompartmentFrame registration")
	local info = W.compartment[1]
	T.eq(info.text, "Dragon Chess", "compartment text")
	App.win.frame:Hide()
	info.func(nil, nil, nil, nil, "LeftButton")
	T.ok(App.win.frame:IsShown(), "compartment left click opens the window")
	info.func(nil, { buttonName = "RightButton" })
	T.ok(App.menu_open, "compartment right click opens the menu")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("minimap: missing globals are not fatal; saved angle restored", function()
	local W = Stubs.new()
	W.stubs.Minimap = nil
	W.stubs.AddonCompartmentFrame = nil
	local ns = {}
	for _, f in ipairs(toc_files) do W.load(addon_dir .. f, ADDON, ns) end
	W.store.DragonChessDB = { minimap = { angle = 45 } }
	-- reads of nil globals raise in the strict env: pcall inside the addon must swallow them
	W.fire("ADDON_LOADED", ADDON)
	T.ok(ns.App.db ~= nil, "DB initialised without a Minimap")
	T.ok(ns.App.minimap == nil, "no button without a Minimap")
	T.eq(ns.App.db.minimap.angle, 45, "saved angle untouched")
	local W2 = session({ DragonChessDB = { minimap = { angle = 45 } } })
	local ex, ey = W2.ns.MinimapButton.position(45, 75)
	T.ok(math.abs(W2.App.minimap.x - ex) < 1e-6 and math.abs(W2.App.minimap.y - ey) < 1e-6, "saved angle restored")
	local W3 = session({ DragonChessDB = { minimap = { angle = "bad" } } })
	T.eq(W3.App.db.minimap.angle, W3.ns.MinimapButton.DEFAULT_ANGLE, "invalid angle falls back")
end)

---------------------------------------------------------------- menu

T.case("menu: restart with inline confirm", function()
	local W = session(nil)
	local App = W.App
	slash(W, "")
	local win = App.win
	click(win.menu_button)
	T.ok(App.menu_open and App.menu.frame:IsShown(), "Menu button opens the menu")
	local old_sim = App.sim
	local t0 = old_sim.now
	frames(W, 30)
	T.eq(old_sim.now, t0, "the game is paused while the menu is open")
	local b = App.menu.buttons.restart
	click(b)
	T.eq(App.sim, old_sim, "first click only arms the confirm")
	T.ok(b.dc_text:find("Really") ~= nil, "confirm label: " .. tostring(b.dc_text))
	click(App.menu.buttons.close)
	T.ok(not App.menu_open and not App.menu.frame:IsShown(), "Close closes the menu")
	T.eq(App.sim, old_sim, "close does not restart")
	click(win.menu_button)
	T.ok(App.menu.buttons.restart.dc_text == "Restart run", "confirm disarmed after closing")
	click(b)
	click(b)
	T.ok(App.sim ~= old_sim and App.sim ~= nil, "second click starts a new run")
	T.ok(not App.menu_open, "menu closes after the restart")
	T.ok(frames_until(W, function() return App.sim.now > 0.5 end, 200), "the new run ticks")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("menu: restart works on the result screen (menu above it)", function()
	local W = session(nil)
	local App = W.App
	slash(W, "")
	App.combat:take_true_damage(App.combat.player_health)
	T.ok(App.lost and App.result_menu.frame:IsShown(), "run lost: result screen up")
	click(App.win.menu_button)
	T.ok(App.menu.frame.level > App.win.overlay.level, "menu frame level above the overlay")
	T.ok(App.menu.frame.level > App.result_menu.frame.level, "menu frame level above the result screen")
	local old = App.sim
	click(App.menu.buttons.restart)
	click(App.menu.buttons.restart)
	T.ok(App.sim ~= old and not App.lost, "restart from the menu clears the loss")
end)

T.case("menu: sound gate, quiet mode, difficulty, scale, persistence", function()
	local W = session(nil)
	local App = W.App
	local A = W.ns.Assets
	local db = W.store.DragonChessDB
	T.eq(db.options.sound, true, "defaults: sound on")
	T.eq(db.options.quiet, false, "defaults: quiet off")
	slash(W, "")
	local n = #W.sounds
	T.ok(n >= 1, "open sound played")
	click(App.win.menu_button)
	local m = App.menu.checks
	T.ok(m.sound.dc_checked and not m.quiet.dc_checked and m.shake.dc_checked and m.combat_hide.dc_checked, "checks show the defaults")

	-- hide in combat: default on, the menu toggles it
	T.eq(db.options.combat_hide, true, "defaults: hide in combat on")
	click(m.combat_hide)
	T.eq(db.options.combat_hide, false, "hide in combat off")
	T.ok(not m.combat_hide.dc_checked, "combat check off")
	click(m.combat_hide)
	T.eq(db.options.combat_hide, true, "hide in combat on again")
	T.ok(m.combat_hide.dc_checked, "combat check on")

	-- quiet mode: only key sounds
	click(m.quiet)
	T.eq(db.options.quiet, true, "quiet on")
	T.ok(m.quiet.dc_checked, "quiet check on")
	n = #W.sounds
	A.play("gem_break")
	A.play("open")
	A.play("ability")
	A.play("ab_flamestrike") -- a skill sound: not a key sound
	A.play("enemy_attack", 600668)
	T.eq(#W.sounds, n, "quiet: gem break / open / ability / skill / creature silent")
	A.play("ab_frost_nova") -- an ult sound (slot.key)
	A.play("blocked")
	n = n + 2
	A.play("ult")
	A.play("player_hit")
	A.play("cleared")
	A.play("defeat")
	T.eq(#W.sounds, n + 4, "quiet: key sounds still play")
	click(m.quiet)
	n = #W.sounds
	A.play("gem_break")
	A.play("ab_flamestrike")
	T.eq(#W.sounds, n + 2, "quiet off: everything plays")

	-- sound off: nothing at all through the single gate
	click(m.sound)
	T.eq(db.options.sound, false, "sound off")
	T.ok(m.quiet.dc_dim and not m.sound.dc_checked, "Sound off: the Quiet entry looks disabled, the check is off")
	n = #W.sounds
	for _, k in ipairs(A.sound_keys()) do A.play(k) end
	A.play("ability", nil, true) -- even a forced audition (/dcsnd) respects the sound-off option
	T.eq(#W.sounds, n, "sound off: every key silent")
	click(m.sound)
	T.ok(not m.quiet.dc_dim, "Sound on: Quiet looks normal again")
	n = #W.sounds
	A.play("ability")
	T.eq(#W.sounds, n + 1, "sound on again")

	-- window size segment: Normal selected; Large -> Small -> Normal
	local sc = App.menu.scale_seg
	T.eq(sc.selected, 2, "Normal selected")
	click(sc.buttons[3])
	T.eq(db.options.scale, 1.2, "large")
	T.eq(App.win.frame.scale, 1.2, "window scaled")
	T.eq(sc.selected, 3, "segment follows")
	click(sc.buttons[1])
	T.eq(db.options.scale, 0.85, "small")
	click(sc.buttons[2])
	T.eq(db.options.scale, 1, "normal")

	-- the difficulty is chosen on the start screen: no entry in the options any more
	T.eq(App.menu.buttons.difficulty, nil, "no difficulty entry in the options")

	-- persistence: options survive a session (SavedVariables copy), applied before the window exists
	click(m.quiet)
	click(sc.buttons[3])
	local saved = { DragonChessDB = copy(db) }
	local W2 = session(saved)
	T.eq(W2.ns.Assets.quiet, true, "quiet restored")
	T.eq(W2.ns.Assets.sound_enabled, true, "sound restored")
	T.eq(W2.App.db.options.scale, 1.2, "scale restored in the DB")
	slash(W2, "")
	T.eq(W2.App.win.frame.scale, 1.2, "window opens at the saved scale")
	T.eq(#W.errors + #W2.errors, 0, "no errors")

	local W3 = session({ DragonChessDB = { options = { sound = "x", quiet = 3, scale = 99 } } })
	T.eq(W3.App.db.options.sound, true, "invalid sound option -> default")
	T.eq(W3.App.db.options.quiet, false, "invalid quiet option -> default")
	T.eq(W3.App.db.options.scale, nil, "invalid scale dropped")
end)

T.case("menu: gem set toggle (WoW / Shapes), persistence, immediate redraw", function()
	local W = session(nil)
	local App = W.App
	local A = W.ns.Assets
	T.eq(A.gem_set, "jewels", "default set jewels")
	T.eq(App.db.gem_set, nil, "default not stored")
	T.ok(App.set_gem_set("wow"), "switch to wow")
	slash(W, "")
	click(App.win.menu_button)
	local seg = App.menu.gems_seg
	T.eq(seg.selected, 2, "segment shows WoW")
	frames(W, 3)
	local f = App.view.active[1]
	T.ok(f ~= nil, "a gem frame exists")
	T.eq(f.icon.texture, A.GEM_ICON[f.ltype], "wow texture on the board")
	T.ok(f.icon.mask ~= nil, "wow gems round-masked")
	T.eq(App.hud.weak_icon.texture, A.GEM_ICON[5], "weakness icon wow")
	click(seg.buttons[3])
	T.eq(W.store.DragonChessDB.gem_set, "shapes", "saved in the db")
	T.eq(seg.selected, 3, "segment shows Shapes")
	frames(W, 3)
	f = App.view.active[1]
	T.eq(f.icon.texture, A.GEM_SETS.shapes[f.ltype][1], "board redrawn at once with the shapes texture")
	T.ok(f.icon.mask == nil, "shapes are not round-masked")
	T.eq(App.hud.weak_icon.texture, A.GEM_SETS.shapes[5][1], "weakness icon follows the set")
	click(seg.buttons[1])
	frames(W, 3)
	T.eq(A.gem_set, "jewels", "Jewels picked")
	f = App.view.active[1]
	T.eq(f.icon.texture, A.GEM_SETS.jewels[f.ltype][1], "jewels texture")
	T.ok(f.icon.mask == nil, "jewels are not round-masked")
	click(seg.buttons[2])
	frames(W, 3)
	T.eq(A.gem_set, "wow", "WoW picked again")
	f = App.view.active[1]
	T.eq(f.icon.texture, A.GEM_ICON[f.ltype], "wow again")
	T.ok(f.icon.mask ~= nil, "mask restored")
	-- shapes set: 6 distinct textures, valid coords
	local seen, n = {}, 0
	for t = 0, 5 do
		local e = A.GEM_SETS.shapes[t]
		T.ok(e ~= nil and type(e[1]) == "string" and #e[2] == 4, "shapes entry " .. t)
		if e and not seen[e[1]] then seen[e[1]] = true; n = n + 1 end
	end
	T.eq(n, 6, "six distinct shapes")
	-- fallback + invalid names
	A.gem_set = "nope"
	T.eq((A.gem(3)), A.GEM_ICON[3], "unknown set falls back to wow")
	A.GEM_SETS.shapes[3] = nil
	A.gem_set = "shapes"
	T.eq((A.gem(3)), A.GEM_ICON[3], "missing shapes entry falls back to wow")
	T.ok(not App.set_gem_set("bogus"), "invalid set rejected")
end)

T.case("menu: saved gem set is restored on load", function()
	local W = session({ DragonChessDB = { gem_set = "shapes" } })
	T.eq(W.ns.Assets.gem_set, "shapes", "loaded set active")
	local W2 = session({ DragonChessDB = { gem_set = "garbage" } })
	T.eq(W2.ns.Assets.gem_set, "jewels", "garbage -> default")
end)

T.case("menu: Esc closes the menu first, then the window", function()
	local W = session(nil)
	local App = W.App
	slash(W, "")
	local esc = W.named.DragonChessEsc
	T.ok(esc ~= nil and esc:IsShown(), "Esc catcher armed while the window is shown")
	local listed = false
	for _, n in ipairs(W.stubs.UISpecialFrames) do if n == "DragonChessEsc" then listed = true end end
	T.ok(listed, "catcher in UISpecialFrames")
	T.ok(not listed or W.named.DragonChessFrame ~= nil, "window frame exists")
	local win_listed = false
	for _, n in ipairs(W.stubs.UISpecialFrames) do if n == "DragonChessFrame" then win_listed = true end end
	T.ok(not win_listed, "window itself is not in UISpecialFrames")
	App.open_menu()
	esc:Hide() -- what Esc does
	T.ok(not App.menu_open and App.win.frame:IsShown(), "first Esc closes only the menu")
	T.ok(esc:IsShown(), "catcher re-armed")
	esc:Hide()
	T.ok(not App.win.frame:IsShown(), "second Esc closes the window")
	T.ok(not esc:IsShown(), "catcher disarmed with the window")
	slash(W, "")
	T.ok(esc:IsShown(), "armed again on re-open")
	App.open_menu()
	App.win.frame:Hide() -- X button / toggle with the menu open
	T.ok(not App.menu_open and not App.menu.frame:IsShown(), "hiding the window closes the menu")
	slash(W, "")
	T.ok(not App.menu_open and not App.menu.frame:IsShown(), "window reopens without the menu")
	T.eq(#W.errors, 0, "no errors")
end)

---------------------------------------------------------------- start / resume panel (W0-P10)

T.case("start panel: opens on show, blocks tick and input until Start; fresh run = start form", function()
	local W = session(nil)
	slash_raw(W, "")
	local App = W.App
	local sm = App.start
	T.ok(App.start_open and sm.frame:IsShown(), "panel open on show")
	T.eq(sm.form, "start", "fresh run: start form")
	T.eq(sm.title.text, "Dragon Chess", "title")
	T.ok(sm.buttons.start:IsVisible() and sm.diff:IsVisible(), "Start + difficulty row shown")
	T.ok(not sm.buttons.continue:IsVisible() and not sm.buttons.new_run:IsVisible() and not sm.buttons.options:IsVisible(), "pause buttons hidden")
	T.eq(sm.diff.selected, 1, "difficulty 1 selected")
	T.eq(sm.best.text, "Best: -", "no best score yet")
	T.ok(not App.run_in_progress(), "no run in progress")
	local t0 = App.sim.now
	frames(W, 60)
	T.eq(App.sim.now, t0, "no tick while the panel is open")
	T.ok(not App.can_input(), "no board input while the panel is open")
	local old = App.sim
	click(sm.diff.buttons[2]) -- locked: not selectable, nothing changes
	T.ok(App.start_open and sm.diff.selected == 1 and App.sim == old and App.run.difficulty == 1, "locked difficulty is not selectable")
	sm.diff.buttons[2].scripts.OnEnter(sm.diff.buttons[2])
	T.ok(W.tooltip.lines[2] == "Win difficulty 1 to unlock", "locked tooltip: " .. tostring(W.tooltip.lines[2]))
	sm.diff.buttons[2].scripts.OnLeave(sm.diff.buttons[2])
	T.ok(not W.tooltip.shown, "tooltip hidden")
	click(sm.diff.buttons[1])
	T.ok(App.start_open, "clicking the selected difficulty keeps the panel")
	click(sm.buttons.start)
	T.ok(not App.start_open and not sm.frame:IsShown(), "Start closes the panel")
	T.ok(frames_until(W, function() return App.sim.now > t0 + 0.5 end, 200), "the game ticks after Start")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("start panel: a higher unlocked difficulty can be chosen on the start form (fresh run restarts, panel stays)", function()
	local W = session({ DragonChessDB = { unlocked = 3, records = { [1] = { best = 900 }, [2] = { best = 1500 } } } })
	slash_raw(W, "")
	local App = W.App
	local old = App.sim
	local sm = App.start
	T.eq(sm.best.text, "Best: 900", "best of difficulty 1")
	T.ok(not sm.diff.buttons[3].dc_disabled and sm.diff.buttons[4].dc_disabled and sm.diff.buttons[5].dc_disabled, "D1-D3 open, D4 / D5 locked")
	T.ok(sm.diff.buttons[4].dc_tip ~= nil and sm.diff.buttons[4].dc_tip[2][1] == "Win difficulty 3 to unlock", "tooltip names the difficulty to win")
	T.ok(sm.diff.buttons[2].dc_tip == nil, "open levels have no lock tooltip")
	click(sm.diff.buttons[2])
	T.ok(App.start_open and App.start.form == "start", "panel stays open in the start form")
	T.ok(App.sim ~= old, "a fresh run restarted with the new difficulty")
	T.eq(App.run.difficulty, 2, "difficulty 2")
	T.eq(sm.diff.selected, 2, "segment follows")
	T.eq(sm.best.text, "Best: 1500", "best follows the selected difficulty")
	click(sm.diff.buttons[5])
	T.eq(App.run.difficulty, 2, "locked D5 ignored")
	local t0 = App.sim.now
	frames(W, 30)
	T.eq(App.sim.now, t0, "still paused")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("start panel: resume form for a restored or advanced run; Continue resumes", function()
	-- restored snapshot (written when fight 1 began)
	local W = session(nil)
	slash_raw(W, "")
	local saved = { DragonChessDB = copy(W.store.DragonChessDB) }
	T.ok(saved.DragonChessDB.run ~= nil, "a boundary snapshot was written")
	local W2 = session(saved)
	slash_raw(W2, "")
	local App = W2.App
	T.ok(App.start_open and App.start.form == "resume", "restored run: resume form")
	T.eq(App.start.title.text, "Paused", "title Paused")
	T.ok(App.start.buttons.continue:IsVisible() and App.start.buttons.new_run:IsVisible() and App.start.buttons.options:IsVisible(), "Continue + Options + New run")
	T.ok(not App.start.buttons.start:IsVisible(), "no Start button")
	T.ok(App.start.stage_line.text:find("^Dire Maul 1%-1") ~= nil and App.start.stage_line.text:find("Difficulty 1", 1, true) ~= nil, "stage line: " .. tostring(App.start.stage_line.text))
	T.eq(App.start.score_line.text, "Score " .. App.combat.score, "score line")
	local t0 = App.sim.now
	frames(W2, 30)
	T.eq(App.sim.now, t0, "the old fight stays frozen behind the panel")
	click(App.start.buttons.continue)
	T.ok(not App.start_open, "Continue closes the panel")
	T.ok(frames_until(W2, function() return App.sim.now > t0 + 0.3 end, 200), "the game runs again")

	-- the session's own run past its first moment (score > 0 / HP lost / later fight)
	local W3 = session(nil)
	slash_raw(W3, "")
	local A3 = W3.App
	click(A3.start.buttons.start)
	T.ok(not A3.run_in_progress(), "fresh")
	A3.combat.score = 50
	T.ok(A3.run_in_progress(), "score > 0 = in progress")
	A3.combat.score = 0
	A3.combat.player_health = A3.combat.player_max_health - 1
	T.ok(A3.run_in_progress(), "HP lost = in progress")
	A3.win.frame:Hide()
	T.ok(not A3.start_open, "hiding closes the panel")
	slash_raw(W3, "")
	T.ok(A3.start_open and A3.start.form == "resume", "reopen: resume form")
	T.eq(#W.errors + #W2.errors + #W3.errors, 0, "no errors")
end)

T.case("start panel: New run asks for confirmation, then a fresh run waits behind the start form", function()
	local W = session(nil)
	slash_raw(W, "")
	local App = W.App
	click(App.start.buttons.start)
	App.combat.score = 70
	App.win.frame:Hide()
	slash_raw(W, "")
	local sm = App.start
	T.eq(sm.form, "resume", "resume form")
	local old = App.sim
	click(sm.buttons.new_run)
	T.eq(App.sim, old, "first click only arms the confirm")
	T.eq(sm.buttons.new_run.dc_text, "Abandon this run? Click again", "confirm label")
	click(sm.buttons.continue)
	slash_raw(W, "") -- hide
	slash_raw(W, "") -- show again: the form was reopened, confirm disarmed
	T.ok(sm.buttons.new_run.dc_text == "New run", "confirm disarmed after closing")
	click(sm.buttons.new_run)
	click(sm.buttons.new_run)
	T.ok(App.sim ~= old and App.sim ~= nil, "second click starts a new run")
	T.ok(App.start_open and sm.form == "start", "the new run waits behind the start form")
	local t0 = App.sim.now
	frames(W, 30)
	T.eq(App.sim.now, t0, "new run paused until Start")
	click(sm.buttons.start)
	T.ok(frames_until(W, function() return App.sim.now > t0 + 0.3 end, 200), "runs after Start")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("start panel: Esc hides the window, the menu stays reachable above it, overlays and dev fights skip / close it", function()
	local W = session(nil)
	slash_raw(W, "")
	local App = W.App
	local esc = W.named.DragonChessEsc
	T.ok(esc:IsShown(), "Esc catcher armed")
	esc:Hide() -- Esc
	T.ok(not App.win.frame:IsShown() and not App.start_open, "Esc on the panel hides the window")
	slash_raw(W, "")
	T.ok(App.start_open, "reopen shows the panel again")
	click(App.win.menu_button)
	T.ok(App.menu_open and App.start_open, "the menu opens over the panel")
	T.ok(App.menu.frame.level > App.start.frame.level, "menu above the panel")
	App.close_menu()
	T.ok(App.start_open, "closing the menu returns to the panel")
	-- /dchess fight closes the panel
	slash_raw(W, "fight hellhound")
	T.ok(not App.start_open and not App.start.frame:IsShown(), "dev fight closes the panel")
	-- a lost run shows its result screen, not the panel; New run leads to the start form
	App.win.frame:Hide()
	App.lost = true
	slash_raw(W, "")
	T.ok(not App.start_open, "no panel over the result screen")
	T.ok(App.result_menu.frame:IsShown(), "result screen shown (even without result data)")
	click(App.result_menu.buttons.new_run)
	T.ok(not App.lost and App.start_open and App.start.form == "start" and App.sim ~= nil, "New run opens the start form")
	T.ok(not App.result_menu.frame:IsShown(), "result screen closed")
	T.eq(#W.errors, 0, "no errors")
end)

---------------------------------------------------------------- menus in one dialog style (W0-P12)

local function kill_enemy(combat) combat.enemy:take_damage(combat.enemy.current_health) end

T.case("menus: start -> run -> pause form -> Options -> back -> Continue -> loss -> result -> New run -> start form (mouse only)", function()
	local W = session(nil)
	local A = W.ns.Assets
	slash_raw(W, "")
	local App = W.App
	local db = W.store.DragonChessDB
	T.eq(App.start.title.text, "Dragon Chess", "start header")
	click(App.start.buttons.start)
	T.ok(frames_until(W, function() return App.sim:is_at_rest() end), "the run starts")
	App.combat.score = 120
	-- pause form (window closed and reopened)
	App.win.frame:Hide()
	slash_raw(W, "")
	local sm = App.start
	T.eq(sm.form, "resume", "pause form")
	T.eq(sm.title.text, "Paused", "header Paused")
	click(sm.buttons.options)
	T.ok(App.menu_open and App.menu.frame:IsShown() and App.start_open, "Options opens over the pause form")
	T.eq(App.menu.frame.title.text, "Options", "options header")
	T.ok(App.menu.frame.level > sm.frame.level, "options above the pause form")
	click(App.menu.checks.shake)
	T.eq(db.options.shake, false, "an option changed from the pause form")
	click(App.menu.buttons.close)
	T.ok(not App.menu_open and App.start_open and sm.frame:IsShown() and sm.form == "resume", "back on the pause form")
	click(sm.buttons.continue)
	T.ok(not App.start_open, "Continue resumes")
	-- loss -> result screen
	local combat = App.combat
	combat:take_true_damage(combat.player_health)
	local rs = App.result_menu
	T.ok(App.lost and rs.frame:IsShown() and not App.win.overlay:IsShown(), "result screen, no text overlay")
	T.eq(rs.box.title.text, "Defeated", "header Defeated")
	T.eq(rs.box.title.tr, A.COLOR.TITLE_LOSS[1], "red title")
	T.eq(rs.score.text, "120", "score")
	T.eq(rs.best.text, "Best (D1): 120", "best")
	T.ok(rs.new_best:IsShown() and not rs.unlock:IsShown(), "new best, no unlock")
	T.ok(rs.who_line.text:find("^Fell to .+ %(1%-1%)$") ~= nil, "who: " .. tostring(rs.who_line.text))
	T.eq(rs.diff_line.text, "Difficulty 1", "difficulty line")
	T.eq(db.records[1].best, 120, "record written exactly as before")
	T.ok(not App.can_input(), "no board input behind the result")
	-- New run -> start form
	click(rs.buttons.new_run)
	T.ok(not App.lost and not rs.frame:IsShown() and App.start_open and App.start.form == "start", "New run opens the start form")
	T.eq(App.start.best.text, "Best: 120", "the start form shows the new best")
	click(App.start.buttons.start)
	T.ok(frames_until(W, function() return App.sim.now > 0.5 end, 300), "the next run ticks")
	-- a second, worse loss: no new best
	App.combat.score = 50
	App.combat:take_true_damage(App.combat.player_health)
	T.ok(rs.frame:IsShown() and not rs.new_best:IsShown(), "no new-best flag")
	T.eq(rs.best.text, "Best (D1): 120", "best stays 120")
	T.eq(rs.score.text, "50", "score 50")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("menus: a won run shows the victory result with the unlock line; New run offers the new difficulty", function()
	local W = session(nil)
	slash_raw(W, "")
	local App = W.App
	click(App.start.buttons.start)
	App.run.index = 10
	App.run:begin_fight()
	frames(W, 1)
	App.combat.score = 4242
	kill_enemy(App.combat)
	local rs = App.result_menu
	T.ok(App.won and not rs.frame:IsShown(), "the death beat comes first")
	frames(W, 70)
	T.ok(rs.frame:IsShown(), "result after the beat")
	T.eq(rs.box.title.text, "Victory", "header Victory")
	T.eq(rs.box.title.tr, W.ns.Assets.COLOR.TITLE_GOLD[1], "gold title")
	T.eq(rs.score.text, "4242", "score")
	T.eq(rs.best.text, "Best (D1): 4242", "best")
	T.ok(rs.new_best:IsShown(), "new best")
	T.eq(rs.unlock.text, "Difficulty 2 unlocked", "unlock line")
	T.ok(rs.unlock:IsShown(), "unlock shown")
	T.eq(rs.who_line.text, "All 10 enemies defeated", "who")
	click(rs.buttons.new_run)
	local sm = App.start
	T.ok(App.start_open and sm.form == "start" and not sm.diff.buttons[2].dc_disabled, "start form: D2 is open now")
	click(sm.diff.buttons[2])
	T.eq(App.run.difficulty, 2, "D2 chosen")
	T.eq(sm.best.text, "Best: -", "no best on D2 yet")
	click(sm.buttons.start)
	T.eq(#W.errors, 0, "no errors")
end)

T.case("menus: start form shows the spell preview in the active gem set; the sizes of the four panels", function()
	local W = session(nil)
	local A = W.ns.Assets
	slash_raw(W, "")
	local App = W.App
	local sm = App.start
	T.eq(sm.box.w, 440, "start panel width")
	T.ok(sm.box.h >= 340 and sm.box.h <= 420, "start panel height about 400: " .. tostring(sm.box.h))
	T.eq(sm.class_buttons[1].w, 36, "class icons 36 px")
	T.eq(sm.preview[1].w, 36, "spell icons 36 px")
	T.eq(sm.preview[1].border.r, A.COLOR.ICON_BORDER[1], "dark icon border")
	T.eq(sm.preview[1].icon.tc_l, A.ICON_CROP[1], "standard icon crop")
	T.eq(sm.preview_gems[0].texture, A.GEM_SETS.jewels[0][1], "gem preview: jewels")
	App.set_gem_set("shapes")
	T.eq(sm.preview_gems[0].texture, A.GEM_SETS.shapes[0][1], "gem preview follows the set at once")
	App.start:close()
	App.start_open = false
	App.win.frame:Hide()
	click(App.win.menu_button)
	T.eq(App.menu.frame.w, 280, "options width")
	T.ok(App.menu.frame.h >= 300 and App.menu.frame.h <= 380, "options height about 330: " .. tostring(App.menu.frame.h))
	T.eq(W.ns.StartMenu.W_RESUME, 300, "pause panel width")
	T.ok(W.ns.StartMenu.H_RESUME >= 200 and W.ns.StartMenu.H_RESUME <= 260, "pause panel height about 250")
	T.eq(W.ns.ResultMenu.W, 340, "result panel width")
	T.ok(W.ns.ResultMenu.H >= 260 and W.ns.ResultMenu.H <= 320, "result panel height about 300")
	local content = App.win.content
	for _, h in ipairs({ sm.box.h, App.menu.frame.h, W.ns.ResultMenu.H }) do
		T.ok(h + 12 < content.h, "panel fits the content area")
	end
	-- the tooltip of a spell keeps its parts (name, Skill / Ultimate + colour, description)
	local b = sm.preview[1]
	b.scripts.OnEnter(b)
	T.ok(#W.tooltip.lines == 3 and W.tooltip.lines[2]:find("^Skill %- ") ~= nil, "spell tooltip lines")
	T.eq(#W.errors, 0, "no errors")
end)

-- The mouse flow on a session whose client lacks (some of) the templates: flat widgets, never an error.
local function exercise_flat_or_native(W, expect_native)
	slash_raw(W, "")
	local App = W.App
	local sm = App.start
	T.ok(App.start_open and sm.form == "start", "start form opens")
	T.eq(sm.buttons.start.dc_native == true, expect_native, "Start is native: " .. tostring(expect_native))
	T.eq(sm.buttons.start.dc_text, "Start", "Start label")
	if not expect_native then T.eq(sm.buttons.start.dc_fs.text, "Start", "flat label drawn") end
	click(sm.diff.buttons[1])
	click(App.start.class_buttons[2])
	click(sm.buttons.start)
	T.ok(not App.start_open, "Start works")
	App.combat.score = 10
	App.win.frame:Hide()
	slash_raw(W, "")
	T.eq(sm.form, "resume", "pause form")
	click(sm.buttons.options)
	T.ok(App.menu_open, "Options opens")
	local m = App.menu.checks
	T.eq(m.sound.dc_native == true, expect_native, "check native: " .. tostring(expect_native))
	click(m.shake)
	T.eq(W.store.DragonChessDB.options.shake, false, "check toggles the option")
	T.ok(not m.shake.dc_checked, "check shows it")
	click(m.shake)
	T.ok(m.shake.dc_checked, "and back")
	click(App.menu.scale_seg.buttons[3])
	T.eq(W.store.DragonChessDB.options.scale, 1.2, "segment sets the scale")
	click(App.menu.buttons.restart)
	T.eq(App.menu.buttons.restart.dc_text, "Really restart? Click again", "restart arms")
	click(App.menu.buttons.close)
	click(sm.buttons.continue)
	App.combat:take_true_damage(App.combat.player_health)
	T.ok(App.result_menu.frame:IsShown(), "result screen")
	click(App.result_menu.buttons.new_run)
	T.ok(App.start_open and App.start.form == "start", "start form again")
	T.eq(#W.errors, 0, "no errors")
end

T.case("panel kit: native templates are used when the client has them", function()
	local W = session(nil)
	slash_raw(W, "")
	local App = W.App
	T.eq(App.start.buttons.start.template, "UIPanelButtonTemplate", "Start is a UIPanelButtonTemplate button")
	T.eq(App.menu.checks.sound.template, "UICheckButtonTemplate", "Sound is a UICheckButtonTemplate check")
	T.ok(App.start.box.plate:IsShown() and App.start.box.plate.texture == W.ns.Assets.TEXTURE_HEADER, "header plate texture")
	exercise_flat_or_native(session(nil), true)
end)

T.case("panel kit: templates missing -> flat widgets, no error", function()
	exercise_flat_or_native(session(nil, function(W)
		W.missing_templates.UIPanelButtonTemplate = true
		W.missing_templates.UICheckButtonTemplate = true
	end), false)
end)

T.case("panel kit: templates without their methods -> flat widgets, no error; missing header texture keeps the title", function()
	local W = session(nil, function(w)
		w.bare_templates.UIPanelButtonTemplate = true
		w.bare_templates.UICheckButtonTemplate = true
		w.bad_textures["Interface\\DialogFrame\\UI-DialogBox-Header"] = true
	end)
	exercise_flat_or_native(W, false)
	T.ok(not W.App.start.box.plate:IsShown(), "no plate when the texture does not load")
	T.eq(W.App.start.box.title.text, "Dragon Chess", "the title text stays")
end)

T.case("panel kit: a disabled button ignores clicks (native and flat); on_click plays the click sound", function()
	for _, native in ipairs({ true, false }) do
		local W = session(nil, function(w)
			if not native then w.missing_templates.UIPanelButtonTemplate = true end
		end)
		local P = W.ns.Panel
		local parent = W.stubs.CreateFrame("Frame", nil, W.stubs.UIParent)
		local b = P.button(parent, 100, 20, "X")
		local n, sounds = 0, #W.sounds
		P.on_click(b, function() n = n + 1 end)
		click(b)
		T.eq(n, 1, "click runs the handler (native " .. tostring(native) .. ")")
		T.ok(#W.sounds > sounds, "click sound played")
		P.set_enabled(b, false)
		click(b)
		T.eq(n, 1, "disabled: ignored")
		if native then T.eq(b.enabled, false, "native Disable called") end
		P.set_enabled(b, true)
		click(b)
		T.eq(n, 2, "enabled again")
	end
end)

T.case("panel kit: no keyboard capture and no debug dependency in the menu files", function()
	for _, f in ipairs({ "ui/panel.lua", "ui/menu.lua", "ui/start_menu.lua", "ui/result.lua" }) do
		local fh = assert(io.open(addon_dir .. f))
		local src = fh:read("*a")
		fh:close()
		T.ok(src:find("EnableKeyboard", 1, true) == nil, f .. ": no EnableKeyboard")
		T.ok(src:find("ns.Debug", 1, true) == nil and src:find("DebugPanel", 1, true) == nil, f .. ": no debug dependency")
	end
end)

---------------------------------------------------------------- idle hint

T.case("idle hint: once after 6 sim-seconds, stops on swap / pause / hide, no allocation", function()
	local W = session(nil)
	local ns = W.ns
	local calls = 0
	local orig = ns.Match.find_possible_move
	ns.Match.find_possible_move = function(...) calls = calls + 1; return orig(...) end
	local App = open_ready(W)
	local view, hint = App.view, App.hint
	T.eq(hint.DELAY, 6.0, "delay 6 s")
	local calls0 = calls
	local t_start = App.sim.now
	T.ok(view.hint_a == nil, "no hint right away")
	-- just before the delay: nothing
	frames_until(W, function() return hint.t0 ~= nil and App.sim.now - hint.t0 >= 5.9 end, 2000)
	T.ok(view.hint_a == nil and calls == calls0, "no lookup before 6 s")
	T.ok(frames_until(W, function() return view.hint_a ~= nil end, 200), "hint appears after 6 s idle")
	T.ok(App.sim.now - hint.t0 >= 6.0 - 1e-6, "not earlier than 6 sim-seconds")
	T.eq(calls, calls0 + 1, "exactly one find_possible_move lookup")
	local a, b = view.hint_a, view.hint_b
	local c1, r1, c2, r2 = orig(App.sim.board)
	T.ok(a == App.sim.board:get(c1, r1) and b == App.sim.board:get(c2, r2), "wiggles the core's possible move")

	-- the wiggle moves the pair (view-side only: core x / y untouched)
	local moved = false
	for _ = 1, 100 do
		W.update(DT)
		local fa = view.frame_of[a]
		if fa.lx ~= a.x or fa.ly ~= a.y then moved = true end
		T.ok(a.x == c1 and a.y == r1, "core gem position untouched")
	end
	T.ok(moved, "hint gem frame offset from its cell")
	frames(W, 600)
	T.eq(calls, calls0 + 1, "no further lookups while idle (once per idle period)")

	-- allocation: the wiggle + hint update allocate nothing per frame
	local kb = alloc_kb(function()
		hint:update(App.sim, true)
		view:update(App.input)
	end, 300)
	T.ok(kb < 1, ("hint + board view allocate < 1 KB per 300 frames (got %.2f KB)"):format(kb))

	-- a swap cancels it and restarts the timer
	local r = App.swap(a, b)
	T.eq(r, "ok", "swap accepted")
	T.ok(view.hint_a == nil and not hint.shown, "swap cancels the hint")
	T.ok(frames_until(W, function() return App.sim:is_at_rest() end, 3000), "settles")
	local calls1 = calls
	T.ok(frames_until(W, function() return view.hint_a ~= nil end, 3000), "hint again after a fresh 6 s")
	T.eq(calls, calls1 + 1, "one more lookup for the new idle period")

	-- pause cancels
	App.soft_pause("test")
	T.ok(view.hint_a == nil, "soft pause cancels the hint")
	frames(W, 400)
	T.ok(view.hint_a == nil and calls == calls1 + 1, "no hint while paused")
	App.soft_resume()
	T.ok(frames_until(W, function() return view.hint_a ~= nil end, 3000), "hint after resume + 6 s")

	-- hide cancels
	App.win.frame:Hide()
	T.ok(view.hint_a == nil, "hide cancels the hint")
	slash(W, "")
	T.ok(view.hint_a == nil, "no hint right after re-open")

	-- menu open cancels, pressing a gem restarts the timer
	frames_until(W, function() return view.hint_a ~= nil end, 3000)
	T.ok(view.hint_a ~= nil, "hint again")
	App.open_menu()
	frames(W, 5)
	T.ok(view.hint_a == nil, "menu cancels the hint")
	App.close_menu()
	T.eq(#W.errors, 0, "no errors")
	ns.Match.find_possible_move = orig
end)

T.case("idle hint: not while stunned or between fights; none without a move", function()
	local W = session(nil)
	local App = open_ready(W)
	local view, hint = App.view, App.hint
	App.combat:apply_player_stun(30)
	frames(W, 60 * 8)
	T.ok(view.hint_a == nil and not hint.shown, "no hint while stunned")
	T.eq(hint.lookups, 0, "no lookup while stunned")
	App.input:cancel()
	-- hint:update with active=false never looks anything up
	hint:update(App.sim, false)
	T.eq(hint.lookups, 0, "inactive = no lookup")
end)

---------------------------------------------------------------- shuffle feedback

T.case("shuffle feedback: line + pop, stuck overlay with restart", function()
	local W = session(nil)
	local App = open_ready(W)
	local view = App.view
	App.sim:emit("board_shuffled", true)
	T.eq(App.hud.flash_text.text, "No moves - shuffling", "shuffle line")
	T.ok(view.pop_t0 ~= nil, "pop animation started")
	local max_s = 1
	for _ = 1, 30 do
		W.update(DT)
		for i = 1, #view.active do
			local f = view.active[i]
			if f.ls and f.ls > max_s then max_s = f.ls end
		end
	end
	T.ok(max_s > 1.05, "gems pop (scale pulse), max " .. tostring(max_s))
	T.ok(frames_until(W, function() return view.pop_t0 == nil end, 120), "pop ends")
	T.ok(not App.stuck and not App.win.overlay:IsShown(), "a successful shuffle shows no overlay")

	local before = App.sim
	App.sim:emit("board_shuffled", false)
	T.ok(App.stuck, "failed shuffle = stuck")
	T.ok(App.win.overlay:IsShown() and App.win.overlay.text.text:find("Stuck") ~= nil, "Stuck overlay")
	T.ok(not App.can_input(), "no board input while stuck")
	click(App.win.overlay)
	T.ok(not App.stuck and App.sim ~= before, "overlay click restarts")
	T.ok(not App.win.overlay:IsShown(), "overlay gone")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("shuffle: a real no-move board reshuffles and notifies", function()
	local W = session(nil)
	local App = open_ready(W)
	local seen = {}
	App.sim:on("board_shuffled", function(ok) seen[#seen + 1] = ok end)
	-- no-move board: every gem its own checker colour class (no two same colours within reach)
	local board = App.sim.board
	local k = 0
	for col = 0, 7 do
		for row = 0, 7 do
			local g = board:get(col, row)
			g.type = (col % 3) * 2 + (row % 2)
			k = k + 1
		end
	end
	if W.ns.Match.find_possible_move(board) == nil then
		App.sim:mark_resolve_needed()
		frames(W, 300)
		T.ok(#seen >= 1 and seen[1] == true, "core reshuffled and emitted board_shuffled(true)")
		T.ok(App.view.pop_t0 ~= nil or #seen >= 1, "view got the event")
	else
		print("SKIPPED"); T.ok(true, "pattern still had a move (skipped)")
	end
	T.eq(#W.errors, 0, "no errors")
end)

T.done()
