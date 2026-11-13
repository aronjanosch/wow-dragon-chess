-- W0-P6 test: the pooled juice layer (ui/juice.lua + its wiring in ui/fight_view.lua and ui/board_view.lua):
-- gem break curves / flash / spin, match break shards, ability spawn rings, streaks (the hit reaction waits for the
-- arrival, pool bounds, heavier ult, enemy cast / heal / reflect / Mirror directions), vignette colours, trauma
-- shake (rest position restored exactly, drag / option / pause guards), menu option, debug buttons, allocation.
-- Loads the addon in TOC order under test/wow_stubs.lua like ui_fx_test.
local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "."
local T = dofile(dir .. "/t.lua")
local loader = dofile(dir .. "/loader.lua")
local Stubs = dofile(dir .. "/wow_stubs.lua")
T.start("ui_juice_test")

local ADDON = "DragonChess"
local addon_dir = loader.wow_dir() .. "/"
local DT = 1 / 60

local function read_toc()
	local files = {}
	local f = assert(io.open(addon_dir .. "DragonChess.toc"))
	for line in f:lines() do
		line = line:gsub("\r", "")
		if line:match("%S") and not line:match("^#") then files[#files + 1] = line:match("^%s*(.-)%s*$") end
	end
	f:close()
	return files
end
local toc_files = read_toc()

local function session(setup, saved)
	local W = Stubs.new()
	if setup then setup(W) end
	local ns = {}
	for _, f in ipairs(toc_files) do W.load(addon_dir .. f, ADDON, ns) end
	if saved then
		for k, v in pairs(saved) do W.store[k] = v end
	end
	W.fire("ADDON_LOADED", ADDON)
	W.ns, W.App = ns, ns.App
	return W
end

local function slash_raw(W, msg) W.stubs.SlashCmdList.DRAGONCHESS(msg or "") end
-- W0-P10: opening the window shows the start / resume panel (game paused); these tests want a running game.
local function slash(W, msg)
	slash_raw(W, msg)
	if W.App ~= nil and W.App.start_open then W.App.close_start() end
end
-- W0-P10: streak flight is Juice.FLY (x FLY_HEAVY for an ult); waits derive from it, not from literals.
local function fly_frames(W) return math.ceil(W.ns.Juice.FLY * W.ns.Juice.FLY_HEAVY / DT) end
local function frames(W, n) for _ = 1, n do W.update(DT) end end
local function frames_until(W, pred, n)
	for _ = 1, n or 3000 do
		if pred() then return true end
		W.update(DT)
	end
	return pred()
end
local function open_ready(W)
	slash(W, "")
	local App = W.App
	T.ok(frames_until(W, function() return App.sim:is_at_rest() and App.combat:can_player_swap() == "" end), "board at rest")
	return App
end
local function alloc_kb(fn, n, reset)
	if jit then jit.off(); jit.flush() end
	collectgarbage("collect")
	collectgarbage("stop")
	fn() -- warm-up (see ui_fx_test: the collect can shrink the stack, a one-off regrow is not per-frame garbage)
	fn()
	if reset then reset() end
	local kb = collectgarbage("count")
	for _ = 1, n do fn() end
	local grown = collectgarbage("count") - kb
	collectgarbage("restart")
	if jit then jit.on() end
	return grown
end
local function click(page, label)
	for _, ch in ipairs(page.children) do
		if ch.ftype == "Button" and ch.text ~= nil and ch.text.text == label then
			ch:Click()
			return ch
		end
	end
	T.ok(false, "button '" .. label .. "' exists")
end
local function chat_since(W, n)
	local out = {}
	for i = n + 1, #W.printed do out[#out + 1] = W.printed[i] end
	return table.concat(out, "\n")
end

local function gems_at(cells)
	local g = {}
	for i, c in ipairs(cells) do g[i] = { x = c[1], y = c[2], col = c[1], row = c[2], type = c[3] or 3 } end
	return g
end
local function shown_count(pool)
	local n = 0
	for i = 1, #pool do
		if pool[i].shown then n = n + 1 end
	end
	return n
end
local function live_pops(pool)
	local out = {}
	for i = 1, #pool do
		if pool[i].shown then out[#out + 1] = pool[i] end
	end
	return out
end
local function vig_alpha(hud) return hud.vignette.alpha end
local function edge_color(hud)
	local t = hud.vig_edges[1].tex
	return t.r, t.g, t.b
end

---------------------------------------------------------------- pure curves

T.case("gem break curves: flash + swell first, then shrink / spin / fade; clear and pop flash too", function()
	local W = session()
	local curve = W.ns.BoardView.fx_curve
	local s, a, rot, fl = curve("fuse", 0)
	T.ok(s == 1 and a == 1 and rot == 0 and fl == 0, "fuse t=0: untouched, no flash before the effect really started")
	s, a, rot, fl = curve("fuse", 0.1)
	T.ok(s > 1 and a == 1 and fl > 0.5 and rot > 0, "fuse t=0.1: swelling, flashing, turning")
	s, a, rot, fl = curve("fuse", 0.3)
	T.ok(math.abs(s - 1.18) < 1e-9 and fl > 0 and fl < 0.2, "fuse t=0.3: the swell peak, flash nearly gone")
	s, a, rot, fl = curve("fuse", 0.6)
	T.ok(s < 1 and a < 1 and a > 0 and fl == 0, "fuse t=0.6: shrinking and fading")
	s, a, rot, fl = curve("fuse", 1)
	T.ok(math.abs(s - 0.1) < 1e-9 and a == 0 and rot > 3, "fuse t=1: tiny, invisible, spun")
	s, a, rot, fl = curve("clear", 0.1)
	T.ok(s > 1 and fl > 0 and rot > 0, "clear: swell + flash + spin")
	s, a = curve("clear", 1)
	T.ok(s < 0.3 and a == 0, "clear ends small and invisible")
	s, a, rot, fl = curve("pop", 0.5)
	T.ok(s > 1.2 and a == 1 and fl > 0, "pop: bigger + flash")
	s, a, rot, fl = curve("land", 0.5)
	T.ok(s < 1 and rot == 0 and fl == 0, "land unchanged")
	s, a, rot, fl = curve(nil, 0.5)
	T.ok(s == 1 and a == 1 and rot == 0 and fl == 0, "no effect: identity")
end)

---------------------------------------------------------------- board view: break on real gems

T.case("real match: gems flash, spin and shrink while they converge; frames are clean afterwards", function()
	local W = session()
	local App = open_ready(W)
	local view, sim = App.view, App.sim
	local Match = W.ns.Match
	local c1, r1, c2, r2 = Match.find_possible_move(sim.board)
	local seen_flash, seen_rot, seen_small = false, false, false
	T.eq(sim:try_swap_cells(c1, r1, c2, r2), "ok", "swap")
	for _ = 1, 200 do
		W.update(DT)
		for i = 1, #view.active do
			local f = view.active[i]
			if f.fshown and f.flash.alpha > 0 then seen_flash = true end
			if f.lrot ~= 0 and f.icon.rotation ~= nil and f.icon.rotation > 0 then seen_rot = true end
			if f.ls ~= nil and f.ls < 0.4 and f.gem.fx == "fuse" then seen_small = true end
		end
	end
	T.ok(seen_flash, "a flash showed on a breaking gem")
	T.ok(seen_rot, "a breaking gem was rotated (jewels set: full texcoords)")
	T.ok(seen_small, "a breaking gem shrank")
	T.ok(frames_until(W, function() return sim:is_at_rest() end, 600), "rest")
	frames(W, 5)
	for i = 1, #view.active do
		local f = view.active[i]
		T.ok(not f.fshown and f.lrot == 0, "settled gem frame has no flash / spin")
	end
	for i = 1, #view.free do
		local f = view.free[i]
		T.ok(not f.fshown and f.lrot == 0 and not f.flash.shown, "pooled frame is clean")
	end
	T.eq(#W.errors, 0, "no errors")
end)

T.case("cropped gem set (WoW icons): no rotation; no SetRotation at all: the spin is skipped", function()
	local W = session()
	local App = open_ready(W)
	App.set_gem_set("wow")
	local view, sim = App.view, App.sim
	local calls = 0
	local Region = getmetatable(view.active[1].icon) -- the stub's region method table
	local old = Region.SetRotation
	Region.SetRotation = function(...) calls = calls + 1; return old(...) end
	local c1, r1, c2, r2 = W.ns.Match.find_possible_move(sim.board)
	sim:try_swap_cells(c1, r1, c2, r2)
	frames(W, 40)
	T.eq(calls, 0, "wow set: SetRotation never called")
	Region.SetRotation = old
	-- jewels set, but the client has no SetRotation: pcall guard flips can_rotate, no error
	App.set_gem_set("jewels")
	T.ok(frames_until(W, function() return sim:is_at_rest() end, 600), "rest")
	Region.SetRotation = function() error("no SetRotation") end
	c1, r1, c2, r2 = W.ns.Match.find_possible_move(sim.board)
	sim:try_swap_cells(c1, r1, c2, r2)
	frames(W, 40)
	T.ok(W.ns.BoardView.can_rotate == false, "can_rotate cleared after the failure")
	W.ns.BoardView.can_rotate = true
	Region.SetRotation = old
	T.eq(#W.errors, 0, "no errors")
end)

---------------------------------------------------------------- particles / rings

T.case("match break: shards wait for the gems to arrive (FUSE), sparkles from 5, pool never exceeded, no new textures", function()
	local W = session()
	local App = open_ready(W)
	local hud, sim = App.hud, App.sim
	local jc = hud.juice
	App.combat.enemy:stop_rotation() -- W1-G3: the Hellhound bites every 3.7 s; its hit effects would keep the pools busy
	local FUSE = W.ns.Timings.FUSE
	T.eq(#jc.parts, jc.PARTS, "pool built once")
	local regions, nframes = W.regions, #W.frames
	local base = jc:busy()
	sim:emit("match_resolved", 3, gems_at({ { 2, 3 }, { 3, 3 }, { 4, 3 } }), 1, 3, 3, 0)
	T.eq(jc:busy() - base, 6, "a 3-match: 6 shards queued")
	T.eq(shown_count(jc.parts), 0, "none visible before the gems arrive")
	frames(W, 6) -- 0.1 s: still converging
	T.eq(shown_count(jc.parts), 0, "still hidden mid-fuse")
	frames(W, 12) -- past FUSE
	T.ok(shown_count(jc.parts) > 0, "shards fly once the gems arrived (FUSE " .. FUSE .. " s)")
	local p = nil
	for i = 1, #jc.parts do
		if jc.parts[i].shown then p = jc.parts[i] end
	end
	local c = W.ns.Assets.COLOR.GEM_FX[3]
	local tr, tg, tb = p.tex.vr or p.tex.r, p.tex.vg or p.tex.g, p.tex.vb or p.tex.b -- W0-P7: soft glow = vertex colour, square = colour texture
	T.ok(tr == c[1] and tg == c[2] and tb == c[3], "shard in the gem colour (ruby)")
	frames(W, 40 + fly_frames(W))
	T.eq(jc:busy(), 0, "everything over after the effect time")
	T.eq(shown_count(jc.parts), 0, "all hidden")
	-- 5-match: sparkles + ring on top
	sim:emit("match_resolved", 5, gems_at({ { 2, 3 }, { 3, 3 }, { 4, 3 }, { 5, 3 }, { 6, 3 } }), 1, 4, 3, 2)
	T.ok(jc:busy() >= 14 + jc.SPARKLES, "5-match: shards + sparkles (+ ring)")
	frames(W, 60 + fly_frames(W))
	T.eq(jc:busy(), 0, "5-match effect over")
	-- pool bound under a storm
	for _ = 1, 40 do sim:emit("match_resolved", 7, gems_at({ { 1, 1 }, { 2, 1 }, { 3, 1 } }), 3, 2, 1, 2) end
	T.ok(jc:busy() <= jc.PARTS + jc.RINGS + jc.SHOTS, "busy slots bounded by the pools (" .. jc:busy() .. ")")
	T.eq(W.regions, regions, "no texture / mask / font string created while playing")
	T.eq(#W.frames, nframes, "no frame created while playing")
	frames(W, 90)
	T.eq(jc:busy(), 0, "storm drains")
	-- events without payload (older callers): centroid, unknown colour, no error
	sim:emit("match_resolved", 3, gems_at({ { 2, 2 } }), 1)
	sim:emit("match_resolved", 3, {}, 1)
	frames(W, 60)
	T.eq(jc:busy(), 0, "payload-less events end too")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("ability gem spawn: a skill ring + sparks, an ult bigger and golden with a second ring + sparkles", function()
	local W = session()
	local App = open_ready(W)
	local hud, sim, A = App.hud, App.sim, W.ns.Assets
	local jc = hud.juice
	local function rings_shown() return shown_count(jc.rings) end
	sim:emit("ability_gem_spawned", 3, 3, 1, 3)
	frames(W, 2)
	T.eq(rings_shown(), 1, "skill: one ring")
	local skill = nil
	for i = 1, #jc.rings do
		if jc.rings[i].shown then skill = { s1 = jc.rings[i].s1, vb = jc.rings[i].tex.vb } end
	end
	frames(W, 40)
	T.eq(jc:busy(), 0, "skill effect over")
	sim:emit("ability_gem_spawned", 3, 3, 2, 3)
	frames(W, 8)
	T.eq(rings_shown(), 2, "ult: two rings")
	local ult
	for i = 1, #jc.rings do
		if jc.rings[i].shown and (ult == nil or jc.rings[i].s1 > ult.s1) then ult = jc.rings[i] end
	end
	T.ok(ult.s1 > skill.s1, "the ult ring grows bigger")
	T.eq(ult.tex.vr, A.COLOR.RING_ULT[1], "ult ring is golden")
	T.eq(skill.vb, A.COLOR.RING_SKILL[3], "skill ring is cyan-ish")
	frames(W, 60)
	T.eq(jc:busy(), 0, "ult effect over")
	-- the gem itself flashes (pop) and the next streak starts at the spawn cell
	T.ok(W.ns.BoardView.fx_curve("pop", 0.2) > 1, "spawned gem pops")
	T.eq(#W.errors, 0, "no errors")
end)

---------------------------------------------------------------- streaks

T.case("player hit: a streak flies match -> enemy, the damage number / hit reaction wait for the arrival", function()
	local W = session()
	local App = open_ready(W)
	local hud, sim, A = App.hud, App.sim, W.ns.Assets
	local jc = hud.juice
	slash(W, "fight hellhound")
	frames(W, 2)
	W.wall = W.wall + 5
	sim:emit("match_resolved", 3, gems_at({ { 1, 1 }, { 2, 1 }, { 3, 1 } }), 1, 2, 1, 0)
	sim:emit("enemy_damaged", 123, false)
	T.eq(shown_count(hud.pops_enemy), 0, "no damage number at launch")
	T.eq(hud.hit_t0, nil, "no hit reaction at launch")
	frames(W, 4)
	local s
	for i = 1, #jc.shots do
		if jc.shots[i].t0 ~= nil then s = jc.shots[i] end
	end
	T.ok(s ~= nil and s.head.shown, "the head is flying")
	T.eq(s.x0, 2.5 * 64, "starts at the match centre x")
	T.eq(s.y0, 1.5 * 64, "starts at the match centre y")
	T.eq(s.x1, jc.ex, "ends at the enemy")
	T.ok(s.head.point ~= nil and s.head.x > s.x0 and s.head.x < s.x1, "the head is on its way")
	local gc = A.COLOR.GEM_FX[3]
	T.ok(s.r == gc[1] and s.g == gc[2], "streak in the gem colour")
	T.eq(shown_count(hud.pops_enemy), 0, "still no number in flight")
	frames(W, math.ceil(W.ns.Juice.FLY / DT) + 2) -- just past the arrival
	local pops = live_pops(hud.pops_enemy)
	T.ok(#pops == 1 and pops[1].text == "-123", "the number appears on arrival: " .. tostring(pops[1] and pops[1].text))
	T.ok(hud.hit_t0 ~= nil, "hit reaction started on arrival")
	frames(W, 40 + fly_frames(W))
	T.eq(jc:busy(), 0, "streak and impact over")
	T.eq(hud.knock_x, 0, "knock-back back at rest")
	T.eq(hud.enemy_holder.x, 0, "enemy frame back in place")
end)

T.case("knock-back: the enemy frame moves right and returns; pool bound: no hit reaction is ever lost", function()
	local W = session()
	local App = open_ready(W)
	local hud, sim = App.hud, App.sim
	local jc = hud.juice
	slash(W, "fight hellhound")
	frames(W, 30) -- past the 0.35 s entrance slide (W0-P8), which moves the frame too
	sim:emit("enemy_damaged", 5, false)
	local max_kx = 0
	for _ = 1, 40 do
		W.update(DT)
		if hud.enemy_holder.x ~= nil and hud.enemy_holder.x > max_kx then max_kx = hud.enemy_holder.x end
	end
	T.ok(max_kx >= 6 and max_kx <= 8, "knocked right by about 8 px (" .. max_kx .. ")")
	T.eq(hud.enemy_holder.x, 0, "returned")
	-- 20 hits at once (pool 6): all reactions still happen, each exactly once
	local nframes, regions = #W.frames, W.regions
	local hits = 0
	local orig = hud._enemy_hit
	hud._enemy_hit = function(self, a, b) hits = hits + 1; return orig(self, a, b) end
	for i = 1, 20 do sim:emit("enemy_damaged", i, false) end
	T.ok(jc:busy() <= jc.PARTS + jc.RINGS + jc.SHOTS, "bounded")
	frames(W, 60)
	T.eq(hits, 20, "every one of 20 hits was delivered once")
	T.eq(#W.frames, nframes, "no frame created")
	T.eq(W.regions, regions, "no texture created")
	T.eq(jc:busy(), 0, "drained")
	hud._enemy_hit = orig
	T.eq(#W.errors, 0, "no errors")
end)

T.case("ability hits: an ult streak is thicker and slower, comes from the gem cell in its colour; flash + shake by tier", function()
	local W = session()
	local App = open_ready(W)
	local hud, sim, A = App.hud, App.sim, W.ns.Assets
	local jc = hud.juice
	slash(W, "fight hellhound")
	frames(W, 2)
	sim:emit("match_resolved", 3, gems_at({ { 1, 1 }, { 2, 1 }, { 3, 1 } }), 1, 2, 1, 0)
	sim:emit("enemy_damaged", 10, false)
	local plain
	for i = 1, #jc.shots do
		if jc.shots[i].t0 ~= nil then plain = { size = jc.shots[i].size, fly = jc.shots[i].fly } end
	end
	frames(W, 40 + fly_frames(W))
	sim:emit("ability_triggered", { id = "frost_nova", toast = "F", blurb = "", icon = "x", tier = 2, col = 5, row = 6, gem_type = 4 })
	hud:update()
	T.ok(jc.trauma > 0.5, "ult shakes (" .. jc.trauma .. ")")
	T.ok(vig_alpha(hud) > 0, "ult flash")
	local r, g, b = edge_color(hud)
	T.ok(r == A.COLOR.VIG_ULT[1] and g == A.COLOR.VIG_ULT[2] and b == A.COLOR.VIG_ULT[3], "gold flash")
	sim:emit("enemy_damaged", 500, false)
	local ult
	for i = 1, #jc.shots do
		if jc.shots[i].t0 ~= nil then ult = jc.shots[i] end
	end
	T.ok(ult.size > plain.size * 1.9 and ult.fly > plain.fly * 1.3, "thicker and slower")
	T.eq(ult.x0, 5.5 * 64, "from the ability gem's cell")
	T.eq(ult.y0, 6.5 * 64, "from the ability gem's cell (y)")
	local c4 = A.COLOR.GEM_FX[4]
	T.ok(ult.r == c4[1] and ult.b == c4[3], "sapphire colour")
	frames(W, 60)
	-- a skill: cyan, lighter shake
	sim:emit("ability_triggered", { id = "flamestrike", toast = "F", blurb = "", icon = "x", tier = 1, col = 1, row = 1, gem_type = 3 })
	r, g, b = edge_color(hud)
	T.ok(r == A.COLOR.VIG_SKILL[1] and b == A.COLOR.VIG_SKILL[3], "cyan flash for a skill")
	T.ok(jc.trauma > 0 and jc.trauma < 0.5, "skill: lighter shake")
	frames(W, 80)
	T.eq(#W.errors, 0, "no errors")
end)

T.case("enemy cast streak: enemy -> player bar, chunkier for a boss, purple for a curse, junk -> the board edge", function()
	local W = session()
	local App = open_ready(W)
	local hud, sim, A = App.hud, App.sim, W.ns.Assets
	local jc = hud.juice
	slash(W, "fight hellhound")
	frames(W, 2)
	local function newest()
		local s
		for i = 1, #jc.shots do
			if jc.shots[i].t0 ~= nil and (s == nil or jc.shots[i].t0 >= s.t0) then s = jc.shots[i] end
		end
		return s
	end
	sim:emit("enemy_ability_executed", { name = "Bite", kind = "plain", is_special = false })
	local s = newest()
	T.eq(s.x0, jc.ex, "from the enemy")
	T.eq(s.x1, jc.px, "to the player bar x")
	T.eq(s.y1, jc.py, "to the player bar y")
	T.ok(s.y1 > 8 * 64, "the player bar is below the board")
	T.ok(s.r == A.COLOR.PROJ_ENEMY[1], "red")
	local plain_size = s.size
	frames(W, 40)
	sim:emit("enemy_ability_executed", { name = "Curse", kind = "curse", is_special = true, description = "x", icon = "x" })
	s = newest()
	T.ok(s.r == A.COLOR.PROJ_CURSE[1] and s.g == A.COLOR.PROJ_CURSE[2], "curse is purple")
	frames(W, 40)
	sim:emit("enemy_ability_executed", { name = "Web", kind = "junk", is_special = true, description = "x", icon = "x" })
	s = newest()
	T.eq(s.x1, jc.jx, "junk flies to the board's right edge")
	T.ok(s.x1 == 8 * 64, "board right edge")
	frames(W, 40)
	-- boss: chunkier
	App.combat.enemy.def.is_boss = true
	sim:emit("enemy_ability_executed", { name = "Bite", kind = "plain", is_special = false })
	T.ok(newest().size > plain_size, "boss streak is thicker")
	App.combat.enemy.def.is_boss = false
	frames(W, 60)
	T.eq(jc:busy(), 0, "over")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("heal / reflect / Mirror directions", function()
	local W = session()
	local App = open_ready(W)
	local hud, sim, A = App.hud, App.sim, W.ns.Assets
	local jc = hud.juice
	slash(W, "fight hellhound")
	frames(W, 2)
	local function newest()
		local s
		for i = 1, #jc.shots do
			if jc.shots[i].t0 ~= nil and (s == nil or jc.shots[i].t0 >= s.t0) then s = jc.shots[i] end
		end
		return s
	end
	-- hot / heal: board cell -> the player bar, green, lighter than a hit
	sim:emit("match_resolved", 3, gems_at({ { 1, 1 }, { 2, 1 }, { 3, 1 } }), 1, 2, 1, 0)
	sim:emit("player_healed", 50, "ult")
	local s = newest()
	T.eq(s.x1, jc.px, "heal flies to the player bar")
	T.eq(s.x0, 2.5 * 64, "from the last match")
	T.ok(s.g == A.COLOR.PROJ_HEAL[2] and s.size < jc.HEAD * (s.soft and jc.SOFT_HEAD or 1), "green, thinner")
	frames(W, 40)
	-- Fire Shield: orange flash, the returned hit flies from the player to the enemy
	sim:emit("attack_reflected", 200)
	hud:update()
	T.ok(vig_alpha(hud) > 0, "reflect flash")
	local r, g, b = edge_color(hud)
	T.ok(r == A.COLOR.VIG_REFLECT[1] and g == A.COLOR.VIG_REFLECT[2], "orange")
	sim:emit("enemy_damaged", 200, false)
	s = newest()
	T.eq(s.x0, jc.px, "reflect starts at the player bar")
	T.eq(s.x1, jc.ex, "and ends at the enemy")
	T.ok(s.r == A.COLOR.PROJ_REFLECT[1], "orange streak")
	frames(W, 40)
	-- a later plain hit is not hijacked by the old reflect (different sim instant)
	sim:emit("match_resolved", 3, gems_at({ { 1, 1 }, { 2, 1 }, { 3, 1 } }), 1, 2, 1, 0)
	sim:emit("enemy_damaged", 10, false)
	T.eq(newest().x0, 2.5 * 64, "plain hit again from the match")
	frames(W, 40)
	-- Mirror bounce: enemy -> player, silver
	sim:emit("player_damaged", 300, "mirror")
	s = newest()
	T.eq(s.x0, jc.ex, "mirror bounce starts at the enemy")
	T.eq(s.x1, jc.px, "ends at the player")
	T.ok(s.r == A.COLOR.PROJ_MIRROR[1] and s.size > jc.HEAD, "silver, chunky")
	frames(W, 60)
	T.eq(jc:busy(), 0, "over")
	T.eq(#W.errors, 0, "no errors")
end)

---------------------------------------------------------------- vignette / mirror / cleared

T.case("vignette colours: red hit, silver Mirror shatter (+ shake + text), flashes end", function()
	local W = session()
	local App = open_ready(W)
	local hud, sim, A = App.hud, App.sim, W.ns.Assets
	local jc = hud.juice
	T.eq(vig_alpha(hud), 0, "no flash at rest")
	sim:emit("player_damaged", 400, "hit")
	hud:update()
	T.eq(vig_alpha(hud), 1, "hit: full red flash")
	local r, g, b = edge_color(hud)
	T.ok(r == A.COLOR.VIGNETTE[1] and g == A.COLOR.VIGNETTE[2], "red")
	frames(W, 30)
	T.eq(vig_alpha(hud), 0, "hit flash faded")
	-- bigger hits shake more (relative to max HP)
	jc.trauma = 0
	sim:emit("player_damaged", 10, "hit")
	local small = jc.trauma
	jc.trauma = 0
	sim:emit("player_damaged", App.combat.player_max_health, "hit")
	T.ok(small > 0 and jc.trauma > small and jc.trauma <= 1, "shake grows with the damage (" .. small .. " < " .. jc.trauma .. ")")
	frames(W, 40)
	-- Mirror shattered: silver flash, shake, SHATTERED text
	sim:emit("enemy_mirror_changed", false, true)
	hud:update()
	r, g, b = edge_color(hud)
	T.ok(r == A.COLOR.VIG_MIRROR[1] and b == A.COLOR.VIG_MIRROR[3], "silver flash")
	T.ok(jc.trauma >= 0.3 and vig_alpha(hud) > 0, "shake + flash")
	T.eq(hud.mirror_msg.alpha, 1, "SHATTERED! text")
	frames(W, 60)
	T.eq(vig_alpha(hud), 0, "flash ended")
	-- an expired mirror stays quiet
	jc.trauma = 0
	sim:emit("enemy_mirror_changed", false, false)
	T.eq(jc.trauma, 0, "expiry: no shake")
	-- CLEARED shakes lightly
	sim:emit("enemy_defeated", {})
	T.eq(jc.trauma, 0, "no CLEARED shake at the kill (W0-P11: it follows the death beat)")
	local shook = false
	for _ = 1, 80 do
		W.update(DT)
		if jc.trauma > 0 then shook = true break end
	end
	T.ok(shook, "CLEARED shake at kill + 1.0 s")
	frames(W, 40)
	T.eq(#W.errors, 0, "no errors")
end)

---------------------------------------------------------------- shake

T.case("shake: offsets the window by trauma, restores the exact rest position, 4+ match / ult trigger it", function()
	local W = session()
	local App = open_ready(W)
	local hud, sim = App.hud, App.sim
	local jc = hud.juice
	local f = App.win.frame
	f:SetPoint("TOPLEFT", W.UIParent, "TOPLEFT", 120, -80) -- a dragged-to position, not the default
	local p0, r0, rp0, x0, y0 = f:GetPoint()
	T.eq(jc.trauma, 0, "no trauma at rest")
	sim:emit("match_resolved", 3, gems_at({ { 1, 1 }, { 2, 1 }, { 3, 1 } }), 1, 2, 1, 0)
	T.eq(jc.trauma, 0, "a 3-match does not shake")
	sim:emit("match_resolved", 4, gems_at({ { 1, 1 }, { 2, 1 }, { 3, 1 }, { 4, 1 } }), 1, 2, 1, 1)
	T.ok(jc.trauma > 0.1 and jc.trauma < 0.3, "4-match: light shake (" .. jc.trauma .. ")")
	jc.trauma = 0
	sim:emit("match_resolved", 7, gems_at({ { 1, 1 } }), 1, 1, 1, 2)
	T.ok(jc.trauma >= 0.6, "7-match: heavy shake (" .. jc.trauma .. ")")
	local moved, maxd = false, 0
	for _ = 1, 90 do
		W.update(DT)
		local _, _, _, x, y = f:GetPoint()
		if x ~= x0 or y ~= y0 then moved = true end
		local d = math.max(math.abs(x - x0), math.abs(y - y0))
		if d > maxd then maxd = d end
	end
	T.ok(moved, "the window moved while shaking")
	T.ok(maxd <= jc.SHAKE_MAX, "never further than SHAKE_MAX (" .. maxd .. ")")
	local p1, r1, rp1, x1, y1 = f:GetPoint()
	T.ok(p1 == p0 and r1 == r0 and rp1 == rp0 and x1 == x0 and y1 == y0, "exactly the rest position afterwards")
	T.ok(not jc.shaking and jc.trauma == 0, "shake over")
	-- trauma stacks and clamps
	jc:add_trauma(0.8)
	jc:add_trauma(0.8)
	T.eq(jc.trauma, 1, "clamped to 1")
	-- hide mid-shake: back at rest at once, nothing left running
	frames(W, 3)
	App.win.frame:Hide()
	p1, r1, rp1, x1, y1 = f:GetPoint()
	T.ok(x1 == x0 and y1 == y0 and not jc.shaking and jc.trauma == 0, "hide restores the window")
	slash(W, "")
	-- pause mid-shake
	jc:add_trauma(0.9)
	frames(W, 3)
	App.soft_pause("test")
	_, _, _, x1, y1 = f:GetPoint()
	T.ok(x1 == x0 and y1 == y0 and jc.trauma == 0, "soft pause restores the window")
	frames(W, 10)
	_, _, _, x1, y1 = f:GetPoint()
	T.ok(x1 == x0 and y1 == y0, "and it stays still while paused")
	App.soft_resume()
	-- the menu pauses too
	jc:add_trauma(0.9)
	frames(W, 3)
	App.open_menu()
	_, _, _, x1, y1 = f:GetPoint()
	T.ok(x1 == x0 and y1 == y0, "menu restores the window")
	App.close_menu()
	T.eq(#W.errors, 0, "no errors")
end)

T.case("shake: never while the window is dragged; a drag start ends it; the saved position is the rest one", function()
	local W = session()
	local App = open_ready(W)
	local hud = App.hud
	local jc = hud.juice
	local f = App.win.frame
	f:SetPoint("TOPLEFT", W.UIParent, "TOPLEFT", 50, -60)
	jc:add_trauma(1)
	frames(W, 3)
	local _, _, _, x, y = f:GetPoint()
	T.ok(jc.shaking, "shaking")
	local title = App.win.title
	title.scripts.OnDragStart(title)
	_, _, _, x, y = f:GetPoint()
	T.ok(x == 50 and y == -60 and jc.trauma == 0 and not jc.shaking, "drag start: window back at rest, trauma gone")
	T.ok(f.moving, "StartMoving still called")
	jc:add_trauma(1)
	T.eq(jc.trauma, 0, "no trauma while dragging")
	frames(W, 5)
	_, _, _, x, y = f:GetPoint()
	T.ok(x == 50 and y == -60, "does not shake while dragged")
	title.scripts.OnDragStop(title)
	local db = W.store.DragonChessDB
	T.ok(db.window.x == 50 and db.window.y == -60, "saved position = rest position (" .. tostring(db.window.x) .. "," .. tostring(db.window.y) .. ")")
	jc:add_trauma(0.5)
	T.ok(jc.trauma == 0.5, "shake works again after the drag")
	frames(W, 60)
	T.eq(#W.errors, 0, "no errors")
end)

T.case("option 'Screen shake': default on, saved, off = no trauma and no window offset", function()
	local W = session()
	local App = open_ready(W)
	local db = W.store.DragonChessDB
	local hud = App.hud
	local jc = hud.juice
	T.eq(db.options.shake, true, "default on")
	T.ok(jc.shake_enabled, "juice follows")
	-- menu button
	App.open_menu()
	local btn = App.menu.checks.shake
	T.ok(btn ~= nil and btn.dc_checked == true, "menu shows the option checked")
	btn.scripts.OnClick(btn)
	T.eq(db.options.shake, false, "click turns it off")
	T.eq(btn.dc_checked, false, "check follows")
	T.ok(not jc.shake_enabled, "juice follows (off)")
	App.close_menu()
	local f = App.win.frame
	local _, _, _, x0, y0 = f:GetPoint()
	App.sim:emit("player_damaged", 5000, "hit")
	App.sim:emit("match_resolved", 7, gems_at({ { 1, 1 } }), 1, 1, 1, 2)
	T.eq(jc.trauma, 0, "no trauma while off")
	frames(W, 20)
	local _, _, _, x1, y1 = f:GetPoint()
	T.ok(x0 == x1 and y0 == y1, "no window offset while off")
	T.ok(vig_alpha(hud) >= 0, "the red flash is independent of the option")
	-- switching off mid-shake ends it at once
	App.set_option("shake", true)
	jc:add_trauma(1)
	frames(W, 3)
	App.set_option("shake", false)
	_, _, _, x1, y1 = f:GetPoint()
	T.ok(x0 == x1 and y0 == y1 and not jc.shaking, "off mid-shake: window back at once")
	-- a stored non-boolean falls back to on; a stored false stays off
	local W2 = session(nil, { DragonChessDB = { options = { shake = "yes" } } })
	T.eq(W2.store.DragonChessDB.options.shake, true, "garbage -> on")
	local W3 = session(nil, { DragonChessDB = { options = { shake = false } } })
	T.eq(W3.store.DragonChessDB.options.shake, false, "stored off stays off")
	slash(W3, "")
	T.ok(not W3.App.hud.juice.shake_enabled, "applied when the window is created")
	T.eq(#W.errors, 0, "no errors")
end)

---------------------------------------------------------------- pause / halt

T.case("pause, hide, menu: every streak / shard / ring is hidden, nothing resurrects, time is sim time", function()
	local W = session()
	local App = open_ready(W)
	local hud, sim = App.hud, App.sim
	local jc = hud.juice
	local function all_hidden()
		for _, pool in ipairs({ jc.parts, jc.rings }) do
			for i = 1, #pool do
				if pool[i].shown or pool[i].tex.shown then return false end
			end
		end
		for i = 1, #jc.shots do
			local s = jc.shots[i]
			if s.head.shown then return false end
			for k = 1, #s.trail do
				if s.trail[k].shown then return false end
			end
		end
		return true
	end
	local function start_all()
		sim:emit("match_resolved", 5, gems_at({ { 2, 3 }, { 3, 3 }, { 4, 3 }, { 5, 3 }, { 6, 3 } }), 1, 4, 3, 2)
		sim:emit("ability_gem_spawned", 3, 3, 2, 3)
		sim:emit("enemy_damaged", 99, false)
		sim:emit("enemy_ability_executed", { name = "Bite", kind = "plain", is_special = false })
		frames(W, 12)
	end
	start_all()
	T.ok(jc:busy() > 0 and not all_hidden(), "effects are showing")
	local hits = shown_count(hud.pops_enemy)
	App.soft_pause("test")
	T.ok(all_hidden() and jc:busy() == 0, "soft pause hides everything")
	frames(W, 120)
	T.ok(all_hidden() and jc:busy() == 0, "stays hidden while paused")
	T.eq(shown_count(hud.pops_enemy), hits, "the dropped hit reaction does not appear later")
	App.soft_resume()
	frames(W, 20)
	T.ok(all_hidden(), "nothing resurrected after the resume")
	-- window hide
	start_all()
	App.win.frame:Hide()
	T.ok(all_hidden() and jc:busy() == 0, "hide hides everything")
	slash(W, "")
	-- menu
	start_all()
	App.open_menu()
	T.ok(all_hidden() and jc:busy() == 0, "menu hides everything")
	App.close_menu()
	-- game over (halt through run_lost)
	start_all()
	hud:halt()
	T.ok(all_hidden(), "halt hides everything")
	-- a new run resets
	start_all()
	App.reset()
	T.ok(all_hidden() and jc:busy() == 0, "a new run starts clean")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("time runs on the sim clock: a frozen sim ends nothing early", function()
	local W = session()
	local App = open_ready(W)
	local hud, sim = App.hud, App.sim
	local jc = hud.juice
	sim:emit("enemy_damaged", 5, false)
	frames(W, 3)
	local busy = jc:busy()
	T.ok(busy > 0, "streak in flight")
	W.wall = W.wall + 100 -- wall time passing changes nothing
	hud:update()
	hud:update()
	T.eq(jc:busy(), busy, "same sim time: unchanged")
	-- update with the same sim time, many times: nothing advances
	for _ = 1, 50 do hud:update() end
	T.eq(jc:busy(), busy, "50 updates at one sim instant: unchanged")
	T.eq(#W.errors, 0, "no errors")
end)

---------------------------------------------------------------- fallbacks

T.case("no juice layer (build failed): hit reactions run at once, nothing crashes", function()
	local W = session()
	-- simulate the failed build: swap the stand-in in
	local App = open_ready(W)
	local hud, sim = App.hud, App.sim
	local NONE = W.ns.Juice.NONE
	hud.juice = NONE
	NONE.on_hit = nil
	slash(W, "fight hellhound")
	frames(W, 2)
	sim:emit("enemy_damaged", 77, false)
	T.eq(#live_pops(hud.pops_enemy), 1, "immediate number without a juice layer")
	sim:emit("match_resolved", 5, gems_at({ { 1, 1 } }), 1, 1, 1, 2)
	sim:emit("ability_gem_spawned", 3, 3, 2, 3)
	sim:emit("ability_triggered", { id = "frost_nova", toast = "F", blurb = "", icon = "x", tier = 2, col = 1, row = 1 })
	sim:emit("enemy_ability_executed", { name = "Bite", kind = "plain", is_special = false })
	sim:emit("player_damaged", 100, "hit")
	sim:emit("player_healed", 5, "ult")
	sim:emit("attack_reflected", 5)
	sim:emit("enemy_mirror_changed", false, true)
	frames(W, 30)
	hud:halt()
	T.eq(#W.errors, 0, "no errors")
end)

T.case("a model-less build still works (no PlayerModel): streaks and shake do not need models", function()
	local W = session(function(w) w.fail_frame_types.PlayerModel = true end)
	local App = open_ready(W)
	local hud, sim = App.hud, App.sim
	sim:emit("enemy_damaged", 40, false)
	frames(W, 20 + fly_frames(W))
	T.eq(#live_pops(hud.pops_enemy), 1, "number after the streak")
	hud.juice:add_trauma(0.5)
	frames(W, 5)
	T.eq(#W.errors, 0, "no errors")
end)

---------------------------------------------------------------- debug panel

T.case("debug panel Effects tab: break / streak / cast / shake buttons obey pause", function()
	local W = session()
	local App = open_ready(W)
	local hud = App.hud
	local jc = hud.juice
	slash(W, "debug")
	local p = App.debug_panel
	T.ok(p ~= nil, "panel open")
	p:select(4)
	local page = p.pages[4]
	click(page, "Break 5")
	T.ok(jc:busy() > 0, "break plays")
	frames(W, 80)
	T.eq(jc:busy(), 0, "and ends")
	click(page, "Streak")
	T.ok(jc:busy() > 0, "streak plays")
	frames(W, 60)
	click(page, "Ult streak")
	frames(W, 60)
	click(page, "Enemy cast")
	T.ok(jc:busy() > 0, "enemy cast streak plays")
	frames(W, 60)
	click(page, "Skill spawn")
	click(page, "Ult spawn")
	click(page, "Break 3")
	frames(W, 90)
	T.eq(jc:busy(), 0, "all end")
	click(page, "Shake")
	T.ok(jc.trauma > 0, "shake plays")
	frames(W, 60)
	click(page, "Big shake")
	T.ok(jc.trauma > 0.8, "big shake")
	frames(W, 80)
	-- paused: refused with a reason
	App.soft_pause("test")
	local n = #W.printed
	click(page, "Streak")
	T.eq(jc:busy(), 0, "paused: nothing plays")
	T.ok(chat_since(W, n):find("unpause", 1, true) ~= nil, "says why")
	App.soft_resume()
	-- shake off in the menu: the button says so
	App.set_option("shake", false)
	n = #W.printed
	click(page, "Shake")
	T.eq(jc.trauma, 0, "shake off: no trauma")
	T.ok(chat_since(W, n):find("shake is off", 1, true) ~= nil, "says why")
	T.eq(#W.errors, 0, "no errors")
end)

---------------------------------------------------------------- budget

T.case("budget: juice live (streak, shards, rings, shake, flash) allocates nothing per frame", function()
	local W = session()
	local App = open_ready(W)
	local hud = App.hud
	local jc = hud.juice
	slash(W, "fight hellhound")
	frames(W, 60)
	-- Warm every pooled slot once (the stub tables grow their fields on a texture's first use; the client does not
	-- care): a storm that uses all particles, rings and streaks, then let it drain.
	jc.now = App.sim.now
	for _ = 1, 4 do
		jc:match_break(7, 100, 100, 3, 0)
		jc:spawn_fx(3, 3, 2)
		jc:projectile(10, 10, 400, 200, 2, 1, 1, 1, 0)
		jc:projectile(10, 10, 400, 200, 1, 1, 1, 1, 0)
	end
	jc:add_trauma(1)
	frames(W, 90)
	T.eq(jc:busy(), 0, "warm-up drained")
	local ui_kb = 0
	local n = 0
	local function frame()
		W.wall = W.wall + DT
		n = n + 1
		App.sim:tick(DT) -- the core allocates (timers): not part of the view budget
		local k = collectgarbage("count")
		if n % 8 == 1 then
			-- re-trigger every 8 frames so something is always flying
			hud:dev_juice("break5")
			hud:dev_juice("shot_ult")
			hud:dev_juice("spawn")
			jc:add_trauma(0.4)
		end
		hud:update()
		ui_kb = ui_kb + collectgarbage("count") - k
	end
	alloc_kb(frame, 300, function() ui_kb = 0 end)
	T.ok(jc:busy() > 0, "effects live during the measurement")
	T.ok(ui_kb < 1, ("HUD + juice with effects live allocate < 1 KB per 300 frames (got %.2f KB)"):format(ui_kb))
	T.eq(#W.errors, 0, "no errors")
end)

T.done()
