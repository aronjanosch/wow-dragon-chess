-- Release build test: loads the addon like the release TOC would (every TOC file except core/debug.lua and
-- ui/debug.lua, see tools/package.sh) and checks that nothing dev-only is there and the game still runs.
-- Also: the TOC lists every .lua file under core/, data/ and ui/ (a new file cannot be forgotten in the release).
local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "."
local T = dofile(dir .. "/t.lua")
local loader = dofile(dir .. "/loader.lua")
local Stubs = dofile(dir .. "/wow_stubs.lua")
T.start("release_test")

local ADDON = "DragonChess"
local addon_dir = loader.wow_dir() .. "/"
local DT = 1 / 60

---------------------------------------------------------------- TOC completeness

T.case("TOC lists every .lua file under core/, data/ and ui/", function()
	local listed = {}
	for _, f in ipairs(loader.toc_files()) do listed[f] = true end
	local p = io.popen('cd "' .. addon_dir .. '" && find core data ui -name "*.lua" | sort')
	local n = 0
	for rel in p:lines() do
		n = n + 1
		T.ok(listed[rel], "TOC lists " .. rel)
	end
	p:close()
	T.ok(n > 20, "found the addon files (" .. n .. ")")
	for f in pairs(listed) do
		local fh = io.open(addon_dir .. f)
		T.ok(fh ~= nil, "TOC entry exists: " .. f)
		if fh then fh:close() end
	end
	local rel = loader.toc_files({ release = true })
	local have_debug = false
	for _, f in ipairs(rel) do
		if f:find("debug", 1, true) then have_debug = true end
	end
	T.ok(not have_debug, "the release TOC has no debug file")
	T.eq(#rel, #loader.toc_files() - 2, "the release TOC is the dev TOC minus the two debug files")
end)

---------------------------------------------------------------- release session

local function session()
	local W = Stubs.new()
	local ns = {}
	for _, f in ipairs(loader.toc_files({ release = true })) do W.load(addon_dir .. f, ADDON, ns) end
	W.fire("ADDON_LOADED", ADDON)
	W.ns, W.App = ns, ns.App
	return W
end

local function slash(W, msg)
	W.stubs.SlashCmdList.DRAGONCHESS(msg or "")
	if W.App ~= nil and W.App.start_open then W.App.close_start() end
end

T.case("release build: no dev tooling, the game runs", function()
	local W = session()
	local App, ns = W.App, W.ns
	T.ok(ns.DEV == nil and ns.Debug == nil and ns.DebugPanel == nil, "no ns.DEV / ns.Debug / ns.DebugPanel")
	T.eq(#W.errors, 0, "no error at load")
	T.ok(W.store.SLASH_DCFX1 == nil and W.store.SLASH_DCSND1 == nil and W.store.SLASH_DCBG1 == nil, "no dev slash commands")
	T.ok(W.stubs.SlashCmdList.DCFX == nil and W.stubs.SlashCmdList.DCSND == nil and W.stubs.SlashCmdList.DCBG == nil, "no dev handlers")
	T.eq(W.store.SLASH_DRAGONCHESS1, "/dchess", "/dchess stays")

	-- unknown commands in a release build: the normal help, nothing opens, no error
	for _, cmd in ipairs({ "debug", "debug on", "fight x", "fight", "bg" }) do
		local before = #W.printed
		W.stubs.SlashCmdList.DRAGONCHESS(cmd)
		T.ok(App.win == nil, "/dchess " .. cmd .. " opens nothing")
		T.ok(#W.printed > before, "/dchess " .. cmd .. " prints the help")
		local help = W.printed[#W.printed] or ""
		T.ok(help:find("/dchess reset", 1, true) ~= nil and not help:find("debug", 1, true) and not help:find("fight", 1, true),
			"help for /dchess " .. cmd .. " lists no dev command")
	end
	T.eq(#W.errors, 0, "dev commands: no error")

	-- the window opens, a run starts and ticks
	slash(W, "")
	T.ok(App.win ~= nil and App.win.frame:IsShown(), "/dchess opens the window")
	T.ok(App.sim ~= nil and App.combat ~= nil, "run started")
	for _ = 1, 10 * 60 do W.update(DT) end
	T.ok(App.sim.now > 5, "the sim ticks (" .. tostring(App.sim.now) .. " s)")
	T.eq(#W.errors, 0, "ticking: no error")
	T.ok(not App.crashed, "no crash")

	-- no Debug button in the title strip
	local found = false
	for _, f in ipairs(W.frames) do
		if f.ftype == "Button" and f.text ~= nil and f.text.text == "Debug" then found = true end
	end
	T.ok(not found, "no Debug button")

	-- a saved tuning table from a dev build is ignored, not an error
	T.ok(App.dev_fight ~= nil and select(1, App.dev_fight("puppy")) == false, "dev_fight is a no-op")
	T.eq(#W.errors, 0, "dev_fight: no error")
end)

T.case("release build: the four menus (start, pause, options, result) work without any debug code", function()
	local W = session()
	local App, ns = W.App, W.ns
	T.ok(ns.Panel ~= nil and ns.StartMenu ~= nil and ns.Menu ~= nil and ns.ResultMenu ~= nil, "panel kit and menus loaded")
	W.stubs.SlashCmdList.DRAGONCHESS("")
	T.ok(App.start_open and App.start.form == "start", "start form")
	T.eq(App.start.title.text, "Dragon Chess", "start header")
	App.start.buttons.start.scripts.OnClick(App.start.buttons.start)
	App.combat.score = 77
	App.win.frame:Hide()
	W.stubs.SlashCmdList.DRAGONCHESS("")
	T.eq(App.start.form, "resume", "pause form")
	local opt = App.start.buttons.options
	opt.scripts.OnClick(opt)
	T.ok(App.menu_open and App.menu.frame:IsShown(), "options")
	App.menu.buttons.close.scripts.OnClick(App.menu.buttons.close)
	App.start.buttons.continue.scripts.OnClick(App.start.buttons.continue)
	App.combat:take_true_damage(App.combat.player_health)
	T.ok(App.result_menu.frame:IsShown() and App.result_menu.score.text == "77", "result screen")
	local nr = App.result_menu.buttons.new_run
	nr.scripts.OnClick(nr)
	T.ok(App.start_open and App.start.form == "start", "New run -> start form")
	T.eq(#W.errors, 0, "no error")
end)

T.case("release build: saved debug data from a dev build is ignored", function()
	local W = Stubs.new()
	local ns = {}
	W.store.DragonChessDB = { debug = { enemy_tuning = { puppy = { cam_scale = 9 } } } }
	for _, f in ipairs(loader.toc_files({ release = true })) do W.load(addon_dir .. f, ADDON, ns) end
	W.fire("ADDON_LOADED", ADDON)
	T.eq(#W.errors, 0, "no error with saved tuning")
	W.App = ns.App
	slash(W, "")
	for _ = 1, 120 do W.update(DT) end
	T.eq(#W.errors, 0, "runs with saved tuning")
end)

T.done()
