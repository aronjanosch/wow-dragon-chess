-- core/enemy.lua (stub): attack cycle incl. wind-up (enemy.gd:512-546),
-- stun / freeze pausing the timer, delay_attack, intents, pauses.
local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "."
local H = dofile(dir .. "/helpers.lua")
local T, ns = H.T, H.ns
local Enemy = ns.Enemy
T.start("enemy_stub_test")

local function near(a, b, eps) return math.abs(a - b) < (eps or 1e-6) end
local HELLHOUND = Enemy.STUBS.hellhound
local W = 8 / 12 -- hellhound wind-up
-- Engine-mechanics cases (stun, freeze, delay) run on a fixed 2.5 s plain hit, independent of the Hellhound tuning.
local SLOW_BITE = {
	id = "slow_bite", name = "Slow Bite", display = "hellhound", max_health = 2250, weak_to_color = 5, is_boss = false,
	windup = 8 / 12,
	rotation = { { id = "slow_bite", name = "Slow Bite", icon = "slow_bite", kind = "plain", is_special = false,
		damage_min = 120, damage_max = 160, cooldown = 2.5 } },
}

local function hits_at(sim)
	local list = {}
	sim:on("enemy_ability_executed", function() list[#list + 1] = sim.now end)
	return list
end

T.case("Hellhound data and the cycle formula", function()
	T.eq(HELLHOUND.max_health, 2250, "HP (hellhound.tres)")
	T.eq(HELLHOUND.weak_to_color, 5, "weak to Topaz")
	local bite = HELLHOUND.rotation[1]
	T.ok(bite.damage_min == 75 and bite.damage_max == 95 and bite.cooldown == 1.4, "Hellhound Bite 75-95, 1.4 s (W1-G3)")
	T.ok(near(Enemy.cycle_time(HELLHOUND, bite), 1.4 + 8 / 12), "cycle = cooldown + wind-up + execute")
end)

T.case("rotation timing incl. wind-up; damage rolled on the combat stream", function()
	local sim, c = H.fight(nil, { def = HELLHOUND })
	local hits = hits_at(sim)
	local windups = H.collect(sim, "enemy_windup")
	local dmg = H.collect(sim, "player_damaged")
	H.tick_to(sim, 10)
	T.eq(#hits, 4, "4 hits in 10 s")
	T.ok(near(windups[1].t, 1.4), "first wind-up at the first cooldown")
	T.ok(near(hits[1], 1.4 + W), "first hit after the wind-up: " .. hits[1])
	T.ok(near(hits[2], 2 * (1.4 + W)), "second one cycle later")
	T.ok(near(hits[3], 3 * (1.4 + W)), "third")
	local total = 0
	for _, d in ipairs(dmg) do
		T.ok(d[1] >= 75 and d[1] <= 95, "roll in 75-95: " .. d[1])
		total = total + d[1]
	end
	T.eq(c.player_health, 10000 - total, "HP")
	-- same seed, same rolls
	local sim2, c2 = H.fight(nil, { def = HELLHOUND })
	H.tick_to(sim2, 10)
	T.eq(c2.player_health, c.player_health, "deterministic rolls")
	-- a tape decides the roll
	local sim3, c3 = H.fight(nil, { def = HELLHOUND, rng_combat = H.tape({ 85 }) })
	H.tick_to(sim3, 2.5)
	T.eq(c3.player_health, 10000 - 85, "rolled value from the tape")
end)

T.case("stun pauses the timer and holds the time left", function()
	local sim, c = H.fight(nil, { def = SLOW_BITE })
	local hits = hits_at(sim)
	H.tick_to(sim, 1)
	c.enemy:apply_stun(3)
	T.ok(near(c.enemy:get_time_to_next_attack(), 3 + 1.5), "stun + held 1.5 s")
	T.eq(c.enemy:get_status_kind(), "stun", "kind")
	H.tick_to(sim, 6.5)
	T.ok(near(hits[1], 1 + 3 + 1.5 + W), "hit after stun + held + wind-up: " .. tostring(hits[1]))
	T.eq(c.enemy:get_status_kind(), "", "stun over")
end)

T.case("freeze and overlapping stuns: the longer one wins", function()
	local sim, c = H.fight(nil, { def = SLOW_BITE })
	local hits = hits_at(sim)
	local st = H.collect(sim, "enemy_status_changed")
	H.tick_to(sim, 1)
	c.enemy:apply_stun(5, "freeze")
	H.tick_to(sim, 2)
	c.enemy:apply_stun(3)
	T.ok(near(c.enemy:get_stun_remaining(), 4), "4 s left (not 3)")
	T.eq(c.enemy:get_stun_duration_max(), 5, "max stays 5")
	H.tick_to(sim, 9)
	T.ok(near(hits[1], 1 + 5 + 1.5 + W), "hit after the freeze: " .. tostring(hits[1]))
	T.eq(st[1][1], "freeze", "freeze event")
	local last = st[#st]
	T.ok(last[2] == false and near(last.t, 6), "stun end event at 6 s")
end)

T.case("delay_attack: +s on the timer; adds to the held time while stunned; lost in the wind-up", function()
	local sim, c = H.fight(nil, { def = SLOW_BITE })
	local hits = hits_at(sim)
	H.tick_to(sim, 1)
	c.enemy:delay_attack(2)
	H.tick_to(sim, 6)
	T.ok(near(hits[1], 2.5 + 2 + W), "delayed by 2 s: " .. tostring(hits[1]))

	local sim2, c2 = H.fight(nil, { def = SLOW_BITE })
	local hits2 = hits_at(sim2)
	H.tick_to(sim2, 1)
	c2.enemy:apply_stun(3)
	c2.enemy:delay_attack(2)
	T.ok(near(c2.enemy:get_time_to_next_attack(), 3 + 1.5 + 2), "delay added to the held time")
	H.tick_to(sim2, 9)
	T.ok(near(hits2[1], 1 + 3 + 3.5 + W), "hit: " .. tostring(hits2[1]))

	local sim3, c3 = H.fight(nil, { def = SLOW_BITE })
	local hits3 = hits_at(sim3)
	H.tick_to(sim3, 2.8) -- the timer fired at 2.5, wind-up until 3.1667
	T.ok(c3.enemy:is_winding_up(), "winding up")
	c3.enemy:delay_attack(2)
	H.tick_to(sim3, 7)
	T.ok(near(hits3[1], 2.5 + W), "the wound-up hit lands on time")
	T.ok(near(hits3[2], 2 * (2.5 + W)), "the delay was lost (timer restarted after the hit)")
end)

T.case("stun during the wind-up: the hit still lands, the next waits for the stun", function()
	local sim, c = H.fight(nil, { def = SLOW_BITE })
	local hits = hits_at(sim)
	H.tick_to(sim, 2.8)
	c.enemy:apply_stun(3)
	H.tick_to(sim, 10)
	T.ok(near(hits[1], 2.5 + W), "wound-up hit lands")
	-- held = the repeating timer's time left at 2.8 (restarted at 2.5): 2.2 s
	T.ok(near(hits[2], 2.8 + 3 + 2.2 + W), "next hit: " .. tostring(hits[2]))
end)

T.case("intents wrap; gameplay pause freezes the enemy; a dead enemy stops", function()
	local def = H.enemy_def({ rotation = {
		{ id = "a", name = "A", damage_min = 10, damage_max = 10, cooldown = 2, is_special = false },
		{ id = "b", name = "B", damage_min = 20, damage_max = 20, cooldown = 3, is_special = true },
	} })
	local sim, c = H.fight(nil, { def = def })
	local up = c.enemy:peek_upcoming(3)
	T.eq(up[1].name .. up[2].name .. up[3].name, "ABA", "next 3 intents wrap")
	local hits = hits_at(sim)
	H.tick_to(sim, 1)
	sim:pause_gameplay()
	H.tick_to(sim, 6)
	T.eq(#hits, 0, "no attack while gameplay is paused")
	sim:resume_gameplay()
	H.tick_to(sim, 11.5) -- (the third attack comes at 9 + B's 3 s)
	T.ok(near(hits[1], 2 + 5), "first attack 5 s later")
	T.ok(near(hits[2], 7 + 2), "after A: A's cooldown (Godot restarts with the used ability's cooldown)")
	T.eq(c.player_health, 10000 - 30, "A then B")
	T.eq(c.enemy:peek_next_ability().name, "A", "rotation index wrapped")
	c:deal_damage_to_enemy(1e9)
	T.ok(c.enemy.dead, "dead")
	T.eq(c.enemy:get_time_to_next_attack(), -1, "rotation stopped")
end)

T.case("Fire Shield reflects the bite into the enemy", function()
	local sim, c = H.fight(nil, { def = HELLHOUND, rng_combat = H.tape({ 85 }) })
	c:apply_fire_shield(10, 1.0)
	H.tick_to(sim, 2.5)
	T.eq(c.player_health, 10000, "no HP lost")
	T.eq(c.enemy.current_health, 2250 - 85, "reflected 85")
end)

T.done()
