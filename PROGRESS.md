# v8 PROGRESS

Read this first in any new session. **v8 was promoted to the repo root on 2026-08-01** (`Lib\`, `micro\`, `Bots\`, `Tools\`, `Images\`, `logs\` — no more `v8\` prefix). Everything that came before lives frozen under `archive\`: `archive\v7\` (the previous root — proven, runnable fallback, and the calibration reference for bot values), `archive\legacy\` (v6), `archive\v10\` (untracked third-party toolkit, nothing portable in it).

## Where things stand (end of session, 2026-08-01)

**All 12 micros are live-confirmed.** **`Bots\woodcutting.ahk` is built and live-confirmed working** — the user's own words: "the script has been tested." This was the first real v8 bot, and it drove a lot of real Lib growth (see below) beyond what the original 12-micro plan anticipated.

**The next session's job is an audit + standardization pass** — not new features. Building `woodcutting.ahk` happened under live iterative tuning (the user testing, reporting back, tuning again, repeatedly), which is exactly how this project has always worked — but it means several Lib additions below were shaped by fast back-and-forth rather than the project's usual "one micro per new primitive" discipline. Before any *other* bot gets built on top of this Lib, it needs a deliberate pass to standardize naming, remove duplication, and decide what's genuinely general-purpose vs. woodcutting-specific. See "Next steps."

### Bugs found and fixed during the 12-micro live-confirm pass (all invisible to `/validate`)

1. **`micro\04-find-block.ahk`** — local `region` collided case-insensitively with the global config `REGION` (AHK v2 names are case-insensitive; the auto-local shadowed the global, so `REGION.x` read the unassigned local). Renamed the local `clampedRegion`.
2. **`Lib\Steps.ahk` `FindAndClick`** — same collision class, worse scope: local `clickTarget` shadowed the Lib function `ClickTarget`, breaking every `FindAndClick` call. Renamed `resolvedClickTarget`.
3. **`Lib\Core.ahk` `IMAGES_DIR`** — was `A_ScriptDir "\..\..\Images"` (two levels up), silently resolving to the OLD root's `Images\` instead of this tree's own. Fixed to `"\..\Images"` (matches `LOG_DIR`'s one-level pattern).
4. **`Lib\Run.ahk` `RunSteps`** — `step.run()` dot-call syntax implicitly passes `step` as a hidden first argument to a stored closure ("Too many parameters"). Fixed by extracting to a local first (`runFn := step.run`, then `runFn()`).

**Lesson for future AHK v2 work:** local-vs-global case-insensitive name collisions and stored-closure dot-calls both pass `/validate` clean and only explode at runtime. When adding any Lib function or config global, grep for case-insensitive name matches; when calling a closure stored on an object, always extract it to a local first.

### Lib growth while building `woodcutting.ahk` (all this session, all opt-in/backward-compatible)

This is the real content of the next audit. In build order:

1. **`DepositAllToBank`** (`Steps.ahk`) — `markerCtrl`/`depositCtrl` (independent ctrl per click; the bank marker is ctrl-clicked to run there, the deposit button is a UI click and isn't), `depositSearchDelayMs` (settle gap before the deposit-button search starts, letting the bank UI actually render).
2. **`TrackAndClick`** (`Steps.ahk`) — `acquireDelayChance`/`acquireDelayMs`: a chance-gated pause right before each fresh acquisition search (models "took a moment to spot the next tree").
3. **Bug found live:** `CONFIRM_EMPTY_SLOT` — the bot initially checked inventory slot 1 to confirm a deposit emptied the inventory; slot 1 sits at the grid edge next to UI chrome and intermittently false-read as "full." Switched to slot 28 (the last slot — already the established convention for "is inventory full" everywhere else in the project) for both the full-trigger and the empty-confirm.
4. **Click-settle floor** — `TrackAndClick`'s `clickSettleMs`/`postClickSettleMs` and `DepositAllToBank`'s `settleMs` default to 100ms/0ms in Lib; the bot floors these to 300ms via its own `CLICK_SETTLE_MS`/`POST_CLICK_SETTLE_MS` config.
5. **`WanderNear`** (`Act.ahk`, entirely new primitive) — idle cursor wandering. Went through several real redesigns, each driven by a live bug or live feedback:
   - v1 (small-radius wander around the tracked point via an axis-aligned `avoidBox`) had a real geometry bug: the exclusion box was larger than the wander radius could ever reach, so every candidate got rejected and it silently did nothing. Rewritten to a circular exclusion (`avoidRadiusPx`) with a radius range mathematically guaranteed to clear it.
   - A second real bug: `RandTri()` always divides by 2, which in AHK v2 always produces a float, even from integer bounds. That float flowed into `GlideStepDelay`'s `//` (floor division, which AHK v2 requires strict integers for) and crashed. Fixed by `Round()`-ing every `RandTri()` result destined for a step-delay value.
   - Redesigned again per live feedback into its final shape: **loops** (2-5 waypoints traced around a randomly-placed/sized circle via `Cos`/`Sin` — the round/sweeping look) plus **hops** (the jump from one loop's last point to the next loop's fresh center, landing anywhere on screen — the long-distance moves), both composed from real `HumanGlide` legs.
   - Speed was tuned five times total: once against real recorded data (see `Tools\` below), then four more rounds purely on live "still feels slow" feedback, each cutting the slow-tail ceiling further. Final state and full tuning history are documented directly in `Act.ahk`'s comment above `WanderNear`'s `GlideTo` helper — worth reading before touching those numbers again.
6. **`HumanGlide`/`HumanMove`** (`Act.ahk`) — gained optional `stepDelayMinMs`/`stepDelayMaxMs` and `pxPerStep`/`maxSteps` overrides (all default to the existing `HUMANMOVE_*` globals, so every real click glide is unchanged). Needed because `WanderNear`'s full-screen legs are much longer than any real click distance, and the default 30-step ceiling (tuned for click-range distances) looked visibly choppy at full-screen range.
7. **`WaitUntil`** (`Core.ahk` — the single most-used primitive in the whole Lib) — gained an optional 4th arg, `wanderOpts` (default `""` = off), which triggers `WanderNear` mid-wait on a chance/cadence. Deliberately NOT wired into every wait by default — most `WaitUntil` calls are short mechanical settles or "about to act again very soon" windows where wandering would be wrong; only a caller that explicitly knows a wait is a genuine "nothing to do" stretch passes it.
8. **`WaitForTarget`** (`Find.ahk`) and **`FindAndClick`** (`Steps.ahk`) — both thread an optional `wander` opt straight through to `WaitUntil`.
9. **`DepositAllToBank`** — gained `wanderChance`/`wanderCheckMs`/`wanderDurationMs`, applied to **all three** of its waits (marker search, deposit-button search, post-deposit confirm).
10. **`Tools\record-movement.ahk` + `Tools\analyze-movement.ahk`** (new `Tools\` folder) — a real mouse-movement recorder (samples `MouseGetPos()` on a fixed interval to a CSV) and a statistics analyzer (per-tick speed distribution, movement-segment curvature vs. straight-line distance, segment duration/distance/speed, pause durations). Used once, live, against a real 94s/5962-sample recording (avg speed 1.325 px/ms, avg curvature 2.86× straight-line) to calibrate `WanderNear`'s initial speed — deliberately reports raw statistics only, no auto-generated "suggested constants" (that would be false precision from a formula, not a human judgment call).

### Asset/calibration fixes (from the earlier 12-micro pass, still current)

- `Images\` (this tree's own) holds: `air-rune.png` (78×20), `gold-bar.png` (72×64), `deposit-bank.png` (72×72), `li_bank-deposit-box.png` (332×30).
- **`BANK_GRID` (`Lib\Inv.ahk`)** — origin/cellW/cellH/gapX are v7's real live-measured values (`625, 203, 72, 64, 24`), bounded to 8 real columns. **Rows beyond 1 are still unmeasured.**

### Open items

1. **The audit itself** (see Next steps) — naming is currently inconsistent between the two composites that got wander support: `TrackAndClick` uses `idleWanderChance`/`idleWanderCheckMs`/`idleWanderDurationMs`, `DepositAllToBank` uses `wanderChance`/`wanderCheckMs`/`wanderDurationMs` (no `idle` prefix) for the conceptually identical feature. `woodcutting.ahk` currently passes the same `IDLE_WANDER_*` bot-level constants into both separately rather than through one shared concept.
2. **Micro 08's F5 menu-item image match is unresolved** — `li_bank-deposit-box.png` would not match live even full-screen at high tol, with or without a background wildcard (OSRS context menus are translucent overlays blended with the scene behind them). Recapture the asset fresh before relying on `RightClickMenuItem` in a real bot.
3. **`BANK_GRID` rows > 1 unmeasured** — live-measure before trusting any bank slot index > 8.
4. **`WanderNear` has no dedicated micro** — it was built live inside `woodcutting.ahk` under iteration, skipping the project's usual "one micro per new Lib primitive, live-confirmed before it's used in a bot" discipline. Worth deciding during the audit whether it needs one retroactively.

## Next steps

1. **Audit + standardize pass** (the actual next task, per explicit user instruction 2026-08-01) — NOT new features:
   - Unify the `idleWander*` vs `wander*` naming across `TrackAndClick`/`DepositAllToBank` into one consistent shape (likely a single shared opts object, e.g. `wander: {chance, checkMs, durationMs}`, that any composite's `opts` can accept, instead of each one redeclaring its own trio of params).
   - Review every Lib addition listed above for redundancy and decide what's genuinely general-purpose (belongs in `Lib\` permanently) vs. woodcutting-specific (should stay local to that bot).
   - Decide whether `WanderNear` needs a retroactive micro (open item 4).
   - Update every touched Lib file's header/opts-doc comment to reflect the final, audited shape — several are currently accurate-but-messy from being edited five times in one session.
   - Re-validate everything and re-confirm the touched micros (02, 05, 07, 11, 12) live one more time after any renaming, since renaming opts is a breaking change for any caller still using the old names.
2. **Once audited, this becomes the template for future bots.** `archive\v7\Bots\` has the original 7-bot roster (crafting, smithing, sudoku, mining/motherlode2, seller, autoclicker, woodcutting) for reference — every future v8 bot should be able to reuse `TrackAndClick`/`DepositAllToBank`/`StepLoop`/`WanderNear` exactly as `woodcutting.ahk` does, with no further Lib surprises needed.
3. Recapture the menu-row asset before any bot uses `RightClickMenuItem` (open item 2).
4. Live-measure `BANK_GRID`'s second row before a bot needs bank slots beyond 8 (open item 3).

## Why v8 (recap)

A full v7 audit found: (a) two holes in the click-jitter guarantee - a pinned marker click could fall through to a flat, unbounded ±40px offset; (b) zero retry anywhere - one missed click killed the whole session; (c) naming drift (`blockW/blockH` vs `w/h` vs `imageW/imageH`) and some dead code. User requirements: hard-guarantee every coordinate click has an offset bounded by its target's own cell, add a fail-safe (fail → one fresh retry → FAILED clean stop, script stays open), and shrink 29 near-duplicate micros down to ~12 one-per-idea.

## The three unifications

1. **Click-jitter hard guarantee** (`Lib\Act.ahk`) - `ClickAt` no longer accepts a bare x/y. Every click is built from `ClickTarget(x, y, w, h)` (center-based; throws if w/h < 1), and `JitterInCell` is mathematically bounded to stay inside that cell (per-axis triangular, `CLICK_JITTER_FRAC` of each dimension, `CLICK_JITTER_MAX_PX` as an absolute ceiling only). NOTE: `ClickTarget`'s x/y is a CENTER; corner-measured inputs (standard #2) get converted once via `CenterX`/`CenterY` or by the composite that found them.
2. **Unified target-spec objects** (`Lib\Find.ahk`) - one shape everywhere: `{colors, tol, w, h}` for a block, `{path, tol, transColor, w, h}` for an image. `FindTarget`/`WaitForTarget`/`WaitForTargetGone` dispatch on which fields are present.
3. **The fail-safe engine** (`Lib\Run.ahk`) - `RunSteps(steps, opts)` runs a named sequence once, retrying each step up to `retries` times (default 1) before returning false. `StepLoop(opts)` wraps that in a cycle loop with session pacing at the seam - this **replaces v7's `GatherBankLoop`**.

## Standards carried from v7 (unchanged)

Primitives take `(requiredPositional..., opts)`; composites are opts-object; scalar-or-`[min,max]` rolled fresh at point of use (`RandTri`, though NOTE: `RandTri`'s `/2` always returns a float in AHK v2 — `Round()` it before feeding an integer-strict context, see open item 5 above); `Pause()`/`WaitUntil` are the only sleep mechanism (throws `BotStopped`, never caught in Lib); validate via `AutoHotkey64.exe /ErrorStdOut /validate` from **PowerShell** (never Git Bash); one Lib function/file built per micro, in lockstep (though see the audit note above — this discipline slipped somewhat during `woodcutting.ahk`'s live tuning).

## Standards amended in v8

- **`Bot.ahk`'s `WrapHandler`** wraps every handler uniformly - resets `g_StopRequested`, catches `BotStopped`, reports DONE/FAILED/STOPPED.
- **`SearchZone` only has `"full"` and `"area"` modes.**
- **`FindAndClick` replaces v7's three-function split.**
- **`GatherBankLoop` is gone, replaced by `Run.ahk`'s `StepLoop`.**
- **`RegionAround` clamps all four edges to the screen.**
- **Dropped as dead code**: `TargetLock.IsLost`/`missingTicksToUnlock`, `ACQUIRE_PADDING_SMALL/LARGE`, `GameZoneQuadrant`.

## File map (all paths root-relative)

- `Lib\Core.ahk` - `Pause`/`WaitUntil` (now with optional wander hook)/`Opt`/`Say`/`LogLine`/`BotStopped`; `LOG_DIR`/`IMAGES_DIR` load-time globals.
- `Lib\Bot.ahk` - `InstallBotHarness`, uniform `WrapHandler`.
- `Lib\Act.ahk` - movement (`HumanGlide`/`HumanMove`, both now with optional pacing/step-count overrides; `GlideStepDelay`/`RandTri`/`MinJerk`/`TremorWeight`) + click (`ClickTarget`/`JitterInCell`/`ClickAt`) + `PressKey` + **`WanderNear`** (new - idle cursor wandering, see Lib growth above).
- `Lib\Find.ahk` - block search, image search, unified dispatch (`FindTarget`/`WaitForTarget`, now wander-capable/`WaitForTargetGone`), state watchers, calibration constants.
- `Lib\Steps.ahk` - `FindAndClick` (now wander-capable), `ClearAllInstances`, `PickupAppeared`, `RightClickMenuItem`, `ClickUntilCondition`, `TravelToPoint`, `VerifySlotsAndDrop`, `RunRestockPlan`, `TargetLock`, `TrackAndClick` (now with `acquireDelay*`/`idleWander*`), `DepositAllToBank` (now with `markerCtrl`/`depositCtrl`/`depositSearchDelayMs`/`wander*`).
- `Lib\Run.ahk` - `RunSteps`, `StepLoop`.
- `Lib\Grid.ahk` - `GridSpec`/`GridCorner`/`GridCenter`/`GridCellRegion`.
- `Lib\Inv.ahk` - `INV_GRID`, `BANK_GRID` (row 1 real, rows>1 unmeasured), `SlotFull`/`SlotProbe`/`SlotCenter`/`DropSlot`/etc.
- `Lib\Session.ahk` - `MaybeTakeBreak`, `NewSessionTimer`.
- `Lib\v8.ahk` - umbrella include, order: Core → Bot → Act → Find → Steps → Run → Grid → Inv → Session.
- `Images\` - `air-rune.png`, `gold-bar.png`, `deposit-bank.png`, `li_bank-deposit-box.png`.
- `Bots\woodcutting.ahk` - **live-confirmed working.** Chops either of 2 tree colors (69×69, `0x00FF00`/`0x00B809`) near `CHAR_X/Y`, ctrl-clicks (running), banks via a 43×43 orange (`0xFF980A`) marker + `deposit-bank.png` button (marker ctrl-clicked, deposit button not), confirms via last-slot-empty. Two independent probabilistic breaks (~1/3 chance each, after-inventory-full and after-banking) plus full-screen idle-wandering during every genuine wait (tree-tracking idle, all three bank waits).
- `Tools\` - **new.** `record-movement.ahk` + `analyze-movement.ahk`, real-movement calibration scripts (see Lib growth above).
- `archive\v7\` - the complete previous root, frozen, runnable fallback + calibration reference. `archive\legacy\` - v6. `archive\v10\` - third-party toolkit, ignore.

## Micro list (all live-confirmed 2026-08-01)

| # | Micro | Live result |
|---|---|---|
| 01 | harness-stop | confirmed incl. stale-flag F7 regression |
| 02 | human-move | err=0px every move; bow verified via path trace (re-confirm after HumanGlide's opts additions) |
| 03 | click-jitter (hard-guarantee proof) | every scatter run 50/50 in-cell |
| 04 | find-block | confirmed; found+fixed the REGION/region bug |
| 05 | find-image | both spec branches through one FindTarget (re-confirm after WaitForTarget's wander threading) |
| 06 | indicators | present/absent/arrival-tol/snapshot all confirmed |
| 07 | find-and-click (pin-jitter fix proof) | confirmed (re-confirm after FindAndClick's wander threading) |
| 08 | menu-travel | F7/F8/F9 confirmed; F5 menu-item asset match OPEN |
| 09 | grid-inventory | confirmed; BANK_GRID row 1 real |
| 10 | run-steps (fail-safe engine proof) | retry/FAILED/retries:0/done-timeout/pacing all per spec |
| 11 | track-and-click | confirmed (re-confirm after acquireDelay/idleWander additions) |
| 12 | deposit-loop + dress rehearsal | confirmed incl. real-world double-failure → clean FAILED (re-confirm after ctrl-split/wander additions) |
