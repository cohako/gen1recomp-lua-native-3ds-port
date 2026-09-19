-- Which Nintendo console this is running on, or nil everywhere else.
--
-- love.system.getOS() cannot answer this.  The LOVE Potion build defines
-- __OS__ as "Horizon" for BOTH the 3DS and the Switch, and "Cafe" for the
-- Wii U (lovebrew/lovepotion CMakeLists.txt), so an OS test meaning "3DS"
-- would equally catch a Switch -- two machines separated by roughly two orders
-- of magnitude of CPU and an order of magnitude of pixels.  Anything scaled to
-- the hardware has to distinguish them.
--
-- The console name is published separately, as the love._console string
-- ("3DS" / "Switch" / "Wii U", set in source/modules/love/love.cpp).  It is
-- absent on desktop LOVE, on Android and on iOS, which is what makes its mere
-- presence the "is this a console" probe.
--
-- Nothing here is cached: the two table lookups are free next to a frame, and
-- caching would freeze whatever the first caller saw, which tests override.

local Console = {}

-- The console names LOVE Potion publishes.  An unrecognized string is treated
-- as "not a console we know", not as a console -- a future port would need its
-- own branches here anyway, and guessing would silently apply 3DS-shaped
-- compromises to hardware that does not need them.
local NAMES = { ["3DS"] = true, ["Switch"] = true, ["Wii U"] = true }

-- "3DS" / "Switch" / "Wii U", or nil.
function Console.name()
  local name = love and rawget(love, "_console")
  if type(name) == "string" and NAMES[name] then return name end
  return nil
end

-- Running on a LOVE Potion console at all.  Falls back to the OS name so a
-- build that stops publishing love._console still takes the console paths
-- (both strings are unique to LOVE Potion), even though it cannot then say
-- which console it is.
function Console.isConsole()
  if Console.name() then return true end
  local os = love and love.system and love.system.getOS and love.system.getOS()
  return os == "Horizon" or os == "Cafe"
end

-- The 3DS specifically: a 400x240 top screen on a 268MHz ARM11, which is the
-- one target where effects the other two render for free have to be dropped.
function Console.is3DS()
  return Console.name() == "3DS"
end

-- Whether songs must arrive as audio files the decoder streams rather than be
-- synthesized from the ROM's channel programs as they play.  The 3DS cannot do
-- the latter: interpreted Lua on this CPU renders about one buffer per eight
-- seconds of wall clock, roughly 43x short of real time, so the synth worker
-- never catches up no matter how deep the queue.  Import pre-renders each song
-- to a WAV beside the rest of the derived cache and this sends playback there.
function Console.prefersPrerenderedMusic()
  return Console.is3DS()
end

return Console
