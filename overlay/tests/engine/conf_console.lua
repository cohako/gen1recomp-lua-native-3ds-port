-- conf.lua on the LOVE Potion consoles (3DS / Switch / Wii U).
--
-- conf runs before love.load and before any module is available, so it has only
-- the love._* strings the engine sets during initialization to go on.  Three
-- things have to come out right there, and none of them are observable later:
-- the declared API version (LOVE Potion is 12.0, this game declares 11.5), the
-- mouse module (that port builds none), and the window constraints (a 480x360
-- minimum is larger than the entire 3DS screen).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")

-- A conf table shaped like the one LOVE hands love.conf: defaults already
-- filled in, for the callback to overwrite.
local function newConf()
  return {
    identity = nil, version = "0.0.0", window = {}, modules = {},
  }
end

local function runConf()
  local t = newConf()
  -- conf.lua defines a global love.conf; load it fresh each time so an earlier
  -- run cannot leak state into the next.
  assert(loadfile("conf.lua"))()
  love.conf(t)
  return t
end

local realConsole, realVersion, realOs = love._console, love._version, love._os

-- ------------------------------------------------------------------ desktop
love._console, love._version, love._os = nil, nil, "OS X"
local desktop = runConf()
T.eq(desktop.version, "11.5", "desktop still declares the LOVE it targets")
T.eq(desktop.window.resizable, true, "and keeps its resizable window")
T.eq(desktop.window.minwidth, 480, "with the drag floor the launcher needs")
T.eq(desktop.modules.mouse, nil, "and says nothing about the mouse module")

-- ------------------------------------------------------------------ console
love._console, love._version, love._os = "3DS", "12.0", "Horizon"
local ctr = runConf()
T.eq(ctr.version, "12.0", "a console declares the API the running engine has, "
  .. "read from love._version rather than hardcoded a second time")
T.eq(ctr.modules.mouse, false, "and asks for no mouse module, which that port "
  .. "does not build")
T.eq(ctr.window.resizable, false, "a console window does not resize")
T.eq(ctr.window.minwidth, nil, "and carries no desktop drag floor: 480x360 is "
  .. "larger than the whole 400x240 3DS screen")
T.eq(ctr.window.minheight, nil, "neither dimension of it")

-- The console branch has to run after the mobile/desktop branch, which ends in
-- an `else` that re-enables resizing.  Ordering is the whole bug here, so pin
-- it on a second console rather than trusting one case.
love._console, love._version, love._os = "Switch", "12.0", "Horizon"
T.eq(runConf().window.resizable, false,
  "the console branch wins over the desktop else that follows it")

-- A LOVE Potion build that stopped publishing love._version must not blank the
-- declared version, which would read as "no version" to the engine.
love._console, love._version, love._os = "Wii U", nil, "Cafe"
T.eq(runConf().version, "11.5", "a missing love._version falls back rather "
  .. "than clearing the declaration")

love._console, love._version, love._os = realConsole, realVersion, realOs

T.finish("conf console")
