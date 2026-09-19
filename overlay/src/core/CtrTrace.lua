-- On-device diagnostic trace for the 3DS bring-up (temporary tooling).
--
-- One line per event in trace3ds.txt: "t=<seconds> [tag] message".  No-op on
-- every other platform, so call sites can stay in place while the port
-- stabilizes and cost nothing elsewhere.  Pulled off the console over FTP.
local CtrTrace = {}

local enabled
local function isEnabled()
  if enabled == nil then
    local ok, Console = pcall(require, "src.core.Console")
    enabled = ok and Console.is3DS() and love and love.filesystem ~= nil
    if enabled then
      pcall(love.filesystem.write, "trace3ds.txt", "-- trace start --\n")
    end
  end
  return enabled
end

function CtrTrace.log(tag, msg)
  if not isEnabled() then return end
  local t = (love.timer and love.timer.getTime and love.timer.getTime()) or 0
  pcall(love.filesystem.append, "trace3ds.txt",
        ("t=%.2f [%s] %s\n"):format(t, tag, tostring(msg)))
end

return CtrTrace
