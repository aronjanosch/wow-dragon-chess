-- W0-P8 test: hit / status readability (ui/hit_fx.lua): chip bars, heal flash, low HP, status pop / blink / shatter /
-- slide / class edge / aura, block / reflect, damage number pop / stack / shake, windup telegraph, entrance, death, phase,
-- score punch, fallbacks (no soft textures, no FontString:SetScale, no HitFx at all), halt, the Hit FX debug tab and the
-- allocation budget. Loads the addon in TOC order under test/wow_stubs.lua like ui_boardfx_test.
local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "."
local T = dofile(dir .. "/t.lua")
local loader = dofile(dir .. "/loader.lua")
local Stubs = dofile(dir .. "/wow_stubs.lua")
T.start("ui_hitfx_test")

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
-- W0-P10: streak flight is Juice.FLY (x FLY_HEAVY for an ult); waits derive from it.
local function fly_frames(W, heavy) return math.ceil(W.ns.Juice.FLY * (heavy and W.ns.Juice.FLY_HEAVY or 1) / DT) + 2 end
local function frames(W, n) for _ = 1, n do W.update(DT) end end
local function frames_until(W, pred, n)
	for _ = 1, n or 3000 do
		if pred() then return true end
		W.update(DT)
	end
	return pred()
end
-- Open, wait until the board rests, hold the enemy's timers (no attacks) and make the player safe.
local function open_ready(W, hold)
	slash(W, "")
	local App = W.App
	T.ok(frames_until(W, function() return App.sim:is_at_rest() and App.combat:can_player_swap() == "" end), "board at rest")
	frames(W, 1) -- W0-P10: the start panel halted the HUD; its first running frame re-adopts the statuses
	if hold ~= false then
		App.combat.enemy_timers_held = true
		App.combat.enemy:set_timers_held(true)
	end
	return App
end
local function require_stun(W, App)
	local ok = W.ns.Debug.status(App.run, App.combat, "player_stun")
	return ok
end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end
local function shown(pool)
	local n = 0
	for i = 1, #pool do
		if pool[i].shown then n = n + 1 end
	end
	return n
end
local function wrap(obj, name)
	local orig = obj[name]
	local rec = { n = 0, args = {} }
	obj[name] = function(self, ...)
		rec.n = rec.n + 1
		rec.args = { ... }
		return orig(self, ...)
	end
	return rec
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

---------------------------------------------------------------- pure

T.case("pure helpers: chip value, telegraph envelope, vignette ramp, warn threshold, score peak, aura priority, tint table", function()
	local W = session()
	open_ready(W)
	local H, A = W.ns.HitFx, W.ns.Assets
	T.eq(H.chip_value(100, 60, 0), 100, "chip holds at t = 0")
	T.eq(H.chip_value(100, 60, 0.349), 100, "chip holds until 0.35")
	T.eq(H.chip_value(100, 60, 0.35), 100, "slide starts from the old value")
	local mid = H.chip_value(100, 60, 0.35 + 0.125)
	T.ok(mid < 100 and mid > 60, "sliding in between (" .. mid .. ")")
	T.eq(H.chip_value(100, 60, 0.6), 60, "chip rests at the new value at t = 0.6")
	T.eq(H.chip_value(100, 60, 5), 60, "and stays")
	local prev = -1
	for i = 0, 40 do
		local e = H.telegraph_env(i / 40)
		T.ok(e >= prev, "telegraph envelope monotone at " .. i)
		prev = e
	end
	T.eq(H.telegraph_env(0), 0, "envelope starts at 0")
	T.ok(near(H.telegraph_env(1), 0.5), "envelope ends at 0.5")
	T.eq(H.telegraph_env(5), H.telegraph_env(1), "envelope is capped")
	T.eq(H.telegraph_vig(0.6), 0, "no vignette in the first 60 %")
	prev = 0
	for i = 24, 40 do
		local v = H.telegraph_vig(i / 40)
		T.ok(v >= prev and v <= 0.2 + 1e-9, "vignette monotone and <= 0.2 at " .. i)
		prev = v
	end
	T.ok(near(H.telegraph_vig(1), 0.2), "vignette peaks at 0.2")
	T.eq(H.warn_threshold(8), 2, "8 s status: blink in the last 2 s")
	T.ok(near(H.warn_threshold(20), 5), "20 s status: blink in the last 25 % (5 s)")
	T.eq(H.warn_threshold(0), 2, "min 2 s")
	T.ok(H.score_peak(0) >= 1.08 and H.score_peak(40) > H.score_peak(0), "score peak grows with the amount")
	T.ok(H.score_peak(1e9) <= 1.18 + 1e-9 and H.score_peak(1e9) == H.score_peak(1e12), "score peak is capped")
	local function st(o)
		local s = { statuses = { shield = o.shield or 0, curse = { remaining = o.curse or 0 }, fire_shield = { remaining = o.fire or 0 },
			hot = { remaining = o.life or 0 } }, player_stunned = o.stun or false }
		return s
	end
	T.eq(H.aura_pick(st({})), nil, "no aura without a status")
	T.eq(H.aura_pick(st({ life = 3 })), "hot", "hot")
	T.eq(H.aura_pick(st({ life = 3, shield = 2 })), "shield", "shield beats hot")
	T.eq(H.aura_pick(st({ life = 3, shield = 2, fire = 2 })), "fire_shield", "fire shield beats shield")
	T.eq(H.aura_pick(st({ life = 3, shield = 2, fire = 2, curse = 4 })), "curse", "curse beats fire shield")
	T.eq(H.aura_pick(st({ life = 3, shield = 2, fire = 2, curse = 4, stun = true })), "stun", "stun beats everything")
	local ids = W.App.hud.layout.player_status
	for _, id in ipairs(ids) do T.ok(A.STATUS_EDGE[id] ~= nil, "status edge colour for " .. id) end
	for _, id in ipairs({ "enemy_aegis", "enemy_mirror", "enemy_stun", "enemy_freeze", "enemy_slow" }) do
		T.ok(A.STATUS_EDGE[id] ~= nil, "status edge colour for " .. id)
	end
	for i = 1, #A.AURA_ORDER do T.ok(A.STATUS_AURA[A.AURA_ORDER[i]] ~= nil, "aura colour for " .. A.AURA_ORDER[i]) end
	for _, kind in ipairs({ "plain", "stagger", "flurry", "nuke", "curse", "junk", "mirror", "aegis", "heal_block", "sand", "heal" }) do
		T.ok(H.intent_tint(kind) ~= nil, "telegraph tint for " .. kind)
	end
	T.ok(H.intent_tint("plain") ~= H.intent_tint("curse") and H.intent_tint("curse") ~= H.intent_tint("junk"), "tints differ by kind")
	T.ok(H.intent_tint("sand") == H.intent_tint("heal_block"), "every other kind: orange special")
end)

T.case("every status icon has its class edge colour on its edge texture", function()
	local W = session()
	local App = open_ready(W)
	local hud, A = App.hud, W.ns.Assets
	local gold = A.STATUS_EDGE.shield
	local e = hud.status.shield.edge
	T.ok(e.r == gold[1] and e.g == gold[2] and e.b == gold[3], "shield: gold edge")
	local v = A.STATUS_EDGE.curse
	e = hud.status.curse.edge
	T.ok(e.r == v[1] and e.g == v[2] and e.b == v[3], "curse: violet edge")
	e = hud.aegis_icon.edge
	T.ok(e.r == A.STATUS_EDGE.enemy_aegis[1], "aegis: gold")
	e = hud.mirror_icon.edge
	T.ok(e.r == A.STATUS_EDGE.enemy_mirror[1] and e.b == A.STATUS_EDGE.enemy_mirror[3], "mirror: silver")
	T.eq(hud.status.shield.edge.point ~= nil, true, "edge is placed")
end)

---------------------------------------------------------------- chips, heal, low HP

T.case("chip bar: holds the old value, then slides; a heal snaps it; heal flash; enemy chip too", function()
	local W = session()
	local App = open_ready(W)
	local hud, combat, sim = App.hud, App.combat, App.sim
	local c = hud.hitfx.bars.player
	local mx = combat.player_max_health
	combat.player_health = mx
	frames(W, 3)
	T.ok(c.init and c.lpx == c.w, "chip at rest = full width, behind the fill")
	local old = combat.player_health
	combat.player_health = old - 4000
	frames(W, 1)
	T.eq(c.val, old, "t = 0: chip still at the old value")
	T.ok(c.chip.shown and c.chip.w == c.lpx, "chip texture shows with its width")
	local t0 = sim.now
	frames(W, 18) -- ~0.3 s
	T.ok(sim.now - t0 < 0.35, "still inside the hold")
	T.eq(c.val, old, "t < 0.35: chip holds")
	frames(W, 6) -- ~0.4 s
	T.ok(c.val < old and c.val > old - 4000, "t ~ 0.4: sliding")
	frames(W, 20) -- ~0.73 s
	T.eq(c.val, old - 4000, "t > 0.6: chip at the new value")
	T.eq(c.lpx, math.floor((old - 4000) / mx * c.w + 0.5), "chip width = whole pixels of the value")
	-- widths are whole pixels while sliding
	combat.player_health = old - 8000
	frames(W, 1)
	for _ = 1, 40 do
		frames(W, 1)
		T.ok(c.chip.w == math.floor(c.chip.w), "whole pixel width")
	end
	-- heal: the chip snaps to the new value, the flash starts
	combat.player_health = old - 6000
	frames(W, 1)
	T.eq(c.val, old - 6000, "heal: chip jumps to the value (the fill grows over it)")
	sim:emit("player_healed", 2000)
	frames(W, 1)
	local ht = hud.hitfx.heal_tex
	T.ok(ht.shown and ht.alpha > 0 and ht.alpha <= 0.45 + 1e-9, "green flash over the player bar")
	T.ok(ht.blend == "ADD", "additive")
	frames(W, 25)
	T.ok(not ht.shown, "flash over after 0.25 s")
	-- enemy chip
	local e = hud.hitfx.bars.enemy
	local before = hud.state.enemy_health
	combat.enemy.current_health = before - 1000
	frames(W, 1)
	T.eq(e.val, before, "enemy chip holds the old value")
	frames(W, 40)
	T.eq(e.val, before - 1000, "enemy chip slid")
	-- a new fight (higher HP) does not leave a stale chip: the value just snaps
	T.eq(#W.errors, 0, "no errors")
end)

T.case("low HP: glow + heartbeat at <= 25 %, faster below 10 %, off when healthy / stunned / dead / halted", function()
	local W = session()
	local App = open_ready(W)
	local hud, combat = App.hud, App.combat
	local hf, A = hud.hitfx, W.ns.Assets
	local mx = combat.player_max_health
	combat.player_health = mx
	frames(W, 3)
	T.ok(not hf.low_glow.shown and hud.state.player_health == mx, "healthy: no glow")
	T.eq(hf.vig.alpha, 0, "healthy: no heartbeat")
	combat.player_health = math.floor(mx * 0.2)
	local lo, hi, seen = 2, -1, false
	for _ = 1, 120 do
		frames(W, 1)
		local a = hf.vig.alpha
		if a < lo then lo = a end
		if a > hi then hi = a end
		seen = seen or hf.low_glow.shown
	end
	T.ok(seen and hf.low_glow.alpha >= 0.15 - 1e-9 and hf.low_glow.alpha <= 0.5 + 1e-9, "20 %: the red glow pulses")
	T.ok(lo >= 0.08 - 1e-9 and hi <= 0.2 + 1e-9 and hi > lo, ("heartbeat vignette in 0.08 .. 0.2 (%.2f .. %.2f)"):format(lo, hi))
	local c = A.COLOR.LOW_HP
	T.ok(hf.vig_c == c, "the heartbeat is red")
	-- pulse rate: count crossings of the middle value in 2 s, 20 % vs 5 %
	local function crossings()
		local n, prev = 0, nil
		local mid = (0.08 + 0.2) / 2
		for _ = 1, 120 do
			frames(W, 1)
			local up = hf.vig.alpha > mid
			if prev ~= nil and up ~= prev then n = n + 1 end
			prev = up
		end
		return n
	end
	local slow = crossings()
	combat.player_health = math.floor(mx * 0.05)
	local fast = crossings()
	T.ok(fast > slow, ("below 10 %% pulses faster (%d vs %d crossings)"):format(fast, slow))
	combat.player_health = math.floor(mx * 0.3)
	frames(W, 2)
	T.ok(not hf.low_glow.shown and hf.vig.alpha == 0, "above 25 %: off")
	combat.player_health = math.floor(mx * 0.2)
	frames(W, 2)
	T.ok(hf.low_glow.shown, "back on at 20 %")
	T.ok(require_stun(W, App), "player stunned")
	frames(W, 2)
	T.ok(not hf.low_glow.shown and hf.vig.alpha == 0, "stunned: off")
	combat:_clear_status("stun")
	frames(W, 2)
	T.ok(hf.low_glow.shown, "stun over: on again")
	hud:halt()
	T.ok(not hf.low_glow.shown and hf.vig.alpha == 0, "halted: off")
	frames(W, 1)
	-- dead
	combat.player_health = 0
	frames(W, 2)
	T.ok(not hf.low_glow.shown, "dead: off")
	-- dev toggle forces it on (healthy bar)
	combat.player_health = mx
	frames(W, 2)
	T.ok(hud:dev_hitfx("low"), "dev low on")
	frames(W, 2)
	T.ok(hf.low_glow.shown, "forced on at full HP")
	hud:dev_hitfx("low")
	frames(W, 2)
	T.ok(not hf.low_glow.shown, "toggled off")
	T.eq(#W.errors, 0, "no errors")
end)

---------------------------------------------------------------- statuses

T.case("status icon: pop + ring on appear, blink in the last seconds, shatter on expiry, no shatter when cleared", function()
	local W = session()
	local App = open_ready(W)
	local hud, combat = App.hud, App.combat
	local hf, jc = hud.hitfx, hud.juice
	local rec = hf.icon_by_id.hot
	local icon = hud.status.hot
	local bursts = wrap(jc, "burst")
	local rings0 = shown(jc.rings)
	combat:apply_hot(5, 5, 1)
	frames(W, 1)
	T.ok(rec.on and icon.shown, "icon on")
	T.ok(icon.scale > 1.3 and icon.scale <= 1.5, "pop: scale 1.5 -> 1 (" .. icon.scale .. ")")
	frames(W, 1)
	T.ok(shown(jc.rings) > rings0, "a ring at the icon")
	frames(W, 13)
	T.eq(icon.scale, 1, "pop over after 0.18 s")
	T.eq(icon.alpha, 1, "no blink with 4+ s left")
	-- blink in the last 2 s: both alpha values appear within a second
	frames_until(W, function() return combat:status_remaining("hot") <= 1.9 end, 600)
	local seen = {}
	for _ = 1, 30 do
		frames(W, 1)
		if combat:status_remaining("hot") > 0.4 then seen[icon.alpha] = true end
	end
	T.ok(seen[1] and seen[0.55], "blinks between 1 and 0.55 in the last 2 s")
	local rem_n = 0
	for _ in pairs(seen) do rem_n = rem_n + 1 end
	T.eq(rem_n, 2, "only those two alpha values")
	-- expiry: shatter 4-6 shards
	bursts.n = 0
	T.ok(frames_until(W, function() return not icon.shown end, 600), "icon expired")
	T.eq(bursts.n, 1, "one shatter burst")
	T.ok(bursts.args[3] >= 4 and bursts.args[3] <= 6, "4 - 6 shards (" .. tostring(bursts.args[3]) .. ")")
	T.eq(icon.alpha, 1, "alpha reset")
	T.eq(icon.scale, 1, "scale reset")
	-- cleared before it ran out: no shatter
	combat:apply_hot(5, 8, 1)
	frames(W, 20)
	bursts.n = 0
	combat:_clear_status("hot")
	frames(W, 2)
	T.ok(not icon.shown and bursts.n == 0, "cleared early: no shatter")
	-- re-applied while on: a small pop
	combat:apply_hot(5, 8, 1)
	frames(W, 20)
	combat:apply_hot(5, 8, 1)
	frames(W, 1)
	T.ok(icon.scale > 1, "re-applied: small pop (" .. icon.scale .. ")")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("status strip slides to its new layout (0.12 s) instead of snapping and converges", function()
	local W = session()
	local App = open_ready(W)
	local hud, combat = App.hud, App.combat
	local life, fire = hud.status.hot, hud.status.fire_shield
	combat:apply_fire_shield(30, 1)
	combat:apply_hot(5, 30, 1)
	frames(W, 20)
	local x_before = life.x
	T.ok(x_before ~= nil, "placed")
	T.ok(fire.shown and life.shown, "both on")
	local slot = hud.layout.status_size + 3
	combat:_clear_status("fire_shield")
	frames(W, 3)
	T.ok(not fire.shown, "the first icon is gone")
	T.ok(life.x < x_before and life.x > x_before - slot, "hot is on its way (" .. life.x .. " of " .. x_before .. " -> " .. (x_before - slot) .. ")")
	local last, mono = life.x, true
	for _ = 1, 12 do
		frames(W, 1)
		if life.x > last then mono = false end
		last = life.x
	end
	T.ok(mono, "moves left only")
	T.ok(near(life.x, x_before - slot, 1), "converged on the new slot")
	local rec = hud.hitfx.icon_by_id.hot
	T.ok(rec.sl_t0 == nil and rec.cx == rec.tx, "slide finished")
	T.eq(life.x, math.floor(life.x), "whole pixels")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("shield: stacks eaten pop, the last one shatters smaller; block = ring + cyan-white flash + icon punch, once", function()
	local W = session()
	local App = open_ready(W)
	local hud, combat = App.hud, App.combat
	local hf, jc, A = hud.hitfx, hud.juice, W.ns.Assets
	local rec = hf.icon_by_id.shield
	local icon = hud.status.shield
	combat:add_shield_stack(0)
	combat:add_shield_stack(0)
	frames(W, 25)
	T.ok(icon.shown and icon.scale == 1, "two stacks, at rest")
	local blocked = wrap(hf, "blocked")
	local bursts = wrap(jc, "burst")
	local rings0 = shown(jc.rings)
	combat:take_damage(100)
	frames(W, 1)
	T.eq(blocked.n, 1, "block effect fired once")
	T.ok(icon.scale > 1.2, "icon punch on the shield (" .. icon.scale .. ")")
	T.ok(rec.pop_peak == 1.4 or icon.scale <= 1.4, "punch 1.4")
	T.ok(shown(jc.rings) > rings0, "block ring")
	T.ok(hud.vig_color == A.COLOR.VIG_BLOCK and hud.vig_peak == 0.35, "vignette flash cyan-white, peak 0.35")
	frames(W, 20)
	T.eq(icon.scale, 1, "punch over")
	T.eq(bursts.n, 0, "one stack left: no shatter yet")
	combat:take_damage(100)
	frames(W, 1)
	T.ok(not icon.shown, "last stack gone")
	T.eq(bursts.n, 1, "the last stack shatters")
	T.eq(bursts.args[3], 3, "a smaller shatter (3 shards)")
	T.eq(blocked.n, 2, "second block, once")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("reflect: orange flash (existing) + icon punch on the fire shield, once", function()
	local W = session()
	local App = open_ready(W)
	local hud, combat = App.hud, App.combat
	local hf, A = hud.hitfx, W.ns.Assets
	combat:apply_fire_shield(10, 1)
	frames(W, 25)
	local reflected = wrap(hf, "reflected")
	combat:take_damage(100)
	frames(W, 1)
	T.eq(reflected.n, 1, "reflect effect fired once")
	T.ok(hud.status.fire_shield.scale > 1.2, "icon punch")
	T.ok(hud.vig_color == A.COLOR.VIG_REFLECT, "orange flash kept")
	frames(W, 20)
	T.eq(hud.status.fire_shield.scale, 1, "punch over")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("player aura: highest priority wins, colour per status, pulses within its alpha range, off without a status", function()
	local W = session()
	local App = open_ready(W)
	local hud, combat = App.hud, App.combat
	local hf, A = hud.hitfx, W.ns.Assets
	frames(W, 2)
	T.ok(not hf.aura_out.shown and hf.aura_id == nil, "no status: no aura")
	local function want(id)
		frames(W, 3)
		T.eq(hf.aura_id, id, "aura " .. tostring(id))
		if id ~= nil then
			T.ok(hf.aura_out.shown and hf.aura_in.shown, id .. ": halo shown")
			local c = A.STATUS_AURA[id]
			T.ok(hf.aura_out.vr == c[1] and hf.aura_out.vg == c[2] and hf.aura_out.vb == c[3], id .. ": colour")
		end
	end
	combat:apply_hot(5, 60, 1)
	want("hot")
	combat:add_shield_stack(0)
	want("shield")
	combat:apply_fire_shield(60, 1)
	want("fire_shield")
	W.ns.Debug.status(App.run, combat, "curse")
	want("curse")
	local lo, hi = 2, -1
	for _ = 1, 150 do
		frames(W, 1)
		local a = hf.aura_out.alpha
		if a < lo then lo = a end
		if a > hi then hi = a end
	end
	T.ok(lo >= 0.12 - 1e-9 and hi <= 0.38 + 1e-9 and hi > lo + 0.05, ("curse pulses in range (%.2f .. %.2f)"):format(lo, hi))
	W.ns.Debug.status(App.run, combat, "player_stun")
	want("stun")
	combat:_clear_status("stun")
	want("curse")
	combat:_clear_status("curse")
	want("fire_shield")
	combat:_clear_status("fire_shield")
	want("shield")
	combat.status.shield.stacks = 0
	combat:_clear_status("hot")
	want(nil)
	T.ok(not hf.aura_out.shown and not hf.aura_in.shown, "halo hidden")
	-- dev preview
	T.ok(hud:dev_hitfx("aura_fire_shield"), "dev aura")
	frames(W, 3)
	T.eq(hf.aura_id, "fire_shield", "dev aura shows")
	frames(W, 200)
	T.eq(hf.aura_id, nil, "dev aura ends after 3 s")
	T.eq(#W.errors, 0, "no errors")
end)

---------------------------------------------------------------- numbers

T.case("damage numbers: pop scale 1.6 -> 1, crit bigger + shake, stacked offsets, heal slower, bounded pool", function()
	local W = session()
	local App = open_ready(W)
	local hud, A = App.hud, W.ns.Assets
	local pool = hud.pops_enemy
	T.ok(hud.hitfx.can_scale, "SetScale probe passed")
	local regions, nframes = W.regions, #W.frames
	hud:_enemy_hit(120, false)
	local fs
	for i = 1, #pool do
		if pool[i].shown then fs = pool[i] end
	end
	T.ok(fs ~= nil and fs.scale == 1.6, "starts at scale 1.6 (" .. tostring(fs and fs.scale) .. ")")
	frames(W, 4)
	T.ok(fs.scale < 1.6 and fs.scale >= 1, "easing down")
	frames(W, 4)
	T.eq(fs.scale, 1, "1.0 after 0.12 s")
	local y1 = fs.y
	frames(W, 20)
	T.ok(fs.y > y1, "then rises")
	frames(W, 60)
	T.ok(not fs.shown, "gone")
	-- crit: bigger + shake for 0.15 s
	hud:_enemy_hit(900, true)
	for i = 1, #pool do
		if pool[i].shown then fs = pool[i] end
	end
	T.ok(fs.scale == 1.9, "crit pops bigger (" .. tostring(fs.scale) .. ")")
	local xs, base = {}, fs.x0
	for _ = 1, 9 do
		frames(W, 1)
		xs[#xs + 1] = fs.x * fs.scale
	end
	local minx, maxx = 1e9, -1e9
	for _, x in ipairs(xs) do
		minx, maxx = math.min(minx, x), math.max(maxx, x)
	end
	T.ok(maxx - minx >= 2 and maxx - base <= 3.5 and base - minx <= 3.5, ("shakes within +-3 px (%.1f .. %.1f around %d)"):format(minx, maxx, base))
	frames(W, 6)
	T.eq(fs.x, base, "shake over: exactly at x0")
	frames(W, 70)
	-- stacking: 5 numbers at the same instant
	local now = App.sim.now
	local ys = {}
	for i = 1, 5 do
		hud:_spawn_pop(pool, "-" .. i, A.COLOR.POP_ENEMY, 0, 0, false)
		ys[i] = pool[(pool.next - 2) % #pool + 1].y0
	end
	T.eq(ys[1], 0, "first: no offset")
	T.eq(ys[2], 14, "second: +14 px")
	T.eq(ys[3], 28, "third: +28 px")
	T.eq(ys[4], 28, "stack is capped at three")
	T.eq(ys[5], 28, "still capped")
	frames(W, 20) -- 0.33 s later: a new burst
	hud:_spawn_pop(pool, "-9", A.COLOR.POP_ENEMY, 0, 0, false)
	T.eq(pool[(pool.next - 2) % #pool + 1].y0, 0, "a later number starts a new stack")
	-- heal numbers rise slower, player numbers shake by size
	frames(W, 80)
	local pp = hud.pops_player
	hud:_spawn_pop(pp, "+100", A.COLOR.POP_HEAL, 60, -232, false, "heal")
	local heal = pp[(pp.next - 2) % #pp + 1]
	frames(W, 60)
	local hdy = heal.y - heal.y0
	frames(W, 80)
	hud:_spawn_pop(pp, "-100", A.COLOR.POP_PLAYER, 60, -232, false, "player", 0.1)
	local small = pp[(pp.next - 2) % #pp + 1].shake
	hud:_spawn_pop(pp, "-1000", A.COLOR.POP_PLAYER, 60, -232, false, "player", 1)
	local big = pp[(pp.next - 2) % #pp + 1].shake
	T.ok(big > small and big <= 3 and small >= 1, ("player shake scales with the hit (%.1f < %.1f)"):format(small, big))
	frames(W, 5)
	T.ok(hdy > 0 and hdy < 46 * 0.9 * 0.6 / 0.9 + 1, "heal rise is the slow one (" .. hdy .. ")")
	-- pool bounded, nothing created
	for i = 1, 60 do hud:_spawn_pop(pool, "-" .. i, A.COLOR.POP_ENEMY, 0, 0, i % 7 == 0, i % 7 == 0 and "crit" or nil) end
	T.eq(#pool, 8, "pool of 8")
	T.eq(W.regions, regions, "no region created")
	T.eq(#W.frames, nframes, "no frame created")
	-- match floats keep the old look
	T.ok(hud.pops_match.plain, "match floats are plain")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("damage numbers without FontString:SetScale: the big font for the first 0.12 s, then back; nothing breaks", function()
	local W = session(function(w) w.no_region_scale = true end)
	local App = open_ready(W)
	local hud, A = App.hud, W.ns.Assets
	T.ok(not hud.hitfx.can_scale, "probe failed -> fallback")
	local pool = hud.pops_enemy
	hud:_enemy_hit(120, false)
	local fs
	for i = 1, #pool do
		if pool[i].shown then fs = pool[i] end
	end
	T.eq(fs.font, A.FONT_POP_BIG, "big font while popping")
	frames(W, 10)
	T.eq(fs.font, A.FONT_POP, "normal font after 0.12 s")
	hud:_enemy_hit(900, true)
	for i = 1, #pool do
		if pool[i].shown and pool[i] ~= fs then fs = pool[i] end
	end
	frames(W, 15)
	T.eq(fs.font, A.FONT_POP_BIG, "crits keep the big font")
	frames(W, 80)
	hud:halt()
	local sc = App.win.bottom.children
	T.eq(#W.errors, 0, "no errors")
	T.ok(sc ~= nil, "window alive")
	-- plaque punch is a Frame: still works
	App.sim:emit("score_awarded", 100)
	frames(W, 5)
	T.ok(hud.plaque.scale > 1, "plaque punch needs no FontString scale")
	T.eq(hud.name_text.scale, nil, "the name text is not scaled without SetScale")
end)

---------------------------------------------------------------- telegraph, figure, phase, score

T.case("windup telegraph: glow grows, vignette only in the last 40 %, intent colour, cleared at the hit", function()
	local W = session()
	local App = open_ready(W, false)
	local hud, combat, sim = App.hud, App.combat, App.sim
	local hf, A = hud.hitfx, W.ns.Assets
	slash(W, "fight hellhound")
	frames(W, 30)
	T.ok(frames_until(W, function() return combat.enemy:is_winding_up() end, 3000), "the enemy winds up")
	frames(W, 1)
	T.ok(hf.tele_t0 ~= nil and hf.tele_dur > 0.3, "telegraph started with the windup length")
	T.ok(hf.tele_c == A.INTENT_TINT.plain, "attack red for a plain hit")
	local first = hf.tele_glow.alpha
	local k_vig_seen, early_vig = 0, 0
	local glows = {}
	while combat.enemy:is_winding_up() do
		frames(W, 1)
		if hf.tele_t0 == nil then break end
		local k = (sim.now - hf.tele_t0) / hf.tele_dur
		glows[#glows + 1] = hf.tele_glow.shown and hf.tele_glow.alpha or 0
		if k < 0.6 and hf.vig.alpha > 0 then early_vig = early_vig + 1 end
		if hf.vig.alpha > k_vig_seen then k_vig_seen = hf.vig.alpha end
		if not combat.enemy:is_winding_up() then break end
	end
	T.eq(early_vig, 0, "no vignette in the first 60 % of the windup")
	T.ok(k_vig_seen > 0 and k_vig_seen <= 0.2 + 1e-9, "vignette near the end, <= 0.2 (" .. k_vig_seen .. ")")
	T.ok(#glows > 5 and glows[#glows - 1] > glows[1], "glow grew over the windup")
	local mx = 0
	for _, g in ipairs(glows) do mx = math.max(mx, g) end
	T.ok(mx <= 0.5 * 1.15 + 0.03, "glow stays <= 0.5 (+ pulse) (" .. mx .. ")")
	frames(W, 2)
	T.ok(hf.tele_t0 == nil and not hf.tele_glow.shown and hf.vig.alpha == 0, "cleared at the hit")
	-- stun cancels it
	T.ok(frames_until(W, function() return combat.enemy:is_winding_up() end, 3000), "next windup")
	frames(W, 3)
	T.ok(hf.tele_glow.shown, "telegraph on")
	combat.enemy:apply_stun(2, "stun")
	frames(W, 2)
	T.ok(hf.tele_t0 == nil and not hf.tele_glow.shown, "cleared on stun")
	-- halt clears it
	combat.enemy:apply_stun(600, "stun") -- W1-G3: hold the (now faster) Hellhound for the dev telegraph checks below
	hf:windup({ kind = "curse" }, 1, sim.now)
	hf.tele_dev = true
	frames(W, 5)
	T.ok(hf.tele_glow.shown and hf.tele_c == A.INTENT_TINT.curse, "curse purple")
	hud:halt()
	T.ok(hf.tele_t0 == nil and not hf.tele_glow.shown and hf.vig.alpha == 0, "cleared on halt")
	-- dev kinds
	for _, kind in ipairs({ "plain", "curse", "junk", "mirror", "special" }) do
		T.ok(hud:dev_hitfx("tele_" .. kind), "dev telegraph " .. kind)
		frames(W, 80)
	end
	frames(W, 120)
	T.ok(hf.tele_t0 == nil and not hf.tele_glow.shown, "dev telegraph ends on its own")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("entrance: slides in 24 px from the right while fading in, ends exactly at rest; name punches", function()
	local W = session()
	local App = open_ready(W)
	local hud, combat = App.hud, App.combat
	local hf = hud.hitfx
	slash(W, "fight hellhound")
	frames(W, 1)
	local holder = hud.enemy_holder
	T.ok(holder.x > 0 and holder.x <= 24 and holder.alpha < 1, ("slides in (x %s, alpha %s)"):format(tostring(holder.x), tostring(holder.alpha)))
	T.ok(hud.name_text.scale > 1, "the name punches")
	T.ok(hf.enter_ring.shown, "ring at the feet")
	local last_x, last_a = holder.x, holder.alpha
	for _ = 1, 20 do
		frames(W, 1)
		T.ok(holder.x <= last_x and holder.alpha >= last_a, "x falls, alpha rises")
		last_x, last_a = holder.x, holder.alpha
	end
	frames(W, 10)
	T.eq(holder.x, 0, "ends at x 0")
	T.eq(holder.y, 0, "and y 0")
	T.eq(holder.alpha, 1, "alpha 1")
	T.ok(not hf.enter_ring.shown, "ring over")
	T.eq(hud.name_text.scale, 1, "name back at scale 1")
	-- halt mid-entrance: resting state at once
	slash(W, "fight hellhound")
	frames(W, 2)
	hud:halt()
	T.ok(hf.enter_t0 == nil and not hf.enter_ring.shown, "halt ends the entrance")
	frames(W, 1)
	T.eq(holder.x, 0, "at rest")
	T.eq(holder.alpha, 1, "visible")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("death: motes, white flash (0.15 s), upward drift 6 px while fading; boss = bigger; next fight at rest", function()
	local W = session()
	local App = open_ready(W)
	local hud, combat = App.hud, App.combat
	local hf, jc = hud.hitfx, hud.juice
	frames(W, 30)
	local holder = hud.enemy_holder
	local parts0 = shown(jc.parts)
	local first = combat.enemy
	first:take_damage(first.current_health)
	frames(W, 2)
	T.ok(hf.death_flash.shown and hf.death_flash.alpha <= 0.6 + 1e-9 and hf.death_flash.blend == "ADD", "white additive flash")
	frames(W, 24)
	T.ok(shown(jc.parts) >= 10, "light motes in flight (" .. shown(jc.parts) .. ")")
	frames(W, 14)
	T.ok(not hf.death_flash.shown, "flash is over after 0.15 s")
	frames(W, 60)
	T.eq(holder.y, 6, "drifted up 6 px")
	T.eq(holder.alpha, 0, "faded out")
	local small = 0
	for _ = 1, 1 do
		hf:death(false, App.sim.now)
		small = hf.jc:busy()
	end
	frames(W, 120)
	hf:death(true, App.sim.now)
	T.ok(hf.jc:busy() > small, "a boss death is bigger (" .. hf.jc:busy() .. " vs " .. small .. ")")
	-- next fight: everything back at rest
	T.ok(frames_until(W, function() return combat.enemy ~= first end, 600), "next fight")
	frames(W, 40)
	T.eq(holder.y, 0, "y 0 again")
	T.eq(holder.x, 0, "x 0")
	T.eq(holder.alpha, 1, "alpha 1")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("phase change: ring, trauma 0.3, cast flash, name punch", function()
	local W = session()
	local App = open_ready(W)
	local hud, sim = App.hud, App.sim
	local jc = hud.juice
	frames(W, 30)
	local rings0 = shown(jc.rings)
	jc.trauma = 0
	sim:emit("enemy_phase_changed", "Enrage")
	T.ok(jc.trauma >= 0.3, "trauma 0.3 (" .. jc.trauma .. ")")
	frames(W, 1)
	T.ok(shown(jc.rings) > rings0, "impact ring on the enemy")
	T.ok(hud.cast_glow.alpha > 0, "cast-tint flash")
	T.ok(hud.name_text.scale > 1, "name punch")
	frames(W, 40)
	T.eq(hud.name_text.scale, 1, "name back at 1")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("score plaque: punch 1.0 -> peak -> 1.0 in 0.2 s, bigger for bigger amounts (capped), glint; unbound = nothing", function()
	local W = session()
	local App = open_ready(W)
	local hud, sim = App.hud, App.sim
	local hf, p = hud.hitfx, hud.plaque
	local function peak(amount)
		sim:emit("score_awarded", amount)
		local m = 1
		for _ = 1, 14 do
			frames(W, 1)
			if p.scale > m then m = p.scale end
		end
		frames(W, 20)
		return m
	end
	frames(W, 5)
	T.eq(p.scale, 1, "rest")
	local small, big, huge = peak(20), peak(200), peak(100000)
	T.ok(small > 1.05 and small < big, ("bigger amount, bigger punch (%.2f < %.2f)"):format(small, big))
	T.ok(huge <= 1.18 + 0.005 and near(huge, big, 0.02), ("capped at 1.18 (%.3f)"):format(huge))
	T.eq(p.scale, 1, "back at 1.0")
	-- the plaque stays in place: the centre anchor offsets are divided by the scale
	sim:emit("score_awarded", 100)
	frames(W, 4)
	T.ok(near(p.x * p.scale, 526, 0.6) and near(p.y * p.scale, 6, 0.1), "plaque centre unchanged while scaled")
	T.ok(hf.glint.shown, "gold glint")
	frames(W, 25)
	T.ok(not hf.glint.shown, "glint over")
	hud:unbind()
	sim:emit("score_awarded", 100)
	T.eq(hf.score_t0, nil, "not subscribed while unbound")
	hud:bind(App.combat)
	sim:emit("score_awarded", 100)
	T.ok(hf.score_t0 ~= nil, "subscribed again after bind")
	T.eq(#W.errors, 0, "no errors")
end)

---------------------------------------------------------------- halt, fallbacks, debug tab, budget

T.case("FightView:halt clears every new effect", function()
	local W = session()
	local App = open_ready(W)
	local hud, combat, sim = App.hud, App.combat, App.sim
	local hf = hud.hitfx
	combat:apply_hot(5, 30, 1)
	combat:add_shield_stack(0)
	combat:apply_fire_shield(30, 1)
	frames(W, 3)
	combat.player_health = math.floor(combat.player_max_health * 0.2)
	frames(W, 3)
	sim:emit("player_healed", 100)
	sim:emit("score_awarded", 100)
	sim:emit("attack_blocked")
	sim:emit("enemy_phase_changed", "Enrage")
	hud:_enemy_hit(500, true)
	hf:dev("tele_plain", sim.now)
	hf:dev("chip_player", sim.now)
	hf:dev("enter", sim.now)
	hf:dev("death_boss", sim.now)
	frames(W, 4)
	T.ok(hf.heal_tex.shown and hf.low_glow.shown and hf.aura_out.shown and hf.tele_glow.shown, "effects are live")
	hud:halt()
	T.ok(not hf.heal_tex.shown and not hf.low_glow.shown and not hf.aura_out.shown and not hf.aura_in.shown, "heal / low / aura hidden")
	T.ok(not hf.tele_glow.shown and not hf.death_flash.shown and not hf.glint.shown and not hf.enter_ring.shown, "telegraph / flash / glint / ring hidden")
	T.eq(hf.vig.alpha, 0, "vignette 0")
	T.ok(not hf.bars.player.chip.shown and not hf.bars.enemy.chip.shown, "chips hidden")
	T.eq(hud.plaque.scale, 1, "plaque scale 1")
	T.eq(hud.name_text.scale, 1, "name scale 1")
	for _, rec in ipairs(hf.icons) do
		T.ok(rec.f.scale == 1 or rec.f.scale == nil, "icon scale 1 " .. rec.id)
		T.ok(rec.f.alpha == 1, "icon alpha 1 " .. rec.id)
	end
	for _, pool in ipairs({ hud.pops_enemy, hud.pops_player }) do
		for i = 1, #pool do T.ok(pool[i].scale == nil or pool[i].scale == 1 or not pool[i].shown, "number scale reset") end
	end
	T.ok(hf.enter_t0 == nil and hf.death_t0 == nil and hf.tele_t0 == nil and hf.score_t0 == nil, "all timers cleared")
	-- the next update does not pop the statuses that were already there
	local rec = hf.icon_by_id.hot
	frames(W, 2)
	T.ok(rec.pop_t0 == nil, "resync: no pop for statuses that were already on")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("fallbacks: no soft textures -> masked discs; a failing HitFx build -> the window keeps working", function()
	local W = session(nil, function(w) w.ns.Assets.GLOW = {} end)
	local App = open_ready(W)
	local hud, combat = App.hud, App.combat
	local hf = hud.hitfx
	T.ok(hf ~= W.ns.HitFx.NONE, "built")
	T.ok(hf.aura_out.hf_soft == false and hf.aura_out.mask ~= nil, "aura: masked disc")
	T.ok(hf.tele_glow.hf_soft == false and hf.low_glow.hf_soft == false and hf.death_flash.hf_soft == false, "glows: masked discs")
	combat:apply_hot(5, 20, 1)
	combat.player_health = math.floor(combat.player_max_health * 0.2)
	frames(W, 4)
	T.ok(hf.aura_out.shown and hf.aura_out.r ~= nil, "aura shows in the colour")
	T.ok(hf.low_glow.shown, "low glow shows")
	hf:dev("death", App.sim.now)
	hf:dev("tele_curse", App.sim.now)
	frames(W, 10)
	T.ok(hf.death_flash.shown or hf.tele_glow.shown, "flash / telegraph without soft textures")
	T.eq(#W.errors, 0, "no errors")

	local W2 = session(nil, function(w) w.ns.HitFx.new = function() error("boom") end end)
	local App2 = W2.App
	slash(W2, "")
	T.ok(frames_until(W2, function() return App2.sim:is_at_rest() end), "board at rest")
	T.eq(App2.hud.hitfx, W2.ns.HitFx.NONE, "the stand-in")
	T.ok(#W2.errors >= 1, "the error went to the handler")
	local n = #W2.errors
	local combat2 = App2.combat
	combat2:apply_hot(5, 5, 1)
	combat2:add_shield_stack(0)
	frames(W2, 20)
	combat2:take_damage(100)
	App2.sim:emit("player_healed", 10)
	App2.sim:emit("score_awarded", 10)
	App2.sim:emit("enemy_phase_changed", "x")
	App2.sim:emit("enemy_windup", { kind = "plain" }, 0.5)
	App2.hud:_enemy_hit(5, true)
	frames(W2, 90)
	T.ok(App2.hud.status.hot.x ~= nil, "icons are placed without HitFx")
	T.eq(#W2.errors, n, "no further errors")
	T.eq(App2.hud:dev_hitfx("block"), false, "dev does nothing")
	App2.hud:halt()
	T.ok(App2.win.frame:IsShown(), "window alive")
end)

T.case("debug panel Hit FX tab: a button for every effect, all play without errors", function()
	local W = session()
	local App = open_ready(W)
	local hud = App.hud
	slash(W, "debug")
	local p = App.debug_panel
	T.ok(p ~= nil and #p.pages == 9, "nine tabs")
	p:select(9)
	local page = p.pages[9]
	local H = W.ns.HitFx
	T.ok(#H.DEV_BUTTONS >= 30, "buttons for every effect (" .. #H.DEV_BUTTONS .. ")")
	local found = {}
	for _, ch in ipairs(page.children) do
		if ch.ftype == "Button" and ch.text ~= nil then found[ch.text.text] = ch end
	end
	local nerr = #W.errors
	for _, entry in ipairs(H.DEV_BUTTONS) do
		T.ok(found[entry[1]] ~= nil, "button " .. entry[1])
		if found[entry[1]] then found[entry[1]]:Click() end
		frames(W, 3)
	end
	frames(W, 300)
	T.eq(#W.errors, nerr, "no errors from any button")
	T.ok(hud:dev_hitfx("nonsense") == false, "unknown kind")
end)

T.case("allocation budget: nothing created and < 1 KB per 300 frames with every effect running", function()
	local W = session()
	local App = open_ready(W)
	local hud, combat, sim = App.hud, App.combat, App.sim
	local hf = hud.hitfx
	combat:apply_hot(5, 600, 1)
	combat:add_shield_stack(0)
	combat:apply_fire_shield(600, 1)
	W.ns.Debug.status(App.run, combat, "curse")
	combat.player_health = math.floor(combat.player_max_health * 0.2)
	local function storm()
		hf:dev("pop_shield", sim.now)
		hf:dev("pop_hot", sim.now)
		hf:dev("tele_plain", sim.now)
		hf:dev("chip_player", sim.now)
		hf:dev("heal", sim.now)
		hf:dev("score", sim.now)
		hf:dev("enter", sim.now)
		hf:dev("death", sim.now)
		hf:dev("phase", sim.now)
		hf:dev("shatter_curse", sim.now)
		hf:dev("block", sim.now)
	end
	for _ = 1, 10 do -- warm every pool slot (the first use of a texture creates its fields in the stub)
		storm()
		frames(W, 20)
		storm()
		storm()
		frames(W, 20)
	end
	frames(W, 150)
	local regions, nframes = W.regions, #W.frames
	local fake = {}
	local ui_kb, n = 0, 0
	local function frame()
		W.wall = W.wall + DT
		n = n + 1
		sim:tick(DT)
		if n % 25 == 1 then storm() end
		local k = collectgarbage("count")
		hud:update()
		ui_kb = ui_kb + collectgarbage("count") - k
	end
	alloc_kb(frame, 300, function() ui_kb = 0 end)
	T.ok(hf.icon_by_id.hot.on and hf.low_glow.shown and hud.juice:busy() > 0, "effects live during the measurement")
	T.ok(ui_kb < 1, ("HitFx + view allocate < 1 KB per 300 frames (got %.2f KB)"):format(ui_kb))
	T.eq(W.regions, regions, "no texture / mask / font string created")
	T.eq(#W.frames, nframes, "no frame created")
	T.ok(fake ~= nil and #W.errors == 0, "no errors")
end)

-- W1-G2: heal feedback by source (the Amber HoT ticks every second; the heal ult is the big one)
T.case("heal feedback by source: tick = float + HP flash only, ult = streak + ring, boss silent, Heal Block rate limit", function()
	local W = session()
	local App = open_ready(W)
	local hud, combat, sim = App.hud, App.combat, App.sim
	local jc = hud.juice
	local streaks, rings = 0, 0
	local orig_streak = hud._streak_to_player
	hud._streak_to_player = function(self, ...) streaks = streaks + 1 return orig_streak(self, ...) end
	local orig_ring = jc.ring
	jc.ring = function(self, ...) rings = rings + 1 return orig_ring(self, ...) end
	local function live(text)
		local n = 0
		for i = 1, #hud.pops_player do
			if hud.pops_player[i].text == text and hud.pops_player[i].t0 ~= nil then n = n + 1 end
		end
		return n
	end
	frames(W, 1)
	-- a HoT tick: a small float and the flash, no streak, no ring
	sim:emit("player_healed", 50, "hot")
	frames(W, 1)
	T.eq(live("+50"), 1, "tick: the number")
	T.ok(hud.hitfx.heal_tex.shown and hud.hitfx.heal_tex.alpha > 0, "tick: the HP bar flash")
	T.eq(streaks, 0, "tick: no streak")
	T.eq(rings, 0, "tick: no ring")
	-- the ult: number, streak, ring
	sim:emit("player_healed", 1500, "ult")
	frames(W, 1)
	T.eq(live("+1500"), 1, "ult: the number")
	T.eq(streaks, 1, "ult: a streak to the player bar")
	T.ok(rings >= 1, "ult: the ring")
	-- the boss heal is celebrated later, not by the event
	sim:emit("player_healed", 2500, "boss")
	frames(W, 1)
	T.eq(live("+2500"), 0, "boss heal: no number at the event")
	-- a heal that lands after the killing blow still shows
	combat.fight_over = true
	sim:emit("player_healed", 50, "hot")
	sim:emit("player_healed", 1500, "ult")
	frames(W, 1)
	T.eq(live("+50"), 2, "tick after the kill still shows")
	T.eq(live("+1500"), 2, "ult after the kill still shows")
	combat.fight_over = false
	-- Heal Block: one message per 3 s however many ticks are blocked
	sim:emit("heal_blocked")
	sim:emit("heal_blocked")
	frames(W, 30)
	sim:emit("heal_blocked")
	T.eq(live("Heal blocked"), 1, "rate limited: one float within 3 s")
	frames(W, 170)
	sim:emit("heal_blocked")
	frames(W, 1)
	T.ok(live("Heal blocked") >= 1, "a new float after 3 s")
	T.eq(#W.errors, 0, "no errors")
end)

T.done()
