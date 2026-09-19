#!/usr/bin/env sh
# Import a ROM on the PC and stage its cache for the 3DS SD card.
#
# The console can import on its own, but on its CPU that takes hours.  This
# runs the same importer on the desktop (POKEPORT_IMPORT_ONLY: no launcher,
# no click, quits when done) and copies the result out of LÖVE's hidden save
# directory into the repo, laid out exactly like the SD card:
#
#   dist/3ds-sd/3ds/save/pokemon-love2d/<version>/
#
# Copy dist/3ds-sd/3ds onto the card's root (merge) and the launcher on the
# console shows that version as ready.  No Docker needed -- only `love`
# (love2d.org), or the packaged desktop executable via LOVE_BIN.
#
# Usage: scripts/3ds/import_rom.sh <rom.gb|rom.gbc> [more roms...]
#   LOVE_BIN=/path/to/love   binary to run (default: love on PATH)
set -eu

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT="$ROOT/dist/3ds-sd/3ds/save/pokemon-love2d"
LOVE_BIN=${LOVE_BIN:-love}

command -v "$LOVE_BIN" >/dev/null 2>&1 || {
  echo "import_rom: '$LOVE_BIN' not found. Install LÖVE (https://love2d.org) or set LOVE_BIN." >&2
  exit 1
}
[ $# -ge 1 ] || { echo "Usage: $0 <rom.gb|rom.gbc> [...]" >&2; exit 1; }

case "$(uname -s)" in
  Darwin) SAVE="$HOME/Library/Application Support/LOVE/pokemon-love2d" ;;
  *)      SAVE="${XDG_DATA_HOME:-$HOME/.local/share}/love/pokemon-love2d" ;;
esac

for ROM in "$@"; do
  [ -f "$ROM" ] || { echo "import_rom: no such file: $ROM" >&2; exit 1; }
  ROM=$(cd "$(dirname "$ROM")" && pwd)/$(basename "$ROM")
  echo "importing $(basename "$ROM") ..."
  ( cd "$ROOT" && POKEPORT_IMPORT_ONLY=1 POKEPORT_IMPORT_ROM="$ROM" "$LOVE_BIN" . )

  # The importer names the version from the ROM's SHA-1; the freshest marker
  # is the one it just wrote.
  MARKER=$(ls -t "$SAVE"/*/rom-cache.complete 2>/dev/null | head -1)
  [ -n "$MARKER" ] || { echo "import_rom: import wrote no rom-cache.complete under $SAVE" >&2; exit 1; }
  VERSION=$(basename "$(dirname "$MARKER")")

  mkdir -p "$OUT"
  rm -rf "$OUT/$VERSION"
  cp -R "$SAVE/$VERSION" "$OUT/$VERSION"
  echo "  -> $OUT/$VERSION  ($(du -sh "$OUT/$VERSION" | cut -f1))"
done

echo
echo "Copy $ROOT/dist/3ds-sd/3ds onto the SD card root (merge folders)."
