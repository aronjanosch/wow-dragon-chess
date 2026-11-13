# Spec: W0-P9 — Hit / cast / aura FX that are not just circles

Status: drafted — awaiting agreement (short on purpose: the implementing agent may get creative inside the rules).
Milestone: W0 addon. Track: P (presentation). Issue #53 (feel). Follows W0-P8 (`docs/specs/w0-p8-hit-status-readability.md`).

## Problem (playtest 5, 2026-10-05)

- Hit reactions, enemy cast flashes and status looks are mostly **additive discs / rings**. A hard-edged orange disc
  covers the whole enemy when an enemy ability lands (`cast_glow`, `fight_view.lua`, built from `C.CAST_TINT`); the same
  family: `hit_glow`, `aegis_glow`, `mirror_glow`, `hit_fx.lua` halos, `Juice:ring`. They look flat and cheap, and when the
  soft glow texture does not load they fall back to a plain coloured disc.
- Dota Dragon Chess reference: hits are slashes, shards, sparks, shockwaves with direction and weight, not round blobs.

## Goal

Every hit / cast / aura reads by **shape and motion**, not by a coloured circle. No full-enemy disc anywhere. A first
glance tells apart: player match hit (colour by gem), crit, ability hit, enemy melee, enemy special cast, shield / mirror /
aegis up.

## Rules (unchanged from W0-P6..P8)

Sim time only, pooled (created once), no per-frame allocation, setters only on quantised change, pcall on unverified
API, everything stops in `FightView:halt`, a failing module must not break the window. Textures: use what the client
has (`A.GLOW`, spell visual textures, the WoW Classic `Spells\\` / `Interface\\` art listed in
`docs/design/wow-effect-textures.md`; find more with `tools/wow_asset.sh`). No solid-colour fallback disc: if a
texture does not load, **skip the effect** (log once), never draw a hard disc.

## Scope (agent decides the look; suggestions, not orders)

1. **Remove the hard discs:** `cast_glow` / `hit_glow` / `aegis_glow` / `mirror_glow` as full discs go. Replace with
   shaped FX (below) or nothing.
2. **Player hits on the enemy:** directional slash streaks / claw marks aligned to the incoming projectile angle,
   spark / shard spray from the impact point, a quick shockwave arc (not a full ring), size by damage power, crit =
   cross-slash + bigger spray. Gem colour tints it.
3. **Enemy hits on the player / enemy casts:** a telegraphed shape at the source (windup gather: converging sparks or a
   charging glyph), then a directional lunge streak or beam toward the player HP bar or board edge; specials get a
   distinct silhouette (fan, spike, wave) per ability `kind` (`plain`, `stagger`, `nuke`, `curse`, `sand`, `mirror`, …).
4. **Statuses on the enemy (Aegis, Mirror, stun, freeze, curse):** shaped overlays (scale pattern, facets, chains,
   rune glyphs) in the enemy panel instead of round glows; keep them low-alpha so the model stays visible.
5. **Player aura (lifesteal, shield, fire shield, curse):** edge-hugging flames / motes / runes around the HP bar or
   portrait region, not a disc.
6. Keep the debug panel Hit FX tab: every new effect must be triggerable there (one button each) and be listed in
   `docs/design/wow-effect-textures.md` with its textures.

## Out of scope

Board gem effects (W0-P7), sounds, balance, new art outside what the client ships.

## Why this could be wrong

- Texture-based shaped FX may look worse in a small panel than the soft discs; check at `/dchess` window scale 1 and 2.
- More distinct effects = more to read at once in real time: a hit must stay readable under a chain of 4+ matches
  (cap simultaneous FX, scale down under load).
- Not all Classic spell textures are usable (alpha / tiling); the agent verifies in game and reports misses.

## Definition of done

`tools/checks.sh` green; new FX covered by the existing pool / allocation tests; spec checklist reported with
deviations; user playtest decides the look. Update `docs/design/wow-effect-textures.md`.
