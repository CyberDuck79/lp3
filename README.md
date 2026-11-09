# lp3

A [norns](https://monome.org/docs/norns/) mod that gives scripts direct access to the **Novation Launchpad Mini MK3** in Programmer mode.

Most norns scripts reach a Launchpad through [midigrid](https://github.com/jaggednz/midigrid), which makes it look like a monome grid. That works for existing grid scripts, but it hides most of the hardware. lp3 talks to the Launchpad itself and gives you:

- **all 80 buttons and 81 LEDs**: the 8×8 grid, the 8 buttons of the top row, the 8 buttons of the right column, and the logo LED;
- **RGB colours**, palette colours, and the Launchpad's **built-in flash and pulse** (they run on the device, so you don't need a metro);
- **batched LED updates**: `refresh()` sends only the LEDs that changed, in a single SysEx message;
- **hotplug**: start a script before plugging the Launchpad in, or unplug it and plug it back in, and the mod connects it with its LEDs as the script drew them;
- **global brightness** and **sleep / wake**.

## Requirements

- norns 2.7 or later (mods support)
- Launchpad Mini MK3, plugged in over USB

Other Launchpads (X, Pro MK3, Mini MK2) use different SysEx headers and layouts and are not supported.

## Install

From maiden:

```
;install https://github.com/CyberDuck79/lp3
```

Then go to **SYSTEM > MODS**, enable **LP3** with E3, and restart the norns (**SYSTEM > RESTART**).

The folder must be named `lp3`: scripts load the driver with `require 'lp3/lib/mod'`. If you clone the repo by hand, clone it into `~/dust/code/lp3`.

## Quick start

```lua
local lp3 = require 'lp3/lib/mod'
local pad

function init()
  pad = lp3.new()
  pad.key = function(x, y, z)
    if z == 1 then
      pad:led(x, y, 21) -- green
    else
      pad:led(x, y, 0)  -- off
    end
    pad:refresh()
  end
  pad:connect()
end

function cleanup()
  pad:all(0)
  pad:refresh()
  pad:disconnect()
end
```

Calling `disconnect()` in `cleanup()` is good practice: it takes the Launchpad out of Programmer mode. If a script forgets it, or crashes, the mod does it for you when the script stops: it turns the LEDs off and leaves Programmer mode for every Launchpad the script left connected.

## Coordinates

Coordinates go from 1 to 9 on both axes. `y = 1` is the **bottom** row.

```
 y
 9   [91][92][93][94][95][96][97][98]  [99]   top row (CC)   + logo (LED only)
 8   [81][82][83][84][85][86][87][88]  [89]
 7   [71] .   .   .   .   .   .  [78]  [79]
 6    .                           .    [69]
 5    .        8×8 grid           .    [59]   right column (CC)
 4    .     (Note on / off)       .    [49]
 3    .                           .    [39]
 2   [21] .   .   .   .   .   .  [28]  [29]
 1   [11][12][13][14][15][16][17][18]  [19]
      1   2   3   4   5   6   7   8     9    x
```

The numbers are the MIDI note (grid) or CC (buttons) that the Launchpad sends in Programmer mode. Grid pads are `note = y * 10 + x`.

On the Launchpad Mini MK3, the top row is ↑ ↓ ← → Session, Drums, Keys, User, and the right column, top to bottom, runs from (9, 8) to (9, 1), which is Stop Solo Mute.

## API

### Module

| Call | Description |
|---|---|
| `lp3.new()` | Returns a new device object. It prints a warning if the mod is not enabled, but still works. |

### Connection

| Call | Description |
|---|---|
| `pad:connect()` | Finds the Launchpad's MIDI port, switches it to Programmer mode and starts listening. Returns `false` if the Launchpad isn't plugged in: the mod then connects it as soon as it appears. |
| `pad:disconnect()` | Leaves Programmer mode and releases the port. |
| `pad.connected` | `true` while the Launchpad is connected. |
| `pad.status = function(connected) end` | Optional. Called with `false` when the Launchpad is unplugged, and `true` when the mod connects it after waiting for it. |

If the Launchpad isn't plugged in when the script calls `connect()`, or if it is unplugged later, lp3 stops sending to it and waits. When it shows up, the mod connects it, puts it in Programmer mode, restores the brightness and sends the LED buffer, so the grid shows what the script drew in the meantime. The script doesn't need to do anything, but it shouldn't give up when `connect()` returns `false`: keep initialising and drawing as usual. A Launchpad the script disconnected itself with `disconnect()` is not reconnected.

`connect()` takes over the device's `event` and `remove` handlers. Don't open the same port with `midi.connect()` or midigrid at the same time.

### Input

| Field | Description |
|---|---|
| `pad.key = function(x, y, z) end` | Called on every press (`z = 1`) and release (`z = 0`), grid and buttons alike. |

The Launchpad Mini MK3 has no velocity sensing. `z` is always 0 or 1.

### LEDs

These calls only write to a buffer. Nothing changes on the Launchpad until you call `refresh()`.

| Call | Description |
|---|---|
| `pad:led(x, y, color)` | Static palette colour, `0`–`127` (`0` = off). |
| `pad:led_rgb(x, y, r, g, b)` | Static RGB colour, each channel `0`–`127`. |
| `pad:led_flash(x, y, color, color_b)` | Flashes between `color` and `color_b`, in sync with the MIDI clock the Launchpad receives (120 BPM by default). |
| `pad:led_pulse(x, y, color)` | Pulses (breathes) a palette colour, in sync with the clock too. |
| `pad:all(color)` | Sets all 81 LEDs to a palette colour (default `0`). |
| `pad:refresh()` | Sends the LEDs that changed since the last refresh, as one SysEx message. `pad:refresh(true)` resends every LED that has been set. |

The palette colours are listed in Novation's *Launchpad Mini MK3 Programmer's Reference Manual*. Some common values: `5` red, `9` orange, `13` yellow, `21` green, `37` cyan, `45` blue, `53` magenta, `57` pink, `3` white.

`refresh()` only sends what changed, so redrawing the whole grid from scratch every frame is cheap: unchanged LEDs cost nothing on the MIDI side. Still, batch your changes and call it once per frame rather than after every `led()` call. After a (re)connection, the next `refresh()` sends everything, since the Launchpad's state is unknown.

### Device

| Call | Description |
|---|---|
| `pad:set_brightness(v)` | Global LED brightness, `0`–`127`. |
| `pad:sleep(true / false)` | Turns all LEDs off (sleep) or back on (wake). |

## Examples

- **`lp3_test`** (in this repo): select **LP3/LP3_TEST** on the norns. Stop Solo Mute cycles between three pad modes (toggle, pulse, random colour), the arrow buttons sweep a wave across the grid, and the logo pulses through the palette.

## How it works

Novation exposes the Launchpad Mini MK3 as two ALSA ports with the same base name. Port 1 is the DAW interface. Port 2 is the standard MIDI interface, the one that accepts Programmer mode. lp3 picks the device whose name contains `Launchpad Mini MK3` and ends in `2`:

```
$ amidi -l
IO  hw:1,0,0  Launchpad Mini MK3 MIDI 1
IO  hw:1,0,1  Launchpad Mini MK3 MIDI 2
```

All other messages are SysEx with the header `F0 00 20 29 02 0D`:

| Command | Bytes |
|---|---|
| Programmer mode on / off | `0E 01` / `0E 00` |
| LED update (colourspecs) | `03 …` |
| Brightness | `08 vv` |
| Sleep / wake | `09 00` / `09 01` |

## Known limitations

- **One Launchpad at a time.** `connect()` takes the first Launchpad Mini MK3 it finds.
- **A small window remains where unplugging can crash matron.** When a MIDI device disappears, matron frees it right away, a few milliseconds before Lua hears about the removal. A write that lands inside that window crashes matron. This is a norns core issue that lp3 cannot fix from Lua. To be safe, stop the script before unplugging the Launchpad.
- To detect a Launchpad that comes back, the mod wraps norns' internal `_norns.midi.add`, because norns has no hook for new devices.
- The automatic disconnect on script stop and the automatic reconnect need the mod to be loaded, which happens at boot when it is enabled in SYSTEM > MODS, or as soon as a script calls `require 'lp3/lib/mod'`.

## License

MIT, see [LICENSE](LICENSE).
