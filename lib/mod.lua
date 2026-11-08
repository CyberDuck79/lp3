-- lp3 mod: makes the Launchpad Mini MK3 driver available to any script.
-- Enable from SYSTEM > MODS > LP3, then in a script:
--   local lp3 = require 'lp3/lib/mod'
--   local pad = lp3.new()
--   pad:connect()
--
-- When a script stops, the mod clears and disconnects every Launchpad the
-- script left connected, so the device never stays in Programmer mode with
-- a frozen frame (e.g. after a crash or a missing cleanup()).
--
-- When a connected Launchpad is unplugged and plugged back in, the mod
-- reconnects it and restores its LEDs.

local mod = require 'core/mods'
local lp3_lib = include('lp3/lib/lp3')

local api = {}

-- devices handed out to the current script. Weak keys: we never keep a
-- device alive on our own.
local devices = setmetatable({}, {__mode = 'k'})

function api.new()
  if not mod.is_enabled('lp3') then
    print('lp3: mod not enabled -- enable it from SYSTEM > MODS > LP3')
  end
  local d = lp3_lib.new()
  devices[d] = true
  return d
end

-- runs after the script's own cleanup() and before norns closes MIDI
-- handlers, so the port is still usable here.
mod.hook.register('script_post_cleanup', 'lp3', function()
  for d in pairs(devices) do
    if d.connected then
      print('lp3: script left the Launchpad connected, disconnecting')
      d:all(0)
      d:refresh()
      d:disconnect()
    end
  end
  devices = setmetatable({}, {__mode = 'k'})
end)

-- norns has no hook for new devices, and midi.add belongs to the script
-- (reset on every script stop), so wrap the core entry point instead.
-- The original is kept on _norns.midi so reloading this file never wraps
-- twice.
_norns.midi.lp3_core_add = _norns.midi.lp3_core_add or _norns.midi.add
_norns.midi.add = function(id, name, dev)
  _norns.midi.lp3_core_add(id, name, dev)
  for d in pairs(devices) do
    local ok, err = pcall(d._reconnect, d)
    if not ok then print('lp3: reconnect failed: ' .. tostring(err)) end
  end
end

return api
