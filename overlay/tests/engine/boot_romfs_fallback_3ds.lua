-- The engine's boot.lua on the 3DS: when the relative "game" source does not
-- resolve (a CIA install with no sdmc:/3ds/game on the card), the game comes
-- from the title's own RomFS at romfs:/game.  When the SD copy is there it
-- wins, and the RomFS is never tried -- updating or modding the game stays a
-- plain file copy.  Off the console the fallback does not exist at all.
--
-- boot.lua is loaded as a plain Lua chunk: its first line is R"luastring"--(,
-- the C++ raw-string wrapper, which is a call to a global R here.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")

local BOOT = "../../engine/source/modules/love/scripts/boot.lua"

-- Runs boot.lua's love.boot() against a fake love whose setSource accepts
-- only the sources in `mounts`.  Returns the sources tried, in order, and
-- whether the no-game screen was reached.
local function boot(console, mounts)
  local tried, nogame = {}, false
  local source = nil
  local love
  love = {
    _console = console,
    arg = {
      getLow = function() return "lovepotion" end,
      options = { game = { set = false, arg = { "game" } }, fused = { set = false } },
      parseOptions = function() love.arg.options.game.set = true end,
      parseGameArguments = function() return {} end,
    },
    filesystem = {
      init = function() end,
      getExecutablePath = function() return "sdmc:/3ds/gen1recomp.3dsx" end,
      setSource = function(path)
        tried[#tried + 1] = path
        if not mounts[path] then error("not a source: " .. path) end
        source = path
      end,
      setFused = function() end,
      getRealDirectory = function() return source end,
      setIdentity = function() end,
      getInfo = function() return source and { type = "file" } or nil end,
      getWorkingDirectory = function() return "sdmc:/3ds" end,
    },
    path = {
      getFull = function(p) return p end,
      leaf = function(p) return (p:gsub("^.*/", "")) end,
    },
  }
  package.loaded["love"] = love
  package.loaded["love.arg"] = true
  package.loaded["love.callbacks"] = true
  package.loaded["love.filesystem"] = true
  package.loaded["love.nogame"] = function() nogame = true end
  _G.R = function() end
  _G.arg = { [0] = "lovepotion" }
  local realOpen = io.open
  io.open = function() return nil end -- no sdmc:/gen1_boot_error.txt here
  local chunk = assert(loadfile(BOOT))
  chunk()
  love.boot()
  io.open = realOpen
  return tried, source, nogame
end

-- CIA on a card with no 3ds/game: the RomFS copy boots.
local tried, source, nogame = boot("3DS", { ["romfs:/game"] = true })
T.eq(source, "romfs:/game", "no SD game on the 3DS: the RomFS game is the source")
T.eq(nogame, false, "and the no-game screen is not shown")
T.eq(tried[#tried], "romfs:/game", "the RomFS is the last thing tried")

-- SD copy present: it wins and the RomFS is never tried.
tried, source = boot("3DS", { ["game"] = true, ["romfs:/game"] = true })
T.eq(source, "game", "an SD game wins over the RomFS copy")
for _, path in ipairs(tried) do
  T.eq(path ~= "romfs:/game", true, "the RomFS is not tried when the SD game mounts")
end

-- Nothing anywhere: the no-game screen, as before.
tried, source, nogame = boot("3DS", {})
T.eq(source, nil, "no game anywhere: no source")
T.eq(nogame, true, "the no-game screen is reached")

-- Not a 3DS: the RomFS is never a candidate.
tried, source, nogame = boot(nil, { ["romfs:/game"] = true })
T.eq(source, nil, "off the console the RomFS fallback does not exist")
for _, path in ipairs(tried) do
  T.eq(path ~= "romfs:/game", true, "romfs:/game is not tried off the console")
end

T.finish("boot romfs fallback 3ds")
