-- Fails if any file in DragonChess/core/ reads or writes an undeclared global.
-- core/ must stay free of WoW API and accidental globals (loaded as `local _, ns = ...`).
local ALLOWED = {
	_G = true, _VERSION = true, assert = true, collectgarbage = true, error = true, getmetatable = true,
	ipairs = true, next = true, pairs = true, pcall = true, rawget = true, rawset = true, select = true,
	setmetatable = true, tonumber = true, tostring = true, type = true, unpack = true, xpcall = true,
	math = true, string = true, table = true, coroutine = true, os = true, bit = true,
}
local failures = 0
local p = io.popen("ls core/*.lua core/*/*.lua 2>/dev/null")
local files = {}
for line in p:lines() do files[#files + 1] = line end
p:close()
for _, path in ipairs(files) do
	local ns = {}
	local chunk, err = loadfile(path)
	if not chunk then
		print("FAIL " .. path .. ": " .. tostring(err)); failures = failures + 1
	else
		local env = setmetatable({}, {
			__index = function(_, k)
				if ALLOWED[k] then return _G[k] end
				print("FAIL " .. path .. ": reads global '" .. tostring(k) .. "'"); failures = failures + 1
			end,
			__newindex = function(_, k)
				print("FAIL " .. path .. ": writes global '" .. tostring(k) .. "'"); failures = failures + 1
			end,
		})
		setfenv(chunk, env)
		if path:find("core/classes.lua", 1, true) then -- registers variants of the six ability files: load them first
			for _, base in ipairs({ "amber", "amethyst", "emerald", "ruby", "sapphire", "topaz" }) do
				local bc = assert(loadfile("core/abilities/" .. base .. ".lua"))
				setfenv(bc, env)
				bc("DragonChess", ns)
			end
		end
		local ok, e = pcall(chunk, "DragonChess", ns)
		if not ok then print("FAIL " .. path .. ": " .. tostring(e)); failures = failures + 1 end
	end
end
print(failures == 0 and ("PASS lint_globals (" .. #files .. " files)") or ("FAIL lint_globals: " .. failures))
os.exit(failures == 0 and 0 or 1)
