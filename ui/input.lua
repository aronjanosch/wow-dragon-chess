local addonName, ns = ...
-- Board input (port of scenes/board_input.gd, W0-P1): drag-to-swap and
-- click-select + click-neighbour. Both end in app.swap(a, b) -> combat:try_swap
-- (W0-G1: stun / game-over / between-fights gate, then sim:try_swap), the single
-- swap entry point (it returns "ok" or a reason). No game rules here:
-- the only board fact read is "is this gem settled" (Godot gates presses on it).
--
-- Mouse: OnMouseDown / OnMouseUp on the board frame (OnMouseUp reaches the
-- pressed frame even when released outside - verified live); an
-- IsMouseButtonDown poll in update() is the fallback release signal.
-- Cursor: GetCursorPosition() is in screen scale with y from the bottom.
--
-- View-side drag visuals: held gem offset (hx, hy) and neighbour offset
-- (nx, ny) in cells, read by the board view; core x / y are never touched.

local abs = math.abs

local Input = {}
Input.__index = Input

-- Godot board_input.gd constants (fractions of a cell; deadzone in Godot px at
-- a 62 px cell, scaled to our cell size).
local DEADZONE_GODOT_PX, GODOT_CELL = 8, 62
local COMMIT = 0.28 -- release past this -> swap
local AUTO_COMMIT = 0.52 -- held drag past this -> swap without waiting for release
local REAIM = 0.18 -- below this progress, the drag direction can change
local LATERAL = 0.24 -- sideways wiggle
local OVERSHOOT, OVERSHOOT_SOFT = 0.1, 0.28 -- soft pull past a full cell
local NEIGHBOUR_SHOW = 0.5 -- neighbour slides toward the held gem past this

-- app: get_sim() -> sim or nil, can_input() -> bool, swap(a, b) -> result.
function Input.new(host, view, app)
	local self = setmetatable({}, Input)
	self.host, self.view, self.app = host, view, app
	self.cell = ns.BoardView.CELL
	self.deadzone = DEADZONE_GODOT_PX * self.cell / GODOT_CELL
	self.last_result = nil
	self:_reset_press()
	self.selected = nil
	host:EnableMouse(true)
	host:SetScript("OnMouseDown", function(_, button)
		if button == "LeftButton" then self:press() end
	end)
	host:SetScript("OnMouseUp", function(_, button)
		if button == "LeftButton" then self:release() end
	end)
	return self
end

function Input:_reset_press()
	self.press_gem = nil
	self.dragging = false
	self.dir_c, self.dir_r = 0, 0
	self.along = 0
	-- read by the view
	self.held, self.hx, self.hy = nil, 0, 0
	self.nb, self.nx, self.ny = nil, 0, 0
end

-- Cursor in board-local px: x from the left edge, y from the top edge.
function Input:cursor()
	local host = self.host
	local left, bottom = host:GetLeft(), host:GetBottom()
	if left == nil or bottom == nil then return nil end
	local s = host:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	local lx = cx / s - left
	local ly = cy / s - bottom -- from the bottom
	return lx, self.view.rows * self.cell - ly -- flip: rows count from the top
end

local function settled(gem)
	return gem ~= nil and not gem.removed and gem.state == ns.Board.SETTLED
end

function Input:_gem_under_cursor()
	local sim = self.app.get_sim()
	if sim == nil then return nil end
	local lx, ly = self:cursor()
	if lx == nil then return nil end
	local c, r = self.view:cell_at(lx, ly)
	if c == nil then return nil end
	return sim.board:get(c, r), lx, ly
end

function Input:press()
	if not self.app.can_input() or self.press_gem ~= nil then return end
	local gem, lx, ly = self:_gem_under_cursor()
	if not settled(gem) then return end
	self:_reset_press()
	self.press_gem = gem
	self.sx, self.sy = lx, ly
	self.held = gem
end

-- Drag maths from the cursor offset (px) since the press.
function Input:_drag_to(dx, dy)
	local cell = self.cell
	if not self.dragging then
		if dx * dx + dy * dy < self.deadzone * self.deadzone then return end
		self.dragging = true
		self.dir_c, self.dir_r = 0, 0
	end
	local ux, uy = dx / cell, dy / cell -- cells; uy grows downward (rows)
	if self.dir_c == 0 and self.dir_r == 0 or self.along <= REAIM then
		-- dominant axis (re-aim while the drag is short)
		if abs(ux) >= abs(uy) then
			self.dir_c, self.dir_r = ux >= 0 and 1 or -1, 0
		else
			self.dir_c, self.dir_r = 0, uy >= 0 and 1 or -1
		end
	end
	local dc, dr = self.dir_c, self.dir_r
	local along = ux * dc + uy * dr
	local lateral = ux * dr + uy * dc -- the other axis (sign irrelevant)
	if along < 0 then along = 0 end
	if along > 1 then
		local over = (along - 1) * OVERSHOOT_SOFT
		if over > OVERSHOOT then over = OVERSHOOT end
		along = 1 + over
	end
	if lateral > LATERAL then lateral = LATERAL elseif lateral < -LATERAL then lateral = -LATERAL end
	self.along = along
	-- held gem: along the axis + a little sideways wiggle
	self.hx = dc * along + dr * lateral
	self.hy = dr * along + dc * lateral
	-- neighbour in the drag direction (settled only)
	local sim = self.app.get_sim()
	local gem = self.press_gem
	local nb
	if sim ~= nil then
		local nc, nr = gem.col + dc, gem.row + dr
		if sim.board:in_bounds(nc, nr) then nb = sim.board:get(nc, nr) end
	end
	if not settled(nb) then nb = nil end
	self.nb = nb
	if nb ~= nil and along > NEIGHBOUR_SHOW then
		self.nx, self.ny = -dc * along, -dr * along
	else
		self.nx, self.ny = 0, 0
	end
end

function Input:_drag_from_cursor()
	local lx, ly = self:cursor()
	if lx == nil then return end
	self:_drag_to(lx - self.sx, ly - self.sy)
end

-- Per frame (driver): drag follow, auto-commit, release fallback.
function Input:update()
	local gem = self.press_gem
	if gem == nil then return end
	if not settled(gem) or not self.app.can_input() then
		self:_reset_press()
		return
	end
	if not IsMouseButtonDown("LeftButton") then
		self:release()
		return
	end
	self:_drag_from_cursor()
	if self.dragging and self.along >= AUTO_COMMIT and self.nb ~= nil then self:_commit() end
end

function Input:release()
	local gem = self.press_gem
	if gem == nil then return end
	-- quick flick: resolve the drag from the final cursor position
	self:_drag_from_cursor()
	if not self.dragging then
		self:_reset_press()
		self:_tap(gem)
		return
	end
	if self.along >= COMMIT and self.nb ~= nil then
		self:_commit()
	else
		self:_reset_press()
	end
end

function Input:_commit()
	local a, b = self.press_gem, self.nb
	self:_reset_press()
	self.selected = nil
	self.last_result = self.app.swap(a, b)
end

function Input:_tap(gem)
	if not settled(gem) then return end
	local sel = self.selected
	if sel == nil or sel.removed then
		self.selected = gem
	elseif sel == gem then
		self.selected = nil
	else
		-- the core decides adjacency; a non-neighbour click moves the selection
		local result = self.app.swap(sel, gem)
		self.last_result = result
		if result == "not_adjacent" or result == "invalid" then
			self.selected = gem
		else
			self.selected = nil
		end
	end
end

-- Hide / soft pause / reset: drop any press and selection.
function Input:cancel()
	self:_reset_press()
	self.selected = nil
end

ns.Input = Input
