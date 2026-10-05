local _, ns = ...
-- Topaz kit: Whirlwind (skill), Chain Lightning (ult).
local A = ns.Abilities or {}
ns.Abilities = A

local floor = math.floor

-- row_clear.gd: direct damage, staggered sweep of the gem's row.
A.whirlwind = {
	id = "whirlwind", template = "whirlwind", variants = {}, color = 5, tier = 1, icon = "whirlwind",
	name = "Whirlwind",
	description = "{damage} dmg, clear the gem's row",
	blurb = "Clear entire row",
	damage = 150, score = 150,
	-- Boon knob (Crossfire): Godot then calls board.clear_cross, which the core
	-- does not port (boons are cut) - the addon always clears the row.
	clear_column = false,
	execute = function(self, ctx)
		local combat, info = ctx.combat, ctx.info
		combat:deal_damage_to_enemy(self.damage)
		combat:award_score(self.score)
		ctx.sim:clear_row(info.row, info.col)
	end,
}

-- color_chain.gd: chain lightning over every gem of the partner colour.
local chain_lightning
chain_lightning = {
	id = "chain_lightning", template = "chain_lightning", variants = {}, color = 5, tier = 2, icon = "chain_lightning",
	name = "Chain Lightning",
	description = "Chain lightning: clear all gems of the partner color",
	blurb = "Chain-clear partner color",
	damage = 0, score = 450,
	target_most_common = false, -- boon knob (Lightning Rod), unused
	delay_per_8_gems = 0.0, -- boon knob (Surge), unused
	execute = function(self, ctx)
		local combat, info = ctx.combat, ctx.info
		combat:award_score(self.score)
		local target = ns.Kit.resolve_partner_color(ctx)
		if self.target_most_common then
			local counts, order = ctx.board:count_colors()
			target = chain_lightning.most_common_color(counts, order, info.gem_type, target)
		end
		local result = ctx.sim:clear_color_chained(target, info.col, info.row)
		local delay = chain_lightning.delay_for_cleared(self, result.count or 0)
		if delay > 0 and combat.enemy ~= nil then
			combat.enemy:delay_attack(delay)
			combat.enemy:apply_slow(delay)
		end
	end,
}

-- Pure: the colour with the most gems, excluding own_color; ties -> the lower
-- colour index; fallback when no other colour is on the board.
function chain_lightning.most_common_color(counts, _, own_color, fallback)
	local best, best_count = fallback, -1
	for color = 0, 5 do
		local n = counts[color]
		if n ~= nil and color ~= own_color and n > best_count then
			best, best_count = color, n
		end
	end
	return best
end

-- Pure: Surge delay for `cleared` gems (whole groups of 8 only).
function chain_lightning.delay_for_cleared(self, cleared)
	if self.delay_per_8_gems <= 0 or cleared < 8 then return 0 end
	return floor(cleared / 8) * self.delay_per_8_gems
end

A.chain_lightning = chain_lightning
