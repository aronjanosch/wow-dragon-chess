-- W1-G1 part B UI test: class picker (default from UnitClass, select + persist, fallbacks, tooltips),
-- the class of a run (kit, snapshot round trip), kit-aware status strip / S2 label / held effect, /dcfx listing.
-- Loads the addon in TOC order under test/wow_stubs.lua like ui_menu_test.
local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "."
local T = dofile(dir .. "/t.lua")
local loader = dofile(dir .. "/loader.lua")
local Stubs = dofile(dir .. "/wow_stubs.lua")
T.start("ui_class_test")

local ADDON = "DragonChess"
local addon_dir = loader.wow_dir() .. "/"
local DT = 1 / 60

local toc_files = {}
do
	local f = assert(io.open(addon_dir .. "DragonChess.toc"))
	for line in f:lines() do
		line = line:gsub("\r", "")
		if line:match("%S") and not line:match("^#") then toc_files[#toc_files + 1] = line:match("^%s*(.-)%s*$") end
	end
	f:close()
end

-- saved = SavedVariables to inject; pre(W) runs before ADDON_LOADED (stubs to change).
local function session(saved, pre)
	local W = Stubs.new()
	local ns = {}
	for _, f in ipairs(toc_files) do W.load(addon_dir .. f, ADDON, ns) end
	if saved then
		for k, v in pairs(saved) do W.store[k] = v end
	end
	if pre then pre(W) end
	W.fire("ADDON_LOADED", ADDON)
	W.ns, W.App = ns, ns.App
	return W
end

local function frames(W, n) for _ = 1, n do W.update(DT) end end
local function click(btn) btn.scripts.OnClick(btn, "LeftButton") end
local function button_of(sm, id)
	for _, b in ipairs(sm.class_buttons) do
		if b.class_id == id then return b end
	end
end
local function copy(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in pairs(v) do out[copy(k)] = copy(x) end
	return out
end
local function open_start(W)
	W.stubs.SlashCmdList.DRAGONCHESS("")
	return W.App
end
local function open_running(W)
	local App = open_start(W)
	if App.start_open then App.close_start() end
	frames(W, 5)
	return App
end

---------------------------------------------------------------- picker

T.case("picker: default class from UnitClass, class buttons in ORDER, selected one highlighted", function()
	local W = session(nil, function(w) w.unit_class = "ROGUE" end)
	local App = open_start(W)
	local sm, A = App.start, W.ns.Assets
	T.ok(App.start_open and sm.form == "start" and sm.start_group:IsShown() and not sm.resume_group:IsShown(), "start form shows the picker")
	T.eq(#sm.class_buttons, 9, "9 class buttons")
	for i, id in ipairs(W.ns.Classes.ORDER) do T.eq(sm.class_buttons[i].class_id, id, "order " .. i) end
	T.eq(App.selected_class(), "ROGUE", "default = the character's class")
	T.eq(App.combat.kit.class_id, "ROGUE", "the run uses it")
	T.eq(sm.class_name.text, "Rogue", "name under the row")
	for _, b in ipairs(sm.class_buttons) do
		local on = b.class_id == "ROGUE"
		T.eq(b.border.r, on and b.cr or A.COLOR.CLASS_IDLE[1], "frame colour (class colour when selected) " .. b.class_id)
		T.eq(b.w, 36, "class icon 36 px")
		T.eq(b.icon.vr, on and 1 or A.COLOR.CLASS_DIM, "dim " .. b.class_id)
		T.eq(b.icon.texture, A.CLASS_ICONS, "class icon sheet")
		T.ok(b.icon.tc_l ~= nil, "tex coords set")
	end
	T.eq(#W.errors, 0, "no errors")
end)

T.case("picker: select persists in DragonChessCharDB, restarts the fresh run with that kit, Start keeps it", function()
	local W = session(nil, function(w) w.unit_class = "MAGE" end)
	local App = open_start(W)
	local sm = App.start
	local old = App.sim
	click(button_of(sm, "WARRIOR"))
	T.eq(W.store.DragonChessCharDB.class_id, "WARRIOR", "stored per character")
	T.ok(App.sim ~= old, "fresh run restarted")
	T.ok(App.start_open and sm.form == "start", "the panel stays open")
	T.eq(App.combat.kit.class_id, "WARRIOR", "kit class")
	T.eq(App.combat.kit:get(3, 1).id, "cleave", "Ruby skill is Cleave")
	T.eq(sm.class_name.text, "Warrior", "name follows")
	T.eq(button_of(sm, "WARRIOR").border.r, button_of(sm, "WARRIOR").cr, "highlight moved (class-coloured frame)")
	T.eq(W.sounds[#W.sounds] ~= nil, true, "click sound played")
	local t0 = App.sim.now
	click(sm.buttons.start)
	T.ok(not App.start_open, "Start closes the panel")
	frames(W, 30)
	T.ok(App.sim.now > t0, "the run ticks")
	T.eq(App.combat.kit.class_id, "WARRIOR", "still Warrior")
	-- next session: the stored class beats the character's class
	local W2 = session({ DragonChessCharDB = copy(W.store.DragonChessCharDB) }, function(w) w.unit_class = "MAGE" end)
	T.eq(open_start(W2).combat.kit.class_id, "WARRIOR", "stored class wins")
	T.eq(#W.errors + #W2.errors, 0, "no errors")
end)

T.case("picker: unknown stored class / missing UnitClass -> default kit", function()
	local W = session({ DragonChessCharDB = { class_id = "BARD" } }, function(w) w.unit_class = nil end)
	local App = open_start(W)
	T.eq(App.combat.kit.class_id, nil, "unknown stored class, no UnitClass token: default kit")
	T.eq(App.start.class_name.text, "Classic", "labelled Classic")
	T.eq(App.start.preview[1].icon.texture, W.ns.Assets.icon(App.combat.kit:get(0, 1).icon), "preview shows the default kit")
	local W2 = session(nil, function(w) w.stubs.UnitClass = nil end) -- the function does not exist
	T.eq(open_start(W2).combat.kit.class_id, nil, "missing UnitClass: default kit")
	local W3 = session(nil, function(w) w.stubs.UnitClass = function() return nil end end) -- returns nothing
	T.eq(open_start(W3).combat.kit.class_id, nil, "UnitClass returns nil: default kit")
	local W4 = session(nil, function(w) w.unit_class = "BARD" end) -- not one of the nine
	T.eq(open_start(W4).combat.kit.class_id, nil, "unknown token: default kit")
	T.eq(#W.errors + #W2.errors + #W3.errors + #W4.errors, 0, "no errors")
end)

T.case("picker: missing icon / colour globals fall back to plain coloured buttons", function()
	local W = session(nil, function(w)
		w.unit_class = "PRIEST"
		w.stubs.CLASS_ICON_TCOORDS, w.stubs.RAID_CLASS_COLORS = nil, nil
	end)
	local App = open_start(W)
	local b = button_of(App.start, "PRIEST")
	T.ok(b.initial ~= nil and b.initial.text == "P", "class initial on the button")
	T.ok(b.icon.texture == nil and b.icon.r ~= nil, "colour fill instead of the sheet")
	T.eq(b.cr, W.ns.Assets.CLASS_COLOR_FALLBACK[1], "fallback colour")
	T.eq(App.start.class_name.text, "Priest", "name still shown")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("picker: preview = the kit's 6 x 2 icons; tooltips carry formatted numbers", function()
	local W = session(nil, function(w) w.unit_class = "DRUID" end)
	local App = open_start(W)
	local sm, A = App.start, W.ns.Assets
	local ns = W.ns
	for _, id in ipairs(ns.Classes.ORDER) do
		click(button_of(sm, id))
		local kit = App.combat.kit
		T.eq(kit.class_id, id, "kit " .. id)
		for color = 0, 5 do
			for tier = 1, 2 do
				local ab = kit:get(color, tier)
				local b = sm.preview[color * 2 + tier]
				T.eq(b.icon.texture, A.icon(ab.icon), id .. " icon " .. ab.id)
				b.scripts.OnEnter(b)
				local lines = W.tooltip.lines
				T.eq(lines[1], ab.name, "tooltip title " .. ab.id)
				T.eq(lines[2], (tier == 2 and "Ultimate" or "Skill") .. " - " .. ns.Combat.COLOR_NAMES[color], "kind line " .. ab.id)
				T.ok(lines[3] ~= nil and not lines[3]:find("{", 1, true), "no raw placeholder in " .. ab.id .. ": " .. tostring(lines[3]))
				T.ok(W.tooltip.shown, "tooltip shown")
				b.scripts.OnLeave(b)
				T.ok(not W.tooltip.shown, "tooltip hidden")
			end
		end
	end
	-- a concrete number: Cleave deals the template's damage
	click(button_of(sm, "WARRIOR"))
	local b = sm.preview[3 * 2 + 1]
	b.scripts.OnEnter(b)
	T.eq(W.tooltip.lines[1], "Cleave", "Cleave tooltip")
	T.ok(W.tooltip.lines[3]:find(ns.Kit.format_number(App.combat.kit:get(3, 1).damage), 1, true) ~= nil, "damage number in the text")
	T.eq(#W.errors, 0, "no errors")
end)

T.case("picker: resume form shows the run's class name, no picker", function()
	local W = session(nil, function(w) w.unit_class = "HUNTER" end)
	open_start(W)
	local saved = { DragonChessDB = copy(W.store.DragonChessDB) }
	local W2 = session(saved, function(w) w.unit_class = "MAGE" end)
	local App = open_start(W2)
	T.eq(App.start.form, "resume", "resume form")
	T.ok(not App.start.start_group:IsShown() and App.start.resume_group:IsShown(), "no picker")
	T.eq(App.start.class_line.text, "Hunter", "the run's class, not the character's")
	T.ok(App.start.class_line:IsShown(), "class line shown")
	T.eq(#W2.errors, 0, "no errors")
end)

---------------------------------------------------------------- persistence

T.case("snapshot: class_id stored and restored; a save without / with an unknown class resumes as Classic", function()
	local W = session({ DragonChessCharDB = { class_id = "PALADIN" } })
	local App = open_running(W)
	local snap = W.store.DragonChessDB.run
	T.eq(snap.class_id, "PALADIN", "boundary snapshot carries the class")
	local W2 = session({ DragonChessDB = copy(W.store.DragonChessDB), DragonChessCharDB = { class_id = "MAGE" } })
	T.eq(open_start(W2).combat.kit.class_id, "PALADIN", "round trip keeps the class (not the stored choice)")
	T.eq(W2.App.combat.kit:get(1, 1).id, "hammer_of_justice", "kit abilities restored")
	local db3 = copy(W.store.DragonChessDB)
	db3.run.class_id = nil
	local W3 = session({ DragonChessDB = db3, DragonChessCharDB = { class_id = "MAGE" } })
	T.eq(open_start(W3).combat.kit.class_id, nil, "no class_id: default kit")
	local db4 = copy(W.store.DragonChessDB)
	db4.run.class_id = "BARD"
	local W4 = session({ DragonChessDB = db4 })
	T.eq(open_start(W4).combat.kit.class_id, nil, "unknown class_id: default kit")
	T.eq(W4.App.start.form, "resume", "and it is still a resume")
	T.eq(W4.App.start.class_line.text, "Classic", "labelled Classic")
	T.eq(#W.errors + #W2.errors + #W3.errors + #W4.errors, 0, "no errors")
end)

---------------------------------------------------------------- status strip / labels / holds

local function kit_icon(W, kit, color, tier) return W.ns.Assets.icon(kit:get(color, tier).icon) end

T.case("_apply_kit: status strip textures on start and after resume, class label", function()
	local W = session({ DragonChessCharDB = { class_id = "WARRIOR" } })
	local App = open_running(W)
	local hud, kit = App.hud, App.combat.kit
	T.eq(hud.status.shield.icon.texture, kit_icon(W, kit, 2, 1), "shield <- Emerald skill")
	T.eq(hud.status.fire_shield.icon.texture, kit_icon(W, kit, 3, 2), "fire shield <- Ruby ult")
	T.eq(hud.status.hot.icon.texture, kit_icon(W, kit, 0, 1), "hot <- Amber skill")
	T.eq(hud.status.shield.icon.texture, W.ns.Assets.icon("shield_block"), "Shield Block")
	T.eq(hud.class_label.text, "Warrior", "class label")
	T.ok(hud.class_label.tr ~= nil, "class colour set")
	-- resume in a new session (other stored class: the run's class wins)
	local W2 = session({ DragonChessDB = copy(W.store.DragonChessDB), DragonChessCharDB = { class_id = "MAGE" } })
	local App2 = open_running(W2)
	local k2 = App2.combat.kit
	T.eq(k2.class_id, "WARRIOR", "resumed class")
	T.eq(App2.hud.status.shield.icon.texture, kit_icon(W2, k2, 2, 1), "after resume: shield")
	T.eq(App2.hud.status.fire_shield.icon.texture, kit_icon(W2, k2, 3, 2), "after resume: fire shield")
	T.eq(App2.hud.status.hot.icon.texture, kit_icon(W2, k2, 0, 1), "after resume: hot")
	-- a new run with another class rebinds
	App2.set_class("DRUID")
	App2.reset()
	T.eq(App2.hud.class_label.text, "Druid", "label after a new run")
	T.eq(App2.hud.status.hot.icon.texture, kit_icon(W2, App2.combat.kit, 0, 1), "strip follows the new kit")
	-- the HoT icon runs its countdown on the granted ticks, also after an extend (W1-G2)
	local hot = App2.hud.status.hot
	App2.combat:apply_hot(5, 10, 1)
	frames(W2, 2)
	T.ok(hot:IsShown() and hot.num.text == "10", "hot icon shows the seconds left")
	App2.combat:apply_hot(5, 10, 1)
	frames(W2, 2)
	T.ok(hot:IsShown() and tonumber(hot.num.text) >= 19, "after an extend the countdown shows 19-20 s")
	T.ok(App2.combat:status_remaining("hot") <= App2.combat:status_max("hot"), "remaining never exceeds max")
	-- default kit: Classic, the old icons of the default abilities
	local W3 = session(nil)
	local App3 = open_running(W3)
	T.eq(App3.hud.class_label.text, "Classic", "default kit label")
	T.eq(App3.hud.status.shield.icon.texture, W3.ns.Assets.icon("power_word_shield"), "default shield icon")
	T.eq(#W.errors + #W2.errors + #W3.errors, 0, "no errors")
end)

T.case("S2 / M1: label, icon and held effect per kit", function()
	local cases = {
		{ "DRUID", "freeze", "ROOTED", "roots_hold", "entangling_roots" },
		{ "MAGE", "freeze", "FROZEN", "freeze", "frost_nova" },
		{ "WARRIOR", "freeze", "STUNNED", "stun_stars", "concussion_blow" },
		{ "PRIEST", "freeze", "SILENCED", "stun_stars", "silence" },
		{ "WARRIOR", "stun", "STUNNED", "stun_stars", "intercept" },
		{ "MAGE", "stun", "STUNNED", "stun_stars", "counterspell" },
	}
	for _, c in ipairs(cases) do
		local class, kind, text, hold, id = c[1], c[2], c[3], c[4], c[5]
		local W = session({ DragonChessCharDB = { class_id = class } })
		local App = open_running(W)
		local hud, A = App.hud, W.ns.Assets
		App.combat.enemy:apply_stun(3, kind)
		frames(W, 2)
		local label = class .. " " .. kind
		T.eq(App.combat.kit:get(kind == "freeze" and 4 or 1, kind == "freeze" and 2 or 1).id, id, label .. " spell")
		T.eq(hud.q_timer.text, text, label .. " status text")
		T.eq(hud.enemy_stun.icon.texture, A.icon(id), label .. " icon")
		T.ok(hud.enemy_stun:IsShown(), label .. " icon shown")
		local f = hud.fx.holds[kind]
		T.ok(f ~= nil and f.on, label .. " hold shown")
		T.eq(f and f.key, hold, label .. " hold fx")
		T.eq(#W.errors, 0, label .. " no errors")
	end
	-- default kit: the old FROZEN / STUNNED with the swirl / block
	local W = session(nil)
	local App = open_running(W)
	App.combat.enemy:apply_stun(3, "freeze")
	frames(W, 2)
	T.eq(App.hud.q_timer.text, "FROZEN", "default kit FROZEN")
	T.eq(App.hud.fx.holds.freeze.key, "freeze", "default kit ice block")
end)

T.case("Fx:hold with a key: another model replaces the previous one, off hides, roots_hold exists", function()
	local W = session(nil)
	local App = open_running(W)
	local fx, A = App.hud.fx, W.ns.Assets
	T.ok(A.FX.roots_hold ~= nil and A.FX.roots_hold.m2 ~= nil, "roots_hold FX entry")
	fx:hold("freeze", true)
	local f = fx.holds.freeze
	T.ok(f.on and f.key == "freeze", "default key")
	local model = f.model_file
	fx:hold("freeze", true, "roots_hold")
	T.ok(f.on and f.key == "roots_hold", "switched to roots")
	T.ok(f.model_file ~= model, "the model changed")
	local n = fx:active_count()
	fx:hold("freeze", true, "roots_hold")
	T.eq(fx:active_count(), n, "same key: no-op")
	fx:hold("freeze", false)
	T.ok(not f.on and not f:IsShown(), "off hides")
	-- a key whose model fails is not retried every frame, a different key is tried
	W.bad_models[A.FX.roots_hold.m2] = true
	fx:hold("freeze", true, "roots_hold")
	T.ok(not f.on and f.failed, "failed model")
	fx:hold("freeze", true)
	T.ok(f.on and f.key == "freeze", "another key still works after a failure")
	T.eq(#W.errors, 0, "no errors")
end)

---------------------------------------------------------------- /dcfx

T.case("/dcfx without arguments lists the event / hold keys and the kit's 12 spells only", function()
	local W = session({ DragonChessCharDB = { class_id = "MAGE" } })
	local App = open_running(W)
	local A = W.ns.Assets
	W.printed = {}
	W.stubs.SlashCmdList.DCFX("")
	local out = table.concat(W.printed, "\n")
	T.ok(out:find("Your kit", 1, true) ~= nil, "kit section")
	for color = 0, 5 do
		for tier = 1, 2 do
			local id = App.combat.kit:get(color, tier).id
			T.ok(out:find(id, 1, true) ~= nil, "lists " .. id)
		end
	end
	for _, key in ipairs({ "enemy_hit", "stun_stars", "freeze", "roots_hold", "heal_moment", "aegis", "mirror" }) do
		T.ok(out:find(key, 1, true) ~= nil, "lists " .. key)
	end
	T.ok(out:find("cleave", 1, true) == nil, "no other class's spell")
	T.ok(#out < 1200, "short listing (" .. #out .. ")")
	-- any key still plays
	W.printed = {}
	W.stubs.SlashCmdList.DCFX("cleave")
	T.ok(W.printed[1] ~= nil and not W.printed[1]:find("unknown", 1, true), "/dcfx cleave works: " .. tostring(W.printed[1]))
	T.ok(A.FX.cleave ~= nil, "cleave has an FX entry")
	T.eq(#W.errors, 0, "no errors")
end)

T.done()
