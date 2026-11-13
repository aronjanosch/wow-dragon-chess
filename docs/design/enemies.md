# Enemies — Godot mechanics reference

> **Old → new id map (W0-G2c, implemented):** `cerberus_puppy → hellhound`, `cyclops → gordok_ogre`, `medusa → basilisk_matriarch`, `troll → forest_troll`, `valkyrie → harpy`, `thor → hakkar`, `mummy → qiraji_scarab`, `anubis → anubisath_sentinel`, `sphinx → ouro`, `world_dragon → nefarian`. Enemy abilities: Puppy Bite → Hellhound Bite, Eye Poke → Ogre Punch, Club Smash → Ogre Smash, Snake Jab → Basilisk Bite, Stone Gaze (kept), Claw → Axe Swing, Valkyrie Flurry → Wing Flurry, Thunder Jab → Blood Strike, Thunderclap → Cause Insanity, Hammer Charge → Blood Siphon, Mummy Strike → Scarab Bite, Bandage Wrap → Web Spray, Anubis Strike → Sentinel Strike, Judgement Curse → Curse of Weakness, Weighing of the Heart → Mortal Strike, Riddle Lock → Sand Trap, Sphinx Strike → Sand Blast, Typhon Strike/Roar → Wing Buffet / Bellowing Roar, Nidhoggr Flurry / Corpse Rot → Claw Flurry / Veil of Shadow (phase "Shadow Flame"), Apep Sandstorm / Nuke → Blinding Ash / Shadow Flame Breath (phase "Corrupted"). Mechanics and numbers unchanged; `test/golden_enemies.lua` stays keyed by the Godot ids.
>
> **Superseded naming (2026-10-04):** the addon uses a WoW Classic roster ([roster.md](roster.md)); the names below are the *old Godot names*. Numbers, rotations and mechanics here remain the reference (they are ported 1:1 to `data/enemies.lua`).

# Enemies — current state

Audited 2026-09-28 (M1-G9 boss mechanics). Data: `scenes/enemies/*.tres` (EnemyData), abilities in
`scenes/enemies/abilities/*.tres` + scripts. Values below are **difficulty 1** (×10 economy since M1-G1; enemy
HP ×2.5 since M1-G8, legacy enemies too); difficulty scaling is in [run.md](run.md). Sprites are placeholders (3 shared asset packs) until the new art
direction lands.

## Roster (ladder order)

| Stage | Fight | Enemy | HP | Weak to | Rotation (damage, cooldown) |
|---|---|---|---|---|---|
M1-G9 knobs are at the hard end of the pre-agreed ranges after the probe (stagger 2.5 s, heal
block 15 s + hit ×1.2, Mirror 60 % / break 500, Sandstorm ×0.3; Aegis stays 7 s), see
`docs/playtests/data/2026-09-28-probe-m1-g9.md`. Rotation order as it runs; the cooldown after an ability is the wait before the next one (= the
next intent's telegraph time).

| Stage | Fight | Enemy | HP | Weak to | Rotation (damage, cooldown) |
|---|---|---|---|---|---|
| 1 Greek | 1 | Cerberus Puppy | 2250 | Topaz | Puppy Bite 120–160 / 2.5 s |
| | 2 | Cyclops | 3750 | Sapphire | Eye Poke 180–240 / 3 s, **Club Smash** stagger 480–580 + stun 2.5 s / 8 s |
| | boss | Medusa | 6000 | Ruby | Snake Jab 180–240 / 3.5 s, **Stone Gaze** stagger 420–520 + stun 2.5 s / 7 s, Snake Jab, **Mirror Shield** 8 s, 60 %, break 500 / 2 s |
| 2 Norse | 1 | Troll | 5000 | Ruby | Claw 240–300 / 5 s, **Rend** heal block 360–432 + 15 s / 5 s, Regenerate 8 % HP / 7 s |
| | 2 | Valkyrie | 4250 | Emerald | Flurry 4–5 × 80–110 / 9 s |
| | boss | Thor | 7500 | Amethyst | Thunder Jab 220–280 / 4 s, **Thunderclap** stagger 250–300 + stun 2.5 s / 4 s, **Divine Aegis** 7 s / 3 s, Hammer Charge 750–950 / 8.5 s (charge nuke; lands while immune) |
| 3 Egyptian | 1 | Mummy | 4500 | Ruby | Bandage Wrap 3 junk / 6 s, Mummy Strike 200–260 / 5 s |
| | 2 | Anubis | 5000 | Sapphire | Anubis Strike 280–340 / 5 s, Judgement Curse ×0.7 for 8 s / 10 s, **Weighing of the Heart** heal block 540–660 + 15 s / 6 s |
| | boss | Sphinx | 8500 | Amber | Riddle Lock 4 junk / 7 s, Sphinx Strike 450–550 / 7 s (special), **Sandstorm** gravity ×0.3 for 8 s / 3 s |
| 4 Final | boss | The World Dragon | 13750 | — | Typhon Strike 400–500 / 6.5 s, **Typhon Roar** stagger 300–360 + 2.5 s / 5 s → phase **Níðhöggr** (Flurry 3–4 × 120–160 / 7 s, **Corpse Rot** heal block 600–720 + 15 s / 6 s, Typhon Strike) → phase **Apep** at 33 % HP (**Apep Sandstorm** ×0.3 for 8 s / 4 s, Apep Nuke 900–1100 / 9 s, **Mirror Scales** 8 s, 60 %, break 500 / 3 s) |

Unused legacy data: `dragon.tres` (and its abilities, incl. Paralizing Goo, a damage-0
`StunAbility`). `slime.tres`, `slime_king.tres`, `goblin.tres` were removed in the repo cleanup.

## Ability types (scripts)

| Script | Effect | Readable as |
|---|---|---|
| `enemy_ability.gd` | Plain hit (rolled damage) | red streak to HP bar |
| `charge_nuke.gd` | Marker for a big telegraphed hit; stun/freeze/slow delay it (answer by banking) | special chrome in queue |
| `multi_hit.gd` | Burst of small hits (per-hit damage, 0.12 s apart) | rapid streaks |
| `heal_self.gd` | Heals % of max HP | green heal on enemy |
| `spawn_junk.gd` | Turns random plain gems into bandage junk (clears when a neighbour clears, 0 dmg) | cast aimed at board + debris |
| `damage_debuff.gd` | Curse: player outgoing damage × multiplier for a duration | purple HP bar + drip |
| `stun.gd` | **Stagger** (M1-G9): rolled hit inside `execute` (roll_damage 0, MultiHit pattern); stuns the player `stun_duration` s (float) only if the hit reached HP (`battle.take_damage` → `"hp"`), never in god mode; damage 0 always stuns | STUNNED overlay |
| `heal_block.gd` | **Heal block** (M1-G9): rolled hit, then player healing ×0 for `duration` s (applies even if the hit was blocked; not in god mode) | grey icon + dark HP bar, grey "0" Lifesteal ticks |
| `spell_immunity.gd` | **Divine Aegis** (M1-G9): enemy spell-immune for `duration` s (rules in [combat.md](combat.md)) | gold tint + gold icon, grey "IMMUNE" |
| `mirror_shield.gd` | **Mirror Shield** (M1-G9): `reflect_fraction` of ability / bomb packets back as true damage for `duration` s; `break_damage` match damage shatters it + stuns the enemy `break_stun` s | silver tint + silver icon (punches per crack), silver reflect streak, SHATTERED |
| `board_slow.gd` | **Sandstorm** (M1-G9): `board.set_gravity_slow(factor, duration)` — falls take 1/factor as long | sand tint over the board + sand icon |
| `grid_rip.gd` | **Rip** (`GridRipAbility`, M1-X1 grid-fight prototype only, `grid_rip.tres`: count 1, 6 s): no-op in the main game; the grid scene tears `count` filled cells out of the enemy grid after a 0.6 s flash (never locked rows / cells < 3 s old); M1-X1.2: in the rotation only every second cycle, and grid-mode enemy hits deal ×0.6 (on copies) | "rip" glyph in the queue, RIP banner, red X flash on the cells |

## Rules

- Stage power is authored per enemy `.tres`; only difficulty scales at runtime: `damage_min/max`
  of every ability (incl. staggers and heal-block hits) × the damage factor, a Mirror Shield's
  `break_damage` × the HP factor; stun / window durations are not scaled.
- All new M1-G9 abilities are special intents (special chrome in the attack queue, banner on cast);
  glyphs `bolt` (stagger), `heal_block`, `aegis`, `mirror`, `sand` (`status_glyphs.gd`).
- Phases (`EnemyPhaseKit`): rotation swaps when HP drops below `hp_fraction` (checked descending),
  with a banner and the attack queue rebinding.
