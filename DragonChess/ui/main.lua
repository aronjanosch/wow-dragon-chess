local addonName, ns = ...
-- Bootstrap (W0-P1, combat wiring W0-G1): SavedVariables, slash commands, the
-- sim + combat driver, soft pause, fight flow and persistence. No game rules:
-- the sim (core/) owns the board, combat (core/combat.lua) the fight.
--
-- Driver: one OnUpdate on the window ticks the sim only while the window is
-- shown and not soft-paused (hide = pause; core clamps dt). All game time is
-- sim time: combat's enemy / status clocks are timers on the sim's gameplay
-- time, so not ticking freezes attacks and statuses too. Core errors are
-- forwarded to geterrorhandler() and stop the driver until the overlay click /
-- /dchess reset (a dead coroutine leaves the board unusable).
--
-- Fight screen (W0-P2): ui/fight_view.lua (App.hud) on the window's panels;
-- the pause button soft-pauses ("paused"), wall-clock widgets (the queue's
-- Cooldown sweep) are frozen on every pause / error / game over.
--
-- Fight flow (W0-G2b): core/run.lua owns the 10-fight ladder, difficulty scaling, the
-- boss heal and the between-fight beat (run:update() once per frame). This file only
-- reacts: run_fight_starting -> boundary snapshot + stage label, run_won / run_lost ->
-- records (best score on both, unlock on a win) + the result overlay, click = new run
-- on the selected difficulty (DragonChessDB.difficulty, <= the unlocked one).
--
-- Persistence (W0 scope: fight boundaries only). DragonChessDB.run =
-- { v = RUN_VERSION, combat = combat:serialize(), board = sim:serialize() or nil,
--   ladder = run:serialize() }
-- is written when a fight starts (the boundary before it) and refreshed on
-- PLAYER_LOGOUT (also /reload) while between fights. A /reload mid-fight
-- therefore restarts that fight from its start (HP / score / statuses as they
-- were then; the board too when it was at rest at that moment, otherwise a new
-- board). A lost run or an error clears it. An empty DB is a normal first run;
-- a corrupt / other-version snapshot (incl. W0-P1 board-only ones) starts a new
-- run silently. DragonChessDB.records / .unlocked / .difficulty (core/run.lua) are
-- account-wide and written when a run ends.
--
-- Globals (documented): DragonChessDB, DragonChessCharDB (SavedVariables),
-- DragonChessFrame (window, for UISpecialFrames), SLASH_DRAGONCHESS1/2 and
-- SlashCmdList.DRAGONCHESS.

local pcall, type, tostring, floor = pcall, type, tostring, math.floor

local App = {
	db = nil, -- DragonChessDB (after ADDON_LOADED)
	sim = nil,
	combat = nil,
	win = nil,
	view = nil,
	hud = nil,
	input = nil,
	running = false, -- window shown -> driver ticks
	soft = false, -- soft-paused (overlay shown)
	soft_text = nil,
	crashed = false, -- core error: driver stopped until reset
	run = nil, -- core/run.lua Run (ladder, difficulty) of the current run
	lost = false, -- run lost: game-over overlay until clicked
	lost_text = nil,
	won = false, -- run won: victory overlay until clicked
	won_text = nil,
	menu = nil, -- ui/menu.lua (W0-P4)
	menu_open = false, -- menu shown: the game is paused (no tick, no input)
	esc = nil, -- Esc catcher (ui/menu.lua)
	hint = nil, -- ui/hint.lua idle hint
	minimap = nil, -- minimap button
	stuck = false, -- the board could not be reshuffled (core board_shuffled(false)): restart offer
	debug_panel = nil, -- ui/debug.lua (W0-D1), created on first /dchess debug
	profile = false, -- debug panel open: on_update measures the frame cost into frame_ms / frame_peak
	frame_ms = 0,
	frame_peak = 0,
}
ns.App = App

local RUN_VERSION = 3 -- DragonChessDB.run layout (1 = W0-P1 board-only, 2 = W0-G1 combat; both discarded)
App.RUN_VERSION = RUN_VERSION
local COLS, ROWS, COLORS = 8, 8, 6
App.FIGHT_TRANSITION = ns.Run.FIGHT_TRANSITION -- kill -> next fight (sim s), owned by core/run.lua
local CRASH_TEXT = "Dragon Chess hit an error.\nClick to start a new run."
local STUCK_TEXT = "Stuck - no moves left on the board.\nClick to start a new run."

-- Swap gate reasons (combat:try_swap) -> short feedback over the board.
-- "game_over" needs none: the game-over overlay covers the board.
local REJECT_TEXT = {
	stunned = "Stunned!",
	not_in_fight = "Wait for the next enemy",
}

local function say(msg)
	print("|cffffcc00Dragon Chess|r " .. tostring(msg))
end

-- Scheduler errors carry a traceback of the failing coroutine.
if ns.traceback == nil then
	ns.traceback = function(co, msg)
		local ok, stack = pcall(debugstack, co, 1, 20, 20)
		if ok and type(stack) == "string" then return tostring(msg) .. "\n" .. stack end
		return tostring(msg)
	end
end

local function report(err)
	local handler = geterrorhandler()
	if handler then handler(err) else say(err) end
end

---------------------------------------------------------------- overlay

-- One overlay, highest priority first: error > soft pause > game over > victory.
local function refresh_overlay()
	if App.win == nil then return end
	local text
	if App.crashed then
		text = CRASH_TEXT
	elseif App.soft then
		text = App.soft_text
	elseif App.stuck then
		text = STUCK_TEXT
	elseif App.lost then
		text = App.lost_text
	elseif App.won then
		text = App.won_text
	end
	ns.Window.set_overlay(App.win, text)
end

---------------------------------------------------------------- run lifecycle

local function new_seed()
	local t = time() or 0
	local fine = floor((debugprofilestop() or 0) * 1000) % 1000003
	return (t + fine) % 2147483647
end

local function valid_sim(sim)
	local b = sim and sim.board
	return b ~= nil and b.cols == COLS and b.rows == ROWS and b.colors == COLORS
end

-- The difficulty of the next run: the player's choice, never above the unlocked one.
local function selected_difficulty()
	local db = App.db
	local d = ns.Run.clamp_difficulty(db.difficulty)
	local u = ns.Run.unlocked(db)
	return d > u and u or d
end

local function fresh_run()
	local seed = new_seed()
	-- No release_on_settle: combat lifts spawn protection after its drain.
	local sim = ns.Sim.new({ seed = seed })
	local combat = ns.Combat.new({ sim = sim, seed = seed, kit = ns.Kit.default() })
	local run = ns.Run.new({ combat = combat, difficulty = selected_difficulty() })
	return sim, combat, run
end

-- Snapshot -> sim, combat, run (nil when unusable).
local function restore_run(data)
	if type(data) ~= "table" or data.v ~= RUN_VERSION or type(data.combat) ~= "table" then return nil end
	local sim
	if type(data.board) == "table" then
		sim = ns.Sim.deserialize(data.board)
		if not valid_sim(sim) then sim = nil end
	end
	if sim == nil then sim = ns.Sim.new({ seed = new_seed() }) end
	local combat = ns.Combat.deserialize(data.combat, { sim = sim, kit = ns.Kit.default() })
	if combat == nil or combat.game_over or not (combat.player_health > 0) then return nil end
	local run = ns.Run.deserialize(data.ladder, combat)
	if run == nil then return nil end
	return sim, combat, run
end

local function load_or_new()
	local ok, sim, combat, run = pcall(restore_run, App.db.run)
	if ok and sim ~= nil then return sim, combat, run end
	App.db.run = nil -- corrupt / other version: discard silently
	return fresh_run()
end

-- Fight-boundary snapshot (nil mid-fight): combat + the board if at rest + the ladder position.
local function boundary_snapshot()
	local combat, sim, run = App.combat, App.sim, App.run
	if combat == nil or combat.game_over or run == nil or run.over then return nil end
	local c = combat:serialize()
	if c == nil then return nil end
	local board
	if sim:is_at_rest() then board = sim:serialize() end
	return { v = RUN_VERSION, combat = c, board = board, ladder = run:serialize() }
end

local create_window, ensure_run -- defined below (a dev fight opens the window / starts the run)

-- Dev command (W0-G2a, fixed W0-P3.1): /dchess fight <id> starts that enemy now (and for the following
-- fights until /dchess reset or the panel's "next fight"; scaled by the run's difficulty, no records,
-- nothing saved). It brings the game into a state where a fight can be seen first: opens the window,
-- starts a run, leaves the menu / soft pause, replaces a lost / won / crashed run. Returns true +
-- message, or false + reason. (Playtest 3: "/dchess fight nefarian does nothing" in the live client;
-- offline it always worked, so the likely causes were a hidden / paused window or the menu being open,
-- where the old code switched the enemy silently behind the overlay and printed nothing.)
function App.dev_fight(id)
	if App.db == nil then return false, "not loaded yet" end
	id = tostring(id or ""):lower()
	if ns.Enemy.STUBS[id] == nil then return false, "unknown enemy '" .. id .. "'" end
	if App.win == nil then create_window() end
	if not App.win.frame:IsShown() then App.win.frame:Show() end -- on_show starts / restores the run
	if App.sim == nil then ensure_run() end
	local combat = App.combat
	if App.crashed or App.lost or App.won or App.stuck or combat == nil or combat.game_over then
		App.reset() -- a dead run cannot host a fight: a fresh one does
	end
	if App.menu_open then App.close_menu() end
	if App.soft then App.soft_resume() end
	if App.run == nil or App.combat == nil then return false, "no run" end
	local ok, res, msg = pcall(ns.Debug.fight, App.run, App.combat, id)
	if not ok then
		report(res)
		return false, "error: " .. tostring(res)
	end
	if not res then return false, msg end
	local okh, err = pcall(App.hud.update, App.hud)
	if not okh then report(err) end
	return true, msg
end

function App.crash(err)
	App.crashed = true
	if App.input then App.input:cancel() end
	if App.hud then pcall(App.hud.halt, App.hud) end
	report(err)
	refresh_overlay()
end

-- The difficulty button: the run's level, and the next run's when they differ ("D2>3").
local function refresh_difficulty_button()
	local win = App.win
	if win == nil or App.db == nil then return end
	local sel = selected_difficulty()
	local run = App.run
	local text = "D" .. sel
	if run ~= nil and not run.over and run.difficulty ~= sel then text = "D" .. run.difficulty .. ">" .. sel end
	win.difficulty.text:SetText(text)
end

-- Flow events (run_fight_starting / run_won are on the sim bus, run_lost on combat's; all run
-- inside sim:tick inside the driver's pcall).
local function on_fight_starting(run)
	if not run.dev then App.db.run = boundary_snapshot() end
	App.hud:set_run_label(run:label(), run:stage())
	refresh_difficulty_button()
end

local function best_line(run, new_best)
	local best = ns.Run.best_score(App.db, run.difficulty)
	return "Best (D" .. run.difficulty .. "): " .. tostring(best) .. (new_best and " - new best!" or "")
end

local function on_run_lost()
	local run, combat = App.run, App.combat
	App.lost = true
	App.db.run = nil -- the next session starts a new run
	local new_best = false
	if not run.dev then new_best = ns.Run.record_result(App.db, run.difficulty, combat.score, false) end
	App.lost_text = "Defeated!\nScore: " .. tostring(combat.score) .. "\n" .. best_line(run, new_best)
		.. "\n\nClick to try again"
	if App.input then App.input:cancel() end
	if App.hud then App.hud:halt() end
	refresh_overlay()
end

local function on_run_won()
	local run, combat = App.run, App.combat
	App.won = true
	App.db.run = nil
	local new_best, unlocked = false, nil
	if not run.dev then new_best, unlocked = ns.Run.record_result(App.db, run.difficulty, combat.score, true) end
	local text = "VICTORY!\nScore: " .. tostring(combat.score) .. "\n" .. best_line(run, new_best)
	if unlocked ~= nil then text = text .. "\nDifficulty " .. unlocked .. " unlocked!" end
	App.won_text = text .. "\n\nClick for a new run"
	if App.input then App.input:cancel() end
	if App.hud then App.hud:halt() end
	refresh_difficulty_button()
	refresh_overlay()
end

-- No-moves reshuffle (core board_shuffled(ok), inside sim:tick): a short line + a pop over the
-- board; ok == false = no move could be made at all -> "Stuck" overlay with the restart offer.
local function on_shuffled(ok)
	if ok then
		App.hud:flash("No moves - shuffling")
		App.view:pop()
	else
		App.stuck = true
		App.input:cancel()
		refresh_overlay()
	end
end

local function bind_run()
	App.view:bind(App.sim)
	App.sim:on("board_shuffled", on_shuffled)
	App.hud:bind(App.combat)
	App.sim:on("run_fight_starting", on_fight_starting)
	App.sim:on("run_won", on_run_won)
	App.combat:on("run_lost", on_run_lost)
	App.run:begin_fight()
	App.hud:update()
end

-- Bind a sim + combat to the view / HUD and start the fight.
local function attach(sim, combat, run)
	App.sim, App.combat, App.run = sim, combat, run
	App.crashed, App.lost, App.won, App.stuck = false, false, false, false
	App.input:cancel()
	App.hint:reset()
	local ok, err = pcall(bind_run)
	if not ok then App.crash(err) end
	refresh_overlay()
end

function ensure_run()
	if App.sim ~= nil then return end
	local ok, sim, combat, run = pcall(load_or_new)
	if not ok then
		report(sim)
		App.db.run = nil
		sim, combat, run = fresh_run()
	end
	attach(sim, combat, run)
end

-- New run: /dchess reset, the game-over click and the error click.
function App.reset()
	App.db.run = nil
	App.sim, App.combat, App.run = nil, nil, nil
	App.crashed, App.lost, App.won, App.stuck = false, false, false, false
	if App.win == nil then return end
	App.view:unbind()
	App.hud:unbind()
	App.input:cancel()
	App.hint:reset()
	App.soft = false
	refresh_overlay()
	refresh_difficulty_button()
	if App.win.frame:IsShown() then ensure_run() end
end

---------------------------------------------------------------- input hooks

function App.get_sim()
	if App.crashed then return nil end
	return App.sim
end

function App.can_input()
	return App.running and not App.soft and not App.menu_open and not App.crashed and not App.lost
		and not App.won and not App.stuck and App.sim ~= nil
end

-- The player's swap: combat:try_swap (gate, then sim:try_swap). Gate reasons
-- get a short text over the board.
function App.swap(a, b)
	local combat = App.combat
	if combat == nil or App.crashed then return "invalid" end
	App.hint:reset() -- any swap attempt cancels the idle hint and restarts its timer
	local ok, result = pcall(combat.try_swap, combat, a, b)
	if not ok then
		App.crash(result)
		return "error"
	end
	local text = REJECT_TEXT[result]
	if text ~= nil and App.hud ~= nil then App.hud:flash(text) end
	return result
end

---------------------------------------------------------------- driver

-- The idle hint runs only while the player could swap right now and is not mid-press.
function App.hint_active()
	local combat = App.combat
	return App.can_input() and combat ~= nil and combat:can_player_swap() == "" and App.input.press_gem == nil
end

-- One frame of game + view (runs in pcall; no per-frame closures).
local function step(elapsed)
	local sim = App.sim
	sim:tick(elapsed)
	App.run:update() -- the next fight, once the between-fight beat is over
	App.hint:update(sim, App.hint_active())
	App.view:update(App.input)
	App.hud:update()
end

local function on_update(_, elapsed)
	if not App.running or App.soft or App.menu_open or App.crashed then return end
	if App.sim == nil then return end
	App.input:update()
	if App.profile then -- debug panel open: smoothed + peak cost of one game frame (ms), no allocation
		local t0 = debugprofilestop()
		local ok, err = pcall(step, elapsed)
		local ms = debugprofilestop() - t0
		App.frame_ms = App.frame_ms * 0.9 + ms * 0.1
		if ms > App.frame_peak then App.frame_peak = ms end
		if not ok then App.crash(err) end
		return
	end
	local ok, err = pcall(step, elapsed)
	if not ok then App.crash(err) end
end

---------------------------------------------------------------- soft pause

function App.soft_pause(reason)
	if not App.running or App.soft or App.crashed then return end
	App.soft = true
	App.soft_text = "Paused (" .. tostring(reason) .. ")\nClick to resume"
	App.input:cancel()
	App.hint:reset()
	App.hud:halt()
	refresh_overlay()
end

function App.soft_resume()
	if not App.soft then return end
	App.soft = false
	refresh_overlay()
end

local function on_overlay_click()
	if App.crashed then
		App.reset()
	elseif App.soft then
		App.soft_resume()
	elseif App.stuck or App.lost or App.won then
		App.reset()
	end
end

---------------------------------------------------------------- window

local function on_show()
	App.running = true
	App.soft = false
	refresh_overlay()
	App.hud:on_show()
	ensure_run()
	if App.esc then App.esc.arm() end
	ns.Assets.play("open")
end

local function on_hide()
	App.running = false
	if App.esc then App.esc.disarm() end
	if App.menu then App.close_menu() end
	if App.hint then App.hint:reset() end
	if App.input then App.input:cancel() end
	if App.hud then App.hud:halt() end
	ns.Assets.play("close")
end

local function on_pause()
	App.soft_pause("paused")
end

-- Spell icon of an ability gem (board view overlay): the combat kit's ability
-- for (colour, tier), the bomb icon for bombs. Display lookup only.
local function gem_icon(gem_type, tier, bomb)
	if bomb then return "bomb" end
	local combat = App.combat
	if combat == nil then return nil end
	local ability = combat.kit:get(gem_type, tier)
	return ability and ability.icon or nil
end

-- Difficulty chooser (/dchess difficulty N and the title-strip button): the choice applies to
-- the NEXT run. It starts a new run at once when nothing is at stake (fight 1, score 0); the
-- result overlay's click uses it anyway. Returns true, or false + why.
function App.set_difficulty(n)
	local db = App.db
	n = tonumber(n)
	if db == nil or n == nil or n ~= floor(n) or n < 1 or n > ns.Run.MAX_DIFFICULTY then
		return false, "difficulty must be 1-" .. ns.Run.MAX_DIFFICULTY
	end
	local unlocked = ns.Run.unlocked(db)
	if n > unlocked then
		return false, "difficulty " .. n .. " is locked (win a run on difficulty " .. unlocked .. " to unlock it)"
	end
	db.difficulty = n
	local run, combat = App.run, App.combat
	if run ~= nil and not run.over and run.difficulty ~= n and App.win ~= nil then
		if run.index == 1 and combat ~= nil and combat.score == 0 and not run.dev then
			App.reset()
			return true
		end
		say("difficulty " .. n .. " applies to the next run (/dchess reset starts it now)")
	end
	refresh_difficulty_button()
	return true
end

-- The button: next unlocked difficulty, wrapping.
function App.cycle_difficulty()
	local db = App.db
	if db == nil then return end
	local unlocked = ns.Run.unlocked(db)
	if unlocked <= 1 then
		say("only difficulty 1 is unlocked (win a run to unlock the next)")
		return
	end
	local ok, why = App.set_difficulty(selected_difficulty() % unlocked + 1)
	if not ok then say(why) end
end

---------------------------------------------------------------- menu + options (W0-P4)



-- DragonChessDB.options: sound (default on), quiet (default off), scale (window size factor), shake (default on).
local function init_options(db)
	if type(db.options) ~= "table" then db.options = {} end
	local o = db.options
	if type(o.sound) ~= "boolean" then o.sound = true end
	if type(o.quiet) ~= "boolean" then o.quiet = false end
	if type(o.shake) ~= "boolean" then o.shake = true end -- screen shake (W0-P6)
	local sc = o.scale
	if type(sc) ~= "number" or sc ~= sc or sc < 0.5 or sc > 2 then o.scale = nil end
	if type(db.minimap) ~= "table" then db.minimap = {} end
	if type(db.debug) ~= "table" then db.debug = {} end -- debug panel (ui/debug.lua)
	if type(db.debug.enemy_tuning) ~= "table" then db.debug.enemy_tuning = {} end
	ns.Assets.enemy_tuning_apply(db.debug.enemy_tuning)
end

-- Push the options into the one sound gate and the window.
function App.apply_options()
	local o = App.db.options
	ns.Assets.gem_set = ns.Assets.GEM_SETS[App.db.gem_set] and App.db.gem_set or "jewels"
	ns.Assets.sound_enabled = o.sound ~= false
	ns.Assets.quiet = o.quiet == true
	if App.hud ~= nil then App.hud:set_shake(o.shake ~= false) end
	if App.win ~= nil and o.scale ~= nil then App.win.frame:SetScale(o.scale) end
end

function App.set_option(name, value)
	if name ~= "sound" and name ~= "quiet" and name ~= "scale" and name ~= "shake" then return false end
	App.db.options[name] = value
	App.apply_options()
	return true
end

-- Gem set (Assets.GEM_SETS), saved in DragonChessDB.gem_set; takes effect at once.
function App.set_gem_set(name)
	if ns.Assets.GEM_SETS[name] == nil then return false end
	App.db.gem_set = name
	ns.Assets.gem_set = name
	if App.view ~= nil then App.view:refresh_looks() end
	if App.hud ~= nil then
		App.hud:refresh_gem_icons()
	end
	return true
end

function App.difficulty_text()
	local sel = selected_difficulty()
	return "D" .. sel .. " (" .. ns.Run.unlocked(App.db) .. " unlocked)"
end

-- The menu pauses the game like a soft pause, without the overlay (it covers part of the board).
function App.open_menu()
	if App.db == nil then return end
	if App.win == nil then create_window() end
	if not App.win.frame:IsShown() then App.win.frame:Show() end
	App.menu_open = true
	App.input:cancel()
	App.hint:reset()
	App.hud:halt()
	App.menu:open()
end

function App.close_menu()
	App.menu_open = false
	if App.menu ~= nil then App.menu:close() end
end

function App.toggle_menu()
	if App.menu_open then App.close_menu() else App.open_menu() end
end

-- Menu: Restart run (after the inline confirm) = a new run on the selected difficulty.
function App.restart_run()
	App.close_menu()
	App.reset()
	say("new run.")
end

-- Esc (via the catcher): the menu first, then the window. The catcher was hidden by the
-- client, so re-arm it while the window stays.
function App.on_escape()
	if App.menu_open then
		App.close_menu()
		if App.esc then App.esc.arm() end
	elseif App.win ~= nil then
		App.win.frame:Hide()
	end
end

function create_window()
	if App.win ~= nil then return end
	local db = App.db
	if type(db.window) ~= "table" then db.window = {} end
	local win = ns.Window.create(db.window, {
		on_show = on_show, on_hide = on_hide, on_overlay_click = on_overlay_click, on_pause = on_pause,
		on_difficulty = App.cycle_difficulty, on_menu = App.toggle_menu,
		on_drag = function(started) -- the shake ends before the window moves and stays off while it is dragged
			if App.hud ~= nil then App.hud.juice:set_dragging(started) end
		end,
		on_debug = function()
			local ok, err = pcall(ns.DebugPanel.command, App)
			if not ok then report(err) end
		end,
	})
	App.win = win
	App.view = ns.BoardView.new(win.host, COLS, ROWS)
	App.view:set_icon_source(gem_icon)
	App.hud = ns.FightView.new(win)
	-- W0-P7: gem landings / rejected swaps puff, halt hides the view-only effects (auras, dragged halo)
	App.view.on_land = function(c, r) App.hud:on_land(c, r) end
	App.view.on_reject = function(c1, r1, c2, r2) App.hud:on_reject(c1, r1, c2, r2) end
	App.hud.on_halt = function() App.view:halt_fx() end
	App.input = ns.Input.new(win.host, App.view, App)
	App.hint = ns.Hint.new(App.view)
	App.menu = ns.Menu.create(win, App)
	App.esc = ns.Menu.create_escape(App.on_escape)
	win.frame:SetScript("OnUpdate", on_update)
	App.apply_options()
	refresh_difficulty_button()
end

function App.show()
	if App.db == nil then return end -- before ADDON_LOADED
	create_window()
	App.win.frame:Show()
end

function App.toggle()
	if App.win ~= nil and App.win.frame:IsShown() then
		App.win.frame:Hide()
	else
		App.show()
	end
end

---------------------------------------------------------------- persistence

-- PLAYER_LOGOUT: between fights, refresh the boundary snapshot (HP after the
-- kill); mid-fight, keep the one written when this fight started.
local function save_run()
	if App.sim == nil then return end -- never opened this session: keep the stored run
	local combat, run = App.combat, App.run
	if App.crashed or App.lost or App.won or combat == nil or combat.game_over or run == nil or run.over then
		App.db.run = nil
		return
	end
	if run.dev then return end -- a dev fight is never saved
	if combat.enemy == nil or combat.fight_over then App.db.run = boundary_snapshot() end
end

---------------------------------------------------------------- events

local SOFT_PAUSE_EVENTS = {
	LFG_PROPOSAL_SHOW = "queue",
	READY_CHECK = "ready check",
	PLAYER_ENTERING_WORLD = "loading",
	UPDATE_BATTLEFIELD_STATUS = "battleground",
	PLAYER_REGEN_DISABLED = "combat", -- only with DragonChessDB.pause_in_combat
}

local events = CreateFrame("Frame")

local function on_event(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= addonName then return end
		events:UnregisterEvent("ADDON_LOADED")
		-- Empty / missing SavedVariables are a normal first run (cold-start bug
		-- in the beta: SavedVariables may not load after a client restart).
		if type(DragonChessDB) ~= "table" then DragonChessDB = {} end
		if type(DragonChessCharDB) ~= "table" then DragonChessCharDB = {} end
		App.db = DragonChessDB
		if type(App.db.window) ~= "table" then App.db.window = {} end
		init_options(App.db)
		App.apply_options()
		-- Minimap button + addon compartment entry: left = toggle, right = menu. Never fatal.
		local hooks = { on_left = App.toggle, on_right = App.toggle_menu }
		local ok, btn = pcall(ns.MinimapButton.create, App.db.minimap, hooks)
		if ok then App.minimap = btn else report(btn) end
		pcall(ns.MinimapButton.register_compartment, hooks)
	elseif event == "PLAYER_LOGOUT" then
		local ok, err = pcall(save_run)
		if not ok then
			App.db.run = nil
			report(err)
		end
	elseif event == "PLAYER_REGEN_DISABLED" then
		if App.db and App.db.pause_in_combat then App.soft_pause(SOFT_PAUSE_EVENTS[event]) end
	elseif event == "UPDATE_BATTLEFIELD_STATUS" then
		if arg1 ~= nil then
			local ok, status = pcall(GetBattlefieldStatus, arg1)
			if ok and status == "confirm" then App.soft_pause(SOFT_PAUSE_EVENTS[event]) end
		end
	elseif SOFT_PAUSE_EVENTS[event] then
		App.soft_pause(SOFT_PAUSE_EVENTS[event])
	end
end

events:SetScript("OnEvent", on_event)
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGOUT")
for name in pairs(SOFT_PAUSE_EVENTS) do -- registration order irrelevant
	-- Registering an unknown event throws; a missing one only loses a soft pause.
	pcall(events.RegisterEvent, events, name)
end

---------------------------------------------------------------- slash commands

SLASH_DRAGONCHESS1 = "/dchess"
SLASH_DRAGONCHESS2 = "/dragonchess"
SlashCmdList.DRAGONCHESS = function(msg)
	local cmd = (msg or ""):match("^%s*(%S*)"):lower()
	if App.db == nil then
		say("not loaded yet (saved data is still loading)")
		return
	end
	if cmd == "reset" then
		App.reset()
		say("new run.")
	elseif cmd == "combat" then
		App.db.pause_in_combat = not App.db.pause_in_combat
		say("pause on entering combat: " .. (App.db.pause_in_combat and "on" or "off"))
	elseif cmd == "fight" then
		local id = (msg or ""):match("^%s*%S+%s+(%S+)")
		if id == nil then
			say("/dchess fight <id>: " .. table.concat(ns.Debug.enemy_ids(), ", "))
		else
			-- never silent: the result (or the reason / the error) always goes to the chat
			local called, ok, msg = pcall(App.dev_fight, id)
			if not called then
				report(ok)
				say("fight: error - " .. tostring(ok))
			else
				say(tostring(msg or (ok and ("fight: " .. id:lower()) or "fight: failed")))
			end
		end
	elseif cmd == "debug" then
		local arg = (msg or ""):match("^%s*%S+%s+(%S+)")
		local called, err = pcall(ns.DebugPanel.command, App, arg and arg:lower() or nil)
		if not called then
			report(err)
			say("debug panel error - " .. tostring(err))
		end
	elseif cmd == "difficulty" then
		local arg = (msg or ""):match("^%s*%S+%s+(%S+)")
		if arg == nil then
			local db = App.db
			local d = selected_difficulty()
			say(("difficulty %d (unlocked up to %d, best %d). /dchess difficulty <1-%d> chooses the next run's."):format(
				d, ns.Run.unlocked(db), ns.Run.best_score(db, d), ns.Run.MAX_DIFFICULTY))
		else
			local ok, why = App.set_difficulty(arg)
			if ok then
				say("next run: difficulty " .. selected_difficulty())
			else
				say(why)
			end
		end
	elseif cmd == "bg" then -- dev: same as /dcbg (background atlases, model framing)
		local rest = (msg or ""):match("^%s*%S+%s*(.-)%s*$")
		local dcbg = SlashCmdList.DCBG
		if dcbg ~= nil then dcbg(rest) end
	elseif cmd == "" then
		App.toggle()
	else
		say("/dchess - open/close, /dchess reset - new run, /dchess difficulty <1-5>, /dchess combat - toggle pause on combat, "
			.. "/dchess fight <id>, /dchess bg and /dchess debug [on|off] (debug panel) - dev")
	end
end
