local _, ns = ...
-- Run (W0-G2b): port of the ladder / difficulty / records parts of autoload/run_manager.gd.
-- Pure Lua, no WoW API. One Run per started run; it rides on a Combat (HP, score and
-- statuses live there and carry over from fight to fight).
--
--   local run = Run.new{ combat = combat, difficulty = 1, index = 1 }
--   run:begin_fight()     -- first fight; emits run_fight_starting(run, def) BEFORE
--                         -- combat:start_fight(def) (the UI writes its boundary snapshot there)
--   run:update()          -- once per frame after sim:tick: starts the next fight once the
--                         -- 1.75 s between-fight beat (sim time) is over
--   run:serialize() / Run.deserialize(data, combat)
--
-- Ladder (10 fights): stage 1-3 = two normals + a boss, stage 4 = Nefarian alone
-- (data/enemies.lua list order). Beating a boss before the last fight heals 25 % of max HP
-- (applied the moment the boss dies, so the fight-boundary snapshot already has it); beating
-- the last one wins the run. Difficulty 1..5: enemy HP +15 % and damage +20 % per level above
-- 1, on per-fight COPIES of the enemy and its abilities (data/enemies.lua is never mutated).
-- Boons / Rest / draft are cut.
--
-- Events (on the combat's sim bus):
--   run_fight_starting(run, def)   the scaled def about to start (before combat:start_fight)
--   run_advanced(result, index)    "next_fight" | "stage_complete"; the next fight starts after
--                                  Run.FIGHT_TRANSITION sim seconds (run:update)
--   run_won(run)                   the last boss died (gameplay stays paused; no next fight)
-- A lost run is combat's `run_lost`; the run only notes it (over = "lost").
--
-- Records (plain functions on a SavedVariables-style table, `DragonChessDB`):
--   db.records[difficulty] = { best, wins, runs }, db.unlocked = highest unlocked difficulty.
--   The best score is recorded on win AND loss, the next difficulty unlocks on win only.

local setmetatable, type, tonumber, assert, pairs = setmetatable, type, tonumber, assert, pairs
local floor, min, max = math.floor, math.min, math.max

local Run = {}
Run.__index = Run

Run.MAX_DIFFICULTY = 5
Run.HEAL_PERCENT_AFTER_BOSS = 0.25
Run.DIFF_HP_SCALE_PER_LEVEL = 0.15
Run.DIFF_DMG_SCALE_PER_LEVEL = 0.20
-- Kill -> next fight, sim seconds: Godot FIGHT_DEATH_BEAT 1.0 + FIGHT_CLEAR_STING 0.75.
Run.FIGHT_TRANSITION = 1.75
Run.SNAPSHOT_VERSION = 1
Run.STAGE_SIZES = { 3, 3, 3, 1 }

---------------------------------------------------------------- ladder

local ladder -- { {def, stage, fight}, ... } (lazy: the data file loads before this one, but lint loads files alone)

function Run.ladder()
	if ladder ~= nil then return ladder end
	local list = ns.EnemyData.list
	local out, i = {}, 0
	for stage = 1, #Run.STAGE_SIZES do
		for fight = 1, Run.STAGE_SIZES[stage] do
			i = i + 1
			out[i] = { def = list[i], stage = stage, fight = fight }
		end
	end
	assert(i == #list, "Run ladder size differs from the enemy roster")
	ladder = out
	return out
end

function Run.fight_count()
	return #Run.ladder()
end

---------------------------------------------------------------- difficulty scaling

local function round(x) return ns.StatusMath.round(x) end

-- Playtest 4: fewer, harder attacks. Every enemy ability waits ATTACK_PACE times longer between uses
-- and hits ATTACK_PACE times harder (same damage per second, less interruption). Applied to the
-- run copies only; data/enemies.lua stays the Godot-derived golden data.
Run.ATTACK_PACE = 2.2

-- (hp multiplier, damage multiplier) of a difficulty (1..5).
function Run.multipliers(difficulty)
	local d = difficulty - 1
	return 1.0 + Run.DIFF_HP_SCALE_PER_LEVEL * d, 1.0 + Run.DIFF_DMG_SCALE_PER_LEVEL * d
end

local function scaled_ability(ab, dmg_mult, hp_mult)
	local c = {}
	for k, v in pairs(ab) do c[k] = v end -- copy: order irrelevant
	local pace = Run.ATTACK_PACE
	c.damage_min = round(ab.damage_min * dmg_mult * pace)
	c.damage_max = round(ab.damage_max * dmg_mult * pace)
	c.cooldown = ab.cooldown * pace
	if c.damage_max < c.damage_min then c.damage_max = c.damage_min end
	-- A Mirror Shield's break damage scales with the enemy's HP factor (the crack takes the
	-- same share of the fight). Durations, stun_duration, heal_percent never scale.
	if ab.kind == "mirror" then c.break_damage = round(ab.break_damage * hp_mult) end
	return c
end

-- A difficulty-scaled COPY of an enemy def (get_current_enemy_data): the original def and
-- every original ability stay untouched. One copy per original ability (they are shared
-- across rotations and phases), each scaled exactly once.
function Run.scale_def(def, difficulty)
	local hp_mult, dmg_mult = Run.multipliers(difficulty)
	local copies = {} -- original ability -> scaled copy (lookup only)
	local function swap(rotation)
		local out = {}
		for i = 1, #rotation do
			local ab = rotation[i]
			local c = copies[ab]
			if c == nil then
				c = scaled_ability(ab, dmg_mult, hp_mult)
				copies[ab] = c
			end
			out[i] = c
		end
		return out
	end
	local d = {}
	for k, v in pairs(def) do d[k] = v end -- copy: order irrelevant
	d.max_health = round(def.max_health * hp_mult)
	d.rotation = swap(def.rotation)
	if def.phases ~= nil then
		local phases = {}
		for i = 1, #def.phases do
			local src = def.phases[i]
			local p = {}
			for k, v in pairs(src) do p[k] = v end
			if src.rotation ~= nil then p.rotation = swap(src.rotation) end
			phases[i] = p
		end
		d.phases = phases
	end
	return d
end

-- How much HP the boss heal restores (capped at max).
function Run.boss_heal_amount(hp, max_hp)
	local heal = floor(max_hp * Run.HEAL_PERCENT_AFTER_BOSS)
	return min(max_hp, hp + heal) - hp
end

---------------------------------------------------------------- records (SavedVariables tables)

function Run.clamp_difficulty(n)
	n = tonumber(n)
	if n == nil or n ~= n then return 1 end
	return max(1, min(Run.MAX_DIFFICULTY, floor(n)))
end

-- Highest unlocked difficulty of `db` (a missing / corrupt value = 1).
function Run.unlocked(db)
	return Run.clamp_difficulty(db ~= nil and db.unlocked or 1)
end

function Run.best_score(db, difficulty)
	local recs = db ~= nil and db.records
	local rec = type(recs) == "table" and recs[difficulty]
	return type(rec) == "table" and tonumber(rec.best) or 0
end

function Run.can_choose(db, difficulty)
	return difficulty >= 1 and difficulty <= Run.unlocked(db) and difficulty == floor(difficulty)
end

-- A run ended: record `score` for `difficulty`. Returns new_best (boolean) and, when a win
-- unlocked a higher difficulty, that difficulty (else nil).
function Run.record_result(db, difficulty, score, won)
	if type(db.records) ~= "table" then db.records = {} end
	local rec = db.records[difficulty]
	if type(rec) ~= "table" then
		rec = {}
		db.records[difficulty] = rec
	end
	rec.runs = (tonumber(rec.runs) or 0) + 1
	local new_best = false
	if score > (tonumber(rec.best) or 0) then
		rec.best = score
		new_best = true
	end
	local unlocked_now
	if won then
		rec.wins = (tonumber(rec.wins) or 0) + 1
		local nxt = min(difficulty + 1, Run.MAX_DIFFICULTY)
		if nxt > Run.unlocked(db) then
			db.unlocked = nxt
			unlocked_now = nxt
		end
	end
	return new_best, unlocked_now
end

---------------------------------------------------------------- run

-- opts: combat (required), difficulty (1..5), index (1..10, the fight to begin).
function Run.new(opts)
	local combat = assert(opts.combat, "Run.new: combat required")
	local self = setmetatable({}, Run)
	self.combat = combat
	self.sim = combat.sim
	self.difficulty = Run.clamp_difficulty(opts.difficulty)
	self.index = max(1, min(Run.fight_count(), floor(tonumber(opts.index) or 1)))
	self.over = false -- false | "won" | "lost"
	self.next_at = nil -- sim time the next fight starts (after a kill)
	self.forced = nil -- dev: base def forced by /dchess fight (also for the following fights)
	self.dev = false -- a dev fight was started: no records
	combat:on("enemy_defeated", function() self:_on_enemy_defeated() end)
	combat:on("run_lost", function()
		self.over = "lost"
		self.next_at = nil
	end)
	return self
end

function Run:stage() return Run.ladder()[self.index].stage end

function Run:fight_in_stage() return Run.ladder()[self.index].fight end

-- "STAGE 2-1" (the dev fight reads "DEV").
function Run:label()
	if self.forced ~= nil then return "DEV" end
	local e = Run.ladder()[self.index]
	return "STAGE " .. e.stage .. "-" .. e.fight
end

function Run:base_def()
	return self.forced or Run.ladder()[self.index].def
end

function Run:is_boss()
	return self:base_def().is_boss == true
end

-- The scaled copy of the current fight's enemy.
function Run:current_def()
	return Run.scale_def(self:base_def(), self.difficulty)
end

-- Starts the current fight (a new scaled copy). `forced_def` (dev): that enemy, and the
-- following fights too until the run ends.
function Run:begin_fight(forced_def)
	if self.over then return nil end
	if forced_def ~= nil then
		self.forced = forced_def
		self.dev = true
	end
	self.next_at = nil
	local def = self:current_def()
	self.sim:emit("run_fight_starting", self, def)
	return self.combat:start_fight(def)
end

-- The boss died or the last fight was won (enemy_defeated): heal after a boss, advance.
-- Returns "next_fight" / "stage_complete" / "run_won".
function Run:advance()
	local lad = Run.ladder()
	if self.index >= #lad then
		self.over = "won"
		self.next_at = nil
		self.sim:emit("run_won", self)
		return "run_won"
	end
	if self:is_boss() then
		self.combat:heal_player(floor(self.combat.player_max_health * Run.HEAL_PERCENT_AFTER_BOSS))
	end
	local stage = lad[self.index].stage
	self.index = self.index + 1
	local result = lad[self.index].stage ~= stage and "stage_complete" or "next_fight"
	self.next_at = self.sim.now + Run.FIGHT_TRANSITION
	self.sim:emit("run_advanced", result, self.index)
	return result
end

function Run:_on_enemy_defeated()
	if self.over then return end
	self:advance()
end

-- Per frame, after sim:tick: begin the next fight when the between-fight beat is over.
function Run:update()
	local at = self.next_at
	if at ~= nil and self.sim.now >= at then self:begin_fight() end
end

---------------------------------------------------------------- snapshot

-- The ladder position of the fight that is about to start / running (the fight-boundary
-- snapshot belongs with Combat:serialize()).
function Run:serialize()
	return { v = Run.SNAPSHOT_VERSION, difficulty = self.difficulty, index = self.index }
end

-- Returns a run on `combat` or nil (corrupt / other version).
function Run.deserialize(data, combat)
	if type(data) ~= "table" or data.v ~= Run.SNAPSHOT_VERSION then return nil end
	local d, i = tonumber(data.difficulty), tonumber(data.index)
	if d == nil or i == nil or d ~= floor(d) or i ~= floor(i) then return nil end
	if d < 1 or d > Run.MAX_DIFFICULTY or i < 1 or i > Run.fight_count() then return nil end
	return Run.new({ combat = combat, difficulty = d, index = i })
end

ns.Run = Run
