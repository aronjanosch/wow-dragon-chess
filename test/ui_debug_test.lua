-- W0-D1 / W0-P3.1 test: the debug panel (ui/debug.lua) and the fixed `/dchess fight <id>` (ui/main.lua):
-- the dev fight in every awkward state (never opened, hidden, soft-paused, menu open, lost run, error,
-- mid-fight), always with chat feedback; panel open / close / enable; every button calls the right core
-- API on the real game; dev actions never record or save; effects obey pause; sound channels; tuning
-- writes the Assets table and prints the copy-paste line; allocation budget. Loads the addon in TOC order
-- under test/wow_stubs.lua like ui_smoke.
local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "."
local T = dofile(dir .. "/t.lua")
local loader = dofile(dir .. "/loader.lua")
local Stubs = dofile(dir .. "/wow_stubs.lua")
T.start("ui_debug_test")

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

local function session(saved)
	local W = Stubs.new()
	local ns = {}
	for _, f in ipairs(toc_files) do W.load(addon_dir .. f, ADDON, ns) end
	if saved then
		for k, v in pairs(saved) do W.store[k] = v end
	end
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
local function open_ready(W)
	slash(W, "")
	local App = W.App
	T.ok(frames_until(W, function() return App.sim:is_at_rest() and App.combat:can_player_swap() == "" end), "board at rest")
	return App
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

-- Chat lines printed since index n, joined.
local function chat_since(W, n)
	local out = {}
	for i = n + 1, #W.printed do out[#out + 1] = W.printed[i] end
	return table.concat(out, "\n")
end

-- A button of a page with exactly this label (the k-th match).
local function find(page, label, k)
	k = k or 1
	for _, ch in ipairs(page.children) do
		if ch.ftype == "Button" and ch.text ~= nil and ch.text.text == label then
			k = k - 1
			if k == 0 then return ch end
		end
	end
	return nil
end
local function click(page, label, k)
	local b = find(page, label, k)
	T.ok(b ~= nil, "button '" .. label .. "' exists")
	if b then b:Click() end
	return b
end

local function open_panel(W)
	slash(W, "debug")
	local p = W.App.debug_panel
	return p
end

---------------------------------------------------------------- /dchess fight

T.case("/dchess fight: window never opened -> opens, starts the enemy, says so", function()
	local W = session()
	local App = W.App
	T.ok(App.win == nil and App.sim == nil, "nothing open yet")
	local n = #W.printed
	slash(W, "fight nefarian")
	T.ok(App.win ~= nil and App.win.frame:IsShown(), "the window was opened")
	T.eq(App.combat.enemy.def.id, "nefarian", "nefarian is the live enemy")
	T.ok(chat_since(W, n):find("fight: nefarian", 1, true) ~= nil, "feedback printed: " .. chat_since(W, n))
	frames(W, 30)
	T.eq(App.hud.name_text.text, "NEFARIAN", "the HUD shows it")
	T.eq(App.hud.stage_text.text, "DEV", "dev label")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("/dchess fight: hidden window, soft pause, open menu, lost run, mid-fight, unknown id", function()
	local W = session()
	local App = open_ready(W)
	-- hidden window
	App.win.frame:Hide()
	local n = #W.printed
	slash(W, "fight hakkar")
	T.ok(App.win.frame:IsShown(), "hidden window is shown again")
	T.eq(App.combat.enemy.def.id, "hakkar", "hakkar from a hidden window")
	T.ok(chat_since(W, n):find("fight: hakkar", 1, true) ~= nil, "feedback printed")
	-- soft pause (overlay up)
	App.soft_pause("test")
	T.ok(App.soft and App.win.overlay:IsShown(), "paused")
	slash(W, "fight harpy")
	T.ok(not App.soft and not App.win.overlay:IsShown(), "the pause is lifted so the fight is visible")
	T.eq(App.combat.enemy.def.id, "harpy", "harpy while paused")
	-- menu open
	App.open_menu()
	T.ok(App.menu_open, "menu open")
	slash(W, "fight ouro")
	T.ok(not App.menu_open, "menu closed")
	T.eq(App.combat.enemy.def.id, "ouro", "ouro with the menu open")
	-- mid-fight with damage taken and a wind-up running
	frames(W, 200)
	App.combat:take_true_damage(1500, "hit")
	slash(W, "fight nefarian")
	T.eq(App.combat.enemy.def.id, "nefarian", "replaces a running fight")
	T.eq(App.combat.player_health, 8500, "player HP carried over")
	frames(W, 120)
	T.eq(#W.errors, 0, "no errors")
	-- lost run: a fresh run hosts the dev fight
	App.combat:take_true_damage(99999, "hit")
	T.ok(App.lost, "run lost")
	n = #W.printed
	slash(W, "fight gordok_ogre")
	T.ok(not App.lost and App.combat.player_health == App.combat.player_max_health, "fresh run after a lost one")
	T.eq(App.combat.enemy.def.id, "gordok_ogre", "ogre after a lost run")
	-- unknown id + no id
	n = #W.printed
	slash(W, "fight nobody")
	T.ok(chat_since(W, n):find("unknown enemy 'nobody'", 1, true) ~= nil, "unknown id: reason printed: " .. chat_since(W, n))
	T.eq(App.combat.enemy.def.id, "gordok_ogre", "unchanged")
	n = #W.printed
	slash(W, "fight")
	T.ok(chat_since(W, n):find("hellhound", 1, true) ~= nil and chat_since(W, n):find("nefarian", 1, true) ~= nil, "no id: list printed")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("/dchess fight: an error is printed and forwarded, never swallowed", function()
	local W = session()
	local App = open_ready(W)
	local real = W.ns.Debug.fight
	W.ns.Debug.fight = function() error("boom") end
	local n = #W.printed
	slash(W, "fight nefarian")
	T.ok(chat_since(W, n):find("boom", 1, true) ~= nil, "error text in the chat: " .. chat_since(W, n))
	T.ok(#W.errors >= 1 and W.errors[1]:find("boom", 1, true) ~= nil, "forwarded to the error handler")
	W.ns.Debug.fight = real
	W.errors = {}
	slash(W, "fight nefarian")
	T.eq(App.combat.enemy.def.id, "nefarian", "works again")
end)

T.case("a dev fight is never recorded or saved", function()
	local W = session()
	local App = open_ready(W)
	local db = W.store.DragonChessDB
	local snap = db.run
	slash(W, "fight hellhound")
	frames(W, 30)
	T.ok(App.run.dev, "dev run")
	T.eq(db.run, snap, "the saved run is untouched by the dev fight")
	App.combat:take_true_damage(99999, "hit")
	T.ok(App.lost, "lost")
	T.ok(db.records == nil or db.records[1] == nil, "a lost dev run records nothing")
	T.eq(#W.errors, 0, "no errors")
end)

---------------------------------------------------------------- panel

T.case("panel: /dchess debug enables, toggles, disables; position and tab are saved", function()
	local W = session()
	local App = W.App
	local db = W.store.DragonChessDB
	T.eq(type(db.debug), "table", "db.debug table")
	T.ok(not db.debug.enabled and App.debug_panel == nil, "disabled by default, nothing built")
	local n = #W.printed
	slash(W, "debug")
	local p = App.debug_panel
	T.ok(p ~= nil and p.frame:IsShown() and db.debug.enabled == true, "first use enables and opens")
	T.ok(chat_since(W, n):find("enabled", 1, true) ~= nil, "says so")
	T.ok(App.profile == true, "frame profiling on while shown")
	slash(W, "debug")
	T.ok(not p.frame:IsShown() and App.profile == false, "second use hides, profiling off")
	slash(W, "debug")
	T.ok(p.frame:IsShown(), "third use shows")
	slash(W, "debug off")
	T.ok(not p.frame:IsShown() and db.debug.enabled == false, "off hides and disables")
	slash(W, "debug on")
	T.ok(p.frame:IsShown() and db.debug.enabled == true, "on shows and enables")
	n = #W.printed
	slash(W, "debug bogus")
	T.ok(chat_since(W, n):find("/dchess debug", 1, true) ~= nil, "usage printed")
	-- tab + position
	p.tabs[3]:Click()
	T.eq(db.debug.tab, 3, "tab saved")
	T.ok(p.pages[3]:IsShown() and not p.pages[1]:IsShown(), "only the selected page shows")
	local title
	for _, ch in ipairs(p.frame.children) do
		if ch.scripts.OnDragStop then title = ch end
	end
	T.ok(title ~= nil, "title strip drags the panel")
	p.frame.point, p.frame.rel, p.frame.rpoint, p.frame.x, p.frame.y = "CENTER", W.UIParent, "CENTER", 100, 50
	title.scripts.OnDragStop(title)
	T.ok(db.debug.point == "CENTER" and db.debug.x == 100 and db.debug.y == 50, "position saved")
	-- a new session restores both
	local W2 = session({ DragonChessDB = { debug = { enabled = true, point = "TOP", x = 5, y = 6, tab = 4 } } })
	slash(W2, "debug")
	local p2 = W2.App.debug_panel
	T.ok(p2.frame.point == "TOP" and p2.frame.x == 5, "position restored")
	T.ok(p2.pages[4]:IsShown(), "tab restored")
	T.eq(#W.errors + #W2.errors, 0, "no errors")
end)

T.case("panel: Fights tab calls the core API; dev flag; labels follow the state", function()
	local W = session()
	local App = open_ready(W)
	local p = open_panel(W)
	local page = p.pages[1]
	local db = W.store.DragonChessDB
	local snap = db.run
	click(page, "gordok ogre")
	T.eq(App.combat.enemy.def.id, "gordok_ogre", "enemy button = jump to that fight")
	T.ok(App.run.dev, "dev run")
	click(page, "Kill enemy")
	T.ok(App.combat.fight_over, "kill enemy")
	click(page, "Next fight")
	frames(W, 10)
	T.ok(not App.combat.fight_over and App.combat.enemy.def.id == "gordok_ogre", "next fight starts the ladder's enemy (fight 2)")
	click(page, "Hurt player")
	T.eq(App.combat.player_health, App.combat.player_max_health - 2000, "hurt player")
	click(page, "Heal player")
	T.eq(App.combat.player_health, App.combat.player_max_health, "heal player")
	click(page, "Difficulty +")
	T.eq(App.run.difficulty, 2, "difficulty +")
	click(page, "Difficulty -")
	T.eq(App.run.difficulty, 1, "difficulty -")
	click(page, "God mode: off")
	T.ok(App.combat.god_mode, "god mode on")
	T.ok(find(page, "God mode: on") ~= nil, "the label follows")
	click(page, "God mode: on")
	T.ok(not App.combat.god_mode and find(page, "God mode: off") ~= nil, "god mode off")
	T.eq(db.run, snap, "no dev action touched the saved run")
	T.ok(p.footer.text:find("DEV run", 1, true) ~= nil, "footer says DEV run: " .. tostring(p.footer.text))
	-- restart run: a clean run
	local old = App.run
	click(page, "Restart run")
	T.ok(App.run ~= old and not App.run.dev and App.combat.enemy.def.id == "hellhound", "restart run = a fresh, non-dev run")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("panel: Board tab spawns gems, converts, junk, shuffle", function()
	local W = session()
	local App = open_ready(W)
	local p = open_panel(W)
	local page = p.pages[2]
	p:select(2)
	local sim = App.sim
	local function ability_gems(tier, gem_type)
		local n = 0
		for c = 0, 7 do
			for r = 0, 7 do
				local g = sim.board:get(c, r)
				if g ~= nil and g.tier == tier and g.type == gem_type and g.protected then n = n + 1 end
			end
		end
		return n
	end
	click(page, "Ruby", 1) -- skill row
	T.eq(ability_gems(1, 3), 1, "a Ruby skill gem on the board")
	click(page, "Sapphire", 2) -- ult row
	T.eq(ability_gems(2, 4), 1, "a Sapphire ult gem on the board")
	T.ok(App.run.dev, "dev run")
	local junk_events = 0
	sim:on("junk_spawned", function() junk_events = junk_events + 1 end)
	click(page, "Junk x4")
	frames(W, 300)
	T.eq(junk_events, 1, "junk spawned")
	click(page, "Emerald", 3) -- convert row
	frames(W, 300)
	T.ok(frames_until(W, function() return sim:is_at_rest() end, 2000), "settles after converting")
	local shuffled = 0
	sim:on("board_shuffled", function() shuffled = shuffled + 1 end)
	click(page, "Shuffle board")
	T.eq(shuffled, 1, "board shuffled")
	-- while the window is hidden the actions still work (they take effect on the board)
	App.win.frame:Hide()
	click(page, "Topaz", 1)
	T.ok(ability_gems(1, 5) >= 1, "spawn works with the window hidden")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("panel: Status tab", function()
	local W = session()
	local App = open_ready(W)
	local p = open_panel(W)
	p:select(3)
	local page = p.pages[3]
	local e, c = App.combat.enemy, App.combat
	click(page, "Stun enemy")
	T.ok(e:get_stun_remaining() > 0 and e:get_status_kind() == "stun", "stun enemy")
	click(page, "Freeze enemy")
	T.eq(e:get_status_kind(), "freeze", "freeze enemy")
	click(page, "Aegis (enemy)")
	T.ok(e:is_spell_immune(), "aegis")
	click(page, "Mirror (enemy)")
	T.ok(e:is_mirror_up(), "mirror")
	click(page, "Stun player")
	T.ok(c:status_remaining("stun") > 0, "stun player")
	click(page, "Heal block")
	T.ok(c:status_remaining("heal_block") > 0, "heal block")
	click(page, "Curse")
	T.ok(c:curse_multiplier() < 1, "curse")
	click(page, "Sandstorm")
	T.ok(App.sim:get_gravity_slow_remaining() > 0, "sandstorm")
	frames(W, 5)
	T.ok(App.hud.aegis_icon:IsShown(), "the HUD shows the aegis")
	local n = #W.printed
	click(page, "Print values")
	T.ok(chat_since(W, n):find("Debug.STATUS.stun", 1, true) ~= nil, "values printed in copy-paste form")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("panel: Effects tab obeys pause; Sounds tab plays, moves channels, prints them", function()
	local W = session()
	local App = open_ready(W)
	local A = W.ns.Assets
	local p = open_panel(W)
	-- effects
	p:select(4)
	local page = p.pages[4]
	local hud = App.hud
	T.eq(hud.fx:active_count(), 0, "no effect yet")
	click(page, "flamestrike")
	T.ok(hud.fx:active_count() == 1, "the effect plays")
	click(page, "Stop effects")
	T.eq(hud.fx:active_count(), 0, "stopped")
	App.soft_pause("test")
	local n = #W.printed
	click(page, "frost nova")
	T.eq(hud.fx:active_count(), 0, "paused: no effect")
	T.ok(chat_since(W, n):find("unpause", 1, true) ~= nil, "says why: " .. chat_since(W, n))
	App.soft_resume()
	App.win.frame:Hide()
	n = #W.printed
	click(page, "frost nova")
	T.eq(hud.fx:active_count(), 0, "hidden window: no effect")
	slash(W, "")
	-- sounds
	p:select(5)
	page = p.pages[5]
	local s0 = #W.sounds
	click(page, "gem break")
	T.eq(W.sounds[s0 + 1], 2561, "the slot plays (kit 2561)")
	T.eq(W.sound_channel, "SFX", "on the SFX channel")
	click(page, "player hit")
	T.eq(W.sound_channel, "Ambience", "player hit on Ambience (from the table)")
	click(page, "enemy attack")
	T.eq(W.sounds[#W.sounds], App.combat.enemy.def.attack_sound, "a creature slot plays the current enemy's file")
	-- channel selector: next channel, written into the Assets table, used by the next play
	local ch = p.channel_buttons.gem_break
	T.eq(ch.text.text, "SFX", "channel button label")
	ch:Click()
	T.eq(A.SOUNDS.gem_break.channel, "Ambience", "channel moved")
	T.eq(ch.text.text, "Amb", "label follows")
	click(page, "gem break")
	T.eq(W.sound_channel, "Ambience", "plays on the new channel")
	ch:Click()
	ch:Click()
	ch:Click()
	T.ok(A.SOUNDS.gem_break.channel == nil and A.channel_of("gem_break") == "SFX", "wraps back to the default (field cleared)")
	-- print channels
	n = #W.printed
	click(page, "Print channels")
	local out = chat_since(W, n)
	T.ok(out:find("player_hit", 1, true) ~= nil and out:find("enemy_attack", 1, true) ~= nil and out:find("Ambience", 1, true) ~= nil,
		"channels printed: " .. out)
	-- sound off
	A.sound_enabled = false
	n = #W.sounds
	click(page, "gem break")
	T.eq(#W.sounds, n, "sound off: silent")
	A.sound_enabled = true
	T.eq(#W.errors, 0, "no errors")
end)

T.case("panel: Tuning tab (background, model framing) edits Assets and prints the paste line", function()
	local W = session()
	local App = open_ready(W)
	local A = W.ns.Assets
	local p = open_panel(W)
	p:select(6)
	local page = p.pages[6]
	local hud = App.hud
	-- background
	local first = hud.bg_file
	local n = #W.printed
	T.eq(first, A.BG_LIST[1].id, "stage 1 starts on the list head")
	click(page, "next >")
	click(page, "next >")
	T.ok(hud.bg_file == A.BG_LIST[2].id and hud.bg_file ~= first, "background advanced")
	T.ok(chat_since(W, n):find(tostring(A.BG_LIST[2].id), 1, true) ~= nil, "name + id printed")
	T.ok(p.bg_text.text:find(tostring(hud.bg_file), 1, true) ~= nil, "panel shows name + id")
	click(page, "< prev")
	click(page, "< prev")
	T.eq(hud.bg_index, #A.BG_LIST, "prev wraps to the end of the shortlist")
	n = #W.printed
	click(page, "Print bg")
	T.ok(chat_since(W, n):find("STAGE_BG_FILE[1] = " .. A.BG_LIST[#A.BG_LIST].id, 1, true) ~= nil, "bg line printed: " .. chat_since(W, n))
	-- model framing
	local e = A.ENEMY.hellhound
	T.ok(e.cam_scale == nil and e.pos == nil, "hellhound starts on the defaults")
	n = #W.printed
	local plus = {}
	for _, ch in ipairs(page.children) do
		if ch.ftype == "Button" and ch.text.text == "+" then plus[#plus + 1] = ch end
	end
	T.eq(#plus, 5, "five steppers (x y z rot scale; no camera row)")
	plus[1]:Click() -- x +0.1
	T.ok(e.pos ~= nil and math.abs(e.pos[1] - 0.1) < 1e-9, "x written into an own pos table")
	T.ok(math.abs(hud.model.pos[1] - 0.1) < 1e-9, "the model is re-framed live")
	T.ok(chat_since(W, n):find("pos = {", 1, true) ~= nil and chat_since(W, n):find("hellhound = {", 1, true) ~= nil,
		"copy-paste line printed: " .. chat_since(W, n))
	T.ok(A.MODEL_DEFAULT.pos[1] == 0, "the shared default is never edited")
	plus[3]:Click() -- z +0.1
	T.ok(math.abs(e.pos[3] - 0.1) < 1e-9, "z")
	plus[4]:Click() -- rot +0.1
	T.ok(math.abs(e.rot - (-0.4)) < 1e-9, "rot -0.5 + 0.1")
	T.ok(p.model_text.text:find("hellhound", 1, true) ~= nil, "panel names the enemy")
	n = #W.printed
	click(page, "Print all")
	T.ok(chat_since(W, n):find("nefarian = {", 1, true) ~= nil, "all enemy lines printed")
	click(page, "Reset enemy")
	T.ok(e.cam_scale == nil and e.pos == nil and e.rot == -0.5, "reset restores the file's values")
	-- no model on screen: a reason, no error
	hud.enemy_mode = "portrait"
	n = #W.printed
	plus[1]:Click()
	T.ok(chat_since(W, n):find("no enemy model", 1, true) ~= nil, "portrait fallback: reason printed")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("panel: footer (fps + frame cost) and allocation budget", function()
	local W = session()
	local App = open_ready(W)
	W.fps = 47
	local p = open_panel(W)
	frames(W, 60)
	T.ok(p.footer.text:find("fps 47", 1, true) ~= nil and p.footer.text:find("ms", 1, true) ~= nil, "footer: " .. tostring(p.footer.text))
	T.ok(App.profile, "profiling on")
	local f = p.frame
	local kb = alloc_kb(function() f.scripts.OnUpdate(f, DT) end, 300)
	T.ok(kb < 4, ("panel OnUpdate allocates < 4 KB per 300 frames (got %.2f KB)"):format(kb))
	-- closed: nothing runs, profiling off
	f:Hide()
	T.ok(not App.profile, "profiling off when closed")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("W0-P5 panel: invincible + enemy timers toggles, Live tab status dump", function()
	local W = session()
	local App = open_ready(W)
	local p = open_panel(W)
	T.eq(#p.pages, 9, "nine tabs (Live added, W0-P7: Board FX, W0-P8: Hit FX)")
	local page = p.pages[1]
	local c = App.combat
	local snap = W.store.DragonChessDB.run
	click(page, "Invincible: off")
	T.ok(c.enemy.invincible and App.run.dev, "invincible on, dev run")
	T.ok(find(page, "Invincible: ON") ~= nil, "label follows")
	local hp = c.enemy.current_health
	c:deal_damage_to_enemy(300)
	T.eq(c.enemy.current_health, hp, "enemy takes no damage")
	click(page, "Enemy timers: run")
	T.ok(c.enemy.timers_held, "timers paused")
	T.ok(find(page, "Enemy timers: PAUSED") ~= nil, "label follows")
	local before = c.enemy:get_time_to_next_attack()
	frames(W, 120)
	T.ok(math.abs(c.enemy:get_time_to_next_attack() - before) < 1e-6, "the cooldown stays put while the game runs")
	-- Live tab
	p.tabs[7]:Click()
	T.ok(p.pages[7]:IsShown(), "Live page shows")
	T.eq(p.tab, 7, "tab 7")
	local function lines()
		local out = {}
		for _, fs in ipairs(p.live_fs) do
			if fs.text ~= nil and fs.text ~= "" then out[#out + 1] = fs.text end
		end
		return table.concat(out, "\n")
	end
	T.ok(lines():find("INVINCIBLE", 1, true) ~= nil and lines():find("TIMERS PAUSED", 1, true) ~= nil, "flags listed: " .. lines())
	T.ok(lines():find("enemy attack in", 1, true) ~= nil, "enemy timer listed")
	-- statuses show up and refresh while the panel runs
	c:apply_heal_block(5)
	local f = p.frame
	f.scripts.OnUpdate(f, 0.3)
	T.ok(lines():find("player heal block", 1, true) ~= nil, "a new status appears on the next refresh: " .. lines())
	local nframes = #W.frames
	local kb = alloc_kb(function() f.scripts.OnUpdate(f, 0.01) end, 300)
	T.ok(kb < 8, ("Live tab OnUpdate allocates < 8 KB per 300 frames (got %.2f KB; strings only on refresh)"):format(kb))
	T.eq(#W.frames, nframes, "no frames created")
	-- off again
	p.tabs[1]:Click()
	click(page, "Invincible: ON")
	click(page, "Enemy timers: PAUSED")
	T.ok(not c.enemy.invincible and not c.enemy.timers_held, "both off")
	T.eq(W.store.DragonChessDB.run, snap, "dev actions never touched the saved run")
	-- a saved tab 7 is restored
	local W2 = session({ DragonChessDB = { debug = { enabled = true, tab = 7 } } })
	slash(W2, "debug")
	T.ok(W2.App.debug_panel.pages[7]:IsShown(), "tab 7 restored")
	T.eq(#W.errors + #W2.errors, 0, "no errors")
end)

T.done()
