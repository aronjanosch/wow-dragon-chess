#!/usr/bin/env bash
# Addon checks, headless. lua5.1 is the primary runner (WoW is Lua 5.1; LuaJIT allows
# yields inside pcall and would hide bugs), luajit the secondary one.
# Usage: tools/checks.sh [--list]   → exit 0 = all clean
# Single source of the test list (add new test files here).
TESTS="lint_globals lint_yield rng_test match_test scheduler_test sim_test effects_test pause_test soak ui_smoke ui_menu_test ui_class_test ui_fx_test ui_juice_test ui_boardfx_test ui_hitfx_test combat_test ability_test class_test enemy_stub_test fight_bot_test enemy_data_test enemy_test enemy_bot_test run_test debug_test ui_debug_test release_test"

if [[ "${1:-}" == "--list" ]]; then echo "$TESTS"; exit 0; fi
root=$(git rev-parse --show-toplevel) || exit 2
cd "$root" || exit 2
fail=0
for runner in lua5.1 luajit; do
	command -v "$runner" > /dev/null || { echo "MISSING runner: $runner"; fail=1; continue; }
	for t in $TESTS; do
		if out=$("$runner" "test/$t.lua" 2>&1) && ! printf '%s' "$out" | grep -q "FAIL"; then
			echo "[$runner] $t: pass"
		else
			echo "[$runner] $t: FAIL"; printf '%s\n' "$out" | head -15; fail=1
		fi
	done
done
exit $fail
