#!/usr/bin/env sh
# Assemble the game tree for the 3DS: upstream gen1recomp at the pinned
# commit, plus this repo's overlay files and patches.
#
# Result: work/game/ -- the folder that goes to sdmc:/3ds/game/ on the card.
#
# Usage: tools/assemble.sh [work-dir]
#   UPSTREAM_DIR=/path/to/gen1recomp   reuse a local clone instead of cloning
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=${1:-$ROOT/work}
GAME="$WORK/game"

read -r UPSTREAM_REPO UPSTREAM_SHA <<EOF
$(grep -v '^#' "$ROOT/UPSTREAM" | grep '^game ' | cut -d' ' -f2-)
EOF

rm -rf "$GAME"; mkdir -p "$WORK"
if [ -n "${UPSTREAM_DIR:-}" ]; then
  echo "assemble: copying $UPSTREAM_DIR at $UPSTREAM_SHA"
  git -C "$UPSTREAM_DIR" archive --format=tar --prefix=game/ "$UPSTREAM_SHA" | tar -x -C "$WORK"
else
  echo "assemble: cloning https://github.com/$UPSTREAM_REPO at $UPSTREAM_SHA"
  git init -q "$GAME"
  git -C "$GAME" remote add origin "https://github.com/$UPSTREAM_REPO.git"
  git -C "$GAME" fetch -q --depth 1 origin "$UPSTREAM_SHA"
  git -C "$GAME" checkout -q FETCH_HEAD
  rm -rf "$GAME/.git"
fi

echo "assemble: overlay"
cp -R "$ROOT/overlay/." "$GAME/"

echo "assemble: patches"
git -C "$GAME" init -q
failed=0
for p in "$ROOT"/patches/*.patch; do
  if git -C "$GAME" apply --whitespace=nowarn "$p"; then
    echo "  ok   $(basename "$p")"
  else
    echo "  FAIL $(basename "$p")" >&2; failed=1
  fi
done
rm -rf "$GAME/.git"
[ "$failed" -eq 0 ] || { echo "assemble: a patch no longer applies to $UPSTREAM_SHA -- refresh it" >&2; exit 1; }

# Not shipped to the console: other platforms' packaging, desktop launchers,
# CI and dev tooling.  Runtime is main.lua, conf.lua, src/, data/, assets/,
# mods/, tools/rom_manifest*.json (+ tests/ for CI).
(cd "$GAME" && rm -rf mobile ports dist .github scratch_repos flatpak native docs test \
  *.deb build-*.sh install-*.sh Play-*.command Play-*.bat .luacheckrc .gitignore \
  tools/save-editor/node_modules 2>/dev/null
 # tools/: the game reads rom_manifest*.json, save-editor/ and shaderfx-bridge/ only.
 find tools -mindepth 1 -maxdepth 1 ! -name 'rom_manifest*.json' ! -name save-editor ! -name shaderfx-bridge -exec rm -rf {} +)
echo "assemble: done -> $GAME"
