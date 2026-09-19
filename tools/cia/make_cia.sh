#!/usr/bin/env sh
# Build the installable CIA from the engine ELF.
#
#   tools/cia/make_cia.sh <lovepotion.elf> <out.cia> [vMAJOR.MINOR.MICRO]
#
# The optional version (a release tag) goes into the title's 16-bit version
# field (major<<10 | minor<<4 | micro -- what FBI lists and what the HOME menu
# compares on reinstall) and into the SMDH description.  Default 0.0.1.
#
# Fetches pinned Linux x86_64 builds of makerom and bannertool into
# tools/cia/.bin (checksums verified), renders the banner and SMDH icon from
# the PNGs here, and packs engine/platform/ctr/romfs as the title's RomFS.
# Nothing from Nintendo goes in: the title is signed with makerom's public
# test keys (-target t), which is why a CFW is needed to install it.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
ELF=${1:?usage: make_cia.sh <lovepotion.elf> <out.cia>}
OUT=${2:?usage: make_cia.sh <lovepotion.elf> <out.cia> [vX.Y.Z]}
VERSION=${3:-v0.0.1}
case "$VERSION" in
  v[0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "make_cia: version must be vMAJOR.MINOR.MICRO (got '$VERSION')" >&2; exit 1 ;;
esac
IFS=. read -r MAJOR MINOR MICRO <<EOF2
$(printf %s "$VERSION" | sed 's/^v//')
EOF2
for n in "$MAJOR" "$MINOR" "$MICRO"; do
  case "$n" in ''|*[!0-9]*) echo "make_cia: version parts must be plain integers (got '$VERSION')" >&2; exit 1 ;; esac
done
# 16-bit title version: 6 bits major, 6 bits minor, 4 bits micro
if [ "$MAJOR" -gt 63 ] || [ "$MINOR" -gt 63 ] || [ "$MICRO" -gt 15 ]; then
  echo "make_cia: version out of range (major/minor <= 63, micro <= 15): $VERSION" >&2; exit 1
fi
TITLE_VER=$(( (MAJOR << 10) | (MINOR << 4) | MICRO ))
BIN="$HERE/.bin"
ROMFS="$ROOT/engine/platform/ctr/romfs"

MAKEROM_URL=https://github.com/3DSGuy/Project_CTR/releases/download/makerom-v0.19.0/makerom-v0.19.0-ubuntu_x86_64.zip
MAKEROM_SHA=287b809dec064e0ad597e3d272c49ecb7eed41693d5ee6fef9d8a8aa24c2497e
BANNERTOOL_URL=https://github.com/carstene1ns/3ds-bannertool/releases/download/1.2.3/bannertool-1.2.3-linux.tar.gz
BANNERTOOL_SHA=748519d200519db18e9fd00c332ac32f5411e41230258291e89953a76c1f7155

fetch() { # url sha dest
  curl -fsSL -o "$3" "$1"
  echo "$2  $3" | sha256sum -c - >/dev/null || { echo "make_cia: checksum mismatch for $1" >&2; exit 1; }
}

mkdir -p "$BIN"
if [ ! -x "$BIN/makerom" ]; then
  fetch "$MAKEROM_URL" "$MAKEROM_SHA" "$BIN/makerom.zip"
  (cd "$BIN" && unzip -qo makerom.zip makerom && chmod +x makerom)
fi
if [ ! -x "$BIN/bannertool" ]; then
  fetch "$BANNERTOOL_URL" "$BANNERTOOL_SHA" "$BIN/bannertool.tar.gz"
  tar -xzf "$BIN/bannertool.tar.gz" -C "$BIN" --strip-components=1 --wildcards '*/bannertool'
  chmod +x "$BIN/bannertool"
fi

"$BIN/bannertool" makebanner -i "$HERE/banner.png" -a "$HERE/silence.wav" -o "$BIN/banner.bnr" >/dev/null
"$BIN/bannertool" makesmdh -s "Gen1Recomp" -l "Gen1Recomp - Lua Native 3DS Port $VERSION" -p "cohako" \
  -i "$HERE/icon.png" -o "$BIN/icon.icn" >/dev/null

mkdir -p "$(dirname "$OUT")"
"$BIN/makerom" -f cia -o "$OUT" -elf "$ELF" -rsf "$HERE/gen1recomp.rsf" \
  -icon "$BIN/icon.icn" -banner "$BIN/banner.bnr" -DAPP_ROMFS="$ROMFS" -target t -exefslogo \
  -ver "$TITLE_VER"
echo "make_cia: $OUT ($(du -h "$OUT" | cut -f1)) version $VERSION (title version $TITLE_VER)"
