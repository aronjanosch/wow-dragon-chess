local _, ns = ...
-- Ability kits (W0-G1): the indirection combat uses to find an ability,
-- kit:get(color, tier) (Godot AbilityKit.get_ability via battle.get_ability).
-- W0 has one default kit (the Godot one); W1 swaps kits per class without
-- touching combat. Also the shared helpers of scenes/abilities/player_ability.gd
-- (banner text placeholders, partner colour).
--
-- Ability definitions live in core/abilities/<color>.lua and register into
-- ns.Abilities[id]: plain data (Godot .tres values and script export defaults)
-- plus execute(ability, ctx). ctx = { sim, board, combat, info } (info = the
-- sim's activation table). Definitions are shared and never mutated: a kit
-- holds shallow copies (Godot: run-scoped kit copies).

local setmetatable, pairs, type, tostring = setmetatable, pairs, type, tostring
local floor, abs = math.floor, math.abs

ns.Abilities = ns.Abilities or {}

local Kit = {}
Kit.__index = Kit

-- Colour indices (Godot PlayerAbility constants / gem order).
Kit.AMBER, Kit.AMETHYST, Kit.EMERALD, Kit.RUBY, Kit.SAPPHIRE, Kit.TOPAZ = 0, 1, 2, 3, 4, 5

-- scenes/abilities/<color>/kit.tres: colour -> { skill id, ult id }.
Kit.DEFAULT = {
	[0] = { "drain_life", "polymorph" },
	[1] = { "hammer_of_justice", "mind_control" },
	[2] = { "power_word_shield", "rain_of_fire" },
	[3] = { "flamestrike", "fire_shield" },
	[4] = { "arcane_explosion", "frost_nova" },
	[5] = { "whirlwind", "chain_lightning" },
}

local function copy(def)
	local out = {}
	for k, v in pairs(def) do out[k] = v end -- field copy; order irrelevant
	return out
end

-- map[color] = { skill_id, ult_id } (ids in ns.Abilities).
function Kit.new(map)
	local self = setmetatable({ skills = {}, ults = {} }, Kit)
	local A = ns.Abilities
	for color = 0, 5 do
		local entry = map[color]
		if entry ~= nil then
			local s, u = A[entry[1]], A[entry[2]]
			if s == nil or u == nil then error("kit: unknown ability for colour " .. color) end
			self.skills[color] = copy(s)
			self.ults[color] = copy(u)
		end
	end
	return self
end

function Kit.default()
	return Kit.new(Kit.DEFAULT)
end

-- Godot AbilityKit.get_ability: tier 2 -> ult, 1 -> skill, else nil.
function Kit:get(color, tier)
	if tier == 2 then return self.ults[color] end
	if tier == 1 then return self.skills[color] end
	return nil
end

---------------------------------------------------------------- banner text

-- PlayerAbility.format_number: 10.0 -> "10", 0.25 -> "0.25", 12.5 -> "12.5".
function Kit.format_number(v)
	local r = floor(v + 0.5)
	if abs(v - r) < 1e-5 then return tostring(r) end
	local s = ("%.2f"):format(v):gsub("0+$", ""):gsub("%.$", "")
	return s
end

-- Placeholder name -> display string: every number / string field of the
-- ability (Godot text_values: script variables that are int / float / String;
-- booleans are not), plus the derived values of Rain of Fire / Arcane Explosion.
function Kit.text_values(ability)
	local values = {}
	for k, v in pairs(ability) do -- builds a lookup map; order irrelevant
		if type(k) == "string" then
			if type(v) == "number" then
				values[k] = Kit.format_number(v)
			elseif type(v) == "string" then
				values[k] = v
			end
		end
	end
	if ability.text_extra then ability.text_extra(ability, values) end
	return values
end

-- Godot String.format with a dictionary: unknown placeholders stay as they are.
function Kit.format_text(ability, text)
	local values = Kit.text_values(ability)
	return (text:gsub("{([%w_]+)}", function(key)
		local v = values[key]
		if v == nil then return "{" .. key .. "}" end
		return v
	end))
end

-- Banner line: blurb if set, else the description (battle._execute_ability).
function Kit.banner_text(ability)
	if ability.blurb ~= nil and ability.blurb ~= "" then return Kit.format_text(ability, ability.blurb) end
	return Kit.format_text(ability, ability.description or "")
end

---------------------------------------------------------------- partner colour

-- PlayerAbility.resolve_partner_color: the swap partner's colour; for a
-- cascade / chain activation a random other colour present on the board
-- (combat stream, Godot count_colors key order), the own colour if none.
function Kit.resolve_partner_color(ctx)
	local info = ctx.info
	local partner = info.partner_color or -1
	if partner >= 0 then return partner end
	local _, order = ctx.board:count_colors()
	local colors = {}
	for i = 1, #order do
		if order[i] ~= info.gem_type then colors[#colors + 1] = order[i] end
	end
	if #colors == 0 then return info.gem_type end
	return colors[ctx.combat.rng_combat:range_i(0, #colors - 1) + 1]
end

ns.Kit = Kit
