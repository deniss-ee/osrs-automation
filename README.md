# OSRS Automation

AutoHotkey v2 automation scripts for Old School RuneScape, built around a small
set of shared detection/click/wait primitives rather than one-off scripts per
bot.

This is **v7** — a ground-up rewrite of the original codebase, now promoted to
the repo root. The old codebase (v6) is frozen in [`legacy/`](legacy/) as a
working fallback; see [Legacy](#legacy) below.

## Layout

```
Lib\      shared building blocks - #Include Lib\v7.ahk to get all of them
  v7.ahk    umbrella include
  Core.ahk  stop flag, interruptible Pause/WaitUntil, Say/LogLine, GameActive,
            Opt() opts-unpacker, POLL_MS_DEFAULT
  Find.ahk  color-block + image detection (FindFilledBlock, FindImage,
            AcquireClosestInBox, SearchZone mode switch, WatchIndicator, ...)
  Act.ahk   ClickAt, PressKey (async modifier release)
  Grid.ahk  GridSpec/GridCorner/GridCenter/GridCellRegion (inventory/bank/menu addressing)
  Inv.ahk   INV_GRID/BANK_GRID, SlotFull/SlotProbe/DropSlot, TakeSnapshot/HasChanged
  Steps.ahk composites: FindAndClickBlock/Image, TrackAndClick, DepositAllToBank,
            GatherBankLoop, ClearAllInstances, TravelToPoint, RunRestockPlan, ...
  Bot.ahk   InstallBotHarness - shared F5/F6/F12/probe/extra-hotkey wiring
micro\    standalone calibration/diagnostic scripts, one per primitive/composite -
          each is F5 to run, F6 to stop, Esc to exit, with its own log.
          All 26 are confirmed live against this user's setup.
Bots\     real bots built on top of Lib\ (currently: woodcutting.ahk)
logs\     one timestamped log file per micro/bot run
Images\   reference PNGs used by image-based detection
legacy\   the old (v6) codebase - frozen, not developed further, kept
          runnable as a fallback (see below)
```

## Running a bot or micro script

Every script follows the same pattern:
- **F5** starts it
- **F6** requests a stop - takes effect within ~40ms, even mid-search or mid-wait
- **Esc** exits immediately (`micro\` scripts) / **F12** exits immediately (`Bots\`
  scripts - some bots send a real Esc keypress as an in-game action, so Esc is
  left free for that)
- **F8** probes/diagnostics on bots/micros that expose one

Open the script, edit the `EDIT THESE FOR YOUR SETUP` block at the top
(colors, regions, timeouts) to match your own screen/setup, then run it.
Every run appends to its own file in `logs\`.

Syntax-check any script without running it:
```
& "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut /validate <path>
```
(run from PowerShell, not Git Bash - Git Bash mangles the `/validate` switch).

## Status

- All 26 shared primitives/composites in `Lib\` are calibrated and confirmed
  live against this user's setup (see `micro\` for the standalone test for
  each one) — the rewrite's Step 2 is complete.
- `Bots\woodcutting.ahk` is confirmed working end-to-end (Step 3, in progress).
- Remaining bots to (re)build in v7: crafting, smithing, seller, sudoku,
  autoclicker, motherlode2 — see `PROGRESS.md` for the current build order
  and every standard/lesson learned along the way.

**`PROGRESS.md`** is the authoritative resume doc for this codebase — read it
first in any new session before touching `Lib\` or `Bots\`.

## Legacy

`legacy\` holds the original (v6) codebase exactly as it was before the v7
rewrite: 7 functional bots (woodcutting, motherlode2, crafting, smithing,
sudoku, autoclicker, seller) on their own `Lib\`/`micro\`/`Images\`/`logs\`.
It is **frozen** - not developed further, kept only as a known-working
fallback while v7 (this root) catches up feature-for-feature.
`legacy\TEMPLATES.md` has the original plain-English step breakdown of every
planned bot. `legacy\prompts\` holds the session-starter prompts that drove
the v6→v7 rewrite, kept for historical context.
