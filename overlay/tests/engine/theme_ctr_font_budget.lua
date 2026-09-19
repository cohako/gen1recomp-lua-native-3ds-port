-- 3DS font budget: every newFont() copies the ~3MB system font into the
-- linear heap (32MB total, less under the Homebrew Launcher).  The launcher's
-- nine distinct sizes exhausted it and LOVE Potion memcpy'd into the failed
-- (NULL) allocation -- an ARM11 data abort, which pcall cannot catch
-- (verified on hardware, crash dump resolved to TrueTypeRasterizer/memcpy).
-- Two buckets keep the cost near 6MB and still separate body from headings.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")

local love = _G.love
love._console = "3DS"

local sizes = {}
local realNewFont = love.graphics.newFont
love.graphics.newFont = function(a, ...)
  if type(a) == "number" then sizes[a] = true end
  return realNewFont(a, ...)
end

local Theme = require("src.ui.kit.Theme")
Theme.fonts(1.17)          -- the scale the 400x240 clamp produces today

local distinct = 0
for _ in pairs(sizes) do distinct = distinct + 1 end
T.eq(distinct <= 2, true,
  ("3DS builds at most 2 font sizes (got %d)"):format(distinct))

-- everywhere else the full ramp stays
love._console = nil
sizes = {}
Theme.fonts(1.17)
local desktopDistinct = 0
for _ in pairs(sizes) do desktopDistinct = desktopDistinct + 1 end
T.eq(desktopDistinct > 2, true, "desktop keeps its full size ramp")

love.graphics.newFont = realNewFont
T.finish("theme ctr font budget")
