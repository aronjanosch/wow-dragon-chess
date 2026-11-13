# Vision — Dragon Chess for WoW (working title)

North star and decision filter. One page on purpose. If a feature idea conflicts with this file,
this file wins until we deliberately change it. Status: AGREED 2026-10-04.
(The previous Godot roguelite vision is archived: archive/vision-godot-roguelite.md.)

## Pitch

A free, open-source World of Warcraft addon: a real-time match-3 with RPG combat that you play
in the dead minutes of WoW — in a queue, waiting for a raid, between pulls of nothing. Your WoW
class decides what each gem colour does. Close the window and the fight freezes; open it and
you're right back in. Think Peggle/Bejeweled for WoW, but with Dota's Dragon Chess depth.

## Pillars

1. **Snappy, always.** Open → playing in under a second. Swaps, cascades and clears feel instant
   (target ≥ 60 fps, no hitching, no per-frame garbage). A dead-minute game lives or dies on feel.
2. **Pause is free.** Hiding the window pauses the fight; showing it resumes. Progress survives
   `/reload` and logout. Never punish the player for being pulled away (queue pops, ready checks).
3. **Two-speed combat: tempo and setup.** Quick 3-matches are chip damage; 4/5+-matches and ability
   gems are the setup layer — bank them, fire them into the right moment. Neither layer may
   dominate, and setup never requires pausing to think. (Carried over from the Godot design.)
4. **Your class is your build.** Each of the 9 Classic classes gets its own 12 spells (2 per gem colour) as
   variants of the 12 effect templates ([design/classes-and-abilities.md](design/classes-and-abilities.md)). Picking a
   class changes how you play, not just numbers.
5. **Readable pressure, full information.** Enemy intent, timers and statuses are always on screen,
   understood by watching once. No tooltips needed.
6. **Social, lightly.** Compare with your guild through an addon channel and local high scores.
   Cheating is accepted (nobody wins anything), so there is no server and no verification.
7. **Free and open.** Free, code fully readable, no donation prompts in-game (Blizzard addon policy).
   No monetisation, ever.

## Theme and art direction

**Everything is WoW Classic**: enemies and bosses are Classic mobs ([design/roster.md](design/roster.md); the old Godot
monster names are gone), abilities are Classic spells, backgrounds are Classic loading-screen art. Assets are
**native game assets, referenced not shipped** (gem icons as a stand-in until the user's own gem art, spell icons,
atlases, creature and effect models, WoW sounds), chosen via the listfile lookup ([DECISIONS.md](DECISIONS.md)). One
consistent style: Blizzard's. Every ability looks and sounds like its WoW spell; enemies animate (attack, hurt,
stun, death).

## Audience

WoW players with idle minutes: queues (LFG, battlegrounds), waiting for a group, AFK moments.
Casual-friendly, but the two-speed combat gives depth for people who want to chase scores.

## What we are NOT building (for now)

- Anything with money, accounts, a backend or a global leaderboard.
- The roguelite layers: boon draft, relics, shop, doors, ascension. They are designed and partly
  built in the Godot archive and stay documented in `docs/design/` and `docs/archive/`. Re-import
  later if the base game is loved.
- Full Godot parity for presentation (shaders, particles, pixel-art sprites). The addon uses native WoW assets.
- PvP duels (maybe later, once the channel exists).
- A bot-verified balance loop in-game. The core is pure Lua, so headless bots can come later.

## Decision filter (ask before every spec)

1. Which pillar does this serve? If none, why are we doing it?
2. Is it snappy? Does it cost frame time or garbage per frame?
3. Does it survive hide/show, `/reload` and logout?
4. Can the player understand it by watching it once?
5. Is this the cheapest version that tests the idea?

## Release gates

- **Title & IP:** "Dragon Chess" is Valve's minigame name; WoW names/art belong to Blizzard.
  Before any public release: final title, no Dota/Valve hero or ability names, credits in
  `CREDITS.md`. WoW assets are **referenced from the installed game** (paths/FileIDs/atlases/
  SOUNDKIT), never extracted into the repo or package; re-read Blizzard's current policy on
  game-asset use before release.
- **Policy:** Blizzard UI Add-On Development Policy (free, readable code, no in-game donation
  requests). Check again before release.
- **Platform facts to verify early** (see W0-T1/W0-P1 risk lists): addon API on WoW Forever
  (Midnight mainline API), texture/sound formats, addon-channel limits.
