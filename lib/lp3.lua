--- lp3: direct MIDI driver for the Novation Launchpad Mini MK3 (Programmer mode)
-- Talks to the "MIDI In/Out" port directly, bypassing midigrid, to expose
-- RGB LEDs, the 16 extra CC buttons, brightness and sleep/wake.
--
-- Coordinate space: 9x9.
--   x = 1..8, y = 1..8  -> main 8x8 grid (Note on/off)
--   x = 9,    y = 1..8  -> right-side column buttons (CC 19,29,...,89)
--   x = 1..8, y = 9     -> top row buttons (CC 91..98)
--   x = 9,    y = 9     -> logo, LED only (index 99), never sends key()

local lp3 = {}
lp3.__index = lp3

local SYSEX_HEADER = {0xF0, 0x00, 0x20, 0x29, 0x02, 0x0D}

local TOP_ROW_CC = {91, 92, 93, 94, 95, 96, 97, 98} -- x=1..8, y=9
local RIGHT_COL_CC = {19, 29, 39, 49, 59, 69, 79, 89} -- x=9, y=1..8
local TOP_RIGHT_CC = 99 -- x=9, y=9

function lp3.new()
  local d = setmetatable({}, lp3)
  d.dev = nil
  d.port_id = nil
  d.connected = false
  d.waiting = false -- true while connect() waits for the Launchpad (not plugged in, or unplugged)
  d.brightness = 127
  d.buffer = {} -- buffer[x][y] = {type, ...} pending state, for refresh()
  d.sent = {}   -- sent[x][y] = colourspec last sent to the hardware
  d.key = nil   -- callback: key(x, y, z)
  d.status = nil -- optional callback: status(connected), on unplug / (re)plug
  for x = 1, 9 do
    d.buffer[x] = {}
    d.sent[x] = {}
    for y = 1, 9 do
      d.buffer[x][y] = {type = 0, index = 0} -- off
    end
  end
  return d
end

-- note number for main grid pad (x=1..8 -> col 1..8, y=1..8 -> row 1..8, row 1 = bottom)
local function grid_note(x, y)
  return y * 10 + x
end

-- resolve (x,y) -> {kind="note"|"cc", value=<note or cc>}
local function resolve_target(x, y)
  if x >= 1 and x <= 8 and y >= 1 and y <= 8 then
    return "note", grid_note(x, y)
  elseif x == 9 and y >= 1 and y <= 8 then
    return "cc", RIGHT_COL_CC[y]
  elseif y == 9 and x >= 1 and x <= 8 then
    return "cc", TOP_ROW_CC[x]
  elseif x == 9 and y == 9 then
    return "cc", TOP_RIGHT_CC
  end
  return nil
end

-- reverse lookup: note/cc -> x,y. built once.
local NOTE_TO_XY = {}
local CC_TO_XY = {}
for y = 1, 8 do
  for x = 1, 8 do
    NOTE_TO_XY[grid_note(x, y)] = {x, y}
  end
end
for x = 1, 8 do CC_TO_XY[TOP_ROW_CC[x]] = {x, 9} end
for y = 1, 8 do CC_TO_XY[RIGHT_COL_CC[y]] = {9, y} end
CC_TO_XY[TOP_RIGHT_CC] = {9, 9}

-- the Launchpad went away (unplugged). Drop every reference to the device:
-- matron frees the underlying C device, and writing through a stale
-- reference would crash it. The LED buffer is kept for the reconnect.
function lp3:_lost()
  if not self.dev then return end
  print("lp3: Launchpad was unplugged, waiting for it to come back")
  self.dev = nil
  self.port_id = nil
  self.connected = false
  self.waiting = true
  if self.status then self.status(false) end
end

-- true while the device we connected to is still registered with norns.
-- Normally the device's remove callback has already called _lost(); this
-- is the safety net if a send happens before that.
function lp3:_alive()
  if not self.dev then return false end
  if midi.devices[self.port_id] ~= self.dev then
    self:_lost()
    return false
  end
  return true
end

function lp3:_send_sysex(bytes)
  if not self:_alive() then return end
  local msg = {}
  for _, b in ipairs(SYSEX_HEADER) do table.insert(msg, b) end
  for _, b in ipairs(bytes) do table.insert(msg, b) end
  table.insert(msg, 0xF7)
  self.dev:send(msg)
end

function lp3:_set_programmer_mode(on)
  self:_send_sysex({0x0E, on and 0x01 or 0x00})
end

-- Novation exposes the Launchpad Mini MK3 as two ALSA ports sharing the same
-- base name ("Launchpad Mini MK3"): port 1 is the DAW interface, port 2 is
-- the standard MIDI interface (the one that speaks Programmer mode).
function lp3:_find_port()
  for id, d in pairs(midi.devices) do
    if d.name and string.find(d.name, "Launchpad Mini MK3") and string.find(d.name, "2$") then
      return id
    end
  end
  return nil
end

function lp3:_handle_midi(data)
  local status = data[1]
  local channel = status & 0x0F
  local kind = status & 0xF0
  local d1, d2 = data[2], data[3]

  if kind == 0x90 or kind == 0x80 then -- note on/off
    local xy = NOTE_TO_XY[d1]
    if xy then
      local z = (kind == 0x90 and d2 > 0) and 1 or 0
      if self.key then self.key(xy[1], xy[2], z) end
    end
  elseif kind == 0xB0 then -- CC (extra buttons)
    local xy = CC_TO_XY[d1]
    if xy then
      local z = (d2 > 0) and 1 or 0
      if self.key then self.key(xy[1], xy[2], z) end
    end
  end
end

--- connect to the Launchpad. Returns false if it isn't plugged in; the mod
-- then connects it as soon as it appears.
function lp3:connect()
  local id = self:_find_port()
  if not id then
    print("lp3: no Launchpad Mini MK3 found, waiting for it to be plugged in")
    self.waiting = true
    return false
  end
  self.port_id = id
  self.dev = midi.devices[id]
  self.dev.event = function(data) self:_handle_midi(data) end
  self.dev.remove = function() self:_lost() end
  self:_forget_sent()
  self:_set_programmer_mode(true)
  self.connected = true
  self.waiting = false
  print("lp3: connected on port " .. id)
  return true
end

-- called by the mod whenever norns adds a MIDI device. If we are waiting for
-- the Launchpad and it is here, take it over and send the LED buffer.
function lp3:_reconnect()
  if not self.waiting or not self:_find_port() then return end
  if self:connect() then
    if self.brightness ~= 127 then self:set_brightness(self.brightness) end
    self:refresh()
    if self.status then self.status(true) end
  end
end

function lp3:disconnect()
  if self.connected then
    self:_set_programmer_mode(false)
  end
  if self.dev then
    self.dev.event = nil
    self.dev.remove = nil
  end
  self.connected = false
  self.waiting = false
  self.dev = nil
  self.port_id = nil
end

--- set a pad/button to a static palette color (0-127)
function lp3:led(x, y, color)
  local kind, target = resolve_target(x, y)
  if not kind then return end
  self.buffer[x][y] = {type = 0, target = target, kind = kind, color = color}
end

--- set a pad/button to full RGB (each channel 0-127)
function lp3:led_rgb(x, y, r, g, b)
  local kind, target = resolve_target(x, y)
  if not kind then return end
  self.buffer[x][y] = {type = 3, target = target, kind = kind, r = r, g = g, b = b}
end

--- set a pad/button to flash between current color and a second palette color
function lp3:led_flash(x, y, color, color_b)
  local kind, target = resolve_target(x, y)
  if not kind then return end
  self.buffer[x][y] = {type = 1, target = target, kind = kind, color = color, color_b = color_b}
end

--- set a pad/button to pulse a palette color
function lp3:led_pulse(x, y, color)
  local kind, target = resolve_target(x, y)
  if not kind then return end
  self.buffer[x][y] = {type = 2, target = target, kind = kind, color = color}
end

--- set every pad/button off
function lp3:all(color)
  color = color or 0
  for x = 1, 9 do
    for y = 1, 9 do
      if resolve_target(x, y) then
        self:led(x, y, color)
      end
    end
  end
end

-- the hardware state is unknown (new connection): resend everything next time
function lp3:_forget_sent()
  for x = 1, 9 do self.sent[x] = {} end
end

-- colourspec bytes for a buffer cell, without the LED index
local function cell_spec(cell)
  if cell.type == 3 then
    return {3, cell.r, cell.g, cell.b}
  elseif cell.type == 1 then
    return {1, cell.color_b or 0, cell.color}
  elseif cell.type == 2 then
    return {2, cell.color}
  else
    return {0, cell.color or 0}
  end
end

local function same_spec(a, b)
  if not a or #a ~= #b then return false end
  for i = 1, #a do
    if a[i] ~= b[i] then return false end
  end
  return true
end

--- send the LEDs that changed since the last refresh, in a single SysEx.
-- pass true to resend every LED that has been set, changed or not.
function lp3:refresh(full)
  if not self:_alive() then return end
  local specs = {0x03}
  for x = 1, 9 do
    for y = 1, 9 do
      local cell = self.buffer[x][y]
      if cell.target then
        local spec = cell_spec(cell)
        if full or not same_spec(self.sent[x][y], spec) then
          table.insert(specs, spec[1])
          table.insert(specs, cell.target)
          for i = 2, #spec do table.insert(specs, spec[i]) end
          self.sent[x][y] = spec
        end
      end
    end
  end
  if #specs > 1 then
    self:_send_sysex(specs)
  end
end

--- global brightness, 0-127
function lp3:set_brightness(v)
  self.brightness = v
  self:_send_sysex({0x08, v})
end

--- put all LEDs to sleep (true) or wake them (false)
function lp3:sleep(on)
  self:_send_sysex({0x09, on and 0x00 or 0x01})
end

return lp3
