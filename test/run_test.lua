-- Run ladder / difficulty / records (W0-G2b): ladder order and stage labels, scaled COPIES
-- (data/enemies.lua deep-compared after D1-D5), boss heal rules, between-fight beat, records
-- and unlocks (win AND loss), snapshot, a fight transition with an enemy killed mid-junk-
-- telegraph, and a full 10-fight god-mode bot run on two seeds / difficulties.
local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "."
local H = dofile(dir .. "/helpers.lua")
local T, ns = H.T, H.ns
local Sim, Combat, Match, Run, Data = ns.Sim, ns.Combat, ns.Match, ns.Run, ns.EnemyData
T.start("run_test")

local DT = 1 / 30

-- The literals below are the unpaced Godot values; ATTACK_PACE has its own test at the end.
local PACE = Run.ATTACK_PACE
Run.ATTACK_PACE = 1
local DMG_SCALE = Run.ENEMY_DAMAGE_SCALE
Run.ENEMY_DAMAGE_SCALE = 1

local function deep_copy(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do out[k] = deep_copy(v) end -- order irrelevant (copy)
	return out
end

local function deep_equal(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	for k, v in pairs(a) do
		if not deep_equal(v, b[k]) then return false end
	end
	for k in pairs(b) do
		if a[k] == nil then return false end
	end
	return true
end

local function new_run(seed, difficulty, index)
	local sim = Sim.new({ seed = seed })
	local c = Combat.new({ sim = sim, seed = seed })
	local run = Run.new({ combat = c, difficulty = difficulty, index = index })
	return sim, c, run
end

local function step(sim, run)
	sim:tick(DT)
	run:update()
end

local function tick_until(sim, run, pred, limit)
	local t_end = sim.now + (limit or 30)
	while sim.now < t_end do
		if pred() then return true end
		step(sim, run)
	end
	return pred()
end

local function kill(c)
	c.enemy:take_damage(c.enemy.current_health)
end

---------------------------------------------------------------- ladder

T.case("ladder order, stages, labels", function()
	local want = { "hellhound", "gordok_ogre", "basilisk_matriarch", "forest_troll", "harpy", "hakkar", "qiraji_scarab", "anubisath_sentinel", "ouro", "nefarian" }
	local labels = { "STAGE 1-1", "STAGE 1-2", "STAGE 1-3", "STAGE 2-1", "STAGE 2-2", "STAGE 2-3", "STAGE 3-1", "STAGE 3-2", "STAGE 3-3", "STAGE 4-1" }
	local bosses = { false, false, true, false, false, true, false, false, true, true }
	T.eq(Run.fight_count(), 10, "10 fights")
	local sim, c, run = new_run(1, 1)
	for i = 1, 10 do
		run.index = i
		T.eq(run:base_def().id, want[i], "fight " .. i .. " enemy")
		T.eq(run:label(), labels[i], "fight " .. i .. " label")
		T.eq(run:is_boss(), bosses[i], "fight " .. i .. " boss flag")
		T.eq(run:stage(), i <= 9 and math.floor((i - 1) / 3) + 1 or 4, "fight " .. i .. " stage")
	end
	-- the ladder is the data order, nothing else
	for i = 1, 10 do T.eq(Run.ladder()[i].def, Data.list[i], "ladder #" .. i .. " is the data entry") end
	T.ok(c.enemy == nil and not run.over, "a new run has not started a fight yet")
	T.eq(sim.now, 0, "no time passed")
end)

---------------------------------------------------------------- scaling

T.case("difficulty multipliers and scaled copies", function()
	local before = deep_copy(Data.list)
	local ab_before = deep_copy(Data.abilities)
	local hp_want = { 1.0, 1.15, 1.3, 1.45, 1.6 }
	local dmg_want = { 1.0, 1.2, 1.4, 1.6, 1.8 }
	for d = 1, 5 do
		local hp_m, dmg_m = Run.multipliers(d)
		T.ok(math.abs(hp_m - hp_want[d]) < 1e-9, "D" .. d .. " HP x" .. hp_want[d])
		T.ok(math.abs(dmg_m - dmg_want[d]) < 1e-9, "D" .. d .. " damage x" .. dmg_want[d])
		for i = 1, #Data.list do
			local def = Data.list[i]
			local s = Run.scale_def(def, d)
			T.ok(s ~= def and s.rotation ~= def.rotation, def.id .. " D" .. d .. ": a copy")
			T.eq(s.max_health, ns.StatusMath.round(def.max_health * hp_m), def.id .. " D" .. d .. " max HP")
			T.eq(s.id, def.id, "identity fields copied")
			T.eq(s.windup, def.windup, "wind-up not scaled")
			T.eq(s.weak_to_color, def.weak_to_color, "weakness copied")
			T.eq(#s.rotation, #def.rotation, "rotation length")
			for k = 1, #def.rotation do
				local o, n = def.rotation[k], s.rotation[k]
				T.ok(n ~= o, def.id .. " ability copied")
				T.eq(n.damage_min, ns.StatusMath.round(o.damage_min * dmg_m), o.id .. " D" .. d .. " damage_min")
				T.eq(n.damage_max, ns.StatusMath.round(o.damage_max * dmg_m), o.id .. " D" .. d .. " damage_max")
				T.ok(n.damage_max >= n.damage_min, "max >= min")
				T.eq(n.cooldown, o.cooldown, "cooldown not scaled")
				T.eq(n.duration, o.duration, "duration not scaled")
				T.eq(n.stun_duration, o.stun_duration, "stun_duration not scaled")
				T.eq(n.heal_percent, o.heal_percent, "heal_percent not scaled")
				T.eq(n.hit_interval, o.hit_interval, "hit_interval not scaled")
				T.eq(n.hit_count_max, o.hit_count_max, "hit counts not scaled")
				T.eq(n.kind, o.kind, "kind kept")
				T.eq(n.is_special, o.is_special, "is_special kept")
				if o.kind == "mirror" then
					T.eq(n.break_damage, ns.StatusMath.round(o.break_damage * hp_m), o.id .. " D" .. d .. " break_damage scales with HP")
				end
			end
		end
	end
	T.ok(deep_equal(before, Data.list), "data/enemies.lua unchanged after D1-D5")
	T.ok(deep_equal(ab_before, Data.abilities), "ability table unchanged after D1-D5")
end)

T.case("scaled copy: golden numbers, shared abilities scaled once, phases", function()
	local cy = Run.scale_def(Data.by_id.gordok_ogre, 3) -- HP x1.3, damage x1.4
	T.eq(cy.max_health, 4875, "Gordok Ogre D3 HP 3750 x 1.3")
	T.eq(cy.rotation[1].damage_min, 252, "Ogre Punch min 180 x 1.4")
	T.eq(cy.rotation[1].damage_max, 336, "Ogre Punch max 240 x 1.4")
	T.eq(cy.rotation[2].damage_min, 672, "Ogre Smash min 480 x 1.4")
	T.eq(cy.rotation[2].stun_duration, 2.5, "stagger duration unchanged")
	local me = Run.scale_def(Data.by_id.basilisk_matriarch, 5) -- HP x1.6
	T.eq(me.rotation[4].break_damage, 800, "Mirror break_damage 500 x 1.6")
	T.eq(me.rotation[4].damage_min, 0, "0-damage ability stays 0")
	T.eq(me.rotation[1], me.rotation[3], "Snake Jab appears twice in the rotation: one copy")
	local wd = Run.scale_def(Data.by_id.nefarian, 2) -- HP x1.15, damage x1.2
	T.eq(wd.max_health, 15812, "Nefarian D2 HP 13750 x 1.15 (= 15812.5 in doubles: 15812, as in Godot)")
	T.ok(wd.phases ~= Data.by_id.nefarian.phases, "phases copied")
	T.eq(wd.phases[1].hp_fraction, 0.66, "phase threshold kept")
	T.eq(wd.phases[1].phase_name, "Shadow Flame", "phase name kept")
	T.eq(wd.phases[1].rotation[3], wd.rotation[1], "Wing Buffet shared by the base rotation and phase 1: one copy")
	T.eq(wd.rotation[1].damage_min, 480, "Wing Buffet min 400 x 1.2 (shared copy scaled once, not twice)")
	T.eq(wd.phases[2].rotation[3].break_damage, 575, "Corrupted mirror 500 x 1.15 (round half up)")
	T.eq(wd.phases[1].rotation[1].damage_min, 144, "flurry per-hit damage scales: 120 x 1.2")
	T.ok(Data.by_id.nefarian.phases[1].rotation[3] == Data.by_id.nefarian.rotation[1], "originals still share it")
	T.eq(Data.by_id.nefarian.rotation[1].damage_min, 400, "original untouched")
	-- D1 is a copy too (nothing may mutate the cached data)
	local p = Run.scale_def(Data.by_id.hellhound, 1)
	T.ok(p.rotation[1] ~= Data.by_id.hellhound.rotation[1], "D1 copies as well")
	T.eq(p.rotation[1].damage_min, 75, "D1 values equal")
	-- clamp: max never below min
	local fake = { id = "x", max_health = 100, rotation = { { id = "a", kind = "plain", damage_min = 10, damage_max = 4, cooldown = 1 } } }
	T.eq(Run.scale_def(fake, 1).rotation[1].damage_max, 10, "damage_max clamped to damage_min")
end)

---------------------------------------------------------------- records

T.case("records: best on win and loss, unlock on win only", function()
	local db = {}
	T.eq(Run.unlocked(db), 1, "fresh DB: only D1")
	T.eq(Run.best_score(db, 1), 0, "no best yet")
	T.ok(Run.can_choose(db, 1) and not Run.can_choose(db, 2), "D2 locked")
	local nb, un = Run.record_result(db, 1, 0, false)
	T.ok(not nb and un == nil, "a 0 score is no best")
	nb, un = Run.record_result(db, 1, 1200, false)
	T.ok(nb and un == nil, "a loss records the best score")
	T.eq(Run.best_score(db, 1), 1200, "best 1200")
	T.eq(Run.unlocked(db), 1, "a loss does not unlock")
	nb = Run.record_result(db, 1, 900, false)
	T.ok(not nb and Run.best_score(db, 1) == 1200, "a lower score keeps the best")
	nb, un = Run.record_result(db, 1, 5000, true)
	T.ok(nb and un == 2, "a win: new best + D2 unlocked")
	T.eq(db.unlocked, 2, "db.unlocked")
	T.eq(db.records[1].wins, 1, "win counted")
	T.eq(db.records[1].runs, 4, "runs counted")
	T.ok(Run.can_choose(db, 2) and not Run.can_choose(db, 3), "D2 choosable, D3 locked")
	nb, un = Run.record_result(db, 1, 7000, true)
	T.ok(nb and un == nil, "winning D1 again does not unlock again")
	nb, un = Run.record_result(db, 2, 100, true)
	T.ok(nb and un == 3, "D2 win unlocks D3")
	T.eq(Run.best_score(db, 2), 100, "per-difficulty best")
	T.eq(Run.best_score(db, 1), 7000, "D1 best untouched")
	for _ = 1, 6 do Run.record_result(db, 5, 1, true) end
	T.eq(Run.unlocked(db), 5, "unlock capped at D5")
	T.ok(Run.can_choose(db, 5) and not Run.can_choose(db, 6) and not Run.can_choose(db, 0) and not Run.can_choose(db, 2.5), "choosable range")
	-- corrupt SavedVariables values are tolerated
	local bad = { unlocked = "x", records = "y" }
	T.eq(Run.unlocked(bad), 1, "corrupt unlocked -> 1")
	T.eq(Run.best_score(bad, 1), 0, "corrupt records -> 0")
	nb = Run.record_result(bad, 1, 10, false)
	T.ok(nb and Run.best_score(bad, 1) == 10, "corrupt records replaced on the next result")
	local bad2 = { unlocked = 99, records = { [1] = "z" } }
	T.eq(Run.unlocked(bad2), 5, "unlocked clamped")
	Run.record_result(bad2, 1, 5, false)
	T.eq(Run.best_score(bad2, 1), 5, "corrupt record entry replaced")
	T.eq(Run.clamp_difficulty(nil), 1, "nil difficulty -> 1")
	T.eq(Run.clamp_difficulty(0), 1, "0 -> 1")
	T.eq(Run.clamp_difficulty(9), 5, "9 -> 5")
	T.eq(Run.clamp_difficulty("3"), 3, "'3' -> 3")
end)

---------------------------------------------------------------- snapshot

T.case("ladder snapshot round-trip and validation", function()
	local _, c, run = new_run(2, 3, 7)
	local snap = run:serialize()
	T.eq(snap.v, Run.SNAPSHOT_VERSION, "version")
	local sim2 = Sim.new({ seed = 2 })
	local c2 = Combat.new({ sim = sim2, seed = 2 })
	local r2 = Run.deserialize(snap, c2)
	T.ok(r2 ~= nil and r2.difficulty == 3 and r2.index == 7, "restored D3 fight 7")
	T.eq(r2:label(), "STAGE 3-1", "label after restore")
	T.eq(c.enemy, nil, "serialize touches nothing")
	local bad = {
		"x", {}, { v = 99, difficulty = 1, index = 1 }, { v = 1, difficulty = 0, index = 1 },
		{ v = 1, difficulty = 6, index = 1 }, { v = 1, difficulty = 1, index = 0 }, { v = 1, difficulty = 1, index = 11 },
		{ v = 1, difficulty = 1.5, index = 1 }, { v = 1, difficulty = "a", index = 1 }, { v = 1, difficulty = 1 },
	}
	for i, b in ipairs(bad) do T.ok(Run.deserialize(b, c2) == nil, "bad ladder snapshot #" .. i .. " rejected") end
end)

---------------------------------------------------------------- flow

T.case("fight flow: heal rules, between-fight beat, stage labels, score carry, win", function()
	local sim, c, run = new_run(7, 3)
	local log = {}
	sim:on("run_fight_starting", function(r, def)
		log[#log + 1] = "starting " .. def.id
		if #log == 1 then T.ok(c.enemy == nil, "run_fight_starting fires before combat:start_fight") end
	end)
	sim:on("run_advanced", function(result, index) log[#log + 1] = result .. " " .. index end)
	sim:on("run_won", function() log[#log + 1] = "won" end)
	local healed = {}
	c:on("player_healed", function(n) healed[#healed + 1] = n end)

	run:begin_fight()
	T.eq(c.enemy.def.id, "hellhound", "fight 1")
	T.eq(c.enemy.max_health, math.floor(2250 * 1.3 + 0.5), "D3 HP applied to the enemy (2925)")
	T.eq(c.enemy_def.rotation[1].damage_min, 105, "D3 damage applied (75 x 1.4)")
	T.ok(c.enemy_def ~= Data.by_id.hellhound, "the fight runs on a copy")
	T.eq(log[1], "starting hellhound", "event log")

	-- normal kill: no heal, next fight only after the 1.75 s beat
	c.score = 777
	c.player_health = 4000
	for _ = 1, 30 do step(sim, run) end -- some time passes (gameplay paused by the kill only afterwards)
	local t_kill = sim.now
	kill(c)
	T.ok(c.fight_over, "fight over")
	T.eq(c.player_health, 4000, "no heal after a normal fight")
	T.eq(run.index, 2, "advanced at the kill")
	T.eq(run:label(), "STAGE 1-2", "label of the next fight")
	T.ok(run.next_at ~= nil and math.abs(run.next_at - (t_kill + Run.FIGHT_TRANSITION)) < 1e-9, "next fight at kill + 1.75 s")
	T.ok(tick_until(sim, run, function() return sim.now >= t_kill + Run.FIGHT_TRANSITION - 0.1 end, 3), "just before the beat ends")
	T.eq(c.enemy.def.id, "hellhound", "still the dead hellhound 0.1 s before the beat ends")
	T.ok(tick_until(sim, run, function() return c.enemy.def.id == "gordok_ogre" end, 1), "Gordok Ogre starts after the beat")
	T.ok(sim.now >= t_kill + Run.FIGHT_TRANSITION, "not earlier than 1.75 s")
	T.eq(c.score, 777, "score carried")
	T.eq(c.player_health, 4000, "HP carried")
	T.ok(not c.fight_over and not c.paused_by_kill, "gameplay resumed")

	-- the boss heals +25 % of max HP (before the next fight snapshot), capped
	run.index = 3
	run:begin_fight()
	T.eq(c.enemy.def.id, "basilisk_matriarch", "boss fight")
	c.player_health = 5000
	local advanced_heal
	local on_adv = function(_, _, heal) advanced_heal = heal end
	sim:on("run_advanced", on_adv)
	local t_boss = sim.now
	kill(c)
	sim:off("run_advanced", on_adv)
	T.eq(advanced_heal, 2500, "run_advanced carries the heal amount")
	T.ok(math.abs(run.next_at - (t_boss + Run.FIGHT_TRANSITION + Run.HEAL_MOMENT)) < 1e-9, "W0-P11: boss kill with a heal: next fight at +6.75 s")
	T.eq(Run.HEAL_MOMENT, 5.0, "heal moment 5.0 s")
	T.ok(tick_until(sim, run, function() return sim.now >= t_boss + 6.65 end, 7), "just before the boss beat ends")
	T.ok(c.fight_over, "still between fights at +6.65 s")
	T.eq(c.player_health, 7500, "boss heal +2500")
	T.eq(healed[#healed], 2500, "player_healed event")
	T.eq(log[#log], "stage_complete 4", "stage_complete after the stage 1 boss")
	T.eq(run:label(), "STAGE 2-1", "stage 2 label")
	T.eq(run:stage(), 2, "stage 2")
	-- heal block does not stop it; the cap works
	run.index = 6
	run:begin_fight()
	T.eq(c.enemy.def.id, "hakkar", "Hakkar")
	c.player_health = 9000
	c:apply_heal_block(15)
	kill(c)
	T.eq(c.player_health, 10000, "boss heal capped at max HP (Heal Block ignored, like Godot)")
	T.eq(healed[#healed], 1000, "only the missing 1000 reported")
	run.index = 9
	run:begin_fight()
	c.player_health = 10000
	local n_heals = #healed
	local t_full = sim.now
	kill(c)
	T.eq(#healed, n_heals, "full HP: no heal event")
	T.ok(math.abs(run.next_at - (t_full + Run.FIGHT_TRANSITION)) < 1e-9, "full HP: no heal moment, normal 1.75 s beat")
	T.eq(run.index, 10, "stage 3 -> Nefarian")
	T.eq(log[#log], "stage_complete 10", "stage_complete before stage 4")

	-- the last boss: run won, no heal, no next fight
	T.ok(tick_until(sim, run, function() return c.enemy.def.id == "nefarian" end, 3), "Nefarian starts")
	T.eq(c.enemy.max_health, math.floor(13750 * 1.3 + 0.5), "Nefarian D3 HP")
	c.player_health = 3000
	n_heals = #healed
	kill(c)
	T.eq(run.over, "won", "run won")
	T.eq(log[#log], "won", "run_won event")
	T.eq(#healed, n_heals, "no heal after the last boss")
	T.eq(c.player_health, 3000, "HP as it was")
	T.eq(run.next_at, nil, "no next fight scheduled")
	local dragon = c.enemy
	for _ = 1, 300 do step(sim, run) end
	T.ok(c.enemy == dragon and c.fight_over, "no further fight starts after the win")
	T.eq(run:begin_fight(), nil, "begin_fight refuses after the run is over")
end)

T.case("run lost is noted, the beat is cancelled", function()
	local _, c, run = new_run(8, 1)
	run:begin_fight()
	c.player_health = 1
	c:take_damage(50)
	T.ok(c.game_over, "player dead")
	T.eq(run.over, "lost", "run over: lost")
	run.next_at = 5
	T.eq(run:begin_fight(), nil, "no fight after the loss")
end)

T.case("dev: a forced enemy is scaled, flagged, and follows the ladder rules", function()
	local sim, c, run = new_run(9, 2)
	run:begin_fight(Data.by_id.hakkar)
	T.eq(c.enemy.def.id, "hakkar", "forced Hakkar")
	T.eq(c.enemy.max_health, 8625, "D2 scaled (7500 x 1.15)")
	T.ok(run.dev, "run flagged dev (no records)")
	T.eq(run:label(), "DEV", "dev label")
	kill(c)
	T.ok(tick_until(sim, run, function() return c.enemy.def.id == "hakkar" and not c.fight_over end, 3), "the forced enemy follows")
end)

---------------------------------------------------------------- an enemy killed mid-junk-telegraph

T.case("a kill mid-junk-telegraph: the transition tolerates the unfinished junk spawn", function()
	local sim, c, run = new_run(11, 1, 7) -- Qiraji Scarab: Web Spray is its first attack
	run:begin_fight()
	T.eq(c.enemy.def.id, "qiraji_scarab", "Qiraji Scarab")
	local junk_before = 0
	T.ok(tick_until(sim, run, function() return c.enemy.exec ~= nil end, 20), "the junk telegraph started")
	for i = 1, sim.board.cols * sim.board.rows do
		local g = sim.board.cells[i]
		if g and g.junk then junk_before = junk_before + 1 end
	end
	T.eq(junk_before, 0, "no junk yet")
	local qiraji_scarab = c.enemy
	kill(c) -- the enemy dies while the telegraph is running
	T.ok(c.fight_over, "fight over")
	T.ok(tick_until(sim, run, function() return c.enemy ~= qiraji_scarab end, 5), "the next fight starts after the beat")
	T.eq(c.enemy.def.id, "anubisath_sentinel", "Anubisath Sentinel")
	T.eq(qiraji_scarab.exec, nil, "the dead enemy's execute state was dropped")
	local settled = tick_until(sim, run, function() return sim:is_at_rest() end, 30)
	T.ok(settled, "the board comes to rest")
	T.ok(sim.board:check_integrity(false), "grid consistent")
	local junk = 0
	for i = 1, sim.board.cols * sim.board.rows do
		local g = sim.board.cells[i]
		if g and g.junk then junk = junk + 1 end
	end
	T.eq(junk, 3, "the junk spawn finished anyway (Godot-consistent)")
	T.ok(c.enemy.current_health == c.enemy.max_health and not c.fight_over, "the new fight is live and untouched")
	-- and the fight can go on
	for _ = 1, 600 do step(sim, run) end
	T.ok(sim.board:check_integrity(false), "still consistent after 20 s")
end)

---------------------------------------------------------------- full-run bot

local REST_LIMIT = 30
local CAP_PER_FIGHT = 600

-- God mode bot: the whole ladder. Returns a result table.
local function play_run(seed, difficulty, pace)
	local sim = Sim.new({ seed = seed })
	local c = Combat.new({ sim = sim, seed = seed })
	c.god_mode = true
	local run = Run.new({ combat = c, difficulty = difficulty })
	local r = { fought = {}, integrity = true, events = {} }
	sim:on("run_fight_starting", function(_, def)
		r.fought[#r.fought + 1] = def.id
		r.last_start = sim.now
		r.hp0 = def.max_health
	end)
	sim:on("run_advanced", function(result) r.events[#r.events + 1] = result end)
	sim:on("run_won", function() r.events[#r.events + 1] = "won" end)
	c:on("enemy_phase_changed", function() r.phases = (r.phases or 0) + 1 end)
	run:begin_fight()
	local next_swap, ticks, last_rest = pace, 0, 0
	while not run.over do
		if sim.now >= next_swap and c:can_player_swap() == "" then
			local c1, r1, c2, r2 = Match.find_possible_move(sim.board)
			local res = c1 and c:try_swap(sim.board:get(c1, r1), sim.board:get(c2, r2)) or "none"
			next_swap = sim.now + (res == "ok" and pace or 0.1)
		end
		step(sim, run)
		ticks = ticks + 1
		if sim:is_at_rest() or sim:is_gameplay_paused() then last_rest = sim.now end
		if sim.now - last_rest > REST_LIMIT then
			r.stuck = true
			break
		end
		if r.last_start and sim.now - r.last_start > CAP_PER_FIGHT then
			r.timeout = true
			break
		end
		if ticks % 15 == 0 and not sim.board:check_integrity(false) then r.integrity = false end
	end
	r.over, r.time, r.score = run.over, sim.now, c.score
	return r
end

local before = deep_copy(Data.list)
local ids = {}
for i = 1, 10 do ids[i] = Data.list[i].id end
-- {seed, difficulty, bot pace}: the D5 bot swaps faster (a 1.5 s mouse pace can't outpace the Forest Troll's
-- regeneration there; the bot is no strategist, this is a flow test)
for _, cfg in ipairs({ { 20261004, 1, 1.5 }, { 77, 5, 1.0 } }) do
	T.case(("full run, seed %d, D%d (god mode bot)"):format(cfg[1], cfg[2]), function()
		local r = play_run(cfg[1], cfg[2], cfg[3])
		local label = ("seed %d D%d"):format(cfg[1], cfg[2])
		if os.getenv("BOT_VERBOSE") == "1" then
			print(("%s: %s in %.0f sim s, score %d, fights %d"):format(label, tostring(r.over), r.time, r.score, #r.fought))
		end
		T.ok(not r.stuck, label .. ": no stuck state")
		T.ok(not r.timeout, label .. ": no fight over " .. CAP_PER_FIGHT .. " s")
		T.ok(r.integrity, label .. ": grid consistent")
		T.eq(r.over, "won", label .. ": run won")
		T.eq(table.concat(r.fought, ","), table.concat(ids, ","), label .. ": all ten enemies in ladder order")
		T.eq(table.concat(r.events, ","),
			"next_fight,next_fight,stage_complete,next_fight,next_fight,stage_complete,next_fight,next_fight,stage_complete,won",
			label .. ": advance results")
		T.ok(r.score > 0, label .. ": score accumulated across fights (" .. tostring(r.score) .. ")")
		T.eq(r.phases, 2, label .. ": Nefarian's two phases")
		-- records from the result, as the UI does it
		local db = { unlocked = cfg[2] } -- the level was playable, i.e. unlocked
		local nb, un = Run.record_result(db, cfg[2], r.score, true)
		T.ok(nb, label .. ": new best")
		T.eq(un, cfg[2] < 5 and cfg[2] + 1 or nil, label .. ": unlock result")
	end)
end
T.ok(deep_equal(before, Data.list), "data/enemies.lua unchanged after two full runs")

Run.ATTACK_PACE = PACE
Run.ENEMY_DAMAGE_SCALE = DMG_SCALE
T.eq(DMG_SCALE, 0.9, "W0-P10: enemy damage -10 %")
for d = 1, 5 do
	local _, dm = Run.multipliers(d)
	local o = Data.by_id.hellhound.rotation[1]
	local n = Run.scale_def(Data.by_id.hellhound, d).rotation[1]
	T.eq(n.damage_min, ns.StatusMath.round(o.damage_min * dm * PACE * 0.9), "D" .. d .. " damage_min includes x0.9")
	T.eq(n.damage_max, ns.StatusMath.round(o.damage_max * dm * PACE * 0.9), "D" .. d .. " damage_max includes x0.9")
end
local mo = Data.by_id.nefarian.phases[2].rotation[3]
local hp_m = Run.multipliers(2)
T.eq(Run.scale_def(Data.by_id.nefarian, 2).phases[2].rotation[3].break_damage, ns.StatusMath.round(mo.break_damage * hp_m),
	"mirror break_damage not touched by the damage scale")
T.ok(PACE >= 2, "attacks at least twice as far apart")
local hb = Data.by_id.hellhound.rotation[1]
local hc = Run.scale_def(Data.by_id.hellhound, 1).rotation[1]
T.ok(math.abs(hc.cooldown - hb.cooldown * PACE) < 1e-9, "cooldown x pace")
T.eq(hc.damage_min, ns.StatusMath.round(hb.damage_min * PACE * DMG_SCALE), "damage x pace x damage scale")

T.done()
