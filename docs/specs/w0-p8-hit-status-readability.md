# Spec: W0-P8 — HP chip bars, status pop / auras, damage numbers, enemy telegraph / entrance / death

Status: implemented — awaiting in-game playtest (approved by user "ja", 2026-10-05, Paket C).
Milestone: W0 addon. Track: P (presentation). Issue #53 (feel).
Pillars served: feedback over explanation; statuses and threats readable at a glance.

## Player experience goal

Damage and healing are felt on the HP bars (a lagging chip shows what was lost), statuses visibly arrive, warn before they
end and shatter when they expire, active buffs show as an aura on the player, numbers pop with weight, an incoming enemy
attack builds visible danger, and enemies enter and die with a moment instead of just appearing / fading.

## Current state (facts)

- `bar_set` sets StatusBars directly (`ui/fight_view.lua:217`); no chip, no heal flash, no low-HP warning.
- Status icons are shown/hidden with `set_shown` and re-laid out instantly (`_update_statuses`, `fight_view.lua:1404`);
  `status_changed` core event is unused (statuses are polled from `hud_state`).
- Damage numbers: pooled FontStrings, linear rise + fade, only font/colour variants (`_spawn_pop`, `update_pool`).
- Windup: slot pulse + "NOW!" + creature animation only (`_update_timer`, `_on_windup`).
- `_on_fight_started` shows the enemy at once; death = animation + alpha fade + CLEARED banner; phase change = banner + sound.
- Score count-up exists; the plaque does not react (`score_awarded` unused).
- W0-P7 added `ui/board_fx.lua` / `ui/juice.lua` pools; reuse `Juice:particle / ring / burst / impact`, `A.soft`, `A.GLOW`.
- Rules from W0-P6/P7 stay: sim time only, pooled (created once), no per-frame allocation, setters only on quantised
  change, pcall on unverified API, everything stops in `FightView:halt`, a failing module must not break the window.

## Changes

1. **Chip bars (player + enemy):** a second, dimmer layer behind the fill (colour: white-ish / dark red for enemy, pale
   red for player) that holds the old value 0.35 s after a drop, then slides down to the new value in 0.25 s (sim time).
   Heals: a green additive flash over the player bar (0.25 s) and the fill grows normally. Implemented in the bar helper
   (one extra texture per bar, created once); quantise width changes to whole pixels.
2. **Low HP:** player HP <= 25 %: the bar border / a soft red glow pulses at ~1.2 Hz and the red edge vignette keeps a
   faint heartbeat (alpha 0.08-0.2); < 10 % faster. Off when HP is above, stunned/dead/halted. Constants at the top.
3. **Status pop / warn / shatter (player strip + enemy slots + Aegis/Mirror icons):** when a status icon appears: scale
   pop 1.5 -> 1.0 over 0.18 s + a ring (Juice ring at the icon, via screen->board px conversion or an own pooled ring
   on the bottom strip: choose the simpler, document it). Remaining <= 25 % (min 1 s) or <= 2 s: icon blinks
   (alpha 1 <-> 0.55 at 4 Hz). When it disappears because it expired: small shatter (4-6 shards, colour by status class)
   instead of a hard hide; consumed-by-hit shield stacks (shield count down) give a smaller pop. Layout re-pack
   slides icons to the new x over 0.12 s instead of snapping (simple lerp per icon, setter only when the rounded x changes).
4. **Status class colours:** a 2 px coloured edge around each icon: buff gold (shield, fire_shield, lifesteal), debuff
   violet/red (curse, heal_block, stun, sandstorm), enemy buffs (aegis gold, mirror silver). Table in `ui/assets.lua`.
5. **Player aura:** while shield / fire_shield / lifesteal are active, a soft pulsing halo around the player HP bar in the
   status colour (blue-white shield, orange fire shield, green lifesteal); curse = slow violet pulse, stun = lilac.
   Stacks combine by showing the highest priority only (priority: stun > curse > fire_shield > shield > lifesteal).
   One pooled glow texture pair on the bottom strip, soft texture (`A.soft`) with fallback to a masked round colour.
6. **Block / reflect feedback:** `attack_blocked`: blue-white ring + short vignette flash (cyan-white, peak 0.35) and a
   shield-icon punch (scale 1.4 -> 1.0) on the shield status icon; `attack_reflected`: the existing orange flash + icon
   punch on the fire_shield icon. Heal: green ring at the player bar.
7. **Damage numbers:** pop scale 1.6 -> 1.0 in 0.12 s (ease out), then rise + fade as before; crits/boosted bigger and
   with a short outward shake (+-3 px for 0.15 s); numbers of a burst within 0.12 s on the same side are stacked
   (vertical offset +14 px per extra, max 3) so they stay readable. Heal numbers float up slower, green. Player damage
   numbers shake slightly scaled by damage / max HP. FontStrings are reused; `SetScale` only on quantised change
   (if `FontString:SetScale` is not verified: use `SetFontObject` size steps or pcall + fallback to current look).
8. **Windup telegraph:** during `enemy_winding_up` the enemy figure gets a growing glow (cast tint, alpha 0 -> 0.5 over
   the windup, pulsing faster near the end), the queue slot pulse stays, and the board edge vignette pulses in the
   intent colour (red attack, purple curse, brown junk, silver mirror/aegis, orange special) at alpha <= 0.2 over the
   last 40 % of the windup. At the hit the existing cast flash fires. Windup length and kind come from existing state
   (`hud_state.enemy_winding_up`, ability kind in `enemy_windup(ability, windup)`).
9. **Enemy entrance:** `_on_fight_started`: the figure slides in from the right (24 px) while fading 0 -> 1 over 0.35 s, a
   soft ring at the feet, name text punches in; no effect on the sim (fight already runs; keep it short).
10. **Enemy death:** on `enemy_defeated`: after the death animation starts, a burst of soft light motes rising from the
    figure (12-20 particles, gold + enemy-hit tint) and a white additive flash (0.15 s) before the existing fade; the
    fade is accompanied by a slight upward drift (6 px). Boss death: bigger burst + trauma (existing TRAUMA_CLEARED) + a
    wide ring.
11. **Phase change:** `enemy_phase_changed`: ring across the enemy panel (Juice impact at the enemy, weight 2), trauma 0.3,
    cast-tint flash, name text punch.
12. **Score plaque:** `score_awarded(amount)` -> plaque punch (scale 1.0 -> 1.12 -> 1.0 in 0.2 s) and a gold glint; bigger
    amounts a bigger punch (cap). `score_awarded` must be subscribed/unsubscribed in bind/unbind (check it is a combat
    event: `core/combat.lua:488`).
13. **Debug panel:** new buttons (tab "Hit FX" or in the existing Board FX tab if room): Chip damage / Heal flash /
    Low HP on-off / Status pop (each status) / Status expire shatter / Aura (each) / Block / Windup telegraph (per kind) /
    Enemy entrance / Death burst / Phase change / Score punch / Damage number stack.

## Alternatives considered

- `AnimationGroup` for pops/chips: rejected (wall clock; project is sim-time driven).
- Spring-based UI animation lib: rejected (new dependency, no need).

## Why this could be wrong

- The player bar strip is small (30 px high); chip, glow, aura and status edges may visually compete with the 7 icons.
  Constants and a debug toggle per layer; reduce first the aura alpha.
- Too many simultaneous blinking elements (low HP + status blink + windup vignette) read as noise: priorities in 2/8 limit
  overlapping; playtest decides.
- `FontString:SetScale` is unverified live; fallback path must keep numbers readable.

## Non-goals

New sounds, core rule changes, hit-stop, changing status durations.

## Tests / acceptance

- New `test/ui_hitfx_test.lua` (registered in `tools/checks.sh`) + extensions: chip holds then slides (values at
  t = 0 / 0.35 / 0.6 sim), heal flash, low-HP thresholds + off conditions, status pop / blink windows / shatter on expire,
  consumed shield stack pop, slide re-pack converges, class colour table covers every status id, aura priority, block /
  reflect effects fire once, number pop + stacking offsets + bounded pool, windup telegraph alpha monotone and cleared at
  the hit / on stun / on halt, entrance and death sequences end in the old resting state (alpha 1 / 0, position exact),
  phase change, score punch cap, no new frames/textures/tables per frame (allocation budget as in `ui_boardfx_test`),
  fallback without `A.GLOW`, `FightView:halt` clears every new effect.
- `tools/checks.sh` green with lua5.1 AND luajit.
- User playtest in WoW.

## Deviations

- New module `ui/hit_fx.lua` (stand-in `HitFx.NONE`); `fight_view.lua` only forwards events / state. Also new in `Assets`: `STATUS_EDGE`,
  `AURA_ORDER`, `STATUS_AURA`, `INTENT_TINT` and the colours `CHIP_*`, `HEAL_FLASH`, `LOW_HP`, `VIG_BLOCK`, `RING_*`, `DEATH_*`, `SCORE_GLINT`.
- (3) Status rings use Juice rings at the icon's board position (computed from the layout constants) instead of an own pool.
  The shatter also uses Juice bursts. The status icons are now centre-anchored (a `home` anchor table per icon, scaled via
  `Frame:SetScale` with divided offsets); the four enemy icons were re-anchored to their centres (same place).
- (4) The 2 px class edge replaces the old black 1 px edge (the icon's edge texture is +-2 px, coloured), so neighbouring edges
  overlap by 1 px in the strip (gap 3).
- (2) The heartbeat and the telegraph share one extra vignette frame (own colour) next to the view's flash vignette; the telegraph wins.
- (7) Stacking / pop / shake apply to the enemy and player number pools only; the board floats (match text, ability names) are
  `plain` and unchanged. Without `FontString:SetScale` (probe) the pop is the big font for 0.12 s.
- (9) The entrance ring at the feet is an own texture (not a Juice ring: a fight start must not occupy the shared ring pool).
  A figure killed during its entrance fades out from full alpha.
- (12) Only `score_awarded` (ability activations) punches the plaque, as specified; match points arrive as `score_changed`
  and do not punch (one-line change in `FightView` if wanted).
- Existing tests changed on purpose: `ui_smoke` ("new enemy visible" now waits for the 0.35 s entrance), `ui_juice_test`
  (knock-back test waits out the entrance), `ui_debug_test` / `ui_boardfx_test` (nine tabs). `wow_stubs.lua` got `Region:SetScale`
  (raises with `W.no_region_scale`).
- Debug buttons for chip / heal are visual only (chips need HP below full: use the Status tab "Hurt player").
