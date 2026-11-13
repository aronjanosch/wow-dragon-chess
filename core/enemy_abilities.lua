local _, ns = ...
-- Enemy ability types (W0-G2a): port of scenes/enemies/abilities/*.gd. Ability data is
-- plain tables (data/enemies.lua); `ability.kind` selects the handler here:
--   plain nuke   - rolled hit only (a charge nuke is just a big plain hit; stun / freeze /
--                  delay already postpone it)
--   flurry       - MultiHit: hit count, then one damage roll per hit, `hit_interval` apart
--   stagger      - StunAbility: rolled hit inside execute; stuns the player only if it reached HP
--   heal_block   - rolled hit (pre-execute), then player healing x0 for `duration`
--   junk         - SpawnJunk: board telegraph (0.62 s), then plain gems become junk
--   curse        - DamageDebuff: player damage x multiplier for `duration`
--   heal         - HealSelf: heal_percent of max HP (does NOT pass through heal block)
--   aegis        - SpellImmunity (Divine Aegis)
--   mirror       - MirrorShield
--   sand         - BoardSlow (Sandstorm): sim gravity slow
--
-- Handler contract (K[kind]):
--   pre                       true: the generic pre-execute damage roll applies (Godot
--                             enemy.gd roll_damage); false: the ability rolls inside execute
--                             (flurry / stagger; roll_damage is 0 there)
--   expected(ability)         seconds execute takes on average (HUD)
--   max(ability)              seconds execute takes at most (data test: windup + max < cooldown)
--   start(enemy, ability)     begins execute; returns true when it finished at once, false when
--                             it runs on (the handler then calls enemy:_execute_done(ability))
--
-- Multi-step execute (flurry) runs on the enemy's `exec_timer` (a Clock timer), junk on a
-- board coroutine (board work): both stand still while the Clock is frozen / gameplay is
-- paused, so Combat:settle_now() can never fire the remaining hits.

local K = {}

local function over(combat)
	return combat.game_over or combat.fight_over
end

local function instant() return 0 end

local function simple(start)
	return { pre = true, expected = instant, max = instant, start = start }
end

K.plain = simple(function() return true end)
K.nuke = K.plain

K.curse = simple(function(enemy, ab)
	enemy.combat:apply_damage_debuff(ab.damage_multiplier, ab.duration)
	return true
end)

K.heal = simple(function(enemy, ab)
	enemy:heal(ns.StatusMath.round(enemy.max_health * ab.heal_percent))
	return true
end)

K.aegis = simple(function(enemy, ab)
	enemy:apply_spell_immunity(ab.duration)
	return true
end)

K.mirror = simple(function(enemy, ab)
	enemy:apply_mirror_shield(ab.duration, ab.reflect_fraction, ab.break_damage, ab.break_stun)
	return true
end)

K.sand = simple(function(enemy, ab)
	local combat = enemy.combat
	if over(combat) then return true end
	combat.sim:set_gravity_slow(ab.factor, ab.duration)
	return true
end)

K.heal_block = simple(function(enemy, ab)
	local combat = enemy.combat
	if over(combat) or combat.god_mode then return true end
	combat:apply_heal_block(ab.duration)
	return true
end)

-- Stagger: roll_damage is 0 - the hit happens here so the stun can see its result.
K.stagger = {
	pre = false, expected = instant, max = instant,
	start = function(enemy, ab)
		local combat = enemy.combat
		if over(combat) or combat.god_mode then return true end
		local dmg = combat.rng_combat:range_i(ab.damage_min, ab.damage_max)
		local result = "hp"
		if dmg > 0 then result = combat:take_damage(dmg) end
		local landed = result == "hp"
		if landed and not combat.game_over then combat:apply_player_stun(ab.stun_duration) end
		combat:_emit("stagger_resolved", landed)
		return true
	end,
}

-- Flurry (MultiHit). State in enemy.exec = { ability, hits, i }.
K.flurry = {
	pre = false,
	expected = function(ab) return ((ab.hit_count_min + ab.hit_count_max) / 2 - 1) * ab.hit_interval end,
	max = function(ab) return (ab.hit_count_max - 1) * ab.hit_interval end,
	start = function(enemy, ab)
		local hits = enemy.combat.rng_combat:range_i(ab.hit_count_min, ab.hit_count_max)
		enemy.exec = { ability = ab, hits = hits, i = 0 }
		return K.flurry.step(enemy)
	end,
	-- One hit; true when the flurry is over (all hits done, or the fight / run ended).
	step = function(enemy)
		local ex = enemy.exec
		local combat = enemy.combat
		ex.i = ex.i + 1
		if ex.i > ex.hits or over(combat) then return true end
		local ab = ex.ability
		local dmg = combat.rng_combat:range_i(ab.damage_min, ab.damage_max)
		if dmg > 0 then combat:take_damage(dmg) end
		if ex.i < ex.hits then
			enemy.clock:start(enemy.exec_timer, ab.hit_interval)
			return false
		end
		return true
	end,
}

-- SpawnJunk: board work (telegraph + convert), so a settle_now simply finishes it.
K.junk = {
	pre = true,
	expected = function() return ns.Timings.CONVERT_TELEGRAPH + ns.Timings.CONVERT_TELEGRAPH_FADE end,
	max = function() return ns.Timings.CONVERT_TELEGRAPH + ns.Timings.CONVERT_TELEGRAPH_FADE end,
	start = function(enemy, ab)
		local sim = enemy.combat.sim
		local ex = { ability = ab }
		enemy.exec = ex
		sim:spawn(function()
			sim:set_gems_junk(ab.junk_count)
			if enemy.exec == ex then enemy:_execute_done(ab) end
		end)
		return false
	end,
}

ns.EnemyAbilities = K
