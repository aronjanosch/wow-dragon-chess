-- core/debug.lua (W0-D1): every helper of the debug panel against the real sim / combat / run: it does what
-- it says, marks the run as a dev run (no records / saves, checked by ui/main.lua), never kills the player,
-- needs a live enemy where it should, and board work runs as sim coroutines.
local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "."
local H = dofile(dir .. "/helpers.lua")
local T, ns = H.T, H.ns
local Sim, Combat, Run, Debug = ns.Sim, ns.Combat, ns.Run, ns.Debug
T.start("debug_test")

local DT = 1 / 30

local function new_run(seed, difficulty)
	local sim = Sim.new({ seed = seed })
	local c = Combat.new({ sim = sim, seed = seed })
	local run = Run.new({ combat = c, difficulty = difficulty or 1 })
	run:begin_fight()
	return sim, c, run
end

local function tick(sim, run, secs)
	local t_end = sim.now + secs
	while sim.now < t_end do
		sim:tick(DT)
		run:update()
	end
end

local function count(sim, pred)
	local n = 0
	local b = sim.board
	for c = 0, b.cols - 1 do
		for r = 0, b.rows - 1 do
			local g = b:get(c, r)
			if g ~= nil and pred(g) then n = n + 1 end
		end
	end
	return n
end

T.case("enemy ids = the ladder order", function()
	local ids = Debug.enemy_ids()
	T.eq(#ids, 10, "ten enemies")
	T.eq(ids[1], "hellhound", "first")
	T.eq(ids[10], "nefarian", "last")
	for i = 1, 10 do T.eq(ids[i], ns.EnemyData.list[i].id, "id " .. i) end
end)

T.case("fight: any enemy now, mid-fight and between fights; refuses unknown ids and finished runs", function()
	local sim, c, run = new_run(11)
	T.ok(not run.dev, "a fresh run is not a dev run")
	local ok, msg = Debug.fight(run, c, "nobody")
	T.ok(not ok and msg:find("unknown") ~= nil, "unknown id refused: " .. tostring(msg))
	T.ok(not run.dev, "a refused fight does not mark the run")
	ok, msg = Debug.fight(run, c, "nefarian")
	T.ok(ok and msg == "fight: nefarian", "nefarian started mid-fight: " .. tostring(msg))
	T.eq(c.enemy.def.id, "nefarian", "enemy replaced")
	T.ok(run.dev and run.forced ~= nil, "dev run, forced def")
	tick(sim, run, 0.5)
	-- between fights (kill, the next fight is pending): the dev fight replaces it
	c.enemy:take_damage(c.enemy.current_health)
	T.ok(c.fight_over and run.next_at ~= nil, "killed: next fight pending")
	ok = Debug.fight(run, c, "hakkar")
	T.ok(ok and run.next_at == nil and not c.fight_over, "between fights: hakkar starts, pending fight dropped")
	T.eq(c.enemy.def.id, "hakkar", "hakkar")
	tick(sim, run, 3)
	T.eq(c.enemy.def.id, "hakkar", "no ladder fight replaces it")
	-- game over / run over
	c.game_over = true
	ok, msg = Debug.fight(run, c, "harpy")
	T.ok(not ok and msg:find("dead") ~= nil, "dead player: refused")
	c.game_over = false
	run.over = "lost"
	ok, msg = Debug.fight(run, c, "harpy")
	T.ok(not ok and msg:find("over") ~= nil, "finished run: refused")
	T.ok(not Debug.fight(nil, nil, "harpy"), "no run: refused")
end)

T.case("kill enemy / next fight", function()
	local sim, c, run = new_run(12)
	local defeated = 0
	c:on("enemy_defeated", function() defeated = defeated + 1 end)
	c.enemy.invincible = true
	local ok = Debug.kill_enemy(run, c)
	T.ok(ok and defeated == 1 and c.fight_over and c.enemy.dead, "an invincible enemy is killed too")
	T.ok(c.enemy.invincible, "invincibility flag restored")
	T.ok(run.dev, "dev run")
	T.ok(not Debug.kill_enemy(run, c), "no live enemy: refused")
	-- next fight: ends the beat now, forced def dropped
	run.forced = ns.Enemy.STUBS.nefarian
	ok = Debug.next_fight(run, c)
	T.ok(ok and run.next_at == sim.now and run.forced == nil, "the between-fight beat ends now, ladder again")
	tick(sim, run, DT * 2)
	T.eq(c.enemy.def.id, "gordok_ogre", "the ladder fight 2 follows the kill of fight 1")
end)

T.case("next fight kills a live enemy first", function()
	local sim, c, run = new_run(13)
	local ok = Debug.next_fight(run, c)
	T.ok(ok and run.index == 2, "advanced to fight 2")
	tick(sim, run, DT * 2)
	T.eq(c.enemy.def.id, "gordok_ogre", "fight 2 live")
	T.ok(run.dev, "dev run")
end)

T.case("difficulty +/- clamps and applies to the next fight", function()
	local _, c, run = new_run(14)
	local hp1 = c.enemy.max_health
	local ok, msg = Debug.difficulty(run, -1)
	T.ok(ok and run.difficulty == 1 and msg:find("difficulty 1") ~= nil, "min 1")
	Debug.difficulty(run, 1)
	T.eq(run.difficulty, 2, "+1")
	for _ = 1, 10 do Debug.difficulty(run, 1) end
	T.eq(run.difficulty, Run.MAX_DIFFICULTY, "capped at the maximum")
	T.eq(c.enemy.max_health, hp1, "the live enemy keeps its numbers")
	T.ok(run.dev, "dev run")
end)

T.case("player: heal, hurt (never lethal), god mode", function()
	local _, c, run = new_run(15)
	local ok, msg = Debug.heal_player(run, c)
	T.ok(not ok and msg:find("nothing") ~= nil, "full HP: nothing to heal")
	ok = Debug.hurt_player(run, c)
	T.ok(ok and c.player_health == c.player_max_health - Debug.HURT_AMOUNT, "hurt by HURT_AMOUNT")
	ok = Debug.heal_player(run, c)
	T.ok(ok and c.player_health == c.player_max_health, "healed to full")
	c.player_health = 500
	ok = Debug.hurt_player(run, c)
	T.ok(ok and c.player_health == 1 and not c.game_over, "hurt leaves 1 HP, never kills")
	ok, msg = Debug.hurt_player(run, c)
	T.ok(not ok and c.player_health == 1, "at 1 HP: refused")
	ok, msg = Debug.toggle_god(run, c)
	T.ok(ok and c.god_mode and msg == "god mode on", "god on")
	Debug.toggle_god(run, c)
	T.ok(not c.god_mode, "god off")
	T.ok(run.dev, "dev run")
end)

T.case("statuses: enemy, player, board", function()
	local sim, c, run = new_run(16)
	local S = Debug.STATUS
	local e = c.enemy
	T.ok(Debug.status(run, c, "stun"), "stun")
	T.ok(e:get_stun_remaining() > 0 and e:get_status_kind() == "stun", "enemy stunned")
	T.ok(Debug.status(run, c, "freeze"), "freeze")
	T.eq(e:get_status_kind(), "freeze", "enemy frozen")
	T.ok(Debug.status(run, c, "aegis") and e:is_spell_immune(), "Divine Aegis")
	T.ok(Debug.status(run, c, "mirror") and e:is_mirror_up(), "Mirror Shield")
	T.ok(Debug.status(run, c, "player_stun") and c:status_remaining("stun") > 0, "player stun")
	T.ok(Debug.status(run, c, "heal_block") and c:status_remaining("heal_block") > 0, "heal block")
	T.ok(Debug.status(run, c, "curse") and c:curse_multiplier() == S.curse_multiplier, "curse")
	T.ok(Debug.status(run, c, "sand") and sim:get_gravity_slow_remaining() > 0, "Sandstorm")
	local ok, msg = Debug.status(run, c, "bogus")
	T.ok(not ok and msg:find("unknown") ~= nil, "unknown status refused")
	T.eq(#Debug.STATUS_LIST, 8, "eight status buttons")
	-- no live enemy: enemy statuses refused, player ones work
	e:take_damage(e.current_health)
	ok, msg = Debug.status(run, c, "stun")
	T.ok(not ok and msg == "no live enemy", "enemy status needs a live enemy")
	T.ok(Debug.status(run, c, "curse"), "player status without an enemy")
	tick(sim, run, S.sand + 1)
	T.ok(sim:get_gravity_slow_remaining() == 0, "Sandstorm ends on sim time")
	T.ok(run.dev, "dev run")
end)

T.case("board: spawn skill / ult gems at a settled plain cell", function()
	local sim, _, run = new_run(17)
	Debug.seed(5)
	T.ok(sim:is_at_rest() or H.run(sim, DT, 10), "board at rest")
	local spawned = {}
	sim:on("ability_gem_spawned", function(col, row, tier, gem_type) spawned[#spawned + 1] = { col, row, tier, gem_type } end)
	local ok, msg, col, row = Debug.spawn_gem(run, sim, 3, 1)
	T.ok(ok and msg == "skill gem" and col ~= nil, "skill gem spawned: " .. tostring(msg))
	local g = sim.board:get(col, row)
	T.ok(g.tier == 1 and g.type == 3 and g.protected and not g.bomb and not g.junk, "skill gem of colour 3, spawn-protected")
	ok, msg, col, row = Debug.spawn_gem(run, sim, 5, 2)
	g = sim.board:get(col, row)
	T.ok(ok and msg == "ult gem" and g.tier == 2 and g.type == 5, "ult gem of colour 5")
	T.eq(#spawned, 2, "ability_gem_spawned emitted for the view")
	-- a board full of ability gems has no free cell
	local b = sim.board
	for c = 0, b.cols - 1 do
		for r = 0, b.rows - 1 do b:get(c, r).tier = 1 end
	end
	ok, msg = Debug.spawn_gem(run, sim, 0, 1)
	T.ok(not ok and msg:find("free") ~= nil, "no free cell: refused")
	T.ok(run.dev, "dev run")
end)

T.case("board: convert N random, junk run as sim coroutines", function()
	local sim, _, run = new_run(18)
	T.ok(H.run(sim, DT, 10), "board at rest")
	local before = table.concat(H.rows(sim.board), "/")
	local junk_events = 0
	sim:on("junk_spawned", function() junk_events = junk_events + 1 end)
	local ok = Debug.convert(run, sim, 2, 5)
	T.ok(ok, "convert started")
	tick(sim, run, 5)
	T.ok(H.run(sim, DT, 30), "settles again")
	T.ok(table.concat(H.rows(sim.board), "/") ~= before, "the board changed")
	ok = Debug.junk(run, sim, 4)
	T.ok(ok, "junk started")
	tick(sim, run, 5)
	T.eq(junk_events, 1, "junk_spawned once")
	T.ok(count(sim, function(g) return g.junk end) >= 1, "junk gems on the board")
	T.ok(not Debug.convert(run, nil, 1, 5) and not Debug.junk(run, nil), "no board: refused")
	T.ok(run.dev, "dev run")
end)

T.case("board: forced shuffle re-rolls the plain gems, only at rest", function()
	local sim, _, run = new_run(19)
	T.ok(H.run(sim, DT, 10), "board at rest")
	local before = table.concat(H.rows(sim.board), "/")
	local shuffled = {}
	sim:on("board_shuffled", function(ok) shuffled[#shuffled + 1] = ok end)
	local ok = Debug.shuffle(run, sim)
	T.ok(ok and #shuffled == 1 and shuffled[1] == true, "shuffled, board_shuffled(true) emitted")
	T.ok(table.concat(H.rows(sim.board), "/") ~= before, "the board changed")
	T.ok(select("#", ns.Match.find_possible_move(sim.board)) == 4, "a move exists afterwards")
	T.eq(#ns.Match.find_matches(sim.board), 0, "no match left standing")
	-- busy: a swap in flight
	local c1, r1, c2, r2 = ns.Match.find_possible_move(sim.board)
	sim:try_swap_cells(c1, r1, c2, r2)
	T.ok(not sim:is_at_rest(), "a swap is in flight")
	do
		local ok2, msg = Debug.shuffle(run, sim)
		T.ok(not ok2 and msg:find("busy") ~= nil, "busy board: refused")
	end
end)

T.case("W0-P5: invincible enemy takes no damage, carries into the next fight, marks the run", function()
	local sim, c, run = new_run(31)
	T.ok(not run.dev, "fresh run")
	local ok, msg = Debug.toggle_invincible(run, c)
	T.ok(ok and run.dev and c.enemy.invincible and c.enemy_invincible and msg:find("on") ~= nil, "on: " .. tostring(msg))
	local hp = c.enemy.current_health
	c:deal_damage_to_enemy(500)
	T.eq(c.enemy.current_health, hp, "no damage taken")
	-- the next fight inherits the flag
	Debug.kill_enemy(run, c) -- kill still works (it lifts the flag for the hit)
	T.ok(c.fight_over, "killed anyway")
	tick(sim, run, 4)
	T.ok(c.enemy.invincible, "the next enemy is invincible too")
	ok, msg = Debug.toggle_invincible(run, c)
	T.ok(ok and not c.enemy.invincible and not c.enemy_invincible, "off")
	T.ok(not Debug.toggle_invincible(nil, nil), "no run: refused")
end)

T.case("W0-P5: enemy timers paused keeps cooldown and wind-up frozen, resumes with the remaining time", function()
	local sim, c, run = new_run(32)
	c.god_mode = true
	local e = c.enemy
	tick(sim, run, 0.5)
	local left = e:get_time_to_next_attack()
	T.ok(left > 0, "an attack is pending: " .. left)
	local windups = 0
	sim:on("enemy_windup", function() windups = windups + 1 end)
	local ok, msg = Debug.toggle_enemy_timers(run, c)
	T.ok(ok and run.dev and e.timers_held and msg:find("paused") ~= nil, "paused: " .. tostring(msg))
	tick(sim, run, 30)
	T.eq(windups, 0, "no wind-up while paused")
	T.ok(math.abs(e:get_time_to_next_attack() - left) < 1e-6, "cooldown frozen at " .. left)
	-- release: it resumes with the remaining time
	Debug.toggle_enemy_timers(run, c)
	T.ok(not e.timers_held, "released")
	tick(sim, run, left - 0.05)
	T.eq(windups, 0, "not yet")
	tick(sim, run, 0.2)
	T.eq(windups, 1, "wind-up starts after the remaining time")
	-- hold during a wind-up: the hit does not land until released
	local hits = 0
	sim:on("enemy_ability_executed", function() hits = hits + 1 end)
	Debug.toggle_enemy_timers(run, c)
	T.ok(e:is_winding_up(), "wind-up in flight")
	local hl = e:get_time_to_next_hit()
	tick(sim, run, 20)
	T.eq(hits, 0, "held wind-up never lands")
	T.ok(math.abs(e:get_time_to_next_hit() - hl) < 1e-6, "wind-up frozen")
	Debug.toggle_enemy_timers(run, c)
	tick(sim, run, hl + 0.1)
	T.eq(hits, 1, "lands after release")
	-- the flag carries into the next fight, and a status (stun) still runs while held
	Debug.toggle_enemy_timers(run, c)
	Debug.kill_enemy(run, c)
	tick(sim, run, 4)
	T.ok(c.enemy ~= e and c.enemy.timers_held, "next enemy starts with paused timers")
	local ne = c.enemy
	ne:apply_stun(2, "stun")
	tick(sim, run, 2.5)
	T.ok(ne:get_stun_remaining() <= 0 and ne.is_active, "the stun ran out while the timers were held")
	T.ok(ne:get_time_to_next_attack() > 0, "cooldown still held after the stun")
	T.ok(not Debug.toggle_enemy_timers(nil, nil), "no run: refused")
end)

T.case("W0-P5: clock hold survives freeze / thaw", function()
	local sim, c = new_run(33)
	local e = c.enemy
	local left = e:get_time_to_next_attack()
	e:set_timers_held(true)
	c:settle_now() -- freeze + thaw
	T.ok(math.abs(e:get_time_to_next_attack() - left) < 1e-6, "still frozen after settle_now")
	e:set_timers_held(false)
	T.ok(e:get_time_to_next_attack() > 0, "running again")
end)

T.case("W0-P5: status_lines lists live statuses, enemy timers and flags", function()
	local sim, c, run = new_run(34)
	local out = {}
	local n = Debug.status_lines(c, out)
	local function has(sub)
		for i = 1, n do
			if out[i]:find(sub, 1, true) then return true end
		end
		return false
	end
	T.ok(has("enemy attack in"), "attack timer listed")
	Debug.status(run, c, "curse")
	Debug.status(run, c, "stun")
	Debug.status(run, c, "aegis")
	Debug.status(run, c, "sand")
	Debug.status(run, c, "heal_block")
	c.status.shield.stacks = 2
	Debug.toggle_invincible(run, c)
	Debug.toggle_enemy_timers(run, c)
	n = Debug.status_lines(c, out)
	T.ok(has("player curse 8.0/8.0"), "curse remaining/max: " .. table.concat(out, " | "))
	T.ok(has("player heal block"), "heal block")
	T.ok(has("player shield x2"), "shield stacks")
	T.ok(has("enemy stun"), "enemy stun")
	T.ok(has("enemy aegis"), "aegis")
	T.ok(has("board sandstorm"), "sandstorm")
	T.ok(has("INVINCIBLE") and has("TIMERS PAUSED"), "flags in the enemy line")
	tick(sim, run, 2)
	Debug.status_lines(c, out)
	T.ok(out[1]:find("player") ~= nil, "lines refilled in the same table")
	c.enemy = nil
	n = Debug.status_lines(c, out)
	T.ok(has("no enemy"), "no enemy line")
	T.eq(Debug.status_lines(nil, out), 1, "no combat: one line")
end)

T.done()
