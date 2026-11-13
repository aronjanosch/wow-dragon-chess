local _, ns = ...
-- Board durations that drive logic order (seconds of gameplay time). Copied
-- from scenes/animation_timings.gd - keep in sync. View-only timings (beam
-- fades, sparkles, banners, juice) stay in ui/.

ns.Timings = {
	-- Sim driver: a frame's dt is clamped to this (a loading screen's long first
	-- frame is absorbed instead of fast-forwarding the board).
	MAX_DT = 0.05,

	-- Player swap
	SWAP = 0.14,

	-- Match resolve
	CLEAR = 0.20,
	CLEAR_ROW = 0.12, -- row clear / wave clear pop
	CLEAR_STAGGER_STEP = 0.025, -- delay between gems of a staggered clear
	ROW_SWEEP = 0.16, -- row-clear beam (fire-and-forget, view only)
	WAVE_CONE = 0.22, -- wave-clear cone expand
	WAVE_CONE_FADE = 0.10,
	FUSE = 0.24, -- gems fly into the ability spawn / dissolve
	CHAIN_HOP = 0.055, -- chain-lightning segment
	CHAIN_HOP_HOLD = 0.02,
	CHAIN_FADE = 0.12,

	-- Gravity
	FALL_PER_CELL = 0.09,
	FALL_CAP = 0.38, -- max fall time regardless of distance (before gravity slow)
	LAND = 0.12, -- landing pose; a gem counts as settled only after it

	-- Ability gem spawn pop
	ABILITY_POP = 0.16,

	-- Cell flashes (ability telegraphs)
	FLASH_CELLS = 0.22,
	FLASH_ROW = 0.10,
	FLASH_CONVERT = 0.18,

	-- Convert ults
	CONVERT_TELEGRAPH = 0.48,
	CONVERT_TELEGRAPH_FADE = 0.14,
	CONVERT_MORPH_OUT = 0.12,
	CONVERT_MORPH_IN = 0.18,
	CONVERT_SETTLE = 0.08,
	CONVERT_STAGGER = 0.06, -- real-time (not board-paused) delay between staggered morphs
}
