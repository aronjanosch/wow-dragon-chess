-- core/abilities + core/kit.lua: each of the 12 abilities on a known board
-- (shape, direct damage, score, status), chains, partner colour, the Color
-- Swap one-colour rule, the Polymorph brake, an ability gem on its own spawn
-- cell, the 6/7 multiplier, banner texts (mirrors ability_gems_test).
local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "."
local H = dofile(dir .. "/helpers.lua")
local T, ns = H.T, H.ns
local Kit, Combat = ns.Kit, ns.Combat
T.start("ability_test")

local function near(a, b, eps) return math.abs(a - b) < (eps or 1e-6) end

-- Drain the queue the way a resolve pass does (sim._resolve_pass): gravity
-- deferred and cascades held until the queue is empty, then gravity + resolve.
local function drain_like_pass(sim, c)
	sim:spawn(function()
		sim.awaiting_drain, sim.defer_gravity = true, true
		c:_drain_ability_queue()
		sim.awaiting_drain, sim.defer_gravity = false, false
		sim:_animate_gravity_and_spawn()
		sim:mark_resolve_needed()
	end)
end

-- Queue one activation (like a chain hit) and run the board to rest.
local function fire(sim, c, info)
	info.source = info.source or "chain"
	info.partner_color = info.partner_color or -1
	info.match_length = info.match_length or 0
	info.is_bomb = info.is_bomb or false
	c.queue[#c.queue + 1] = info
	drain_like_pass(sim, c)
	T.ok(H.run(sim, 1 / 60, 120), "rest after " .. tostring(info.gem_type) .. "/" .. tostring(info.tier))
	local ok, err = sim.board:check_integrity(true)
	T.ok(ok, err)
end

local function first_ability_packet(dealt)
	for _, d in ipairs(dealt) do
		if d[3] == "ability" or d[3] == "bomb" then
			-- direct packets carry the ability colour; clear packets come per colour
			return d
		end
	end
end

-- Wrap a sim primitive to record its arguments / result.
local function spy(sim, name)
	local calls = {}
	local orig = ns.Sim[name]
	sim[name] = function(s, ...)
		local args = { ... }
		local r = orig(s, ...)
		args.result = r
		calls[#calls + 1] = args
		return r
	end
	return calls
end

T.case("kit: default mapping, tiers, a different kit swaps abilities (W1)", function()
	local kit = Kit.default()
	local names = {}
	for color = 0, 5 do
		names[#names + 1] = kit:get(color, 1).name .. "/" .. kit:get(color, 2).name
	end
	T.eq(table.concat(names, ","), "Rejuvenation/Lay on Hands,Hammer of Justice/Mind Control,Power Word: Shield/Rain of Fire,Flamestrike/Fire Shield,"
		.. "Arcane Explosion/Frost Nova,Whirlwind/Chain Lightning", "Godot kits")
	T.eq(kit:get(3, 0), nil, "tier 0 has no ability")
	T.ok(kit:get(3, 1) ~= ns.Abilities.flamestrike, "kit holds copies, not the shared definitions")
	local other = Kit.new({ [3] = { "whirlwind", "frost_nova" } })
	T.eq(other:get(3, 1).name, "Whirlwind", "another kit maps another ability onto Ruby")
	T.eq(other:get(4, 1), nil, "colours without an entry have none")
end)

T.case("Flamestrike: 150 dmg, cone toward the enemy, 150 score", function()
	local sim, c = H.fight(nil)
	local dealt = H.collect(sim, "damage_dealt")
	local by_effect = H.collect(sim, "gems_cleared_by_effect")
	local trig = H.collect(sim, "ability_triggered")
	local awarded = H.collect(sim, "score_awarded")
	fire(sim, c, { col = 2, row = 4, gem_type = 3, tier = 1 })
	local p = first_ability_packet(dealt)
	T.eq(p[1], 150, "direct damage")
	T.eq(p[2], 3, "Ruby")
	T.eq(#by_effect[1][1], 14, "cone 1+1+1+3+3+5")
	T.eq(trig[1][1].toast, "FLAMESTRIKE", "banner toast")
	T.eq(trig[1][1].blurb, "Cone-clear toward the enemy", "banner blurb")
	T.eq(trig[1][1].icon, "flamestrike", "icon key")
	T.eq(awarded[1][1], 150, "score")
end)

T.case("Fire Shield: 12 s, blocks and reflects the hit + bonus", function()
	local sim, c = H.fight(nil)
	fire(sim, c, { col = 0, row = 0, gem_type = 3, tier = 2 })
	T.ok(c:status_remaining("fire_shield") > 11, "up for ~12 s")
	T.eq(c:status_max("fire_shield"), 12, "max 12")
	T.eq(c:take_damage(200), "reflect", "reflects")
	T.eq(100000 - c.enemy.current_health, 300, "reflected = hit 200 + bonus 100, one number")
end)

T.case("Arcane Explosion: 150 dmg, 3x3, enemy attack +2 s and slow window", function()
	local sim, c = H.fight(nil, { def = H.enemy_def({ cooldown = 8 }) })
	local dealt = H.collect(sim, "damage_dealt")
	local by_effect = H.collect(sim, "gems_cleared_by_effect")
	local t0, left0 = sim.now, c.enemy:get_time_to_next_attack()
	fire(sim, c, { col = 3, row = 3, gem_type = 4, tier = 1 })
	T.eq(first_ability_packet(dealt)[1], 150, "direct damage")
	T.eq(#by_effect[1][1], 9, "3x3")
	T.ok(near(c.enemy:get_time_to_next_attack(), left0 + 2 - (sim.now - t0)), "next attack 2 s later")
	T.ok(c.enemy:get_slow_remaining() > 0 and c.enemy:get_slow_duration_max() == 2, "slow window 2 s")
end)

T.case("Frost Nova: 500 dmg, enemy frozen 5 s, timer held", function()
	local sim, c = H.fight(nil, { def = H.enemy_def({ cooldown = 8 }) })
	local dealt = H.collect(sim, "damage_dealt")
	fire(sim, c, { col = 3, row = 3, gem_type = 4, tier = 2 })
	T.eq(first_ability_packet(dealt)[1], 500, "direct damage")
	T.eq(c.enemy:get_status_kind(), "freeze", "kind freeze")
	T.ok(near(c.enemy:get_stun_remaining(), 5, 0.05), "5 s (minus the frame to rest)")
	T.ok(near(c.enemy:get_time_to_next_attack() - c.enemy:get_stun_remaining(), 8), "stun + held timer (8 s)")
end)

T.case("Whirlwind: 150 dmg, whole row outward from the gem", function()
	local sim, c = H.fight(nil)
	local dealt = H.collect(sim, "damage_dealt")
	local by_effect = H.collect(sim, "gems_cleared_by_effect")
	fire(sim, c, { col = 3, row = 2, gem_type = 5, tier = 1 })
	T.eq(first_ability_packet(dealt)[1], 150, "direct damage")
	local cells = {}
	for i, e in ipairs(by_effect[1][1]) do cells[i] = e.col .. "," .. e.row end
	T.eq(table.concat(cells, " "), "3,2 4,2 2,2 5,2 1,2 6,2 0,2 7,2", "row, right first per distance")
end)

T.case("Chain Lightning: partner colour from the swap, random other colour on a chain", function()
	local sim, c = H.fight(nil)
	local n2 = 0
	for i = 1, 64 do if sim.board.cells[i].type == 2 then n2 = n2 + 1 end end
	local chained = spy(sim, "clear_color_chained")
	local dealt = H.collect(sim, "damage_dealt")
	fire(sim, c, { col = 0, row = 0, gem_type = 5, tier = 2, partner_color = 2 })
	T.eq(chained[1][1], 2, "partner colour 2")
	T.eq(chained[1].result.count, n2, "every colour-2 gem")
	T.eq(first_ability_packet(dealt)[1], n2 * 10, "no direct damage: only the cleared gems (source ability)")
	-- chain activation: count_colors order on the base pattern is 0,3,1,4,2,5;
	-- without the own colour (5) -> {0,3,1,4,2}; tape draws index 2 -> colour 1
	local tape = H.tape({ 2 })
	local sim2, c2 = H.fight(nil, { rng_combat = tape })
	local chained2 = spy(sim2, "clear_color_chained")
	fire(sim2, c2, { col = 0, row = 0, gem_type = 5, tier = 2 })
	T.eq(chained2[1][1], 1, "random other colour from the combat stream")
	T.eq(tape.draws, 1, "one draw")
end)

T.case("Rejuvenation: 500 HP over 10 s (5 % of max), 150 score; a second cast extends it", function()
	local sim, c = H.fight(nil)
	local healed = H.collect(sim, "player_healed")
	c.player_health = 5000
	local score = c.score
	fire(sim, c, { col = 0, row = 0, gem_type = 0, tier = 1 })
	T.eq(c.score - score >= 150, true, "score 150 for the ability")
	T.ok(c:status_remaining("hot") > 9.5, "up about 10 s")
	T.eq(c.status.hot.ticks_left, 10, "10 ticks")
	T.eq(c.player_health, 5000, "nothing heals at the cast, the first tick comes after 1 s")
	H.tick_to(sim, sim.now + 11)
	local sum = 0
	for _, h in ipairs(healed) do sum = sum + h[1] end
	T.eq(sum, 500, "500 in total")
	T.eq(#healed, 10, "ten ticks")
	fire(sim, c, { col = 0, row = 0, gem_type = 0, tier = 1 })
	fire(sim, c, { col = 0, row = 0, gem_type = 0, tier = 1 })
	T.eq(c.status.hot.ticks_left >= 19, true, "two casts: extended to 19-20 ticks")
	T.eq(c.status.hot.ticks_left <= 20, true, "never above 20")
end)

T.case("Lay on Hands: 1500 HP (15 % of max) at once, capped; Heal Block stops it; 450 score", function()
	local sim, c = H.fight(nil)
	local healed = H.collect(sim, "player_healed")
	c.player_health = 4000
	fire(sim, c, { col = 0, row = 0, gem_type = 0, tier = 2 })
	T.eq(c.player_health, 5500, "healed 1500")
	T.eq(healed[1][2], "ult", "source ult")
	c.player_health = 9500
	fire(sim, c, { col = 0, row = 0, gem_type = 0, tier = 2 })
	T.eq(c.player_health, 10000, "capped at max")
	c.player_health = 4000
	c:apply_heal_block(10)
	fire(sim, c, { col = 0, row = 0, gem_type = 0, tier = 2 })
	T.eq(c.player_health, 4000, "Heal Block: no heal")
	T.eq(ns.Abilities.lay_on_hands.score, 450, "score")
	T.eq(Kit.banner_text(Kit.default():get(0, 2)), "Heal 1500 health", "blurb")
	T.eq(Kit.banner_text(Kit.default():get(0, 1)), "Heal 500 over 10s", "Rejuvenation blurb")
end)

T.case("Hammer of Justice: 200 dmg, 3 s stun; overlapping stuns keep the longer one", function()
	local sim, c = H.fight(nil, { def = H.enemy_def({ cooldown = 8 }) })
	local dealt = H.collect(sim, "damage_dealt")
	c.enemy:apply_stun(5, "freeze")
	fire(sim, c, { col = 0, row = 0, gem_type = 1, tier = 1 })
	T.eq(first_ability_packet(dealt)[1], 200, "direct damage")
	T.ok(c.enemy:get_stun_remaining() > 4.5, "the longer freeze is kept")
	T.eq(c.enemy:get_stun_duration_max(), 5, "max stays 5")
	T.eq(c.enemy:get_status_kind(), "stun", "kind follows the last application (Godot)")
	local sim2, c2 = H.fight(nil, { def = H.enemy_def({ cooldown = 8 }) })
	fire(sim2, c2, { col = 0, row = 0, gem_type = 1, tier = 1 })
	T.ok(near(c2.enemy:get_stun_remaining(), 3, 0.05), "3 s stun")
end)

T.case("Mind Control: partner -> Amethyst, marked; one colour per chain; reset on settle", function()
	local sim, c = H.fight(nil)
	local conv = spy(sim, "convert_color")
	-- two Mind Controls in one drain: the second has another swap partner but
	-- reuses the chain's colour
	c.queue[1] = { col = 0, row = 0, gem_type = 1, tier = 2, partner_color = 2, source = "match", match_length = 5, is_bomb = false }
	c.queue[2] = { col = 1, row = 1, gem_type = 1, tier = 2, partner_color = 4, source = "chain", match_length = 0, is_bomb = false }
	local during = {}
	sim:on("ability_triggered", function() during[#during + 1] = c.chain_convert_color end)
	drain_like_pass(sim, c)
	T.ok(H.run(sim), "rest")
	T.eq(conv[1][1], 2, "first: partner colour 2")
	T.eq(conv[1][2], 1, "to Amethyst")
	T.eq(conv[1][3], true, "converted gems are marked")
	T.eq(conv[2][1], 2, "second reuses colour 2, not its own partner 4")
	T.eq(during[2], 2, "chain colour remembered")
	T.eq(c.chain_convert_color, -1, "reset on board_settled")
end)

T.case("Power Word: Shield: +1 stack per cast", function()
	local sim, c = H.fight(nil)
	fire(sim, c, { col = 0, row = 0, gem_type = 2, tier = 1 })
	fire(sim, c, { col = 0, row = 0, gem_type = 2, tier = 1 })
	T.eq(c.status.shield.stacks, 2, "2 stacks")
	T.eq(c:take_damage(300), "shield", "blocks")
end)

T.case("W1-G4: the text names the cap and it equals Combat.SHIELD_MAX_STACKS", function()
	local a = ns.Abilities.power_word_shield
	T.eq(a.shield_max, ns.Combat.SHIELD_MAX_STACKS, "shield_max matches the combat cap")
	T.eq(ns.Kit.format_text(a, a.description), "Shield: blocks the next enemy attack (up to 3 stacks)", "description")
end)

T.case("Rain of Fire: 5 bombs; a bomb deals 50 (x its colour's weakness) and clears 3x3", function()
	local sim, c = H.fight(nil)
	local bombs = spy(sim, "convert_random_to_bombs")
	fire(sim, c, { col = 0, row = 0, gem_type = 2, tier = 2 })
	T.eq(bombs[1][1], 5, "bomb_count 5")
	T.eq(bombs[1].result, 5, "5 bombs made")
	local sim2, c2 = H.fight(nil, { def = H.enemy_def({ weak = 4 }) })
	local dealt = H.collect(sim2, "damage_dealt")
	local trig = H.collect(sim2, "ability_triggered")
	local by_effect = H.collect(sim2, "gems_cleared_by_effect")
	fire(sim2, c2, { col = 3, row = 3, gem_type = 4, tier = 0, is_bomb = true })
	T.eq(trig[1][1].toast, "BOMB", "bomb banner")
	T.eq(dealt[1][3], "bomb", "source bomb")
	T.eq(dealt[1][1], 75, "50 x 1.5: the bomb keeps its colour, weakness applies (Godot)")
	T.eq(#by_effect[1][1], 9, "3x3")
end)

T.case("chain: an ability clear hits another ability gem -> queued, FIFO", function()
	local sim, c = H.fight({ ["4,4"] = "d" })
	local trig = H.collect(sim, "ability_triggered")
	local act = H.collect(sim, "ability_activated")
	fire(sim, c, { col = 3, row = 3, gem_type = 4, tier = 1 })
	T.eq(trig[1][1].id, "arcane_explosion", "Arcane Explosion first")
	T.eq(trig[2] and trig[2][1].id, "flamestrike", "then the Flamestrike it hit")
	T.eq(act[1][1].source, "chain", "chain activation")
	T.eq(act[1][1].col .. "," .. act[1][1].row, "4,4", "at the hit gem")
end)

T.case("swap-triggered: partner colour = the swapped gem's colour", function()
	-- row 0: 5 5 _ (3,0 -> 0 to keep it a 3-match), Topaz ult below the gap
	local sim, c = H.fight({ ["0,0"] = "5", ["1,0"] = "5", ["2,1"] = "F", ["3,0"] = "0" })
	local chained = spy(sim, "clear_color_chained")
	T.eq(c:try_swap(sim.board:get(2, 1), sim.board:get(2, 0)), "ok", "swap")
	T.ok(H.run(sim), "rest")
	T.eq(chained[1] and chained[1][1], 2, "Chain Lightning hits colour 2 (the gem swapped with)")
end)

T.case("ability gem on its own spawn cell: fires and the new gem survives its clear", function()
	-- row 0: 4 4 _ 4 with a Sapphire skill below the gap -> 4-match keeps the
	-- swapped-in skill gem as the new skill; the old one fires Arcane Explosion there
	local sim, c = H.fight({ ["0,0"] = "4", ["1,0"] = "4", ["3,0"] = "4", ["2,1"] = "e", ["4,0"] = "0" })
	local gem = sim.board:get(2, 1)
	local trig = H.collect(sim, "ability_triggered")
	local spawned = H.collect(sim, "ability_gem_spawned")
	c:try_swap(gem, sim.board:get(2, 0))
	T.ok(H.run(sim), "rest")
	T.eq(trig[1][1].id, "arcane_explosion", "the matched skill fired")
	T.eq(trig[1][1].col .. "," .. trig[1][1].row, "2,0", "at its cell")
	T.eq(spawned[1][1] .. "," .. spawned[1][2] .. " tier" .. spawned[1][3], "2,0 tier1", "new skill on the same cell")
	T.ok(not gem.removed, "the kept gem survived its own Arcane Explosion")
	T.eq(gem.tier, 1, "still a skill")
	T.eq(gem.type, 4, "Sapphire")
	T.ok(not gem.protected, "protection lifted on settle")
end)

T.case("6/7-match multiplier on direct damage", function()
	for _, case in ipairs({ { 5, 150 }, { 6, 180 }, { 7, 225 }, { 12, 225 } }) do
		local sim, c = H.fight(nil)
		local dealt = H.collect(sim, "damage_dealt")
		fire(sim, c, { col = 2, row = 4, gem_type = 3, tier = 1, match_length = case[1], source = "match" })
		T.eq(first_ability_packet(dealt)[1], case[2], "Flamestrike from a " .. case[1] .. "-match")
	end
end)

T.case("banner texts (mirrors ability_gems_test _test_value_driven_blurbs)", function()
	local kit = Kit.default()
	local fs = kit:get(3, 2)
	T.eq(Kit.banner_text(fs), "Reflect attacks — 12s", "Fire Shield blurb fills its duration")
	fs.fire_shield_duration = 12.5
	T.eq(Kit.banner_text(fs), "Reflect attacks — 12.5s", "changed duration shows in the blurb")
	T.eq(ns.Abilities.fire_shield.fire_shield_duration, 12.0, "the shared definition is untouched")
	local bombs = kit:get(2, 2)
	T.eq(Kit.format_text(bombs, bombs.blurb), "Spawn 5 bombs", "Rain of Fire blurb")
	T.ok(Kit.format_text(bombs, bombs.description):find("deal 50 dmg", 1, true) ~= nil, "Rain of Fire description fills BOMB_DAMAGE")
	local area = kit:get(4, 1)
	T.eq(Kit.format_text(area, area.description),
		"150 dmg, clear 3x3 around the gem, delay the enemy's next attack +2s", "Arcane Explosion description")
	local unfilled, n = {}, 0
	for color = 0, 5 do
		for tier = 1, 2 do
			local a = kit:get(color, tier)
			n = n + 1
			local text = Kit.format_text(a, a.blurb) .. " " .. Kit.format_text(a, a.description)
			if text:find("{", 1, true) then unfilled[#unfilled + 1] = a.id end
		end
	end
	T.ok(n == 12 and #unfilled == 0, "all 12 ability texts resolve every placeholder: " .. table.concat(unfilled, ","))
	T.eq(Kit.format_number(0.25), "0.25", "format 0.25")
	T.eq(Kit.format_number(10.0), "10", "format 10")
	T.eq(Combat.BOMB_DAMAGE, 50, "bomb damage constant")
end)

T.done()
