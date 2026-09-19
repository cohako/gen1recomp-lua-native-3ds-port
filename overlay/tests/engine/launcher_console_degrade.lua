-- Launcher draw on a backend with no shaders, meshes or stencil.
--
-- LOVE Potion (the 3DS/Switch/Wii U port) ships no shader compiler at all, and
-- the console backends expose no stencil path, so every optional GPU object the
-- launcher builds has to resolve to a fallback instead of raising.  This is not
-- cosmetic there: the launcher is also what runs the ROM auto-import on those
-- platforms (findPendingRom scans the save/source dir), so a crash in draw is a
-- crash before the player can import anything at all.
--
-- tests/love_stub deliberately omits newShader / newMesh / stencil, which makes
-- it exactly that backend.  Drawing a full frame through it is the assertion.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")

-- love_stub covers what the engine's headless tests need; the launcher is the
-- one screen that also asks for the desktop shell (OS name, pointer, clock).
-- Fill only the gaps, and only here, so the shared stub keeps modelling a
-- console-shaped graphics backend for everyone else.
local love = _G.love
-- Both the 3DS and the Switch report getOS() == "Horizon" (the LOVE Potion
-- build defines __OS__ that way for both), which is exactly why the console is
-- identified by love._console instead.  Set here for the Switch pass; the 3DS
-- pass at the bottom swaps it.
love.system = love.system or { getOS = function() return "Horizon" end }
love._console = "Switch"
love.timer = love.timer or { getTime = function() return 0 end }
-- No love.mouse is stubbed in on purpose: LOVE Potion does not build that
-- module (its source/modules ships touch, joystick and keyboard, no mouse), so
-- its absence here is the platform under test, not a gap.
love.window = love.window or { getMode = function() return 640, 576, {} end }

-- love.image is genuinely present on LOVE Potion, so its absence from the
-- shared stub is a stub gap, not the platform under test.  It stays local:
-- adding it to love_stub would flip the `love.image and ...` fallback branches
-- that TileRenderer, PartyMenu, Credits and Evolution are tested through.
if not love.image then
  local ImageData = {}
  ImageData.__index = ImageData
  function ImageData:setPixel() end
  function ImageData:mapPixel() end
  function ImageData:getWidth() return self.w end
  function ImageData:getHeight() return self.h end
  love.image = {
    newImageData = function(w, h)
      -- the path form (a PNG on disk) is not modelled; callers that pass one
      -- are expected to pcall, which is the behaviour being tested
      if type(w) ~= "number" then error("no image decoder in this stub", 0) end
      return setmetatable({ w = w, h = h }, ImageData)
    end,
  }
  local newImage = love.graphics.newImage
  love.graphics.newImage = function(src)
    if type(src) == "table" then
      return { w = src.w, h = src.h, setWrap = function() end,
               setFilter = function() end, getWidth = function() return src.w end,
               getHeight = function() return src.h end }
    end
    return newImage(src)
  end
end

-- The stub's fonts measure but do not wrap; the launcher's footer asks for the
-- wrapped lines so it can hit-test the community URL inside them.
do
  local newFont = love.graphics.newFont
  love.graphics.newFont = function(size)
    local font = newFont(size)
    font.getWrap = font.getWrap or function(self, text, width)
      return math.min(width, self:getWidth(text)), { tostring(text) }
    end
    return font
  end
end

local RomImporter = require("src.import.RomImporter")

local importer = RomImporter.new(function() end, { launcher = true })

-- Two frames: the first resolves every lazy object (shaders, meshes, the
-- CPU-inverted mark), the second proves the `false` sentinels are read back as
-- "unavailable" rather than retried and re-failed.
local ok, err = pcall(function()
  importer:draw()
  importer:draw()
end)
T.eq(ok, true, "the launcher draws with no shaders, meshes or stencil: "
  .. tostring(err))

-- The sentinel must be false, not nil: nil would mean "not resolved yet" and
-- would re-attempt the failing call on every frame of a 60Hz launcher.
-- (The July draft also tracked shineShader / bgMesh / scanline sentinels;
-- the launcher rewrite since removed those objects on every platform, so the
-- footer's invert mark is the one lazy shader left.)
T.eq(importer.invertShader, false, "the invert shader resolves to unavailable")

-- The console profile: no pointer to poll (there is no love.mouse to poll it
-- with), and the ROM scan is the only way in, so it must not be gated behind
-- the Android-only picker flags.
T.eq(importer.console, "Switch", "the console is identified by love._console")
T.eq(importer.android, false, "and is not misfiled as Android, which would "
  .. "reach for SAF pickers that do not exist here")
-- Hovering is the observable half of "there is no pointer here".  The
-- launcher rewrite dropped the _hoverEnabled field; hover now flows from the
-- frame's pointer coordinates, which resolve off-screen (-1,-1) when neither
-- the pad cursor nor a mouse module exists, so nothing can hit-test true.
T.eq(importer._padCursorActive or false, false,
  "no pad cursor is active before any pad input")

-- choose() must not open a dialog that cannot exist: with no ROM on the card it
-- reports where to put one instead of calling love.system.pickFile (absent).
local okChoose, chooseErr = pcall(function() importer:choose("red") end)
T.eq(okChoose, true, "choosing a ROM on a console does not reach for a picker: "
  .. tostring(chooseErr))
T.eq(type(importer.notice), "table", "it leaves a notice saying where to copy "
  .. "the cart")

-- ---------------------------------------------------------------- 3DS
-- The 3DS is the one console that has to drop the scanline overlay: the tile is
-- 1x3 and that GPU cannot "repeat"-wrap a non-power-of-two texture, so the
-- single draw call the effect exists for is the call it cannot make.
local Console = require("src.core.Console")
love._console = "3DS"
T.eq(Console.is3DS(), true, "love._console identifies the 3DS")
T.eq(Console.isConsole(), true, "and it counts as a console")

local threeDS = RomImporter.new(function() end, { launcher = true })
local ok3, err3 = pcall(function() threeDS:draw() end)
T.eq(ok3, true, "the launcher draws on a 3DS: " .. tostring(err3))
-- (The July draft asserted the 3DS drops the CRT scanline overlay; the
-- launcher rewrite removed that effect on every platform, so there is no
-- longer a scanline object to gate.)

love._console = nil

T.finish("launcher console degrade")
