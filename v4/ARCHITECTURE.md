# v4 Framework Reference — Helpers & Repeated Patterns

_Written 2026-07-09, after the Motherlode Mine bot's full mine→bank→return loop was completed and verified live. Purpose: a lookup reference for building the next bot, so patterns are reused instead of reinvented._

## Layer map

```
Core/         Engine, EngineContext, FailSafe, Phase       — state machine + shared context + timeout tripwire
Timing/       Waiter, TimingProfile                         — the only place Sleep() is called
Detection/    ColorSearch, TargetLock, Telemetry,
              StaticAnchor, DynamicTarget                   — finding things on screen
Actions/      Click, Humanizer                               — moving the mouse / clicking
Interfaces/   Inventory, Bank, Walk                          — bot-facing wrappers over Detection+Telemetry
Config/       Config                                         — typed .ini loading + schema validation
Diagnostics/  Logger, WindowFocus, Overlay                   — file log, focus guard, on-screen status
Bots/<Name>/  <name>.ahk                                     — entry point + all Phase classes for one bot
config/       <name>.ini                                     — that bot's own config, isolated from legacy
```

Legacy (`lib/`, `scripts/`, `config/` at repo root) is read-only reference material — never modified, only mined for behavior to reimplement cleanly.

## Core state machine

- **`Phase`** (base class): every phase has a `.name`; `Run(ctx)` returns the next phase's name. Returning the same name = "stay in this phase, tick again next cycle."
- **`Engine`**: owns `Map(name -> Phase)` + `Map(name -> timeoutMs)`. `Tick()` (on a `SetTimer`) is busy-guarded (`_busy` flag skips re-entrant ticks), checks `FailSafe.HasPhaseTimedOut()` before running, calls `phase.Run(ctx)`, and calls `ctx.failsafe.EnterPhase(...)` whenever the returned name differs from the current one. `AddPhase(phase, timeoutMs)` registers a phase with its per-phase timeout (0 = unlimited).
- **`EngineContext`**: the one state bag passed to every `Run(ctx)`. Holds `config`, `logger`, `clicker`, `failsafe`, `waiter`, `timing`, `windowFocus`, `overlay`, `inventory`, `bank`, `engine` (set post-construction so a phase can call `ctx.engine.Stop(reason)`), and a free-form `_state` Map for scratch values via `ctx.Get(key, default)` / `ctx.Set(key, value)`. `ctx.Log(text)` fans out to both `logger` and `overlay`.
- **`FailSafe`**: two independent tripwires — a per-phase timeout (reset via `ResetPhaseTimer(ctx)` on real progress, not every tick) and a consecutive-failure budget (`RecordFailure`/`RecordSuccess`/`HasExceededFailureBudget`, currently unused by Motherlode but available).

## Timing (the delay chokepoint)

- **Rule**: `Sleep()` is called in exactly one place in the entire framework — `Waiter.After(profile, key)`. No phase, no helper, ever calls `Sleep` directly.
- **`TimingProfile`**: `Map(key -> {baseMs, jitterPercent?})`, built by `Config.Load()` from a bot's `timingSchema`. `Has`/`BaseMs`/`JitterPercent`.
- **`Waiter.After(profile, key)`**: throws if the key isn't defined (no silent zero-delay fallback); applies an injected jitter function (`(baseMs, jitterPercent) => ms`, usually `Humanizer.Jitter`) then sleeps.
- **`Waiter.ForMs(ms)`**: explicit-duration escape hatch for library-level polling intervals that are a poll *rate*, not a bot-tunable action delay (e.g. `ImageAnchor.WaitFor`'s loop uses a named key via the caller, not this).
- **AHK v2 gotcha**: `this._someFn(a, b)` where `_someFn` holds a plain function (not a real method) is parsed as a method call, silently injecting `this` as a hidden extra arg → "Too many parameters" error. Fix: assign to a local first (`fn := this._someFn; fn(a, b)`).

## Detection primitives

- **`ColorSearch.FindFilledBlock(x1,y1,x2,y2,color,tol,reqW,reqH,&cx,&cy,scanBottomUp)`**: iterative (non-recursive, stack-based) search for a solid `reqW x reqH` block of `color`. Verifies via `VerifyBlock`'s 5-point cross-check (75% of requested size, anti-aliasing-safe). `scanBottomUp` reverses scan order for targets better found from the bottom edge (verification direction flips too). Returns the **verified block's own center**, clamped to the search region's bounds — not the full overlay blob's bounding-box center.
- **`ColorSearch.ColorClose(c1, c2, tol)`** / **`IsColorAt(x,y,color,tol)`**: per-channel RGB tolerance check; the primitive everything else is built from.
- **`TargetLock(stableTicksRequired, moveTolerancePx, missingTicksToUnlock=1)`**: stability debounce. `Observe(found,x,y,&outX,&outY)` always writes the latest real position when found (never freezes); `IsStable()` is a separate counter of consecutive in-tolerance ticks, used only to gate click cadence, never to stop tracking a drifting target. `IsLost()` flags "missing too long, re-acquire." `Reset()` clears both counters — call this whenever a phase (re-)acquires a fresh target, and on every per-cycle reset.
- **`StaticAnchor.ImageAnchor(region, imagePath, imageW, imageH, options)`**: `Find(&x,&y)` wraps `ImageSearch`, converting the returned top-left to a center point using caller-supplied width/height (AHK can't query a PNG's own size). `WaitFor(waiter, profile, pollKey, timeoutMs, &x, &y)` polls `Find` via `Waiter.After` between attempts, bounded by `timeoutMs`.
- **`StaticAnchor.FixedPointAnchor(x, y)`**: trivial anchor for a known/calibrated point clicked without any search — lets a phase treat "click a fixed coordinate" and "click wherever this image/color is" through the same `Find`/`WaitFor` contract.
- **`DynamicTarget.ColorBlockTarget(region, color, tolerance, reqW, reqH, lock)`**: wraps `ColorSearch.FindFilledBlock` + a `TargetLock` behind the same `Find(&x,&y)` contract, plus `IsStable()`/`IsLost()`/`Reset()`/`Retarget(region,color)`. Motherlode's phases currently inline this pattern by hand rather than using this class directly — worth using `ColorBlockTarget` directly in the next bot instead of re-inlining the acquire/track shape.
- **`NearestColorTarget`**: stub, picks the nearest of multiple matches to a reference point — not yet implemented (`_FindRawBlock` throws).

## Telemetry (boolean gates)

All expose `IsSet() => bool`, so a phase never cares which strategy backs a gate:
- **`SlotGate(slotIndex, tolerance, inventory, offsets?)`**: true if any of 4 sampled offsets inside the slot no longer matches `InventoryColors.EMPTY` (`0x3F3629`, measured once, session-invariant).
- **`NotGate(gate)`**: inverts.
- **`AndGate([gates])`**: true only if every wrapped gate is set — used for Motherlode's "truly full" check (slot 28 AND slot 27, since a lone gem in 28 isn't hoppered and shouldn't count as full).
- **`OrGate([gates])`**: true if any wrapped gate is set — used for "sack gave us something" (slot 2 OR slot 12, since a gem can land anywhere).
- **`SlotSignatureGate`**: stub for "item transformed" detection (raw→cooked) via snapshot-then-diff — not yet implemented.

**Gate composition pattern**: build individual `SlotGate`s, wrap in `AndGate`/`OrGate`/`NotGate` as needed, attach to `Inventory` via `SetFullGate`/`SetEmptyGate`/`SetSackGate`. This composition happens once at wiring time, in the bot's entry-point file, not inside phase logic.

## Actions

- **`Clicker.MoveTo(centerX,centerY,width=0,height=0,&targetX,&targetY)`**: applies `Humanizer.Offset` spatial jitter, moves the mouse, returns the actual target point via out-params (so a caller inserting a settle delay before `Press()` clicks the *same* point that was moved to — critical, since a delay-then-recompute pattern causes stale-coordinate clicks). No `Sleep`.
- **`Clicker.Press(button="Left")`**: fires the click at the current mouse position. Deliberately not named `Click` — a method sharing a name with an AHK builtin it calls internally resolves to self-recursion.
- **`Clicker.ClickAt(...)`** / **`ClickAtWithCtrl(...)`**: convenience wrappers with no settle delay — only for callers that genuinely don't need one. Anywhere a settle delay matters, call `MoveTo` then `ctx.waiter.After(...)` then `Press()` directly, as every Motherlode phase's private `_Click(ctx,x,y)` helper does.
- **Force-run pattern**: `if runMode: Send("{Ctrl down}")` before the click, `ctx.waiter.After(ctx.timing, "ctrlHoldSettle")` + `Send("{Ctrl up}")` after — repeated verbatim in every phase's `_Click` helper in `motherlode.ahk`. A candidate for hoisting into `Clicker.ClickAtWithCtrl` properly (with settle-delay support) in the next bot instead of copy-pasting per phase.
- **`Humanizer(enabled, maxClickOffsetPx, maxDelayJitterMs)`**: pure policy object, no timing role. `Offset` returns bounded random spatial jitter (0,0 when disabled). `Jitter(baseMs, jitterPercent)` returns baseMs ± bounded/floored jitter — this is what gets injected into `Waiter`'s constructor as its jitter function.

## Interfaces (bot-facing wrappers)

- **`Inventory(layout, fullGate?, emptyGate?, sackGate?)`**: `layout = {firstX, firstY, cols, rows, slotW, slotH, gapX, gapY}` measured from slot 1's **top-left corner** (not center) — keeps calibration numbers consistent. `SlotCenter(slotIndex, &x, &y)` does 1-based row-major index → screen center math. `IsFull()`/`IsEmpty()`/`HasSackItems()` just delegate to the attached gates — gates are attached post-construction via setters (`SetFullGate` etc.) to avoid a constructor cycle (gates need `SlotCenter`, which needs the `Inventory` to exist first).
- **`Bank(chestAnchor, depositAllAnchor, clicker)`**: `OpenChest(&x,&y)` finds+clicks the chest/booth anchor; `DepositAll(waiter, profile, pollKey, timeoutMs)` waits for the deposit anchor then clicks it. `WithdrawSlot`/`WithdrawPlan` are stubs. **Note**: Motherlode's `DepositBankPhase` currently inlines its own bank flow by hand rather than using this class — `CURRENT_STATE.md` flags Motherlode as "the legacy outlier that inlines" and says `Bank.ahk` should be used instead. Worth revisiting if a shared bank flow is needed for the next bot.
- **`Walk(waypoints, clicker)`** / **`Waypoint(clickX, clickY, arrivalAnchor)`**: generalizes the returnMine1/returnMine2 hand-rolled-stage-integer pattern into an ordered waypoint list — `ClickCurrent()` clicks the active waypoint, `CheckArrival(&x,&y)` checks its anchor and auto-advances, `IsComplete()` when all waypoints are done. **Motherlode's `ReturnMine1Phase`/`ReturnMine2Phase` do NOT use this class** — they hand-roll an internal `ctx.Get("return2Stage", 1)` integer stage machine instead, exactly the pattern `Walk` was built to replace. Strongly worth using `Walk`+`Waypoint` directly for any multi-waypoint traversal in the next bot instead of re-deriving a stage int.

## Config

- **`Config(iniPath, schema, timingSchema)`**: `schema` = `Map(key -> {section, type})` for plain values (`"int"|"float"|"color"|"str"`); `timingSchema` = `Map(timingKey -> {section, baseMsKey, jitterPercentKey?})` for `Waiter`-consumed delays. `Load()` reads every declared key **once**, collects **all** missing keys before throwing (one error listing everything, not one-at-a-time), and builds `this.timing` (a `TimingProfile`) as a side effect. `Get(key)` reads a plain value.
- **Absolute rule**: every pause/delay/coordinate/color/threshold is `.ini`-backed; nothing hardcoded in phase code. The one sanctioned exception is `Inventory`'s pixel-grid layout (`firstX/firstY/cols/rows/slotW/slotH/gapX/gapY`) — a fixed property of one client window, not a gameplay tunable, so it's a hardcoded `Map` in the bot's entry-point file rather than an `.ini` key (matches legacy's own treatment of `Grid.ahk` constants).

## Diagnostics

- **`Logger`**: file-backed log (`v4/logs/<bot>-debug.log`), isolated from legacy's own log files.
- **`WindowFocus(winTitle="ahk_exe RuneLite.exe")`**: `IsActive()` guards every phase's `Run` — `if ctx.windowFocus != "" && !ctx.windowFocus.IsActive(): return <same phase name>`, so a lost-focus window never fires a click. Repeated as the very first check in every Motherlode phase's `Run(ctx)`.
- **`Overlay(maxLines, x, y)`**: rolling on-screen `ToolTip` log of the last N lines — purely cosmetic/diagnostic, fed by `ctx.Log`.

## Repeated phase-authoring patterns (the actual "helpers" to reuse)

1. **Window-focus guard**: first line of every `Run(ctx)`.
   ```
   if (ctx.windowFocus != "" && !ctx.windowFocus.IsActive())
       return this.name
   ```
2. **Acquire/Track two-mode shape** (`MinePhase`, `ClearRedPhase`, `ClearYellowPhase`): a phase-local `ctx.Get("<x>HasTarget", false)` flag branches between `_Acquire(ctx)` (full-region search, locks a target + resets `TargetLock` on success) and `_Track(ctx)` (narrowed re-search around last known position, feeds `TargetLock.Observe`, clicks only per stability + cooldown rules). Losing the target resets the flag back to acquire mode.
3. **One-time settle delay via a scratch flag**: `if (!ctx.Get("xDelayApplied", false)) { ctx.waiter.After(...); ctx.Set("xDelayApplied", true) }` — used everywhere a phase needs to wait once upon first entering a state, not every tick. This is the fix pattern for the recurring "instant click right after a fresh detection" bug class that showed up four separate times this session.
4. **Delay-before-search, not delay-after-search-before-click**: when a settle delay and a coordinate search both need to happen, the delay must come first — searching, then sleeping, then clicking stale pre-sleep coordinates was the root cause of the `DepositBankPhase` stale-click bug.
5. **Non-blocking cooldown check**: `if ((A_TickCount - lastClickTime) > cooldownMs) { click; lastClickTime := A_TickCount }` — never a blocking `Sleep` for cadence, always a tick-driven timestamp comparison.
6. **Bounded indefinite wait with a `ctx.engine.Stop(...)` failsafe**: track a `xWaitStartedAt` timestamp on first entry, compare against a configured timeout every tick, log + `ctx.engine.Stop(reason)` (never throw, never loop forever) if exceeded.
7. **`ResetForNewCycle()` per phase + a shared `nextCyclePhases` array**: every phase that holds cross-cycle state (a `TargetLock`, or scratch timestamps not already covered by the two central reset points) implements `ResetForNewCycle()`. Two places call it on every phase in the shared array: the inventory-full transition in the "start of loop" phase, and the final phase's completion (which also resets literally all scratch state and hands off back to the loop's start). This is the mechanism that makes a second full cycle behave identically to the first.
8. **`_Click(ctx, x, y)` per-phase private helper**: `MoveTo` → `ctx.waiter.After(ctx.timing, "clickSettle")` → `Press()`, wrapped in `Send("{Ctrl down/up}")` + `ctrlHoldSettle` when `runMode` is on. Identical body copy-pasted into every phase class in `motherlode.ahk` — a real candidate to hoist into `Clicker` itself (e.g. `Clicker.ClickAtSettled(ctx, x, y, runMode)`) for the next bot, rather than re-copying per phase.
9. **Engine wiring order**: downstream phases must be constructed *before* an upstream phase whose constructor needs to receive them (e.g. `MinePhase` needs the full `nextCyclePhases` array, so every other phase is built first and pushed into that array incrementally).
10. **Per-phase-group timeout keys**: don't share one `phaseTimeoutX` across phase groups whose internal wait-failsafes have materially different magnitudes — the engine's generic phase timeout can race ahead of and mask a phase's own more specific internal timeout message. Motherlode uses four separate timeout keys (`phaseTimeoutMine`, `phaseTimeoutBank`, `phaseTimeoutSack`, `phaseTimeoutReturn`) for exactly this reason.

## Known stubs / not-yet-implemented (forward-looking scaffolding, confirmed intentional)

- `Telemetry.SlotSignatureGate` (snapshot-then-diff detection)
- `DynamicTarget.NearestColorTarget._FindRawBlock`
- `Interfaces.Bank.WithdrawSlot` / `WithdrawPlan`
- `Timing/Clock.ahk`, `Actions/KeyAction.ahk` (unused stub files per `CURRENT_STATE.md`, not read in this pass — check before reuse)

## Files NOT yet using the "right" abstraction (worth fixing when writing the next bot)

- Motherlode's `ReturnMine1Phase`/`ReturnMine2Phase` hand-roll a waypoint stage machine instead of using `Walk`/`Waypoint`.
- Motherlode's `DepositBankPhase` inlines its own bank-chest/deposit-all flow instead of using `Interfaces/Bank.ahk`.
- Every phase's acquire/track logic hand-inlines what `DynamicTarget.ColorBlockTarget` already provides.
- Every phase's `_Click` helper duplicates the same Ctrl-hold + settle-delay body.

None of these are bugs — Motherlode works correctly as built — but the next bot should reach for these existing classes directly rather than re-deriving the same shape by hand again.
