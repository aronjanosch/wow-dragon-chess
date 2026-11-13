-- Lint: no yield inside pcall / table.sort comparators in core/ (PUC Lua 5.1 and
-- WoW raise "attempt to yield across metamethod/C-call boundary"; LuaJIT allows
-- it, so a LuaJIT-only test run would hide the bug).
-- Rules (text level, comments stripped):
--   1. core/ never calls pcall / xpcall (the scheduler uses coroutine.resume).
--   2. a table.sort(...) call never contains wait / yield (inline comparator).
-- Run directly: lint over DragonChess/core. dofile() returns { scan = fn }.
local M = {}

local function strip_comments(src)
	src = src:gsub("%-%-%[(=*)%[.-%]%1%]", "") -- long comments
	src = src:gsub("%-%-[^\n]*", "")
	return src
end

-- Text from the "(" at `open` to its matching ")".
local function call_body(src, open)
	local depth = 0
	for i = open, #src do
		local ch = src:sub(i, i)
		if ch == "(" then
			depth = depth + 1
		elseif ch == ")" then
			depth = depth - 1
			if depth == 0 then return src:sub(open, i) end
		end
	end
	return src:sub(open)
end

-- Returns a list of problem strings for one source text.
function M.scan(src, name)
	local problems = {}
	local code = strip_comments(src)
	for pos, fn in code:gmatch("()[%w_%.:]*(x?pcall)%s*%(") do
		local line = select(2, code:sub(1, pos):gsub("\n", "")) + 1
		problems[#problems + 1] = ("%s:%d: %s in core (yield inside it breaks on Lua 5.1 / WoW)"):format(name, line, fn)
	end
	local start = 1
	while true do
		local s, e = code:find("table%.sort%s*%(", start)
		if not s then break end
		local body = call_body(code, e)
		if body:find("wait") or body:find("yield") then
			local line = select(2, code:sub(1, s):gsub("\n", "")) + 1
			problems[#problems + 1] = ("%s:%d: wait/yield inside a table.sort comparator"):format(name, line)
		end
		start = e + 1
	end
	return problems
end

function M.main()
	local dir = (debug.getinfo(1, "S").source:sub(2):match("^(.*)/test/[^/]*$") or ".") .. "/core/"
	local p = io.popen('ls "' .. dir .. '"*.lua "' .. dir .. '"*/*.lua 2>/dev/null')
	local files = {}
	for line in p:lines() do files[#files + 1] = line end
	p:close()
	local all = {}
	for _, path in ipairs(files) do
		local f = assert(io.open(path))
		local src = f:read("*a")
		f:close()
		for _, msg in ipairs(M.scan(src, path:match("[^/]+/[^/]+$"))) do all[#all + 1] = msg end
	end
	for _, msg in ipairs(all) do print("FAIL lint_yield: " .. msg) end
	if #all == 0 then print("PASS lint_yield (" .. #files .. " files)") end
	os.exit(#all == 0 and 0 or 1)
end

if arg and arg[0] and arg[0]:match("lint_yield%.lua$") then M.main() end
return M
