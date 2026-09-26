#!/usr/bin/env sh
# Package a release zip laid out like the SD card root, plus the PC-side
# export tools:
#   3ds/gen1recomp.3dsx
#   3ds/game/...
#   import-tools/     double-click scripts that build the SD folder from a ROM
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
cp -R "$ROOT/import-tools" "$STAGE/import-tools"
cat > "$STAGE/INSTALL.txt" <<'EOF'
Gen1Recomp - Lua Native 3DS Port

1. Dump the DSP firmware once per SD card, or there is no sound and the app
   closes at startup: Rosalina menu (L + Down + Select) -> Miscellaneous
   options -> Dump DSP firmware.

2. Build your ROM cache on the PC.  Put "import-tools" next to the gen1recomp
   desktop app, drop your own .gb / .gbc files into import-tools/roms, and
   double-click the file for your system:
       Windows   import-tools/Export-3DS.bat
       macOS     import-tools/Export-3DS.command
       Linux     import-tools/Export-3DS.sh
   It asks nothing and prints where it saved everything.  Already imported a
   ROM in the desktop app?  It picks that up too, no ROM file needed.

3. Copy onto the root of your SD card, merging with what is there:
       the "3ds" folder from this zip
       the "3ds" folder from import-tools/sd-card

4. Start the game:
       Homebrew Launcher -> Gen1Recomp
   Or, for an icon on the HOME menu, install gen1recomp-<version>-3ds.cia
   from the same Release with FBI (SD -> the .cia -> Install and delete).  The
   game is inside the CIA, so the "3ds" folder from this zip is not needed;
   steps 1-2 and the import-tools "3ds" folder still apply (a 3ds/game on the
   card takes precedence when present).
EOF
(cd "$STAGE" && zip -qr "$OUT" .)
rm -rf "$STAGE"
echo "package: $OUT ($(du -h "$OUT" | cut -f1))"
