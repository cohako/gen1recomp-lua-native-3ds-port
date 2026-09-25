#!/usr/bin/env sh
# Build the 3DS SD-card folder from your ROMs.  Double-click it (or run it);
# it asks nothing.
#
#   1. finds the gen1recomp desktop app (or plain love) next to this folder
#   2. imports every ROM in ./roms that it can recognise
#   3. copies every cache the app has -- including ones you imported by hand
#      in the app -- into ./sd-card/3ds/save/pokemon-love2d/<version>/
#
# Then drag ./sd-card/3ds onto the root of your SD card.
set -eu
cd "$(dirname "$0")"
HERE=$(pwd)
ROMS="$HERE/roms"
OUT="$HERE/sd-card/3ds/save/pokemon-love2d"

find_app() {
  # The packaged game first (no extra install for people who already play it),
  # then a plain LÖVE, then the game tree next to us for a source checkout.
  for c in "$HERE"/../gen1recomp*.AppImage "$HERE"/gen1recomp*.AppImage \
           "$HERE"/../gen1recomp "$HERE"/gen1recomp; do
    [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  for c in "$HERE/../Gen1Recomp.app/Contents/MacOS/love" \
           "/Applications/Gen1Recomp.app/Contents/MacOS/love" \
           "/Applications/love.app/Contents/MacOS/love"; do
    [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  command -v love >/dev/null 2>&1 && { printf 'love'; return 0; }
  return 1
}

# LÖVE keeps saves under <appdata>/LOVE/<identity>, but a fused (packaged)
# build drops the LOVE level.  Check both, plus the macOS spelling.
save_dirs() {
  printf '%s\n' \
    "${XDG_DATA_HOME:-$HOME/.local/share}/love/pokemon-love2d" \
    "${XDG_DATA_HOME:-$HOME/.local/share}/pokemon-love2d" \
    "$HOME/Library/Application Support/LOVE/pokemon-love2d" \
    "$HOME/Library/Application Support/pokemon-love2d"
}

APP=$(find_app) || {
  cat >&2 <<'MSG'
Export-3DS: no gen1recomp app found.

Put this folder next to the gen1recomp desktop app (the one you play on the
PC), or install LÖVE from https://love2d.org, then run this again.
MSG
  exit 1
}
echo "using: $APP"

mkdir -p "$ROMS"
imported=0
for rom in "$ROMS"/*.gb "$ROMS"/*.gbc "$ROMS"/*.GB "$ROMS"/*.GBC; do
  [ -f "$rom" ] || continue
  echo "importing $(basename "$rom") ..."
  # POKEPORT_IMPORT_ONLY / POKEPORT_IMPORT_ROM are the game's own headless
  # import mode: it imports, writes the cache, and quits without a window.
  if POKEPORT_IMPORT_ONLY=1 POKEPORT_IMPORT_ROM="$rom" "$APP" >/dev/null 2>&1; then
    imported=$((imported + 1))
  else
    echo "  skipped (not a recognised ROM, or the import failed)" >&2
  fi
done

copied=0
mkdir -p "$OUT"
for dir in $(save_dirs); do
  [ -d "$dir" ] || continue
  for marker in "$dir"/*/rom-cache.complete; do
    [ -f "$marker" ] || continue
    version=$(basename "$(dirname "$marker")")
    rm -rf "$OUT/$version"
    cp -R "$(dirname "$marker")" "$OUT/$version"
    echo "  $version  ($(du -sh "$OUT/$version" | cut -f1))"
    copied=$((copied + 1))
  done
done

echo
if [ "$copied" -eq 0 ]; then
  cat <<MSG
Nothing to export yet.

Put your own Game Boy ROM files (.gb / .gbc) in:
  $ROMS
and run this again -- or import them in the desktop app first.
MSG
  exit 1
fi
cat <<MSG
Done: $copied version(s) ready in
  $HERE/sd-card/3ds

Copy that "3ds" folder onto the root of your SD card (merge with the folder
already there), put the card back in the console, and start Gen1Recomp.
MSG
