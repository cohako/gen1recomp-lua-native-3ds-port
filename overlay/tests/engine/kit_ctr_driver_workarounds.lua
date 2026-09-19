-- 3DS driver workarounds, both verified on a New 2DS XL (2026-08-12):
--
--  * setScissor: the CTR framebuffer is stored rotated and LOVE Potion's
--    scissor path (platform/ctr framebuffer_ext.cpp) applies the rect against
--    the wrong axis, so a clip meant for a row band cut a vertical stripe
--    that drifted sideways as the page scrolled.  The GPU cut is skipped on
--    the 3DS; the tracked rect must survive, because it is what bounds
--    Kit.hit and keeps clipped-out widgets inert.
--
--  * rounded rectangles: the CTR triangulation of love.graphics.rectangle's
--    rounded variant draws partial boxes, so both Theme radii collapse to 0
--    there -- square corners draw correctly.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")

local love = _G.love
love._console = "3DS"

local Kit = require("src.ui.kit.Kit")
local Theme = require("src.ui.kit.Theme")

-- record setScissor traffic through the stub
local calls = 0
local realScissor = love.graphics.setScissor
love.graphics.setScissor = function(...) calls = calls + 1 end

Kit.pushClip(10, 10, 50, 50)
T.eq(Kit._clipRect ~= nil and Kit._clipRect.x == 10 and Kit._clipRect.w == 50,
  true, "3DS pushClip still records the rect that bounds Kit.hit")
T.eq(calls, 0, "3DS pushClip never reaches the GPU scissor")
Kit.popClip()

T.eq(Theme.radius(), 0, "3DS buttons draw square corners")
T.eq(Theme.cardRadius(), 0, "3DS cards draw square corners")

-- sanity: everywhere else keeps the scissor and the rounded look
love._console = nil
calls = 0
Kit.pushClip(10, 10, 50, 50)
T.eq(calls > 0, true, "desktop pushClip drives the GPU scissor")
Kit.popClip()
T.eq(Theme.radius() > 0, true, "desktop keeps rounded buttons")

love.graphics.setScissor = realScissor
T.finish("kit ctr driver workarounds")
