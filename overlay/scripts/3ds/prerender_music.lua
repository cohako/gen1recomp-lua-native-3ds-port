-- Offline music pre-render: turns a ROM cache's chip programs into WAV files
-- the file-playback path in Music.lua can stream, for platforms that cannot
-- synthesize in real time (the 3DS).  Uses the real ChipSynth, so the output
-- is the same audio the desktop synthesizes live.
--
--   docker run --rm -v "$PWD":/src -v "$CACHE":/cache -w /src \
--     akorn/luajit:2.1-alpine luajit scratchpad/prerender_music.lua /cache [song...]
--
-- Writes <cache>/assets/generated/audio/music/<Song>.wav.

package.path = "./?.lua;./?/init.lua;" .. package.path

local cacheDir = arg[1] or error("usage: prerender_music.lua <cacheDir> [song...]")
local only = {}
for index = 2, #arg do only[arg[index]] = true end
local ONLY_SOME = next(only) ~= nil

love = require("tests.love_stub")

-- The stub's filesystem is a fixture sandbox; point reads at the real cache so
-- ChipSynth's loadBanks finds programs.bin.
love.filesystem = love.filesystem or {}
function love.filesystem.read(path)
  local handle = io.open(cacheDir .. "/" .. path, "rb")
  if not handle then return nil, "not found: " .. path end
  local body = handle:read("*a")
  handle:close()
  return body
end

local ChipSynth = require("src.core.ChipSynth")

local audio = dofile(cacheDir .. "/data/generated/audio.lua")
local data = { audio = audio }

local RATE = ChipSynth.SAMPLE_RATE
-- A song rendered with allowLoops=false stops at its loop point, so this only
-- catches a song that never loops and never ends.
local MAX_SECONDS = 240

local function u16(v)
  return string.char(v % 256, math.floor(v / 256) % 256)
end
local function u32(v)
  return string.char(v % 256, math.floor(v / 256) % 256,
    math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256)
end
local function i16le(f)
  local v = math.floor(f * 32767 + (f >= 0 and 0.5 or -0.5))
  if v > 32767 then v = 32767 elseif v < -32768 then v = -32768 end
  if v < 0 then v = v + 65536 end
  return string.char(v % 256, math.floor(v / 256) % 256)
end

-- Same RIFF layout RomExtractor:extractPikachuCries already writes
-- (src/import/RomExtractor.lua:2362), but mono: Gen 1 pans every channel
-- uniformly (engine.pan defaults to 0xFF), so a stereo render measured
-- bit-identical across L/R -- the second channel is pure duplication.
local function wav(pcm)
  return "RIFF" .. u32(36 + #pcm) .. "WAVEfmt " .. u32(16)
    .. u16(1) .. u16(1) .. u32(RATE) .. u32(RATE * 2) .. u16(2) .. u16(16)
    .. "data" .. u32(#pcm) .. pcm
end

-- Render until the song ends on its own.  allowLoops=false makes the bytecode's
-- infinite-loop command (0xFE with count 0, ChipSynth.lua:662-670) end the
-- channel instead of jumping back, so what comes out is exactly one pass from
-- the start to the loop point.
local function render(header)
  local engine = ChipSynth.newEngine(data, header, { allowLoops = false })
  local limit = RATE * MAX_SECONDS
  local parts, count = {}, 0
  while count < limit and not engine:finished() do
    count = count + 1
    parts[count] = i16le(engine:sample())
  end
  return table.concat(parts), count, count >= limit
end

local outDir = cacheDir .. "/assets/generated/audio/music"
os.execute(("mkdir -p '%s'"):format(outDir))

local names = {}
for name in pairs(audio.songs or {}) do
  if not ONLY_SOME or only[name] then names[#names + 1] = name end
end
table.sort(names)

if #names == 0 then
  print("no songs matched")
  os.exit(1)
end

print(("pre-rendering %d song(s) at %dHz into %s"):format(#names, RATE, outDir))
local totalBytes, failures = 0, 0
for _, name in ipairs(names) do
  local started = os.clock()
  local ok, pcm, samples, truncated = pcall(render, audio.songs[name])
  if not ok then
    print(("  %-34s FAILED: %s"):format(name, tostring(pcm)))
    failures = failures + 1
  else
    local body = wav(pcm)
    local handle, openError = io.open(outDir .. "/" .. name .. ".wav", "wb")
    if not handle then
      print(("  %-34s WRITE FAILED: %s"):format(name, tostring(openError)))
      failures = failures + 1
    else
      handle:write(body)
      handle:close()
      totalBytes = totalBytes + #body
      print(("  %-34s %6.2fs  %5.1fKB  rendered in %5.2fs%s"):format(
        name, samples / RATE, #body / 1024, os.clock() - started,
        truncated and "  [TRUNCATED]" or ""))
    end
  end
end

print(("done: %d ok, %d failed, %.1f MB total"):format(
  #names - failures, failures, totalBytes / 1048576))
