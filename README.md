# Gen1Recomp - Lua Native 3DS Port

A Nintendo 3DS / 2DS port of [gen1recomp](https://github.com/bryanthaboi/gen1recomp),
the LÖVE (Lua) recompilation of the Game Boy Pokémon games, running on a fork of
[LÖVE Potion](https://github.com/lovebrew/lovepotion).

Tested on a New 2DS XL with Luma3DS and the Homebrew Launcher. Old 3DS/2DS is
untested.

This repository does not contain the game. It contains:

| Path | What |
|---|---|
| `engine/` | The LÖVE Potion fork (C++), full source. Rendering, audio, input and shutdown fixes for the 3DS, native PNG decode/encode, the Gen1Recomp SMDH icon. |
| `overlay/` | New files added to the game: the 3DS platform layer (`src/core/Console.lua`, `CtrTrace.lua`), the console test suites, `scripts/3ds/`. |
| `patches/` | One diff per upstream game file the port edits (20 files). |
| `UPSTREAM` | The upstream gen1recomp commit the patches apply to. |
| `tools/` | `assemble.sh` (upstream + overlay + patches → `work/game/`), `package.sh` (release zip). |

Releases ship a zip laid out like the SD card root, so nobody needs any of the
above to play.

## Installing on the console

Requirements:

- Luma3DS (any recent version) and the Homebrew Launcher.
- `sdmc:/3ds/dspfirm.cdc`, the DSP firmware. It is Nintendo's and cannot be
  shipped here; every homebrew with sound needs it. Dump it once per SD card:
  open the Rosalina menu (**L + Down + Select**) → *Miscellaneous options* →
  *Dump DSP firmware*. It lands in the right place by itself. Without it the
  app exits before showing anything.

Steps:

1. Download `gen1recomp-3ds-<version>.zip` from the latest Release.
2. Extract it onto the root of the SD card, merging the `3ds` folder. You get
   `sdmc:/3ds/gen1recomp.3dsx` and `sdmc:/3ds/game/`.
3. Import your ROM on the PC (next section) and copy the version folder to
   `sdmc:/3ds/save/pokemon-love2d/`.
4. Open the Homebrew Launcher and start **Gen1Recomp**.

Without a card reader: netload `ftpd.3dsx` once, then
`scripts/3ds/ftp_upload_game.py <3DS-IP>` uploads the game tree over wifi.

**TODO: CIA install.** A `.cia` installable with FBI (own HOME menu icon, no
Homebrew Launcher, full application memory) is planned: `bannertool` +
`makerom` in the release workflow, then FBI *Scan QR Code* against the latest
release URL. Not built yet; the game-path and exit behaviour of LÖVE Potion
under a CIA still have to be verified on hardware.

## Importing a ROM (PC only)

The console does not import ROMs (see Limitations). Build the cache on a PC
with [LÖVE](https://love2d.org) installed, or with the packaged desktop game
via `LOVE_BIN`:

```sh
scripts/3ds/import_rom.sh "Pokemon - Crystal Version (USA, Europe) (Rev A).gbc"
```

The script runs the game's importer headless (`POKEPORT_IMPORT_ONLY=1`), then
copies the result out of LÖVE's save directory into
`dist/3ds-sd/3ds/save/pokemon-love2d/<version>/`:

```
<version>/
  assets/generated/     PNG textures -- the engine decodes PNG natively
  data/generated/
  rom-cache.complete    the marker the launcher checks; identical on every platform
```

Copy `dist/3ds-sd/3ds` onto the SD card root (merge). The launcher shows that
version as ready. Versions: `red`, `blue`, `yellow`, `gold`, `silver`,
`crystal`; the ROM is identified by SHA-1, both Crystal revisions are accepted.

Equivalent by hand: `POKEPORT_IMPORT_ONLY=1 POKEPORT_IMPORT_ROM=<rom> love .`
in an upstream checkout, then copy `~/.local/share/love/pokemon-love2d/<version>`
(Linux; `%APPDATA%\LOVE\...` on Windows, `~/Library/Application Support/LOVE/...`
on macOS).

### Music (optional)

The console cannot synthesize the chip music in real time, so map and battle
music is silent unless pre-rendered WAVs exist in the cache. Render them on
the PC (needs LuaJIT; the script's header shows the Docker one-liner):

```sh
luajit scripts/3ds/prerender_music.lua <path/to/version-cache>
```

Output goes to `<version>/assets/generated/audio/music/*.wav`; copy it with
the rest of the cache, or `scripts/3ds/ftp_upload_music.py <IP> --source <cache>`.
Yellow's full set is ~76 MB.

## Building

Everything runs in Docker; no toolchain install needed.

```sh
# 1. game tree (clones upstream at the pinned commit, applies overlay + patches)
tools/assemble.sh                       # -> work/game

# 2. engine
docker run --rm -v "$PWD/engine":/src -w /src devkitpro/devkitarm:latest \
  sh -c 'cmake -S . -B build -Wno-dev && ninja -C build'   # -> engine/build/lovepotion.3dsx

# 3. zip laid out like the SD root
tools/package.sh engine/build/lovepotion.3dsx v0.0.0-local
```

`UPSTREAM_DIR=/path/to/gen1recomp tools/assemble.sh` reuses a local clone.
Console test suites (`overlay/tests/engine/*.lua`) run with `luajit` from
`work/game`, same as CI.

Notes on the engine:

- The game is loaded from `sdmc:/3ds/game/`, never from the 3DSX RomFS (that
  belongs to LÖVE Potion: shaders and the no-game screen).
- PNG loads natively: decoded straight into the PICA200's 8×8 tile layout;
  anything above 1024 px is box-filtered down to fit. A sibling `.t3x`
  (`tex3ds -f rgba8888 -z auto`) is still preferred when present.
- Fonts use the console's system font; `.ttf` files are not parsed.
- The SMDH title, author, description and icon are set in `engine/CMakeLists.txt`
  (`platform/ctr/icon-gen1recomp.png`, 48×48).

## Updating the upstream game

Edit the `game` line in `UPSTREAM`, run `tools/assemble.sh`. A patch that no
longer applies is named in the output; regenerate it from a checkout with the
change re-applied (`git diff <upstream> -- <file> > patches/NN-<file>.patch`).
Run the tests, then verify on hardware.

## Current limitations

- **No ROM import on the console.** Measured on a New 2DS XL: a Gen 2 import
  took hours (one SD write and PNG encode per file) and then crashed in
  `malloc` at 68% -- the extractor keeps ~30 MB live in Lua 5.1 and the app
  gets ~32 MB under the Homebrew Launcher, shared with textures. The Import
  button only tells you which folder to copy.
- **No map/battle music** without the pre-render step above. Sound effects,
  cries and Yellow's Pikachu voice work.
- **Top screen only** (400×240). The bottom screen is unused.
- Tilt effect disabled (its 741×573 canvas does not fit VRAM). Palette effects
  run without shaders.
- `.3dsx` via Homebrew Launcher only; no CIA yet.
- Azahar/Citra cannot be used to test: LÖVE Potion exits immediately under it
  (lovebrew/LovePotion#102) while the same build runs on hardware.
- Upstream pinned to `fdd1d61e` (dev, 2026-09-05). Newer upstream releases
  need the patches refreshed.

## Debugging on hardware

- Lua errors: `sdmc:/3ds/save/pokemon-love2d/lua-error.log`.
- Trace (close sequence, import stages with heap size): `trace3ds.txt` in the
  same folder.
- Native crashes: Luma writes `sdmc:/luma/dumps/arm11/crash_dump_*.dmp`. Read
  `pc`/`lr` from the register dump and resolve them against the release's
  `lovepotion.elf`:
  `arm-none-eabi-addr2line -f -C -e lovepotion.elf <pc> <lr>`.
- `3dslink` does not stream stdout back; read errors from the files above.

## License

This repository (patches, overlay, tools, engine changes) is MIT, see
`LICENSE`. gen1recomp is © BOIS CLUB GAMES, LLC, MIT. LÖVE Potion is
© Serena S. Postelnek & Logan Hickok-Dickson, MIT (`engine/LICENSE.md`). No
Nintendo or Game Freak assets, ROMs or firmware are included.
