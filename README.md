# OSRS Automation

AutoHotkey v2 automation scripts for Old School RuneScape, built around a small
set of shared detection/click/wait primitives rather than one-off scripts per
bot.

This is **v8** — a streamlined refactor of v7, now promoted to the repo root.
All 12 of its micro test scripts are live-confirmed, and its first real bot
(`Bots\woodcutting.ahk`) is built and live-confirmed working. Every earlier
codebase is frozen under [`archive/`](archive/); see [Archive](#archive) below.

v8's three headline changes over v7:
1. **Click-jitter hard guarantee** — every click is built from a
   `ClickTarget(x, y, w, h)` and jittered strictly inside that cell. No
   sentinel, no flat fallback, no size-less click path anywhere.
2. **Unified target specs** — one object shape for a color block
   (`{colors, tol, w, h}`) or an image (`{path, tol, transColor, w, h}`),
   dispatched by `FindTarget`/`WaitForTarget`/`WaitForTargetGone`.
3. **Fail-safe engine** (`Lib\Run.ahk`, new) — `RunSteps` retries each failed
   step once (a full fresh attempt) before a clean FAILED stop that leaves the
   script responsive; `StepLoop` wraps it with cycle limits and session pacing.

## Layout

```
Lib\      shared building blocks - #Include Lib\v8.ahk to get all of them
  v8.ahk       umbrella include (Core → Bot → Act → Find → Steps → Run → Grid → Inv → Session)
  Core.ahk     stop flag, interruptible Pause/WaitUntil, Say/LogLine, Opt(),
               LOG_DIR/IMAGES_DIR path globals
  Bot.ahk      InstallBotHarness - uniform F5/F6/F12/probe/extra-hotkey wiring
  Act.ahk      HumanGlide/HumanMove (minimum-jerk cursor glide), ClickTarget/
               JitterInCell/ClickAt (the click-jitter hard guarantee), PressKey
  Find.ahk     block + image detection, unified FindTarget spec dispatch,
               state watchers, screen calibration constants
  Steps.ahk    composites: FindAndClick, TrackAndClick, DepositAllToBank,
               ClearAllInstances, TravelToPoint, RightClickMenuItem,
               ClickUntilCondition, VerifySlotsAndDrop, RunRestockPlan
  Run.ahk      RunSteps/StepLoop - the fail-safe retry engine
  Grid.ahk     GridSpec/GridCorner/GridCenter/GridCellRegion
  Inv.ahk      INV_GRID/BANK_GRID, SlotFull/SlotProbe/DropSlot
  Session.ahk  MaybeTakeBreak/NewSessionTimer - session pacing
micro\    12 standalone test scripts, one per idea - each is F5 to run,
          F6 to stop, F12 to exit, with its own log. ALL 12 live-confirmed.
Bots\     real bots built on top of Lib\ - woodcutting.ahk (live-confirmed)
Tools\    one-off calibration scripts (record-movement.ahk +
          analyze-movement.ahk - record real mouse movement, compute
          real speed/curvature statistics for tuning Act.ahk's constants)
logs\     one log file per micro/bot/tool run
Images\   reference PNGs used by image-based detection (this tree resolves
          only its own Images folder, never archive's)
archive\  every earlier codebase, frozen (see below)
```

## Running a bot or micro script

Every script follows the same pattern:
- **F5** starts it
- **F6** requests a stop - takes effect within ~40ms, even mid-search,
  mid-glide, or mid-break
- **F12** exits immediately
- **F8** probes/diagnostics on scripts that expose one (some micros add
  F7/F9/F10/F11 - see each file's header)

Open the script, edit the `EDIT THESE FOR YOUR TEST` block at the top
(colors, regions, timeouts) to match your own screen/setup, then run it.
Every run appends to its own file in `logs\`.

Syntax-check any script without running it:
```
& "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut /validate <path>
```
(run from PowerShell, not Git Bash - Git Bash mangles the `/validate` switch).

## Status

- All 12 micros are **live-confirmed** against a real RuneLite session
  (2026-08-01), including the two most load-bearing: the click-jitter
  scatter proof (micro 03) and the fail-safe engine (micro 10).
- `Bots\woodcutting.ahk` is **live-confirmed working** - the first real v8
  bot. Building it grew the Lib substantially (idle cursor wandering via a
  new `WanderNear` primitive, wander-aware waits threaded through
  `WaitUntil`/`WaitForTarget`/`FindAndClick`/`DepositAllToBank`,
  `DepositAllToBank` ctrl-per-click and search-delay support). **The next
  session's job is auditing and standardizing this growth** before it
  becomes the template for future bots - see `PROGRESS.md`'s Next steps.
- Known open items: micro 08's menu-row image asset needs a fresh recapture
  before `RightClickMenuItem` is used in a real bot; `BANK_GRID` rows beyond
  row 1 are unmeasured; wander-config naming is inconsistent between
  `TrackAndClick` and `DepositAllToBank` (audit item).

**`PROGRESS.md`** is the authoritative resume doc for this codebase — read it
first in any new session before touching `Lib\` or `Bots\`.

## Archive

`archive\` holds every earlier codebase, frozen:
- `archive\v7\` — the immediate predecessor (26 micros + working
  woodcutting bot, all previously live-confirmed). The proven fallback, and
  the reference for calibration values when building v8 bots.
- `archive\legacy\` — the original v6 codebase (7 functional bots).
  `archive\legacy\TEMPLATES.md` has the original plain-English step breakdown
  of every planned bot.
- `archive\v10\` — an unrelated third-party toolkit download, kept only for
  reference; nothing in it is used.
