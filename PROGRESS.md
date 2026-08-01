# v8 PROGRESS

Read this first in any new session. **v8 was promoted to the repo root on 2026-08-01** (`Lib\`, `micro\`, `Bots\`, `Images\`, `logs\` — no more `v8\` prefix). Everything that came before lives frozen under `archive\`: `archive\v7\` (the previous root — proven, runnable fallback), `archive\legacy\` (v6), `archive\v10\` (untracked third-party toolkit, nothing portable in it). The full design plan is at `C:\Users\link\.claude\plans\i-have-a-project-happy-brook.md`.

## Where things stand (2026-08-01)

**ALL 12 MICROS ARE LIVE-CONFIRMED** — built, audited against v7's real source, `/validate`-clean, and confirmed against a real RuneLite session in order 01 → 12 on 2026-08-01. The two most load-bearing (03 click-jitter hard-guarantee scatter test, 10 fail-safe engine) passed solidly: every scatter run 50/50 in-cell, and the retry/FAILED/session-pacing engine behaved exactly per spec including a real-world double-failure → clean FAILED → script-still-responsive sequence in micro 12's dress rehearsal.

`Bots\` is EMPTY on purpose — the next step is writing `Bots\woodcutting.ahk` fresh (see Next steps).

### Bugs found and fixed during live-confirm (all invisible to `/validate`)

Four real code bugs, all caught live, all fixed and re-confirmed:

1. **`micro\04-find-block.ahk`** — local `region` collided case-insensitively with the global config `REGION` (AHK v2 names are case-insensitive; the auto-local shadowed the global, so `REGION.x` read the unassigned local). Renamed the local `clampedRegion`.
2. **`Lib\Steps.ahk` `FindAndClick`** — same collision class, worse scope: local `clickTarget` shadowed the Lib function `ClickTarget`, breaking every FindAndClick call. Renamed `resolvedClickTarget`.
3. **`Lib\Core.ahk` `IMAGES_DIR`** — was `A_ScriptDir "\..\..\Images"` (two levels up), silently resolving to the OLD root's `Images\` instead of this tree's own. Fixed to `"\..\Images"` (matches `LOG_DIR`'s one-level pattern).
4. **`Lib\Run.ahk` `RunSteps`** — `step.run()` dot-call syntax implicitly passes `step` as a hidden first argument to a stored closure ("Too many parameters"). Fixed by extracting to a local first (`runFn := step.run`, then `runFn()`) — the same pattern `ClickUntilCondition` already used. Checked the whole Lib: this was the only occurrence.

**Lesson for future AHK v2 work:** local-vs-global case-insensitive name collisions and stored-closure dot-calls both pass `/validate` clean and only explode at runtime. When adding any Lib function or config global, grep for case-insensitive name matches; when calling a closure stored on an object, always extract it to a local first.

### Asset/calibration fixes

- `Images\` (this tree's own) now holds: `air-rune.png` (78×20), `gold-bar.png` (72×64, copied from v7), `deposit-bank.png` (72×72, copied from v7), `li_bank-deposit-box.png` (332×30). Several micros' declared image w/h and `transColor` were corrected to match the real files (declared size drives the click-center math — it must match the actual pixels).
- **`BANK_GRID` (`Lib\Inv.ahk`)** — no longer a full placeholder: origin/cellW/cellH/gapX are v7's real live-measured values (`625, 203, 72, 64, 24`), bounded to 8 real columns (v7 modeled it as one 999-column row, which defeated `GridCorner`'s range check). **Rows beyond 1 are still unmeasured** — live-measure before trusting any bank slot index > 8.

### Open items

- **Micro 08's F5 menu-item image match is unresolved** — `li_bank-deposit-box.png` (a real menu-row capture) would not match live even full-screen at high tol, with and without a `0x5D5447` background wildcard. OSRS context menus render as a translucent overlay blended with the 3D scene behind them, so the background pixels differ per capture. Recapture the asset fresh (or diagnose further) before relying on `RightClickMenuItem` in a real bot. F7/F8/F9 of that micro (ClickUntilCondition, TravelToPoint pin+search) confirmed fine.
- `BANK_GRID` rows > 1 unmeasured (above).

## Why v8 (recap)

A full v7 audit found: (a) two holes in the click-jitter guarantee - a pinned marker click could fall through to a flat, unbounded ±40px offset; (b) zero retry anywhere - one missed click killed the whole session; (c) naming drift (`blockW/blockH` vs `w/h` vs `imageW/imageH`) and some dead code. User requirements: hard-guarantee every coordinate click has an offset bounded by its target's own cell, add a fail-safe (fail → one fresh retry → FAILED clean stop, script stays open), and shrink 29 near-duplicate micros down to ~12 one-per-idea.

## The three unifications

1. **Click-jitter hard guarantee** (`Lib\Act.ahk`) - `ClickAt` no longer accepts a bare x/y. Every click is built from `ClickTarget(x, y, w, h)` (center-based; throws if w/h < 1), and `JitterInCell` is mathematically bounded to stay inside that cell (per-axis triangular, `CLICK_JITTER_FRAC` of each dimension, `CLICK_JITTER_MAX_PX` as an absolute ceiling only). There is no sentinel, no flat fallback, no size-less click path anywhere in v8. `ClickAt(target, opts)` also took on a `button` param ("left"/"right"), so `RightClickMenuItem` no longer needs its own copy of the click prologue. NOTE: `ClickTarget`'s x/y is a CENTER; corner-measured inputs (standard #2) get converted once via `CenterX`/`CenterY` or by the composite that found them.
2. **Unified target-spec objects** (`Lib\Find.ahk`) - one shape everywhere: `{colors, tol, w, h}` for a block, `{path, tol, transColor, w, h}` for an image. `FindTarget`/`WaitForTarget`/`WaitForTargetGone` dispatch on which fields are present. Every composite takes `opts.target`/`opts.marker`/`opts.deposit` etc. as one of these specs, never loose prefixed fields.
3. **The fail-safe engine** (`Lib\Run.ahk`, entirely new) - `RunSteps(steps, opts)` runs a named sequence once, retrying each step (a full fresh attempt, not a resume) up to `retries` times (default 1) before returning false. `StepLoop(opts)` wraps that in a cycle loop with session pacing at the seam - this **replaces v7's `GatherBankLoop`**. A step's own return value is usually the completion indicator (`TrackAndClick`'s `until`, `DepositAllToBank`'s `confirmCondition`); an optional `done` closure is the extra layer when a composite can report success before the world has actually settled.

## Standards carried from v7 (unchanged)

Primitives take `(requiredPositional..., opts)`; composites are opts-object; scalar-or-`[min,max]` rolled fresh at point of use (`RandTri`); `Pause()`/`WaitUntil` are the only sleep mechanism (40ms chunks, throws `BotStopped`, never caught in Lib); validate via `AutoHotkey64.exe /ErrorStdOut /validate` from **PowerShell** (never Git Bash — it mangles the switch); one Lib function/file built per micro, in lockstep; `v8.ahk`'s `#Include` chain grows one line at a time.

## Standards amended in v8

- **`Bot.ahk`'s `WrapHandler`** wraps every handler uniformly (run, probe, extraHotkeys) - resets `g_StopRequested`, catches `BotStopped`, reports DONE/FAILED/STOPPED. No v8 handler needs to know about the stop flag or `BotStopped` at all. (Confirmed live, micro 01 — including the stale-flag regression check v7's extraHotkeys failed.)
- **`RunWrapped`/`WrapHandler` captures and reports the run function's return value** — a FAILED run is visibly distinct from a clean stop.
- **`SearchZone` only has `"full"` and `"area"` modes** (v7's `"quadrant"`/`"fixed"` dropped per explicit user decision).
- **`FindAndClick` replaces v7's three-function split** (`WaitThenClick` + `FindAndClickBlock` + `FindAndClickImage`).
- **`GatherBankLoop` is gone, replaced by `Run.ahk`'s `StepLoop`.**
- **`GridCellRegion` fixed** (inclusive `x + cellW - 1`; `VerifySlotsAndDrop` now calls the one definition).
- **`RegionAround` clamps all four edges to the screen** (v7 only clamped x1/y1). Confirmed live via micro 04's deliberately-overflowing edge region.
- **`RunRestockPlan` takes opts and returns true.**
- **Dropped as dead code**: `TargetLock.IsLost`/`missingTicksToUnlock`, `ACQUIRE_PADDING_SMALL/LARGE`, `GameZoneQuadrant`.

## File map (all paths root-relative after the 2026-08-01 promotion)

- `Lib\Core.ahk` - `Pause`/`WaitUntil`/`Opt`/`Say`/`LogLine`/`BotStopped`; `LOG_DIR`/`IMAGES_DIR` load-time globals (both one level up from the running script: `..\logs`, `..\Images`).
- `Lib\Bot.ahk` - `InstallBotHarness`, uniform `WrapHandler`.
- `Lib\Act.ahk` - movement (`HumanGlide`/`HumanMove`/`GlideStepDelay`/`RandTri`/`MinJerk`/`TremorWeight`, unchanged from v7's proven minimum-jerk glide, bow 0.04-0.08) + click (`ClickTarget`/`JitterInCell`/`ClickAt`, the hard guarantee) + `PressKey`.
- `Lib\Find.ahk` - block search (`FindFilledBlock`/`AcquireClosestInBox`/`FindAnyFilledBlock`/`SearchZone`), image search (`FindImage`/`WaitForImage`/`WaitForImageGone`), unified dispatch (`FindTarget`/`WaitForTarget`/`WaitForTargetGone`), state watchers (`WatchIndicator`/`BlockAtPoint`/`TakeSnapshot`/`HasChanged`), calibration constants (`CHAR_X/Y`, `GAME_ZONE_*`, `BANK_DEPOSIT_IMAGE_*`, `DEPOSIT_BOX_IMAGE_*`).
- `Lib\Steps.ahk` - `FindAndClick`, `ClearAllInstances`, `PickupAppeared`, `RightClickMenuItem`, `ClickUntilCondition`, `TravelToPoint`, `VerifySlotsAndDrop`, `RunRestockPlan`, `TargetLock`, `TrackAndClick`, `DepositAllToBank`.
- `Lib\Run.ahk` - `RunSteps`, `StepLoop` (the fail-safe engine).
- `Lib\Grid.ahk` - `GridSpec`/`GridCorner`/`GridCenter`/`GridCellRegion`.
- `Lib\Inv.ahk` - `INV_GRID`, `BANK_GRID` (row 1 real, rows>1 unmeasured), `SlotFull`/`SlotProbe`/`SlotCenter`/`DropSlot`/etc.
- `Lib\Session.ahk` - `MaybeTakeBreak`, `NewSessionTimer` (verbatim from v7), consumed by `StepLoop`.
- `Lib\v8.ahk` - umbrella include, order: Core → Bot → Act → Find → Steps → Run → Grid → Inv → Session.
- `Images\` - `air-rune.png`, `gold-bar.png`, `deposit-bank.png`, `li_bank-deposit-box.png` (this tree resolves ONLY its own Images folder — never archive's).
- `Bots\` - EMPTY on purpose; woodcutting is the next thing to write.
- `archive\v7\` - the complete previous root (Lib/micro/Bots/Images/logs/Tools/PROGRESS.md), frozen, runnable fallback. `archive\legacy\` - v6. `archive\v10\` - third-party toolkit, ignore.

## Micro list (ALL live-confirmed 2026-08-01)

| # | Micro | Absorbs (v7 #s) | Live result |
|---|---|---|---|
| 01 | harness-stop | 01, 02, 26 | confirmed incl. stale-flag F7 regression |
| 02 | human-move | 27, 29 | err=0px every move; bow verified via path trace |
| 03 | click-jitter (hard-guarantee proof) | 08, 09 | every scatter run 50/50 in-cell |
| 04 | find-block | 03, 04, 05 | confirmed; found+fixed the REGION/region bug |
| 05 | find-image | 07, 16 | both spec branches through one FindTarget |
| 06 | indicators | 06, 14, 15 | present/absent/arrival-tol/snapshot all confirmed |
| 07 | find-and-click (pin-jitter fix proof) | 11, 17, 22 | pin clicks landed at pin, 150-instance clear sweep, pickup confirmed via pixel-diff |
| 08 | menu-travel | 10, 20, 23 | F7/F8/F9 confirmed; F5 menu-item asset match OPEN (see Open items) |
| 09 | grid-inventory | 12, 13, 18, 19 | grid/occupancy/drop/verify-walk/restock confirmed; BANK_GRID row 1 real |
| 10 | run-steps (fail-safe engine proof) | NEW + 28 | retry/FAILED/retries:0/done-timeout/pacing all per spec |
| 11 | track-and-click | 21 | acquire/drift-reject/stability/reacquire cycle confirmed live |
| 12 | deposit-loop + dress rehearsal | 24, 25 | deposit confirmed ×3; sabotaged retry AND real-world double-failure → clean FAILED, script alive |

## Next steps

1. **Write `Bots\woodcutting.ahk` fresh** - spec-object config, `StepLoop` with `STEP_RETRIES := 1`, same proven v7 calibration values (colors/tol/block sizes/timeouts/bank marker/deposit asset - check `archive\v7\Bots\woodcutting.ahk` for the exact numbers). Test order: bounded run (`maxCycles 2`) → provoke one real bank-step failure to watch a live retry → a second to watch a clean FAILED with the script still responding → session pacing (TAKE_BREAKS/BOUND_SESSION) last, short test values before ever trusting the real 1-2h defaults.
2. When a bot needs `RightClickMenuItem`: recapture the menu-row asset fresh first (open item above).
3. If a bot needs bank slots beyond row 1: live-measure `BANK_GRID`'s second row.
