-- 3DS circle pad: the Y axes arrive with +1 at the top, the opposite of the
-- SDL convention every other platform follows and that the pad-cursor and
-- scroll maths assume (verified on hardware: stick up scrolled down until
-- the sign flip).  X is untouched, and no other platform is.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")

local love = _G.love
love._console = "3DS"

local RomImporter = require("src.import.RomImporter")

-- The smallest importer the method needs: it only reads/writes _padAxis and
-- consults the pad-cursor state fields.
local imp = { _padAxis = {}, _padCursorActive = false }

RomImporter.gamepadaxis(imp, nil, "lefty", -1)   -- SDL: -1 = up
T.eq(imp._padAxis.lefty, 1, "3DS lefty is inverted")
RomImporter.gamepadaxis(imp, nil, "righty", 0.5)
T.eq(imp._padAxis.righty, -0.5, "3DS righty is inverted")
RomImporter.gamepadaxis(imp, nil, "leftx", 0.7)
T.eq(imp._padAxis.leftx, 0.7, "3DS leftx is untouched")

love._console = nil
RomImporter.gamepadaxis(imp, nil, "lefty", -1)
T.eq(imp._padAxis.lefty, -1, "desktop lefty is untouched")

T.finish("rom importer ctr axis")
