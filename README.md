# OSRS Automation

AutoHotkey v2 automation scripts for Old School RuneScape, built around a small
set of shared detection/click/wait primitives rather than one-off scripts per
bot.

## Layout

```
Lib\      shared building blocks - #Include Lib\v6.ahk to get all of them
  v6.ahk    umbrella include
  Core.ahk  stop flag, interruptible Pause/WaitUntil, Say/LogLine, GameActive
  Find.ahk  color-block + image detection (FindFilledBlock, FindImage, ...)
  Act.ahk   ClickAt (settled click, optional force-run/Ctrl-hold)
  Inv.ahk   inventory layout + slot addressing, pixel-box snapshot/diff
  Steps.ahk composites: TrackAndClick (acquire/track/depleted loop), PickupAppeared
micro\    standalone calibration/diagnostic scripts, one per primitive -
          each is F5 to run, F6 to stop, Esc to exit, with its own log
Bots\     real bots built on top of Lib\ (currently: woodcutting.ahk)
Config\   per-bot config (not yet used - bots currently hardcode their own
          calibration constants; see each bot's own EDIT-THESE block)
logs\     one timestamped log file per micro/bot run
Images\   reference PNGs used by image-based detection
```

## Running a bot or micro script

Every script follows the same pattern:
- **F5** starts it
- **F6** requests a stop - takes effect within ~40ms, even mid-search or mid-wait
- **Esc** exits immediately

Open the script, edit the `EDIT THESE FOR YOUR TEST` block at the top
(colors, regions, timeouts) to match your own screen/setup, then run it.
Every run appends to its own file in `logs\`.

## Status

- All shared primitives in `Lib\` are calibrated and confirmed in-game (see
  `micro\` for the standalone test for each one).
- `Bots\woodcutting.ahk` is confirmed working end-to-end.
- Motherlode is the next bot being built.

`TEMPLATES.md` has a plain-English step breakdown of every planned bot.
