-- lp3_test: demo/example script for the lp3 mod (Launchpad Mini MK3 driver).
-- Requires the "lp3" mod to be enabled: SYSTEM > MODS > LP3.
--
-- The "Stop Solo Mute" button (bottom-right, x=9 y=1) cycles through three
-- interaction modes for the 8x8 grid, shown by its own colour:
--   red  : press a pad to toggle it on/off (keeps its current colour)
--   blue : press a pad to make it breathe (pulse) in its current colour
--   green: press a pad to give it a new random colour, without changing
--          whether it's off/static/breathing
-- Each pad remembers its own colour and display state (off/static/pulse), so
-- switching mode and colour independently composes as expected.
--
-- The four direction buttons (top row, arrows) trigger a wave animation
-- across the whole 8x8 grid, sweeping in the pressed direction. This is
-- mostly here as a stress test / example of lp3:refresh()'s batched SysEx
-- (updates all 64 pads at once, once per animation frame).
--
-- The logo button (top-right, x=9 y=9) just pulses as an idle "alive" light.

local lp3 = require 'lp3/lib/mod'

local PALETTE_RED = 5
local PALETTE_GREEN = 19
local PALETTE_BLUE = 45
local DEFAULT_COLOR = 21 -- arbitrary palette colour a pad gets before it's ever coloured

local MODE_TOGGLE = 1
local MODE_BREATHE = 2
local MODE_COLOR = 3
local mode_colors = {PALETTE_RED, PALETTE_BLUE, PALETTE_GREEN}

local pad
local mode = MODE_TOGGLE
local pad_state = {} -- pad_state[x][y] = {color = <palette index>, display = "off"|"static"|"pulse"}
local logo_hue = 0
local logo_metro
local wave_metro

local function init_pad_state()
  for x = 1, 8 do
    pad_state[x] = {}
    for y = 1, 8 do
      pad_state[x][y] = {color = DEFAULT_COLOR, display = "off"}
    end
  end
end

-- push a single pad's stored state to hardware (buffer only, call refresh() after)
local function apply_pad(x, y)
  local st = pad_state[x][y]
  if st.display == "off" then
    pad:led(x, y, 0)
  elseif st.display == "pulse" then
    pad:led_pulse(x, y, st.color)
  else
    pad:led(x, y, st.color)
  end
end

local function redraw_grid()
  for x = 1, 8 do
    for y = 1, 8 do apply_pad(x, y) end
  end
end

local function set_mode_led()
  pad:led(9, 1, mode_colors[mode])
  pad:refresh()
end

local function handle_grid_key(x, y, z)
  if z ~= 1 then return end
  local st = pad_state[x][y]
  if mode == MODE_TOGGLE then
    st.display = (st.display == "off") and "static" or "off"
  elseif mode == MODE_BREATHE then
    st.display = "pulse"
  elseif mode == MODE_COLOR then
    st.color = math.random(0, 127)
    if st.display == "off" then st.display = "static" end
  end
  apply_pad(x, y)
  pad:refresh()
end

-- direction: "up"/"down" sweep by row, "left"/"right" sweep by column
-- reuses a single pre-allocated metro (wave_metro) rather than allocating a
-- new one per press, since norns only has a small pool of script metros and
-- :stop() alone does not return a metro's slot to that pool.
local function start_wave(direction)
  wave_metro:stop()

  local steps = {}
  if direction == "up" then
    for y = 1, 8 do table.insert(steps, {axis = "row", index = y}) end
  elseif direction == "down" then
    for y = 8, 1, -1 do table.insert(steps, {axis = "row", index = y}) end
  elseif direction == "left" then
    for x = 8, 1, -1 do table.insert(steps, {axis = "col", index = x}) end
  elseif direction == "right" then
    for x = 1, 8 do table.insert(steps, {axis = "col", index = x}) end
  end

  local i = 0
  wave_metro.time = 0.06
  wave_metro.event = function()
    i = i + 1
    if i > #steps then
      wave_metro:stop()
      redraw_grid()
      pad:refresh()
      return
    end
    redraw_grid()
    local s = steps[i]
    if s.axis == "row" then
      for x = 1, 8 do pad:led_rgb(x, s.index, 127, 127, 127) end
    else
      for y = 1, 8 do pad:led_rgb(s.index, y, 127, 127, 127) end
    end
    pad:refresh()
  end
  wave_metro:start()
end

function init()
  pad = lp3.new()

  pad.key = function(x, y, z)
    if x == 9 and y == 1 then
      -- Stop Solo Mute: cycle interaction mode on press
      if z == 1 then
        mode = mode % 3 + 1
        set_mode_led()
      end
    elseif x == 9 and y == 9 then
      -- logo: no interaction, just the ambient pulse
    elseif y == 9 and x >= 1 and x <= 4 and z == 1 then
      -- direction arrows: up, down, left, right
      local directions = {"up", "down", "left", "right"}
      start_wave(directions[x])
    else
      handle_grid_key(x, y, z)
    end
  end

  if not pad:connect() then
    print("lp3_test: connect failed, is the Launchpad plugged in?")
    return
  end

  init_pad_state()
  pad:set_brightness(100)
  pad:all(0)

  -- decorate the extra buttons dimly, except the mode button, arrows and logo
  for x = 5, 8 do pad:led(x, 9, 2) end
  for y = 2, 8 do pad:led(9, y, 2) end
  set_mode_led()
  pad:refresh()

  logo_metro = metro.init(function()
    logo_hue = (logo_hue + 4) % 128
    pad:led_pulse(9, 9, logo_hue)
    pad:refresh()
  end, 0.3)
  logo_metro:start()

  wave_metro = metro.init(function() end, 0.06)
end

function cleanup()
  if logo_metro then metro.free(logo_metro.id) end
  if wave_metro then metro.free(wave_metro.id) end
  if pad then
    pad:all(0)
    pad:refresh()
    pad:disconnect()
  end
end
