# Spec: W0-G3 — Ladder curve (MC → ZG → AQ), fewer stuns, Divine Shield ult, Flamestrike frame

Status: DRAFT rev 2 (after critic review 2026-10-10) — awaiting agreement.
Milestone: W0. Track: G (+ C roster/models, + one P fix).
Pillars served: readable real-time combat (one new mechanic at a time, telegraphed), WoW Classic fantasy (stages are
instances, X-3 is the instance's end boss).

## Player experience goal

The run starts gently and teaches one enemy mechanic at a time: the first enemy only bites, the second has one harmless
trick, stuns only appear at bosses. Pressure rises stage by stage; later normals bring one ability you must watch for;
bosses have two abilities, C'Thun three. Every stage is one Classic instance and ends with its real end boss. You get a
"panic button": Divine Shield (Emerald ult) makes you invulnerable for a few seconds and heals a bit — cast it just
before the big hit you see coming.

User input (2026-10-10, chat): "1-2 has a hit that already does several 1000 damage", "not all of them should just
stun", "first none, 2nd one but not yet a stun, then later harsher ones", "X-3 is always the boss round,
bosses have more abilities (2, 3 at the end)", "a heal instead of just lifesteal, briefly invulnerable + heal, that you can
time" (must be an ult: Emerald, replaces Rain of Fire — "let's try it"), stages MC → ZG → AQ,
"fireball animation again clipped by the frame and too big".

## Current state (facts)

- Ladder: `core/run.lua` `Run.STAGE_SIZES = {3,3,3,1}`; `Run.ladder()` asserts `#list == 10` (roster order = `data/enemies.lua` `list`).
- Effective enemy damage = data × (1 + 0.2·(d−1)) × `ATTACK_PACE` 2.2 × `ENEMY_DAMAGE_SCALE` 0.9 → ×1.98 at d1, ×3.56 at d5; cooldown ×2.2.
  `cooldown` is the gap **after** an ability (`core/enemy.lua` `_execute_done`), so the first ability of a rotation
  fires after its own cooldown and later entries come late. `windup` is a constant 8/12 s (data test asserts it).
- Player HP 10 000; boss kill heals 25 % (`HEAL_PERCENT_AFTER_BOSS`).
- 1-2 Gordok Ogre: Ogre Smash → **950–1148** at d1 (**1710–2066** at d5) + 2.5 s stun ("mehrere 1000").
- Today 4 of 10 enemies stun, the first at 1-2. Rotation DPS today (critic, luajit): 1-1 45 · 1-2 16 · 1-3 — · stage 2 peaks at Hakkar · Nefarian P0 58 / P1 70 / P2 53 (max hit 2178).
- Stage label exists: `ui/assets.lua` `A.STAGE_NAME` ("Dire Maul" for stage 1), `STAGE_BG_FILE[1] = 340663`; `fight_view` `stage_line`.
- Emerald kit `core/abilities/emerald.lua`: Power Word: Shield (skill), Rain of Fire (ult, only bomb source). Rain of
  Fire is referenced in `core/kit.lua`, `ui/assets.lua` (icon, sound `ab_rain_of_fire`, FX) and `ui_fx_test.lua`.
- Ruby ult Fire Shield already nullifies + reflects every hit for 10 s.
- Flamestrike FX: frames are board-sized (512 px); a cone effect's visual centre sits `CONE_SHIFT` 0.45 × size right of
  the gem cell, so from the right columns the **visible** effect overflows the board by up to ~0.95 × size. The shift,
  not only the size, is the cause. ("Fireball" = Flamestrike is an assumption — no fireball FX exists.)

## Changes

### 1. Roster and ladder (data/enemies.lua, ui/assets.lua)

Rules (into `docs/design/enemies.md`):
- **Normals: exactly 1 special** (1-1: none), each mechanic appears once among normals.
- **Bosses: 2 specials, C'Thun 3; Nefarian keeps his phases.** **Stuns only at bosses** (Ragnaros, C'Thun, Nefarian).
- **Every special lands within 30 s** of the fight start at d1 (rotation order: specials early; data test).
- Existing ability kinds only.

Values = data (before ×1.98 at d1); rotation listed in firing order; cd = data cooldown (×2.2 in play).

| # | Enemy (instance) | Model | Rotation (firing order) | HP d1 | DPS d1 / d5 | max hit d1 |
|---|---|---|---|---|---|---|
| 1-1 | **Core Hound** (MC), id stays `hellhound` | existing | Bite 80–105 cd 3.0 | 2250 | 25 / 45 | 208 |
| 1-2 | **Molten Giant** (MC) | **new** | Fist 150–190 cd 3.0 · **Molten Slag** junk 3 cd 4.0 · Fist | 3750 | 27 / 49 | 376 |
| 1-3 | **Ragnaros** (MC boss) | **new** | Hammer 110–140 cd 3.5 · **Wrath of Ragnaros** stagger 180–220, 2.0 s stun, cd 3.5 · **Magma Blast** nuke 380–460 cd 4.0 · Hammer | 6500 | 50 / 90 | 911 |
| 2-1 | **Gurubashi Berserker** (ZG) | forest troll | Axe 200–250 cd 3.0 · **Regenerate** self-heal 8 % cd 3.0 · Axe | 5000 | 41 / 74 | 495 |
| 2-2 | **Razzashi Raptor** (ZG) | **new** | Bite 120–150 cd 3.0 · **Claw Flurry** 4–5 × 55–75 cd 4.0 | 4250 | 49 / 89 | 297 |
| 2-3 | **Hakkar** (ZG boss) | existing | Blood Strike 120–150 cd 3.0 · **Corrupted Blood** heal block 15 s + 200–240 cd 3.0 · **Blood Siphon** nuke 480–580 cd 4.0 · Blood Strike | 7500 | 65 / 116 | 1148 |
| 3-1 | **Qiraji Scarab** (AQ) | existing | Bite 300–360 cd 3.0 · **Weakening Venom** curse ×0.7 8 s cd 3.0 | 4500 | 45 / 81 | 713 |
| 3-2 | **Anubisath Sentinel** (AQ) | existing | Strike 280–340 cd 3.0 · **Reflect** Mirror Shield (today's matriarch values) cd 2.0 · Strike | 5000 | 63 / 113 | 673 |
| 3-3 | **C'Thun** (AQ boss) | **new** | Eye Beam 300–360 cd 3.0 · **Eye Tentacles** junk 4 cd 3.0 · **Dark Glare** stagger 420–500, 2.5 s, cd 3.0 · **Carapace** aegis 7 s cd 3.0 · Eye Beam | 9000 | ~61 / 110 | 990 |
| 4 | **Nefarian** (BWL finale) | existing | unchanged | 13750 | 58–70 / 104–126 | 2178 |

- Curve (DPS d1): 25 · 27 · **50** | 41 · 49 · **65** | 45 · 63 · **~61** | Nefarian 58–70 with the biggest hit.
  C'Thun ≈ Hakkar on DPS but with 3 specials (junk + stun + aegis). Computed with the critic's rotation model
  (avg hit / cycle, no player actions); the bot / playtest decides the final numbers.
- Max hit of a stage-1 normal at d1: 376 (was 1148). First stun at Ragnaros, ≈ 16 s in.
- Ladder stays 3/3/3/1; difficulty / pace / damage scale unchanged.
- **Retired** (Gordok Ogre, Basilisk Matriarch, Harpy, Ouro): defs move to a non-ladder `EnemyData.retired` list,
  still in `by_id`, so debug / tests / probe can still reach them. `hellhound` and other kept ids stay unchanged
  (only `name` changes) — records, framings and tests keep working.
- Stage labels / backgrounds (`A.STAGE_NAME`, `STAGE_BG_FILE`): "Molten Core" (MC art 340678 from `roster.md`),
  "Zul'Gurub", "Ahn'Qiraj", "Blackwing Lair" (keep existing art where it fits).
- New models (Molten Giant, Ragnaros, Razzashi Raptor, C'Thun): display IDs from wago.tools, framing tuned live by the
  user in the debug panel; `MODEL_DEFAULT` until then. Sounds: closest `sound/creature/*` or none.

### 2. Divine Shield replaces Rain of Fire (Emerald ult)

- `core/abilities/emerald.lua`: new `A.divine_shield` (color 2, tier 2): **invulnerable 3.0 s + heal 10 % of max HP**
  (1000), score 450. Kit ult = divine_shield (`core/kit.lua`). `rain_of_fire` table stays unused; bomb code untouched.
- Timing in honest terms: there is no per-hit reaction window (wind-up is 0.67 s); you **pre-cast within 3 s before a
  hit** you see coming on the enemy's cooldown sweep. Unlike Frost Nova (freeze stops the attack timer but not a hit
  already in flight), Divine Shield also absorbs an in-flight hit.
- `core/combat.lua`, new timed status `invulnerable`:
  - added to `TIMED_STATUSES` (start / serialize / deserialize / hud_state); cleared in `start_fight` (no carry-over).
  - `take_damage`: first check → result `"immune"`, no HP loss, no shield stack spent, no Fire Shield reflect.
    Stagger stuns only on `"hp"` → no stun; flurry hits are each immune.
  - `take_true_damage` (Mirror reflect, Mirror break) is also blocked while invulnerable.
  - the heal uses a new heal path that **honours heal block** (like the lifesteal branch; `heal_player` ignores it on
    purpose for the boss heal) — under Corrupted Blood the heal is 0 and a "HEAL BLOCKED" float shows, immunity works.
  - re-cast refreshes the duration (no stacking).
- UI: status strip icon with countdown, player aura (after stun in `HitFx.aura_pick`, `AURA_ORDER`, `STATUS_AURA`),
  "IMMUNE" float per blocked hit, the bubble as a **held** FX (`Fx:hold`, m2 165961) for the whole duration (not a
  one-shot). New icon / sound / FX keys `divine_shield` in `ui/assets.lua`. PW:Shield FX unchanged.
- Debug panel / ult spawn lists pick it up from the kit (no special-case code).

### 3. Flamestrike / cell effects stay on the board (ui/fx.lua, ui/assets.lua)

- Clamp the **visible centre** of one-shot `cone` and `cell` effects: `cx = clamp(cx, size/2, board_w − size/2)`
  (same for `cy`); the 512 px frame may overhang, the effect does not.
- Flamestrike `size` 280 → **200** (tune live).

### 4. Tests and docs touched

- Tests: `enemy_data_test.lua` (ladder ids, Godot golden map, display assertions → for ladder only), `run_test.lua`,
  `debug_test.lua`, `ui_debug_test.lua`, `ui_smoke.lua` ("DIRE MAUL" ×6 → "MOLTEN CORE"), `enemy_test.lua`,
  `ui_fx_test.lua` (Ouro sound / `fight ouro`, rain_of_fire key loops, cone positions ~l.398–420), `ui_hitfx_test.lua`,
  `ui_juice_test.lua`, `ui_menu_test.lua`, `fight_bot_test.lua`, `enemy_stub_test.lua`; probe addon `probe` if it
  names removed ids.
- Docs: `docs/design/enemies.md`, `roster.md`, `abilities.md`, `classes-and-abilities.md`, `run.md`, `wow-addon.md`.

## Alternatives considered

- **Only rescale numbers, keep roster:** fixes 1-2 damage but not "all stun" or theme; user asked for both.
- **Divine Shield as Emerald skill (replace PW:Shield):** user: must be an ult.
- **Dire Maul / leveling dungeons as stage 1:** user chose MC → ZG → AQ.
- **Keep Ouro as AQ boss:** not AQ's end boss → C'Thun.
- **Divine Shield heal only from blocked damage** (critic option): more skill-coupled but invisible math; flat 10 % is
  readable. Revisit if pre-casting feels mindless.
- **Per-boss longer wind-up for nukes** (field exists): not in scope; first see if pre-cast timing is enough.

## Why this could be wrong

- **Stage 1 too easy:** 25–27 DPS for two fights. Fix: raise HP, not hit size.
- **Divine Shield vs Fire Shield:** Fire Shield (10 s nullify + reflect) out-defends a 3 s bubble; Divine Shield's
  edge is the heal and that it also covers true damage. If nobody picks Emerald ult moments over Ruby, raise to 4 s.
  vs Frost Nova: distinct (freeze delays, bubble absorbs in-flight + heals).
- **10 % heal vs attrition economy:** one cast ≈ 15–40 s of enemy DPS; at 20 % it would be 80 % of a boss-kill heal
  (critic). If runs become unloseable, drop to 5 %.
- **No more bombs:** Rain of Fire was the only bomb source and a fun board effect.
- **Curve is a model:** avg-hit maths without player stuns / freezes / delays; the bot (W0-T2) or playtests decide.
- **New models cost tuning time** (4 displays + framing); placeholders work meanwhile.

## Critic findings addressed (2026-10-10)

Curve didn't ramp (C'Thun 18 DPS, stage 3 trough, 1-2 below 1-1) → all values retuned, table with computed DPS /
max hit, Hakkar nuke down, stage-3 up. Late specials invisible (cooldown = gap after) → rotations reordered, "every
special within 30 s" rule + data test. Divine Shield 20 % heal dominant → 3 s + 10 %. "React during wind-up" wrong
→ reworded to pre-cast; Frost Nova difference stated. Missing invulnerability paths → `take_true_damage`, Fire Shield
order, heal-block path, `TIMED_STATUSES`, aura order specified. Test/fixture fallout → `retired` pool, ids kept, full
touch list. Fire Shield overlap → in risks. Stage label exists → renamed + MC art. Duplicate junk at 3-1 / Raptor =
Harpy → 3-1 gets curse, C'Thun gets junk; Raptor gains a basic bite. One-shot FX for a state → `Fx:hold`. Flamestrike
clamp of the frame impossible → clamp the visible centre, also for `cell` effects.

## Non-goals

- No new enemy ability kinds, no change to difficulty multipliers, pace, player HP, boss heal.
- No class kits (W1-G1), no roguelite layers. Nefarian unchanged. No art beyond model ids + framing.

## Tests / acceptance

- Data test: ladder = 10; normals exactly 1 special (1-1: 0); bosses 2–3; stun kinds only on `is_boss`; every special's
  first firing ≤ 30 s at d1 (sum of `cooldown × ATTACK_PACE + windup` along the rotation); windup + max < cooldown.
- Combat test: invulnerable → `take_damage` = `"immune"`, HP unchanged, shield stack kept, no Fire Shield reflect,
  stagger no stun, `take_true_damage` blocked, heal 0 under heal block (immunity active), expiry after 3.0 s Clock time,
  re-cast refreshes, cleared on `start_fight`, serialize round trip.
- Kit test: Emerald ult = divine_shield.
- Run test: max effective hit of 1-2 at d1 < 400.
- FX test: Flamestrike from column 8 → visible centre inside the board.
- `tools/checks.sh` all green.
- User playtest: stage 1 gentle but not boring; first stun at Ragnaros readable; Divine Shield timing feels good;
  C'Thun / Nefarian feel like the peak.

## Open decisions

1. Divine Shield: **3.0 s invulnerable + 10 % heal** (critic; user had no number yet).
2. Retired enemies stay in data as `retired` (for later pools): **yes**.
3. Is "Fireball" = Flamestrike? **Assumed yes** — user to confirm.
