local _, ns = ...
-- Amethyst kit: Hammer of Justice (skill), Mind Control (ult).
local A = ns.Abilities or {}
ns.Abilities = A

-- stun.gd: damage + stun the enemy (its attack timer pauses).
local hammer
hammer = {
	id = "hammer_of_justice", template = "hammer_of_justice", variants = {}, color = 1, tier = 1, icon = "hammer_of_justice",
	name = "Hammer of Justice",
	description = "{damage} dmg, stun the enemy for {stun_duration}s",
	blurb = "Damage · stun enemy",
	damage = 200, score = 150,
	stun_duration = 3.0,
	special_multiplier = 1.0, -- boon knob (Interrupt), unused
	execute = function(self, ctx)
		local combat = ctx.combat
		combat:deal_damage_to_enemy(self.damage)
		combat:award_score(self.score)
		local enemy = combat.enemy
		if enemy ~= nil then
			enemy:apply_stun(hammer.duration_against(self, enemy:peek_next_ability()))
		end
	end,
}

-- Pure: stun length when `next_ability` (enemy ability table or nil) is next.
function hammer.duration_against(self, next_ability)
	if self.special_multiplier == 1.0 or next_ability == nil then return self.stun_duration end
	if not next_ability.is_special then return self.stun_duration end
	return self.stun_duration * self.special_multiplier
end

A.hammer_of_justice = hammer

-- color_swap.gd (Nether Swap): every gem of one other colour -> Amethyst.
-- M1-G8: one colour per chain (combat.chain_convert_color, reset on settle) and
-- converted gems are marked, so a flood region spawns at most a skill.
local mind_control
mind_control = {
	id = "mind_control", template = "mind_control", variants = {}, color = 1, tier = 2, icon = "mind_control",
	name = "Mind Control",
	description = "Convert all gems of one other color into Amethyst (no bonus ability damage)",
	blurb = "Convert partner → Amethyst",
	damage = 0, score = 450,
	execute = function(self, ctx)
		ctx.combat:award_score(self.score)
		local partner = mind_control.chain_partner_color(ctx)
		ctx.sim:convert_color(partner, 1, true)
	end,
}

-- The chain's colour if one was picked since the last settle, else
-- resolve_partner_color (remembered for the chain).
function mind_control.chain_partner_color(ctx)
	local combat = ctx.combat
	if combat.chain_convert_color >= 0 then return combat.chain_convert_color end
	local picked = ns.Kit.resolve_partner_color(ctx)
	combat.chain_convert_color = picked
	return picked
end

A.mind_control = mind_control
