# Changelog

## 2026-11-09

- **`connect()` waits for a Launchpad that isn't plugged in yet.** It still returns `false`, but the mod connects the Launchpad as soon as it appears, the same way it reconnects one that was unplugged, and calls `pad.status(true)`. A `disconnect()` stops the wait.
  - *Impact on scripts:* don't stop `init()` when `connect()` returns `false`. Keep initialising and drawing: everything goes to the LED buffer, and the Launchpad shows it when it is plugged in. `lp3_test` now works this way.

- **`refresh()` only sends the LEDs that changed** since the last refresh. Redrawing the whole grid every frame no longer costs anything for LEDs that did not move: one changed pad is 11 bytes instead of about 250 for a full frame. `refresh(true)` resends every LED that has been set. After a connection or a reconnection, the next `refresh()` sends everything.
  - *Impact on scripts:* none for scripts that only talk to the Launchpad through lp3. If a script also sends its own LED messages to the Launchpad, lp3 no longer knows what is displayed: call `refresh(true)` afterwards.
- README: the logo is an LED, not a button (80 buttons, 81 LEDs).

## 2026-11-08

- **Automatic reconnect.** When a connected Launchpad is unplugged, lp3 stops sending to it and waits. When it comes back, the mod reconnects it, restores Programmer mode and brightness, and resends the LED buffer. New optional callback `pad.status(connected)`, called with `false` on unplug and `true` on reconnect. `pad.connected` follows the real state.
  - *Impact on scripts:* no need to call `connect()` again after a replug. Keep drawing while the Launchpad is away: LED calls still update the buffer, so the Launchpad shows the current state when it comes back.
- **No more writes to an unplugged Launchpad.** Writing to a MIDI device that norns has removed crashed matron (black screen, keys dead). lp3 now checks the device before every send. A very short window remains in norns itself, see *Known limitations* in the README.
- **Cleanup when a script stops.** A `script_post_cleanup` hook turns the LEDs off and leaves Programmer mode for every Launchpad the script left connected, for example after a crash or without a `cleanup()`.
- `disconnect()` also releases the device's `event` handler, so `pad.key` stops firing after a disconnect.
- First published version: driver, mod, README, MIT license and the `lp3_test` example.
