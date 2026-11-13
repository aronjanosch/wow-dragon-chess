#!/usr/bin/env bash
# Search the community listfile (FileDataID;path) for WoW assets to reference by ID.
# Usage: tools/wow_asset.sh '<regex>' [max]   e.g. 'sound/spells/frostnova'  or  'spells/.*stun.*\.m2'
# The listfile (~150 MB) is downloaded once to ~/.cache/dragon-chess/ (github.com/wowdev/wow-listfile).
set -euo pipefail
LF="${LISTFILE:-$HOME/.cache/dragon-chess/community-listfile.csv}"
if [[ ! -s "$LF" ]]; then
	mkdir -p "$(dirname "$LF")"
	curl -sL -o "$LF" "https://github.com/wowdev/wow-listfile/releases/latest/download/community-listfile.csv"
fi
grep -iE "^[0-9]+;[^;]*(${1})" "$LF" | head -n "${2:-30}"
