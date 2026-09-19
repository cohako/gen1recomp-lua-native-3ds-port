-- Turning into the Pikachu follower rings SFX_COLLISION -- and that is the
-- original's behaviour, not a defect.  Reported as "the bump sound plays when
-- I change direction without hitting anything"; the follower IS the thing
-- being hit.
--
-- Yellow's CollisionCheckOnLand (home/overworld.asm:1215-1267) gives the
-- follower no silent branch: the PIKACHU_SPRITE_INDEX path falls through
-- `dec [hl]` on wPikachuCollisionCounter and `jr nz, .collision` into the very
-- same .collision label an ordinary wall bump uses, which plays SFX_COLLISION
-- guarded only by wChannelSoundIDs + CHAN5.  Only the terminal 1->0 decrement
-- takes `jr z` and passes silently.  The counter is seeded to 8 on a direction
-- change (.handleDirectionButtonPress, :175-199, which then `jp OverworldLoop`
-- without any collision check) and zeroed with no d-pad held
-- (.noDirectionButtonsPressed, :125-130) or once a step commits
-- (.moveAhead2, :238-242).
--
-- So the port is right to ring it, and is in fact gentler than the original:
-- Yellow decrements once per collision check -- one OverworldLoop iteration,
-- two DelayFrame calls, so ~14 frames of block and up to 7 collision events
-- starting 2 frames after the turn -- while this port drains the counter once
-- per fixed step (PikachuFollower.lua:551-556), including during the 4-frame
-- turn window where no collision check runs at all.  That costs the block half
-- its length and delays the first cue to the frame the turn window opens.
--
-- What this locks down is the shape: the cue fires only with the follower
-- actually in the way, only on a hold past the turn window, and never on a tap
-- or onto open floor.
--
-- This drives the REAL Player, PikachuFollower and OverworldState.handleInput
-- (not a reimplementation) against a stub open-floor map and a hand-built
-- follower npc, ROM-free -- same idiom as tests/engine/turn_in_place_bug415.lua
-- (inline map stub) and tests/engine/pikachu_counter_shadow_2196.lua (hand-
-- built follower npc), plus the debug-upvalue trick tests/engine/
-- trainer_talk_sting_bug764.lua already uses to run OverworldController
-- methods with no love.stack/Screens machinery.  The Sound.play cue capture
-- is the same wrapper as
-- tests/drivers/menu_sfx_bug960_bug961_bug1044_bug1045_test.lua:22-45.
--
-- One simplification: the follower npc is a plain table, not a real NPC
-- instance, with a no-op :update -- safe here because the player never
-- actually completes a step onto the follower's cell in any scenario below
-- (that is the bug: it never gets the chance to), so PikachuFollower.update's
-- own chase logic (which would call npc:update) never engages.
--
--   luajit tests/engine/pikachu_block_collision_sfx.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local Collision = require("src.world.Collision")
local FieldDefaults = require("src.world.FieldDefaults")
local GameVersion = require("src.core.GameVersion")
local Input = require("src.core.Input")
local OW = require("src.world.OverworldController")
local Player = require("src.world.Player")
local PikachuFollower = require("src.world.PikachuFollower")
local Sound = require("src.core.Sound")
local Game = require("src.core.Game")

Collision.load(Data)
Data.field.playerSprites = { walk = "SPRITE_FIX_PLAYER" }
-- shouldSpawn (PikachuFollower.lua:144) only checks this table entry is
-- truthy -- it never touches sprite pixels -- so a sentinel is enough
Data.sprites.SPRITE_PIKACHU = true
GameVersion.set("yellow")

local window = FieldDefaults.world(Data, "turnFrames")
T.eq(window, 4, "fixture turn window is 4 fixed steps, as in bug415")

-- OverworldController.lua:36 forward-declares `local Game`, assigned only by
-- :enter(); every OW.* function closes over that ONE upvalue slot, so
-- pointing any one of them at the real Game singleton wires all of them
-- (checkEdgeExit, checkLedgeHop, checkBoulderPush, dirHeld, canCollisionWarp,
-- pushableAtCell...) without ever calling :enter (which wants a real map/
-- Screens/StateStack). Same trick as trainer_talk_sting_bug764.lua.
local function setUpvalue(fn, name, val)
  local i = 1
  while true do
    local n = debug.getupvalue(fn, i)
    if not n then return false end
    if n == name then debug.setupvalue(fn, i, val); return true end
    i = i + 1
  end
end
T.check(setUpvalue(OW.handleInput, "Game", Game),
  "Game upvalue wired on OverworldController")

Game.data = Data
Game.input = Input
Game.save = {
  onBike = false,
  pikachuInBall = false,
  flags = { EVENT_GOT_STARTER = true, EVENT_BATTLED_RIVAL_IN_OAKS_LAB = true },
  party = { { species = "PIKACHU", hp = 20 } },
}
Input:init()

-- an always-open floor: no wall, no water, no tile-pair rule -- isolates the
-- follower as the only possible blocker (same shape as bug415's stub map)
local map = {
  def = { tileset = "FIX_OUT" },
  inBounds = function(_, x, y) return x >= 0 and y >= 0 and x < 20 and y < 20 end,
  isWalkableCell = function() return true end,
  isWaterCell = function() return false end,
  cellTile = function() return 0 end,
}

-- cue capture, same idiom as menu_sfx_bug960_bug961_bug1044_bug1045_test.lua
local cues, frame = {}, 0
local realPlay = Sound.play
Sound.play = function(data, name)
  cues[#cues + 1] = { name = name, frame = frame }
  return realPlay(data, name)
end
local function firstCollisionFrame()
  for _, c in ipairs(cues) do if c.name == "Collision" then return c.frame end end
  return nil
end

-- fresh player + optional follower, facing "up" with the follower parked on
-- the tile behind (south) -- so pressing "down" turns the player around to
-- face it.  withFollower=false leaves save.party without a Pikachu so
-- PikachuFollower.update's own shouldSpawn gate never conjures one either.
local function newScenario(withFollower)
  Input:reset()
  cues, frame = {}, 0
  Game.save.party = withFollower and { { species = "PIKACHU", hp = 20 } } or {}
  local player = Player.new(Data, 5, 6, "up")
  local ow = setmetatable({
    map = map, player = player, npcs = {}, entities = { player },
    bumpCooldown = 0,
  }, { __index = OW })
  local npc
  if withFollower then
    npc = {
      pikachuFollower = true, passable = true, facing = "up",
      cellX = 5, cellY = 7, px = 5 * 16, py = 7 * 16,
      def = { name = "PIKACHU_FOLLOWER", sprite = "SPRITE_PIKACHU",
              movement = "STAY" },
      update = function() end, -- see file header: never exercised here
    }
    ow.npcs = { npc }
    ow.entities = { player, npc }
  end
  return ow, player, npc
end

-- One fixed step, real production order (OverworldController.lua:1423-1465):
-- per-npc update, then PikachuFollower.update, then handleInput (tryMove +
-- the bump SFX live here), then Player:update (turnTimer countdown).
local function tick(ow, dir)
  frame = frame + 1
  if dir then Input.state[dir] = true end
  for _, n in ipairs(ow.npcs) do n:update(ow.map, ow.entities) end
  PikachuFollower.update(Game, ow)
  local pikaCounter = ow.pikachuCollisionCounter or 0
  local turnTimerBefore = ow.player.turnTimer
  local cuesBefore = #cues
  ow:handleInput()
  local bumped = false
  for i = cuesBefore + 1, #cues do
    if cues[i].name == "Collision" then bumped = true end
  end
  ow.player:update()
  return { frame = frame, turnTimer = turnTimerBefore, pikaCounter = pikaCounter,
           passable = ow.npcs[1] and ow.npcs[1].passable, bumped = bumped }
end

local function printTimeline(rows, label)
  print("  " .. label)
  print("  frame  turnTimer  pikaCounter  passable  Collision?")
  for _, r in ipairs(rows) do
    print(("  %3d    %5d      %5d        %-5s    %s"):format(
      r.frame, r.turnTimer, r.pikaCounter, tostring(r.passable),
      r.bumped and "*** BUMP ***" or ""))
  end
end

-- ==========================================================================
-- (a)+(b): turn toward the follower and hold -- which frame bumps, and the
-- pikachuCollisionCounter/turnTimer timeline for the first 12 frames
-- ==========================================================================
do
  local ow = newScenario(true)
  tick(ow, nil) -- one standing-still poll first, arming pikachuTurnArmed and
                -- player.turnArmed exactly as a real standstill would
                -- before any press (PikachuFollower.lua:537, Player.lua:91)
  local rows = {}
  for _ = 1, 12 do rows[#rows + 1] = tick(ow, "down") end
  printTimeline(rows, "(a)/(b) hold \"down\" toward the parked follower")

  local bumpFrame = firstCollisionFrame()
  print(("  first Collision cue: frame %s"):format(tostring(bumpFrame)))
  T.check(bumpFrame ~= nil, "holding into the follower rings Collision, as .collision does in Yellow")
  -- +2, not +1: frame counter includes the one idle priming poll before the
  -- held sequence starts, so the held press itself is frame 2 and the
  -- (turnWindow+1)th held poll lands on absolute frame 2 + turnWindow
  T.eq(bumpFrame, window + 2,
    "it fires on the (turnWindow+1)th HELD poll -- the same poll a real " ..
    "wall would first block on, per turn_in_place_bug415.lua's \"poll " ..
    "past the window commits the step\" case")
  -- the counter mid-turn-lock, matching the hypothesis's "goes 8 -> ~4"
  T.eq(rows[1].pikaCounter, 8, "the fresh press seeds the counter to 8")
  T.check(rows[window].pikaCounter > 0 and rows[window].pikaCounter <= 5,
    "the counter is still positive (solid) when the turn window closes")
end

-- ==========================================================================
-- (c): a SHORT TAP -- held for only 2 logic frames, then released. Does the
-- bump still fire?
-- ==========================================================================
do
  local ow = newScenario(true)
  tick(ow, nil)
  local rows = {}
  for _ = 1, 2 do rows[#rows + 1] = tick(ow, "down") end
  Input.state.down = false -- release
  for _ = 1, 10 do rows[#rows + 1] = tick(ow, nil) end
  printTimeline(rows, "(c) 2-frame tap, then release, +10 idle polls")
  local bumpFrame = firstCollisionFrame()
  print(("  first Collision cue: %s"):format(tostring(bumpFrame)))
  T.check(bumpFrame == nil,
    "a 2-frame tap releases before the turn window closes: no bump")
end

-- ==========================================================================
-- (d): hold for N frames with no release poll in between, N = 2,4,6,8,12 --
-- approximating "several logic frames drained per input poll" (the harness
-- has no separate rendered-frame axis: tests/drivers' own coroutine-per-
-- logic-step contract, and Game:update's single FixedStep call per resume,
-- mean one yield IS one logic frame here; see file header). Reports the
-- first N at which the bump fires within that many held frames.
-- ==========================================================================
do
  print("(d) held N frames, no release in between:")
  for _, n in ipairs({ 2, 4, 6, 8, 12 }) do
    local ow = newScenario(true)
    tick(ow, nil)
    local bumped = false
    for _ = 1, n do
      local r = tick(ow, "down")
      if r.bumped then bumped = true end
    end
    print(("  N=%2d  bump=%s"):format(n, tostring(bumped)))
    T.eq(bumped, n >= window + 1,
      ("N=%d matches the (turnWindow+1)-frame threshold"):format(n))
  end
end

-- ==========================================================================
-- (e) CONTROL: turning toward an empty tile -- no follower, no wall. Same
-- press, same hold length as (a); must never bump.
-- ==========================================================================
do
  local ow, player = newScenario(false)
  tick(ow, nil)
  local rows = {}
  for _ = 1, 8 do rows[#rows + 1] = tick(ow, "down") end
  printTimeline(rows, "(e) control: hold \"down\" onto open floor")
  T.check(firstCollisionFrame() == nil,
    "no follower, no wall: holding into open floor never bumps")
  T.check(player.moving == true,
    "and the turn actually resolves into a real step once the window closes")
end

GameVersion.set("red")
T.finish("pikachu block rings collision sfx")
