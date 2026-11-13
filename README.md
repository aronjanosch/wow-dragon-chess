# Dragon Chess (WoW Forever addon)

A free, real-time match-3 puzzle with RPG combat against the bosses of classic Azeroth, playable in a window inside World of Warcraft Forever.
Swap gems to match colours, charge skill and ult gems, and take down its enemies before they take you down.

## Install

1. Get it on [CurseForge](https://www.curseforge.com/wow/addons/dragon-chess), or download
   `DragonChess-<version>.zip` from the [Releases](../../releases) page.
2. Unzip it so that the folder `DragonChess` ends up in `World of Warcraft/<client>/Interface/AddOns/`.
3. In game: `/dchess` (or the minimap button).

## Notes

- The addon only references assets that ship with the WoW client by path; nothing from Blizzard is included here.
- World of Warcraft and its art are © Blizzard Entertainment, Inc.
- The addon's own code and gem art are released under the MIT License (see `LICENSE`).

## Development

The repository root is the addon folder itself (the release zip wraps it in `DragonChess/` and leaves out tests,
tools and docs). For a dev install, symlink the repo into `Interface/AddOns/DragonChess`.

```bash
tools/checks.sh       # headless tests (needs lua5.1 and luajit)
tools/package.sh      # local release zip in dist/
```

Game rules live in `core/` (pure Lua, no WoW API), the interface in `ui/`, enemies in `data/`. Design notes,
decisions and specs are in `docs/`; `AGENTS.md` describes the workflow. A pushed tag `v<version>` builds and
publishes the release.
