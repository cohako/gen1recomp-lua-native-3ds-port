-- Pre-rendered music on the 3DS: the console cannot synthesize the ROM's
-- channel programs as they play (interpreted Lua renders ~1 buffer per 8s,
-- some 43x short of real time), so import writes each song to a WAV beside the
-- rest of the derived cache and playback streams that file instead.
--
-- What must hold: the swap happens only where the platform asks for it, only
-- when the file is actually there, and it must hand Music's file branch a def
-- with no chip fields left -- startSong tests those first
-- (src/core/Music.lua), so a surviving ROM header would win and the song
-- would go right back to the synth that cannot keep up.
--
--   luajit tests/engine/prerendered_music_3ds.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

love = require("tests.love_stub")

local Source = {}
Source.__index = Source
function Source:play() self.playing = true end
function Source:stop() self.playing = false end
function Source:isPlaying() return self.playing end
function Source:setLooping(v) self.looping = v end
function Source:setVolume(v) self.volume = v end
function Source:setPitch() end
function Source:setFilter() end
function Source:getDuration() return 1 end

local made = {}
love.audio = {
  newSource = function(file, mode)
    made[#made + 1] = { file = file, mode = mode }
    return setmetatable({ file = file, mode = mode }, Source)
  end,
}

-- Stand in for the cache on disk: only what is listed here exists.
local onDisk = {}
love.filesystem = love.filesystem or {}
function love.filesystem.getInfo(path)
  return onDisk[path] and { type = "file" } or nil
end

local Music = require("src.core.Music")

local SONG = "Music_PalletTown"
local WAV = "assets/generated/audio/music/" .. SONG .. ".wav"

-- A ROM-backed def, exactly the shape RomExtractor writes into audio.songs.
local function freshData()
  return { audio = { songs = { [SONG] = { bank = 31, address = 0x4242 } } } }
end

-- Drive one playback attempt and report what love.audio.newSource was asked
-- for.  The chip path never reaches newSource, so an empty list means "went to
-- the synth" and an entry means "streamed a file".
local function play(consoleName, files, data)
  love._console = consoleName
  onDisk = files
  made = {}
  Music.reload() -- drops failed defs, the playing label and the prerender cache
  Music.play(data or freshData(), SONG)
  return made
end

-- 1. Desktop synthesizes live: the file must never be reached for, even when
-- one happens to be sitting in the cache.
local desktop = play(nil, { [WAV] = true })
eq(#desktop, 0, "off-console playback stays on the chip synth")

-- 2. On the 3DS with the render present, playback streams it.
local console = play("3DS", { [WAV] = true })
eq(#console, 1, "the 3DS reaches for exactly one audio file")
eq(console[1] and console[1].file, WAV,
   "and it is the song's pre-rendered WAV in the derived cache")
eq(console[1] and console[1].mode, "stream",
   "streamed rather than decoded into memory, as Music's file path does")

-- 3. A 3DS with no render must not silently lose the song: the def keeps its
-- ROM header and goes to the synth, which is what degrades gracefully.
local missing = play("3DS", {})
eq(#missing, 0, "with no WAV on disk the def keeps its ROM header")

-- 4. The real console layout: the cache lives under the active version's
-- prefix (yellow/assets/generated/...), which is where import writes it and
-- the only place the file actually is.  Reading audio.programPrefix instead
-- would look at the un-prefixed path and find nothing, so this is the case
-- that matters on hardware.
local GameVersion = require("src.core.GameVersion")
local realPrefix = GameVersion.cachePrefix
GameVersion.cachePrefix = function() return "yellow/" end
local viaPrefix = play("3DS", { ["yellow/" .. WAV] = true })
eq(#viaPrefix, 1, "a version-prefixed cache still finds the render")
eq(viaPrefix[1] and viaPrefix[1].file, "yellow/" .. WAV,
   "and streams it through the versioned path")

-- The un-prefixed path still wins when that is where the file sits, so a
-- build that mounts the version at the root keeps working.
local viaPlain = play("3DS", { [WAV] = true })
eq(viaPlain[1] and viaPlain[1].file, WAV,
   "and falls back to the plain path when the cache is mounted at the root")
-- Switching versions inside one process must not serve the previous game's
-- recording: every version names its songs identically, so the lookup is
-- keyed by prefix as well.  Both trees exist here, which is exactly the state
-- a launcher leaves behind after importing two ROMs.
local bothVersions = { ["yellow/" .. WAV] = true, ["red/" .. WAV] = true }
GameVersion.cachePrefix = function() return "yellow/" end
local asYellow = play("3DS", bothVersions)
eq(asYellow[1] and asYellow[1].file, "yellow/" .. WAV, "Yellow streams its own render")

-- No reload() in between: the cache from the Yellow playback above is still
-- warm, and must not answer for Red.
GameVersion.cachePrefix = function() return "red/" end
made = {}
Music.stop()
Music.play(freshData(), SONG)
eq(made[1] and made[1].file, "red/" .. WAV,
   "and switching to Red streams Red's, not the cached Yellow path")

GameVersion.cachePrefix = realPrefix

-- 5. The substitution must not mutate the shared registry def: the next
-- platform (or a reimport) still needs the ROM header that lives there.
local shared = freshData()
play("3DS", { [WAV] = true }, shared)
local def = shared.audio.songs[SONG]
eq(def.bank, 31, "the registry def keeps its bank")
eq(def.address, 0x4242, "and its address")
check(def.file == nil, "and never acquires a file field of its own")

love._console = nil
T.finish("pre-rendered music on 3DS")
