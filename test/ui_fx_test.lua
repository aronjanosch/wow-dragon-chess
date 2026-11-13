-- W0-P3 test: per-event sounds (Assets.SOUNDS: slot per event, rate limit, quiet / sound-off gate, cut-off,
-- fallbacks), spell effect models (ui/fx.lua: pool cap, targets, stop on hide / pause / menu / game over,
-- model failures), creature animation ids per event, and sanity of the asset tables.
-- Loads the addon in TOC order under test/wow_stubs.lua like ui_smoke.
local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "."
local T = dofile(dir .. "/t.lua")
local loader = dofile(dir .. "/loader.lua")
local Stubs = dofile(dir .. "/wow_stubs.lua")
T.start("ui_fx_test")

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

local function session(setup)
	local W = Stubs.new()
	if setup then setup(W) end
	local ns = {}
	for _, f in ipairs(toc_files) do W.load(addon_dir .. f, ADDON, ns) end
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
	-- warm-up: the full collect above can shrink the Lua stack and the first calls regrow it (a one-off ~1 KB that
	-- depends on a function's frame size, not on steady-state per-frame garbage); reset() clears the caller's sums
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

-- Sounds played since index n: { {id, kind}, ... }.
local function since(W, n)
	local out = {}
	for i = n + 1, #W.sounds do out[#out + 1] = { W.sounds[i], W.sound_kinds[i] } end
	return out
end

-- Visible effect frames of the HUD's pool (one-shots and holds).
local function visible_fx(hud)
	local out = {}
	for i = 1, #hud.fx.shots do
		local f = hud.fx.shots[i]
		if f.shown then out[#out + 1] = f end
	end
	for _, f in pairs(hud.fx.holds) do
		if f.shown then out[#out + 1] = f end
	end
	return out
end
local function fx_with_model(hud, m2)
	for _, f in ipairs(visible_fx(hud)) do
		if f.model_file == m2 then return f end
	end
	return nil
end
local function player_models(W)
	local n = 0
	for _, f in ipairs(W.frames) do
		if f.ftype == "PlayerModel" then n = n + 1 end
	end
	return n
end

---------------------------------------------------------------- asset tables

T.case("asset tables: every referenced key exists, ids are numbers, every ability has a sound and an effect", function()
	local W = session()
	local ns = W.ns
	local A = ns.Assets
	local n_slots = 0
	for key, slot in pairs(A.SOUNDS) do
		n_slots = n_slots + 1
		T.ok(type(key) == "string", "slot key is a string: " .. tostring(key))
		local has_kit, has_file = slot.kit ~= nil, slot.file ~= nil
		T.ok(not (has_kit and has_file), key .. ": kit or file, not both")
		if has_file then T.ok(type(slot.file) == "number", key .. ": file is a FileDataID number") end
		if has_kit then
			local k = type(slot.kit) == "table" and slot.kit or { slot.kit }
			T.ok(#k > 0, key .. ": kit list not empty")
			for _, v in ipairs(k) do T.ok(type(v) == "number" or type(v) == "string", key .. ": kit entry number or SOUNDKIT name") end
		end
		if slot.max ~= nil then T.ok(type(slot.max) == "number" and slot.max > 0, key .. ": max seconds") end
		if slot.gap ~= nil then T.ok(type(slot.gap) == "number" and slot.gap > 0, key .. ": gap seconds") end
		if slot.fallback ~= nil then
			local fb = slot.fallback
			T.ok((fb.kit ~= nil) ~= (fb.file ~= nil), key .. ": fallback is a kit slot or a file slot (class variant -> template)")
		end
		T.ok(has_kit or has_file or slot.creature, key .. ": plays something (or is a creature slot)")
	end
	T.ok(n_slots >= 20, "sound slots present: " .. n_slots)
	for _, key in ipairs({ "open", "close", "click", "ability", "ult", "cleared", "defeat", "gem_break", "miss", "blocked",
		"player_hit", "enemy_attack", "enemy_death" }) do
		T.ok(A.SOUNDS[key] ~= nil, "slot exists: " .. key)
	end
	T.eq(A.SOUNDS.gem_break.kit, 2561, "gem break = SoundKit 2561 Nature Cast")
	T.eq(A.SOUNDS.blocked.kit, 132, "blocked = SoundKit 132")
	T.eq(A.SOUNDS.miss.kit, 139, "miss = SoundKit 139")
	T.ok(A.SOUNDS.player_hit.fallback ~= nil, "player hit has a documented fallback")
	T.ok(A.SOUNDS.enemy_wound == nil, "no creature wound (hurt) slot (W0-P3.1)")
	T.eq(A.SOUNDS.player_hit.channel, "Ambience", "player hit on the Ambience channel")
	T.eq(A.SOUNDS.enemy_attack.channel, "Ambience", "creature attack on the Ambience channel")
	T.ok(A.SOUNDS.enemy_death.channel == nil and A.SOUNDS.gem_break.channel == nil, "death + UI stay on the default channel")

	local ids = {}
	for _, ab in pairs(ns.Abilities) do
		if type(ab) == "table" and type(ab.id) == "string" and ab.tier ~= nil and ab.template == ab.id then ids[#ids + 1] = ab end -- canonical definitions (class variants: class_test)
	end
	T.eq(#ids, 12, "twelve player abilities")
	for _, ab in ipairs(ids) do
		local skey = A.ABILITY_KEY[ab.id]
		T.ok(skey ~= nil and A.SOUNDS[skey] ~= nil and type(A.SOUNDS[skey].file) == "number", ab.id .. ": own sound (file id)")
		local fx = A.FX[ab.id]
		T.ok(fx ~= nil and type(fx.m2) == "number", ab.id .. ": own effect (m2 id)")
		T.ok(A.ICONS[ab.icon] ~= nil, ab.id .. ": icon exists")
		T.eq(A.SOUNDS[skey].key == true, ab.tier == 2, ab.id .. ": ults are key sounds in quiet mode, skills are not")
	end
	local targets = { enemy = true, player = true, board = true, cell = true, cone = true, row = true }
	for key, fx in pairs(A.FX) do
		T.ok(type(fx.m2) == "number", key .. ": m2 FileDataID")
		T.ok(targets[fx.at], key .. ": known target " .. tostring(fx.at))
		T.ok(fx.size == nil or type(fx.size) == "number", key .. ": size")
		T.ok(fx.duration == nil or type(fx.duration) == "number", key .. ": duration")
		T.ok(fx.offset == nil or #fx.offset == 3, key .. ": offset {x, y, z}")
		T.ok(fx.px == nil or #fx.px == 2, key .. ": px {dx, dy}")
	end
	for name, key in pairs(A.FX_HOLD) do T.ok(A.FX[key] ~= nil, "hold " .. name .. " -> FX." .. key) end
	T.ok(A.FX.enemy_hit ~= nil, "enemy hit effect")
	for k, v in pairs(A.ANIM) do T.ok(type(v) == "number", "ANIM." .. k .. " is a number") end

	for _, def in ipairs(ns.EnemyData.list) do
		for _, f in ipairs({ "attack_sound", "wound_sound", "death_sound" }) do
			T.ok(def[f] == nil or type(def[f]) == "number", def.id .. "." .. f .. " is a FileDataID or absent")
		end
		T.ok(def.attack_sound ~= nil or def.wound_sound ~= nil, def.id .. ": at least one creature sound")
		T.ok(A.ENEMY[def.display] ~= nil, def.id .. ": presentation entry")
	end
	T.eq(ns.EnemyData.by_id.hellhound.attack_sound, 600668, "Hellhound attack sound")
	T.eq(ns.EnemyData.by_id.hellhound.death_sound, 600677, "Hellhound death sound")
end)

---------------------------------------------------------------- sounds per event

T.case("sound slots per event, rate limit, creature sounds", function()
	local W = session()
	local App = open_ready(W)
	local sim, A = App.sim, W.ns.Assets
	local n = #W.sounds

	-- gem break: SoundKit 101 on gems_cleared, rate-limited (one per wave, not per gem). The clear also
	-- damages the enemy (wound creature sound), so count the kit sounds only.
	local function breaks(list)
		local c = 0
		for _, s in ipairs(list) do
			if s[1] == 2561 and s[2] == "kit" then c = c + 1 end
		end
		return c
	end
	sim:emit("match_resolved", 3, {}, 1)
	sim:emit("match_resolved", 3, {}, 1)
	T.eq(breaks(since(W, n)), 1, "two matches in the same instant: one gem-break sound (kit 101, gap)")
	n = #W.sounds
	W.wall = W.wall + 0.2
	sim:emit("match_resolved", 3, {}, 1)
	T.eq(breaks(since(W, n)), 1, "after the gap: plays again")
	local got
	W.wall = W.wall + 1

	-- miss / blocked / reflected
	n = #W.sounds
	sim:emit("swap_rejected")
	got = since(W, n)
	T.ok(#got == 1 and got[1][1] == 139, "swap rejected = kit 139")
	n = #W.sounds
	sim:emit("attack_blocked")
	sim:emit("attack_reflected", 10)
	got = since(W, n)
	T.ok(#got == 2 and got[1][1] == 132 and got[2][1] == 132, "blocked / reflected = kit 132")

	-- player hit: a file sound, with the kit 129 fallback when PlaySoundFile fails
	n = #W.sounds
	sim:emit("player_damaged", 100, "hit")
	got = since(W, n)
	T.ok(#got == 1 and got[1][1] == 567867 and got[1][2] == "file", "player hit = file 567867")
	W.fail_sound_file = true
	n = #W.sounds
	sim:emit("player_damaged", 100, "hit")
	got = since(W, n)
	T.ok(#got == 1 and got[1][1] == 129 and got[1][2] == "kit", "PlaySoundFile fails: fallback kit 129")
	W.fail_sound_file = false

	-- abilities by id: each its own file sound; bombs / unknown ids keep the generic skill / ult sound
	for _, id in ipairs({ "flamestrike", "fire_shield", "arcane_explosion", "frost_nova", "whirlwind", "chain_lightning",
		"drain_life", "polymorph", "hammer_of_justice", "mind_control", "power_word_shield", "rain_of_fire" }) do
		n = #W.sounds
		sim:emit("ability_triggered", { id = id, toast = id, blurb = "", icon = id, tier = 1, col = 3, row = 3 })
		got = since(W, n)
		T.ok(#got == 1 and got[1][2] == "file" and got[1][1] == A.SOUNDS[A.ABILITY_KEY[id]].file, id .. ": its own sound")
	end
	n = #W.sounds
	sim:emit("ability_triggered", { id = "bomb", toast = "BOMB", blurb = "", icon = "bomb", tier = 0, is_bomb = true })
	got = since(W, n)
	T.ok(#got == 1 and got[1][2] == "kit", "bomb: generic ult sound")
	n = #W.sounds
	sim:emit("ability_triggered", { toast = "X", blurb = "", icon = "bomb", tier = 1 })
	T.eq(#since(W, n), 1, "ability without an id: generic skill sound")

	-- creature sounds from the enemy def (Hellhound): windup = attack, damage = wound (throttled), defeat = death
	local def = App.combat.enemy.def
	n = #W.sounds
	sim:emit("enemy_windup", def.rotation[1], 8 / 12)
	got = since(W, n)
	T.ok(#got == 1 and got[1][1] == def.attack_sound and got[1][2] == "file", "windup: attack_sound")
	T.eq(W.sound_channel, "Ambience", "the creature attack plays on the Ambience channel (W0-P3.1)")
	n = #W.sounds
	sim:emit("enemy_damaged", 10, false)
	sim:emit("enemy_damaged", 10, false)
	W.wall = W.wall + 0.5
	sim:emit("enemy_damaged", 10, false)
	T.eq(#since(W, n), 0, "damage: no creature wound sound at all (W0-P3.1)")
	n = #W.sounds
	sim:emit("player_damaged", 100, "hit")
	got = since(W, n)
	T.ok(#got == 1 and got[1][1] == 567867 and W.sound_channel == "Ambience", "player hit: file sound on the Ambience channel")
	n = #W.sounds
	A.play("gem_break")
	T.eq(W.sound_channel, "SFX", "gem break stays on SFX")
	W.wall = W.wall + 1
	n = #W.sounds
	sim:emit("enemy_defeated", App.combat.enemy)
	got = since(W, n)
	T.ok(#got == 1 and got[1][1] == def.death_sound, "defeat: only the death sound at the kill (W0-P11)")
	n = #W.sounds
	frames(W, 70) -- kill + 1.0 s: the CLEARED sting
	got = since(W, n)
	T.ok(#got == 1 and got[1][2] == "kit", "CLEARED sting after the 1.0 s death beat")

	-- an enemy without a field is silent for that event (Ouro has no attack sound; its wound sound stays unused)
	slash(W, "fight ouro")
	frames(W, 2)
	def = App.combat.enemy.def
	T.ok(def.id == "ouro" and def.attack_sound == nil and def.wound_sound ~= nil, "Ouro: wound sound in the data only")
	n = #W.sounds
	sim = App.sim
	sim:emit("enemy_windup", def.rotation[1], 0.6)
	T.eq(#since(W, n), 0, "no attack_sound: silent")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("sound gate: quiet mode classes, sound off, cut-off after max, stop on hide", function()
	local W = session()
	local App = open_ready(W)
	local sim, A = App.sim, W.ns.Assets
	local def = App.combat.enemy.def

	A.quiet = true
	local n = #W.sounds
	sim:emit("gems_cleared", { [0] = 3 }, { 0 })
	sim:emit("swap_rejected")
	sim:emit("ability_triggered", { id = "flamestrike", toast = "F", blurb = "", icon = "flamestrike", tier = 1, col = 1, row = 1 })
	sim:emit("enemy_windup", def.rotation[1], 0.6)
	sim:emit("enemy_damaged", 5, false)
	T.eq(#since(W, n), 0, "quiet: gem break / miss / skill / creature sounds silent")
	sim:emit("ability_triggered", { id = "frost_nova", toast = "F", blurb = "", icon = "frost_nova", tier = 2, col = 1, row = 1 })
	sim:emit("player_damaged", 50, "hit")
	sim:emit("attack_blocked")
	T.eq(#since(W, n), 3, "quiet: ult sound, player hit, blocked still play")
	A.quiet = false

	A.sound_enabled = false
	n = #W.sounds
	sim:emit("gems_cleared", { [0] = 3 }, { 0 })
	sim:emit("player_damaged", 50, "hit")
	sim:emit("enemy_windup", def.rotation[1], 0.6)
	T.eq(#since(W, n), 0, "sound off: nothing plays")
	A.sound_enabled = true

	-- cut-off: a file sound is stopped after its max (default 1.5 s) by the HUD frames
	W.wall = W.wall + 1
	n = #W.sounds
	local function stopped(h)
		for _, s in ipairs(W.stopped) do
			if s == h then return true end
		end
		return false
	end
	sim:emit("ability_triggered", { id = "drain_life", toast = "D", blurb = "", icon = "drain_life", tier = 1, col = 1, row = 1 })
	T.eq(#since(W, n), 1, "drain life sound played")
	local handle = W.next_handle
	frames(W, 30) -- 0.5 s
	T.ok(not stopped(handle), "not stopped before its max (1.2 s)")
	frames(W, 50) -- 1.33 s
	T.ok(stopped(handle), "stopped after max")
	T.eq(W.stop_fade, A.STOP_FADE_MS, "with a short fade")
	local stopped0 = #W.stopped

	-- hide / pause stop a running sound
	stopped0 = #W.stopped
	sim:emit("ability_triggered", { id = "polymorph", toast = "P", blurb = "", icon = "polymorph", tier = 2, col = 1, row = 1 })
	W.App.win.frame:Hide()
	T.ok(#W.stopped > stopped0, "hide stops running spell sounds")
	slash(W, "")
	stopped0 = #W.stopped
	sim:emit("ability_triggered", { id = "polymorph", toast = "P", blurb = "", icon = "polymorph", tier = 2, col = 1, row = 1 })
	App.soft_pause("test")
	T.ok(#W.stopped > stopped0, "soft pause stops running spell sounds")

	-- /dcsnd auditions a slot even in quiet mode, not with sound off
	App.soft_resume()
	A.quiet = true
	n = #W.sounds
	W.stubs.SlashCmdList.DCSND("ab_flamestrike")
	T.eq(#since(W, n), 1, "/dcsnd plays in quiet mode")
	W.stubs.SlashCmdList.DCSND("enemy_attack 600668")
	T.eq(#since(W, n), 2, "/dcsnd <slot> <file> auditions a creature file")
	W.stubs.SlashCmdList.DCSND("nope")
	W.stubs.SlashCmdList.DCSND("")
	T.eq(#since(W, n), 2, "unknown slot / list: silent")
	T.eq(#W.errors, 0, "no errors")
end)

---------------------------------------------------------------- effects

T.case("effects: per-ability model, pool cap, targets", function()
	local W = session()
	local App = open_ready(W)
	local sim, A, hud = App.sim, W.ns.Assets, App.hud
	local fx = hud.fx
	T.ok(fx.available, "effect pool available")
	local models0 = player_models(W)
	T.ok(models0 <= 1 + fx.SHOTS + 4, "frames: enemy model + pool (" .. models0 .. ")")
	T.eq(#visible_fx(hud), 0, "nothing shown at rest")

	for _, id in ipairs({ "flamestrike", "fire_shield", "arcane_explosion", "frost_nova", "whirlwind", "chain_lightning",
		"drain_life", "polymorph", "hammer_of_justice", "mind_control", "power_word_shield", "rain_of_fire" }) do
		fx:stop_all()
		sim:emit("ability_triggered", { id = id, toast = id, blurb = "", icon = id, tier = 1, col = 2, row = 5 })
		local f = fx_with_model(hud, A.FX[id].m2)
		T.ok(f ~= nil, id .. ": effect model " .. A.FX[id].m2 .. " shown")
		if f then
			T.eq(f.animation, 0, id .. ": anim 0")
			local at0 = A.FX[id].at
			local aw, ah
			if at0 == "enemy" then aw, ah = hud.enemy_holder:GetWidth(), hud.enemy_holder:GetHeight()
			elseif at0 == "player" then aw, ah = 256, 256
			else aw, ah = App.win.host:GetWidth(), App.win.host:GetHeight() end
			T.eq(f.w, aw, id .. ": unified frame width (play area / enemy frame)")
			T.eq(f.h, ah, id .. ": unified frame height")
			T.ok(math.abs(f.cam_scale - (A.FX[id].size or 192) / math.min(aw, ah)) < 1e-9, id .. ": camera shrinks the effect to its size")
			T.ok(f.cam_scale ~= nil and f.pos ~= nil and f.model_scale == 1 and f.rotation == 0, id .. ": framed with defaults")
			local at = A.FX[id].at
			if at == "enemy" then T.eq(f.rel, hud.enemy_holder, id .. ": on the enemy")
			elseif at == "player" then T.eq(f.rel, hud.player_bar, id .. ": on the player bar")
			else T.eq(f.rel, App.win.host, id .. ": on the board") end
		end
	end
	-- board targets: one unified frame size; W0-P7 A3: cell / row / cone follow the ability's gem cell (col 2, row 5),
	-- "board" stays centred on the play area
	for _, id in ipairs({ "arcane_explosion", "frost_nova", "whirlwind", "flamestrike" }) do
		fx:stop_all()
		sim:emit("ability_triggered", { id = id, toast = "A", blurb = "", icon = "x", tier = 1, col = 2, row = 5 })
		local f = fx_with_model(hud, A.FX[id].m2)
		local at = A.FX[id].at
		T.ok(f ~= nil and f.rel == App.win.host, id .. " on the board")
		if at == "board" then
			T.ok(f.x == 0 and f.y == 0 and f.point == "CENTER", id .. " centred on the play area")
		else
			T.eq(f.point, "CENTER", id .. " centre-anchored")
			T.eq(f.rpoint, "TOPLEFT", id .. " placed against the board's top-left")
			local cell = 64
			local size = A.FX[id].size
			if at == "cell" then
				T.ok(f.x == 2.5 * cell and f.y == -5.5 * cell, id .. " centred on its cell")
			elseif at == "row" then
				T.ok(f.x == f.w / 2 and f.y == -5.5 * cell, id .. " centred on its row, full width kept")
			else
				T.ok(math.abs(f.x - (2.5 * cell + size * fx.CONE_SHIFT)) < 1e-9 and f.y == -5.5 * cell, id .. " cone starts at the cell, points right")
			end
		end
	end
	-- no col / row: the old centred placement for every board target
	for _, id in ipairs({ "arcane_explosion", "whirlwind", "flamestrike" }) do
		fx:stop_all()
		fx:play(id, nil, nil, sim.now)
		local f = fx_with_model(hud, A.FX[id].m2)
		T.ok(f ~= nil and f.point == "CENTER" and f.rpoint == "CENTER" and f.x == 0 and f.y == 0, id .. " without col / row: centred")
	end

	-- hard cap: many events never create frames and never show more than SHOTS at once
	fx:stop_all()
	for i = 1, 40 do
		sim:emit("ability_triggered", { id = (i % 2 == 0) and "frost_nova" or "polymorph", toast = "A", blurb = "", icon = "x", tier = 2, col = i % 8, row = i % 8 })
	end
	T.ok(#visible_fx(hud) <= fx.SHOTS, "pool cap: at most " .. fx.SHOTS .. " one-shots visible (" .. #visible_fx(hud) .. ")")
	T.eq(player_models(W), models0, "no frame created while playing")

	-- sim-time lifetime: effects end after their duration, only while the sim runs
	fx:stop_all()
	sim:emit("ability_triggered", { id = "polymorph", toast = "P", blurb = "", icon = "x", tier = 2, col = 1, row = 1 })
	frames(W, 30)
	T.ok(fx_with_model(hud, A.FX.polymorph.m2) ~= nil, "still shown after 0.5 s")
	frames(W, 60)
	T.ok(fx_with_model(hud, A.FX.polymorph.m2) == nil, "gone after its duration (1.2 s)")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("effects: enemy hit replaces the red disc, state effects follow the statuses", function()
	local W = session()
	local App = open_ready(W)
	local A, hud, combat = W.ns.Assets, App.hud, App.combat
	slash(W, "fight hellhound") -- no own Aegis / stun
	combat = App.combat
	frames(W, 2)
	combat:deal_damage_to_enemy(100)
	combat:deal_damage_to_enemy(100) -- lands at the same instant: inside the gap, throttled
	frames(W, fly_frames(W)) -- the streak (Juice.FLY) lands first (W0-P6): the hit reaction waits for it
	T.ok(fx_with_model(hud, A.FX.enemy_hit.m2) ~= nil, "hit effect model on the enemy")
	T.eq(hud.hit_glow.alpha, 0, "no red disc while the hit effect shows")
	T.ok(hud.punch > 1, "the punch stays")
	T.eq(hud.hit_glow.alpha, 0, "throttled hit: still no disc")

	-- stun stars while stunned, gone when it ends; the stun pose is covered below
	combat.enemy:apply_stun(1, "stun")
	frames(W, 1)
	local stars = fx_with_model(hud, A.FX.stun_stars.m2)
	T.ok(stars ~= nil, "stun stars above the enemy")
	T.ok(stars.rel == hud.enemy_holder and stars.y == A.FX.stun_stars.px[2], "stars offset above the enemy centre")
	local visible = #visible_fx(hud)
	frames(W, 20)
	T.eq(#visible_fx(hud), visible, "held while stunned (not re-created)")
	T.ok(frames_until(W, function() return fx_with_model(hud, A.FX.stun_stars.m2) == nil end, 120), "stars gone when the stun ends")

	-- freeze
	combat.enemy:apply_stun(1, "freeze")
	frames(W, 1)
	T.ok(fx_with_model(hud, A.FX.freeze.m2) ~= nil, "freeze effect on the enemy")
	T.ok(fx_with_model(hud, A.FX.stun_stars.m2) == nil, "no stars on a freeze")
	T.ok(frames_until(W, function() return fx_with_model(hud, A.FX.freeze.m2) == nil end, 120), "freeze effect gone")

	-- Divine Aegis / Mirror Shield
	combat.enemy:apply_spell_immunity(1)
	frames(W, 1)
	T.ok(fx_with_model(hud, A.FX.aegis.m2) ~= nil, "Aegis effect")
	T.ok(frames_until(W, function() return fx_with_model(hud, A.FX.aegis.m2) == nil end, 120), "Aegis effect gone")
	combat.enemy:apply_mirror_shield(2, 0.6, 500, 1)
	frames(W, 1)
	T.ok(fx_with_model(hud, A.FX.mirror.m2) ~= nil, "Mirror effect")
	combat.enemy:add_mirror_crack(600) -- shatters
	frames(W, 1)
	T.ok(fx_with_model(hud, A.FX.mirror.m2) == nil, "Mirror effect gone when shattered")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("effects stop on hide, soft pause, menu, game over; none starts while the sim is frozen", function()
	local function playing(W)
		local App = open_ready(W)
		App.sim:emit("ability_triggered", { id = "frost_nova", toast = "F", blurb = "", icon = "x", tier = 2, col = 1, row = 1 })
		App.combat.enemy:apply_stun(5, "stun")
		frames(W, 1)
		T.ok(#visible_fx(App.hud) >= 2, "effects playing (one-shot + stars)")
		return App
	end
	local W = session()
	local App = playing(W)
	App.win.frame:Hide()
	T.eq(#visible_fx(App.hud), 0, "hide: no effect frame stays shown")
	T.eq(App.hud.fx:active_count(), 0, "hide: pool idle")
	slash(W, "")
	frames(W, 1)
	T.ok(#visible_fx(App.hud) >= 1, "reopen: the stars come back with the next frame")

	W = session()
	App = playing(W)
	App.soft_pause("test")
	T.eq(#visible_fx(App.hud), 0, "soft pause: effects hidden")
	-- the sim is frozen: a status starting now shows nothing until the game runs again
	App.combat.enemy:apply_stun(5, "freeze")
	frames(W, 30)
	T.eq(#visible_fx(App.hud), 0, "soft pause: nothing plays while frozen")
	App.soft_resume()
	frames(W, 1)
	T.ok(fx_with_model(App.hud, W.ns.Assets.FX.freeze.m2) ~= nil, "resume: the freeze effect is back")

	W = session()
	App = playing(W)
	App.open_menu()
	T.eq(#visible_fx(App.hud), 0, "menu open: effects hidden")
	frames(W, 20)
	T.eq(#visible_fx(App.hud), 0, "menu open: nothing plays")
	App.close_menu()

	W = session()
	App = playing(W)
	App.combat.player_health = 1
	App.hud.fx:stop_all()
	T.ok(frames_until(W, function() return App.combat.game_over end, 2400), "player dies")
	T.eq(#visible_fx(App.hud), 0, "game over: no effects")
	frames(W, 30)
	T.eq(#visible_fx(App.hud), 0, "game over: still none")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("effect failures: SetModel errors / unloadable models / no PlayerModel", function()
	local A
	local W = session(function(w)
		w.error_models[165559] = true -- enemy hit: SetModel raises
		w.bad_models[165961] = true -- shield: loads nothing
	end)
	local App = open_ready(W)
	A = W.ns.Assets
	local hud = App.hud
	App.combat:deal_damage_to_enemy(100)
	frames(W, fly_frames(W))
	T.ok(fx_with_model(hud, 165559) == nil, "no hit model")
	T.ok(hud.hit_glow.alpha > 0, "red disc stays as the fallback")
	App.sim:emit("ability_triggered", { id = "power_word_shield", toast = "S", blurb = "", icon = "x", tier = 1 })
	T.ok(fx_with_model(hud, 165961) == nil, "model that loads nothing is hidden")
	App.combat.enemy:apply_spell_immunity(1)
	frames(W, 5)
	T.eq(#W.errors, 0, "no errors")
	T.ok(hud.fx.holds.aegis.failed, "failed hold is not retried every frame")

	-- no PlayerModel frame type at all: no effects, no animation, no errors, sounds still play
	W = session(function(w) w.fail_frame_types.PlayerModel = true end)
	App = open_ready(W)
	hud = App.hud
	T.ok(not hud.fx.available and hud.fx.shots[1] == nil, "no effect pool")
	local n = #W.sounds
	App.sim:emit("ability_triggered", { id = "frost_nova", toast = "F", blurb = "", icon = "x", tier = 2, col = 1, row = 1 })
	App.combat:deal_damage_to_enemy(100)
	App.combat.enemy:apply_stun(1, "stun")
	frames(W, fly_frames(W, true)) -- the ult's heavier streak flies FLY * FLY_HEAVY
	T.ok(#W.sounds > n, "sounds still play without models")
	T.ok(hud.hit_glow.alpha > 0, "red disc without effect models")
	T.eq(#W.errors, 0, "no errors")
end)

---------------------------------------------------------------- creature animation

T.case("creature animation: stand, attack at the wind-up, wound, stun pose, death", function()
	local W = session()
	local App = open_ready(W)
	local hud, sim, combat = App.hud, App.sim, App.combat
	local m = hud.model
	T.eq(m.animation, 0, "idle on show")
	local def = combat.enemy.def
	combat.enemy:delay_attack(1000) -- the enemy's own wind-ups would interleave with the animations below

	-- attack animation at the wind-up (17), back to idle after the wind-up + tail
	sim:emit("enemy_windup", def.rotation[1], 8 / 12)
	frames(W, 1)
	T.eq(m.animation, 17, "wind-up: attack animation 17")
	frames(W, 30)
	T.eq(m.animation, 17, "held through the wind-up")
	T.ok(frames_until(W, function() return m.animation == 0 end, 90), "back to idle after the attack")

	-- the attack falls back to 16 when 17 is rejected
	W.error_animations = { [17] = true }
	sim:emit("enemy_windup", def.rotation[1], 8 / 12)
	frames(W, 1)
	T.eq(m.animation, 16, "attack animation falls back to 16")
	W.error_animations = nil
	T.ok(frames_until(W, function() return m.animation == 0 end, 90), "idle again")

	-- wound (8): throttled, then back to idle
	local calls = #m.anim_log
	combat:deal_damage_to_enemy(50)
	frames(W, fly_frames(W) + 2)
	T.eq(m.animation, 8, "damage: wound animation 8")
	combat:deal_damage_to_enemy(50)
	frames(W, 14)
	T.eq(#m.anim_log, calls + 1, "a second hit inside the throttle does not restart it")
	T.ok(frames_until(W, function() return m.animation == 0 end, 60), "wound ends, idle again")

	-- a wound does not cut an attack in progress
	sim:emit("enemy_windup", def.rotation[1], 8 / 12)
	frames(W, 1)
	W.wall = W.wall + 1
	combat:deal_damage_to_enemy(50)
	frames(W, 14)
	T.eq(m.animation, 17, "attack beats wound")
	T.ok(frames_until(W, function() return m.animation == 0 end, 120), "idle")

	-- stun pose (14) while stunned, idle after
	combat.enemy:apply_stun(1, "stun")
	frames(W, 1)
	T.eq(m.animation, 14, "stun pose 14")
	T.ok(frames_until(W, function() return m.animation == 0 end, 120), "idle after the stun")

	-- death (1) at the kill, shown until the fade
	local first = combat.enemy
	first:take_damage(first.current_health)
	frames(W, 1)
	T.eq(m.animation, 1, "death animation 1")
	frames(W, 20)
	T.eq(m.animation, 1, "stays on the death animation")
	T.ok(hud.enemy_holder.alpha > 0, "figure still visible while it dies")
	T.ok(frames_until(W, function() return combat.enemy ~= first end, 300), "next fight")
	frames(W, 2)
	T.eq(m.animation, 0, "next enemy: idle again")
	T.eq(#W.errors, 0, "no errors")

	-- portrait fallback: no model, no animation calls, no errors
	W = session(function(w) w.fail_frame_types.PlayerModel = true end)
	App = open_ready(W)
	App.sim:emit("enemy_windup", App.combat.enemy.def.rotation[1], 0.6)
	App.combat:deal_damage_to_enemy(50)
	frames(W, 5)
	T.ok(App.hud.model == nil and App.hud.portrait:IsShown(), "portrait fallback shown")
	T.eq(#W.errors, 0, "portrait fallback: no errors")
end)

---------------------------------------------------------------- budgets

T.case("no steady-state allocation: effects, holds, animation and sound cut-offs", function()
	local W = session()
	local App = open_ready(W)
	local hud = App.hud
	App.combat.enemy:apply_stun(60, "stun") -- a held effect + stun pose for the whole measurement
	App.sim:emit("ability_triggered", { id = "frost_nova", toast = "F", blurb = "", icon = "x", tier = 2, col = 1, row = 1 })
	frames(W, 2)
	T.ok(#visible_fx(hud) >= 2, "effects live during the measurement")
	W.wall = W.wall + 10 -- pending sound cut-offs fire now (the stub's StopSound log would count as garbage)
	W.ns.Assets.tick()
	frames(W, 45) -- the one-off model re-frame after a load is done (budget is for steady state)
	-- Steady-state garbage shows in every pass; a one-off (a table rehash, whose timing depends on memory addresses,
	-- failed this check about once in 15 runs) does not: measure up to three passes and keep the smallest.
	local ui_kb, grown = math.huge, 0
	for _ = 1, 3 do
		local pass_kb = 0
		grown = alloc_kb(function()
			W.wall = W.wall + DT
			local k = collectgarbage("count")
			hud:update()
			pass_kb = pass_kb + collectgarbage("count") - k
		end, 300, function() pass_kb = 0 end)
		if pass_kb < ui_kb then ui_kb = pass_kb end
		if ui_kb < 1 then break end
	end
	T.ok(ui_kb < 1, ("HUD update with effects live allocates < 1 KB per 300 frames (got %.2f KB; total %.2f KB)"):format(ui_kb, grown))
	T.eq(#W.errors, 0, "no errors")
end)

---------------------------------------------------------------- W0-P5 feel

local function live_pops(pool)
	local out = {}
	for i = 1, #pool do
		if pool[i].shown then out[#out + 1] = pool[i] end
	end
	return out
end
local function played(W, n, id)
	for i = n + 1, #W.sounds do
		if W.sounds[i] == id then return true end
	end
	return false
end
local function gems_at(cells)
	local g = {}
	for i, c in ipairs(cells) do g[i] = { x = c[1], y = c[2] } end
	return g
end

T.case("W0-P5 match feedback: text float at the match, sound by length, cascade slot, pooled", function()
	local W = session()
	local App = open_ready(W)
	local hud, sim, A = App.hud, App.sim, W.ns.Assets
	W.wall = W.wall + 5
	local nframes = #W.frames
	local pool = hud.pops_match
	T.eq(#pool, 8, "pool of 8 float strings")
	local n = #W.sounds
	sim:emit("match_resolved", 3, gems_at({ { 2, 3 }, { 3, 3 }, { 4, 3 } }), 1)
	local live = live_pops(pool)
	T.eq(#live, 1, "one float")
	T.ok(live[1].text:find("MATCH", 1, true) == 1 and live[1].text:find("+50", 1, true) ~= nil, "3-match text: " .. tostring(live[1].text))
	T.ok(live[1].x == 3 * 64 + 32 - 256 or live[1].x == (3 + 0.5) * 64 - 256, "centred on the match (x " .. tostring(live[1].x) .. ")")
	T.eq(live[1].y, 256 - (3 + 0.5) * 64, "centred on the match (y)")
	T.eq(#since(W, n), 2, "a plain 3-match plays the layered base sounds (nature + holy cast) only")
	W.wall = W.wall + 1
	sim:emit("match_resolved", 3, gems_at({ { 0, 0 }, { 1, 0 }, { 2, 0 } }), 2)
	T.ok(played(W, n, A.SOUNDS.match_cascade.file), "3-match in a chain: cascade slot")
	W.wall = W.wall + 1
	n = #W.sounds
	sim:emit("match_resolved", 4, gems_at({ { 1, 1 }, { 1, 2 }, { 1, 3 }, { 1, 4 } }), 1)
	T.ok(played(W, n, A.SOUNDS.match_4.file), "4-match sound")
	T.ok(live_pops(pool)[3].text:find("4-MATCH", 1, true) == 1 and live_pops(pool)[3].text:find("+125", 1, true) ~= nil, "4-MATCH +125")
	for len, slot in pairs({ [5] = "match_5", [6] = "match_6", [7] = "match_7", [9] = "match_7" }) do
		W.wall = W.wall + 1
		n = #W.sounds
		sim:emit("match_resolved", len, gems_at({ { 4, 4 } }), 1)
		T.ok(played(W, n, A.SOUNDS[slot].file), len .. "-match plays " .. slot)
	end
	T.ok(A.SOUNDS.match_4.file ~= A.SOUNDS.match_7.file, "longer matches use different (deeper) files, no pitch")
	-- pool cap, no new frames
	for _ = 1, 30 do sim:emit("match_resolved", 3, gems_at({ { 5, 5 } }), 1) end
	T.ok(#live_pops(pool) <= 8, "never more than the pool")
	T.eq(#W.frames, nframes, "no frame created while playing")
	-- expires on sim time
	frames(W, 80)
	T.eq(#live_pops(pool), 0, "floats end after their time")
	-- empty gem list does not crash
	sim:emit("match_resolved", 3, {}, 1)
	-- quiet mode: only key sounds
	A.quiet = true
	W.wall = W.wall + 1
	n = #W.sounds
	sim:emit("match_resolved", 5, gems_at({ { 4, 4 } }), 1)
	T.eq(#since(W, n), 0, "quiet mode: match sounds off")
	A.quiet = false
	T.eq(#W.errors, 0, "no errors")
end)

T.case("W0-P5 ability gem spawn: float with the name, sound, ult banner READY", function()
	local W = session()
	local App = open_ready(W)
	local hud, sim, A = App.hud, App.sim, W.ns.Assets
	W.wall = W.wall + 5
	local n = #W.sounds
	sim:emit("ability_gem_spawned", 2, 5, 1, 3) -- Ruby skill = Flamestrike
	local live = live_pops(hud.pops_match)
	T.eq(#live, 1, "float")
	T.eq(live[1].text, "FLAMESTRIKE", "ability name")
	T.ok(played(W, n, A.SOUNDS.ability_spawn_skill.file), "skill spawn sound")
	hud.banner_t0 = nil -- (the fight-start spawn banner is not what is under test)
	sim:emit("ability_gem_spawned", 2, 5, 1, 3)
	T.ok(hud.banner_t0 == nil, "a skill spawn shows no banner")
	W.wall = W.wall + 1
	n = #W.sounds
	sim:emit("ability_gem_spawned", 4, 4, 2, 3) -- Ruby ult = Fire Shield
	T.ok(played(W, n, A.SOUNDS.ability_spawn_ult.file), "ult spawn sound")
	T.eq(hud.banner.title.text, "FIRE SHIELD READY", "ult banner title")
	frames(W, 20)
	T.ok(hud.banner.alpha > 0, "banner visible")
	T.eq(hud.banner.title.tg, A.COLOR.BANNER_TITLE[2], "player banner colour")
	-- a real fuse spawns through the same event: debug spawn path
	local seen
	sim:on("ability_gem_spawned", function(...) seen = { ... } end)
	W.ns.Debug.spawn_gem(App.run, sim, 0, 1)
	T.ok(seen ~= nil and seen[3] == 1 and seen[4] == 0, "sim emits ability_gem_spawned for the dev spawn")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("W0-P5 enemy cast: flash on every cast, banner + sound only for specials", function()
	local W = session()
	local App = open_ready(W)
	local hud, sim, A = App.hud, App.sim, W.ns.Assets
	W.wall = W.wall + 5
	local n = #W.sounds
	sim:emit("enemy_ability_executed", { id = "x", name = "Plain Bite", is_special = false, kind = "plain", icon = "hellhound_bite", description = "d" })
	T.ok(hud.cast_t0 ~= nil, "flash started")
	frames(W, 2)
	T.ok(hud.cast_glow.alpha > 0, "cast glow visible")
	T.eq(#since(W, n), 0, "a plain hit: no cast sound")
	T.ok(hud.banner_t0 ~= nil, "(only the fight-start spawn banner runs)")
	hud.banner_t0 = nil
	sim:emit("enemy_ability_executed", { id = "x", name = "Plain Bite", is_special = false, kind = "plain", icon = "hellhound_bite", description = "d" })
	T.ok(hud.banner_t0 == nil, "a plain hit: no banner")
	frames(W, 40)
	T.eq(hud.cast_glow.alpha, 0, "flash ends")
	sim:emit("enemy_ability_executed", { id = "y", name = "Sand Trap", is_special = true, kind = "junk", icon = "ouro_trap", description = "Traps gems in junk" })
	T.eq(hud.banner.title.text, "SAND TRAP", "special: banner name")
	T.eq(hud.banner.blurb.text, "Traps gems in junk", "special: banner description")
	T.eq(hud.banner.title.tg, A.COLOR.BANNER_TITLE_ENEMY[2], "enemy banner colour")
	T.ok(played(W, n, A.SOUNDS.enemy_special.file), "special cast sound")
	T.eq(W.sound_channel, "Ambience", "special cast sound on Ambience")
	frames(W, 5)
	T.ok(hud.banner.alpha > 0, "banner visible")
	-- a nil ability must not crash
	sim:emit("enemy_ability_executed", nil)
	-- the real enemy emits it: a full fight frame loop stays error free
	frames(W, 600)
	T.eq(#W.errors, 0, "no errors")
end)

T.case("W0-P5 swap hint: rings on same-colour neighbours of a selected skill / ult gem, text, pooled", function()
	local W = session()
	local App = open_ready(W)
	local view, sim, input, Board = App.view, App.sim, App.input, W.ns.Board
	local board = sim.board
	local function setup(c, r, tier, tc)
		-- selected gem (c, r) of colour 2 with the given tier; neighbours: right + below colour 2, left + above colour 3
		local function put(cc, rr, t) Board.set_gem_type(board:get(cc, rr), t) end
		put(c, r, 2); put(c + 1, r, 2); put(c, r + 1, 2); put(c - 1, r, 3); put(c, r - 1, 3)
		local g = board:get(c, r)
		Board.set_tier(g, tier)
		return g
	end
	local nframes = #W.frames
	local g = setup(3, 3, 1)
	input.selected = g
	frames(W, 2)
	local shown = 0
	for _, r in ipairs(view.rings) do
		if r.shown then shown = shown + 1 end
	end
	T.eq(shown, 2, "two same-colour neighbours ringed")
	T.ok(view.hint_text.shown and view.hint_text.text == W.ns.BoardView.HINT_SKILL, "skill text: " .. tostring(view.hint_text.text))
	T.ok(view.hint_text.text:find("SKILL", 1, true) == 1, "text starts with SKILL")
	-- ult
	Board.set_tier(g, 2)
	frames(W, 2)
	T.ok(view.hint_text.text:find("ULT", 1, true) == 1, "ult text")
	-- deselect clears everything
	input.selected = nil
	frames(W, 2)
	shown = 0
	for _, r in ipairs(view.rings) do
		if r.shown then shown = shown + 1 end
	end
	T.eq(shown, 0, "rings hidden")
	T.ok(not view.hint_text.shown, "text hidden")
	-- a plain selected gem next to a same-colour ability gem: ring on that neighbour only, no text
	Board.set_tier(g, 0)
	Board.set_tier(board:get(4, 3), 1)
	input.selected = g
	frames(W, 2)
	shown = 0
	for _, r in ipairs(view.rings) do
		if r.shown then shown = shown + 1 end
	end
	T.eq(shown, 1, "plain selected: only the ability neighbour is ringed")
	T.ok(not view.hint_text.shown, "no text for a plain gem")
	-- a bomb is not hinted
	Board.set_tier(board:get(4, 3), 0)
	Board.set_bomb(g, true)
	frames(W, 2)
	T.ok(not view.hint_text.shown, "bomb: no text")
	Board.set_bomb(g, false)
	T.eq(#W.frames, nframes, "no frame created")
	-- allocation budget with a hint showing
	Board.set_tier(g, 1)
	input.selected = g
	frames(W, 2)
	local kb = alloc_kb(function() view:update(input) end, 300)
	T.ok(kb < 1, ("hint update allocates < 1 KB per 300 frames (got %.2f KB)"):format(kb))
	input.selected = nil
	T.eq(#W.errors, 0, "no errors")
end)

T.done()
