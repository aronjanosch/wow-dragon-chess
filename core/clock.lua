local _, ns = ...
-- Combat clock (W0-G1): restartable one-shot timers on the sim's gameplay time
-- for statuses and the enemy (Godot: battle._process status ticks and the
-- enemy's AttackTimer). Each running timer is a scheduler *service* task, so it
-- wakes at its exact gameplay time, freezes with the gameplay-pause gate and
-- never counts as board work (is_at_rest / settle_now ignore it).
--
-- freeze() / thaw(): stop every timer and keep its remaining time, then re-arm
-- it with that time (Combat:settle_now uses this so board work run with
-- unbounded virtual time can't let the enemy attack or a status run out).
--
--   local rec = clock:timer(fn)   -- fn(rec) runs when the timer fires
--   clock:start(rec, seconds) / clock:stop(rec) / clock:left(rec) / clock:remove(rec)
--   clock:hold(rec, on)           -- dev: keep one timer's remaining time frozen (a start while held only
--                                    stores the time); hold(rec, false) re-arms it (W0-P5 debug)

local setmetatable = setmetatable
local sort = table.sort

local Clock = {}
Clock.__index = Clock

function Clock.new(sim)
	return setmetatable({ sim = sim, recs = {}, frozen = false, seq = 0 }, Clock)
end

-- New stopped timer, registered with this clock.
function Clock:timer(fn)
	local rec = { fn = fn, gen = 0, active = false, due = 0, held = 0, seq = 0 }
	self.recs[#self.recs + 1] = rec
	return rec
end

local function run(clock, rec, gen, seconds)
	clock.sim:wait(seconds)
	if rec.gen == gen and rec.active then
		rec.active = false
		rec.fn(rec)
	end
end

-- (Re)start: fires `seconds` of gameplay time from now (replaces a running one).
function Clock:start(rec, seconds)
	if seconds < 0 then seconds = 0 end
	rec.gen = rec.gen + 1
	rec.active = true
	self.seq = self.seq + 1
	rec.seq = self.seq
	if self.frozen or rec.hold_on then
		rec.held = seconds
		return
	end
	rec.due = self.sim:gnow() + seconds
	self.sim:spawn_service(run, self, rec, rec.gen, seconds)
end

function Clock:stop(rec)
	rec.gen = rec.gen + 1
	rec.active = false
end

-- Seconds until it fires (0 when stopped).
function Clock:left(rec)
	if not rec.active then return 0 end
	if self.frozen or rec.hold_on then return rec.held end
	local l = rec.due - self.sim:gnow()
	return l > 0 and l or 0
end

function Clock:is_running(rec)
	return rec.active
end

-- Stop and unregister (an enemy that leaves the fight).
function Clock:remove(rec)
	self:stop(rec)
	local recs = self.recs
	for i = #recs, 1, -1 do
		if recs[i] == rec then table.remove(recs, i) end
	end
end

-- Dev hold of one timer (the debug panel's "pause enemy timers"): its remaining time stays put until
-- hold(rec, false). Independent of freeze() / thaw() (both keep working while held).
function Clock:hold(rec, on)
	on = on and true or false
	if (rec.hold_on or false) == on then return end
	if on then
		if rec.active and not self.frozen then
			rec.held = self:left(rec)
			rec.gen = rec.gen + 1 -- the running task becomes stale
		end
		rec.hold_on = true
	else
		rec.hold_on = false
		if rec.active and not self.frozen then self:start(rec, rec.held) end
	end
end

function Clock:freeze()
	if self.frozen then return end
	local recs = self.recs
	for i = 1, #recs do
		local rec = recs[i]
		if rec.active and not rec.hold_on then
			rec.held = self:left(rec)
			rec.gen = rec.gen + 1 -- the running task becomes stale
		end
	end
	self.frozen = true
end

-- Re-arm in original start order, so equal due times keep their tie order.
function Clock:thaw()
	if not self.frozen then return end
	self.frozen = false
	local list = {}
	local recs = self.recs
	for i = 1, #recs do
		if recs[i].active then list[#list + 1] = recs[i] end
	end
	sort(list, function(a, b) return a.seq < b.seq end)
	for i = 1, #list do self:start(list[i], list[i].held) end
end

ns.Clock = Clock
