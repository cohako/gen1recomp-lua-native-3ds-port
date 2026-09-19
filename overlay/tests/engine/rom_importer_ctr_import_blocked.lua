-- No ROM import on the LOVE Potion consoles.  Measured on a New 2DS XL: a
-- Gen 2 import takes hours and the extractor's live heap does not fit the
-- ~32 MB the app gets under the Homebrew Launcher (native crash in malloc at
-- 68%).  The Import button therefore never reads a cart there; it tells the
-- player to import on the PC and copy the version folder to the SD card.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("console import blocked")
local check, eq = S.check, S.eq

local RomImporter = require("src.import.RomImporter")

love.filesystem = love.filesystem or {}
local reads = 0
love.filesystem.read = function() reads = reads + 1; return string.rep("Y", 1024 * 1024) end
love.filesystem.getInfo = function() return { type = "file", size = 1024 * 1024 } end
love.filesystem.getDirectoryItems = function() return { "crystal.gbc", "yellow.gb" } end
love.filesystem.getSaveDirectory = function() return "sdmc:/3ds/save/pokemon-love2d" end

local function importer()
  return setmetatable({
    console = true,
    baseRomDiscovery = false,
    baseRoms = {},
    ready = { red = false, blue = false, yellow = false, crystal = false },
    returning = {},
    workState = nil,
    nativePicker = false,
    isNX = false,
    startData = function(self, data, name) self.started = { data = data, name = name } end,
  }, RomImporter)
end

for _, version in ipairs({ "yellow", "crystal" }) do
  local imp = importer()
  imp:choose(version)
  check(imp.started == nil, version .. ": console Import never starts an import")
  check(imp.notice and imp.notice.status:find("PC", 1, true),
    version .. ": notice sends the player to the PC")
  eq(imp.notice.detail, "sdmc:/3ds/save/pokemon-love2d/" .. version,
    version .. ": notice names the folder to copy")
end
eq(reads, 0, "no cart is read on the console")

local ready = importer()
ready.ready.yellow = true
ready:reimport("yellow")
eq(ready.ready.yellow, true, "re-import on the console keeps the column ready")

S.finish()
