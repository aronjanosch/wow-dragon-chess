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
-- { v = RUN_VERSION, combat = combat:serialize(), board = sim:serialize() or nil, class_id = kit class (W1-G1),
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
	lost = false, -- run lost: result screen until its button is clicked
	won = false, -- run won: result screen (after the death beat)
	result = nil, -- data of the result screen (ui/result.lua), set by on_run_lost / on_run_won
	result_menu = nil, -- ui/result.lua (W0-P12)
	menu = nil, -- ui/menu.lua (W0-P4)
	menu_open = false, -- menu shown: the game is paused (no tick, no input)
	esc = nil, -- Esc catcher (ui/menu.lua)
	start = nil, -- ui/start_menu.lua start / resume panel (W0-P10)
	restored = false, -- the run came from a saved snapshot (the start panel shows its resume form)
	start_open = false, -- start / resume panel shown: the game is paused (no tick, no input)
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
App.HEAL_MOMENT = ns.Run.HEAL_MOMENT -- extra beat after a boss that healed
local VICTORY_BEAT = 1.0 -- W0-P11: the last boss's death plays this long before the victory overlay (Godot FIGHT_DEATH_BEAT)
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

-- One overlay, highest priority first: error > soft pause > stuck (text overlay). A lost / won run shows the result
-- screen (W0-P12) instead, unless one of those overlays is up.
local function refresh_overlay()
	if App.win == nil then return end
	local text
	if App.crashed then
		text = CRASH_TEXT
	elseif App.soft then
		text = App.soft_text
	elseif App.stuck then
		text = STUCK_TEXT
	end
	ns.Window.set_overlay(App.win, text)
	if App.result_menu ~= nil then
		if text == nil and (App.lost or (App.won and App.won_at == nil)) then
			App.result_menu:open(App.result)
		else
			App.result_menu:close()
		end
	end
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

-- The class of the next run (W1-G1): DragonChessCharDB.class_id when it names a class, else the character's
-- own class (UnitClass may be missing or return nothing); nil = no class = the default kit ("Classic").
local function valid_class(id)
	return type(id) == "string" and ns.Classes ~= nil and ns.Classes[id] ~= nil and id or nil
end

function App.selected_class()
	local cdb = App.chardb
	local id = type(cdb) == "table" and valid_class(cdb.class_id) or nil
	if id ~= nil then return id end
	local ok, token = pcall(function() return (select(2, UnitClass("player"))) end)
	return ok and valid_class(token) or nil
end

local function fresh_run()
	local seed = new_seed()
	-- No release_on_settle: combat lifts spawn protection after its drain.
	local sim = ns.Sim.new({ seed = seed })
	local combat = ns.Combat.new({ sim = sim, seed = seed, kit = ns.Kit.for_class(App.selected_class()) })
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
	-- a save without / with an unknown class_id resumes with the default kit ("Classic")
	local combat = ns.Combat.deserialize(data.combat, { sim = sim, kit = ns.Kit.for_class(valid_class(data.class_id)) })
	if combat == nil or combat.game_over or not (combat.player_health > 0) then return nil end
	local run = ns.Run.deserialize(data.ladder, combat)
	if run == nil then return nil end
	return sim, combat, run
end

local function load_or_new()
	local ok, sim, combat, run = pcall(restore_run, App.db.run)
	if ok and sim ~= nil then
		App.restored = true
		return sim, combat, run
	end
	App.db.run = nil -- corrupt / other version: discard silently
	App.restored = false
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
	return { v = RUN_VERSION, combat = c, board = board, ladder = run:serialize(), class_id = combat.kit.class_id }
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
	if App.start_open then App.close_start() end
	if App.soft then App.soft_resume() end
	if App.run == nil or App.combat == nil then return false, "no run" end
	if ns.Debug == nil then return false, "not available" end
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

-- The data of the result screen (ui/result.lua); the records were written by the caller.
local function make_result(run, combat, won, new_best, unlocked)
	return {
		won = won, score = combat.score, best = ns.Run.best_score(App.db, run.difficulty), new_best = new_best,
		unlocked = unlocked, difficulty = run.difficulty, class_id = combat.kit.class_id,
		enemy = combat.enemy ~= nil and combat.enemy.name or nil, stage = run:stage(), fight = run:fight_in_stage(),
		dev = run.dev, fights = ns.Run.fight_count(),
	}
end

local function on_run_lost()
	local run, combat = App.run, App.combat
	App.lost = true
	App.db.run = nil -- the next session starts a new run
	local new_best = false
	if not run.dev then new_best = ns.Run.record_result(App.db, run.difficulty, combat.score, false) end
	App.result = make_result(run, combat, false, new_best, nil)
	if App.input then App.input:cancel() end
	if App.hud then App.hud:halt() end
	refresh_overlay()
end

local function on_run_won()
	local run, combat = App.run, App.combat
	App.won = true
	App.won_at = App.sim.now + VICTORY_BEAT -- the overlay (and the HUD halt) wait for the death beat
	App.db.run = nil
	local new_best, unlocked = false, nil
	if not run.dev then new_best, unlocked = ns.Run.record_result(App.db, run.difficulty, combat.score, true) end
	App.result = make_result(run, combat, true, new_best, unlocked)
	if App.input then App.input:cancel() end
	refresh_difficulty_button()
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
	App.crashed, App.lost, App.won, App.stuck, App.won_at, App.result = false, false, false, false, nil, nil
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
		App.restored = false
		sim, combat, run = fresh_run()
	end
	attach(sim, combat, run)
end

-- New run: /dchess reset, the game-over click and the error click.
function App.reset()
	App.db.run = nil
	App.restored = false
	App.sim, App.combat, App.run = nil, nil, nil
	App.crashed, App.lost, App.won, App.stuck, App.won_at, App.result = false, false, false, false, nil, nil
	if App.win == nil then return end
	App.view:unbind()
	App.hud:unbind()
	App.input:cancel()
	App.hint:reset()
	App.soft = false
	-- the start form survives a reset (its difficulty button restarts a fresh run); the resume form does not
	local reopen = App.start_open and App.start ~= nil and App.start.form == "start"
	App.close_start()
	refresh_overlay()
	refresh_difficulty_button()
	if App.win.frame:IsShown() then
		ensure_run()
		if reopen then App.open_start() end
	end
end

---------------------------------------------------------------- input hooks

function App.get_sim()
	if App.crashed then return nil end
	return App.sim
end

function App.can_input()
	return App.running and not App.soft and not App.menu_open and not App.start_open and not App.crashed and not App.lost
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
	if App.won_at ~= nil and sim.now >= App.won_at then -- the victory overlay, after the death beat (W0-P11)
		App.won_at = nil
		App.hud:halt()
		refresh_overlay()
	end
	App.hint:update(sim, App.hint_active())
	App.view:update(App.input)
	App.hud:update()
end

local function on_update(_, elapsed)
	if App.hud ~= nil then App.hud:settle_model() end -- also behind a menu / while paused (the model shows there)
	if not App.running or App.soft or App.menu_open or App.start_open or App.crashed then return end
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
	elseif App.stuck then
		App.reset()
	end
end

---------------------------------------------------------------- window

local function on_show()
	App.running = true
	App.hidden_by_combat = false -- opened (by hand or after combat): combat end must not reopen it later
	App.soft = false
	refresh_overlay()
	App.hud:on_show()
	ensure_run()
	App.open_start() -- W0-P10: every open starts at a start / resume panel, never in a running fight
	if App.esc then App.esc.arm() end
	ns.Assets.play("open")
end

local function on_hide()
	App.running = false
	App.hidden_by_combat = false -- closed by hand stays closed; on_combat_start sets it after its Hide
	if App.esc then App.esc.disarm() end
	if App.menu then App.close_menu() end
	App.close_start()
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

-- Class picker (start menu): stores the choice per character and, while nothing is at stake (fight 1,
-- score 0), starts the new run with that class's kit at once (like set_difficulty). Returns true, or false + why.
function App.set_class(id)
	if valid_class(id) == nil then return false, "unknown class" end
	if type(App.chardb) == "table" then App.chardb.class_id = id end
	local run, combat = App.run, App.combat
	if run ~= nil and not run.over and combat ~= nil and combat.kit.class_id ~= id and App.win ~= nil then
		if run.index == 1 and combat.score == 0 and not run.dev then
			App.reset()
		else
			say("class " .. id .. " applies to the next run")
		end
	end
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
	if type(o.combat_hide) ~= "boolean" then o.combat_hide = true end -- hide (= pause) in combat, reopen after
	db.pause_in_combat = nil -- replaced by options.combat_hide
	local sc = o.scale
	if type(sc) ~= "number" or sc ~= sc or sc < 0.5 or sc > 2 then o.scale = nil end
	if type(db.minimap) ~= "table" then db.minimap = {} end
	if type(db.debug) ~= "table" then db.debug = {} end -- debug panel (ui/debug.lua)
	if type(db.debug.enemy_tuning) ~= "table" then db.debug.enemy_tuning = {} end
	if ns.DebugPanel ~= nil then ns.Assets.enemy_tuning_apply(db.debug.enemy_tuning) end -- the release ignores saved tuning
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
	if name ~= "sound" and name ~= "quiet" and name ~= "scale" and name ~= "shake" and name ~= "combat_hide" then
		return false
	end
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
	if App.start ~= nil and App.start:is_open() then App.start:refresh() end -- the spell preview's gems follow the set
	return true
end

-- The difficulty of the next run (the start screen's segment row).
function App.selected_difficulty()
	return selected_difficulty()
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

-- A run is in progress (resume form): a restored snapshot or a run past its first moment.
function App.run_in_progress()
	local run, combat = App.run, App.combat
	if run == nil or combat == nil or run.over or combat.game_over then return false end
	return App.restored or run.index > 1 or combat.score > 0 or combat.player_health < combat.player_max_health
end

-- Start / resume panel (W0-P10): pauses like the menu. Not over the crash / stuck / game-over / victory overlays
-- (their click starts a new run directly).
function App.open_start()
	if App.start == nil or App.sim == nil or not App.win.frame:IsShown() then return end
	if App.crashed or App.lost or App.won or App.stuck then return end
	App.start_open = true
	App.input:cancel()
	App.hint:reset()
	App.hud:halt()
	App.start:open(App.run_in_progress() and "resume" or "start")
end

-- Result screen -> New run: a fresh run that waits behind the start form (the picker).
function App.new_run_from_result()
	App.reset()
	App.open_start()
end

function App.close_start()
	App.start_open = false
	if App.start ~= nil then App.start:close() end
end

-- Resume form -> New run (after its inline confirm): a fresh run that waits behind the start form.
function App.new_run_from_start()
	App.reset()
	say("new run.")
	App.open_start()
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
			if ns.DebugPanel == nil then return end
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
	App.start = ns.StartMenu.create(win, App)
	App.result_menu = ns.ResultMenu.create(win, App)
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
}

-- Entering combat hides the window (hiding = paused); leaving combat reopens it at the resume
-- panel, but only if combat closed it and the player did not open / close it meanwhile.
local function on_combat_start()
	if not (App.db and App.db.options.combat_hide) then return end
	if App.win == nil or not App.win.frame:IsShown() then return end
	App.win.frame:Hide()
	App.hidden_by_combat = true
end

local function on_combat_end()
	if not App.hidden_by_combat then return end
	App.hidden_by_combat = false
	if App.win ~= nil and not App.win.frame:IsShown() then App.show() end
end

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
		App.chardb = DragonChessCharDB
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
		on_combat_start()
	elseif event == "PLAYER_REGEN_ENABLED" then
		on_combat_end()
	elseif event == "UPDATE_BATTLEFIELD_STATUS" then
		-- same gate as App.soft_pause: no API call while there is nothing to pause
		if arg1 ~= nil and App.running and not App.soft and not App.crashed then
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
pcall(events.RegisterEvent, events, "PLAYER_REGEN_DISABLED")
pcall(events.RegisterEvent, events, "PLAYER_REGEN_ENABLED")

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
		App.set_option("combat_hide", not App.db.options.combat_hide)
		if App.menu then App.menu:refresh() end
		say("hide window in combat: " .. (App.db.options.combat_hide and "on" or "off"))
	elseif cmd == "fight" and ns.DEV and ns.Debug ~= nil then
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
	elseif cmd == "debug" and ns.DEV and ns.DebugPanel ~= nil then
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
	elseif cmd == "bg" and ns.DEV then -- dev: same as /dcbg (background atlases, model framing)
		local rest = (msg or ""):match("^%s*%S+%s*(.-)%s*$")
		local dcbg = SlashCmdList.DCBG
		if dcbg ~= nil then dcbg(rest) end
	elseif cmd == "" then
		App.toggle()
	else
		local help = "/dchess - open/close, /dchess reset - new run, /dchess difficulty <1-5>, /dchess combat - toggle pause on combat"
		if ns.DEV then help = help .. ", /dchess fight <id>, /dchess bg and /dchess debug [on|off] (debug panel) - dev" end
		say(help)
	end
end
