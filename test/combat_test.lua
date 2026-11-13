-- core/combat.lua: damage numbers, hit order, statuses in sim time, the
-- match/ability ordering (spec change 5), the kill pause (5b), settle_now /
-- snapshot (5c), score, game over, input gate.
local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "."
local H = dofile(dir .. "/helpers.lua")
local T, ns = H.T, H.ns
local Sim, Combat, Board = ns.Sim, ns.Combat, ns.Board
local SM = ns.StatusMath
T.start("combat_test")

local function near(a, b, eps) return math.abs(a - b) < (eps or 1e-6) end

T.case("x10 damage economy (mirrors ability_gems_test _test_x10_damage_economy)", function()
	local def = H.enemy_def()
	local _, c = H.fight(nil, { def = def })
	T.eq(c:_match_damage_from_counts({ [3] = 3 }), 30, "a 3-match clear deals 30")
	def.weak_to_color = 3
	T.eq(c:_match_damage_from_counts({ [3] = 3 }), 45, "a weak-colour 3-match deals 45")
	T.eq(c:_match_damage_from_counts({ [3] = 1 }), 15, "a weak-colour single gem deals 15")
	T.eq(c:_match_damage_from_counts({ [3] = 3, [0] = 3 }), 75, "weak 3 + plain 3 in one wave deals 75")
	def.weak_to_color = -1
	c:apply_damage_debuff(0.7, 10)
	T.eq(c:_match_damage_from_counts({ [3] = 1 }), 7, "a cursed single gem deals 7")
	c:_clear_status("curse")
	T.eq(c:_scale_outgoing_damage(Combat.BOMB_DAMAGE, -1), 50, "a bomb deals 50")
	T.eq(c:_match_damage_from_counts({ [0] = 0 }), 0, "nothing cleared, no damage")
end)

T.case("ability direct damage: 6/7-match multiplier, then the ability colour's weakness", function()
	local def = H.enemy_def()
	local sim, c = H.fight(nil, { def = def })
	local dealt = H.collect(sim, "damage_dealt")
	c.cur_source, c.cur_gem_type = "ability", 3
	c.cur_mult = ns.Match.damage_multiplier_for_length(6)
	c:deal_damage_to_enemy(150)
	T.eq(dealt[1][1], 180, "6-match: 150 x 1.2")
	T.eq(dealt[1][2], 3, "packet colour = the ability's colour")
	T.eq(dealt[1][3], "ability", "source ability")
	c.cur_mult = ns.Match.damage_multiplier_for_length(7)
	def.weak_to_color = 3
	c:deal_damage_to_enemy(150)
	T.eq(dealt[2][1], 338, "7-match + weak: round(round(150 x 1.5) x 1.5) = 338")
	c:_reset_current()
	c:deal_damage_to_enemy(100)
	T.eq(dealt[3][3], "other", "outside an ability the source is other")
	T.eq(c.enemy.current_health, 100000 - 180 - 338 - 100, "enemy HP")
end)

T.case("hit order: Fire Shield -> shield stack -> HP; true damage skips both", function()
	local sim, c = H.fight(nil)
	local dealt = H.collect(sim, "damage_dealt")
	c:add_shield_stack(0)
	c:apply_fire_shield(10, 1.0)
	T.eq(c:take_damage(300), "reflect", "fire shield first")
	T.eq(c.enemy.current_health, 100000 - 300, "full hit reflected into the enemy")
	T.eq(dealt[1][3], "reflect", "reflect packet")
	T.eq(dealt[1][2], -1, "reflect is colourless")
	T.eq(c.status.shield.stacks, 1, "stack untouched while the fire shield is up")
	H.tick_to(sim, 10.01)
	T.eq(c:status_remaining("fire_shield"), 0, "fire shield ran out after 10 s")
	T.eq(c:take_damage(300), "shield", "then the shield stack")
	T.eq(c.status.shield.stacks, 0, "stack consumed")
	T.eq(c.player_health, 10000, "no HP lost yet")
	T.eq(c:take_damage(300), "hp", "then HP")
	T.eq(c.player_health, 9700, "HP lost")
	c:add_shield_stack(0)
	c:apply_fire_shield(10, 1.0)
	c:take_true_damage(100, "mirror")
	T.eq(c.player_health, 9600, "true damage goes straight to HP")
	T.eq(c.status.shield.stacks, 1, "true damage keeps the stack")
	c.god_mode = true
	T.eq(c:take_damage(300), "none", "god mode")
	c.god_mode = false
	c.fight_over = true
	T.eq(c:take_damage(300), "none", "fight over")
end)

-- W1-G2: the Amber skill is a heal over time, the ult an instant heal (core/abilities/amber.lua).
local function tick_sum(list)
	local sum = 0
	for _, e in ipairs(list) do sum = sum + e[1] end
	return sum
end

T.case("HoT: one tick per second for 10 s, cumulative rounding, expires on the last tick", function()
	local sim, c = H.fight(nil)
	local healed = H.collect(sim, "player_healed")
	local changes = H.collect(sim, "status_changed")
	c.player_health = 5000
	c:apply_hot(5, 10, 1)
	T.ok(near(c:status_remaining("hot"), 10), "10 s up at the cast")
	T.eq(c:status_max("hot"), 10, "max = ticks x interval")
	H.tick_to(sim, 0.99)
	T.eq(#healed, 0, "no tick before 1 s")
	H.tick_to(sim, 10.5)
	T.eq(#healed, 10, "ten ticks")
	for i, e in ipairs(healed) do
		T.ok(near(e.t, i, 0.051), "tick " .. i .. " at +" .. i .. " s (" .. e.t .. ")")
		T.eq(e[1], 50, "tick " .. i .. " heals 50")
		T.eq(e[2], "hot", "source hot")
	end
	T.eq(c.player_health, 5500, "500 in total = 5 % of 10000")
	T.eq(c:status_remaining("hot"), 0, "expired right after the last tick")
	T.eq(c:status_max("hot"), 0, "max reset")
	local last = changes[#changes]
	T.ok(last[1] == "hot" and last[2] == false and near(last.t, 10, 0.051), "status_changed(false) with the last tick")
	-- a max HP that does not divide: the ticks sum to exactly T
	local sim2, c2 = H.fight(nil)
	local h2 = H.collect(sim2, "player_healed")
	c2.player_max_health, c2.player_health = 12345, 1000
	c2:apply_hot(5, 10, 1)
	H.tick_to(sim2, 11)
	local total = math.floor(12345 * 5 / 100 + 0.5)
	T.eq(tick_sum(h2), total, "ticks sum to exactly " .. total)
	for k = 1, 10 do
		T.eq(h2[k][1], SM.round(total * k / 10) - SM.round(total * (k - 1) / 10), "tick " .. k .. " is the cumulative share")
	end
end)

T.case("HoT: a cast while it runs extends it, capped at 20 ticks; the tick timer is not restarted", function()
	local sim, c = H.fight(nil)
	local healed = H.collect(sim, "player_healed")
	c.player_health = 1000
	c:apply_hot(5, 10, 1)
	H.tick_to(sim, 1.01) -- 9 ticks left
	T.eq(c.status.hot.ticks_left, 9, "9 ticks left")
	c:apply_hot(5, 10, 1)
	T.eq(c.status.hot.ticks_left, 19, "9 + 10 = 19")
	T.eq(c:status_max("hot"), 20, "max = every granted tick (10 + 10)")
	T.ok(near(c:status_remaining("hot"), 18.99, 0.06), "remaining counts every tick left")
	T.ok(c:status_remaining("hot") <= c:status_max("hot"), "the countdown ring is honest")
	H.tick_to(sim, 2.05)
	T.ok(near(healed[2].t, 2, 0.051), "the next tick came on its own beat (not restarted)")
	T.eq(#healed, 2, "one tick per second, the rate never doubles")
	H.tick_to(sim, 5.01) -- 5 ticks done, 15 left
	T.eq(c.status.hot.ticks_left, 15, "15 ticks left")
	c:apply_hot(5, 10, 1)
	T.eq(c.status.hot.ticks_left, 20, "capped at 20")
	T.eq(c:status_max("hot"), 25, "granted ticks: 10 + 10 + 5")
	H.tick_to(sim, 5.01 + 21)
	T.eq(#healed, 25, "25 ticks in all")
	T.eq(c:status_remaining("hot"), 0, "over")
	-- every 10-tick chunk of the cycle heals exactly T (the cycle runs on)
	T.eq(tick_sum(healed), 1250, "two and a half casts")
end)

T.case("HoT: frozen by the gameplay pause and by freeze(); carries over the fight boundary", function()
	local sim, c = H.fight(nil, { def = H.enemy_def({ hp = 100 }) })
	local healed = H.collect(sim, "player_healed")
	c.player_health = 1000
	c:apply_hot(5, 10, 1)
	H.tick_to(sim, 2.5) -- 2 ticks done
	sim:pause_gameplay()
	H.tick_to(sim, 8)
	T.eq(#healed, 2, "no tick while paused")
	sim:resume_gameplay()
	c.clock:freeze()
	H.tick_to(sim, 12)
	T.eq(#healed, 2, "no tick while frozen (settle_now)")
	c.clock:thaw()
	H.tick_to(sim, 12.6)
	T.eq(#healed, 3, "ticking again after the thaw")
	-- the kill pauses gameplay: the beat between two fights does not tick
	c:deal_damage_to_enemy(100)
	T.ok(c.fight_over and sim:is_gameplay_paused(), "enemy dead, gameplay paused")
	local n = #healed
	local left = c.status.hot.ticks_left
	H.tick_to(sim, 20)
	T.eq(#healed, n, "no tick during the between-fight beat")
	T.eq(c.status.hot.ticks_left, left, "the HoT waits")
	c:start_fight(H.enemy_def())
	T.ok(c:status_remaining("hot") > 0, "the next fight starts with the HoT still running")
	H.tick_to(sim, 20 + left + 1)
	T.eq(#healed, n + left, "the remaining ticks land in the next fight")
	T.eq(c:status_remaining("hot"), 0, "and it ends")
end)

T.case("HoT: nothing heals once the run is lost", function()
	local sim, c = H.fight(nil)
	local healed = H.collect(sim, "player_healed")
	c:apply_hot(5, 10, 1)
	c:take_damage(10000)
	T.ok(c.game_over, "lost")
	H.tick_to(sim, 5)
	T.eq(#healed, 0, "no heal after game over")
	T.eq(c.player_health, 0, "still dead")
	T.eq(c:status_remaining("hot"), 0, "the status is gone")
end)

T.case("HoT: Heal Block turns a tick into 0 (consumed), later ticks heal again; full HP loses the tick", function()
	local sim, c = H.fight(nil)
	local healed = H.collect(sim, "player_healed")
	local blocked = H.collect(sim, "heal_blocked")
	local lost = H.collect(sim, "heal_lost")
	c.player_health = 5000
	c:apply_hot(5, 10, 1)
	c:apply_heal_block(2.5)
	H.tick_to(sim, 3.05)
	T.eq(#healed, 1, "only the 3rd tick healed")
	T.ok(near(healed[1].t, 3, 0.051), "at +3 s")
	T.eq(#blocked, 2, "heal_blocked on the two blocked ticks")
	T.eq(#lost, 2, "heal_lost on them")
	T.eq(lost[1][1], 50, "the lost amount")
	T.eq(lost[1][2], "block", "reason block")
	T.eq(lost[1][3], "hot", "source hot")
	T.eq(c.player_health, 5050, "HP")
	T.eq(c.status.hot.ticks_left, 7, "the blocked ticks were consumed")
	-- overheal: full HP, a tick heals 0 and says so
	c.player_health = 10000
	local nh = #healed
	H.tick_to(sim, 4.05)
	T.eq(#healed, nh, "no player_healed at full HP")
	T.eq(lost[#lost][2], "overheal", "reason overheal")
	T.eq(lost[#lost][1], 50, "the whole tick")
	T.eq(#blocked, 2, "no heal_blocked for an overheal")
	-- a partial overheal heals the rest and loses the surplus
	c.player_health = 9980
	H.tick_to(sim, 5.05)
	T.eq(c.player_health, 10000, "capped")
	T.eq(healed[#healed][1], 20, "the event carries the HP actually restored")
	T.eq(lost[#lost][1], 30, "the surplus is lost")
end)

T.case("HoT: serialize / deserialize mid-HoT reproduces the same later heals", function()
	local def = H.enemy_def({ hp = 100 })
	local sim, c = H.fight(nil, { def = def })
	c.player_max_health, c.player_health = 12345, 1000
	c:apply_hot(5, 10, 1)
	H.tick_to(sim, 3.4)
	c:apply_hot(5, 10, 1) -- extended: 17 ticks left
	c:deal_damage_to_enemy(100)
	T.ok(c.fight_over, "between fights")
	local snap = c:serialize()
	T.ok(snap ~= nil, "snapshot")
	local sim2 = Sim.new({ seed = 3 })
	local c2 = Combat.deserialize(snap, { sim = sim2 })
	T.eq(c2.status.hot.ticks_left, 17, "ticks left")
	T.ok(near(c2:status_remaining("hot"), c:status_remaining("hot")), "remaining survives the round trip")
	T.ok(near(c2:status_max("hot"), c:status_max("hot")), "max survives")
	local h1, h2 = H.collect(sim, "player_healed"), H.collect(sim2, "player_healed")
	local t1, t2 = sim.now, sim2.now
	c:start_fight(H.enemy_def())
	c2:start_fight(H.enemy_def())
	H.tick_to(sim, t1 + 20)
	H.tick_to(sim2, t2 + 20)
	T.eq(#h1, 17, "17 ticks on the original")
	T.eq(#h2, #h1, "17 ticks after the restore")
	for i = 1, #h1 do
		T.eq(h2[i][1], h1[i][1], "tick " .. i .. ": same amount")
		T.ok(near(h2[i].t - t2, h1[i].t - t1, 1e-6), "tick " .. i .. ": same time")
	end
	T.eq(c2.player_health, c.player_health, "same HP")
end)

T.case("heal_player: ult 15 % capped at max, Heal Block, the boss heal ignores Heal Block and reports no loss", function()
	local sim, c = H.fight(nil)
	local healed = H.collect(sim, "player_healed")
	local blocked = H.collect(sim, "heal_blocked")
	local lost = H.collect(sim, "heal_lost")
	c.player_health = 4000
	T.eq(c:heal_player(1500, "ult", true), 1500, "restored 1500")
	T.eq(c.player_health, 5500, "HP")
	T.eq(healed[1][1], 1500, "player_healed amount")
	T.eq(healed[1][2], "ult", "player_healed source")
	c.player_health = 9000
	T.eq(c:heal_player(1500, "ult", true), 1000, "capped at max")
	T.eq(lost[1][1], 500, "the surplus is lost")
	T.eq(lost[1][2], "overheal", "reason overheal")
	T.eq(lost[1][3], "ult", "source ult")
	c.player_health = 4000
	c:apply_heal_block(5)
	T.eq(c:heal_player(1500, "ult", true), 0, "Heal Block: nothing")
	T.eq(c.player_health, 4000, "HP unchanged")
	T.eq(#blocked, 1, "heal_blocked")
	T.eq(lost[2][2], "block", "reason block")
	T.eq(lost[2][1], 1500, "the whole heal is lost")
	local nl = #lost
	T.eq(c:heal_player(2500, "boss", false), 2500, "the boss heal ignores Heal Block")
	T.eq(healed[#healed][2], "boss", "source boss")
	c.player_health = 9000
	c:heal_player(2500, "boss", false)
	T.eq(#lost, nl, "no heal_lost for the boss heal")
	c.game_over = true
	T.eq(c:heal_player(100, "ult", true), 0, "no heal after game over")
end)

T.case("the Amber abilities draw no random numbers", function()
	local tape = H.tape({})
	local sim, c = H.fight(nil, { rng_combat = tape })
	c.player_health = 5000
	local kit = c.kit
	for _, tier in ipairs({ 1, 2 }) do
		kit:get(0, tier):execute({ sim = sim, board = sim.board, combat = c, info = { gem_type = 0, tier = tier } })
	end
	H.tick_to(sim, 12)
	T.eq(tape.draws, 0, "no combat RNG draw")
	T.ok(c.player_health > 5000, "and they healed")
end)

T.case("timed statuses tick in gameplay time and freeze in the gameplay pause", function()
	local sim, c = H.fight(nil)
	local changes = H.collect(sim, "status_changed")
	c:apply_fire_shield(10, 1.0)
	H.tick_to(sim, 5)
	T.ok(near(c:status_remaining("fire_shield"), 5), "5 s left")
	sim:pause_gameplay()
	H.tick_to(sim, 8)
	T.ok(near(c:status_remaining("fire_shield"), 5), "frozen while paused")
	sim:resume_gameplay()
	H.tick_to(sim, 12.99)
	T.ok(c:status_remaining("fire_shield") > 0, "still up 0.01 s before the end")
	H.tick_to(sim, 13.01)
	T.eq(c:status_remaining("fire_shield"), 0, "ran out after 10 s of gameplay time")
	local last = changes[#changes]
	T.ok(last[1] == "fire_shield" and last[2] == false and near(last.t, 13), "status_changed(false) at the exact time")
	-- heal block keeps the longer window; curse multiplier resets on expiry
	c:apply_heal_block(4)
	c:apply_heal_block(2)
	T.ok(near(c:status_remaining("heal_block"), 4), "heal block keeps the longer window")
	c:apply_damage_debuff(0.7, 1)
	T.eq(c:curse_multiplier(), 0.7, "curse active")
	H.tick_to(sim, 14.02)
	T.eq(c:curse_multiplier(), 1.0, "curse expired")
	T.eq(c.status.curse.multiplier, 1.0, "multiplier reset")
end)

T.case("order: gems_cleared before ability_activated; drain alongside the fuse; gravity after", function()
	-- row 0: 3 3 _ with a Ruby skill (Flamestrike) below the gap
	local sim, c = H.fight({ ["0,0"] = "3", ["1,0"] = "3", ["2,1"] = "d", ["3,0"] = "0" })
	local log = {}
	local function mark(name)
		sim:on(name, function(a, b, d)
			local s = name
			if name == "damage_dealt" then s = s .. " " .. a .. " " .. d end
			log[#log + 1] = { t = sim.now, s = s }
		end)
	end
	for _, n in ipairs({ "gems_cleared", "ability_activated", "ability_triggered", "damage_dealt",
		"gem_removed", "gems_cleared_by_effect", "gem_created", "board_settled" }) do mark(n) end
	T.eq(c:try_swap(sim.board:get(2, 1), sim.board:get(2, 0)), "ok", "swap")
	T.ok(H.run(sim), "rest")
	local first = {}
	for i, e in ipairs(log) do
		local key = e.s:match("^(%S+)")
		if e.s:find("damage_dealt") then key = e.s end
		if first[key] == nil then first[key] = { i = i, t = e.t } end
	end
	local t0 = first.gems_cleared.t
	T.ok(near(t0, 0.14), "match after the swap tween: " .. t0)
	T.ok(first.gems_cleared.i < first.ability_activated.i, "gems_cleared before ability_activated")
	T.ok(first["damage_dealt 30 match"] ~= nil and first["damage_dealt 30 match"].i < first.ability_activated.i,
		"match damage (30) before the activation")
	T.ok(first.ability_activated.i < first.ability_triggered.i, "activation queued, then executed")
	T.ok(near(first.ability_triggered.t, t0), "the drain starts at once (does not wait for the fuse)")
	T.ok(near(first["damage_dealt 150 ability"].t, t0), "Flamestrike direct damage at the match time")
	T.ok(near(first.gem_removed.t, t0 + 0.24), "fuse ends 0.24 s later: " .. first.gem_removed.t)
	T.ok(first.gem_removed.t < first.gems_cleared_by_effect.t, "the wave clears after the fuse")
	T.ok(near(first.gems_cleared_by_effect.t, t0 + 0.40), "wave scan after cone + slices + fade")
	T.ok(first.gem_created.t > first.gems_cleared_by_effect.t + 0.12 - 1e-9, "gravity / refill only after the drain")
	local ok, err = sim.board:check_integrity(true)
	T.ok(ok, err)
end)

T.case("kill pauses gameplay; leftover board work hits the next enemy (5b)", function()
	local sim, c = H.fight({ ["0,0"] = "3", ["1,0"] = "3", ["2,1"] = "d", ["3,0"] = "0" }, { def = H.enemy_def({ hp = 30 }) })
	local defeated = H.collect(sim, "enemy_defeated")
	local triggered = H.collect(sim, "ability_triggered")
	c:try_swap(sim.board:get(2, 1), sim.board:get(2, 0))
	H.tick_to(sim, 0.5)
	T.eq(#defeated, 1, "the 30-damage match killed the 30-HP enemy")
	T.ok(c.fight_over, "fight over")
	T.ok(sim:is_gameplay_paused(), "gameplay paused on the kill")
	T.eq(c:can_player_swap(), "not_in_fight", "input gate between fights")
	H.tick_to(sim, 3)
	T.eq(#triggered, 0, "the queued Flamestrike waits")
	T.ok(not sim:is_at_rest(), "board work is held, not dropped")
	local second = c:start_fight(H.enemy_def({ hp = 1000, name = "Second" }))
	T.ok(not sim:is_gameplay_paused(), "start_fight lifts the kill pause")
	T.ok(H.run(sim), "rest")
	T.eq(#triggered, 1, "Flamestrike fired after the transition")
	T.ok(second.current_health <= 1000 - 150, "its damage hit the next enemy: " .. second.current_health)
end)

T.case("settle_now freezes enemy and status clocks (5c)", function()
	local def = H.enemy_def({ cooldown = 0.1, dmg = 500 })
	local sim, c = H.fight({ ["0,0"] = "1", ["1,0"] = "1", ["2,1"] = "1" }, { def = def })
	c:apply_fire_shield(10, 1.0)
	H.tick_to(sim, 0.05)
	local next_attack = c.enemy:get_time_to_next_attack()
	local shield_left = c:status_remaining("fire_shield")
	c:try_swap(sim.board:get(2, 1), sim.board:get(2, 0))
	T.ok(c:settle_now(), "board at rest")
	T.ok(sim:is_at_rest(), "is_at_rest")
	T.eq(c.player_health, 10000, "no hit during settle")
	T.ok(near(c.enemy:get_time_to_next_attack(), next_attack), "enemy timer unchanged")
	T.ok(near(c:status_remaining("fire_shield"), shield_left), "fire shield unchanged")
	local refl = H.collect(sim, "attack_reflected")
	H.tick_to(sim, sim.now + next_attack + 0.01)
	T.eq(#refl, 1, "the enemy attacks again once ticking resumes")
end)

T.case("W1-G3: reflect = hit + bonus (one number), per hit; no bonus without the argument", function()
	local sim, c = H.fight(nil)
	local dealt = H.collect(sim, "damage_dealt")
	local refl = H.collect(sim, "attack_reflected")
	c:apply_fire_shield(15, 1.0, 100)
	T.eq(c:status_max("fire_shield"), 15, "15 s window")
	for _ = 1, 4 do c:take_damage(60) end -- a flurry: every hit reflects hit + bonus
	T.eq(100000 - c.enemy.current_health, 4 * 160, "4 x (60 + 100)")
	T.eq(#refl, 4, "one attack_reflected per hit")
	T.eq(refl[1][1], 160, "event carries the one number")
	T.eq(dealt[1][1], 160, "damage_dealt carries the same number")
	T.eq(dealt[1][3], "reflect", "source reflect")
	T.eq(c.player_health, 10000, "no HP lost")
	local sim2, c2 = H.fight(nil)
	c2:apply_fire_shield(10, 1.0)
	c2:take_damage(60)
	T.eq(100000 - c2.enemy.current_health, 60, "bonus defaults to 0")
	T.eq(SM.reflected_damage(301, 0.5, 100), 251, "multiplier first, then the bonus")
end)

T.case("W1-G3: the bonus survives a snapshot; an old snapshot loads with bonus 0", function()
	local sim, c = H.fight(nil, { def = H.enemy_def({ hp = 10 }) })
	c:apply_fire_shield(15, 1.0, 100)
	c:deal_damage_to_enemy(10)
	local snap = c:serialize()
	T.eq(snap.statuses.fire_shield[4], 100, "bonus saved")
	local c2 = Combat.deserialize(snap, { sim = Sim.new({ seed = 3 }) })
	T.eq(c2.status.fire_shield.reflect_bonus, 100, "bonus restored")
	snap.statuses.fire_shield[4] = nil
	local c3 = Combat.deserialize(snap, { sim = Sim.new({ seed = 3 }) })
	T.eq(c3.status.fire_shield.reflect_bonus, 0, "old snapshot: no bonus (like the shield it was granted as)")
end)

T.case("W1-G4: shield stacks cap at 3; the cast at the cap emits shield_capped and changes nothing", function()
	local sim, c = H.fight(nil)
	T.eq(Combat.SHIELD_MAX_STACKS, 3, "cap 3")
	local capped, changes = H.collect(sim, "shield_capped"), H.collect(sim, "status_changed")
	c:add_shield_stack(40)
	c:add_shield_stack(40)
	c:add_shield_stack(40)
	T.eq(c.status.shield.stacks, 3, "3 stacks")
	T.eq(#capped, 0, "no event below the cap")
	local n = #changes
	c:add_shield_stack(99)
	T.eq(c.status.shield.stacks, 3, "still 3")
	T.eq(c.status.shield.thorns, 40, "thorns untouched at the cap")
	T.eq(#capped, 1, "shield_capped emitted")
	T.eq(#changes, n, "no status_changed at the cap")
	T.eq(c:take_damage(300), "shield", "a stack blocks")
	c:add_shield_stack(0)
	T.eq(c.status.shield.stacks, 3, "back to 3 after a block")
end)

T.case("W1-G4: a snapshot with too many stacks is clamped", function()
	local sim, c = H.fight(nil, { def = H.enemy_def({ hp = 10 }) })
	c:add_shield_stack(0)
	c:deal_damage_to_enemy(10)
	local snap = c:serialize()
	snap.shield[1] = 9
	local c2 = Combat.deserialize(snap, { sim = Sim.new({ seed = 3 }) })
	T.eq(c2.status.shield.stacks, 3, "clamped to the cap")
end)

T.case("serialize only between fights; round trip", function()
	local sim, c = H.fight(nil, { def = H.enemy_def({ hp = 10 }) })
	local snap, why = c:serialize()
	T.ok(snap == nil and why == "mid-fight", "refused mid-fight")
	c:add_shield_stack(0)
	c:apply_fire_shield(10, 1.0)
	c:take_damage(1) -- reflected: 1 damage to the enemy
	c:deal_damage_to_enemy(10) -- kills it (9 HP left)
	T.ok(c.fight_over, "enemy dead")
	H.tick_to(sim, 2) -- paused: the fire shield does not tick
	c.score = 1234
	snap = c:serialize()
	T.ok(snap ~= nil, "snapshot between fights")
	local sim2 = Sim.new({ seed = 3 })
	local c2 = Combat.deserialize(snap, { sim = sim2 })
	T.eq(c2.player_health, c.player_health, "HP")
	T.eq(c2.score, 1234, "score")
	T.eq(c2.status.shield.stacks, 1, "shield stack")
	T.ok(near(c2:status_remaining("fire_shield"), c:status_remaining("fire_shield")), "fire shield remaining")
	T.eq(c2.rng_combat:range_i(0, 1000000), c.rng_combat:range_i(0, 1000000), "combat stream continues identically")
	T.eq(Combat.deserialize({ v = 99 }), nil, "other version refused")
end)

T.case("score: match table (mirrors _test_match_score) and ability / single scores", function()
	T.eq(Combat.match_score(3), 50, "3-match 50")
	T.eq(Combat.match_score(7), 850, "7-match 850")
	T.eq(Combat.match_score(8), 850, "8 capped")
	T.eq(Combat.match_score(29), 850, "29-region capped")
	local sim, c = H.fight({ ["0,0"] = "1", ["1,0"] = "1", ["2,1"] = "1" })
	local scores = {}
	sim:on("match_resolved", function(len) scores[#scores + 1] = Combat.match_score(len) end)
	c:try_swap(sim.board:get(2, 1), sim.board:get(2, 0))
	T.ok(H.run(sim), "rest")
	local sum = 0
	for _, s in ipairs(scores) do sum = sum + s end
	T.eq(c.score, sum, "score = sum of match scores (no abilities)")
	c:award_score(150)
	T.eq(c.score, sum + 150, "ability score added")
end)

T.case("player death: run_lost, enemy stops, input closed", function()
	local sim, c = H.fight(nil, { def = H.enemy_def({ cooldown = 5 }) })
	local lost = H.collect(sim, "run_lost")
	T.eq(c:take_damage(10000), "hp", "lethal hit")
	T.eq(c.player_health, 0, "0 HP")
	T.ok(c.game_over, "game over")
	T.eq(#lost, 1, "run_lost")
	T.eq(c.enemy:get_time_to_next_attack(), -1, "enemy rotation stopped")
	T.eq(c:can_player_swap(), "game_over", "input gate")
	T.eq(c:take_damage(10), "none", "no more hits")
end)

T.case("player stun gates input only", function()
	local sim, c = H.fight({ ["0,0"] = "1", ["1,0"] = "1", ["2,1"] = "1" })
	c:apply_player_stun(2)
	T.eq(c:try_swap(sim.board:get(2, 1), sim.board:get(2, 0)), "stunned", "stunned")
	H.tick_to(sim, 2.01)
	T.eq(c:can_player_swap(), "", "stun over")
	T.eq(c:try_swap(sim.board:get(2, 1), sim.board:get(2, 0)), "ok", "swap works again")
end)

T.case("status math (mirrors ability_gems_test _test_status_helpers)", function()
	T.ok(near(SM.tick_status_remaining(3.0, 1.25), 1.75), "ticks down")
	T.ok(near(SM.tick_status_remaining(0.5, 1.0), 0.0), "clamps at zero")
	T.eq(SM.consume_shield_stack(2), 1, "stack decrements")
	T.eq(SM.consume_shield_stack(1), 0, "last stack")
	T.eq(SM.consume_shield_stack(0), 0, "zero stays zero")
	T.ok(near(SM.status_ratio(5.0, 10.0), 0.5), "ratio")
	T.ok(near(SM.status_ratio(1.0, 0.0), 0.0), "ratio with zero max")
	T.ok(near(SM.stun_max_after_apply(3.0, 5.0, 10.0), 5.0), "stun max updates when the new duration wins")
	T.ok(near(SM.stun_max_after_apply(8.0, 5.0, 10.0), 10.0), "stun max kept when the old remaining wins")
	T.eq(SM.reflected_damage(301, 0.5), 151, "reflect rounds half away from zero")
end)

T.case("hud_state reuses its tables", function()
	local sim, c = H.fight(nil)
	local s = c:hud_state()
	local st, intents = s.statuses, s.intents
	c:apply_hot(5, 10, 1)
	c:hud_state(s)
	T.ok(s.statuses == st and s.intents == intents, "same tables")
	T.ok(near(s.statuses.hot.remaining, 10), "hot shown")
	T.eq(s.enemy_name, "Dummy", "enemy name")
	T.eq(#s.intents, 3, "next 3 intents")
	T.eq(s.player_health, 10000, "player HP")
	T.ok(sim ~= nil and Board ~= nil, "fixtures")
end)

T.done()
