local addonName, ns = ...
-- Idle hint (W0-P4; port of the Godot idle hint in scenes/board_input.gd, HINT_IDLE_DELAY 6 s).
-- After DELAY sim-seconds of the player doing nothing (board at rest, fight running, not
-- stunned, not pressing / in the menu) it asks the core ONCE for a possible move
-- (Match.find_possible_move) and tells the board view to wiggle that gem pair. The wiggle is
-- view-side (BoardView:set_hint); one lookup per idle period, never per frame. Any swap /
-- press / pause / hide / reset cancels it (reset()), and the timer starts over.
--
-- Time is sim time (sim.now): hide / soft pause stop the clock, and reset() also restarts it.

local Hint = {}
Hint.__index = Hint

Hint.DELAY = 6.0 -- scenes/animation_timings.gd HINT_IDLE_DELAY

function Hint.new(view)
	return setmetatable({ view = view, t0 = nil, done = false, shown = false, lookups = 0 }, Hint)
end

-- Cancel the wiggle and restart the idle timer.
function Hint:reset()
	self.t0 = nil
	self.done = false
	if self.shown then
		self.shown = false
		self.view:clear_hint()
	end
end

-- Per frame from the driver, after the sim tick. active = the player could swap right now.
function Hint:update(sim, active)
	if not active or not sim:is_at_rest() then
		self:reset()
		return
	end
	local now = sim.now
	if self.t0 == nil then self.t0 = now end
	if self.done or now - self.t0 < Hint.DELAY then return end
	self.done = true -- once per idle period, whatever the result
	self.lookups = self.lookups + 1
	local c1, r1, c2, r2 = ns.Match.find_possible_move(sim.board)
	if c1 == nil then return end -- no move: the core reshuffles on its own
	local board = sim.board
	local a, b = board:get(c1, r1), board:get(c2, r2)
	if a == nil or b == nil then return end
	self.view:set_hint(a, b, c2 - c1, r2 - r1)
	self.shown = true
end

ns.Hint = Hint
