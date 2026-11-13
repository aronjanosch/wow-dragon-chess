local _, ns = ...
-- Enemy (W0-G2a): port of scenes/enemies/enemy.gd - attack rotation / timer / stun /
-- freeze / delay_attack / wind-up (W0-G1) plus the M1-G9 mechanics (Divine Aegis, Mirror
-- Shield, Sandstorm, ...) via core/enemy_abilities.lua, and HP-threshold phases.
--
-- Attack cycle (enemy.gd _on_attack_timer_timeout): the AttackTimer (a repeating Godot
-- Timer) fires -> next rotation ability -> wind-up (`windup`, the sprite's attack clip) ->
-- the hit lands: ability_executed, the generic pre-execute damage roll (kinds with pre =
-- true), then the ability's execute (core/enemy_abilities.lua; flurry steps on Clock
-- timers) -> the timer restarts with the ability's cooldown. One cycle = cooldown +
-- wind-up + execute time (Enemy.cycle_time uses the *expected* execute time, HUD only).
-- The timer also restarts with the previous cooldown at timeout (Godot's repeat, kept for
-- parity); a timeout while a hit / execute is still in flight is skipped (guard). The data
-- test asserts max(windup + execute max) < min(cooldown), so the guard never fires on
-- shipped data. All times are combat-clock (gameplay) seconds.
--
-- Enemy data: data/enemies.lua (ns.EnemyData; shape documented there). Never mutated:
-- a phase swaps `self.rotation` to the phase's table (a reference), nothing is written
-- into the def.
--
-- Events (via combat.sim:emit): enemy_windup(ability, s), enemy_ability_executed(ability),
-- enemy_status_changed(kind, active, remaining, max), enemy_immune(kind),
-- enemy_phase_changed(label), enemy_mirror_changed(active, broken),
-- enemy_health_changed, stagger_resolved(landed).

local setmetatable = setmetatable
local max, min = math.max, math.min

local Enemy = {}
Enemy.__index = Enemy

-- Dev / compat alias: enemy defs by id (ui/main.lua, tests). The data is read-only.
Enemy.STUBS = ns.EnemyData and ns.EnemyData.by_id or {} -- (lint loads core files in isolation)

local function kind_of(ability)
	return ns.EnemyAbilities[ability.kind or "plain"]
end

-- Expected seconds the ability's execute takes (HUD; 0 for an instant one).
function Enemy.execute_time_expected(ability)
	return kind_of(ability).expected(ability)
end

-- Longest execute (data test: windup + this < every cooldown).
function Enemy.execute_time_max(ability)
	return kind_of(ability).max(ability)
end

-- Seconds between two attacks of `ability` while nothing interferes (expected value).
function Enemy.cycle_time(def, ability)
	return ability.cooldown + (def.windup or 0) + Enemy.execute_time_expected(ability)
end

-- combat: the owning Combat (clock, rng_combat, events, take_damage).
function Enemy.new(def, combat)
	local self = setmetatable({}, Enemy)
	self.def = def
	self.combat = combat
	self.clock = combat.clock
	self.name = def.name
	self.max_health = def.max_health
	self.current_health = def.max_health
	self.weak_to_color = def.weak_to_color or -1
	self.rotation = def.rotation -- reference; a phase swaps it, nothing is mutated
	self.rotation_index = 1
	self.phases_applied = 0
	self.phase_name = "" -- label of the current phase ("" before the first swap)
	self.is_active = false
	self.dead = false
	self.disposed = false
	self.invincible = false -- debug / playtest
	self.wait_time = 1.0 -- AttackTimer.wait_time
	self.paused_wait_time = 0 -- timer time held while stunned
	self.stun_max = 0
	self.status_kind = ""
	self.slow_max = 0
	self.hits = {} -- in-flight attacks (wind-up timers)
	self.exec = nil -- in-flight multi-step execute (flurry / junk)
	-- Divine Aegis / Mirror Shield (M1-G9)
	self.immune = false
	self.immune_max = 0
	self.mirror = false
	self.mirror_max = 0
	self.mirror_fraction = 0
	self.mirror_break_damage = 0
	self.mirror_break_stun = 0
	self.mirror_crack = 0
	local clock = self.clock
	self.attack_timer = clock:timer(function() self:_on_attack_timer_timeout() end)
	self.stun_timer = clock:timer(function() self:_on_stun_end() end)
	self.slow_timer = clock:timer(function()
		self.slow_max = 0
		self:_emit_status("slow")
	end)
	self.immune_timer = clock:timer(function()
		self.immune = false
		self.immune_max = 0
	end)
	self.mirror_timer = clock:timer(function() self:_end_mirror(false) end)
	self.exec_timer = clock:timer(function() self:_on_exec_step() end)
	return self
end

function Enemy:_emit(name, ...)
	self.combat.sim:emit(name, ...)
end

function Enemy:_emit_status(kind)
	if kind == "slow" then
		local rem = self:get_slow_remaining()
		self:_emit("enemy_status_changed", "slow", rem > 0, rem, self.slow_max)
	else
		local rem = self:get_stun_remaining()
		self:_emit("enemy_status_changed", kind, rem > 0, rem, self.stun_max)
	end
end

---------------------------------------------------------------- rotation

function Enemy:start_rotation()
	if #self.rotation == 0 then return end
	self.is_active = true
	self.wait_time = self.rotation[1].cooldown
	self.clock:start(self.attack_timer, self.wait_time)
end

function Enemy:stop_rotation()
	self.is_active = false
	self.clock:stop(self.attack_timer)
end

-- Dev (debug panel, W0-P5): freezes / releases the attack cooldown, every wind-up in flight and a running
-- multi-step execute. Statuses (stun, slow, Aegis, Mirror) keep running. A held timer keeps its remaining time.
function Enemy:set_timers_held(on)
	on = on and true or false
	self.timers_held = on
	local clock = self.clock
	clock:hold(self.attack_timer, on)
	clock:hold(self.exec_timer, on)
	for i = 1, #self.hits do clock:hold(self.hits[i], on) end
end

-- Leaves the fight (a new enemy replaces it): every timer is dropped.
function Enemy:dispose()
	local clock = self.clock
	self.disposed = true
	self.is_active = false
	clock:remove(self.attack_timer)
	clock:remove(self.stun_timer)
	clock:remove(self.slow_timer)
	clock:remove(self.immune_timer)
	clock:remove(self.mirror_timer)
	clock:remove(self.exec_timer)
	for i = 1, #self.hits do clock:remove(self.hits[i]) end
	self.hits = {}
	self.exec = nil
end

function Enemy:peek_next_ability()
	return self.rotation[self.rotation_index]
end

-- Upcoming abilities from the current index (wraps). out: reused array.
function Enemy:peek_upcoming(count, out)
	out = out or {}
	local n = #self.rotation
	local k = 0
	if n > 0 then
		for i = 0, count - 1 do
			k = k + 1
			out[k] = self.rotation[(self.rotation_index - 1 + i) % n + 1]
		end
	end
	for i = #out, k + 1, -1 do out[i] = nil end
	return out
end

function Enemy:get_next_ability()
	local ability = self.rotation[self.rotation_index]
	if ability ~= nil then self.rotation_index = self.rotation_index % #self.rotation + 1 end
	return ability
end

function Enemy:_on_attack_timer_timeout()
	if not self.is_active then return end
	if #self.hits > 0 or self.exec ~= nil then
		-- Guard: a hit / execute is still in flight (unreachable with shipped data, see
		-- the data test). Skip this attack, keep the timer repeating.
		self.clock:start(self.attack_timer, self.wait_time)
		return
	end
	local ability = self:get_next_ability()
	if ability == nil then return end
	-- A Godot Timer repeats: it restarts with the same wait_time at once (the
	-- restart after the execute replaces it).
	self.clock:start(self.attack_timer, self.wait_time)
	local hit
	hit = self.clock:timer(function() self:_land_hit(hit, ability) end)
	if self.timers_held then self.clock:hold(hit, true) end
	self.hits[#self.hits + 1] = hit
	local windup = self.def.windup or 0
	self:_emit("enemy_windup", ability, windup)
	self.clock:start(hit, windup)
end

function Enemy:_land_hit(hit, ability)
	self.clock:remove(hit)
	for i = #self.hits, 1, -1 do
		if self.hits[i] == hit then table.remove(self.hits, i) end
	end
	if self.dead or self.disposed then return end
	self:_emit("enemy_ability_executed", ability)
	local handler = kind_of(ability)
	if handler.pre then
		-- range_i(hi <= lo) draws nothing, so 0-damage abilities consume no RNG.
		local rolled = self.combat.rng_combat:range_i(ability.damage_min, ability.damage_max)
		if rolled > 0 then self.combat:take_damage(rolled) end
	end
	if handler.start(self, ability) then self:_execute_done(ability) end
end

-- exec_timer: the next step of a running multi-step execute (flurry).
function Enemy:_on_exec_step()
	local ex = self.exec
	if ex == nil or self.disposed then return end
	if ns.EnemyAbilities.flurry.step(self) then self:_execute_done(ex.ability) end
end

-- The ability's execute is over: restart the attack timer with its cooldown.
function Enemy:_execute_done(ability)
	self.exec = nil
	if self.dead or self.disposed or self.current_health <= 0 then return end
	self.wait_time = ability.cooldown
	if self:get_stun_remaining() > 0 then
		-- Godot restarts the timer here too, but it is ignored while stunned
		-- (is_active false) and replaced when the stun ends.
		return
	end
	if self.is_active then self.clock:start(self.attack_timer, self.wait_time) end
end

---------------------------------------------------------------- phases

-- enemy.gd _check_phase_thresholds: rotation swaps when HP drops to a phase's
-- hp_fraction (descending, monotonic - healing never un-phases; one hit may cross two).
function Enemy:_check_phase_thresholds()
	local phases = self.def.phases
	if phases == nil or #phases == 0 or self.max_health <= 0 then return end
	local hp_frac = self.current_health / self.max_health
	while self.phases_applied < #phases do
		local kit = phases[self.phases_applied + 1]
		if hp_frac > kit.hp_fraction then break end
		local next_rotation = kit.rotation
		if next_rotation == nil or #next_rotation == 0 then
			self.phases_applied = self.phases_applied + 1
		else
			self.rotation = next_rotation
			self.rotation_index = 1
			self.phases_applied = self.phases_applied + 1
			local name = kit.phase_name
			local label = (name ~= nil and name ~= "") and name or ("Phase " .. (self.phases_applied + 1))
			self.phase_name = label
			self:_emit("enemy_phase_changed", label)
			-- Restart the telegraph on the new rotation's first ability.
			if self.is_active then
				self.wait_time = self.rotation[1].cooldown
				self.clock:start(self.attack_timer, self.wait_time)
			end
		end
	end
end

---------------------------------------------------------------- stun / slow / delay

-- kind: "stun" (Hammer of Justice) or "freeze" (Frost Nova): same mechanics.
function Enemy:apply_stun(duration, kind)
	kind = kind or "stun"
	if not self.is_active and self.current_health <= 0 then return end
	if self:is_spell_immune() then
		self:_emit("enemy_immune", kind)
		return
	end
	local clock = self.clock
	local rem = self:get_stun_remaining()
	if rem <= 0 then
		local left = clock:left(self.attack_timer)
		self.paused_wait_time = (clock:is_running(self.attack_timer) and left > 0) and left or self.wait_time
		clock:stop(self.attack_timer)
		self.is_active = false
	end
	self.stun_max = ns.StatusMath.stun_max_after_apply(rem, duration, self.stun_max)
	clock:start(self.stun_timer, max(rem, duration))
	self.status_kind = kind
	self:_emit_status(kind)
end

function Enemy:_on_stun_end()
	local kind = self.status_kind
	self.stun_max = 0
	self.status_kind = ""
	if self.current_health > 0 and not self.dead then
		self.is_active = true
		self.wait_time = max(self.paused_wait_time, 0.05)
		self.clock:start(self.attack_timer, self.wait_time)
	end
	self:_emit_status(kind)
end

-- Cosmetic slow window (Arcane Explosion / Surge): HUD only. Ignored while immune (the
-- delay_attack that goes with it still applies).
function Enemy:apply_slow(duration)
	if self:is_spell_immune() then return end
	self.slow_max = duration
	self.clock:start(self.slow_timer, duration)
	self:_emit_status("slow")
end

function Enemy:delay_attack(seconds)
	if self:get_stun_remaining() > 0 then
		self.paused_wait_time = self.paused_wait_time + seconds
		return
	end
	local left = self.clock:left(self.attack_timer)
	if self.is_active and self.clock:is_running(self.attack_timer) and left > 0 then
		self.wait_time = left + seconds
		self.clock:start(self.attack_timer, self.wait_time)
	end
end

---------------------------------------------------------------- Divine Aegis / Mirror Shield (M1-G9)

function Enemy:apply_spell_immunity(duration)
	if duration <= 0 or self.current_health <= 0 then return end
	local remaining = max(self.clock:left(self.immune_timer), duration)
	self.immune = true
	self.immune_max = remaining
	self.clock:start(self.immune_timer, remaining)
end

function Enemy:is_spell_immune() return self.immune end

function Enemy:get_immune_remaining()
	if not self.immune then return 0 end
	return self.clock:left(self.immune_timer)
end

function Enemy:get_immune_duration_max() return self.immune and self.immune_max or 0 end

function Enemy:apply_mirror_shield(duration, fraction, break_damage, break_stun)
	if duration <= 0 or self.current_health <= 0 then return end
	self.mirror = true
	self.mirror_max = duration
	self.mirror_fraction = min(max(fraction, 0), 1)
	self.mirror_break_damage = max(break_damage, 1)
	self.mirror_break_stun = break_stun
	self.mirror_crack = 0 -- a re-cast resets the crack counter
	self.clock:start(self.mirror_timer, duration)
	self:_emit("enemy_mirror_changed", true, false)
end

function Enemy:is_mirror_up() return self.mirror end

function Enemy:get_mirror_remaining()
	if not self.mirror then return 0 end
	return self.clock:left(self.mirror_timer)
end

function Enemy:get_mirror_duration_max() return self.mirror and self.mirror_max or 0 end

function Enemy:get_mirror_fraction()
	return self.mirror and self.mirror_fraction or 0
end

-- Crack progress 0..1 (match damage so far / break_damage).
function Enemy:get_mirror_crack_ratio()
	if not self.mirror or self.mirror_break_damage <= 0 then return 0 end
	local r = self.mirror_crack / self.mirror_break_damage
	return r < 0 and 0 or (r > 1 and 1 or r)
end

-- Match damage cracks the mirror. Returns true when this shattered it (the enemy is
-- then stunned break_stun s - bounces while spell-immune).
function Enemy:add_mirror_crack(amount)
	if not self.mirror or amount <= 0 then return false end
	self.mirror_crack = self.mirror_crack + amount
	if self.mirror_crack < self.mirror_break_damage then return false end
	local stun = self.mirror_break_stun
	self:_end_mirror(true)
	if stun > 0 and self.current_health > 0 then self:apply_stun(stun) end
	return true
end

function Enemy:_end_mirror(broken)
	self.clock:stop(self.mirror_timer)
	self.mirror = false
	self.mirror_max = 0
	self.mirror_crack = 0
	self:_emit("enemy_mirror_changed", false, broken)
end

---------------------------------------------------------------- reads

function Enemy:get_stun_remaining()
	return self.clock:left(self.stun_timer)
end

function Enemy:get_stun_duration_max()
	return self.stun_max
end

-- "" outside a stun / freeze window.
function Enemy:get_status_kind()
	return self:get_stun_remaining() > 0 and self.status_kind or ""
end

function Enemy:get_slow_remaining()
	return self.clock:left(self.slow_timer)
end

function Enemy:get_slow_duration_max()
	return self.slow_max
end

-- Seconds until the attack timer fires (a stun counts as held time); -1 when
-- no rotation runs. The hit lands `windup` later.
function Enemy:get_time_to_next_attack()
	local stun = self:get_stun_remaining()
	if stun > 0 then return stun + self.paused_wait_time end
	if self.clock:is_running(self.attack_timer) then return self.clock:left(self.attack_timer) end
	return -1
end

-- Seconds until the next hit lands (wind-up in flight first; HUD helper).
function Enemy:get_time_to_next_hit()
	local best = -1
	for i = 1, #self.hits do
		local l = self.clock:left(self.hits[i])
		if best < 0 or l < best then best = l end
	end
	if best >= 0 then return best end
	local t = self:get_time_to_next_attack()
	if t < 0 then return -1 end
	return t + (self.def.windup or 0)
end

function Enemy:is_winding_up()
	return #self.hits > 0
end

-- A multi-step execute (flurry / junk) is running.
function Enemy:is_executing()
	return self.exec ~= nil
end

---------------------------------------------------------------- health

function Enemy:take_damage(amount)
	if self.dead then return end
	if self.invincible then
		self:_emit("enemy_health_changed", self.current_health, self.max_health)
		return
	end
	self.current_health = self.current_health - amount
	self:_emit("enemy_health_changed", self.current_health, self.max_health)
	if self.current_health > 0 then self:_check_phase_thresholds() end
	if self.current_health <= 0 then
		self.dead = true
		self:stop_rotation()
		self.combat:_on_enemy_defeated(self)
	end
end

function Enemy:heal(amount)
	if amount <= 0 or self.current_health <= 0 then return end
	self.current_health = min(self.max_health, self.current_health + amount)
	self:_emit("enemy_health_changed", self.current_health, self.max_health)
end

ns.Enemy = Enemy
