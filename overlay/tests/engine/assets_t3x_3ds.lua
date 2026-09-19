-- 3DS texture paths: the bundler rewrites shipped PNGs to .t3x.
--
-- The lovebrew bundler converts every image in the bundle to the 3DS texture
-- format and does NOT keep the original, so `assets/logo/logo.png` simply does
-- not exist inside a built .3dsx -- `assets/logo/logo.t3x` does.  Loading the
-- .png path there is a hard error, and it fired in RomImporter.new, which is
-- the first thing the app builds: the launcher died before drawing a frame,
-- with nothing in the log after service registration.
--
-- Only shipped art is converted.  Everything under assets/generated/ is
-- written as PNG by the ROM import at runtime, long after the bundler ran, so
-- the swap must be driven by whether a .t3x actually exists rather than
-- applied to every .png path.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local Assets = require("src.render.Assets")

local love = _G.love

-- Model a built .3dsx: the shipped logo exists only as .t3x, while a
-- runtime-generated texture exists only as .png.
local present = {
  ["assets/logo/logo.t3x"] = true,
  ["assets/generated/tilesets/ship.png"] = true,
}
local realGetInfo = love.filesystem.getInfo
love.filesystem.getInfo = function(path, ...)
  if present[path] then return { type = "file" } end
  if path:match("^assets/") then return nil end
  return realGetInfo and realGetInfo(path, ...) or nil
end

local realConsole = love._console

-- --------------------------------------------------------------- desktop
love._console = nil
T.eq(Assets.resolve("assets/logo/logo.png"), "assets/logo/logo.png",
  "off-console, a .png path is left exactly as written")

-- ------------------------------------------------------------------- 3DS
love._console = "3DS"
T.eq(Assets.resolve("assets/logo/logo.png"), "assets/logo/logo.t3x",
  "on a 3DS, shipped art resolves to the .t3x the bundler produced")
T.eq(Assets.resolve("assets/generated/tilesets/ship.png"),
  "assets/generated/tilesets/ship.png",
  "but a runtime-generated PNG stays PNG: it has no .t3x, having been written "
  .. "after the bundler ran")
T.eq(Assets.resolve("assets/logo/missing.png"), "assets/logo/missing.png",
  "and a path with no .t3x sibling is left alone rather than pointed at a "
  .. "file that does not exist either")

-- Non-strings pass through untouched: resolve() is called with whatever a
-- caller had, and must not start indexing nil.
T.eq(Assets.resolve(nil), nil, "a nil path survives resolve")

-- The Switch and Wii U keep their PNGs -- only the 3DS gets converted art, so
-- swapping there would point at a file the build does not contain.
love._console = "Switch"
T.eq(Assets.resolve("assets/logo/logo.png"), "assets/logo/logo.png",
  "the Switch keeps the .png: only the 3DS build converts textures")

love._console = realConsole
love.filesystem.getInfo = realGetInfo

T.finish("assets t3x 3ds")
