local _, ns = ...
-- Sapphire kit: Arcane Explosion (skill), Frost Nova (ult).
local A = ns.Abilities or {}
ns.Abilities = A

-- area_clear.gd: damage, clear (2r+1)^2 around the gem, delay the next enemy
-- attack (+ the cosmetic slow window of the same length).
A.arcane_explosion = {
	id = "arcane_explosion", template = "arcane_explosion", variants = {}, color = 4, tier = 1, icon = "arcane_explosion",
	name = "Arcane Explosion",
	description = "{damage} dmg, clear {clear_size}x{clear_size} around the gem, delay the enemy's next attack +{attack_delay}s",
	blurb = "Clear {clear_size}x{clear_size} · delay attack",
	damage = 150, score = 150,
	clear_radius = 1,
	attack_delay = 2.0,
	execute = function(self, ctx)
		local combat, info = ctx.combat, ctx.info
		combat:deal_damage_to_enemy(self.damage)
		combat:award_score(self.score)
		ctx.sim:clear_area(info.col, info.row, self.clear_radius)
		local enemy = combat.enemy
		if enemy ~= nil then
			enemy:delay_attack(self.attack_delay)
			enemy:apply_slow(self.attack_delay)
		end
	end,
	text_extra = function(self, values)
		values.clear_size = tostring(self.clear_radius * 2 + 1)
	end,
}

-- freeze.gd: damage + freeze the enemy (stun mechanics, kind "freeze").
A.frost_nova = {
	id = "frost_nova", template = "frost_nova", variants = {}, color = 4, tier = 2, icon = "frost_nova",
	name = "Frost Nova",
	description = "{damage} dmg, freeze the enemy for {stun_duration}s",
	blurb = "Heavy damage · freeze enemy",
	damage = 500, score = 450,
	stun_duration = 5.0,
	execute = function(self, ctx)
		local combat = ctx.combat
		combat:deal_damage_to_enemy(self.damage)
		combat:award_score(self.score)
		if combat.enemy ~= nil then combat.enemy:apply_stun(self.stun_duration, "freeze") end
	end,
}
