-- Report what a rendered music WAV actually contains, so quality can be
-- judged without listening: duration, level, whether the two channels differ,
-- and how much of the head/tail is silence.
local path = arg[1] or error("usage: inspect_wav.lua <file.wav>")
local handle = assert(io.open(path, "rb"))
local body = handle:read("*a")
handle:close()

local function u16(at) return body:byte(at) + body:byte(at + 1) * 256 end
local function u32(at)
  return body:byte(at) + body:byte(at + 1) * 256
       + body:byte(at + 2) * 65536 + body:byte(at + 3) * 16777216
end

assert(body:sub(1, 4) == "RIFF" and body:sub(9, 12) == "WAVE", "not a RIFF/WAVE file")
local channels, rate, bits = u16(23), u32(25), u16(35)
local dataSize = u32(41)
local frames = dataSize / (channels * bits / 8)

local function sampleAt(frame, channel)
  local at = 45 + (frame * channels + (channel - 1)) * 2
  local lo, hi = body:byte(at), body:byte(at + 1)
  if not hi then return 0 end
  local v = lo + hi * 256
  if v >= 32768 then v = v - 65536 end
  return v / 32768
end

local sumSq, peak, differing, clipped = 0, 0, 0, 0
local firstLoud, lastLoud
for frame = 0, frames - 1 do
  local left = sampleAt(frame, 1)
  local right = channels == 2 and sampleAt(frame, 2) or left
  if channels == 2 and left ~= right then differing = differing + 1 end
  local mag = math.abs(left)
  if mag >= 0.9999 then clipped = clipped + 1 end
  if mag > peak then peak = mag end
  if mag > 0.005 then
    if not firstLoud then firstLoud = frame end
    lastLoud = frame
  end
  sumSq = sumSq + left * left
end

print(("file        %s"):format(path:match("[^/]+$")))
print(("format      %d ch, %d Hz, %d-bit"):format(channels, rate, bits))
print(("duration    %.2f s (%d frames)"):format(frames / rate, frames))
print(("size        %.1f KB"):format(#body / 1024))
print(("peak        %.3f"):format(peak))
print(("rms         %.4f"):format(math.sqrt(sumSq / frames)))
print(("clipped     %d frames at full scale (%.3f%%)"):format(clipped, clipped / frames * 100))
if channels == 2 then
  print(("stereo      %d/%d frames differ L/R (%.1f%%) -- %s"):format(
    differing, frames, differing / frames * 100,
    differing == 0 and "MONO CONTENT: half the bytes are redundant"
                    or "genuinely stereo"))
end
print(("lead-in     %.2f s of silence"):format((firstLoud or frames) / rate))
print(("tail        %.2f s of silence"):format((frames - (lastLoud or 0)) / rate))
