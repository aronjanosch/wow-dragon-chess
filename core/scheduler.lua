local _, ns = ...
-- Event-driven coroutine scheduler on continuous sim time (W0-T1 contract).
--
--  * spawn(fn, ...) runs fn IMMEDIATELY up to its first yield (Godot: a signal
--    handler runs synchronously until its first await).
--  * Inside a spawned coroutine: wait(s) (gameplay time - frozen while the
--    gameplay-pause gate is closed, like a board tween), wait_real(s) (sim time,
--    ignores the gate, like a SceneTree timer), wait_until(pred), wait_event(name).
--  * tick(dt) (dt clamped to MAX_DT) jumps to each due wake-up in order: earliest
--    due time first, ties by spawn order. Results never depend on how the time
--    is cut into ticks.
--  * pause_gameplay() / resume_gameplay(): the gameplay-pause gate (Godot
--    board.pause_gameplay + wait_if_paused). Hide-pause is simply not ticking.
--  * emit(name, ...): listeners (on) run first, then coroutines waiting on that
--    event are resumed synchronously (Godot: emit resumes awaiting functions).
--  * A coroutine error is re-raised as error(traceback(co, err)) from whatever
--    resumed it (tick / emit / spawn). Default traceback: ns.traceback if the
--    loader provides one (headless: debug.traceback; WoW: debugstack), else the
--    plain message.
--  * Never yield inside pcall or a table.sort comparator (PUC Lua 5.1 / WoW
--    forbid it; LuaJIT allows it and would hide the bug) - see test/lint_yield.lua.

local co_create, co_resume, co_yield = coroutine.create, coroutine.resume, coroutine.yield
local co_running, co_status = coroutine.running, coroutine.status
local setmetatable = setmetatable
local tostring = tostring
local error = error

local Scheduler = {}
Scheduler.__index = Scheduler

-- Task wait modes.
local NONE, TIME, EVENT, PRED = 0, 1, 2, 3

function Scheduler.new(opts)
	local self = setmetatable({}, Scheduler)
	Scheduler.init(self, opts)
	return self
end

function Scheduler.init(self, opts)
	opts = opts or {}
	self.now = 0 -- sim time (advances while ticked)
	self.pause_acc = 0 -- sim time spent gameplay-paused (closed intervals)
	self.paused_at = 0
	self.gameplay_paused = false
	self.max_dt = opts.max_dt or (ns.Timings and ns.Timings.MAX_DT) or 0.05
	self.tasks = {} -- live tasks in spawn order
	self.task_of = {} -- coroutine -> task (lookup only, never iterated)
	self.seq = 0
	self.listeners = {}
	self.traceback = opts.traceback or ns.traceback or function(_, msg) return tostring(msg) end
end

-- Gameplay time: frozen while the gameplay-pause gate is closed.
function Scheduler:gnow()
	if self.gameplay_paused then return self.paused_at - self.pause_acc end
	return self.now - self.pause_acc
end

---------------------------------------------------------------- tasks

local function remove_task(self, task)
	local tasks = self.tasks
	for i = 1, #tasks do
		if tasks[i] == task then
			table.remove(tasks, i)
			break
		end
	end
	self.task_of[task.co] = nil
	task.dead = true
end

local function resume(self, task, ...)
	task.mode = NONE
	task.due = nil
	task.pred = nil
	task.event = nil
	local co = task.co
	local ok, err = co_resume(co, ...)
	if not ok then
		remove_task(self, task)
		error(self.traceback(co, tostring(err)), 0)
	end
	if co_status(co) == "dead" then remove_task(self, task) end
end

-- Run fn(...) as a sim coroutine, immediately up to its first yield.
-- `service` tasks (background timers) don't count as pending work for
-- is_idle / settle_now.
function Scheduler:spawn(fn, ...)
	self.seq = self.seq + 1
	local co = co_create(fn)
	local task = { co = co, seq = self.seq, mode = NONE, wgen = 0 }
	self.tasks[#self.tasks + 1] = task
	self.task_of[co] = task
	resume(self, task, ...)
	return task
end

function Scheduler:spawn_service(fn, ...)
	self.seq = self.seq + 1
	local co = co_create(fn)
	local task = { co = co, seq = self.seq, mode = NONE, wgen = 0, service = true }
	self.tasks[#self.tasks + 1] = task
	self.task_of[co] = task
	resume(self, task, ...)
	return task
end

local function current(self)
	local co = co_running()
	local task = co and self.task_of[co]
	if task == nil then error("sim wait outside a sim coroutine", 3) end
	return task
end

-- Wait `seconds` of gameplay time (a board tween: frozen by pause_gameplay).
function Scheduler:wait(seconds)
	local task = current(self)
	task.mode = TIME
	task.gated = true
	task.wgen = task.wgen + 1
	if self.gameplay_paused then
		task.due = nil
		task.remaining = seconds
	else
		task.due = self.now + seconds
	end
	return co_yield()
end

-- Wait `seconds` of sim time, ignoring the gameplay-pause gate.
function Scheduler:wait_real(seconds)
	local task = current(self)
	task.mode = TIME
	task.gated = false
	task.wgen = task.wgen + 1
	task.due = self.now + seconds
	return co_yield()
end

-- Wait until pred() is true (checked after every scheduler step).
function Scheduler:wait_until(pred)
	if pred() then return end
	local task = current(self)
	task.mode = PRED
	task.pred = pred
	task.wgen = task.wgen + 1
	return co_yield()
end

-- Wait for the next emit(name); returns the emit's arguments.
function Scheduler:wait_event(name)
	local task = current(self)
	task.mode = EVENT
	task.event = name
	task.wgen = task.wgen + 1
	return co_yield()
end

-- Godot wait_if_paused().
function Scheduler:wait_if_paused()
	if self.gameplay_paused then self:wait_event("gameplay_unpaused") end
end

---------------------------------------------------------------- events

function Scheduler:on(name, fn)
	local list = self.listeners[name]
	if list == nil then
		list = {}
		self.listeners[name] = list
	end
	list[#list + 1] = fn
	return fn
end

function Scheduler:off(name, fn)
	local list = self.listeners[name]
	if list == nil then return end
	for i = #list, 1, -1 do
		if list[i] == fn then table.remove(list, i) end
	end
end

function Scheduler:emit(name, ...)
	local list = self.listeners[name]
	if list ~= nil then
		local n = #list
		for i = 1, n do
			local fn = list[i]
			if fn then fn(...) end
		end
	end
	-- Snapshot the waiters first: a resumed coroutine that waits on the same
	-- event again must not be woken by this emit (wgen guards nested emits).
	local tasks = self.tasks
	local waiters
	for i = 1, #tasks do
		local t = tasks[i]
		if t.mode == EVENT and t.event == name then
			waiters = waiters or {}
			waiters[#waiters + 1] = t
			waiters[#waiters + 1] = t.wgen
		end
	end
	if waiters == nil then return end
	for i = 1, #waiters, 2 do
		local t = waiters[i]
		if not t.dead and t.mode == EVENT and t.event == name and t.wgen == waiters[i + 1] then
			resume(self, t, ...)
		end
	end
end

---------------------------------------------------------------- pause gate

function Scheduler:pause_gameplay()
	if self.gameplay_paused then return end
	self.gameplay_paused = true
	self.paused_at = self.now
	local tasks = self.tasks
	for i = 1, #tasks do
		local t = tasks[i]
		if t.mode == TIME and t.gated and t.due ~= nil then
			t.remaining = t.due - self.now
			t.due = nil
		end
	end
end

function Scheduler:resume_gameplay()
	if not self.gameplay_paused then return end
	self.gameplay_paused = false
	self.pause_acc = self.pause_acc + (self.now - self.paused_at)
	local tasks = self.tasks
	for i = 1, #tasks do
		local t = tasks[i]
		if t.mode == TIME and t.gated and t.due == nil then
			t.due = self.now + t.remaining
			t.remaining = nil
		end
	end
	self:emit("gameplay_unpaused")
end

function Scheduler:is_gameplay_paused()
	return self.gameplay_paused
end

---------------------------------------------------------------- driving

local function check_preds(self)
	local guard = 0
	local i = 1
	while i <= #self.tasks do
		local t = self.tasks[i]
		if t.mode == PRED and t.pred() then
			resume(self, t)
			guard = guard + 1
			if guard > 100000 then error("wait_until livelock", 0) end
			i = 1 -- state changed: rescan in spawn order
		else
			i = i + 1
		end
	end
end
Scheduler._check_preds = check_preds

-- Earliest due timed task (ties: spawn order), optionally only due <= limit.
local function next_due(self, limit)
	local best
	local tasks = self.tasks
	for i = 1, #tasks do
		local t = tasks[i]
		local due = t.mode == TIME and t.due
		if due and (limit == nil or due <= limit) and (best == nil or due < best.due) then
			best = t
		end
	end
	return best
end

-- One scheduler step: wake `task` at its due time.
local function step(self, task)
	if task.due > self.now then self.now = task.due end
	resume(self, task)
	check_preds(self)
end

-- Advance sim time by dt (clamped to max_dt), waking every due coroutine in order.
function Scheduler:tick(dt)
	if dt == nil or dt < 0 then dt = 0 end
	if dt > self.max_dt then dt = self.max_dt end
	local target = self.now + dt
	check_preds(self)
	while true do
		local task = next_due(self, target)
		if task == nil then break end
		step(self, task)
	end
	self.now = target
	if self.on_tick_end then self:on_tick_end() end
end

-- Any non-service task alive?
function Scheduler:has_work()
	local tasks = self.tasks
	for i = 1, #tasks do
		if not tasks[i].service then return true end
	end
	return false
end

-- Run the scheduler with unbounded virtual time until no non-service task is
-- left. Returns true when idle; false if the remaining work can't progress
-- (waits on an event / predicate that never comes, or gameplay is paused).
function Scheduler:run_until_idle(max_steps)
	max_steps = max_steps or 1000000
	check_preds(self)
	local steps = 0
	while self:has_work() do
		local task = next_due(self, nil)
		if task == nil then return false end
		step(self, task)
		steps = steps + 1
		if steps > max_steps then return false end
	end
	if self.on_tick_end then self:on_tick_end() end
	return true
end

ns.Scheduler = Scheduler
