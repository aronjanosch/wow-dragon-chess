local _, ns = ...
-- Ruby kit: Flamestrike (skill), Fire Shield (ult).
-- Values: the .tres files and the scripts' export defaults.
local A = ns.Abilities or {}
ns.Abilities = A

-- fire_wave.gd: direct damage, then a cone from the gem toward the enemy (right).
A.flamestrike = {
	id = "flamestrike", template = "flamestrike", variants = {}, color = 3, tier = 1, icon = "flamestrike",
	name = "Flamestrike",
	description = "{damage} dmg, fire cone from gem toward enemy",
	blurb = "Wave-clear a row",
	damage = 150, score = 150,
	cone_spread = 0.4, -- half-width growth per column toward the enemy
	execute = function(self, ctx)
		local combat, info = ctx.combat, ctx.info
		combat:deal_damage_to_enemy(self.damage)
		combat:award_score(self.score)
		ctx.sim:clear_wave(info.row, info.col, self.cone_spread)
	end,
}

-- fire_shield.gd: blocks and reflects every enemy hit for the duration.
A.fire_shield = {
	id = "fire_shield", template = "fire_shield", variants = {}, color = 3, tier = 2, icon = "fire_shield",
	name = "Fire Shield",
	description = "Fire shield {fire_shield_duration}s: nullifies enemy attacks and reflects the damage back",
	blurb = "Reflect attacks — {fire_shield_duration}s",
	damage = 0, score = 450,
	fire_shield_duration = 10.0,
	reflect_multiplier = 1.0, -- boon knob (Backdraft), unused in the addon
	execute = function(self, ctx)
		local combat = ctx.combat
		combat:award_score(self.score)
		combat:apply_fire_shield(self.fire_shield_duration, self.reflect_multiplier)
	end,
}
