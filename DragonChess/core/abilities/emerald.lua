local _, ns = ...
-- Emerald kit: Power Word: Shield (skill), Rain of Fire (ult).
local A = ns.Abilities or {}
ns.Abilities = A

-- shield.gd: +shield_stacks stacks; each blocks one enemy hit.
A.power_word_shield = {
	id = "power_word_shield", template = "power_word_shield", variants = {}, color = 2, tier = 1, icon = "power_word_shield",
	name = "Power Word: Shield",
	description = "Shield: blocks the next enemy attack (stacks)",
	blurb = "Block next enemy hit · stacks",
	damage = 0, score = 150,
	shield_stacks = 1,
	thorns_damage = 0, -- boon knob (Thorns), unused
	execute = function(self, ctx)
		local combat = ctx.combat
		combat:award_score(self.score)
		for _ = 1, (self.shield_stacks > 0 and self.shield_stacks or 0) do
			combat:add_shield_stack(self.thorns_damage)
		end
	end,
}

-- bombs.gd: bomb_count random plain gems become bombs (they keep their colour;
-- a matched bomb clears 3x3 for Combat.BOMB_DAMAGE, see Combat:_execute).
A.rain_of_fire = {
	id = "rain_of_fire", template = "rain_of_fire", variants = {}, color = 2, tier = 2, icon = "rain_of_fire",
	name = "Rain of Fire",
	description = "Turn {bomb_count} random gems into bombs: activate with any color, clear 3x3 and deal {bomb_damage} dmg",
	blurb = "Spawn {bomb_count} bombs",
	damage = 0, score = 450,
	bomb_count = 5,
	execute = function(self, ctx)
		ctx.combat:award_score(self.score)
		ctx.sim:convert_random_to_bombs(self.bomb_count)
	end,
	text_extra = function(_, values)
		values.bomb_damage = tostring(ns.Combat and ns.Combat.BOMB_DAMAGE or 50)
	end,
}
