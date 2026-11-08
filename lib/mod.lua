-- lp3 mod: makes the Launchpad Mini MK3 driver available to any script.
-- Enable from SYSTEM > MODS > LP3, then in a script:
--   local lp3 = require 'lp3/lib/mod'
--   local pad = lp3.new()
--   pad:connect()

local mod = require 'core/mods'
local lp3_lib = include('lp3/lib/lp3')

local api = {}

function api.new()
  if not mod.is_enabled('lp3') then
    print('lp3: mod not enabled -- enable it from SYSTEM > MODS > LP3')
  end
  return lp3_lib.new()
end

return api
