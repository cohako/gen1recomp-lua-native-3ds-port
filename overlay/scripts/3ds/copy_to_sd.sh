#!/usr/bin/env bash
# Copy 3DS homebrew builds to a mounted SD card.
#
# Usage: scripts/3ds/copy_to_sd.sh /media/user/SDCARD [mini|full]

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SD="${1:-}"
WHICH="${2:-full}"

[ -n "$SD" ] || { echo "usage: $0 /path/to/sdcard [mini|full]" >&2; exit 1; }
[ -d "$SD" ] || { echo "error: $SD is not a mounted directory" >&2; exit 1; }

mkdir -p "$SD/3ds"

case "$WHICH" in
  mini) SRC="/tmp/fused3ds/mini.3dsx"; DST="$SD/3ds/mini.3dsx" ;;
  full) SRC="$ROOT/dist/3ds/Gen1Recomp.3dsx"; DST="$SD/3ds/Gen1Recomp.3dsx" ;;
  *) echo "error: expected 'mini' or 'full'" >&2; exit 1 ;;
esac

[ -f "$SRC" ] || { echo "error: missing $SRC (run: make -f Makefile.3ds)" >&2; exit 1; }

cp "$SRC" "$DST"
sync
echo "copied $(du -h "$DST" | cut -f1) -> $DST"
