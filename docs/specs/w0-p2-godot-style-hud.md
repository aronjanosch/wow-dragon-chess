# Spec: W0-P2 — Godot-style fight screen with WoW assets

Status: **implemented — awaiting in-game playtest** (2026-10-04; current state in
[../design/wow-addon.md](../design/wow-addon.md) "UI (W0-P2)"). AGREED direction (user 2026-10-04: "basically like the Godot original, replace textures/sprites with WoW assets,
backgrounds from the game welcome"); asset picks below from the live probe (`/dcprobe ui`,
`/dcprobe atlas`); the user judges the look in the first build.

Implementation deviations: window 1010 × 588 (title strip + 30 px bottom strip; sketch ≈ 560);
`hud_min.lua` deleted (fight_view reached parity, except the intent damage range text, which the
Godot queue doesn't show either); no "number tick texts" on the HP bars; the enemy hit "red tint" is
an additive red disc over the model (a PlayerModel can't be vertex-tinted); backgrounds are
stretched to the panel (no aspect crop).
Milestone: W0 Base game port. Track: P. Depends on W0-T1, W0-P1, W0-G1 (core + text HUD, merged).
Pillars served: 5 (readable pressure: enemy intent, timers and statuses always visible), 1 (snappy),
and the art direction in [../VISION.md](../VISION.md) (native WoW assets, one consistent style).

## Player experience goal

The fight screen looks and reads like the Godot game / the Dota original: board on the left, the
enemy presented big on the right with its name, stage and weakness, a vertical **attack queue**
showing the next three enemy actions with a visible timer, health bars under each side, a score
plaque in the middle, an ability banner when something fires, statuses as icons next to the bars.
Everything understood by watching, no text-only HUD.

## Current state (facts)

- The W0-G1 HUD (`ui/hud_min.lua`) is a text/bar strip above the board; the user's verdict after
  the first in-game run: works, but "the UI is super bad" — it should follow the Godot layout.
- Reference layouts: `Screenshot1.png` in the repo root (the Dota Dragon Chess original; **design
  reference only, never shipped**) and `scenes/game.tscn` (nodes: `BoardPanel`, `EnemyPanel` with
  `StageLabels` [stage, name, divider, weakness], `EnemyFrame` (enemy art), `Attacks` (queue backdrop,
  `EnemyStunIcon`, `EnemyBuffIcon`, `AttackQueue`), ability banner (icon + title + blurb),
  `PlayerHealthBar` (+ status strip with Shield / Fire Shield / Lifesteal / Curse / Heal block /
  Sandstorm icons), `EnemyHealthBar`, `ScoreChrome`/`ScoreDisplay`, `Vignette`). Queue behaviour:
  `scenes/ui/attack_queue.gd`, status icons: `scenes/ui/status_icon.tscn`, `status_glyphs.gd`.
- The core exposes everything needed: `combat:hud_state(out)`, events `ability_triggered`,
  `enemy_windup`, `enemy_status_changed`, `status_changed`, `player_damaged`, `enemy_damaged`, …
  ([../design/wow-addon.md](../design/wow-addon.md) "Combat (W0-G1)").
- WoW facts verified so far ([../design/wow-forever-api.md](../design/wow-forever-api.md)):
  `StatusBar`, `Cooldown`, `PlayerModel`, `DressUpModel`, `ModelScene` frame types exist; SOUNDKIT
  entries; atlases exist (`GetAtlasExists`); spell icons render; round masks work.
  **Probe results 2026-10-04 (live client):** `PlayerModel:SetDisplayInfo(1000)` showed a creature and `SetUnit("player")` the player's model; `SetCreature` with IDs 448/3/46/11502 and displays 17000/30000/50000, a model path and a FileID showed nothing, ModelScene nothing → creatures are possible but only via valid display IDs (a scan is needed to pick them). UI textures that render: `UI-StatusBar`, Tooltip background/border, DialogBox background/border/gold border, `UI-Background-Marble` / `-Rock`, Spellbook page, Achievement parchment; `PvPBackground` missing; status icons Holy_PowerWordShield, Fire_FireArmor, Shadow_LifeDrain02, Frost_Stun, Warrior_Sunder/Rampage, Druid_Maul, Hunter_Pet_Wolf, Nature_Slow render (`Spell_Shadow_CurseOfTounge` missing). The atlas dump has 16 874 names (re-run pending, see below). **Still unverified:** whether `PlayerModel:SetCreature` / `SetDisplayInfo` show creatures in
  the Forever client (and which IDs), usable backdrop/frame textures and atlases (a name dump via
  `C_Texture.GetAtlasElements` is in the probe), 3D model camera/position control for framing.

## Reference screenshots (user, 2026-10-04) — not 1:1, translate to WoW

Godot fight screen (Cerberus Puppy): full-window background art; **left** a translucent dark panel
with the 8×8 board; **right** the enemy side with a small "STAGE 1-1", the enemy name in large
capitals, a small "WEAK · TOPAZ" line, the enemy sprite big at the bottom right, and a **vertical
attack queue** (dark column on the enemy panel's left edge: three round slots, the first larger
with a ring timer sweep, two smaller below; a small stun/buff icon slot underneath); full-width
**HP bars along the bottom** (player green on the left, enemy red on the right, "9830/10000"
centred in the bar); a **yellow score plaque with gold frame** at the seam between the bars; a
small pause button top right; a debug button. The title/menu screen ("GEMFALL", PLAY + difficulty
row, Records/Options/Credits/Quit) and the options panel (gold-framed dark panel with sliders) are
reference for later; the **grid-fight mode** (enemy side shows a hole grid + piece tray) comes
later too (M1-X1 designs in the archive branch) — **not in W0-P2**. The "BAG / GOLD" strip is a
roguelite leftover and is **not** ported.

WoW translation: backgrounds from the game (zone/loading/atlas art if usable, else tinted marble /
rock textures), panel and plaque frames from WoW frame textures/atlases, queue slots as round
spell icons with a `Cooldown` sweep, bars as `StatusBar`s, the enemy as a model (display ID) or
portrait, plus the user's later custom gem art. WoW-style fonts instead of the pixel font.

## Asset picks (verified to render in the live client via `/dcprobe atlas`, 2026-10-04)

All behind `ui/assets.lua`; every atlas is applied with `pcall(tex.SetAtlas, tex, name)` and has a
plain-colour fallback (`SetColorTexture`) so a missing atlas never breaks the fight screen.

- **Backgrounds** (`groupfinder-background-*`, large dark scene art): per stage —
  `-dungeons` (stage 1), `-raids-warlords` (stage 2), `-raids-legion` (stage 3), `-battlegrounds`
  (final); also available: `-questing`, `-scenarios`, `-arenas`, `-ashran`, `-custom-pve`,
  `collections-background-tile`, `Garr_WoodFrame-BackgroundTile`. Enemy panel = the stage background at
  full brightness; board panel = same art dimmed by a translucent dark overlay (Godot look).
- **Panel frames:** `Interface\DialogFrame\UI-DialogBox-Gold-Border` / `UI-DialogBox-Border` (edge
  files, work as `BackdropTemplate` edges), `UI-DialogBox-Background` (dark fill).
- **Score plaque:** `UI-Frame-Neutral-CardParchment` (yellow parchment, like the Godot plaque) with a
  gold border; fallback `Interface\AchievementFrame\UI-Achievement-Parchment-Horizontal`.
- **HP bars:** `StatusBar` with `Interface\TargetingFrame\UI-StatusBar`, tinted green (player) / red
  (enemy); optional frame art `MainPet-HealthBarFrame` / `PetJournal-HealthBar-*` /
  `GarrMission_EncounterBar-*` (judge on screen; plain tinted bar is acceptable).
- **Queue slots:** spell icon (circle-masked, like the gems) inside a ring (`GarrMission_EncounterBar-PortraitRing`,
  `Portrait-Frame-Nameplate`, `ZoneAbility-Generic-IconBorder`), `Cooldown` frame for the sweep on slot 1.
- **Ability banner / CLEARED:** `BossBanner-BgBanner-Mid` (+ `-Top`, `BossBanner-SkullCircle`,
  `BossBanner-TopFillagree`) behind icon + title + blurb.
- **Status icons** (player strip / enemy): `Spell_Holy_PowerWordShield` (Shield), `Spell_Fire_FireArmor`
  (Fire Shield), `Spell_Shadow_LifeDrain02` (Lifesteal), `Spell_Frost_Stun` (stun/freeze),
  `Ability_Warrior_Sunder` (heal block, placeholder), `Spell_Nature_Slow` (Sandstorm); Curse: pick any
  existing shadow icon (`Spell_Shadow_CurseOfTounge` does not exist).
- **Enemy:** `PlayerModel:SetDisplayInfo(1000)` (the one creature that rendered) as a stand-in for the Puppy,
  behind a `display` key; **fallback = large icon portrait** when the model is empty. The real roster is
  a W0-G2 decision (needs a display-ID scan).

## Layout (target, window ≈ 1010 × 560 at scale 1.0)

```
┌───────────────────────────────────────┬────────────────────────────────────┐
│                                       │         STAGE 1-1                  │
│    8×8 board  (8 × 64 px)             │      CERBERUS PUPPY    weak: Topaz │
│                                       │ [stun][buff]                       │
│                                       │ ┌──┐                               │
│                                       │ │Q1│     enemy model / portrait    │
│                                       │ ├──┤     (EnemyFrame, big)         │
│                                       │ │Q2│                               │
│                                       │ ├──┤     ability banner (icon +    │
│                                       │ │Q3│     title + blurb) fades      │
│                                       │ └──┘                               │
│  [shield][fire][life]  player HP bar  │ ╔═ SCORE ═╗      enemy HP bar       │
└───────────────────────────────────────┴════ 4070 ═════════════════════════─┘
```

## Changes

1. **Layout** in `ui/window.lua` + new `ui/fight_view.lua` (replaces `hud_min.lua`, which stays
   until feature parity): two panels as above, scale-able as one frame; the board keeps its
   position/size logic from W0-P1 (view/input untouched, only the board's anchor moves).
2. **Panels and chrome:** dark panel backgrounds and a gold-ish frame from WoW textures/atlases
   (picked from the probe's atlas dump; fallback: `UI-DialogBox`/Tooltip textures), enemy panel
   backdrop = a WoW art texture or a tinted gradient (decided after the probe).
3. **Enemy presentation:** a `PlayerModel` (or `ModelScene`) in `EnemyFrame` showing the enemy's
   creature (asset key `display` in the enemy data, resolved in `ui/assets.lua`); fallback if
   models don't work: a large icon/portrait texture. Hit reaction: scale punch + red tint on
   `enemy_damaged`; death: fade out. Stage label + name + weakness (colour icon of the weak gem).
4. **Attack queue** (port of `attack_queue.gd`): three vertical slots with the intent icons (spell
   icons per attack kind via `ui/assets.lua`), the first slot larger with the timer sweep
   (`Cooldown` frame or a StatusBar), special-attack chrome, a "NOW" pulse during the wind-up;
   driven by `hud_state.intents` / `enemy_next_hit`.
5. **Health bars:** `StatusBar` with the WoW bar texture, label "cur / max", number tick texts;
   player bar violet while stunned, curse/heal-block tints as in Godot; **status icons** next to
   the player bar (spell icons per status, with remaining-time sweep/number) and next to the enemy
   (stun / freeze, and later Aegis / Mirror from W0-G2).
6. **Score plaque:** centred at the seam, label SCORE + value with a count-up tween.
7. **Ability banner:** icon (from `ability_triggered.icon`) + title + blurb at the top of the enemy
   panel, fade in/out on sim time. Also put the ability's spell icon as an **overlay on the ability
   gem** in the board view (W0-G1 4a, deferred from the HUD work).
8. **FX (cheap):** hit flash (red edge vignette on `player_damaged`), floating damage numbers on the
   enemy (pooled FontStrings), CLEARED banner, game-over overlay restyled. Sounds: `PlaySound`
   from SOUNDKIT for match/ability/hit (picks documented in `ui/assets.lua`; bigger events lower,
   never squeakier — pick sounds, no pitch).
9. **Tests:** extend `ui_smoke` (layout frames exist and are anchored, queue shows 3 slots with
   the right icons, statuses show/hide with `status_changed`, banner fades on sim time, zero
   steady-state garbage in the view code, no leaked globals).

## Alternatives considered

- **Keep the text HUD, polish only:** cheapest, but the user explicitly wants the Godot look; the
  pillar-5 readability (queue icons, status icons) isn't reachable with text.
- **Exact pixel port of the Godot layout:** the Godot window is 1920-wide with parallax art; the
  addon window must be a compact, movable frame. We copy the *structure*, not the pixels.
- **Own pixel/sprite art now:** rejected earlier (user: consistent Blizzard style, native assets).

## Why this could be wrong

- Creature models may not load (Forever beta, display IDs/camera): then the enemy is a portrait/icon,
  which changes the feel; decided by the probe before implementation.
- A big window (≈ 1010 px) may be too large for small screens or users' UI scale; mitigate with a
  scale option (W3) and a sensible default scale; check at 1080p.
- Many textured frames cost frame time; budget stays < 1 ms per frame in the steady state.
- The gems (Blizzard vanilla icons) may not fit the new frame style; the user plans own gem art
  later ("then we'll develop our own"), so `ui/assets.lua` keeps gem textures swappable.

## Non-goals

No ladder/stage progression (W0-G2: the stage label shows "STAGE 1-1" statically until then), no
options panel, no final backgrounds/music, no custom gem art, no minimap button.

## Tests / acceptance

- `tools/checks.sh` clean on `lua5.1` and `luajit`.
- In-game: the layout matches the sketch; queue/timers/statuses readable at a glance; banner, damage
  numbers and hit flash fire; closing the window freezes everything including fades; frame cost
  acceptable (`/dcprobe`-style `debugprofilestop` readout).
- User playtest: "reads like the Godot game", readable without text.

## Open decisions

1. Enemy presentation (model vs portrait) — **model if the probe shows creatures load, else portrait**.
2. Window default size/scale — **board 8×64 (512 px) + enemy panel 480 px, scale 1.0**.
3. Which WoW creature stands in for the Puppy (and later the ladder) — **after the probe**; roster
   decision belongs to W0-G2.
