# Console instrumentation (removed from the shipped build)

Everything below was used to bring the port up on hardware and was then taken
out, because each probe does blocking SD-card I/O every frame or every second.
The code is kept here as two patches so it can be put back in one command when
a console-only problem needs evidence again.

```sh
# re-add (from the repo root; apply to the fork checkout and to the assembled game)
patch -p0 -d engine     < docs/instrumentation-engine.patch   # paths are engine/...
patch -p0 -d work/game  < docs/instrumentation-game.patch     # paths are game/...
# remove again
patch -p0 -R -d engine    < docs/instrumentation-engine.patch
patch -p0 -R -d work/game < docs/instrumentation-game.patch
```

(The patches were generated with directory prefixes `engine/` and `game/`;
use `-p1` when applying from inside those directories.)

Rule that paid for itself every time: **add the probe first, read the whole
file it produces, then change code.** Hypotheses formed from a screenshot cost
a console cycle each; one probe usually names the cause outright.

## What is still in the build (failure-only, no cost during play)

| File on SD | Written by | When |
|---|---|---|
| `sdmc:/gen1_init.txt` | `engine/platform/ctr/source/runtime.cpp` (`tryInit`) | a system service failed to initialise (`code=` is the `AbortCode` index: 0 romfs, 1 mcuHwc, 2 ptmu, 3 cfgu, 4 ac, 5 frd, 6 y2r; `result=` is the libctru `Result`). Under a CIA the error applet cannot be shown this early, so this file is the only report. |
| `sdmc:/gen1_boot_error.txt` | `engine/source/modules/love/scripts/boot.lua` | `love.boot` failed (traceback), or the no-game screen was reached (`exepath`, `cwd`, `tried` = the source path that was rejected). |
| `sdmc:/3ds/save/pokemon-love2d/lua-error.log` | game (`main.lua` error handler) | any uncaught Lua error, with the LÖVE/OS line. |
| `sdmc:/luma/dumps/arm11/crash_dump_NNNNN.dmp` | Luma3DS | native crash. Decode: header is 40 bytes; registers follow (`r0..r12, sp, lr, pc, cpsr`, then `dfsr/far`); `arm-none-eabi-addr2line -f -C -e lovepotion.elf <pc> <lr>` against the **same build's** ELF. Words in the stack dump that fall in `0x00100000..0x00800000` are candidate return addresses. |

## What the patches put back, and what to read in each

### Engine (`docs/instrumentation-engine.patch`)

| Probe | File written | Where in the code | Read it for |
|---|---|---|---|
| **Close-path breadcrumbs** `love_ctr_closelog(msg)` | `sdmc:/gen1_close.txt` (append, one fsynced line per stage) | `renderer_ext.cpp` (function), calls in `main.cpp` (RunLOVE tail, fast-exit, main tail), `love_ext.cpp` (MainLoop grace frames), `hid_ext.cpp` (APT ONEXIT hook) | A hang or crash **while closing** (HOME menu, START to launcher). The last line names the stage that blocked. `grace-start` = `aptMainLoop()` went false while Lua was still running (HOME close); `normal path: lua_close` = in-game quit. `apt-onexit hook` present = the ONEXIT hook fired (it does under a CIA, not under hbloader). |
| **Composition trace** `love_ctr_trace(fmt, ...)` / `tracef` | `sdmc:/gen1_trace.txt` (first 240 frames) | `renderer_ext.cpp`: every `bind` (target + viewport), `clear`, `draw n=`, `-- present --`; `framebuffer_ext.cpp`: every `scissor in=… out=…` (` EMPTY` when the converted rect collapsed) | The screen composes wrong (black, partial, wrong target). Read frame by frame: a `clear` right after `bind screen` with no `draw` before `present` means the canvas never received the draws; a scissor marked `EMPTY` explains a missing region. |
| **Render health snapshot** | `sdmc:/gen1_stats.txt` (one line per 60 presents) | `renderer_ext.cpp`, in `Present()` before `C3D_FrameEnd` | Performance and memory over time: `lin=` free linear heap, `vram=` free VRAM, `cmd=` fraction of the GPU command buffer used (0.08 in the overworld, 0.36 peak in battle transitions — GPU is not the bottleneck), `verts=`/`peak=` vertices this frame / max, `splits=` frame splits, `draws=` draw calls (≈80 overworld, up to ~1000 in heavy scenes: that is the Lua cost). A line that stops appearing while the app is alive = the render thread is wedged. |
| **Heap split at start** | `sdmc:/gen1_init.txt` | `runtime.cpp`, end of `userAppInit` | `heap=` / `linear=` / `appRegion=` for the current launch mode (`3dsx:` or `cia:`). Expected: 3dsx ≈ 24 MB heap + 32 MB linear (inherited from the host title); CIA ≈ 91 MB + 32 MB. `heap≈3 MB` means the RSF lost `ResourceLimitCategory` = Application. |
| **`chdir` check** | `sdmc:/gen1_init.txt` | `runtime.cpp`, after `chdir("sdmc:/3ds")` | `rc=0 cwd=sdmc:/3ds` expected under a CIA. Anything else and the game tree / save dir resolve to the wrong place. |
| **System font allocation** | `sdmc:/gen1_init.txt` | `fontmodule_ext.cpp`, `loadFromArchive` | `linearAlloc(<bytes>) failed; linearFree=` — the 3 MB system font did not fit the linear heap. (The build still throws a clear exception here without the probe.) |

### Game (`docs/instrumentation-game.patch`)

All game-side probes go through `src/core/CtrTrace.lua` (restored by the
patch): `require("src.core.CtrTrace").log(tag, msg)` appends
`t=<seconds> [tag] msg` to `trace3ds.txt` in the save directory, only when
`Console.is3DS()`.

| Tag | Where | Read it for |
|---|---|---|
| `[close]` | `main.lua` `love.quit` (enter / branch / done), `SessionLifecycle.endProcess` (`shutdown N begin/end` per registered shutdown) | Which shutdown callback hangs when closing; whether `love.quit` ran at all (pairs with the engine's `gen1_close.txt`). |
| `[import]` | `RomImporter:_pumpExtract` (`<stage> mem=<MB> files=n/total` on every stage change, `thread died:`, `failed:`), fed by `memKB = collectgarbage("count")` in `ExtractThread.lua` | Where an on-console import dies and how much Lua heap it held (`Menu graphics mem=25.0MB` was the last line before the malloc crash; the app has ~32 MB under the launcher). |
| `[chip]` | `ChipAudio.playMusic` (skipped / sync fallback / threaded, `newEngine FAILED`, `newQueueableSource FAILED`), worker pump (`worker buffer ERROR`, `source:play ok= err= queued=`) | Music path decisions and audio worker health. `source:play` with `queued=0` repeatedly = the synth is not keeping up (measured ~1 buffer per 8 s on this CPU). |
| `[music]` | `Music.startSong` (chip bank/addr and result, or `file <path>`) | Whether a song went the chip route or the pre-rendered WAV route, and why it produced no source. |
| `[canvas]` | `PixelCanvas.new` on `newCanvas` failure | Which canvas size ran the console out of VRAM (`741x573` was the Tilt canvas). |
| **Freeze probe** (`POKEPORT_CTR_PROBE=1`) | `main.lua`, `__ctrProbeAfterDraw` → `probe3ds.txt` in the save dir, once a second | Whether the game *thinks* it is drawing while the screen is frozen: the line keeps advancing → engine-side problem; it stops → game logic stalled. |

## Pulling the files

Netload `ftpd.3dsx`, then from the PC:

```sh
scripts/3ds/mirror_sd.py <3DS-IP>          # mirrors /3ds/game and /3ds/save/pokemon-love2d
# or one file:
python3 -c "from ftplib import FTP; f=FTP(); f.connect('<3DS-IP>',5000); f.login(); f.retrlines('RETR /gen1_close.txt')"
```

Delete the `sdmc:/gen1_*.txt` files between runs: everything appends.
