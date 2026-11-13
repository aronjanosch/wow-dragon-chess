-- core/scheduler.lua: the W0-T1 scheduler contract.
local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "."
local H = dofile(dir .. "/helpers.lua")
local T, ns = H.T, H.ns
local Scheduler = ns.Scheduler
local IS_JIT = jit ~= nil
T.start("scheduler_test")

local function new(opts)
	opts = opts or {}
	opts.max_dt = opts.max_dt or 1
	return Scheduler.new(opts)
end

T.case("spawn runs immediately up to the first yield", function()
	local s = new()
	local before, after = false, false
	s:spawn(function()
		before = true
		s:wait(0.1)
		after = true
	end)
	T.ok(before, "body ran before spawn returned")
	T.ok(not after, "stopped at the first wait")
	s:tick(0.1)
	T.ok(after, "woke at its due time")
	T.ok(not s:has_work(), "finished task removed")
	-- nested spawn from inside a coroutine also runs immediately
	local order = {}
	s:spawn(function()
		order[#order + 1] = "outer1"
		s:spawn(function()
			order[#order + 1] = "inner1"
			s:wait(0)
			order[#order + 1] = "inner2"
		end)
		order[#order + 1] = "outer2"
	end)
	T.eq(table.concat(order, " "), "outer1 inner1 outer2", "nested spawn order")
	s:tick(0)
	T.eq(table.concat(order, " "), "outer1 inner1 outer2 inner2", "wait(0) wakes on the next tick")
end)

local function wake_log(dts)
	local s = new()
	local log = {}
	local function task(name, waits)
		s:spawn(function()
			for _, w in ipairs(waits) do
				s:wait(w)
				log[#log + 1] = ("%s@%.6f"):format(name, s.now)
			end
		end)
	end
	task("A", { 0.3, 0.05 })
	task("B", { 0.1, 0.25 })
	task("C", { 0.1, 0.2 })
	task("D", { 0.35 })
	for _, dt in ipairs(dts) do s:tick(dt) end
	return table.concat(log, " ")
end

T.case("wake order: earliest due first, ties by spawn order", function()
	local log = wake_log({ 1 })
	-- ties at 0.1 (B, C), 0.3 (A, C) and 0.35 (A, B, D) resolve in spawn order
	T.eq(log, "B@0.100000 C@0.100000 A@0.300000 C@0.300000 A@0.350000 B@0.350000 D@0.350000",
		"wake order")
end)

T.case("results do not depend on how time is cut into ticks", function()
	local ref = wake_log({ 1 })
	local small = {}
	for i = 1, 200 do small[i] = 1 / 144 end
	local odd = {}
	for i = 1, 100 do odd[i] = (i % 7 + 1) * 0.0031 end
	T.eq(wake_log(small), ref, "144 Hz ticks")
	T.eq(wake_log(odd), ref, "irregular ticks")
end)

T.case("dt is clamped", function()
	local s = Scheduler.new({})
	s:tick(10)
	T.eq(s.now, 0.05, "tick(10) advances MAX_DT only")
	s:tick(-1)
	T.eq(s.now, 0.05, "negative dt ignored")
end)

T.case("wait_event resumes synchronously with the emit arguments", function()
	local s = new()
	local got, count = nil, 0
	s:spawn(function()
		while true do
			local a, b = s:wait_event("ping")
			count = count + 1
			got = tostring(a) .. "," .. tostring(b)
		end
	end)
	s:emit("ping", 1, "x")
	T.eq(got, "1,x", "args passed")
	T.eq(count, 1, "re-waiting on the same event is not woken twice by one emit")
	s:emit("pong")
	T.eq(count, 1, "other events ignored")
	s:emit("ping", 2)
	T.eq(count, 2, "second emit")
	-- listeners run before waiters
	local order = {}
	s:on("x", function() order[#order + 1] = "listener" end)
	s:spawn(function() s:wait_event("x"); order[#order + 1] = "waiter" end)
	s:emit("x")
	T.eq(table.concat(order, " "), "listener waiter", "listener first")
end)

T.case("wait_until checks after every step", function()
	local s = new()
	local flag, done_at = false, nil
	s:spawn(function() s:wait(0.2); flag = true end)
	s:spawn(function()
		s:wait_until(function() return flag end)
		done_at = s.now
	end)
	s:tick(0.5)
	T.eq(done_at, 0.2, "predicate woke at the step that made it true")
	local immediate = false
	s:spawn(function() s:wait_until(function() return true end); immediate = true end)
	T.ok(immediate, "true predicate does not yield")
end)

T.case("gameplay-pause gate", function()
	local s = new()
	local gated_at, real_at, after_gate = nil, nil, nil
	s:spawn(function() s:wait(0.5); gated_at = s.now end)
	s:spawn(function() s:wait_real(0.5); real_at = s.now end)
	s:tick(0.2)
	s:pause_gameplay()
	T.ok(s:is_gameplay_paused(), "paused")
	local g0 = s:gnow()
	s:spawn(function() s:wait_if_paused(); after_gate = s.now end)
	T.eq(after_gate, nil, "wait_if_paused holds")
	s:tick(1.0)
	T.eq(gated_at, nil, "gated wait frozen while paused")
	T.eq(real_at, 0.5, "real-time wait ignores the gate")
	T.eq(s:gnow(), g0, "gameplay clock frozen")
	local unpaused = 0
	s:on("gameplay_unpaused", function() unpaused = unpaused + 1 end)
	s:resume_gameplay()
	T.eq(unpaused, 1, "gameplay_unpaused emitted")
	T.eq(after_gate, 1.2, "wait_if_paused released on resume")
	s:tick(0.29)
	T.eq(gated_at, nil, "remaining time not yet elapsed")
	s:tick(0.02)
	T.ok(gated_at and math.abs(gated_at - 1.5) < 1e-9, "gated wait finished after its remaining 0.3 s: " .. tostring(gated_at))
	-- a wait started while paused only starts counting on resume
	local w
	s:pause_gameplay()
	s:spawn(function() s:wait(0.1); w = s.now end)
	s:tick(1)
	T.eq(w, nil, "wait started while paused is frozen")
	s:resume_gameplay()
	s:tick(0.1)
	T.ok(w ~= nil, "it runs after resume")
	s:resume_gameplay()
	T.eq(unpaused, 2, "resume when not paused is a no-op")
end)

T.case("errors are re-raised with a traceback", function()
	local s = new()
	s:spawn(function()
		s:wait(0.1)
		local t = nil
		return t.field -- boom
	end)
	local ok, err = pcall(s.tick, s, 0.2)
	T.ok(not ok, "tick raised")
	T.ok(tostring(err):find("attempt to index") ~= nil, "message kept: " .. tostring(err))
	T.ok(tostring(err):find("stack traceback") ~= nil, "traceback attached")
	T.ok(not s:has_work(), "crashed task removed")
	local ok2, err2 = pcall(s.spawn, s, function() error("at spawn") end)
	T.ok(not ok2 and tostring(err2):find("at spawn") ~= nil, "error before the first yield raised from spawn")
	local ok3, err3 = pcall(s.wait, s, 1)
	T.ok(not ok3 and tostring(err3):find("outside a sim coroutine") ~= nil, "wait outside a coroutine is an error")
end)

T.case("yield inside pcall: lint flags it; Lua 5.1 errors, LuaJIT hides it", function()
	local lint = dofile(dir .. "/lint_yield.lua")
	local bad = "local ok = pcall(function() sim:wait(1) end)\n"
	T.eq(#lint.scan(bad, "snippet"), 1, "pcall flagged")
	local bad_sort = "table.sort(list, function(a, b) sim:wait(0) return a < b end)\n"
	T.eq(#lint.scan(bad_sort, "snippet"), 1, "yield in sort comparator flagged")
	T.eq(#lint.scan("table.sort(list, function(a, b) return a < b end)\n-- pcall(x)\n", "ok"), 0,
		"plain sort / comment not flagged")
	-- runtime behaviour of the hidden bug
	local s = new()
	local inner_ok, inner_err, resumed_at
	s:spawn(function()
		inner_ok, inner_err = pcall(function() s:wait(0.1) end)
		resumed_at = s.now
	end)
	if IS_JIT then
		T.eq(inner_ok, nil, "LuaJIT really yields across pcall (the bug is invisible here)")
		s:tick(0.1)
		T.eq(resumed_at, 0.1, "LuaJIT: the wait inside pcall worked")
	else
		T.ok(inner_ok == false and tostring(inner_err):find("yield across") ~= nil,
			"Lua 5.1: pcall swallows 'attempt to yield across' - the wait silently does not wait: "
			.. tostring(inner_err))
		T.eq(resumed_at, 0, "Lua 5.1: continued immediately")
	end
end)

T.case("run_until_idle", function()
	local s = new()
	local n = 0
	for i = 1, 5 do
		s:spawn(function() s:wait(i * 0.7); n = n + 1 end)
	end
	s:spawn_service(function() s:wait(100); n = n + 100 end)
	T.ok(s:run_until_idle(), "idle")
	T.eq(n, 5, "all tasks ran, service task not waited for")
	T.ok(math.abs(s.now - 3.5) < 1e-9, "virtual time advanced to the last wake: " .. s.now)
	s:spawn(function() s:wait_event("never") end)
	T.ok(not s:run_until_idle(), "stuck on an event -> false")
end)

T.done()
