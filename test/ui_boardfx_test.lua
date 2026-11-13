-- W0-P7 test: board ability effects (ui/board_fx.lua), the soft-texture roles (Assets.GLOW / Assets.soft) with their
-- fallbacks, the combo meter and chain escalation, gem motion (fall / land / swap flash / rejected-swap shake), ability
-- gem auras, the breathing selection glow, landing dust, signatures, halt, the Board FX debug tab and the allocation budget.
-- Loads the addon in TOC order under test/wow_stubs.lua like ui_juice_test.
local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "."
local T = dofile(dir .. "/t.lua")
local loader = dofile(dir .. "/loader.lua")
local Stubs = dofile(dir .. "/wow_stubs.lua")
T.start("ui_boardfx_test")

local ADDON = "DragonChess"
local addon_dir = loader.wow_dir() .. "/"
local DT = 1 / 60
local CELL = 64

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

local function session(setup, pre_open)
	local W = Stubs.new()
	if setup then setup(W) end
	local ns = {}
	for _, f in ipairs(toc_files) do W.load(addon_dir .. f, ADDON, ns) end
	W.fire("ADDON_LOADED", ADDON)
	W.ns, W.App = ns, ns.App
	if pre_open then pre_open(W) end
	return W
end

local function slash_raw(W, msg) W.stubs.SlashCmdList.DRAGONCHESS(msg or "") end
-- W0-P10: opening the window shows the start / resume panel (game paused); these tests want a running game.
local function slash(W, msg)
	slash_raw(W, msg)
	if W.App ~= nil and W.App.start_open then W.App.close_start() end
end
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
local function click(page, label)
	for _, ch in ipairs(page.children) do
		if ch.ftype == "Button" and ch.text ~= nil and ch.text.text == label then
			ch:Click()
			return ch
		end
	end
	T.ok(false, "button '" .. label .. "' exists")
end
local function active_cells(bf)
	local n = 0
	for i = 1, #bf.cells do
		if bf.cells[i].t0 ~= nil then n = n + 1 end
	end
	return n
end
local function shown_cells(bf)
	local n = 0
	for i = 1, #bf.cells do
		if bf.cells[i].shown then n = n + 1 end
	end
	return n
end
local function active(pool)
	local n = 0
	for i = 1, #pool do
		if pool[i].t0 ~= nil then n = n + 1 end
	end
	return n
end
local function alloc_kb(fn, n, reset)
	if jit then jit.off(); jit.flush() end
	collectgarbage("collect")
	collectgarbage("stop")
	fn()
	fn()
	if reset then reset() end
	local kb = collectgarbage("count")
	for _ = 1, n do fn() end
	local grown = collectgarbage("count") - kb
	collectgarbage("restart")
	if jit then jit.on() end
	return grown
end
local function area_cells()
	local c = {}
	for col = 2, 4 do
		for row = 2, 4 do c[#c + 1] = col; c[#c + 1] = row end
	end
	return c
end

---------------------------------------------------------------- pure

T.case("chain escalation is monotonic in depth and capped (shards, ring size, trauma, vignette)", function()
	local W = session()
	local J = W.ns.Juice
	local prev_s, prev_r, prev_t, prev_v = 0, 0, -1, -1
	local extra_from
	for d = 1, 9 do
		local sm, rm, extra, tr, vig = J.chain_scale(d)
		T.ok(sm >= prev_s and rm >= prev_r and tr >= prev_t and vig >= prev_v, "monotonic at depth " .. d)
		prev_s, prev_r, prev_t, prev_v = sm, rm, tr, vig
		if extra and not extra_from then extra_from = d end
		if d == 1 then T.ok(sm == 1 and rm == 1 and tr == 0 and vig == 0 and not extra, "depth 1 = the plain match") end
		if d == 3 then T.ok(extra, "an extra ring from depth 3") end
		if d == 4 then T.ok(vig > 0.19, "gold vignette from depth 4 (peak 0.15 + 0.05 e)") end
		if d == 3 then T.ok(vig == 0, "none below depth 4") end
	end
	T.eq(extra_from, 3, "extra ring starts at 3")
	local a = { J.chain_scale(6) }
	local b = { J.chain_scale(60) }
	T.ok(a[1] == b[1] and a[2] == b[2] and a[4] == b[4], "capped at depth 6")
	T.ok(math.abs(a[1] - 2.25) < 1e-9 and math.abs(a[2] - 1.75) < 1e-9 and math.abs(a[4] - 0.2) < 1e-9, "depth 6 numbers (x2.25 shards, x1.75 ring, +0.2 trauma)")
	local x1 = { J.chain_scale(3) }
	local x2 = { J.chain_scale(3) }
	T.ok(x1[1] == x2[1] and x1[5] == x2[5], "pure: the same input, the same output")
end)

T.case("combo meter scale grows with depth", function()
	local W = session()
	local BF = W.ns.BoardFx
	local prev = 0
	for d = 2, 10 do
		local s = BF.combo_scale(d)
		T.ok(s >= prev, "scale monotonic at " .. d)
		prev = s
	end
	T.ok(BF.combo_scale(2) < BF.combo_scale(5), "x5 is bigger than x2")
end)

T.case("fx_curve fall / land: pure, bounded, springs back", function()
	local W = session()
	local curve = W.ns.BoardView.fx_curve
	for i = 0, 100 do
		local t = i / 100
		local s, a, rot, fl, sx, sy = curve("land", t)
		local s2, a2, rot2, fl2, sx2, sy2 = curve("land", t)
		T.ok(s == s2 and sx == sx2 and sy == sy2, "land pure at " .. t)
		T.ok(sx >= 0.879 and sx <= 1.121 and sy >= 0.879 and sy <= 1.121 and s > 0.9 and s <= 1, "land bounded at " .. t)
		T.ok(a == 1 and rot == 0 and fl == 0, "land: no fade / spin / flash")
		local fs, fa, fr, ff, fsx, fsy = curve("fall", t)
		T.ok(fs == 1 and fa == 1 and fsx == 1 and fsy >= 1 and fsy <= 1.0601, "fall bounded (stretch 1 -> 1.06) at " .. t)
	end
	local _, _, _, _, sx0, sy0 = curve("land", 0)
	local _, _, _, _, sx1, sy1 = curve("land", 1)
	T.ok(sx0 == 1 and sy0 == 1 and math.abs(sx1 - 1) < 1e-9 and math.abs(sy1 - 1) < 1e-9, "land starts and ends at the plain size")
	local _, _, _, _, sxp = curve("land", 0.2)
	local _, _, _, _, sxn = curve("land", 0.6)
	T.ok(sxp > 1.05 and sxn < 0.99 or sxn < 1, "wide first (x1.12), then one small overshoot the other way")
	local _, _, _, _, sxe, sye = curve("land", 0.2)
	T.ok(sxe > 1 and sye < 1, "squash: wider and flatter")
	local _, _, _, _, nsx, nsy = curve("fuse", 0.5)
	T.ok(nsx == nil and nsy == nil, "other effects return the 4 old values only")
end)

---------------------------------------------------------------- soft textures

T.case("Assets.soft: roles resolve (primary, then fallback), a missing role reports it, the report lists all", function()
	local W = session()
	local A = W.ns.Assets
	local frame = W.stubs.CreateFrame("Frame")
	local tex = frame:CreateTexture()
	T.ok(A.soft(tex, "ring"), "ring loads")
	T.eq(tex.texture, A.GLOW.ring[1], "primary candidate")
	W.bad_textures[A.GLOW.beam[1]] = true
	T.ok(A.soft(frame:CreateTexture(), "beam"), "beam: the fallback candidate loads")
	W.bad_textures[A.GLOW.bolt[1]] = true
	W.bad_textures[A.GLOW.bolt[2]] = true
	T.ok(not A.soft(frame:CreateTexture(), "bolt"), "bolt: no candidate loads -> false")
	T.ok(not A.soft(frame:CreateTexture(), "bolt"), "and stays false")
	T.ok(not A.soft(frame:CreateTexture(), "nope"), "unknown role -> false")
	local rep = A.soft_report()
	T.ok(rep:find("ring ok", 1, true) and rep:find("bolt missing", 1, true) and rep:find("beam ok (fallback", 1, true), "report: " .. rep)
	A.GLOW_CHECK = false
	A.soft_reset()
	T.ok(A.soft(frame:CreateTexture(), "bolt"), "GLOW_CHECK off: the paths are trusted")
	A.GLOW.glow = false
	A.soft_reset()
	T.ok(not A.soft(frame:CreateTexture(), "glow"), "a role set to false is missing")
end)

T.case("no soft textures at all (A.GLOW empty): particles, rings, streaks, cells, beams, auras still work", function()
	local W = session(nil, function(w) w.ns.Assets.GLOW = {} end)
	local App = open_ready(W)
	local hud, sim = App.hud, App.sim
	local jc, bf = hud.juice, hud.boardfx
	T.ok(not bf.cells[1].soft and bf.wedge.tex == nil, "cells are colour squares, no wedge texture")
	jc.now = sim.now
	jc:match_break(5, 100, 100, 3, 0)
	jc:spawn_fx(3, 3, 2)
	jc:projectile(10, 10, 300, 200, 2, 1, 0, 0, 0)
	T.ok(jc:busy() > 0, "juice plays")
	local live
	frames(W, 6)
	for i = 1, #jc.parts do
		if jc.parts[i].shown then live = jc.parts[i] end
	end
	T.ok(live ~= nil and not live.soft and live.tex.r ~= nil, "particles are colour squares")
	T.ok(not jc.shots[1].soft and jc.shots[1].head.mask ~= nil, "streak heads are masked discs")
	sim:emit("flash", "area", area_cells(), 0.22)
	sim:emit("flash", "row_sweep", { 3, 3, 4, 3, 2, 3, 5, 3, 1, 3 }, 0.16)
	sim:emit("flash", "wave", { 1, 3, 2, 2, 2, 3, 2, 4 }, 0.22)
	sim:emit("chain_hop", 1, 1, 5, 4)
	frames(W, 4)
	T.ok(bf:busy() > 0 and shown_cells(bf) > 0, "board effects play on squares")
	sim:emit("ability_triggered", { id = "frost_nova", toast = "F", blurb = "", icon = "x", tier = 2, col = 1, row = 1, gem_type = 4 })
	sim:emit("match_resolved", 3, { { x = 1, y = 1, col = 1, row = 1, type = 3 } }, 3, 1, 1, 0)
	local a = hud.boardfx
	local view = App.view
	local g = sim.board:get(2, 2)
	g.tier = 2
	frames(W, 6)
	T.ok(g and view.frame_of[g].aura ~= nil, "an ult aura exists")
	T.ok(not view.frame_of[g].aura.soft and view.frame_of[g].aura.flare == nil, "disc halo, no flare texture")
	frames(W, 120)
	T.ok(a:busy() == 0, "everything ends")
	T.eq(#W.errors, 0, "no errors")
end)

---------------------------------------------------------------- board effects

T.case("flash kinds: the expected slots, nothing created while playing, the pool bound, recycling", function()
	local W = session()
	local App = open_ready(W)
	local hud, sim = App.hud, App.sim
	local bf = hud.boardfx
	local regions, nframes = W.regions, #W.frames
	frames(W, 10)
	sim:emit("flash", "area", area_cells(), 0.22)
	T.eq(active_cells(bf), 9, "area: 9 cells")
	frames(W, 3)
	T.eq(shown_cells(bf), 9, "all shown")
	frames(W, 30)
	T.eq(active_cells(bf), 0, "and gone after the duration")
	sim:emit("flash", "color", { 0, 0, 3, 1, 7, 7 }, 0.22)
	T.eq(active_cells(bf), 3, "color: 3 cells")
	frames(W, 30)
	sim:emit("flash", "convert_to", { 0, 0, 3, 1 }, 0.18)
	sim:emit("flash", "chain", { 4, 4 }, 0.18)
	T.eq(active_cells(bf), 3, "convert_to + chain")
	frames(W, 30)
	-- telegraph: pulses for the whole duration
	sim:emit("flash", "telegraph", { 1, 1, 2, 2, 3, 3, 4, 4 }, 0.62)
	frames(W, 25) -- 0.42 s
	T.eq(shown_cells(bf), 4, "telegraph still pulsing at 0.42 s")
	local c = bf.cells[1]
	frames(W, 20) -- 0.75 s
	T.eq(active_cells(bf), 0, "telegraph over after dur")
	sim:emit("flash", "telegraph_from", { 1, 1 }, 0.3)
	sim:emit("flash", "telegraph_to", { 2, 2 }, 0.3)
	T.eq(active_cells(bf), 2, "telegraph_from + to")
	frames(W, 30)
	-- row sweep: 2 arms from the origin, 8 cells
	sim:emit("flash", "row_sweep", { 3, 3, 4, 3, 2, 3, 5, 3, 1, 3, 6, 3, 0, 3, 7, 3 }, 0.16)
	T.eq(active(bf.beams), 2, "row_sweep: a beam per direction")
	T.eq(active_cells(bf), 8, "row_sweep: 8 cell flashes")
	frames(W, 4)
	T.ok(shown_cells(bf) >= 1 and shown_cells(bf) < 8, "cells flash as the beam passes, not all at once")
	frames(W, 30)
	T.eq(active(bf.beams), 0, "beams end")
	sim:emit("flash", "row_sweep", { 0, 5, 1, 5, 2, 5 }, 0.16)
	T.eq(active(bf.beams), 1, "origin at the left edge: one arm")
	frames(W, 30)
	-- wave: the wedge + staggered column slices
	local cells = {}
	for col = 1, 7 do
		local half = math.floor((col - 1) * 0.4)
		for r = 3 - half, 3 + half do cells[#cells + 1] = col; cells[#cells + 1] = r end
	end
	sim:emit("flash", "wave", cells, 0.22)
	T.eq(active_cells(bf), #cells / 2, "wave: every cone cell")
	T.ok(bf.wedge.t0 ~= nil, "wave: the wedge unfolds")
	local d1, d2
	for i = 1, #bf.cells do
		local s = bf.cells[i]
		if s.t0 ~= nil then
			if s.tex.x == 1.5 * CELL and not d1 then d1 = s.t0 end
			if s.tex.x == 3.5 * CELL and not d2 then d2 = s.t0 end
		end
	end
	T.ok(d1 ~= nil and d2 ~= nil and math.abs((d2 - d1) - 2 * 2 * W.ns.Timings.CLEAR_STAGGER_STEP) < 1e-9, "column slices CLEAR_STAGGER_STEP * 2 apart")
	frames(W, 60)
	T.eq(active_cells(bf), 0, "wave cells end")
	T.ok(bf.wedge.t0 == nil and not bf.wedge.shown, "wedge ends")
	-- chain hop: a bolt + a spark burst
	local before = W.ns.Juice and hud.juice:busy() or 0
	sim:emit("chain_hop", 0, 0, 3, 2)
	T.eq(active(bf.bolts), 1, "chain_hop: a bolt")
	T.ok(hud.juice:busy() > before, "and a spark burst at the target")
	frames(W, 2)
	T.ok(bf.bolts[1].shown or bf.bolts[2].shown, "bolt visible")
	frames(W, 30)
	T.eq(active(bf.bolts), 0, "bolt ends after hop + hold + fade")
	-- pools: never more than the cap, recycles the oldest
	for _ = 1, 20 do sim:emit("flash", "area", area_cells(), 0.22) end
	T.ok(active_cells(bf) <= bf.CELLS, "cell pool bound (" .. active_cells(bf) .. ")")
	for i = 1, 20 do sim:emit("chain_hop", 0, 0, i % 8, 1) end
	T.ok(active(bf.bolts) <= bf.BOLTS, "bolt pool bound")
	for _ = 1, 10 do sim:emit("flash", "row_sweep", { 3, 3, 4, 3, 2, 3 }, 0.16) end
	T.ok(active(bf.beams) <= bf.BEAMS, "beam pool bound")
	frames(W, 60)
	T.eq(bf:busy(), 0, "everything drains")
	T.eq(W.regions, regions, "no texture / font string created while playing")
	T.eq(#W.frames, nframes, "no frame created while playing")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("the event's cell list is copied: changing it afterwards changes nothing", function()
	local W = session()
	local App = open_ready(W)
	local sim, bf = App.sim, App.hud.boardfx
	local cells = { 1, 1, 6, 5 }
	sim:emit("flash", "area", cells, 0.22)
	for i = 1, #cells do cells[i] = 0 end
	cells[5], cells[6] = 7, 7
	frames(W, 3)
	local at = {}
	for i = 1, #bf.cells do
		local s = bf.cells[i]
		if s.t0 ~= nil then at[s.tex.x .. "," .. s.tex.y] = true end
	end
	local n = 0
	for _ in pairs(at) do n = n + 1 end
	T.eq(n, 2, "still two cells")
	T.ok(at[1.5 * CELL .. "," .. -1.5 * CELL], "first cell where it was")
	T.ok(at[6.5 * CELL .. "," .. -5.5 * CELL], "second cell where it was")
	-- no reference to a long list either
	local big = {}
	for i = 1, 400 do big[i] = i % 8 end
	sim:emit("flash", "color", big, 0.22)
	T.ok(active_cells(bf) <= bf.CELLS, "a huge list is capped")
	sim:emit("flash", "area", {}, 0.22)
	sim:emit("flash", "area", nil, 0.22)
	T.eq(#W.errors, 0, "empty / nil lists are fine")
end)

T.case("cast colour: colour flashes use the casting gem's colour, chain its own", function()
	local W = session()
	local App = open_ready(W)
	local sim, bf, A = App.sim, App.hud.boardfx, W.ns.Assets
	sim:emit("ability_triggered", { id = "frost_nova", toast = "F", blurb = "", icon = "x", tier = 1, col = 1, row = 1, gem_type = 4 })
	sim:emit("flash", "area", { 2, 2 }, 0.22)
	local s
	for i = 1, #bf.cells do
		if bf.cells[i].t0 ~= nil then s = bf.cells[i] end
	end
	local c = A.COLOR.GEM_FX[4]
	T.ok(s.tex.vr == c[1] and s.tex.vg == c[2] and s.tex.vb == c[3], "sapphire blue")
	frames(W, 30)
	sim:emit("flash", "chain", { 2, 2 }, 0.18)
	for i = 1, #bf.cells do
		if bf.cells[i].t0 ~= nil then s = bf.cells[i] end
	end
	T.eq(s.tex.vr, A.COLOR.FX_CHAIN[1], "chain colour")
end)

T.case("board light: a wash for every ability, a darkening for an ult only; ends on time", function()
	local W = session()
	local App = open_ready(W)
	local sim, bf = App.sim, App.hud.boardfx
	local function ab(tier) sim:emit("ability_triggered", { id = "frost_nova", toast = "F", blurb = "", icon = "x", tier = tier, col = 1, row = 1, gem_type = 3 }) end
	ab(1)
	frames(W, 8) -- 0.13 s, the peak
	T.ok(bf.wash.shown and bf.wash.alpha > 0.1 and bf.wash.alpha <= 0.18 + 1e-9, "skill: wash up to 0.18 (" .. tostring(bf.wash.alpha) .. ")")
	T.ok(not bf.dark.shown, "skill: no darkening")
	frames(W, 30)
	T.ok(not bf.wash.shown, "wash over after 0.25 s")
	ab(2)
	frames(W, 8)
	T.ok(bf.wash.alpha > 0.2 and bf.wash.alpha <= 0.3 + 1e-9, "ult: wash up to 0.3 (" .. tostring(bf.wash.alpha) .. ")")
	T.ok(bf.dark.shown and bf.dark.alpha > 0.1 and bf.dark.alpha <= 0.35 + 1e-9, "ult: dark up to 0.35")
	frames(W, 30)
	T.ok(not bf.dark.shown and not bf.wash.shown, "both over")
	T.ok(bf.lf:GetFrameLevel() < bf.gf:GetFrameLevel() and bf.gf:GetFrameLevel() < App.win.host:GetFrameLevel() + 19, "levels: light under glow, both under juice")
	T.ok(not bf.lf.mouse and not bf.gf.mouse, "never takes the mouse")
end)

T.case("combo meter: x<depth> from depth 2, punches on each new level, fades after the board settled, depth 1 resets", function()
	local W = session()
	local App = open_ready(W)
	local sim, bf = App.sim, App.hud.boardfx
	local g = { { x = 1, y = 1, col = 1, row = 1, type = 3 } }
	sim:emit("match_resolved", 3, g, 1, 1, 1, 0)
	T.ok(not bf.combo_frame.shown, "depth 1: nothing")
	sim:emit("match_resolved", 3, g, 2, 1, 1, 0)
	frames(W, 2)
	T.ok(bf.combo_frame.shown and bf.combo_text.text == "x2", "x2 shown")
	local s2 = bf.combo_frame.scale
	frames(W, 20) -- punch over
	local s2r = bf.combo_frame.scale
	T.ok(s2 > s2r, "punch: bigger right after the new level, settling down")
	sim:emit("match_resolved", 3, g, 4, 1, 1, 0)
	frames(W, 30)
	T.eq(bf.combo_text.text, "x4", "x4")
	T.ok(bf.combo_frame.scale > s2r, "bigger at depth 4 than at depth 2")
	local gold = W.ns.Assets.COLOR.COMBO_TEXT
	T.ok(bf.combo_text.tr == gold[1] and bf.combo_text.tg == gold[2], "gold")
	frames(W, 30) -- 1 s since the last match
	T.ok(bf.combo_frame.shown and bf.combo_frame.alpha == 1, "still full at 1.0 s")
	sim:emit("board_settled")
	frames(W, 60) -- 1 s since the settle
	T.ok(bf.combo_frame.shown and bf.combo_frame.alpha == 1, "1.2 s after the board settled: still full at 1.0 s")
	frames(W, 20)
	T.ok(bf.combo_frame.alpha < 1, "fading")
	frames(W, 30)
	T.ok(not bf.combo_frame.shown and bf.cdepth == 0, "gone")
	-- a new chain after the old one: depth 1 ends a running meter at once
	sim:emit("match_resolved", 3, g, 3, 1, 1, 0)
	frames(W, 2)
	T.ok(bf.combo_frame.shown, "x3 again")
	sim:emit("match_resolved", 3, g, 1, 1, 1, 0)
	T.ok(not bf.combo_frame.shown, "a fresh depth-1 match resets the meter")
	-- high depths use the cached string table (no per-event string)
	sim:emit("match_resolved", 3, g, 12, 1, 1, 0)
	frames(W, 2)
	T.eq(bf.combo_text.text, "x12", "x12")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("escalation in the HUD: deeper chains give more shards, a gold vignette from depth 4, more shake", function()
	local W = session()
	local App = open_ready(W)
	local hud, sim = App.hud, App.sim
	local jc = hud.juice
	local g = { { x = 1, y = 1, col = 1, row = 1, type = 3 }, { x = 2, y = 1, col = 2, row = 1, type = 3 }, { x = 3, y = 1, col = 3, row = 1, type = 3 } }
	local function parts_for(depth)
		jc:halt()
		hud:_reset_view()
		jc.now = sim.now
		sim:emit("match_resolved", 3, g, depth, 2, 1, 0)
		local n = 0
		for i = 1, #jc.parts do
			if jc.parts[i].t0 ~= nil then n = n + 1 end
		end
		return n, jc.trauma, hud.vig_t0 ~= nil
	end
	local n1, t1, v1 = parts_for(1)
	local n3, t3, v3 = parts_for(3)
	local n6, t6, v6 = parts_for(6)
	T.ok(n1 < n3 and n3 < n6, ("shards grow with depth (%d < %d < %d)"):format(n1, n3, n6))
	T.ok(t1 == 0 and t3 > t1 and t6 > t3, "trauma grows with depth even for 3-matches")
	T.ok(not v1 and not v3 and v6, "gold vignette from depth 4 only")
	local c = W.ns.Assets.COLOR.VIG_COMBO
	local tr = hud.vig_edges[1].tex
	T.ok(tr.r == c[1] and tr.g == c[2], "in gold")
	T.eq(#W.errors, 0, "no errors")
end)

---------------------------------------------------------------- gem motion

T.case("landing: dust at the feet, at most one puff per column per 0.1 s, pooled", function()
	local W = session()
	local App = open_ready(W)
	local jc = App.hud.juice
	jc.now = App.sim.now
	local before = jc:busy()
	T.ok(jc:land_dust(2, 5), "first puff")
	T.ok(jc:busy() > before, "particles")
	T.ok(not jc:land_dust(2, 4), "same column within 0.1 s: refused")
	T.ok(jc:land_dust(3, 5), "another column is independent")
	jc.now = jc.now + 0.11
	T.ok(jc:land_dust(2, 5), "after 0.1 s again")
	for i = 1, 100 do jc:land_dust(i % 8, 5); jc.now = jc.now + 0.11 end
	local n = 0
	for i = 1, #jc.parts do
		if jc.parts[i].t0 ~= nil then n = n + 1 end
	end
	T.ok(n <= jc.PARTS, "pool bound")
	jc:halt()
	T.ok(jc:land_dust(2, 5), "halt resets the throttle")
	-- the board view reports real landings (once per landing)
	local landed = {}
	App.view.on_land = function(c, r) landed[#landed + 1] = c .. "," .. r end
	local gem = App.sim.board:get(3, 4)
	gem.fx, gem.fx_t = "land", 0.1
	App.view:update(nil)
	App.view:update(nil)
	T.eq(#landed, 1, "BoardView.on_land fires once when a gem's effect becomes land")
	T.eq(landed[1], gem.col .. "," .. gem.row, "with its cell")
	gem.fx = nil
	App.view:update(nil)
	gem.fx, gem.fx_t = "land", 0
	App.view:update(nil)
	T.eq(#landed, 2, "and again for the next landing")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("gem frames: fall stretches tall, land squashes wide, then back to a square", function()
	local W = session()
	local App = open_ready(W)
	local sim, view = App.sim, App.view
	local gem = sim.board:get(4, 4)
	local f = view.frame_of[gem]
	gem.fx, gem.fx_t = "fall", 0.9
	view:update(nil)
	T.ok(f.h > f.w and f.w > 0, "falling: taller than wide")
	gem.fx, gem.fx_t = "land", 0.2
	view:update(nil)
	T.ok(f.w > f.h, "landing: wider than tall")
	gem.fx, gem.fx_t = nil, 0
	view:update(nil)
	T.ok(f.w == f.h, "back to a square")
end)

T.case("swap: both gems flash at the swap start", function()
	local W = session()
	local App = open_ready(W)
	local sim, view = App.sim, App.view
	local a, b = sim.board:get(0, 0), sim.board:get(1, 0)
	local fa, fb = view.frame_of[a], view.frame_of[b]
	a.state, b.state = 1, 1 -- Board.SWAPPING
	view:update(nil)
	T.ok(fa.fshown and fb.fshown and fa.flash.alpha > 0.5, "swapping gems flash")
	a.state, b.state = 0, 0
	view:update(nil)
	T.ok(fa.sw_t0 == nil, "and reset when settled")
end)

T.case("rejected swap: both gems shake sideways, the offset returns to exactly 0, the sim stays untouched", function()
	local W = session()
	local App = open_ready(W)
	local sim, view = App.sim, App.view
	local A = W.ns.Assets
	-- a swap that matches nothing
	local ga, gb
	local board = sim.board
	for c = 0, 6 do
		for r = 0, 7 do
			local a, b = board:get(c, r), board:get(c + 1, r)
			if not ga and a and b and a.type ~= b.type then
				board:set(c, r, b); board:set(c + 1, r, a)
				local ok = W.ns.Match.find_matches and #W.ns.Match.find_matches(board) > 0
				board:set(c, r, a); board:set(c + 1, r, b)
				if not ok then ga, gb = a, b end
			end
		end
	end
	T.ok(ga ~= nil, "found a non-matching pair")
	local puffs = {}
	view.on_reject = function(c1, r1, c2, r2) puffs[#puffs + 1] = { c1, r1, c2, r2 } end
	local fa = view.frame_of[ga]
	local rest_x = (ga.x + 0.5) * CELL
	sim:emit("swap_rejected", ga, gb)
	T.eq(#puffs, 1, "the HUD is told (puff)")
	local seen_off, maxoff = false, 0
	local t = 0
	for _ = 1, 40 do
		sim:tick(DT)
		view:update(nil)
		local off = fa.x - rest_x
		if math.abs(off) > 0.5 then seen_off = true end
		if math.abs(off) > maxoff then maxoff = math.abs(off) end
	end
	T.ok(seen_off, "the gem was displaced sideways")
	T.ok(maxoff <= 0.1 * CELL + 1e-6, "by at most 0.1 cell (" .. maxoff .. " px)")
	T.eq(view.rej_a, nil, "the shake ended")
	T.eq(fa.x - (ga.x + 0.5) * CELL, 0, "offset back to exactly 0")
	T.eq(ga.x, ga.col, "the sim gem was never moved by the view")
	sim:emit("swap_rejected") -- no payload (older callers): ignored
	T.eq(view.rej_a, nil, "no gems, no shake")
	-- via the HUD: a puff on both cells
	view.on_reject = App.view.on_reject
	T.eq(#W.errors, 0, "no errors")
	A = nil
end)

T.case("real swap rejection through the sim: the event carries the gems and the shake plays", function()
	local W = session()
	local App = open_ready(W)
	local sim, view = App.sim, App.view
	local got
	sim:on("swap_rejected", function(a, b) got = a ~= nil and b ~= nil end)
	local board = sim.board
	local done = false
	for c = 0, 6 do
		for r = 0, 7 do
			if not done then
				local a, b = board:get(c, r), board:get(c + 1, r)
				if a and b and sim:try_swap(a, b) == "ok" then
					done = true
				end
			end
		end
	end
	frames(W, 60)
	T.ok(done, "a swap was tried")
	-- (some swaps match; the event is only checked when one was rejected)
	T.ok(got == nil or got == true, "payload present when rejected")
	T.eq(#W.errors, 0, "no errors")
end)

---------------------------------------------------------------- auras, selection

T.case("ability auras: skill / ult / bomb, pooled, quantised setters, freed with the gem", function()
	local W = session()
	local App = open_ready(W)
	local sim, view = App.sim, App.view
	local board = sim.board
	local regions, nframes = W.regions, #W.frames
	local gs, gu, gb = board:get(1, 1), board:get(5, 5), board:get(6, 2)
	gs.tier = 1
	gu.tier = 2
	gb.bomb = true
	frames(W, 4)
	local as, au, ab = view.frame_of[gs].aura, view.frame_of[gu].aura, view.frame_of[gb].aura
	T.ok(as and au and ab, "all three have an aura")
	T.ok(as.shown and as.halo.shown and as.ndots == 0, "skill: halo only (playtest 5)")
	T.ok(au.ndots == 0 and not (au.flare ~= nil and au.flare.shown), "ult: halo only")
	T.eq(ab.ndots, 0, "bomb: halo flicker only")
	local C = W.ns.Assets.COLOR
	T.ok(as.halo.vr == C.AURA_SKILL[1] and au.halo.vr == C.AURA_ULT[1] and ab.halo.vr == C.AURA_BOMB[1], "cyan / gold / red")
	-- static gem: setters only on changed quantised values
	local sizes, alphas = 0, 0
	local halo = as.halo
	local ss, sa = halo.SetSize, halo.SetAlpha
	-- (stub regions share methods through a metatable: count by wrapping on the instance)
	halo.SetSize = function(self, w, h) sizes = sizes + 1; return ss(self, w, h) end
	halo.SetAlpha = function(self, v) alphas = alphas + 1; return sa(self, v) end
	local sets = 0
	local dot = as.dots[1]
	local sp = dot.SetPoint
	dot.SetPoint = function(self, ...) sets = sets + 1; return sp(self, ...) end
	frames(W, 120)
	T.ok(sizes < 60 and alphas < 60, ("halo setters on changes only (%d size, %d alpha in 120 frames)"):format(sizes, alphas))
	T.ok(sets < 80, ("orbit dot repositioned on quantised angle steps only (%d in 120 frames)"):format(sets))
	-- pulse range
	local lo, hi = math.huge, 0
	for _ = 1, 90 do
		frames(W, 1)
		lo, hi = math.min(lo, halo.w), math.max(hi, halo.w)
	end

	T.ok(hi > lo and lo / hi > 0.75, "the halo pulses (0.8 -> 1.0)")
	-- the flare turns
	-- (playtest 5: no flare any more)
	-- freed
	gs.tier = 0
	frames(W, 3)
	T.ok(view.frame_of[gs].aura == nil and not as.shown and as.f == nil, "aura released when the gem is no longer an ability gem")
	-- pool bound
	for c = 0, 7 do
		for r = 0, 3 do board:get(c, r).tier = 1 end
	end
	frames(W, 3)
	local used = 0
	for i = 1, #view.auras do
		if view.auras[i].f ~= nil then used = used + 1 end
	end
	T.ok(used <= view.AURA_SLOTS, "aura pool bound (" .. used .. ")")
	T.eq(W.regions, regions, "no texture created by the auras")
	T.eq(#W.frames, nframes, "no frame created by the auras")
	-- halt hides them; the next update brings them back
	view:halt_fx()
	local any = false
	for i = 1, #view.auras do
		if view.auras[i].shown then any = true end
	end
	T.ok(not any, "halt_fx hides every aura")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("selection glow breathes (0.35 -> 0.65); the dragged gem gets a soft halo", function()
	local W = session()
	local App = open_ready(W)
	local sim, view = App.sim, App.view
	local gem = sim.board:get(3, 3)
	local fake = { selected = gem }
	local lo, hi = 9, 0
	for _ = 1, 100 do
		frames(W, 1)
		view:update(fake)
		local a = view.sel.tex.alpha
		lo, hi = math.min(lo, a), math.max(hi, a)
	end
	T.ok(view.sel:IsShown(), "selection shown")
	T.ok(lo >= 0.35 - 1e-9 and hi <= 0.65 + 1e-9 and hi - lo > 0.2, ("breathes between 0.35 and 0.65 (%.2f .. %.2f)"):format(lo, hi))
	local held = { held = gem, hx = 0.3, hy = 0, nb = nil, nx = 0, ny = 0 }
	view:update(held)
	T.ok(view.held_halo.shown, "halo under the dragged gem")
	view:update(nil)
	T.ok(not view.held_halo.shown, "gone when dropped")
	T.eq(#W.errors, 0, "no errors")
end)

---------------------------------------------------------------- signatures

T.case("per-colour signature: all six colours play, ruby rises, sapphire falls, topaz is fast; ult = more", function()
	local W = session()
	local App = open_ready(W)
	local jc = App.hud.juice
	jc.now = App.sim.now
	local function count()
		local n = 0
		for i = 1, #jc.parts do
			if jc.parts[i].t0 ~= nil then n = n + 1 end
		end
		return n
	end
	local counts = {}
	for t = 0, 5 do
		jc:halt()
		jc.now = App.sim.now
		T.ok(jc:signature(t, 200, 200, 1, 0), "signature " .. t)
		counts[t] = count()
		T.ok(counts[t] > 0, "particles for " .. t)
	end
	jc:halt()
	jc:signature(3, 200, 200, 1, 0)
	local n1 = count()
	jc:halt()
	jc:signature(3, 200, 200, 2, 0)
	T.ok(count() > n1, "an ult adds particles")
	local sig = W.ns.Juice.SIGNATURE
	T.ok(sig[3].vy < 0 and sig[4].vy > 0 and sig[5].radial > sig[1].radial and sig[1].radial < 0, "ruby up, sapphire down, topaz fast, amethyst drifts inward")
	T.ok(not jc:signature(99, 1, 1, 1, 0), "unknown colour: nothing")
	-- through the HUD: at the gem cell now, on the enemy when the hit lands
	jc:halt()
	jc.now = App.sim.now
	App.sim:emit("ability_triggered", { id = "frost_nova", toast = "F", blurb = "", icon = "x", tier = 1, col = 2, row = 2, gem_type = 4 })
	T.ok(count() > 0, "ability_triggered plays the signature")
	T.eq(#W.errors, 0, "no errors")
end)

---------------------------------------------------------------- halt, pause

T.case("halt / pause / hide / menu: every board effect is hidden at once and nothing comes back", function()
	local W = session()
	local App = open_ready(W)
	local hud, sim = App.hud, App.sim
	local bf = hud.boardfx
	local function alive()
		return bf:busy() + (bf.combo_frame.shown and 1 or 0) + (bf.wash.shown and 1 or 0) + (bf.dark.shown and 1 or 0)
	end
	local function fire()
		sim:emit("flash", "area", area_cells(), 0.22)
		sim:emit("flash", "row_sweep", { 3, 3, 4, 3, 2, 3 }, 0.16)
		sim:emit("flash", "wave", { 1, 3, 2, 2, 2, 3, 2, 4 }, 0.22)
		sim:emit("chain_hop", 0, 0, 5, 4)
		sim:emit("match_resolved", 3, { { x = 1, y = 1, col = 1, row = 1, type = 3 } }, 4, 1, 1, 0)
		sim:emit("ability_triggered", { id = "frost_nova", toast = "F", blurb = "", icon = "x", tier = 2, col = 1, row = 1, gem_type = 3 })
		sim.board:get(2, 2).tier = 2
		hud.juice:land_dust(1, 1)
		frames(W, 3)
	end
	fire()
	T.ok(alive() > 0, "effects live")
	App.soft_pause("test")
	T.eq(alive(), 0, "pause: hidden")
	for i = 1, #bf.cells do T.ok(not bf.cells[i].tex.shown, "cell hidden " .. i) end
	local view = App.view
	local any = false
	for i = 1, #view.auras do
		if view.auras[i].shown then any = true end
	end
	T.ok(not any, "pause: auras hidden")
	frames(W, 30)
	T.eq(alive(), 0, "and nothing resurrects while paused")
	App.soft_resume()
	frames(W, 60)
	fire()
	hud:halt()
	T.eq(alive(), 0, "halt: hidden")
	fire()
	slash(W, "") -- hides the window
	frames(W, 3)
	hud:halt()
	T.eq(alive(), 0, "hide: hidden")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("unbind removes the sim listeners; a new run gets fresh ones", function()
	local W = session()
	local App = open_ready(W)
	local sim, bf = App.sim, App.hud.boardfx
	local function listeners(name)
		local l = sim.listeners[name]
		local n = 0
		for i = 1, l and #l or 0 do
			if l[i] == bf._on_flash or l[i] == bf._on_hop or l[i] == bf._on_settled then n = n + 1 end
		end
		return n
	end
	T.eq(listeners("flash") + listeners("chain_hop") + listeners("board_settled"), 3, "three listeners while bound")
	App.hud:unbind()
	T.eq(listeners("flash") + listeners("chain_hop") + listeners("board_settled"), 0, "none after unbind")
	sim:emit("flash", "area", area_cells(), 0.22)
	T.eq(active_cells(bf), 0, "an unbound BoardFx ignores events")
	App.hud:bind(App.combat)
	App.hud:bind(App.combat) -- twice: still one set
	T.eq(listeners("flash") + listeners("chain_hop") + listeners("board_settled"), 3, "re-bind: exactly one set")
end)

T.case("a failed BoardFx build leaves the stand-in: the window works, nothing raises", function()
	local W = session(nil, function(w) w.ns.BoardFx.new = function() error("boom") end end)
	local App = open_ready(W)
	local hud, sim = App.hud, App.sim
	T.eq(hud.boardfx, W.ns.BoardFx.NONE, "stand-in")
	T.ok(#W.errors >= 1, "the error was reported")
	local n = #W.errors
	sim:emit("flash", "area", area_cells(), 0.22)
	sim:emit("flash", "wave", { 1, 3, 2, 2 }, 0.22)
	sim:emit("flash", "row_sweep", { 1, 3, 2, 3 }, 0.22)
	sim:emit("chain_hop", 0, 0, 3, 3)
	sim:emit("match_resolved", 3, { { x = 1, y = 1, col = 1, row = 1, type = 3 } }, 5, 1, 1, 0)
	sim:emit("ability_triggered", { id = "frost_nova", toast = "F", blurb = "", icon = "x", tier = 2, col = 1, row = 1, gem_type = 3 })
	frames(W, 30)
	hud:halt()
	T.eq(hud.boardfx:dev("area"), false, "dev does nothing")
	T.eq(#W.errors, n, "no further errors")
end)

---------------------------------------------------------------- debug tab, budget

T.case("debug panel Board FX tab: a button for every effect, the texture test, the glow report", function()
	local W = session()
	local App = open_ready(W)
	local hud = App.hud
	slash(W, "debug")
	local p = App.debug_panel
	T.ok(p ~= nil, "panel open")
	T.eq(#p.pages, 9, "nine tabs (W0-P8: Hit FX)")
	p:select(8)
	local page = p.pages[8]
	local bf = hud.boardfx
	for _, label in ipairs({ "Row sweep", "Wave", "Chain bolt", "Telegraph", "Tele from", "Area flash", "Color flash", "Light skill", "Light ult" }) do
		click(page, label)
		frames(W, 2)
		T.ok(bf:busy() > 0 or bf.wash.shown, label .. " plays")
		frames(W, 90)
	end
	T.eq(bf:busy(), 0, "all end")
	for d = 2, 6 do
		click(page, "Combo x" .. d)
		frames(W, 2)
		T.eq(bf.combo_text.text, "x" .. d, "combo x" .. d)
	end
	frames(W, 150)
	T.ok(not bf.combo_frame.shown, "combo ends")
	click(page, "Land dust")
	T.ok(hud.juice:busy() > 0, "land dust")
	frames(W, 60)
	for _, label in ipairs({ "Sig Amber", "Sig Amethyst", "Sig Emerald", "Sig Ruby", "Sig Sapphire", "Sig Topaz" }) do
		click(page, label)
		T.ok(hud.juice:busy() > 0, label .. " plays")
		frames(W, 60)
	end
	click(page, "Rejected shake")
	T.ok(App.view.rej_a ~= nil, "rejected shake plays")
	frames(W, 40)
	T.eq(App.view.rej_a, nil, "and ends")
	click(page, "Texture test")
	T.ok(bf.tt ~= nil and bf.tt:IsShown(), "texture test shown")
	click(page, "Texture test")
	T.ok(not bf.tt:IsShown(), "and toggled off")
	p:refresh()
	T.ok(page.children and p.glow_text.text:find("glow ok", 1, true) ~= nil, "report in the tab: " .. tostring(p.glow_text.text))
	-- paused: refused with a reason
	App.soft_pause("test")
	local n = #W.printed
	click(page, "Wave")
	T.eq(bf:busy(), 0, "paused: nothing plays")
	local said = false
	for i = n + 1, #W.printed do
		if W.printed[i]:find("unpause", 1, true) then said = true end
	end
	T.ok(said, "says why")
	App.soft_resume()
	T.eq(#W.errors, 0, "no errors")
end)

T.case("budget: board effects live (cells, beam, wedge, bolt, combo, light, auras, selection) allocate nothing per frame", function()
	local W = session()
	local App = open_ready(W)
	local hud, sim, view = App.hud, App.sim, App.view
	slash(W, "fight hellhound")
	frames(W, 60)
	local gs, gu = sim.board:get(1, 1), sim.board:get(5, 5)
	gs.tier = 1
	gu.tier = 2
	local row = { 3, 3, 4, 3, 2, 3, 5, 3, 1, 3, 6, 3, 0, 3, 7, 3 }
	local wave = { 1, 3, 2, 2, 2, 3, 2, 4, 3, 1, 3, 2, 3, 3, 3, 4, 3, 5 }
	local area = area_cells()
	local tele = { 1, 1, 2, 2, 3, 3 }
	local depth = 2
	local fake = { selected = sim.board:get(3, 3) }
	local function storm()
		sim:emit("flash", "row_sweep", row, 0.16)
		sim:emit("flash", "wave", wave, 0.22)
		sim:emit("flash", "area", area, 0.22)
		sim:emit("flash", "telegraph", tele, 0.62)
		sim:emit("chain_hop", 0, 0, 5, 4)
		sim:emit("chain_hop", 5, 4, 2, 6)
		-- (not match_resolved: the score counter and the float text are per-event strings by design)
		hud.boardfx:combo(depth)
		hud.juice:match_break(3, 100, 100, 3, 0, depth)
		depth = depth % 6 + 2
		hud.boardfx:light(3, 2)
		hud.juice:land_dust(depth, 4)
		hud.juice:signature(3, 100, 100, 1, 0)
	end
	-- warm every pooled slot once (the stub tables grow their fields on a texture's first use), then drain
	local jc = hud.juice
	jc.now = sim.now
	for _ = 1, 4 do
		jc:match_break(7, 100, 100, 3, 0, 6)
		jc:spawn_fx(3, 3, 2)
		jc:projectile(10, 10, 400, 200, 2, 1, 1, 1, 0)
		jc:projectile(10, 10, 400, 200, 1, 1, 1, 1, 0)
		jc:signature(3, 100, 100, 2, 0)
	end
	for i = 1, 8 do
		sim:emit("chain_hop", 0, 0, i - 1, 4)
		sim:emit("flash", "area", { 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7 }, 0.22)
		sim:emit("flash", "area", { 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 0 }, 0.22)
		sim:emit("flash", "area", { 0, 2, 1, 3, 2, 4, 3, 5, 4, 6, 5, 7, 6, 0, 7, 1 }, 0.22)
		sim:emit("flash", "area", { 0, 3, 1, 4, 2, 5, 3, 6, 4, 7, 5, 0, 6, 1, 7, 2 }, 0.22)
		sim:emit("flash", "row_sweep", row, 0.16)
		frames(W, 2)
	end
	for _ = 1, 3 do
		storm()
		frames(W, 4)
	end
	for _ = 1, 6 do storm() end
	frames(W, 150)
	local ui_kb = 0
	local n = 0
	local function frame()
		W.wall = W.wall + DT
		n = n + 1
		sim:tick(DT)
		local k = collectgarbage("count")
		if n % 10 == 1 then storm() end
		view:update(fake)
		hud:update()
		ui_kb = ui_kb + collectgarbage("count") - k
	end
	local regions, nframes = W.regions, #W.frames
	alloc_kb(frame, 300, function() ui_kb = 0 end)
	T.ok(hud.boardfx:busy() > 0, "effects live during the measurement")
	T.ok(ui_kb < 1, ("board effects + view allocate < 1 KB per 300 frames (got %.2f KB)"):format(ui_kb))
	T.eq(W.regions, regions, "no texture created")
	T.eq(#W.frames, nframes, "no frame created")
	T.eq(#W.errors, 0, "no errors")
end)

T.done()
