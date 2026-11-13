# Spec: W1-G2 — Amber becomes the healing colour: HoT skill + strong heal ult

Status: agreed rev 2 (2026-11-11) — direction and the 15 % by the user, details by the director, critic review worked in.
Milestone: W1. Track: G (+ presentation data for the new spells). Follows W1-G1 (class kits).
Pillars served: readable real-time combat (a heal you can see and time), WoW Classic fantasy (Rejuvenation is a HoT,
Lay on Hands is a big heal).

User input (2026-11-11, first look at the class kits): "Noticeable on Druid: Rejuv is not a HoT, it should heal at least a
little. And I think healing would be better as an ultimate, generally across the classes, but then also strong,
maybe around 15 %." Decided in the follow-up: the heal ult **replaces the Amber ult** (convert 10 gems → Amber);
the Amber skill becomes a **real HoT** (heals by itself, no clears needed). This changes the balance on purpose
(the "keep the balance" rule of W1-G1 covered the reskin only).

## Player experience goal

Amber is your healing colour and it does what the icon says. A 4-match Amber gem is a small heal over time you
can fire and forget (Rejuvenation, Renew, Mend Pet). A 5-match Amber gem is your big heal — Lay on Hands, Healing
Touch, Healthstone: you keep it on the board and trigger it when your health is low. Heal Block (Forest Troll,
Anubisath Sentinel, Nefarian phase 1) stops both.

## Current state (facts, verified 2026-11-11; numbers from the critic's bot run on the current kit)

- Amber skill = `drain_life` (`core/abilities/amber.lua`): `combat:apply_lifesteal(10 s, 100 %)` — for 10 s every
  clear heals 100 % of its damage (`core/combat.lua` l.424–436; stacks via `extras` since playtest 5). Nothing heals
  without clears. In practice ≈ 350 HP per cast for a slow player, ≈ 650 for a fast one; ≈ 8 k per run at D1.
- Amber ult = `polymorph`: `sim:convert_random_gems(0, 10, -1, 0)`.
- Player HP 10 000; a boss kill heals 25 % (three per run = 7.5 k); enemy rotation DPS at D1 19–74 (× 1.4 at D3,
  × 1.8 at D5); biggest hits ≈ 1.7–2.0 k at D1, 3.0–3.6 k at D5.
- A fast first-legal-move bot (swap every 0.6 s) gets ≈ 1.2 Amber skills and ≈ 0.8 Amber ults per fight; at the
  1.5 s pace of the existing tests it dies in fight 3–4 at D1 (floor effect — useless for tuning).
- Ability gems are fired by any clear that reaches them (area / row / cone / bombs chain every `tier > 0` gem), so a
  banked heal can go off by accident; enemy junk skips ability gems.
- `start_fight` clears only `curse` and `heal_block`; `lifesteal` / `fire_shield` carry over between fights.
- Saved runs never store an ability id (ladder, class, HP, score, statuses by status id, board colours / tiers).
- `drain_life` / `polymorph` ids appear in: `core/kit.lua:27`, `core/classes.lua`, `core/abilities/amber.lua`,
  `ui/assets.lua` (icons, sounds, FX), `test/ui_fx_test.lua`, `test/ability_test.lua`. The status id `lifesteal`
  is the generic "timed buff" fixture in ~40 places of the UI tests.

## Changes

### 1. Core: the HoT and the heal (core/abilities/amber.lua, core/combat.lua)

- **A1 `rejuvenation` (skill, canonical = Druid): heal over time.** `hot_percent = 5` (% of max HP per cast = 500),
  `hot_ticks = 10`, `hot_interval = 1.0` s, score 150, damage 0. `execute` → `combat:apply_hot(total, ticks,
  interval)`.
  - The player status **`lifesteal` is renamed to `hot`** (same slot in `TIMED_STATUSES`, strip, aura, tests) and
    the lifesteal logic is **deleted**: `apply_lifesteal`, `lifesteal_percent`, the `extras` stacking, the heal
    branch in the clear handler, the `percent` field. (Curse / Aegis thereby stop affecting healing — intended.)
  - **One chained Clock timer** (`core/clock.lua`, so freeze / thaw, the gameplay pause between fights and
    hide / soft pause all cover it): the first tick fires `hot_interval` after the cast; the callback heals,
    decrements `ticks_left` and restarts itself, or expires the status after the last tick (no separate expiry
    timer → no tie). The status icon appears at the cast.
  - **Cumulative rounding:** with total `T = round(max_hp × hot_percent / 100)` and `n` ticks, tick `k` heals
    `round(T·k/n) − round(T·(k−1)/n)` (sums to exactly `T` for any max HP).
  - **Re-cast while active: extend with a cap** — `ticks_left = min(ticks_left + hot_ticks, 2 × hot_ticks)`; the
    running tick timer is not restarted, the rate never doubles, a second gem is never wasted (up to 20 ticks).
  - `status_remaining("hot")` = `(ticks_left − 1) × hot_interval + clock:left(timer)`; `status_max` = the number of
    ticks granted since the status started × interval (so the countdown ring is honest after an extend).
  - **Serialize** `{ remaining, max, ticks_left, heal state for the cumulative rounding }`; deserialize re-arms the
    timer with the fractional remainder. Round trip mid-HoT must reproduce the exact same later heals.
  - **Ticks only heal in a live fight:** a tick while there is no live enemy (between restore and `start_fight`,
    after `game_over`) is skipped without consuming healing… simplest rule that satisfies this: the tick timer
    only runs on fight time like the other status timers, and the callback returns without healing when
    `game_over`. The HoT **carries over** into the next fight like `fire_shield` does (frozen during the beat).
  - **Heal Block:** a tick during Heal Block heals 0 (the tick is consumed), emits `heal_blocked`.
  - **Overheal:** at full HP a tick heals 0, emits nothing but `heal_lost(amount, "overheal", source)`.
- **A2 `lay_on_hands` (ult, canonical = Paladin): instant heal.** `heal_percent = 15` (1500 HP), score 450,
  damage 0. `Combat:heal_player(amount, source, blockable)`: when `blockable` and Heal Block is active → heals 0,
  emits `heal_blocked` + `heal_lost(amount, "block", source)`; overheal is lost (`heal_lost(…, "overheal", …)`).
  The boss heal keeps ignoring Heal Block (`blockable = false`).
- **Events:** `player_healed(amount, source)` with source `"hot"` / `"ult"` / `"boss"`; new `heal_lost(amount,
  reason, source)` (probe + UI). No RNG use anywhere in this item.
- **Deleted:** the `drain_life` (lifesteal) and `polymorph` (convert) ability definitions. `sim:convert_random_gems`
  stays (debug panel, soak, `effects_test`). `Kit.DEFAULT[0] = { "rejuvenation", "lay_on_hands" }`.
- Text uses absolute numbers through `text_extra` (max HP is flat): blurb "Heal {hot_total} over {hot_seconds}s" /
  "Heal {heal_total} health".

### 2. Class mapping for Amber (core/classes.lua, ui/assets.lua)

| Class | A1 — HoT skill | A2 — heal ult |
|---|---|---|
| Druid | **Rejuvenation** `Spell_Nature_Rejuvenation` | Healing Touch `Spell_Nature_HealingTouch` |
| Priest | Renew `Spell_Holy_Renew` | Greater Heal `Spell_Holy_GreaterHeal` |
| Paladin | Seal of Light `Spell_Holy_HealingAura` | **Lay on Hands** `Spell_Holy_LayOnHands` |
| Shaman | Healing Stream Totem `INV_Spear_04` | Chain Heal `Spell_Nature_HealingWaveGreater` |
| Mage | Conjure Food `INV_Misc_Food_10` | Evocation `Spell_Nature_Purge` |
| Warlock | Drain Life `Spell_Shadow_LifeDrain02` | Healthstone `INV_Stone_04` |
| Warrior | Bloodthirst `Spell_Nature_BloodLust` | Last Stand `Spell_Holy_AshesToAshes` |
| Hunter | Mend Pet `Ability_Hunter_MendPet` | Revive Pet `Ability_Hunter_BeastSoothe` |
| Rogue | First Aid `Spell_Holy_SealOfSacrifice` | Healing Potion `INV_Potion_54` |

- Removed variants: `battle_shout`, `blessing_of_kings`, `hunters_mark`, `instant_poison`, `power_infusion`,
  `flametongue_weapon`, `corruption`, `mark_of_the_wild`, `hemorrhage`, `vampiric_embrace`, `arcane_power`.
  `evocation` moves to A2 (its sound slot becomes a key sound). `drain_life` is now the Warlock's variant of
  `rejuvenation`; `rejuvenation` and `lay_on_hands` are canonical (not registered as variants again).
- **Mage M2 becomes Polymorph** `Spell_Nature_Polymorph` (variant id `polymorph` of template `mind_control`,
  replacing Arcane Power). Its sound / effect model are the existing Polymorph picks (569526 / 166649); placement
  and duration come from the `mind_control` template entry.
- Asset picks (listfile; the implementer completes the rest with `tools/wow_asset.sh` under the rules of
  `docs/design/class-kit-assets.md` and records them there): Lay on Hands 568145 `layonhands_low_chest` / m2 166452;
  Healing Touch: `healingtouch*` / `heal_low_base` 569570 / m2 166292; Greater Heal 568017 / m2 166273; Renew m2
  166696 `renew_base`; Revive Pet m2 166709; Conjure Food + First Aid m2 166204 `food_healeffect_base`; Last Stand
  568028 `battleshouttarget` / m2 165658; Healthstone, Chain Heal, Healing Potion: closest heal files. Both slots
  play on the player panel. All 18 icon names exist in the listfile.

### 3. Presentation (ui/)

- Status `lifesteal` → `hot` everywhere: `ui/assets.lua` (`status_hot` icon key, `STATUS_EDGE.hot`, `AURA_ORDER`,
  `STATUS_AURA.hot` — the old lifesteal green), `ui/fight_view.lua` (`PLAYER_STATUS`, `_apply_kit`: icon = the kit's
  A1 spell), `ui/hit_fx.lua` (`aura_pick`, dev entries), `core/debug.lua` (status names / apply list),
  `class_test` `KIT_STATUS`.
- `player_healed` handler by source: `"hot"` → a small green float + the HP bar heal flash only (no streak, no
  ring, no sound); `"ult"` → the big heal feedback (float, streak, ring / vignette) + the spell's sound and effect;
  `"boss"` as today. A heal that lands after the killing blow still shows.
- "HEAL BLOCKED" feedback is rate-limited to once per 3 s.

### 4. Measure, then fix the numbers (tooling)

- New `tools/balance_probe.lua` (headless, lua5.1; not part of `checks.sh`): full runs without god mode,
  **swap pace 0.6 s** (primary) and 0.9 s (casual row), difficulties **2 / 3 / 4** (+ 1 and 5 as sanity rows),
  **≥ 30 seeds** each, two policies: `first` (first legal move) and `hold` (skips moves that would fire an Amber ult
  gem while HP > 70 %, when another move exists). Prints a markdown report: run win rate with a Wilson 95 %
  interval, the fight the bot dies in, per fight: damage taken, min HP, HP at the end; per run: HP healed by source
  (`hot` / `ult` / `boss`), HP lost to overheal and to Heal Block, Amber skill / ult casts, share of heal ults
  fired below 60 % HP, HoT uptime.
- Run it on the commit **before** this change (lifesteal kit; heal by source = lifesteal) and **after**; both
  reports go to `docs/playtests/data/2026-11-11-amber-heals-probe.md`. Boards diverge after the first Amber ult,
  so compare distributions, not seeds.
- **Outcome gates (director decides after the report):** at pace 0.6 the D3 win rate should land in 55–85 % (today
  ≈ 67 %), D5 ≤ 25 % (today 0 %), median HP at fight end 40–75 %. If D3 > 85 %: `heal_percent` 15 → 12 first, then
  `hot_percent` 5 → 4. The two percents are the only knobs of this item.

### 5. Tests and docs

- `ability_test.lua` / `combat_test.lua`: ticks at +1 … +10 s with cumulative rounding (also for a max HP that does
  not divide, e.g. 12 345), extend-with-cap (cast at 9 ticks left → 19; at 15 → 20), expiry right after the last
  tick, pause / freeze / between-fight beat do not tick, carry-over into the next fight, `game_over` stops it,
  serialize round trip mid-HoT gives identical later heals, Heal Block ticks heal 0 and later ticks heal again,
  overheal emits `heal_lost`; heal ult: 15 %, cap, Heal Block → 0 + events; boss heal unchanged; no RNG draws.
- `class_test.lua`: still 108 spells, all with icon / sound / FX; the removed variants are gone; Mage M2 =
  `polymorph`; parity against the new default kit for all 9 classes.
- Fixtures that used `lifesteal` as the generic timed buff move to `hot`; the literal kit string in
  `ability_test.lua` l.67 is updated; lifesteal / convert ability tests are removed with the code.
- UI tests: `hot` slot icon from the kit + countdown after an extend, tick feedback is the small variant, blocked
  feedback rate limit, heal after the killing blow shows.
- Docs: `design/abilities.md` (also fix the stale "recast resets timer"), `design/combat.md`,
  `design/classes-and-abilities.md`, `design/class-kit-assets.md`, `CHANGELOG.md` +
  `docs/store/curseforge-description.md` (0.2.0 text). Not ROADMAP / DECISIONS / AGENTS.md.

## Alternatives considered

- **Heal ult on Emerald (replacing bombs), as in the W0-G3 draft (Divine Shield):** user chose Amber. W0-G3's
  Divine Shield part is superseded by this item (its ladder part stays a draft).
- **Keep lifesteal and add a small instant heal:** still depends on clears; the user wants a real HoT.
- **Convert moves to the Amber skill (5 gems):** convert on a 4-match re-opens the Amber chain loop (issues #27 / #28).
- **HoT refresh-to-full** (rev 1): wastes most of a second gem; **stacking the rate** (lifesteal did since playtest 5):
  doubles healing per second and is harder to read. Extend-with-cap keeps one rate and wastes nothing.
- **Keep lifesteal / convert as unused templates** (rev 1): dead status state in serialize / HUD / debug and special
  cases in the 108-spell asset test; git remembers the code.
- **Tranquility as the Druid ult:** it is a channel; Healing Touch is the Druid's big single heal.

## Why this could be wrong

- **15 % may be too much.** The boss heal is 25 %; the W0-G3 critic judged a 20 % heal ult dominant. One ult per fight
  is +15 % effective HP per fight; a player who farms Amber 5-matches may become unkillable. The probe counts ults
  per fight; the knob goes down if needed.
- **Held ults are stronger than the bot shows.** A human triggers the heal at low HP (no overheal); the bot wastes it.
- **Amber loses its board effect.** Convert was the only "more of my colour" tool and fun in chains; Amber becomes
  purely defensive. If Amber feels dull, the ult can keep a small convert rider later.
- **Dominated option?** With a HoT that needs no clears, the old lifesteal skill-expression (heal by playing fast)
  is gone; healing becomes "fire on cooldown". The HoT is small on purpose (5 % ≈ one weak enemy hit; the Emerald
  skill blocks a whole hit of 280–1000+).
- **Accidental triggers:** an area / row clear that reaches a banked heal gem fires it at full HP. That is the
  existing rule for every ability gem and part of the board skill; the probe counts the waste.
- **Fit stretches:** Hunter (Mend Pet / Revive Pet heal the pet), Mage Evocation (mana), Rogue (First Aid and a
  Healing Potion are not class spells, but real self-heals).

## Critic findings addressed (2026-11-11)

Tick design unspecified (scheduling, tie with expiry, rounding drift, `status_remaining`, serialize) → one chained
Clock timer, cumulative rounding, `ticks_left` serialized. Refresh wasted gems and silently reversed playtest 5 →
extend with cap. "Retire but keep" → lifesteal and the two abilities deleted, status renamed to `hot`, every touch
point listed. Id collisions (`rejuvenation` duplicate, `evocation` tier, Polymorph FX duration) → named in the
mapping section. Per-tick feedback spam / heal swallowed after the kill → `player_healed(amount, source)`, small
tick feedback, block message rate limit. Probe at the 1.5 s test pace is a floor effect and "healing doubles" is
meaningless (it doubles at any sane value) → pace 0.6, D2–D4, ≥ 30 seeds, hold policy, outcome gates. HoT 4 % judged
weak next to the old ≈ 6.5 % per fast cast → start at **5 %**. "Hakkar-style Heal Block" was wrong → fixed. Mapping:
Druid ult Healing Touch, Rogue First Aid / Healing Potion. Not adopted: Conjure Food icon `_33` (kept `_10`, to be
confirmed in game).

## Non-goals

- No change to enemies, ladder, player HP, boss heal, other colours' numbers. No class twists.

## Acceptance

- `tools/checks.sh` green; probe report before / after committed.
- In game: Rejuvenation shows a ticking heal with a countdown icon; the Amber ult heals 1500 at once; under Heal
  Block both show "HEAL BLOCKED" and do nothing.

## Open decisions (director default in bold)

1. `hot_percent` **5** over **10 s**, `heal_percent` **15** — final values after the probe (gates in section 4).
2. HoT re-cast **extends, capped at 20 ticks**.
3. Mage M2 becomes **Polymorph**.
