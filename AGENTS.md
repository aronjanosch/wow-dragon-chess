# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project

Dragon Chess is a free World of Warcraft Forever addon: a real-time match-3 puzzle with RPG combat and class
spells, played in a window inside the game. Lua 5.1, no libraries. Released on CurseForge (project 1799077) and
GitHub Releases. This repository is public: everything in it is English (code comments, docs, commit messages,
issues, pull requests).

The addon was ported from a Godot prototype that lives in a private archive repo; docs that mention `scenes/…`,
`.tres` files or `docs/archive/…` refer to it. The golden test data (`test/golden_*.lua`) was generated from that
prototype and is never edited by hand.

## Layout

- Repo root = the addon folder (`DragonChess.toc` must stay in the root: the packager needs it there).
- `core/` — game rules in pure Lua. **No WoW API**, no globals (`test/lint_globals.lua` enforces it).
  `board` / `match` / `sim` (board and cascades), `combat` (HP, damage, statuses), `enemy` + `enemy_abilities`,
  `run` (ladder, difficulty, records), `abilities/` (12 effect templates, two per gem colour), `classes.lua`
  (class kits: skins of the templates), `debug.lua` (dev only, sets `ns.DEV`).
- `data/enemies.lua` — enemy roster and abilities (plain tables, hand-owned).
- `ui/` — frames, effects, menus. **No game rules.** Every asset reference (icons, sounds, models, textures)
  lives in `ui/assets.lua`.
- `media/` — own art (gem textures; `tools/cut_gems.py` cuts a sheet into them).
- `test/` — headless tests with WoW API stubs (`wow_stubs.lua`), `tools/` — checks, balance probe, packaging,
  `probe/` — a separate dev addon that inspects the client, `docs/` — decisions, design, specs, playtest data.

## Commands

```bash
tools/checks.sh                       # all tests on lua5.1 and luajit; exit 0 = clean
lua5.1 test/<name>.lua                # one test file (run from the repo root)
lua5.1 tools/balance_probe.lua        # bot win rates per difficulty (see --seeds / --diffs / --paces)
tools/package.sh                      # local release zip in dist/ (no debug files)
```

In game: symlink the repo into `<WoW>/_forever_/Interface/AddOns/DragonChess`; `/dchess` opens the game,
`/reload` picks up Lua and texture changes.

## Rules that bite

- **Class skins may not change rules.** A variant in `core/classes.lua` overrides only `id`, `template`, `name`,
  `icon`, `description`, `blurb`; its icon / sound / effect live in `ui/assets.lua` keyed by the variant id.
  `test/class_test.lua` enforces this and proves parity with the default kit.
- **Enemy timing:** final cooldown = base cooldown × `Run.ATTACK_PACE`, final damage = base × pace × 0.9 ×
  difficulty factor (`core/run.lua`, applied to per-fight copies; the data file is never mutated).
  `test/enemy_data_test.lua` pins the roster to the golden data plus an explicit override list.
- **Check the API before using it:** `docs/design/wow-forever-api.md` (Forever is not the Classic API).
- **Debug code is dev only.** `core/debug.lua` and `ui/debug.lua` do not ship: their TOC lines sit between
  `#@debug@` markers and `.pkgmeta` ignores the files. Release code must work without them
  (`test/release_test.lua`).
- New `.lua` file → add it to `DragonChess.toc` (and `test/loader.lua` `CORE_FILES` for core files).
- Asset FileDataIDs come from the community listfile (`tools/wow_asset.sh`); a listfile hit does not prove the
  client ships the file. Say "unconfirmed in game" until the user has seen it.

## Workflow

- Read `docs/DECISIONS.md` first (the user's standing decisions), then `docs/ROADMAP.md` and the relevant
  `docs/design/*.md` (current state of each system) and `docs/DIRECTOR.md` (director role, briefs, traps).
- **discuss → spec → critic review → user agreement → implement → verify → user playtest.** Never implement an
  undiscussed gameplay change. Specs are deltas in `docs/specs/` (`_TEMPLATE.md`); a spec marked "DRAFT" is not
  approved. Gameplay specs get a critic review (`/critic`) before they go to the user.
- Implementation is delegated to a coding agent in an isolated worktree; the director reviews the diff, merges
  and runs `/verify`. The brief names the spec (source of truth), the files, these rules, and asks for
  deviations to be reported explicitly.
- Balance claims are measured with `tools/balance_probe.lua` (100 seeds for a decision), reports go to
  `docs/playtests/data/`. Fun and feel are decided by the user in game.
- Definition of done: `tools/checks.sh` green, spec checklist covered, `docs/design/*` and `CHANGELOG.md`
  updated when behaviour or values changed, deviations listed.
- Commit only when the user asks. Conventional commits (`feat:`, `fix:`, `docs:`, `ci:`). No push to `main` and
  no tag without the user's go.

## Release

1. Bump `## Version` in `DragonChess.toc`, add the section to `CHANGELOG.md`.
2. Push `main`, then push the tag `v<version>`. The workflow (`.github/workflows/release.yml`, BigWigs packager,
   `.pkgmeta`) builds the zip, creates the GitHub release and uploads to CurseForge when the repo secret
   `CF_API_KEY` is set.
3. Store text and logo: `docs/store/`.
