local _, ns = ...
-- Combat (W0-G1): port of scenes/battle_controller.gd + battle_status_math.gd,
-- plus the board<->battle glue and score tally of scenes/game.gd. Owns player /
-- enemy HP, damage routing, the ability queue (the sim's drain hook), player
-- statuses and fight start / end. Pure Lua, no WoW API.
--
--   local combat = Combat.new{ sim = sim, seed = n | rng_combat = stream,
--                              kit = Kit (default kit), player_max = 10000, player_hp = ... }
--   combat:start_fight(enemy_def)  -- first fight, and after enemy_defeated
--   combat:try_swap(a, b)          -- input gate (stun / game over / between fights) + sim:try_swap
--   combat:settle_now()            -- board work to rest with enemy / status clocks frozen
--   combat:serialize() / Combat.deserialize(data, opts)   -- between fights only
--   combat:hud_state(out)          -- read-only snapshot for the HUD (reuses `out`)
--
-- Create the Sim WITHOUT release_on_settle: combat lifts spawn protection on
-- board_settled after draining the queue (battle.on_board_settled).
--
-- Events (combat:on(name, fn); emitted on the sim's bus):
--   fight_started(enemy)                     Godot enemy_spawned
--   enemy_health_changed(hp, max)
--   enemy_damaged(amount, boosted)
--   damage_dealt(amount, gem_type, source)   source match|ability|bomb|reflect|thorns|other; gem_type -1 = colourless
--   enemy_windup(ability, seconds)           (added: no sprite to show the wind-up)
--   enemy_ability_executed(ability)          the hit lands now
--   enemy_status_changed(kind, active, remaining, max)   kind stun|freeze|slow (added; Godot polls)
--   enemy_immune(kind)                       stun / freeze / damage bounced off Divine Aegis
--   enemy_phase_changed(label)               HP-threshold rotation swap (W0-G2a)
--   enemy_mirror_changed(active, broken)     Mirror Shield up / ended (broken = shattered, else expired)
--   stagger_resolved(landed)                 a stagger hit resolved (landed = it reached HP and stunned)
--   enemy_defeated(enemy)                    gameplay is paused now; call start_fight(next) to go on
--   player_health_changed(hp, max)
--   player_damaged(amount, source)           hit | mirror
--   player_healed(amount)
--   attack_blocked / attack_reflected(amount) / heal_blocked
--   status_changed(id, active, remaining, max)   id fire_shield|lifesteal|curse|stun|heal_block|shield (added; Godot polls / per-status signals)
--   ability_triggered(info)                  banner: tier, toast, blurb, score, col, row, is_bomb, gem_type, icon, id
--   score_awarded(amount) / score_changed(total)
--   run_lost

local setmetatable, type, tonumber = setmetatable, type, tonumber
local floor, max, min = math.floor, math.max, math.min
local upper = string.upper
local remove = table.remove

---------------------------------------------------------------- status math

-- battle_status_math.gd (pure).
local StatusMath = {}

function StatusMath.tick_status_remaining(remaining, delta)
	return max(0, remaining - delta)
end

function StatusMath.consume_shield_stack(stacks)
	return max(0, stacks - 1)
end

function StatusMath.status_ratio(remaining, duration_max)
	if duration_max <= 0 then return 0 end
	local r = remaining / duration_max
	if r < 0 then return 0 elseif r > 1 then return 1 end
	return r
end

function StatusMath.stun_max_after_apply(old_remaining, new_duration, old_max)
	if new_duration > old_remaining then return new_duration end
	return old_max
end

-- GDScript round(): half away from zero.
local function round(x)
	if x >= 0 then return floor(x + 0.5) end
	return -floor(-x + 0.5)
end
StatusMath.round = round

function StatusMath.reflected_damage(amount, multiplier)
	return max(0, round(amount * multiplier))
end

ns.StatusMath = StatusMath

---------------------------------------------------------------- module

local Combat = {}
Combat.__index = Combat

-- M1-G1 x10 economy.
Combat.GEM_DAMAGE = 10
Combat.BOMB_DAMAGE = 50
Combat.WEAKNESS_MULTIPLIER = 1.5
Combat.PLAYER_START_HEALTH = 10000
Combat.COLOR_NAMES = { [0] = "Amber", "Amethyst", "Emerald", "Ruby", "Sapphire", "Topaz" }

-- scenes/score_rules.gd + game.gd SINGLE_SCORE.
Combat.MATCH_SCORES = { [3] = 50, [4] = 125, [5] = 200, [6] = 500, [7] = 850 }
Combat.SINGLE_SCORE = 15

function Combat.match_score(length)
	if length >= 7 then return Combat.MATCH_SCORES[7] end
	return Combat.MATCH_SCORES[length] or 0
end

-- Timed player statuses, fixed order (events, serialize).
Combat.TIMED_STATUSES = { "fire_shield", "lifesteal", "curse", "stun", "heal_block" }

Combat.SNAPSHOT_VERSION = 1

function Combat.new(opts)
	opts = opts or {}
	local sim = assert(opts.sim, "Combat.new: sim required")
	local self = setmetatable({}, Combat)
	self.sim = sim
	self.board = sim.board
	local Rng = ns.Rng
	self.rng_combat = opts.rng_combat or Rng.fork(opts.seed or 0, Rng.SALT.combat)
	self.kit = opts.kit or ns.Kit.default()
	self.clock = ns.Clock.new(sim)
	self.player_max_health = opts.player_max or Combat.PLAYER_START_HEALTH
	self.player_health = opts.player_hp or self.player_max_health
	self.score = opts.score or 0

	self.enemy = nil
	self.enemy_def = nil
	self.game_over = false
	self.fight_over = false
	self.god_mode = false
	self.enemy_invincible = false
	self.enemy_timers_held = false -- dev: debug panel "pause enemy timers" (W0-P5), carried into the next fights
	self.paused_by_kill = false
	-- Boon run flag (Hex), kept as a plain field: no boons in the addon.
	self.stun_ability_damage_bonus = 0
	-- Mind Control "one colour per chain" (M1-G8 A); reset on settle / fight start.
	self.chain_convert_color = -1

	self.queue = {}
	self.draining = false
	self.cur_mult = 1.0
	self.cur_gem_type = -1
	self.cur_source = "" -- "" outside ability execution; "ability" / "bomb" inside

	-- Player statuses: flat table keyed by status id (spec open decision 3).
	local clock = self.clock
	local status = {}
	self.status = status
	status.shield = { stacks = 0, thorns = 0 }
	for i = 1, #Combat.TIMED_STATUSES do
		local id = Combat.TIMED_STATUSES[i]
		local st = { id = id, max = 0 }
		st.timer = clock:timer(function() self:_expire(st) end)
		status[id] = st
	end
	status.fire_shield.reflect_multiplier = 1.0
	status.lifesteal.percent = 100.0
	status.curse.multiplier = 1.0

	-- Board wiring (game.gd _ready).
	sim:on("gems_cleared", function(counts, order) self:on_gems_cleared(counts, order) end)
	sim:on("ability_activated", function(info) self.queue[#self.queue + 1] = info end)
	sim:on("board_settled", function() self:on_board_settled() end)
	sim:on("match_resolved", function(length) self:_add_score(Combat.match_score(length)) end)
	sim:on("gems_cleared_by_effect", function(info) self:_add_score(Combat.SINGLE_SCORE * #info) end)
	sim:set_drain(function() self:_drain_ability_queue() end)
	return self
end

function Combat:on(name, fn) return self.sim:on(name, fn) end
function Combat:off(name, fn) return self.sim:off(name, fn) end

function Combat:_emit(name, ...)
	self.sim:emit(name, ...)
end

---------------------------------------------------------------- statuses

function Combat:status_remaining(id)
	local st = self.status[id]
	if st == nil or st.timer == nil then return 0 end
	local left = self.clock:left(st.timer)
	if st.extras ~= nil then -- stacked lifesteal: the HUD shows the longest instance
		for i = 1, #st.extras do
			local l = self.clock:left(st.extras[i].timer)
			if l > left then left = l end
		end
	end
	return left
end

function Combat:status_max(id)
	local st = self.status[id]
	return st and st.max or 0
end

function Combat:_emit_status(id)
	if id == "shield" then
		local s = self.status.shield.stacks
		self:_emit("status_changed", "shield", s > 0, s, s)
		return
	end
	local rem = self:status_remaining(id)
	self:_emit("status_changed", id, rem > 0, rem, self.status[id].max)
end

function Combat:_start_status(id, duration)
	local st = self.status[id]
	st.max = duration
	self.clock:start(st.timer, duration)
	self:_emit_status(id)
end

-- Timer ran out (battle._process reaching 0).
function Combat:_expire(st)
	st.max = 0
	if st.id == "curse" then st.multiplier = 1.0 end
	self:_emit_status(st.id)
end

function Combat:_clear_status(id)
	local st = self.status[id]
	if st.extras ~= nil then
		for i = 1, #st.extras do self.clock:stop(st.extras[i].timer) end
	end
	local was = self.clock:is_running(st.timer) or st.max > 0
	self.clock:stop(st.timer)
	st.max = 0
	if id == "curse" then st.multiplier = 1.0 end
	if was then self:_emit_status(id) end
end

-- Lifesteal stacks (playtest 5): a cast while one is running starts an extra independent instance, so two
-- active casts heal twice the damage. The main instance drives the HUD; extras are not part of the snapshot.
function Combat:apply_lifesteal(duration, percent)
	local ls = self.status.lifesteal
	if self.clock:is_running(ls.timer) then
		local extras = ls.extras
		if extras == nil then
			extras = {}
			ls.extras = extras
		end
		local slot
		for i = 1, #extras do
			if not self.clock:is_running(extras[i].timer) then slot = extras[i] break end
		end
		if slot == nil then
			slot = { timer = self.clock:timer(function() end) }
			extras[#extras + 1] = slot
		end
		slot.percent = percent or 100.0
		self.clock:start(slot.timer, duration)
		if duration > ls.max then ls.max = duration end
		self:_emit_status("lifesteal") -- the HUD pops the buff again
		return
	end
	ls.percent = percent or 100.0
	self:_start_status("lifesteal", duration)
end

-- Sum of the percents of every running lifesteal instance (0 = none).
function Combat:lifesteal_percent()
	local ls = self.status.lifesteal
	local total = self.clock:is_running(ls.timer) and ls.percent or 0
	local extras = ls.extras
	if extras ~= nil then
		for i = 1, #extras do
			if self.clock:is_running(extras[i].timer) then total = total + extras[i].percent end
		end
	end
	return total
end

function Combat:apply_fire_shield(duration, reflect_multiplier)
	self.status.fire_shield.reflect_multiplier = reflect_multiplier or 1.0
	self:_start_status("fire_shield", duration)
end

-- thorns: Shield.thorns_damage of the cast; the newest cast wins.
function Combat:add_shield_stack(thorns)
	local sh = self.status.shield
	sh.stacks = sh.stacks + 1
	sh.thorns = max(thorns or 0, 0)
	self:_emit_status("shield")
end

-- Anubisath curse (enemy ability kind curse): outgoing damage x multiplier.
function Combat:apply_damage_debuff(multiplier, duration)
	self.status.curse.multiplier = multiplier
	self:_start_status("curse", duration)
end

function Combat:curse_multiplier()
	if self:status_remaining("curse") > 0 then return self.status.curse.multiplier end
	return 1.0
end

-- Heal block keeps the longer window.
function Combat:apply_heal_block(duration)
	if duration <= 0 then return end
	self:_start_status("heal_block", max(self:status_remaining("heal_block"), duration))
end

-- Player stun (W0-G2 stagger): input locked, the board keeps resolving.
function Combat:apply_player_stun(duration)
	if duration <= 0 then return end
	self:_start_status("stun", duration)
end

---------------------------------------------------------------- fight flow

-- Start a fight against `def` (enemy data table). Also the transition after a
-- kill (game.gd _run_fight_transition): reset per-fight state, spawn the
-- enemy, then lift the kill pause so the leftover board work hits it.
function Combat:start_fight(def)
	self.fight_over = false
	self.sim:clear_gravity_slow() -- a Sandstorm never carries into the next fight
	self.chain_convert_color = -1
	self:_clear_status("curse")
	self:_clear_status("heal_block")
	if self.enemy ~= nil then self.enemy:dispose() end
	self.enemy_def = def
	local enemy = ns.Enemy.new(def, self)
	enemy.invincible = self.enemy_invincible
	if self.enemy_timers_held then enemy:set_timers_held(true) end
	self.enemy = enemy
	self:_emit("enemy_health_changed", enemy.current_health, enemy.max_health)
	enemy:start_rotation()
	self:_emit("fight_started", enemy)
	if self.paused_by_kill then
		self.paused_by_kill = false
		self.sim:resume_gameplay()
	end
	return enemy
end

-- battle._on_enemy_defeated: the kill pauses gameplay (board + drain).
function Combat:_on_enemy_defeated(enemy)
	self.fight_over = true
	if not self.sim:is_gameplay_paused() then
		self.paused_by_kill = true
		self.sim:pause_gameplay()
	end
	self:_emit("enemy_defeated", enemy)
end

---------------------------------------------------------------- damage to the enemy

local function is_spell_source(source)
	return source == "ability" or source == "bomb"
end

function Combat:_live()
	return self.enemy ~= nil and not self.game_over and not self.fight_over
end

function Combat:_enemy_spell_immune()
	return self.enemy ~= nil and self.enemy:is_spell_immune()
end

-- Hex (boon, 0 in the addon): x(1 + bonus) on ability / bomb damage while the
-- enemy is stunned or frozen.
function Combat:hex_multiplier()
	if self.stun_ability_damage_bonus <= 0 then return 1.0 end
	if self.cur_source ~= "ability" and self.cur_source ~= "bomb" then return 1.0 end
	if self.enemy == nil or self.enemy:get_stun_remaining() <= 0 then return 1.0 end
	return 1.0 + self.stun_ability_damage_bonus
end

function Combat:_scale_outgoing_damage(amount, gem_type)
	if amount <= 0 then return 0 end
	local scaled = amount * self:hex_multiplier()
	local def = self.enemy_def
	if gem_type ~= nil and gem_type >= 0 and def ~= nil and (def.weak_to_color or -1) == gem_type then
		scaled = scaled * Combat.WEAKNESS_MULTIPLIER
	end
	scaled = scaled * self:curse_multiplier()
	return max(0, round(scaled))
end

-- counts[type] = gems; rounded per colour group (sum is order-independent).
function Combat:_match_damage_from_counts(counts)
	local total = 0
	for t = 0, 5 do
		local n = counts[t]
		if n ~= nil then total = total + self:_scale_outgoing_damage(n * Combat.GEM_DAMAGE, t) end
	end
	return total
end

-- After a packet landed: Mirror Shield rules (enemy.lua).
function Combat:_after_enemy_packet(amount, source)
	local enemy = self.enemy
	if amount <= 0 or enemy == nil or not enemy:is_mirror_up() then return end
	if source == "match" then
		enemy:add_mirror_crack(amount)
		return
	end
	if not is_spell_source(source) then return end
	if self.fight_over or self.game_over or enemy.current_health <= 0 then return end
	local reflected = round(amount * enemy:get_mirror_fraction())
	if reflected > 0 then self:take_true_damage(reflected, "mirror") end
end

-- board gems_cleared(counts, order): every cleared gem hurts (source "match",
-- or the running ability's source); Drain Life heals from it.
function Combat:on_gems_cleared(counts, order)
	local damage = self:_match_damage_from_counts(counts)
	local source = self.cur_source ~= "" and self.cur_source or "match"
	local live = self:_live()
	if damage > 0 and live and is_spell_source(source) and self:_enemy_spell_immune() then
		self:_emit("enemy_immune", "damage")
		damage = 0
	end
	if damage > 0 and live then
		local boosted = self:hex_multiplier() > 1.0
		self.enemy:take_damage(damage)
		self:_emit("enemy_damaged", damage, boosted)
		for i = 1, #order do
			local t = order[i]
			local part = self:_scale_outgoing_damage(counts[t] * Combat.GEM_DAMAGE, t)
			if part > 0 then self:_emit("damage_dealt", part, t, source) end
		end
		self:_after_enemy_packet(damage, source)
	end
	-- (Godot heals even when the packet hit nothing: an overkill clear after the kill.)
	local ls_percent = self:lifesteal_percent()
	if ls_percent > 0 and not self.game_over and damage > 0 then
		if self:status_remaining("heal_block") > 0 then
			self:_emit("heal_blocked")
			return
		end
		local heal = round(damage * ls_percent / 100)
		if heal > 0 then
			self.player_health = min(self.player_max_health, self.player_health + heal)
			self:_emit("player_health_changed", self.player_health, self.player_max_health)
			self:_emit("player_healed", heal)
		end
	end
end

-- Ability direct damage: x the 6/7-match multiplier of the triggering match,
-- then weakness (the ability's colour unless given) / curse.
function Combat:deal_damage_to_enemy(amount, gem_type)
	if amount <= 0 or not self:_live() then return end
	local color = (gem_type ~= nil and gem_type >= 0) and gem_type or self.cur_gem_type
	local source = self.cur_source ~= "" and self.cur_source or "other"
	if is_spell_source(source) and self:_enemy_spell_immune() then
		self:_emit("enemy_immune", "damage")
		return
	end
	local boosted = self:hex_multiplier() > 1.0
	amount = round(amount * self.cur_mult)
	amount = self:_scale_outgoing_damage(amount, color)
	if amount <= 0 then return end
	self.enemy:take_damage(amount)
	self:_emit("enemy_damaged", amount, boosted)
	self:_emit("damage_dealt", amount, color, source)
	self:_after_enemy_packet(amount, source)
end

---------------------------------------------------------------- damage to the player

-- Enemy hit. Returns where it ended: "reflect" (Fire Shield), "shield" (a
-- stack ate it), "hp", or "none" (fight / run over, god mode).
function Combat:take_damage(amount)
	if self.game_over or self.fight_over or self.god_mode then return "none" end
	local enemy = self.enemy
	if self:status_remaining("fire_shield") > 0 then
		local reflected = StatusMath.reflected_damage(amount, self.status.fire_shield.reflect_multiplier)
		self:_emit("attack_reflected", reflected)
		if enemy ~= nil and reflected > 0 then
			enemy:take_damage(reflected)
			self:_emit("enemy_damaged", reflected, false)
			self:_emit("damage_dealt", reflected, -1, "reflect")
		end
		return "reflect"
	end
	local sh = self.status.shield
	if sh.stacks > 0 then
		sh.stacks = StatusMath.consume_shield_stack(sh.stacks)
		self:_emit("attack_blocked")
		self:_emit_status("shield")
		local thorns = sh.thorns
		if sh.stacks <= 0 then sh.thorns = 0 end
		if thorns > 0 and enemy ~= nil then
			enemy:take_damage(thorns)
			self:_emit("enemy_damaged", thorns, false)
			self:_emit("damage_dealt", thorns, -1, "thorns")
		end
		return "shield"
	end
	self:_apply_hp_loss(amount, "hit")
	return "hp"
end

-- Mirror Shield true damage: skips Fire Shield and shield stacks.
function Combat:take_true_damage(amount, source)
	if self.game_over or self.fight_over or self.god_mode or amount <= 0 then return end
	self:_apply_hp_loss(amount, source or "mirror")
end

function Combat:_apply_hp_loss(amount, source)
	self.player_health = max(0, self.player_health - amount)
	self:_emit("player_damaged", amount, source)
	self:_emit("player_health_changed", self.player_health, self.player_max_health)
	if self.player_health <= 0 then
		self.game_over = true
		if self.enemy ~= nil then self.enemy:stop_rotation() end
		self:_emit("run_lost")
	end
end

-- Direct heal of the player (the boss heal of core/run.lua; ignores Heal Block like Godot's
-- heal_after_boss). Returns the HP actually restored.
function Combat:heal_player(amount)
	if amount <= 0 or self.game_over then return 0 end
	local healed = min(self.player_max_health, self.player_health + amount) - self.player_health
	if healed <= 0 then return 0 end
	self.player_health = self.player_health + healed
	self:_emit("player_health_changed", self.player_health, self.player_max_health)
	self:_emit("player_healed", healed)
	return healed
end

---------------------------------------------------------------- score

function Combat:_add_score(amount)
	if amount ~= nil and amount > 0 then
		self.score = self.score + amount
		self:_emit("score_changed", self.score)
	end
end

-- Ability activations (battle.award_score -> game.gd score).
function Combat:award_score(amount)
	if amount > 0 then
		self:_emit("score_awarded", amount)
		self:_add_score(amount)
	end
end

---------------------------------------------------------------- ability queue

-- Runs inside a sim coroutine (the drain hook / the settle handler). FIFO, one
-- at a time; chain activations append and run next. Re-entry returns at once
-- (Godot: _draining_abilities guard).
function Combat:_drain_ability_queue()
	if self.draining or #self.queue == 0 then return end
	self.draining = true
	local sim = self.sim
	while #self.queue > 0 do
		if self.game_over then
			-- Mirror true damage can kill the player mid-drain.
			for i = #self.queue, 1, -1 do self.queue[i] = nil end
			break
		end
		sim:wait_if_paused()
		local info = remove(self.queue, 1)
		self:_execute_ability(info)
		sim:wait_if_paused()
	end
	self.draining = false
end

function Combat:_reset_current()
	self.cur_mult = 1.0
	self.cur_gem_type = -1
	self.cur_source = ""
end

function Combat:_execute_ability(info)
	local sim = self.sim
	sim:wait_if_paused()
	if self.game_over then return end
	self.cur_mult = ns.Match.damage_multiplier_for_length(info.match_length or 0)
	self.cur_gem_type = info.gem_type or -1
	self.cur_source = info.is_bomb and "bomb" or "ability"

	if info.is_bomb then
		self:_emit("ability_triggered", {
			tier = 0, toast = "BOMB", blurb = "Clear 3x3", score = 0, id = "bomb", icon = "bomb",
			col = info.col, row = info.row, is_bomb = true, gem_type = info.gem_type,
		})
		self:deal_damage_to_enemy(Combat.BOMB_DAMAGE)
		sim:wait_if_paused()
		sim:clear_area(info.col, info.row, 1)
		self:_reset_current()
		return
	end

	local ability = self.kit:get(info.gem_type, info.tier)
	if ability == nil then
		self:_reset_current()
		return
	end
	self:_emit("ability_triggered", {
		tier = info.tier, toast = upper(ability.name), blurb = ns.Kit.banner_text(ability),
		score = ability.score, id = ability.id, icon = ability.icon,
		col = info.col, row = info.row, is_bomb = false, gem_type = info.gem_type,
	})
	ability:execute({ sim = sim, board = sim.board, combat = self, info = info })
	self:_reset_current()
end

function Combat:get_ability_queue_length()
	return #self.queue
end

-- battle.on_board_settled: a new chain starts (Mind Control picks anew); drain
-- leftovers, then lift spawn protection (lines it blocked resolve after).
function Combat:on_board_settled()
	self.chain_convert_color = -1
	self.sim:spawn(function()
		self:_drain_ability_queue()
		self.sim:release_spawn_protection()
	end)
end

---------------------------------------------------------------- input gate

-- BoardInput.can_player_swap: "" or game_over / not_in_fight / stunned.
function Combat:can_player_swap()
	if self.game_over then return "game_over" end
	if self.fight_over or self.enemy == nil then return "not_in_fight" end
	if self:status_remaining("stun") > 0 then return "stunned" end
	return ""
end

-- Single player swap entry point: the gate, then sim:try_swap (its reasons).
function Combat:try_swap(a, b, check_gate)
	if check_gate ~= false then
		local reason = self:can_player_swap()
		if reason ~= "" then return reason end
	end
	return self.sim:try_swap(a, b)
end

---------------------------------------------------------------- rest / snapshot

-- Run the pending board work to rest (sim:settle_now) with the enemy and
-- status clocks frozen: no enemy attack, no status runs out meanwhile (a
-- logout can never kill the player). Returns sim:settle_now()'s result.
function Combat:settle_now()
	self.clock:freeze()
	local ok = self.sim:settle_now()
	self.clock:thaw()
	return ok
end

-- Between fights only (no enemy yet, after the kill, or after the run ended):
-- HP, score, statuses and the combat stream. The run position belongs to the
-- run module (W0-G2); the board snapshot is sim:serialize() (at rest only).
function Combat:serialize()
	if self.enemy ~= nil and not self.fight_over and not self.game_over then
		return nil, "mid-fight"
	end
	local statuses = {}
	for i = 1, #Combat.TIMED_STATUSES do
		local id = Combat.TIMED_STATUSES[i]
		local st = self.status[id]
		statuses[id] = { self:status_remaining(id), st.max }
	end
	statuses.fire_shield[3] = self.status.fire_shield.reflect_multiplier
	statuses.lifesteal[3] = self.status.lifesteal.percent
	statuses.curse[3] = self.status.curse.multiplier
	if type(self.rng_combat.get_state) ~= "function" then return nil, "rng without state" end
	return {
		v = Combat.SNAPSHOT_VERSION,
		player_health = self.player_health, player_max_health = self.player_max_health,
		score = self.score, game_over = self.game_over,
		shield = { self.status.shield.stacks, self.status.shield.thorns },
		statuses = statuses,
		rng_combat = self.rng_combat:get_state(),
	}
end

-- opts: sim (required), kit. Returns a combat (no enemy yet) or nil + reason.
function Combat.deserialize(data, opts)
	if type(data) ~= "table" or data.v ~= Combat.SNAPSHOT_VERSION then return nil, "version" end
	if type(data.rng_combat) ~= "table" or type(data.statuses) ~= "table" then return nil, "corrupt" end
	opts = opts or {}
	local self = Combat.new({
		sim = opts.sim, kit = opts.kit,
		rng_combat = ns.Rng.from_state(data.rng_combat),
		player_max = tonumber(data.player_max_health), player_hp = tonumber(data.player_health),
		score = tonumber(data.score),
	})
	self.game_over = data.game_over == true
	if type(data.shield) == "table" then
		self.status.shield.stacks = tonumber(data.shield[1]) or 0
		self.status.shield.thorns = tonumber(data.shield[2]) or 0
	end
	for i = 1, #Combat.TIMED_STATUSES do
		local id = Combat.TIMED_STATUSES[i]
		local e = data.statuses[id]
		local st = self.status[id]
		if type(e) == "table" then
			if id == "fire_shield" then st.reflect_multiplier = tonumber(e[3]) or 1.0 end
			if id == "lifesteal" then st.percent = tonumber(e[3]) or 100.0 end
			if id == "curse" then st.multiplier = tonumber(e[3]) or 1.0 end
			local rem = tonumber(e[1]) or 0
			if rem > 0 then
				self.clock:start(st.timer, rem)
				st.max = tonumber(e[2]) or rem
			end
		end
	end
	return self
end

---------------------------------------------------------------- HUD read model

-- Fills `out` (reused; no per-frame tables after the first call) with what a
-- HUD shows. Pure read: never changes state.
function Combat:hud_state(out)
	out = out or {}
	out.player_health, out.player_max_health = self.player_health, self.player_max_health
	out.score = self.score
	out.game_over, out.fight_over = self.game_over, self.fight_over
	out.queue_length = #self.queue
	out.player_stunned = self:status_remaining("stun") > 0
	local st = out.statuses or {}
	out.statuses = st
	st.shield = self.status.shield.stacks
	for i = 1, #Combat.TIMED_STATUSES do
		local id = Combat.TIMED_STATUSES[i]
		local e = st[id] or {}
		st[id] = e
		e.remaining, e.max = self:status_remaining(id), self.status[id].max
	end
	st.curse.multiplier = self:curse_multiplier()
	out.sand_remaining, out.sand_max = self.sim:get_gravity_slow_remaining(), self.sim.slow_max -- Sandstorm (board)
	local enemy = self.enemy
	out.has_enemy = enemy ~= nil
	if enemy ~= nil then
		out.enemy_name, out.enemy_display = enemy.name, enemy.def.display
		out.enemy_health, out.enemy_max_health = enemy.current_health, enemy.max_health
		out.enemy_weak_to = enemy.weak_to_color
		out.enemy_next_attack = enemy:get_time_to_next_attack()
		out.enemy_next_hit = enemy:get_time_to_next_hit()
		out.enemy_winding_up = enemy:is_winding_up()
		out.enemy_stun_remaining, out.enemy_stun_max = enemy:get_stun_remaining(), enemy:get_stun_duration_max()
		out.enemy_stun_kind = enemy:get_status_kind()
		out.enemy_slow_remaining, out.enemy_slow_max = enemy:get_slow_remaining(), enemy:get_slow_duration_max()
		out.enemy_phase_name = enemy.phase_name -- "" before the first phase swap
		out.enemy_aegis_remaining, out.enemy_aegis_max = enemy:get_immune_remaining(), enemy:get_immune_duration_max()
		out.enemy_mirror_remaining, out.enemy_mirror_max = enemy:get_mirror_remaining(), enemy:get_mirror_duration_max()
		out.enemy_mirror_crack_ratio = enemy:get_mirror_crack_ratio()
		out.intents = enemy:peek_upcoming(3, out.intents) -- ability tables (.kind for the glyph)
	end
	return out
end

ns.Combat = Combat
