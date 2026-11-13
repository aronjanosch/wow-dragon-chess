-- core/enemy.lua + core/enemy_abilities.lua (W0-G2a): rotation, cycle formula, phases, stun /
-- freeze, Aegis, Mirror, Sandstorm, heal block, curse, stagger, flurry, junk, heal self.
-- The plain-hit / stun / delay basics are covered by enemy_stub_test.lua.
local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "."
local H = dofile(dir .. "/helpers.lua")
local T, ns = H.T, H.ns
local Enemy, Data = ns.Enemy, ns.EnemyData
T.start("enemy_test")

local function near(a, b, eps) return math.abs(a - b) < (eps or 1e-6) end

-- Ability table: kind defaults; t overrides.
local function ab(kind, t)
	local a = { id = kind, name = kind, icon = kind, kind = kind, is_special = kind ~= "plain",
		damage_min = 0, damage_max = 0, cooldown = 10 }
	for k, v in pairs(t or {}) do a[k] = v end -- copy; order irrelevant
	return a
end

local function def_of(rotation, opts)
	opts = opts or {}
	local d = H.enemy_def({ rotation = rotation, windup = opts.windup or 1.0, hp = opts.hp })
	d.phases = opts.phases
	return d
end

-- A real Rng whose draws we can compare (state before / after).
local function state_str(rng) return table.concat(rng:get_state(), ",") end

local function names(list)
	local out = {}
	for i = 1, #list do out[i] = list[i].name end
	return table.concat(out, ",")
end

---------------------------------------------------------------- rotation and cycle

T.case("real data: Gordok Ogre rotation, cycle formula, intent kinds", function()
	local cy = Data.by_id.gordok_ogre
	local sim, c = H.fight(nil, { def = cy })
	local W = cy.windup
	local ex = H.collect(sim, "enemy_ability_executed")
	local up = c.enemy:peek_upcoming(3)
	T.eq(names(up), "Ogre Punch,Ogre Smash,Ogre Punch", "next intents wrap")
	T.eq(up[2].kind, "stagger", "intent carries the kind for the glyph")
	H.tick_to(sim, 20)
	T.ok(near(ex[1].t, 3 + W), "poke after its cooldown + wind-up: " .. ex[1].t)
	T.eq(ex[1][1].name, "Ogre Punch", "first")
	T.ok(near(ex[2].t, 3 + W + 3 + W), "club one poke-cooldown later: " .. ex[2].t)
	T.eq(ex[2][1].name, "Ogre Smash", "second")
	T.ok(near(ex[3].t, ex[2].t + 8 + W), "back to the poke after the club's 8 s: " .. ex[3].t)
	T.ok(near(Enemy.cycle_time(cy, cy.rotation[2]), 8 + W), "cycle_time: cooldown + wind-up + execute 0")
end)

T.case("the in-flight guard skips a timeout while a hit is still winding up", function()
	-- an invalid data set on purpose (cooldown 0.4 < wind-up 1.0): the data test forbids it
	local d = def_of({ ab("plain", { damage_min = 10, damage_max = 10, cooldown = 0.4 }) }, { windup = 1.0 })
	local sim, c = H.fight(nil, { def = d })
	local most, hits = 0, 0
	sim:on("enemy_ability_executed", function() hits = hits + 1 end)
	for _ = 1, 400 do
		sim:tick(0.05)
		if #c.enemy.hits > most then most = #c.enemy.hits end
	end
	T.eq(most, 1, "never two hits in flight")
	T.ok(hits >= 5, "still attacks: " .. hits)
end)

---------------------------------------------------------------- flurry (MultiHit)

T.case("flurry: count first, then one roll per hit, gaps of hit_interval, cooldown after the last", function()
	local fl = ab("flurry", { damage_min = 80, damage_max = 110, hit_count_min = 3, hit_count_max = 4,
		hit_interval = 0.12, cooldown = 10 })
	local tape = H.tape({ 4, 90, 81, 110, 95 })
	local sim, c = H.fight(nil, { def = def_of({ fl }), rng_combat = tape })
	local dmg = H.collect(sim, "player_damaged")
	H.tick_to(sim, 12)
	T.eq(tape.draws, 5, "1 count + 4 damage draws")
	T.eq(#dmg, 4, "4 hits")
	local want = { 90, 81, 110, 95 }
	for i = 1, 4 do
		T.eq(dmg[i][1], want[i], "hit " .. i .. " damage")
		T.ok(near(dmg[i].t, 11 + (i - 1) * 0.12), "hit " .. i .. " time " .. dmg[i].t)
	end
	T.eq(c.player_health, 10000 - 376, "HP")
	-- the timer restarted when the last hit was done: next timeout 10 s after 11.36
	local ex = H.collect(sim, "enemy_windup")
	H.tick_to(sim, 22)
	T.ok(near(ex[1].t, 11.36 + 10), "next attack 10 s after the flurry's end: " .. tostring(ex[1] and ex[1].t))
end)

T.case("settle_now mid-flurry deals 0 hits (the clock is frozen); the flurry resumes after", function()
	local fl = ab("flurry", { damage_min = 50, damage_max = 50, hit_count_min = 4, hit_count_max = 4,
		hit_interval = 0.12, cooldown = 10 })
	local sim, c = H.fight(nil, { def = def_of({ fl }) })
	local dmg = H.collect(sim, "player_damaged")
	H.tick_to(sim, 11.01) -- hit 1 landed at 11.0
	T.eq(#dmg, 1, "one hit so far")
	T.ok(c.enemy:is_executing(), "mid-flurry")
	T.ok(c:settle_now(), "board reaches rest")
	T.eq(#dmg, 1, "settle_now fired no remaining hit")
	T.ok(c.enemy:is_executing(), "still mid-flurry")
	H.tick_to(sim, 11.5)
	T.eq(#dmg, 4, "the rest follows on the clock")
	T.ok(near(dmg[2].t, 11.12 + 0.0, 0.06), "hit 2 on schedule (frozen time kept): " .. dmg[2].t)
end)

T.case("gameplay pause freezes a flurry; stun doesn't cancel it; death / game over end it", function()
	local fl = ab("flurry", { damage_min = 50, damage_max = 50, hit_count_min = 4, hit_count_max = 4,
		hit_interval = 0.12, cooldown = 10 })
	local sim, c = H.fight(nil, { def = def_of({ fl }) })
	local dmg = H.collect(sim, "player_damaged")
	H.tick_to(sim, 11.01)
	sim:pause_gameplay()
	H.tick_to(sim, 15)
	T.eq(#dmg, 1, "paused: no hit")
	sim:resume_gameplay()
	H.tick_to(sim, 15.5)
	T.eq(#dmg, 4, "resumed: all hits")

	-- stun during the flurry: remaining hits land, the next attack waits for the stun
	local sim2, c2 = H.fight(nil, { def = def_of({ fl }) })
	local dmg2 = H.collect(sim2, "player_damaged")
	H.tick_to(sim2, 11.01)
	c2.enemy:apply_stun(5)
	H.tick_to(sim2, 12)
	T.eq(#dmg2, 4, "stun doesn't stop the running flurry")
	T.ok(c2.enemy:get_time_to_next_attack() > 4, "timer held by the stun")

	-- the enemy dies mid-flurry: no more hits
	local sim3, c3 = H.fight(nil, { def = def_of({ fl }) })
	local dmg3 = H.collect(sim3, "player_damaged")
	H.tick_to(sim3, 11.01)
	c3:deal_damage_to_enemy(1e9)
	T.ok(c3.fight_over, "enemy dead")
	sim3:resume_gameplay() -- the kill pauses gameplay; lift it to prove the flurry itself stopped
	H.tick_to(sim3, 14)
	T.eq(#dmg3, 1, "no hits after the kill")

	-- the player dies mid-flurry: the rest is skipped
	local sim4, c4 = H.fight(nil, { def = def_of({ fl }) })
	c4.player_health = 80
	local dmg4 = H.collect(sim4, "player_damaged")
	H.tick_to(sim4, 14)
	T.ok(c4.game_over, "player dead")
	T.eq(#dmg4, 2, "hit 1 (30 left)... hit 2 kills; hits 3-4 skipped")
end)

---------------------------------------------------------------- stagger

T.case("stagger: stuns only when the hit reaches HP; shield / Fire Shield eat the stun", function()
	local st = ab("stagger", { damage_min = 100, damage_max = 100, stun_duration = 2.5, cooldown = 5 })
	local sim, c = H.fight(nil, { def = def_of({ st }) })
	local res = H.collect(sim, "stagger_resolved")
	H.tick_to(sim, 6.5)
	T.eq(c.player_health, 9900, "the hit")
	T.ok(c:status_remaining("stun") > 1.9, "player stunned 2.5 s (2.0 left 0.5 s later)")
	T.eq(c:can_player_swap(), "stunned", "input locked")
	T.eq(res[1][1], true, "stagger_resolved(true)")

	local sim2, c2 = H.fight(nil, { def = def_of({ st }) })
	c2:add_shield_stack(0)
	local res2 = H.collect(sim2, "stagger_resolved")
	H.tick_to(sim2, 6.5)
	T.eq(c2.player_health, 10000, "blocked")
	T.eq(c2:status_remaining("stun"), 0, "a shield eats the stun too")
	T.eq(res2[1][1], false, "stagger_resolved(false)")

	local sim3, c3 = H.fight(nil, { def = def_of({ st }) })
	c3:apply_fire_shield(20, 1.0)
	H.tick_to(sim3, 6.5)
	T.eq(c3:status_remaining("stun"), 0, "Fire Shield reflect: no stun")

	-- a stagger with damage 0 always stuns
	local z = ab("stagger", { damage_min = 0, damage_max = 0, stun_duration = 3.0, cooldown = 5 })
	local sim4, c4 = H.fight(nil, { def = def_of({ z }) })
	c4:add_shield_stack(0)
	H.tick_to(sim4, 6.5)
	T.ok(c4:status_remaining("stun") > 2.4, "0-damage stagger stuns even with a shield up")
	T.eq(c4.status.shield.stacks, 1, "and doesn't consume it")
end)

T.case("stagger in god mode: no hit, no stun, no RNG", function()
	local st = ab("stagger", { damage_min = 100, damage_max = 150, stun_duration = 2.5, cooldown = 5 })
	local rng = ns.Rng.new(99)
	local before = state_str(rng)
	local sim, c = H.fight(nil, { def = def_of({ st }), rng_combat = rng })
	c.god_mode = true
	H.tick_to(sim, 7)
	T.eq(c:status_remaining("stun"), 0, "no stun")
	T.eq(c.player_health, 10000, "no damage")
	T.eq(state_str(rng), before, "no RNG consumed")
end)

---------------------------------------------------------------- heal block / curse / heal / aegis RNG

T.case("heal block: the hit lands first (pre-execute roll), then healing x0; applies when the hit is blocked", function()
	local hb = ab("heal_block", { damage_min = 100, damage_max = 100, duration = 15, cooldown = 5 })
	local sim, c = H.fight(nil, { def = def_of({ hb }) })
	local log = {}
	sim:on("player_damaged", function() log[#log + 1] = "hit" end)
	sim:on("status_changed", function(id, active) if id == "heal_block" and active then log[#log + 1] = "block" end end)
	H.tick_to(sim, 6.5)
	T.eq(table.concat(log, ","), "hit,block", "order: hit, then the window")
	T.ok(c:status_remaining("heal_block") > 14.4, "15 s window")

	local sim2, c2 = H.fight(nil, { def = def_of({ hb }) })
	c2:add_shield_stack(0)
	H.tick_to(sim2, 6.5)
	T.eq(c2.player_health, 10000, "hit eaten")
	T.ok(c2:status_remaining("heal_block") > 14, "the window still lands")

	local sim3, c3 = H.fight(nil, { def = def_of({ hb }) })
	c3.god_mode = true
	H.tick_to(sim3, 6.5)
	T.eq(c3:status_remaining("heal_block"), 0, "not in god mode")
end)

T.case("curse: player damage x multiplier for the window", function()
	local cu = ab("curse", { damage_multiplier = 0.7, duration = 8, cooldown = 5 })
	local idle = ab("plain", { damage_min = 0, damage_max = 0, cooldown = 1000 })
	local sim, c = H.fight(nil, { def = def_of({ cu, idle }) })
	H.tick_to(sim, 6.5)
	T.eq(c:curse_multiplier(), 0.7, "cursed")
	local before = c.enemy.current_health
	c:deal_damage_to_enemy(100)
	T.eq(before - c.enemy.current_health, 70, "damage x0.7")
	H.tick_to(sim, 6.0 + 8.1)
	T.eq(c:curse_multiplier(), 1.0, "expired")
end)

T.case("heal self: % of max HP (rounded), capped, not blocked by player heal block", function()
	local hs = ab("heal", { heal_percent = 0.08, cooldown = 5 })
	local sim, c = H.fight(nil, { def = def_of({ hs }, { hp = 5000 }) })
	c.enemy.current_health = 2000
	c:apply_heal_block(60) -- the PLAYER's block: irrelevant to the enemy
	H.tick_to(sim, 6.5)
	T.eq(c.enemy.current_health, 2400, "+8 % of 5000")
	c.enemy.current_health = 4900
	H.tick_to(sim, 6.0 + 1.0 + 5.0 + 1.0) -- the second cast
	T.eq(c.enemy.current_health, 5000, "capped at max")
end)

T.case("0-damage abilities consume no RNG; pre-roll abilities do", function()
	for _, kind in ipairs({ "aegis", "mirror", "curse", "heal", "sand", "junk" }) do
		local a = ab(kind, { cooldown = 5, duration = 8, reflect_fraction = 0.5, break_damage = 100,
			break_stun = 1, damage_multiplier = 0.7, heal_percent = 0.05, factor = 0.3, junk_count = 1 })
		local rng = ns.Rng.new(5)
		local before = state_str(rng)
		local sim = H.fight(nil, { def = def_of({ a }), rng_combat = rng })
		H.tick_to(sim, 8)
		T.eq(state_str(rng), before, kind .. ": no draws")
	end
	local p = ab("plain", { damage_min = 10, damage_max = 20, cooldown = 5 })
	local rng = ns.Rng.new(5)
	local before = state_str(rng)
	local sim = H.fight(nil, { def = def_of({ p }), rng_combat = rng })
	H.tick_to(sim, 8)
	T.ok(state_str(rng) ~= before, "a ranged plain hit draws")
end)

---------------------------------------------------------------- Divine Aegis

T.case("Divine Aegis: ability / bomb damage 0, stun / freeze bounce, match + delay_attack work, expiry", function()
	local ae = ab("aegis", { duration = 7, cooldown = 3 })
	local sim, c = H.fight(nil, { def = def_of({ ae, ab("plain", { damage_min = 10, damage_max = 10, cooldown = 3 }) }, { windup = 0.5 }) })
	local imm = H.collect(sim, "enemy_immune")
	H.tick_to(sim, 3.6) -- cast at 3.5
	T.ok(c.enemy:is_spell_immune(), "immune")
	local hud = c:hud_state()
	T.ok(near(hud.enemy_aegis_remaining, 6.9, 0.2) and hud.enemy_aegis_max == 7, "hud aegis remaining / max")

	local hp = c.enemy.current_health
	c.cur_source = "ability"
	c:deal_damage_to_enemy(100)
	c.cur_source = ""
	T.eq(c.enemy.current_health, hp, "ability damage 0")
	T.eq(imm[#imm][1], "damage", "IMMUNE (damage)")
	c.cur_source = "bomb"
	c:deal_damage_to_enemy(50)
	c.cur_source = ""
	T.eq(c.enemy.current_health, hp, "bomb damage 0")

	c:on_gems_cleared({ [0] = 3 }, { 0 })
	T.eq(c.enemy.current_health, hp - 30, "match damage still works")

	c.enemy:apply_stun(3)
	T.eq(c.enemy:get_stun_remaining(), 0, "stun bounces")
	T.eq(imm[#imm][1], "stun", "IMMUNE (stun)")
	c.enemy:apply_stun(3, "freeze")
	T.eq(imm[#imm][1], "freeze", "freeze bounces")
	c.enemy:apply_slow(3)
	T.eq(c.enemy:get_slow_remaining(), 0, "slow ignored")

	local left = c.enemy:get_time_to_next_attack()
	c.enemy:delay_attack(2)
	T.ok(near(c.enemy:get_time_to_next_attack(), left + 2, 1e-6), "delay_attack still applies")

	H.tick_to(sim, 3.5 + 7.1)
	T.ok(not c.enemy:is_spell_immune(), "expired after 7 s")
	T.eq(c.enemy:get_immune_remaining(), 0, "no remaining")
	c.cur_source = "ability"
	c:deal_damage_to_enemy(100)
	c.cur_source = ""
	T.ok(c.enemy.current_health < hp - 30, "ability damage works again")

	-- recast takes the longer window; reflect still works while immune
	c.enemy:apply_spell_immunity(2)
	c.enemy:apply_spell_immunity(1)
	T.eq(c.enemy:get_immune_duration_max(), 2, "max stays the longer one")
end)

---------------------------------------------------------------- Mirror Shield

T.case("Mirror Shield: reflects ability damage as true damage, match damage cracks it, break stuns", function()
	local sim, c = H.fight(nil, { def = def_of({ ab("plain", { damage_min = 1, damage_max = 1, cooldown = 1000 }) }) })
	local ev = H.collect(sim, "enemy_mirror_changed")
	local pd = H.collect(sim, "player_damaged")
	c.enemy:apply_mirror_shield(8, 0.6, 500, 1.0)
	T.eq(ev[1][1], true, "event: up")
	T.ok(c.enemy:is_mirror_up(), "up")
	T.eq(c.enemy:get_mirror_fraction(), 0.6, "fraction")

	c.cur_source = "ability"
	c:deal_damage_to_enemy(200)
	c.cur_source = ""
	T.eq(pd[1][1], 120, "round(200 x 0.6) = 120 true damage")
	T.eq(pd[1][2], "mirror", "source mirror")
	T.eq(c.player_health, 9880, "HP")
	c:add_shield_stack(0)
	c.cur_source = "bomb"
	c:deal_damage_to_enemy(50)
	c.cur_source = ""
	T.eq(c.player_health, 9850, "true damage ignores the shield stack (bomb reflected 30)")

	T.eq(c.enemy:get_mirror_crack_ratio(), 0, "ability damage doesn't crack")
	c:on_gems_cleared({ [0] = 30 }, { 0 }) -- 300 match damage
	T.ok(near(c.enemy:get_mirror_crack_ratio(), 0.6), "crack 300 / 500")
	T.ok(c.enemy:is_mirror_up(), "still up")
	c:on_gems_cleared({ [0] = 25 }, { 0 }) -- 250 -> 550 >= 500
	T.ok(not c.enemy:is_mirror_up(), "shattered")
	T.eq(ev[#ev][1], false, "event: down")
	T.eq(ev[#ev][2], true, "broken = true")
	T.ok(c.enemy:get_stun_remaining() > 0.9, "enemy stunned break_stun s")
	c.cur_source = "ability"
	c:deal_damage_to_enemy(200)
	c.cur_source = ""
	T.eq(#pd, 2, "no more reflect after the break (ability + bomb only)")
end)

T.case("Mirror Shield: expiry, re-cast resets the crack counter, Aegis blocks the break stun", function()
	local sim, c = H.fight(nil, { def = def_of({ ab("plain", { damage_min = 1, damage_max = 1, cooldown = 1000 }) }) })
	local ev = H.collect(sim, "enemy_mirror_changed")
	c.enemy:apply_mirror_shield(8, 0.5, 400, 1.0)
	c:on_gems_cleared({ [0] = 20 }, { 0 }) -- 200
	T.ok(near(c.enemy:get_mirror_crack_ratio(), 0.5), "half cracked")
	c.enemy:apply_mirror_shield(8, 0.5, 400, 1.0)
	T.eq(c.enemy:get_mirror_crack_ratio(), 0, "re-cast resets the crack counter")
	H.tick_to(sim, 8.1)
	T.ok(not c.enemy:is_mirror_up(), "expired")
	T.eq(ev[#ev][1], false, "event: down")
	T.eq(ev[#ev][2], false, "broken = false (expiry)")

	local imm = H.collect(sim, "enemy_immune")
	c.enemy:apply_spell_immunity(7)
	c.enemy:apply_mirror_shield(8, 0.5, 100, 2.0)
	c:on_gems_cleared({ [0] = 12 }, { 0 }) -- 120 >= 100
	T.ok(not c.enemy:is_mirror_up(), "shattered")
	T.eq(c.enemy:get_stun_remaining(), 0, "the break stun bounces off Aegis")
	T.eq(imm[#imm][1], "stun", "IMMUNE (stun)")

	-- hud_state
	c.enemy:apply_mirror_shield(8, 0.5, 400, 1.0)
	local h = c:hud_state()
	T.ok(h.enemy_mirror_remaining > 7.9 and h.enemy_mirror_max == 8, "hud mirror remaining / max")
	T.eq(h.enemy_mirror_crack_ratio, 0, "hud crack ratio")
end)

---------------------------------------------------------------- Sandstorm / junk

T.case("Sandstorm: board gravity slow for the window (the sim's gravity slow)", function()
	local sa = ab("sand", { factor = 0.3, duration = 8, cooldown = 3 })
	local sim, c = H.fight(nil, { def = def_of({ sa, ab("plain", { cooldown = 1000 }) }, { windup = 0.5 }) })
	local ev = H.collect(sim, "gravity_slow_changed")
	H.tick_to(sim, 3.7)
	T.eq(sim:get_gravity_slow_factor(), 0.3, "factor 0.3")
	T.ok(sim:get_gravity_slow_remaining() > 7.5, "8 s window")
	T.eq(ev[1][1], true, "event")
	H.tick_to(sim, 3.5 + 8.2)
	T.eq(sim:get_gravity_slow_factor(), 1.0, "over")
end)

T.case("Spawn Junk: telegraph, then plain gems become junk; the cooldown starts after it", function()
	local jk = ab("junk", { junk_count = 3, cooldown = 2 })
	local pl = ab("plain", { damage_min = 10, damage_max = 10, cooldown = 2 })
	local sim, c = H.fight(nil, { def = def_of({ jk, pl }, { windup = 0.5 }), seed = 3 })
	local made = H.collect(sim, "junk_spawned")
	local pd = H.collect(sim, "player_damaged")
	H.tick_to(sim, 2.6)
	T.ok(c.enemy:is_executing(), "telegraphing")
	T.eq(#made, 0, "no junk yet")
	H.tick_to(sim, 3.2)
	T.eq(#made, 1, "junk_spawned")
	T.ok(near(made[1].t, 2.5 + 0.62), "after the 0.62 s telegraph: " .. made[1].t)
	local junk = 0
	for i = 1, 64 do if c.sim.board.cells[i].junk then junk = junk + 1 end end
	T.eq(junk, 3, "3 junk gems")
	H.tick_to(sim, 7)
	T.ok(near(pd[1].t, 2.5 + 0.62 + 2 + 0.5), "next attack: cooldown counted from the junk's end: " .. tostring(pd[1] and pd[1].t))
end)

---------------------------------------------------------------- phases

local function phase_def(extra_first)
	local base = { ab("plain", { id = "base", name = "Base", damage_min = 10, damage_max = 10, cooldown = 7 }) }
	local p1 = { ab("plain", { id = "p1a", name = "P1a", damage_min = 20, damage_max = 20, cooldown = 4 }),
		ab("plain", { id = "p1b", name = "P1b", damage_min = 20, damage_max = 20, cooldown = 6 }) }
	local p2 = { ab("plain", { id = "p2", name = "P2", damage_min = 30, damage_max = 30, cooldown = 5 }) }
	return def_of(base, { hp = 1000, phases = {
		{ hp_fraction = 0.66, phase_name = "One", rotation = extra_first or p1 },
		{ hp_fraction = 0.33, phase_name = "", rotation = p2 },
	} }), base, p1, p2
end

T.case("phases: threshold <= hp_fraction, label, rotation swap by reference, timer restart", function()
	local d, base, p1 = phase_def()
	local sim, c = H.fight(nil, { def = d })
	local ev = H.collect(sim, "enemy_phase_changed")
	local e = c.enemy
	H.tick_to(sim, 8.5) -- one base attack done (cooldown 7 + wind-up 1)
	T.eq(e.rotation_index, 1, "base rotation wrapped")
	c:deal_damage_to_enemy(339) -- 661 left: above 66 %
	T.eq(#ev, 0, "just above the threshold: nothing")
	c:deal_damage_to_enemy(1) -- 660 = exactly 66 %
	T.eq(#ev, 1, "<= hp_fraction triggers")
	T.eq(ev[1][1], "One", "label")
	T.ok(e.rotation == p1, "rotation swapped by reference")
	T.ok(d.rotation == base and #base == 1, "the def's own rotation untouched")
	T.eq(e.rotation_index, 1, "index reset")
	T.eq(e.phase_name, "One", "hud phase_name")
	T.eq(c:hud_state().enemy_phase_name, "One", "hud_state phase_name")
	T.ok(near(e:get_time_to_next_attack(), 4), "timer restarted with the new rotation's first cooldown")
	T.eq(names(e:peek_upcoming(2)), "P1a,P1b", "intents rebound")
end)

T.case("phases: one hit can cross two thresholds; label default; healing never un-phases; lethal hit has none", function()
	local d = phase_def()
	local sim, c = H.fight(nil, { def = d })
	local ev = H.collect(sim, "enemy_phase_changed")
	c:deal_damage_to_enemy(800) -- 200 left: both thresholds in order
	T.eq(#ev, 2, "two phases at once")
	T.eq(ev[1][1], "One", "first")
	T.eq(ev[2][1], "Phase 3", "empty label defaults to 'Phase N' (applied 2 + 1)")
	T.eq(c.enemy.rotation[1].name, "P2", "the last rotation wins")
	c.enemy:heal(700)
	c:deal_damage_to_enemy(10)
	T.eq(#ev, 2, "healing back above a threshold doesn't re-trigger")

	local sim2, c2 = H.fight(nil, { def = phase_def() })
	local ev2 = H.collect(sim2, "enemy_phase_changed")
	c2:deal_damage_to_enemy(1000)
	T.eq(#ev2, 0, "no phase on a lethal hit")
	T.ok(c2.enemy.dead, "dead")
end)

T.case("phases: empty rotation skipped, stunned enemy keeps its held timer, invincible never phases, reflect can trigger", function()
	-- empty rotation: skipped without an event, the next phase still applies
	local base = { ab("plain", { id = "b", name = "B", damage_min = 1, damage_max = 1, cooldown = 7 }) }
	local p2 = { ab("plain", { id = "q", name = "Q", damage_min = 1, damage_max = 1, cooldown = 5 }) }
	local d = def_of(base, { hp = 1000, phases = {
		{ hp_fraction = 0.66, phase_name = "Empty", rotation = {} },
		{ hp_fraction = 0.33, phase_name = "Real", rotation = p2 },
	} })
	local sim, c = H.fight(nil, { def = d })
	local ev = H.collect(sim, "enemy_phase_changed")
	c:deal_damage_to_enemy(400)
	T.eq(#ev, 0, "empty phase: no event")
	T.ok(c.enemy.rotation == base, "rotation unchanged")
	T.eq(c.enemy.phases_applied, 1, "but consumed")
	c:deal_damage_to_enemy(300)
	T.eq(ev[1][1], "Real", "the next phase applies")

	-- stunned: the rotation swaps, the held timer is not restarted
	local sim2, c2 = H.fight(nil, { def = phase_def() })
	H.tick_to(sim2, 1)
	c2.enemy:apply_stun(5)
	local held = c2.enemy:get_time_to_next_attack()
	c2:deal_damage_to_enemy(400)
	T.eq(c2.enemy.phase_name, "One", "phase applied while stunned")
	T.ok(near(c2.enemy:get_time_to_next_attack(), held), "timer not restarted while stunned")
	T.ok(not c2.enemy.is_active, "still inactive")

	-- invincible: no HP loss, no phase
	local sim3, c3 = H.fight(nil, { def = phase_def() })
	c3.enemy.invincible = true
	c3:deal_damage_to_enemy(900)
	T.eq(c3.enemy.current_health, 1000, "invincible")
	T.eq(c3.enemy.phases_applied, 0, "no phase")

	-- Fire Shield reflect damage can cross a threshold
	local big = ab("plain", { damage_min = 700, damage_max = 700, cooldown = 3 })
	local d4 = def_of({ big }, { hp = 1000, phases = { { hp_fraction = 0.66, phase_name = "Thorns", rotation = p2 } } })
	local sim4, c4 = H.fight(nil, { def = d4 })
	local ev4 = H.collect(sim4, "enemy_phase_changed")
	c4:apply_fire_shield(30, 1.0)
	H.tick_to(sim4, 5)
	T.eq(ev4[1] and ev4[1][1], "Thorns", "reflected damage triggered the phase")
end)

T.case("real data: Nefarian phases at 66 % and 33 %", function()
	local wd = Data.by_id.nefarian
	local sim, c = H.fight(nil, { def = wd })
	local ev = H.collect(sim, "enemy_phase_changed")
	local e = c.enemy
	c:deal_damage_to_enemy(13750 - 9076) -- 9076 left: 0.660072 > 0.66
	T.eq(#ev, 0, "just above 66 %")
	c:deal_damage_to_enemy(1) -- 9075 = exactly 66 %
	T.eq(ev[1] and ev[1][1], "Shadow Flame", "phase 1")
	T.eq(names(e:peek_upcoming(3)), "Claw Flurry,Veil of Shadow,Wing Buffet", "phase 2 kit")
end)

T.case("real data: Nefarian second phase", function()
	local wd = Data.by_id.nefarian
	local sim, c = H.fight(nil, { def = wd })
	local ev = H.collect(sim, "enemy_phase_changed")
	c:deal_damage_to_enemy(13750 - 4538) -- 4538 left
	T.eq(#ev, 1, "4538 / 13750 = 0.33003 > 0.33: only phase 1")
	c:deal_damage_to_enemy(1) -- 4537 -> 0.32996
	T.eq(#ev, 2, "phase 2")
	T.eq(ev[2][1], "Corrupted", "Corrupted")
	T.eq(names(c.enemy:peek_upcoming(3)), "Blinding Ash,Shadow Flame Breath,Mirror Scales", "phase 3 kit")
	T.eq(wd.rotation[1].name, "Wing Buffet", "data untouched")
end)

---------------------------------------------------------------- misc

T.case("nuke is delayed by stun / delay_attack like any attack; kinds flow through hud_state", function()
	local nk = ab("nuke", { damage_min = 800, damage_max = 800, cooldown = 8.5 })
	local sim, c = H.fight(nil, { def = def_of({ nk }) })
	local dmg = H.collect(sim, "player_damaged")
	H.tick_to(sim, 2)
	c.enemy:apply_stun(3)
	H.tick_to(sim, 8.5 + 3 + 1.0 + 0.1)
	T.eq(#dmg, 1, "the nuke lands")
	T.ok(near(dmg[1].t, 8.5 + 3 + 1.0), "after the stun: " .. dmg[1].t)
	T.eq(c:hud_state().intents[1].kind, "nuke", "intent kind")
end)

T.case("dispose drops every timer; a replaced enemy's wind-up never lands", function()
	local d = def_of({ ab("plain", { damage_min = 10, damage_max = 10, cooldown = 2 }) }, { windup = 1.0 })
	local sim, c = H.fight(nil, { def = d })
	local old = c.enemy
	local ex = H.collect(sim, "enemy_ability_executed")
	H.tick_to(sim, 2.5) -- wind-up running
	c.enemy.invincible = false
	c:start_fight(H.enemy_def({ cooldown = 1000 }))
	H.tick_to(sim, 6)
	T.eq(#ex, 0, "the old enemy's hit is gone")
	T.ok(old.disposed, "disposed")
	T.eq(#old.hits, 0, "no wind-ups left")
end)

T.done()
