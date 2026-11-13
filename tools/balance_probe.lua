-- Headless balance probe (W1-G2): full runs WITHOUT god mode, two bot policies, human-like swap paces.
-- Not part of checks.sh. Works on the lifesteal kit (before W1-G2) and the HoT kit (after): the heal
-- source and the waste counters use whatever the events provide.
--
--   lua5.1 tools/balance_probe.lua [--seeds N] [--paces 0.6,0.9] [--diffs 1,2,3,4,5]
--                                      [--policies first,hold] [--fights] [--title "text"]
--
-- Policies: `first` = first legal move (scan order of Match.find_possible_move); `hold` = the same, but
-- while HP > 70 % it skips moves whose line would contain an Amber ult gem (a heal ult stays banked) if
-- another move exists. The "line" test is the plain 3-in-a-row check; region merging / area clears that
-- reach a banked gem by accident are NOT avoided (that is part of what the probe measures).
-- Deterministic: seeds 1..N, sim time only. Output: markdown on stdout.

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "."
local H = dofile(here .. "/../test/helpers.lua")
local ns = H.ns
local Sim, Combat, Match, Run = ns.Sim, ns.Combat, ns.Match, ns.Run

local DT = 1 / 30
local FIGHT_CAP = 400 -- sim seconds per fight; longer = timeout (counted as a loss)
local HOLD_ABOVE = 0.70
local LOW_HP = 0.60

---------------------------------------------------------------- options

local opt = { seeds = 30, paces = { 0.6, 0.9 }, diffs = { 1, 2, 3, 4, 5 }, policies = { "first", "hold" }, fights = false,
	title = "" }
local function list(s, conv)
	local out = {}
	for w in s:gmatch("[^,]+") do out[#out + 1] = conv(w) end
	return out
end
do
	local i = 1
	while i <= #arg do
		local a = arg[i]
		if a == "--seeds" then opt.seeds = tonumber(arg[i + 1]); i = i + 1
		elseif a == "--paces" then opt.paces = list(arg[i + 1], tonumber); i = i + 1
		elseif a == "--diffs" then opt.diffs = list(arg[i + 1], tonumber); i = i + 1
		elseif a == "--policies" then opt.policies = list(arg[i + 1], tostring); i = i + 1
		elseif a == "--title" then opt.title = arg[i + 1]; i = i + 1
		elseif a == "--fights" then opt.fights = true end
		i = i + 1
	end
end

---------------------------------------------------------------- policies

-- Would the line through (c, r) / (c2, r2) after the type swap contain an Amber ult gem?
local function line_has_amber_ult(board, c1, r1, c2, r2)
	local g1, g2 = board:get(c1, r1), board:get(c2, r2)
	g1.type, g2.type = g2.type, g1.type
	g1.tier, g2.tier = g2.tier, g1.tier
	local hit = false
	local function scan(c, r)
		local t = board:type_at(c, r)
		for _, d in ipairs({ { 1, 0 }, { 0, 1 } }) do
			local run = { { c, r } }
			for s = 1, -1, -2 do
				local k = 1
				while board:type_at(c + d[1] * k * s, r + d[2] * k * s) == t do
					run[#run + 1] = { c + d[1] * k * s, r + d[2] * k * s }
					k = k + 1
				end
			end
			if #run >= 3 then
				for i = 1, #run do
					local g = board:get(run[i][1], run[i][2])
					if g ~= nil and g.type == 0 and g.tier == 2 then hit = true end
				end
			end
		end
	end
	scan(c1, r1)
	scan(c2, r2)
	g1.type, g2.type = g2.type, g1.type
	g1.tier, g2.tier = g2.tier, g1.tier
	return hit
end

local function pick_move(board, policy, hp_ratio)
	if policy == "first" or hp_ratio <= HOLD_ABOVE then return Match.find_possible_move(board) end
	local first
	local cols, rows = board.cols, board.rows
	for col = 0, cols - 1 do
		for row = 0, rows - 1 do
			for k = 1, 2 do
				local c2, r2 = col, row
				if k == 1 then c2 = col + 1 else r2 = row + 1 end
				if c2 < cols and r2 < rows and Match.would_swap_match(board, col, row, c2, r2) then
					if first == nil then first = { col, row, c2, r2 } end
					if not line_has_amber_ult(board, col, row, c2, r2) then return col, row, c2, r2 end
				end
			end
		end
	end
	if first then return first[1], first[2], first[3], first[4] end
	return nil
end

---------------------------------------------------------------- one run

local function play(seed, diff, pace, policy)
	local sim = Sim.new({ seed = seed })
	local c = Combat.new({ sim = sim, seed = seed })
	local run = Run.new({ combat = c, difficulty = diff })
	local hot_id = c.status.hot and "hot" or "lifesteal" -- the Amber skill's status
	local R = {
		fights = {}, heal = { hot = 0, ult = 0, boss = 0, lifesteal = 0 }, lost_overheal = 0, lost_block = 0,
		blocked_events = 0, skills = 0, ults = 0, ults_low = 0, ults_n = 0, dead_fight = nil, timeout = false,
		hot_time = 0, fight_time = 0,
	}
	local cur
	local unk = 0 -- heals without a source (old code): lifesteal unless run_advanced says boss
	sim:on("run_fight_starting", function(_, def)
		cur = { id = def.id, t0 = sim.now, taken = 0, minhp = c.player_health, hp1 = nil, won = false, heal = 0 }
		R.fights[#R.fights + 1] = cur
	end)
	c:on("player_damaged", function(a)
		if cur then
			cur.taken = cur.taken + a
			if c.player_health < cur.minhp then cur.minhp = c.player_health end
		end
	end)
	c:on("player_healed", function(a, src)
		if src == nil then unk = unk + a else R.heal[src] = (R.heal[src] or 0) + a end
		if cur then cur.heal = cur.heal + a end
	end)
	local sourced = c.status.hot ~= nil -- new code: player_healed carries a source
	sim:on("run_advanced", function(_, _, healed)
		if healed and healed > 0 then
			if not sourced then -- old code: the boss heal arrived unsourced
				unk = unk - healed
				R.heal.boss = R.heal.boss + healed
			end
			if cur then cur.heal = cur.heal - healed end
		end
	end)
	c:on("heal_lost", function(a, reason)
		if reason == "block" then R.lost_block = R.lost_block + a else R.lost_overheal = R.lost_overheal + a end
	end)
	c:on("heal_blocked", function() R.blocked_events = R.blocked_events + 1 end)
	c:on("ability_triggered", function(i)
		if i.gem_type == 0 and i.tier == 1 then R.skills = R.skills + 1 end
		if i.gem_type == 0 and i.tier == 2 then
			R.ults = R.ults + 1
			R.ults_n = R.ults_n + 1
			if c.player_health < LOW_HP * c.player_max_health then R.ults_low = R.ults_low + 1 end
		end
	end)
	local last_hp = c.player_health -- HP while the fight was live (the boss heal comes after fight_over)
	c:on("player_health_changed", function(hp) if not c.fight_over then last_hp = hp end end)
	c:on("enemy_defeated", function()
		if cur then cur.won = true; cur.t1 = sim.now; cur.hp1 = last_hp end
	end)
	c:on("run_lost", function()
		if cur then cur.t1 = sim.now; cur.hp1 = 0 end
		R.dead_fight = #R.fights
	end)

	run:begin_fight()
	local next_swap = pace
	while not run.over and not c.game_over do
		if sim.now >= next_swap and c:can_player_swap() == "" then
			local c1, r1, c2, r2 = pick_move(sim.board, policy, c.player_health / c.player_max_health)
			local res = c1 and c:try_swap(sim.board:get(c1, r1), sim.board:get(c2, r2)) or "none"
			next_swap = sim.now + (res == "ok" and pace or 0.1)
		end
		sim:tick(DT)
		run:update()
		if cur and not cur.t1 then
			R.fight_time = R.fight_time + DT
			if c.status[hot_id] and c:status_remaining(hot_id) > 0 then R.hot_time = R.hot_time + DT end
			if sim.now - cur.t0 > FIGHT_CAP then R.timeout = true; R.dead_fight = #R.fights; break end
		end
	end
	R.won = run.over == "won"
	-- old code: unsourced heals are lifesteal
	R.heal.lifesteal = R.heal.lifesteal + unk
	return R
end

---------------------------------------------------------------- statistics

local function wilson(k, n)
	if n == 0 then return 0, 0 end
	local z = 1.96
	local p = k / n
	local d = 1 + z * z / n
	local ctr = (p + z * z / (2 * n)) / d
	local half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
	return math.max(0, ctr - half), math.min(1, ctr + half)
end

local function median(t)
	if #t == 0 then return 0 end
	table.sort(t)
	local m = math.floor((#t + 1) / 2)
	if #t % 2 == 1 then return t[m] end
	return (t[m] + t[m + 1]) / 2
end

local function pct(x) return ("%.0f%%"):format(x * 100) end

---------------------------------------------------------------- main

local function sum_heal(R) return R.heal.hot + R.heal.ult + R.heal.boss + R.heal.lifesteal end

local out = {}
local function p(s) out[#out + 1] = s; print(s) end

local sample_kit = Combat.new({ sim = Sim.new({ seed = 1 }), seed = 1 })
local code = sample_kit.status.hot and "HoT kit (W1-G2)" or "lifesteal kit (before W1-G2)"
p(("## Probe: %s%s"):format(code, opt.title ~= "" and (" - " .. opt.title) or ""))
p("")
p(("Seeds 1..%d per row, sim step 1/30 s, no god mode. `first` = first legal move, `hold` = skip moves that fire an Amber ult while HP > 70 %%."):format(opt.seeds))
p("Heal columns are per run, mean (HP; max HP 10000). `lifesteal` = unsourced `player_healed` minus boss heals (old code). `waste` = overheal + Heal Block loss (n/a before W1-G2: no `heal_lost` event). `uptime` = share of fight time the Amber skill status was up.")
p("")
p("| policy | pace | D | wins | win rate (95 % Wilson) | dies in fight (median) | median HP at fight end (won fights) | heal lifesteal | heal hot | heal ult | heal boss | waste | skills | ults | ults <60 % HP | uptime |")
p("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")

local detail = {}
local t0 = os.clock()
for _, policy in ipairs(opt.policies) do
	for _, pace in ipairs(opt.paces) do
		for _, diff in ipairs(opt.diffs) do
			local wins, n = 0, 0
			local deaths, hp_end = {}, {}
			local agg = { lifesteal = 0, hot = 0, ult = 0, boss = 0, waste = 0, skills = 0, ults = 0, ults_low = 0, hot_time = 0, ft = 0 }
			local perfight = {}
			for seed = 1, opt.seeds do
				local R = play(seed, diff, pace, policy)
				n = n + 1
				if R.won then wins = wins + 1 end
				if R.dead_fight then deaths[#deaths + 1] = R.dead_fight end
				for i, f in ipairs(R.fights) do
					if f.won and f.hp1 then hp_end[#hp_end + 1] = f.hp1 / 10000 end
					local a = perfight[i] or { n = 0, won = 0, taken = 0, minhp = 0, hp1 = 0, heal = 0, id = f.id, t = 0 }
					perfight[i] = a
					a.n = a.n + 1
					a.taken = a.taken + f.taken
					a.minhp = a.minhp + f.minhp
					a.heal = a.heal + f.heal
					if f.won then a.won = a.won + 1; a.hp1 = a.hp1 + (f.hp1 or 0); a.t = a.t + (f.t1 - f.t0) end
				end
				agg.lifesteal = agg.lifesteal + R.heal.lifesteal
				agg.hot = agg.hot + R.heal.hot
				agg.ult = agg.ult + R.heal.ult
				agg.boss = agg.boss + R.heal.boss
				agg.waste = agg.waste + R.lost_overheal + R.lost_block
				agg.skills = agg.skills + R.skills
				agg.ults = agg.ults + R.ults
				agg.ults_low = agg.ults_low + R.ults_low
				agg.hot_time = agg.hot_time + R.hot_time
				agg.ft = agg.ft + R.fight_time
			end
			local lo, hi = wilson(wins, n)
			local has_lost = sample_kit.status.hot ~= nil
			p(("| %s | %.1f | %d | %d/%d | %s (%s-%s) | %s | %s | %.0f | %.0f | %.0f | %.0f | %s | %.1f | %.1f | %s | %s |"):format(
				policy, pace, diff, wins, n, pct(wins / n), pct(lo), pct(hi),
				#deaths > 0 and ("f" .. median(deaths) .. " (" .. #deaths .. " runs)") or "-",
				#hp_end > 0 and pct(median(hp_end)) or "-",
				agg.lifesteal / n, agg.hot / n, agg.ult / n, agg.boss / n,
				has_lost and ("%.0f"):format(agg.waste / n) or "n/a",
				agg.skills / n, agg.ults / n,
				agg.ults > 0 and pct(agg.ults_low / agg.ults) or "-",
				agg.ft > 0 and pct(agg.hot_time / agg.ft) or "-"))
			io.stderr:write(("[%s %.1f D%d] %d/%d  (%.0f s cpu)\n"):format(policy, pace, diff, wins, n, os.clock() - t0))
			if opt.fights then detail[#detail + 1] = { policy = policy, pace = pace, diff = diff, perfight = perfight } end
		end
	end
end

if opt.fights then
	p("")
	p("### Per fight (mean over runs that reached the fight)")
	for _, d in ipairs(detail) do
		p("")
		p(("**%s, pace %.1f, D%d**"):format(d.policy, d.pace, d.diff))
		p("")
		p("| fight | enemy | reached | won | damage taken | min HP | HP at end (won) | duration (won) | heal in fight |")
		p("|---|---|---|---|---|---|---|---|---|")
		for i, a in ipairs(d.perfight) do
			p(("| %d | %s | %d | %d | %.0f | %.0f | %s | %s | %.0f |"):format(i, a.id, a.n, a.won, a.taken / a.n, a.minhp / a.n,
				a.won > 0 and ("%.0f"):format(a.hp1 / a.won) or "-", a.won > 0 and ("%.0fs"):format(a.t / a.won) or "-", a.heal / a.n))
		end
	end
end
