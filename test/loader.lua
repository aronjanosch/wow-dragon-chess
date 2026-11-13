-- Headless addon loader: loads core/ files in TOC order the way WoW does
-- (chunk(addonName, ns)), each in a strict environment so a runtime read or
-- write of an undeclared global fails the test (lint_globals only sees load time).
-- Usage: local ns = dofile(<wow dir> .. "/test/loader.lua").load()
local M = {}

M.CORE_FILES = {
	"core/rng.lua",
	"core/timings.lua",
	"core/board.lua",
	"core/match.lua",
	"core/scheduler.lua",
	"core/board_effects.lua",
	"core/sim.lua",
	"core/clock.lua",
	"core/kit.lua",
	"core/abilities/amber.lua",
	"core/abilities/amethyst.lua",
	"core/abilities/emerald.lua",
	"core/abilities/ruby.lua",
	"core/abilities/sapphire.lua",
	"core/abilities/topaz.lua",
	"core/classes.lua",
	"data/enemies.lua",
	"core/enemy_abilities.lua",
	"core/enemy.lua",
	"core/combat.lua",
	"core/run.lua",
	"core/debug.lua",
}

-- Directory of the wow/ folder, derived from this file's path.
function M.wow_dir()
	local src = debug.getinfo(1, "S").source:sub(2)
	return src:match("^(.*)/test/[^/]*$") or "."
end

local ALLOWED = {
	_G = true, _VERSION = true, assert = true, collectgarbage = true, error = true, getmetatable = true,
	ipairs = true, next = true, pairs = true, pcall = true, rawget = true, rawset = true, select = true,
	setmetatable = true, tonumber = true, tostring = true, type = true, unpack = true, xpcall = true,
	math = true, string = true, table = true, coroutine = true, os = true, bit = true,
}

local strict_env = setmetatable({}, {
	__index = function(_, k)
		if ALLOWED[k] then return _G[k] end
		error("core reads undeclared global '" .. tostring(k) .. "'", 2)
	end,
	__newindex = function(_, k)
		error("core writes global '" .. tostring(k) .. "'", 2)
	end,
})

-- Files the release build leaves out (tools/package.sh removes them from the staged tree and the TOC).
M.DEBUG_FILES = { ["core/debug.lua"] = true, ["ui/debug.lua"] = true }

-- Every file of DragonChess.toc in load order; opts.release drops the debug files like the release package does.
function M.toc_files(opts)
	local release = opts ~= nil and opts.release
	local f = assert(io.open(M.wow_dir() .. "/DragonChess.toc"))
	local files = {}
	for line in f:lines() do
		line = line:gsub("\r", ""):match("^%s*(.-)%s*$")
		if line ~= "" and not line:match("^#") and not (release and M.DEBUG_FILES[line]) then files[#files + 1] = line end
	end
	f:close()
	return files
end

-- opts.release: load only the core files of the release TOC.
function M.load(opts)
	local dir = M.wow_dir() .. "/"
	local ns = { traceback = debug.traceback }
	local release = opts ~= nil and opts.release
	for _, f in ipairs(M.CORE_FILES) do
		if not (release and M.DEBUG_FILES[f]) then
			local chunk = assert(loadfile(dir .. f))
			setfenv(chunk, strict_env)
			chunk("DragonChess", ns)
		end
	end
	return ns
end

return M
