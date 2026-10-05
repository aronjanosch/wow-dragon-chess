local _, ns = ...
-- Amber kit: Drain Life (skill), Polymorph (ult).
local A = ns.Abilities or {}
ns.Abilities = A

-- lifesteal.gd: for the duration, clears heal lifesteal_percent % of their damage.
A.drain_life = {
	id = "drain_life", template = "drain_life", variants = {}, color = 0, tier = 1, icon = "drain_life",
	name = "Drain Life",
	description = "Lifesteal {lifesteal_duration}s: heal {lifesteal_percent}% of clear damage dealt",
	blurb = "Clears heal you — {lifesteal_duration}s",
	damage = 0, score = 150,
	lifesteal_duration = 10.0,
	lifesteal_percent = 100.0,
	execute = function(self, ctx)
		local combat = ctx.combat
		combat:award_score(self.score)
		combat:apply_lifesteal(self.lifesteal_duration, self.lifesteal_percent)
	end,
}

-- convert.gd: convert_count random plain gems -> Amber. M0-G5 brake: never a
-- gem next to an Amber skill / ult gem (exclude_adjacent_to_type = Amber).
-- (The .tres blurb "Convert partner → Amber" is stale in Godot too; kept.)
A.polymorph = {
	id = "polymorph", template = "polymorph", variants = {}, color = 0, tier = 2, icon = "polymorph",
	name = "Polymorph",
	description = "Convert {convert_count} random gems into Amber",
	blurb = "Convert partner → Amber",
	damage = 0, score = 450,
	convert_count = 10,
	execute = function(self, ctx)
		ctx.combat:award_score(self.score)
		ctx.sim:convert_random_gems(0, self.convert_count, -1, 0)
	end,
}
