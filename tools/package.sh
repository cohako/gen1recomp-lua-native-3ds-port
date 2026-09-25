#!/usr/bin/env sh
# Package a release zip laid out like the SD card root:
#   3ds/gen1recomp.3dsx
#   3ds/game/...
#   INSTALL.txt
#
# Output: dist/gen1recomp-<version>-3ds.zip (upstream's <name>-<version>-<platform> naming)
# Usage: tools/package.sh <path/to/gen1recomp.3dsx> [version]
#   expects work/game from tools/assemble.sh
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DSX=${1:?usage: package.sh <gen1recomp.3dsx> [version]}
VERSION=${2:-dev}
GAME="$ROOT/work/game"
STAGE="$ROOT/dist/stage"
OUT="$ROOT/dist/gen1recomp-$VERSION-3ds.zip"

[ -d "$GAME" ] || { echo "package: run tools/assemble.sh first" >&2; exit 1; }
rm -rf "$STAGE" "$OUT"; mkdir -p "$STAGE/3ds"
cp "$DSX" "$STAGE/3ds/gen1recomp.3dsx"
cp -R "$GAME" "$STAGE/3ds/game"
cat > "$STAGE/INSTALL.txt" <<'EOF'
Gen1Recomp - Lua Native 3DS Port

1. Copy the "3ds" folder onto the root of your SD card (merge with the
   existing one).
2. Make sure sdmc:/3ds/dspfirm.cdc exists. If not: Rosalina menu
   (L + Down + Select) -> Miscellaneous options -> Dump DSP firmware.
3. Import your ROM on the PC and copy the resulting version folder to
   sdmc:/3ds/save/pokemon-love2d/<version>/  (see README.md, "Importing a ROM").
4. Open the Homebrew Launcher and start Gen1Recomp.

Prefer a HOME menu icon?  Install the gen1recomp-<version>-3ds.cia from the
same Release with FBI (SD -> the .cia -> Install and delete).  The game is
inside the CIA, so step 1 is not needed; steps 2-3 still apply (same
3ds/save folder, and a 3ds/game on the card takes precedence when present).
EOF
(cd "$STAGE" && zip -qr "$OUT" .)
rm -rf "$STAGE"
echo "package: $OUT ($(du -h "$OUT" | cut -f1))"
