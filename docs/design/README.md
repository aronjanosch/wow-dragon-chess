# Design docs — current state

> **Addon pivot (2026-10-04):** these docs describe the Godot game, which is the rules reference for the WoW addon port. What is ported/cut: [wow-addon.md](wow-addon.md). [boons.md](boons.md) and the roguelite parts of [run.md](run.md) are **out of scope for the addon** (kept for later re-import).

Living descriptions of how each system works **today**. Specs are deltas. When an
implementation changes a system, update the matching file here in the same change (part of the
definition of done). If a doc and the data (`.tres` / code constants) disagree, the data wins —
fix the doc.

| Doc | Covers |
|---|---|
| [combat.md](combat.md) | Board, matching, damage, ability queue, statuses, enemy attacks |
| [abilities.md](abilities.md) | The 12 player abilities (6 colours × skill/ult) with values |
| [enemies.md](enemies.md) | Roster per stage, enemy ability types, bosses/phases |
| [run.md](run.md) | Run structure, healing, difficulty, persistence |
| [boons.md](boons.md) | Boon draft between fights, offer rules, the 18 boons |
| [wow-addon.md](wow-addon.md) | Addon layout, port map, what is cut (draft) |
| [wow-forever-api.md](wow-forever-api.md) | WoW Forever API facts + external references (forever-addon-kit) |
| [classes-and-abilities.md](classes-and-abilities.md) | Ability model: 12 effect templates, spell variants, class kits, canonical names (draft) |
| [roster.md](roster.md) | WoW Classic enemy roster replacing the Godot names (draft) |
| [audio.md](audio.md) | Sound slots: events, abilities, enemy attacks → WoW SoundKit IDs (draft) |
| [scoring.md](scoring.md) | Score values and known gaps |

Prototype (not part of the main game): the M1-X1 grid fight — `scenes/grid_fight/`, base rules in
../specs/m1-x1-grid-fight-prototype.md, ability pops give
pieces / singles / override / click-to-place in
../specs/m1-x1.1-grid-prototype-iteration.md, current
placement rules (silhouettes, sockets, Lift / Seal, pop clears, fewer singles) in
../specs/m1-x1.2-grid-placement-pressure.md, current
supply and controls (meter and double match give small pieces, per-colour shape pools, badge = next
draw, T flip / R rotate / D discard) in
../specs/m1-x1.3-grid-supply-variance.md.

Vision and pillars: [../VISION.md](../VISION.md). Plans: [../ROADMAP.md](../ROADMAP.md).
