local _, ns = ...
-- Amber kit (W1-G2): Rejuvenation (skill, a heal over time), Lay on Hands (ult, an instant heal).
local A = ns.Abilities or {}
ns.Abilities = A

local floor = math.floor

local function total(percent) -- flat max HP: the text names absolute numbers
	return floor((ns.Combat and ns.Combat.PLAYER_START_HEALTH or 10000) * percent / 100 + 0.5)
end

-- Heal over time: hot_percent % of max HP in total, one tick every hot_interval s for hot_ticks ticks
-- (core/combat.lua apply_hot). A cast while it runs adds hot_ticks ticks, capped at 2 x hot_ticks.
A.rejuvenation = {
	id = "rejuvenation", template = "rejuvenation", color = 0, tier = 1, icon = "rejuvenation",
	name = "Rejuvenation",
	description = "Heal {hot_total} health over {hot_seconds}s",
	blurb = "Heal {hot_total} over {hot_seconds}s",
	damage = 0, score = 150,
	hot_percent = 5.0,
	hot_ticks = 10,
	hot_interval = 1.0,
	execute = function(self, ctx)
		local combat = ctx.combat
		combat:award_score(self.score)
		combat:apply_hot(self.hot_percent, self.hot_ticks, self.hot_interval)
	end,
	text_extra = function(self, values)
		local K = ns.Kit
		values.hot_total = K.format_number(total(self.hot_percent))
		values.hot_seconds = K.format_number(self.hot_ticks * self.hot_interval)
	end,
}

-- Instant heal of heal_percent % of max HP (blocked by Heal Block, capped at max HP).
A.lay_on_hands = {
	id = "lay_on_hands", template = "lay_on_hands", color = 0, tier = 2, icon = "lay_on_hands",
	name = "Lay on Hands",
	description = "Heal {heal_total} health at once",
	blurb = "Heal {heal_total} health",
	damage = 0, score = 450,
	heal_percent = 15.0,
	execute = function(self, ctx)
		local combat = ctx.combat
		combat:award_score(self.score)
		combat:heal_player(floor(combat.player_max_health * self.heal_percent / 100 + 0.5), "ult", true)
	end,
	text_extra = function(self, values)
		values.heal_total = ns.Kit.format_number(total(self.heal_percent))
	end,
}
