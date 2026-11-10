#!/bin/sh
# Install the WeaponStash addon into a WoW client's Interface/AddOns folder.
#
# Usage:
#   scripts/install.sh [--link] [flavor]
#
#   flavor   client folder inside the WoW install, e.g. _classic_era_ or _anniversary_.
#            Optional when only one client is installed.
#   --link   symlink instead of copying: edits in this repo show up in game after /reload.
#
# The WoW install defaults to /Applications/World of Warcraft; override with WOW_DIR.

set -eu

ADDON=WeaponStash
REPO=$(cd "$(dirname "$0")/.." && pwd)
SRC="$REPO/$ADDON"
WOW_DIR=${WOW_DIR:-"/Applications/World of Warcraft"}

link=0
flavor=""
for arg in "$@"; do
    case "$arg" in
        --link) link=1 ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) flavor=$arg ;;
    esac
done

if [ -z "$flavor" ]; then
    found=""
    for dir in "$WOW_DIR"/_*_/Interface/AddOns; do
        [ -d "$dir" ] || continue
        f=$(basename "$(dirname "$(dirname "$dir")")")
        found="$found $f"
    done
    set -- $found
    if [ $# -eq 1 ]; then
        flavor=$1
    elif [ $# -eq 0 ]; then
        echo "No Interface/AddOns folder found under $WOW_DIR (set WOW_DIR)." >&2
        exit 1
    else
        echo "Several clients found; pick one:$found" >&2
        echo "  e.g. scripts/install.sh $1" >&2
        exit 1
    fi
fi

ADDONS="$WOW_DIR/$flavor/Interface/AddOns"
DEST="$ADDONS/$ADDON"
[ -d "$ADDONS" ] || { echo "Not found: $ADDONS" >&2; exit 1; }

if [ "$link" -eq 1 ]; then
    if [ -L "$DEST" ]; then
        rm "$DEST"
    elif [ -e "$DEST" ]; then
        echo "$DEST already exists as a copy; remove it first to link instead." >&2
        exit 1
    fi
    ln -s "$SRC" "$DEST"
    echo "Linked $DEST -> $SRC"
else
    if [ -L "$DEST" ]; then
        rm "$DEST" # replace an earlier symlink with a real copy
    fi
    mkdir -p "$DEST"
    # --delete keeps the installed folder an exact copy (removes files deleted here).
    rsync -a --delete "$SRC/" "$DEST/"
    echo "Copied $ADDON to $DEST"
fi
echo "Run /reload in game (or restart the client)."
