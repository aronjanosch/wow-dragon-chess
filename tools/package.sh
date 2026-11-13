#!/usr/bin/env bash
# Builds the RELEASE tree and zip locally: dist/DragonChess-<version>.zip with the single top-level folder
# DragonChess/ (what the addon managers expect). The version comes from the TOC (## Version).
# The official release is built by the BigWigs packager on a pushed tag (.pkgmeta, .github/workflows/release.yml);
# this script builds the same content for a manual upload and for a local look at what ships.
# The release has no debug tooling: core/debug.lua and ui/debug.lua and their TOC lines are left out
# (the dev tree keeps them; ns.DEV is set by core/debug.lua).
# Usage: tools/package.sh                 -> builds the zip, prints the file count and the zip path
#        tools/package.sh --stage <dir>   -> only stages the release tree into <dir>/DragonChess (no zip)
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
SRC="$ROOT"
TOC="$SRC/DragonChess.toc"
# What ships: the TOC, the code and media folders, licence and changelog. Tests, tools, docs stay out.
SHIP=(DragonChess.toc core data ui media LICENSE CHANGELOG.md)
DEBUG_FILES=(core/debug.lua ui/debug.lua)

STAGE_ONLY=""
if [[ "${1:-}" == "--stage" ]]; then
	STAGE_ONLY="${2:?--stage needs a directory}"
elif [[ $# -gt 0 ]]; then
	echo "usage: tools/package.sh [--stage <dir>]" >&2
	exit 2
fi

VERSION="$(sed -n 's/^## Version: *//p' "$TOC" | tr -d '\r')"
[[ -n "$VERSION" ]] || { echo "no ## Version in $TOC" >&2; exit 1; }

# Stage into <dest>/DragonChess without debug tooling; fails when anything debug-like is left.
stage() {
	local dest="$1"
	rm -rf "$dest/DragonChess"
	mkdir -p "$dest"
	mkdir -p "$dest/DragonChess"
	local item
	for item in "${SHIP[@]}"; do cp -r "$SRC/$item" "$dest/DragonChess/"; done
	find "$dest/DragonChess" \( -name .gitkeep -o -name .DS_Store \) -delete
	local f
	for f in "${DEBUG_FILES[@]}"; do
		[[ -f "$dest/DragonChess/$f" ]] || { echo "missing $f in the source tree" >&2; exit 1; }
		rm -f "$dest/DragonChess/$f"
		sed -i "\\#^${f}[[:space:]]*\$#d" "$dest/DragonChess/DragonChess.toc"
	done
	# the packager markers around the debug lines (#@debug@ / #@end-debug@) go too
	sed -i '/^#@\(end-\)\?debug@[[:space:]]*$/d' "$dest/DragonChess/DragonChess.toc"
	if [[ -n "$(find "$dest/DragonChess" -name 'debug.lua')" ]]; then
		echo "staged tree still contains a debug.lua" >&2
		exit 1
	fi
	if grep -qi 'debug' "$dest/DragonChess/DragonChess.toc"; then
		echo "staged TOC still mentions debug" >&2
		exit 1
	fi
	# every file the staged TOC lists must exist
	local line
	while IFS= read -r line; do
		line="${line%$'\r'}"
		[[ -z "$line" || "$line" == \#* ]] && continue
		[[ -f "$dest/DragonChess/$line" ]] || { echo "TOC lists a missing file: $line" >&2; exit 1; }
	done < "$dest/DragonChess/DragonChess.toc"
}

if [[ -n "$STAGE_ONLY" ]]; then
	stage "$STAGE_ONLY"
	echo "$(find "$STAGE_ONLY/DragonChess" -type f | wc -l) files staged"
	echo "$STAGE_ONLY/DragonChess"
	exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
stage "$WORK"
OUT="$ROOT/dist/DragonChess-$VERSION.zip"
mkdir -p "$ROOT/dist"
rm -f "$OUT"
(cd "$WORK" && zip -qr "$OUT" DragonChess)
unzip -l "$OUT" | tail -1
echo "$OUT"
