# lp3

A [norns](https://monome.org/docs/norns/) mod that gives scripts direct access to the **Novation Launchpad Mini MK3** in Programmer mode.

Most norns scripts reach a Launchpad through [midigrid](https://github.com/jaggednz/midigrid), which makes it look like a monome grid. That works for existing grid scripts, but it hides most of the hardware. lp3 talks to the Launchpad itself and gives you:

- **all 81 controls**: the 8×8 grid, the 8 buttons of the top row, the 8 buttons of the right column and the logo button;
- **RGB colours**, palette colours, and the Launchpad's **built-in flash and pulse** (they run on the device, so you don't need a metro);
- **batched LED updates**: `refresh()` sends the whole frame as a single SysEx message;
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
 9   [91][92][93][94][95][96][97][98]  [99]   top row (CC)   + logo (CC 99)
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
| `pad:connect()` | Finds the Launchpad's MIDI port, switches it to Programmer mode and starts listening. Returns `true` or `false`. |
| `pad:disconnect()` | Leaves Programmer mode and releases the port. |
| `pad.connected` | `true` after a successful `connect()`. |

`connect()` takes over the device's `event` handler. Don't open the same port with `midi.connect()` or midigrid at the same time.

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
| `pad:all(color)` | Sets all 81 controls to a palette colour (default `0`). |
| `pad:refresh()` | Sends the whole buffer as one SysEx message. |

The palette colours are listed in Novation's *Launchpad Mini MK3 Programmer's Reference Manual*. Some common values: `5` red, `9` orange, `13` yellow, `21` green, `37` cyan, `45` blue, `53` magenta, `57` pink, `3` white.

`refresh()` resends every control that has ever been set, not only the ones that changed. Batch your changes and call it once per frame rather than after every `led()` call.

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

- **No hotplug.** If you unplug the Launchpad and plug it back in, the script has to call `connect()` again.
- **One Launchpad at a time.** `connect()` takes the first Launchpad Mini MK3 it finds.
- **Unplugging while LEDs are being updated can crash matron.** ALSA fails an assertion when norns writes to a device that has just disappeared. Stop the script before unplugging the Launchpad.
- The automatic disconnect on script stop needs the mod to be loaded, which happens at boot when it is enabled in SYSTEM > MODS, or as soon as a script calls `require 'lp3/lib/mod'`.

## License

MIT, see [LICENSE](LICENSE).
