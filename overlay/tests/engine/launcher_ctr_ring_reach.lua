-- Every focusable control must be reachable by dpad alone at 400x240.
--
-- On the 3DS the ring is the only input (no pointer module exists), and the
-- hardware bring-up (2026-08-12) found two ways it stranded: a wide row's
-- centre out-scored the small chips on its right, so "down" skipped Rename /
-- Delete entirely; and focus walked into controls whose rects had scrolled
-- off-screen.  This walks the ring over the real control geometry captured
-- from the device (focus.log: the red tab with one save slot) and asserts a
-- dpad-only fixpoint reaches every control.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")

local love = _G.love
love._console = "3DS"
local realDims = love.graphics.getDimensions
local realW, realH = love.graphics.getWidth, love.graphics.getHeight
love.graphics.getDimensions = function() return 400, 240 end
love.graphics.getWidth = function() return 400 end
love.graphics.getHeight = function() return 240 end

local Kit = require("src.ui.kit.Kit")

-- geometry captured on the 2DS (sizes in framebuffer pixels)
local controls = {
  { id = "gear",        x = 289, y = 6,   w = 46,  h = 46 },
  { id = "quit",        x = 342, y = 6,   w = 46,  h = 46 },
  { id = "tab-red",     x = 12,  y = 61,  w = 88,  h = 46 },
  { id = "tab-blue",    x = 107, y = 61,  w = 46,  h = 46 },
  { id = "rom-red",     x = 28,  y = 132, w = 344, h = 44 },
  { id = "slot-row",    x = 28,  y = 180, w = 344, h = 40 },
  { id = "slot-rename", x = 240, y = 182, w = 60,  h = 35 },
  { id = "slot-del",    x = 307, y = 182, w = 53,  h = 35 },
  { id = "slot-new",    x = 28,  y = 226, w = 344, h = 44 },
}

local function frame()
  Kit.beginFrame(-1, -1, false, 0)
  for _, c in ipairs(controls) do Kit.focusable(c.id, c.x, c.y, c.w, c.h) end
  Kit.endFrame()
end

-- seed the ring
Kit.focusId = nil
frame()
frame()

local reached = { [Kit.focusId] = true }
local moved = true
local guard = 0
while moved and guard < 200 do
  moved = false
  guard = guard + 1
  local frontier = {}
  for id in pairs(reached) do frontier[#frontier + 1] = id end
  for _, id in ipairs(frontier) do
    for _, dir in ipairs({ "up", "down", "left", "right" }) do
      Kit.setFocus(id)
      Kit.navigate(dir)
      frame()   -- _resolveNav consumes the queued direction
      if Kit.focusId and not reached[Kit.focusId] then
        reached[Kit.focusId] = true
        moved = true
      end
    end
  end
end

for _, c in ipairs(controls) do
  T.eq(reached[c.id] == true, true, "reachable by dpad: " .. c.id)
end

love.graphics.getDimensions = realDims
love.graphics.getWidth, love.graphics.getHeight = realW, realH
love._console = nil
T.finish("launcher ctr ring reach")
