#!/bin/sh
# Prepare (or remove) the Steam Workshop upload copy of CeroSec.
#
# The game scans ~/Zomboid/Workshop/*/Contents/mods/* as mods too, and a
# SYMLINK there makes ScriptManager build a doubled, lowercased path and lose
# every script file (seen 2026-09-10 and again 2026-09-12). So the Workshop
# folder holds a plain COPY, made only when publishing, and removed right
# after the upload so the game goes back to loading ~/Zomboid/mods/CeroSec.
#
#   sh tools/workshop-sync.sh sync    copy 42/, common/ and workshop/ there
#   sh tools/workshop-sync.sh clean   remove the copy (keep workshop.txt, preview.png)
set -eu
REPO=$(cd "$(dirname "$0")/.." && pwd)
WS="$HOME/Zomboid/Workshop/CeroSec"
DEST="$WS/Contents/mods/CeroSec"
case "${1:-}" in
  sync)
    mkdir -p "$DEST"
    rsync -a --delete "$REPO/42" "$REPO/common" "$DEST/"
    # Steam writes its item id into the Workshop-side workshop.txt after the
    # first upload; keep that line when the repo copy has none yet.
    ID=$(grep -h '^id=' "$WS/workshop.txt" 2>/dev/null | head -1 || true)
    for f in workshop.txt preview.png; do
      rm -f "$WS/$f"; cp "$REPO/workshop/$f" "$WS/$f"
    done
    if [ -n "$ID" ] && ! grep -q '^id=' "$WS/workshop.txt"; then
      printf '%s\n' "$ID" >> "$WS/workshop.txt"
      echo "kept Steam's $ID (copy it into $REPO/workshop/workshop.txt and commit)"
    fi
    echo "copied to $DEST"
    echo "upload from the game, then: sh tools/workshop-sync.sh clean"
    ;;
  clean)
    rm -rf "$DEST"
    echo "removed $DEST (the game loads $REPO again)"
    ;;
  *) echo "usage: $0 sync|clean" >&2; exit 2 ;;
esac
