# WoW Forever — API facts and external references

Status: collected 2026-10-04 from the community repo **forever-addon-kit** (build 1.60.1.69893,
interface 16001; MIT, by Thunderz96), the Forever developer guide, and our own probe
(`probe/DragonChessProbe`, results to be added below). Community data may lag the client:
confirm anything load-bearing with the probe. Used by [wow-addon.md](wow-addon.md) and the W0+ specs.

## References

- **forever-addon-kit** — https://github.com/Thunderz96/forever-addon-kit — captured API baseline
  `data/forever_api.json` (6 045 functions, 269 namespaces, 11 417 named frames), porting scripts,
  three small addons (ForeverCompat: saved-variables workaround). Grep the JSON before guessing
  whether an API exists (`functions`, `namespaces`, `frames`, `client`).
- Developer guide (community) — https://wowforeverguides.com/addons/developers
- Launch date per that guide: **2026-11-04** (unverified; useful as a soft deadline).

## Facts (verified = seen in the baseline JSON or probe)

- **Interface number 16001** (`## Interface: 16001`); client build 1.60.1, `WOW_PROJECT_ID` =
  mainline (1), i.e. the **Retail/Midnight UI architecture**, not Classic. Beta lives in the
  `_classic_beta_` folder. (baseline `client` block)
- **Lua 5.1 only**: no `goto`, `//`, bitwise operators, `_ENV`, `require`, `dofile`, `loadfile`,
  `io`, `os`. Every file opens `local addonName, ns = ...`. SavedVariables are initialised in
  `ADDON_LOADED`, not at file scope.
- **SavedVariables bug (important for us):** the kit reports that saved variables **do not load
  on a client restart** (Blizzard bug in the beta; they survive `/reload`), with a workaround addon
  (`ForeverCompat`, seeds saved variables as addon code). Our persistence (run at fight
  boundaries, local high scores, window position) must tolerate this: treat an empty DB as normal,
  and re-test after Blizzard fixes it. Probe result for `/reload` is separate from a cold start.
- Errors: more than ~100 Lua errors per session silence the error display. Registering an unknown
  event throws — wrap `RegisterEvent` in `pcall` (our probe does).
- `ReloadUI()` is protected (use `/reload`). Secure snippets were broken until build 70009.
- Missing Classic globals: `GetItemInfo`, `GetSpellInfo`, `UnitAura`, `GetTalentInfo`,
  `CombatLogGetCurrentEventInfo` → use `C_Item.GetItemInfo`, `C_Spell.GetSpellInfo`, `C_Traits`.
- Midnight restrictions (combat data, secret values, no combat log) **do not affect** our own
  frames/game logic. Own-player health stays readable; irrelevant for a minigame.
- **Present** (baseline): `CreateFrame`, `CreateFramePool`, `GetCursorPosition`,
  `IsMouseButtonDown`, `debugprofilestop`, `PlaySound`, `PlaySoundFile`, `JoinChannelByName`,
  `GetChannelName`, `LeaveChannelByName`, `geterrorhandler`, `C_Timer` (4 fns),
  `C_Texture` incl. `GetAtlasInfo` / `GetAtlasExists` / `GetFilenameFromFileDataID`,
  `C_ChatInfo.SendAddonMessage` + `RegisterAddonMessagePrefix`, `C_Item` (121), `C_Spell` (72).
  **Not** in the list: `C_Texture.GetFileIDFromPath` (the probe's texture check must use
  `GetAtlasExists` / try-load instead — to fix), `C_SoundKit`.
- **`C_EncodingUtil`** exists: `CompressString`/`DecompressString`, `SerializeCBOR`/`DeserializeCBOR`,
  `SerializeJSON`, `EncodeBase64` … → built-in packet serialisation for the W2 channel (no
  AceSerializer needed; verify limits).
- **Addon messaging restrictions:** `C_ChatInfo.AreOutgoingAddonChatMessagesRestricted` and
  `InChatMessagingLockdown` exist (Midnight-style limits on addon comms, e.g. in instances/combat).
  W2 must check them before sending and degrade silently.
- Frame *types* (`ModelScene`, `PlayerModel`, …) are not in the baseline's `frames` list (that list
  holds named frames, not types) — probe `CreateFrame(type)` results decide boss presentation.
- **Gems:** the probe's item scan found **no gem items** (classID 3) — the beta has no socket
  gems yet (gems arrived with WotLK). **But the vanilla icon files exist** (probe `/dcprobe icons`,
  screenshot 2026-10-04): `INV_Misc_Gem_Ruby_01/02`, `Sapphire_01/02`, `Emerald_01/02`,
  `Amethyst_01/02`, `Topaz_01/02`, `Opal_01/02`, `Pearl_01`, `Diamond_01`, `Bloodstone_01`,
  `Crystal_01`, `Variety_01/02`, `Azuredraenite_01`, `Gem_01`–`Gem_03` (`Gem_04` missing), spell
  icons `Spell_Fire_FlameBolt`, `Spell_Frost_FrostBolt02`, `Spell_Nature_Lightning`, … all present.
  Proposed six board gems: Ruby `Gem_Ruby_01` (red), Sapphire `Gem_Sapphire_02` (light blue),
  Emerald `Gem_Emerald_01` (green), Amethyst `INV_Misc_Gem_01` (violet; `Amethyst_01` is magenta,
  too close to Ruby), Topaz `Gem_Topaz_01` (yellow), Amber `Gem_Opal_01` (orange). Final pick in W0-P1.
- Build seen by the probe: 1.60.1 / **70205**, interface 16001 (confirmed on a live client).
- **Live launch (2026-11-04):** product `wowf`, client folder **`_forever_`** (not `_classic_beta_`), build
  **1.60.1.70790**, interface still **16001** (every current Forever addon in the live folder ships `16001`;
  multi-flavour addons add a `_Camelot.toc` suffix file for this client). No TOC change needed. Live
  SavedVariables get written with `.bak` copies; the cold-start bug still needs a re-test on live.
- Mouse: `OnMouseDown`, `OnMouseUp` and an `IsMouseButtonDown` poll all fire in the probe's test
  box (user run 2026-10-04); release-outside behaviour still to be confirmed.

## Probe results (live client, build 1.60.1 / 70205, 2026-10-04)

From `WTF/Account/<acct>/SavedVariables/DragonChessProbe.lua` after `/reload` (the first run; the
texture check in it was obsolete and is superseded by the visual `/dcprobe icons` result above).

- **Lua semantics = PUC Lua 5.1, not LuaJIT** (`_VERSION` "Lua 5.1", `jit` = false). A
  `coroutine.yield` inside `pcall` fails: the coroutine's `pcall` returned `false` and the coroutine
  ended. This **confirms the critic's finding**: the scheduler must never yield inside `pcall`, and
  `lua5.1` is the right primary test runner (`lint_yield` guards it).
- `WOW_PROJECT_ID` is **18** here (the community kit says 1/mainline — don't rely on it for flavour
  checks; if we need one, test for a feature instead).
- **All needed events register:** `PLAYER_LOGOUT`, `PLAYER_ENTERING_WORLD`, `PLAYER_REGEN_DISABLED/
  ENABLED`, `LFG_PROPOSAL_SHOW/FAILED`, `READY_CHECK`, `UPDATE_BATTLEFIELD_STATUS`,
  `PVP_ROLE_POPUP_SHOW`, `CHAT_MSG_ADDON`, `CHAT_MSG_CHANNEL`, `CHANNEL_UI_UPDATE`, `ADDON_LOADED`,
  `GUILD_ROSTER_UPDATE`, `LOADING_SCREEN_ENABLED` → the soft-pause trigger set from W0-P1 is available.
- **Frame types available:** `Frame`, `Button`, `StatusBar`, `Slider`, `Cooldown`, `Model`,
  `PlayerModel`, `DressUpModel`, `ModelScene` → boss/creature presentation via models is possible.
- **APIs:** `C_Timer`, `C_Texture`, `C_Item`, `C_Container`, `C_AddOns`, `C_ChatInfo`
  (`SendAddonMessage`, `SendAddonMessageLogged`, `RegisterAddonMessagePrefix`, `GetNumActiveChannels`),
  `bit`, `Settings`, `AddonCompartmentFrame`, `BackdropTemplateMixin`, `CreateFromMixins`,
  `SOUNDKIT`. **Not present:** `LibStub`, `ChatThrottleLib` (we ship our own tiny throttle or bundle
  the library; the addon must not depend on others being installed).
- **Atlases exist** (`GetAtlasExists`): `UI-HUD-ActionBar-IconFrame`, `common-icon-checkmark`,
  `poi-workorders`, `auctionhouse-itemicon-border-purple`.
- **Sounds:** `SOUNDKIT` has `IG_MAINMENU_OPEN` (850), `IG_MAINMENU_CLOSE` (851),
  `IG_CHARACTER_INFO_TAB` (841), `UI_BNET_TOAST` (18019), `GS_TITLE_OPTION_OK` (798),
  `IG_ABILITY_ICON_DROP` (838).
- **Performance:** 200 iterations × 64 frames × (`ClearAllPoints` + `SetPoint`) = 12 800 calls took
  **11.7 ms** → about **0.06 ms per frame** for repositioning all 64 gems. The board view's
  per-frame cost is not a concern. Client baseline memory 110 MB (irrelevant).
- **Mouse (confirmed 2026-10-04):** pressing in the frame, dragging out and releasing outside still
  fires `OnMouseUp` on the pressed frame (probe log "cursor OUTSIDE", 3/3). Drag input can rely on
  `OnMouseDown`/`OnMouseUp` + `GetCursorPosition`; the poll stays only as a fallback.
- **Gem look (decided on a live mock board 2026-10-04):** the `_02` variants — `Ruby_02`,
  `Sapphire_02`, `Emerald_02`, `Amethyst_02`, `Topaz_02`, `Opal_02` — cropped with
  `SetTexCoord(0.08, 0.92, 0.08, 0.92)` and a round `MaskTexture` (`Interface\CharacterFrame\
  TempPortraitAlphaMask`, `CLAMPTOBLACKADDITIVE`) look clean and uniform at 56 px; raw icons show a
  black frame, crop-only leaves black corners. All six read as distinct on an 8×8 board; Ruby
  (red-pink) vs Amethyst (magenta) is the closest pair → add a small shape/rim cue if playtests
  show confusion. (Replaces the earlier `Gem_Ruby_01 … Gem_01` proposal.)
- (earlier note) in every test sequence `OnMouseDown` → `OnMouseUp` → `poll-release` fired (6 runs).
  Whether the releases happened outside the box is unconfirmed; keep the `IsMouseButtonDown` poll
  as the primary release detector anyway.
- `SetCVar`, `JoinChannelByName`, `GetChannelName`, `PlaySound(File)`, `GetCursorPosition`,
  `IsMouseButtonDown`, `debugprofilestop`, `geterrorhandler` exist.

- **Used by W0-P3.1 (unverified, always guarded):** `GetFramerate()` (debug panel footer; `type()` check),
  `PlaySound` / `PlaySoundFile` with the channel `"Ambience"` (only `"SFX"` is verified; Ambience is the standard
  channel name with its own slider, default 60 %), `PlayerModel:SetDisplayInfo(displayID)` with real display IDs (1000
  verified in the probe; the creature IDs in `ui/assets.lua` are from wago.tools, to confirm in game).

## Sound picks and effect assets (user + probe, 2026-10-04)

- SoundKit IDs found with the probe's sound browser (`/dcprobe sound`): **101 = break** (gem destroyed;
  mining-like, "super"), **129 = attack** (good but too loud — `PlaySound` has no per-sound volume; pick a
  quieter ID or use another channel), **132 = attack vs shield**, **139 / 235 = miss**. Named list: `SOUNDKIT`
  constants (names → IDs) via `/dcprobe snd <text>` (auditions every matching name, one per second).
- `AnimationGroup` works (the probe icon moved/scaled). A `FlipBook` of `Cast_Standard_Flipbook02` showed
  nothing with a guessed 4×4/16 grid: the grid layout of each flipbook atlas must be read from the sheet
  (`/dcprobe flip <atlas> <rows> <cols> <frames>` shows the sheet and plays it). `PlayerModel:SetAnimation(id)`
  steps through model animations (works). **ModelScene actors** exist with `SetSpellVisualKit`,
  `PlayAnimationKit`, `SetAnimation`, `SetModelByCreatureDisplayID/FileID` → spell visuals are plausible
  (needs kit IDs; untested).
- Interesting effect atlases in the dump (120 flipbook names, e.g.): `GemAppear_T1..T4_Flipbook`,
  `GemDissolve_T1..T4_Flipbook` (jewelcrafting gem appear/dissolve — a natural fit for gem clear/spawn),
  `Cast_Standard_Flipbook02`, `UF-SoulShards-Flipbook-*`, `dragonriding_sgvigor_burst_flipbook`;
  bursts: `OBJFX_StarBurst`, `GarrisonFX-StarBurst`, `PowerSwirlAnimation-StarBurst`,
  `Adventures-Buff-Heal-Burst/-Ring`, `Insanity-PurpleBurstOn`; no lightning/impact atlases (only
  `BossBanner-RedLightning`).
