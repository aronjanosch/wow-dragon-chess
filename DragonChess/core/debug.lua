local _, ns = ...
-- Debug helpers (W0-D1): the game-state side of the debug panel (ui/debug.lua), the model for the
-- Godot cheats in scenes/debug/debug_cheats.gd (F1 kill, F2 heal, F3 hurt, F4 boss, F5 next stage, F6 god
-- mode, F7 / F8 spawn skill / ult, convert 5 random). Pure Lua, no WoW API, no pcall (core rule: a
-- yield inside pcall breaks in WoW), so the UI wraps every call.
--
-- Every function takes the core objects it works on and returns `ok, message` (message = one line for the
-- chat). A function that changes the run marks it `run.dev = true` where a run is at hand: the UI never
-- writes records or the saved run for a dev run (ui/main.lua checks run.dev). Board work that waits
-- (convert, junk) runs as a sim coroutine (`sim:spawn`), exactly like an enemy ability would.
--
-- Tuning values live in Debug.STATUS (edit here / print from the panel): durations in seconds.

local min = math.min

local Debug = {}

-- Durations / parameters of the status buttons (Godot enemy ability data for Mirror / Sandstorm / Curse).
Debug.STATUS = {
	stun = 3.0, freeze = 3.0, player_stun = 3.0, heal_block = 8.0,
	curse_multiplier = 0.7, curse = 8.0,
	aegis = 7.0,
	mirror = 8.0, mirror_fraction = 0.6, mirror_break_damage = 500, mirror_break_stun = 1.0,
	sand_factor = 0.3, sand = 8.0,
}

Debug.HURT_AMOUNT = 2000 -- "hurt player" (Godot F3 hurt)
Debug.CONVERT_COUNT = 5 -- "convert N random" (Godot debug menu: 5)
Debug.JUNK_COUNT = 4

-- Status buttons in panel order: id, label, target ("enemy" | "player" | "board").
Debug.STATUS_LIST = {
	{ id = "stun", label = "Stun enemy", target = "enemy" },
	{ id = "freeze", label = "Freeze enemy", target = "enemy" },
	{ id = "aegis", label = "Aegis (enemy)", target = "enemy" },
	{ id = "mirror", label = "Mirror (enemy)", target = "enemy" },
	{ id = "player_stun", label = "Stun player", target = "player" },
	{ id = "heal_block", label = "Heal block", target = "player" },
	{ id = "curse", label = "Curse", target = "player" },
	{ id = "sand", label = "Sandstorm", target = "board" },
}

-- Own random stream for random cells (a cheat must not shift the fight's rolls; the shuffle below uses the
-- board's refill stream, which is fine for a dev run).
local rng = nil
function Debug.seed(n)
	rng = ns.Rng.new(n or 1)
end

local function stream()
	if rng == nil then Debug.seed(1) end
	return rng
end

local function mark(run)
	if run ~= nil then run.dev = true end
end
Debug.mark = mark

-- Enemy ids in ladder order (panel buttons, /dchess fight list).
function Debug.enemy_ids()
	local out = {}
	local list = ns.EnemyData.list
	for i = 1, #list do out[i] = list[i].id end
	return out
end

local function live_enemy(combat)
	if combat == nil or combat.enemy == nil or combat.game_over or combat.fight_over then return nil end
	return combat.enemy
end

---------------------------------------------------------------- fights

-- Starts enemy `id` now (and the following fights until a new run, run.forced). Works mid-fight and
-- between fights (the pending next fight is dropped). Returns ok, message.
function Debug.fight(run, combat, id)
	if run == nil or combat == nil then return false, "no run (open the window first)" end
	local def = ns.Enemy.STUBS[id]
	if def == nil then return false, "unknown enemy '" .. tostring(id) .. "'" end
	if run.over then return false, "this run is over (new run first)" end
	if combat.game_over then return false, "the player is dead (new run first)" end
	run:begin_fight(def)
	return true, "fight: " .. id
end

-- Kills the live enemy (Godot F1).
function Debug.kill_enemy(run, combat)
	local e = live_enemy(combat)
	if e == nil then return false, "no live enemy" end
	mark(run)
	local was = e.invincible
	e.invincible = false
	e:take_damage(e.current_health)
	e.invincible = was
	return true, "enemy killed"
end

-- Skips to the next fight at once: kills the live enemy (the run advances), then lets the between-fight
-- beat end now (the UI's run:update starts the fight on its next frame).
function Debug.next_fight(run, combat)
	if run == nil or combat == nil then return false, "no run" end
	if run.over then return false, "this run is over" end
	mark(run)
	if live_enemy(combat) ~= nil then
		local ok, why = Debug.kill_enemy(run, combat)
		if not ok then return false, why end
	end
	run.forced = nil -- back to the ladder (after the kill, so the boss heal rule saw the forced enemy)
	if run.next_at ~= nil then
		run.next_at = run.sim.now
		return true, "next fight"
	end
	return false, "no next fight (the run is over)"
end

-- Difficulty +/- (clamped 1..MAX); scales the NEXT fight (the live enemy keeps its numbers).
function Debug.difficulty(run, delta)
	if run == nil then return false, "no run" end
	mark(run)
	run.difficulty = ns.Run.clamp_difficulty(run.difficulty + delta)
	return true, "difficulty " .. run.difficulty .. " (from the next fight)"
end

---------------------------------------------------------------- player

function Debug.heal_player(run, combat, amount)
	if combat == nil then return false, "no run" end
	mark(run)
	local hp, mx = combat.player_health, combat.player_max_health
	local healed = combat:heal_player(amount or (mx - hp))
	if healed <= 0 then return false, "nothing to heal" end
	return true, "healed " .. healed
end

-- True damage that never kills (leaves 1 HP at least).
function Debug.hurt_player(run, combat, amount)
	if combat == nil then return false, "no run" end
	local hp = combat.player_health
	amount = min(amount or Debug.HURT_AMOUNT, hp - 1)
	if amount <= 0 then return false, "player has 1 HP" end
	mark(run)
	combat:take_true_damage(amount, "hit")
	return true, "hurt " .. amount
end

function Debug.toggle_god(run, combat)
	if combat == nil then return false, "no run" end
	mark(run)
	combat.god_mode = not combat.god_mode
	return true, "god mode " .. (combat.god_mode and "on" or "off")
end

---------------------------------------------------------------- statuses

-- Applies status `id` (Debug.STATUS_LIST). Needs a live enemy for the enemy ones.
function Debug.status(run, combat, id)
	if combat == nil then return false, "no run" end
	local S = Debug.STATUS
	local sim = combat.sim
	local e = live_enemy(combat)
	local entry
	for i = 1, #Debug.STATUS_LIST do
		if Debug.STATUS_LIST[i].id == id then entry = Debug.STATUS_LIST[i] end
	end
	if entry == nil then return false, "unknown status '" .. tostring(id) .. "'" end
	if entry.target == "enemy" and e == nil then return false, "no live enemy" end
	if combat.game_over then return false, "the player is dead" end
	mark(run)
	if id == "stun" then
		e:apply_stun(S.stun, "stun")
	elseif id == "freeze" then
		e:apply_stun(S.freeze, "freeze")
	elseif id == "aegis" then
		e:apply_spell_immunity(S.aegis)
	elseif id == "mirror" then
		e:apply_mirror_shield(S.mirror, S.mirror_fraction, S.mirror_break_damage, S.mirror_break_stun)
	elseif id == "player_stun" then
		combat:apply_player_stun(S.player_stun)
	elseif id == "heal_block" then
		combat:apply_heal_block(S.heal_block)
	elseif id == "curse" then
		combat:apply_damage_debuff(S.curse_multiplier, S.curse)
	else -- sand
		sim:set_gravity_slow(S.sand_factor, S.sand)
	end
	return true, entry.label
end

---------------------------------------------------------------- enemy dev switches (W0-P5)

-- Enemy takes no damage (Enemy.invincible; carried into the next fights via combat.enemy_invincible).
function Debug.toggle_invincible(run, combat)
	if combat == nil then return false, "no run" end
	mark(run)
	combat.enemy_invincible = not combat.enemy_invincible
	if combat.enemy ~= nil then combat.enemy.invincible = combat.enemy_invincible end
	return true, "enemy invincible " .. (combat.enemy_invincible and "on" or "off")
end

-- Freezes the enemy's attack cooldown + wind-ups (statuses keep running); carried into the next fights.
function Debug.toggle_enemy_timers(run, combat)
	if combat == nil then return false, "no run" end
	mark(run)
	combat.enemy_timers_held = not combat.enemy_timers_held
	if combat.enemy ~= nil then combat.enemy:set_timers_held(combat.enemy_timers_held) end
	return true, "enemy timers " .. (combat.enemy_timers_held and "paused" or "running")
end

---------------------------------------------------------------- live status dump

local function fmt_status(label, remaining, maxv)
	if remaining <= 0 then return nil end
	return ("%s %.1f/%.1f s"):format(label, remaining, maxv)
end

local function add(out, n, line)
	if line == nil then return n end
	n = n + 1
	out[n] = line
	return n
end

-- Fills `out` (array, reused by the caller) with one text line per live status / timer: player statuses
-- (remaining/max), board Sandstorm, enemy stun / slow / Aegis / Mirror, the enemy's attack timer and wind-up.
-- Returns the number of lines (the caller hides the rest). Called by the panel a few times a second, never per
-- frame; the strings are made per call.
function Debug.status_lines(combat, out)
	local n = 0
	if combat == nil then return add(out, 0, "no run") end
	local C = ns.Combat
	local sh = combat.status.shield.stacks
	if sh > 0 then n = add(out, n, "player shield x" .. sh) end
	local names = { fire_shield = "player fire shield", lifesteal = "player lifesteal", curse = "player curse",
		stun = "player stun", heal_block = "player heal block" }
	for i = 1, #C.TIMED_STATUSES do
		local id = C.TIMED_STATUSES[i]
		n = add(out, n, fmt_status(names[id], combat:status_remaining(id), combat:status_max(id)))
	end
	local sim = combat.sim
	n = add(out, n, fmt_status("board sandstorm", sim:get_gravity_slow_remaining(), sim.slow_max or 0))
	local e = combat.enemy
	if e == nil then return add(out, n, "no enemy") end
	n = add(out, n, e.name .. (e.dead and " (dead)" or "") .. (e.invincible and " INVINCIBLE" or "")
		.. (e.timers_held and " TIMERS PAUSED" or ""))
	n = add(out, n, fmt_status("enemy " .. (e:get_status_kind() ~= "" and e:get_status_kind() or "stun"),
		e:get_stun_remaining(), e:get_stun_duration_max()))
	n = add(out, n, fmt_status("enemy slow", e:get_slow_remaining(), e:get_slow_duration_max()))
	n = add(out, n, fmt_status("enemy aegis", e:get_immune_remaining(), e:get_immune_duration_max()))
	n = add(out, n, fmt_status("enemy mirror", e:get_mirror_remaining(), e:get_mirror_duration_max()))
	local nxt = e:get_time_to_next_attack()
	if nxt >= 0 then n = add(out, n, ("enemy attack in %.1f s"):format(nxt)) end
	local hit = e:get_time_to_next_hit()
	if e:is_winding_up() and hit >= 0 then n = add(out, n, ("enemy wind-up: hit lands in %.1f s"):format(hit)) end
	if e:is_executing() then n = add(out, n, "enemy executing (multi-step)") end
	if n == 0 then n = add(out, n, "nothing active") end
	return n
end

---------------------------------------------------------------- board

-- Settled plain gems (no ability / bomb / junk): the cells a cheat may overwrite.
local function plain_cells(board)
	local out = {}
	for c = 0, board.cols - 1 do
		for r = 0, board.rows - 1 do
			local gem = board:get(c, r)
			if gem ~= nil and gem.state == ns.Board.SETTLED and gem.tier == 0 and not gem.bomb and not gem.junk then
				out[#out + 1] = { c, r }
			end
		end
	end
	return out
end

-- Spawns a skill (tier 1) or ult (tier 2) gem of `color` (0..5) at a random settled plain cell
-- (Godot F7 / F8). Returns ok, message, col, row.
function Debug.spawn_gem(run, sim, color, tier)
	if sim == nil then return false, "no board" end
	local cells = plain_cells(sim.board)
	if #cells == 0 then return false, "no free cell right now" end
	local pick = cells[stream():range_i(1, #cells)]
	mark(run)
	sim:spawn_ability_gem(pick[1], pick[2], tier, color)
	return true, (tier == 2 and "ult" or "skill") .. " gem", pick[1], pick[2]
end

-- Converts `n` random plain gems to `color` (Godot debug menu "convert 5 random"). Board work: runs as
-- a sim coroutine (telegraph + morph).
function Debug.convert(run, sim, color, n)
	if sim == nil then return false, "no board" end
	mark(run)
	n = n or Debug.CONVERT_COUNT
	sim:spawn(function() sim:convert_random_gems(color, n) end)
	return true, "converting " .. n
end

-- Turns `n` random plain gems into bandage junk.
function Debug.junk(run, sim, n)
	if sim == nil then return false, "no board" end
	mark(run)
	n = n or Debug.JUNK_COUNT
	sim:spawn(function() sim:set_gems_junk(n) end)
	return true, "junk x" .. n
end

-- Re-rolls every plain gem (an unconditional shuffle; the board's own shuffle only runs when no move is
-- left) and keeps rolling until a move exists. Only at rest. Emits board_shuffled(ok) like the sim does.
function Debug.shuffle(run, sim)
	if sim == nil then return false, "no board" end
	if not sim:is_at_rest() then return false, "the board is busy" end
	mark(run)
	local board = sim.board
	for c = 0, board.cols - 1 do
		for r = 0, board.rows - 1 do
			local gem = board:get(c, r)
			if gem ~= nil and gem.tier == 0 and not gem.bomb and not gem.junk then
				ns.Board.set_gem_type(gem, board:roll_type())
			end
		end
	end
	board:clear_initial_matches()
	local ok = board:shuffle_board() -- no-op when a move exists
	sim:emit("board_shuffled", ok)
	return true, "shuffled"
end


ns.Debug = Debug
