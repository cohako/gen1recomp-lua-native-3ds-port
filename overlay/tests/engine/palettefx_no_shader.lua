-- PaletteFX with no shader compiler behind it.
--
-- PaletteFX.shader() / keyedShader() already resolve to nil where newShader
-- fails, and most callers test for that and skip the colorized path entirely.
-- sendColors is the exception: BattleState:drawZonePass sets the shader once
-- and then calls sendColors per zone from inside its loop, so a nil arriving
-- there used to become nil:send() in the middle of a battle draw.
--
-- This is not hypothetical on the LOVE Potion consoles: that port compiles no
-- shaders at all, so shader() is nil on every frame of every battle.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local PaletteFX = require("src.render.PaletteFX")

-- The stub compiles no shaders, which is the platform being modelled.
T.eq(PaletteFX.shader(), nil, "no shader resolves where none can be compiled")
T.eq(PaletteFX.keyedShader(), nil, "and neither does the keyed variant")

local COLORS = { { 255, 255, 255 }, { 170, 170, 170 }, { 85, 85, 85 },
                 { 0, 0, 0 } }

local ok, err = pcall(PaletteFX.sendColors, nil, COLORS)
T.eq(ok, true, "sending colors to a nil shader is a no-op, not a crash: "
  .. tostring(err))

-- The guard must not swallow the real path: a shader that IS present still
-- receives all four uniforms, or every colorized platform silently goes gray.
local sent = {}
local fake = { send = function(_, name, value) sent[name] = value end }
PaletteFX.sendColors(fake, COLORS)
T.eq(sent.c0 ~= nil and sent.c1 ~= nil and sent.c2 ~= nil and sent.c3 ~= nil,
  true, "a real shader still gets all four shade uniforms")
T.eq(sent.c3[1], 0, "and they carry the mapped colors, normalized to 0..1")

T.finish("palettefx no shader")
