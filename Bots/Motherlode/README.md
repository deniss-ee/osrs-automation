# Motherlode

## Overview

Automates OSRS Motherlode Mine pay-dirt farming: mine a pay-dirt vein until the
inventory fills, clear the path to the hopper (rockfalls), deposit the mined
ore into the hopper, run to the ore sack and withdraw the processed
loot/gems, bank everything, then walk back to the mining spot and repeat.
This is the most complex bot in the repo — 7 phases, all bot-specific (none
share code with Firemaking/Smelter/Smithing), using a `TargetLock`-based
acquire/track stability model and a hand-rolled 2-stage waypoint state
machine for the return-to-mine walk. See `ARCHITECTURE.md` for the shared
framework layer (`Engine`/`Phase`/`FailSafe`/`Waiter`/gates/etc.) — this
document only covers Motherlode-specific logic.

Start location / setup assumption: character standing at the mining spot
inside the upper Motherlode Mine floor, RuneLite client at the calibrated
window position/size, inventory not already full, F5 starts the engine at
phase `"mine"`. The bot never opens the mine itself or handles being
somewhere else on F5 — it assumes the player is already positioned at (or
very near) the vein search region when started.

Required calibration (re-measure if resolution/client layout changes):
- `mineRegionX1/Y1/X2/Y2` — the on-screen box where pay-dirt veins render.
- `veinColorLight` / `veinColorDark` (`0x00FF00` / `0x00CE00`) — the two
  green overlay shades OSRS renders on minable veins (two shades because the
  game alternates/varies overlay brightness per vein or lighting).
- `referencePointX/Y` (defaults to screen center) — tiebreaker point when two
  veins are visible at once.
- `redColor` (`0xFF0000`) — rockfall obstruction overlay.
- `yellowColor` (`0xFFFF00`) — hopper overlay color (same yellow also reused
  for both return-waypoint arrival markers — see Known Risks).
- `bankColor` (`0xFF00FF`, magenta) — deposit-container marker.
- `bankImageAnchorX/Y` + `Images/deposit-motherlode.png` (80x72px) — the
  "Deposit All" button image inside the deposit-box interface.
- `sackRunX/Y` — fixed click point to run to the ore sack.
- `return1MarkerX/Y`, `return2MarkerX/Y` — orange/yellow arrival markers for
  the two-leg walk back from bank to mine.
- `return1ClickX/Y`, `return2ClickX/Y`, `return2FinalClickX/Y` — fixed
  waypoint/approach click points for the walk back.
- `inventoryLayout` (hardcoded in the wiring section, not `.ini`-backed —
  `firstX=2099, firstY=801, cols=4, rows=7, slotW=72, slotH=64, gapX=12,
  gapY=8`) — the inventory pixel grid. Recalibrate directly in the `.ahk` if
  the client window ever moves/resizes.
- `indicatorSlot=28` / `secondaryIndicatorSlot=27` — full-inventory gate
  slots. `sackGateSlotA=2` / `sackGateSlotB=12` — sack-received gate slots.

## Files

- Entry point: `Bots/Motherlode/motherlode.ahk`
- Config: `Config/auto-motherlode-v2.ini` (confirmed via the `.ahk`'s
  `iniPath := A_ScriptDir "\..\..\Config\auto-motherlode-v2.ini"`, line 838)
- Log: `logs/auto-motherlode-v4-debug.log`
- Deposit-box "Deposit All" image: `Images/deposit-motherlode.png` (80x72px)

## State Machine

Phase sequence: `mine -> clearRed -> clearYellow -> withdrawSack ->
depositBank -> returnMine1 -> returnMine2 -> mine`. All 7 phases begin
`Run(ctx)` with the window-focus guard (`if (ctx.windowFocus != "" &&
!ctx.windowFocus.IsActive()) return "<ownPhaseName>"`) — confirmed present,
identically shaped, as literally the first statement in every phase's
`Run()`: `MinePhase` (line 90), `ClearRedPhase` (248), `ClearYellowPhase`
(355), `WithdrawSackPhase` (436), `DepositBankPhase` (498), `ReturnMine1Phase`
(565), `ReturnMine2Phase` (643, guards the outer `Run` before dispatching to
either internal stage). This still holds true for all 7 phases as of this
audit.

### 1. `mine` (`MinePhase`, motherlode.ahk:49-217)

**Purpose**: locate and repeatedly click a pay-dirt vein until the inventory
is full (both indicator slots occupied).

**Every tick**, before acquire/track dispatch: checks `ctx.inventory.IsFull()`
first. If full, resets **every downstream phase's** per-cycle scratch state
(`redHasTarget`/`redTargetX/Y`/`redLastClickTime`, `yellowTargetX/Y`
/`yellowLastClickTime`/`yellowEntryDelayApplied`, `sackLastClickTime`
/`sackWaitStartedAt`, `bankPreDelayApplied`) and calls `ResetForNewCycle()` on
every phase in `nextCyclePhases` (`ClearRed`, `ClearYellow`, `WithdrawSack`,
`DepositBank`, `ReturnMine1`, `ReturnMine2` — built incrementally in the
wiring section, lines 914/924/935), then transitions to `clearRed`. This is
the **only** full-inventory check in the whole state machine — no other
phase re-checks `IsFull()`.

**Acquire mode** (`ctx.Get("mineHasTarget", false) == false`, `_Acquire`,
lines 121-162): searches the whole `mineRegion` for **both** vein colors
(`veinColorLight` and `veinColorDark`) via two separate
`ColorSearch.FindFilledBlock` calls every tick. Selection logic:
- Both found → picks whichever is closer (squared Euclidean distance) to
  `referencePoint` (defaults to screen center, 960,540).
- Only one found → uses that one.
- Neither found → stays in `mine`, keeps searching (no timeout on acquire
  itself beyond the phase-level `phaseTimeoutMine`, 180s).

On acquiring: sets `mineHasTarget=true`, records `mineTargetColor` (the
**specific color** that matched, light or dark — this becomes the locked
search color for tracking), `mineTargetX/Y`, resets `mineLastClickTime=0`,
calls `this._lock.Reset()` (fresh `TargetLock`), calls
`ctx.failsafe.ResetPhaseTimer(ctx)`. **Deliberately does not click on the
same tick** — the comment explains the overlay may not be fully rendered
yet; the real first click happens on `_Track`'s next tick.

**Track mode** (`_Track`, lines 167-216): re-searches a box of radius
`mineTrackBoxRadiusPx` (50px) around the last known position, **locked to
`mineTargetColor`** (only the originally-matched color, not both). Feeds
`this._lock.Observe(found, nvx, nvy, &outX, &outY)`.
- **If not found** (`!found`): logs `"Lost track of vein or depleted. Finding
  new vein."`, sets `mineHasTarget=false`, zeroes `mineTargetX/Y`, returns to
  `mine` (re-enters Acquire mode next tick). **This is the vein-depletion
  handling** — OSRS veins deplete after a random number of hits and the
  overlay disappears; the very next `_Track` tick's `FindFilledBlock` fails
  to find the locked color in the narrowed box, `found=false` is fed straight
  through (no debounce), and the bot re-acquires immediately. See Known Risks
  for the one-tick-late click edge case.
- **If found**: updates `mineTargetX/Y` to the live position (position always
  tracks the latest read, per `TargetLock.Observe`'s contract, never
  freezes). Then:
  - **Stable** (`this._lock.IsStable()`, i.e. ≥`mineStableTicks`=2 consecutive
    in-tolerance ticks): clicks if `(A_TickCount - mineLastClickTime) >
    ctx.timing.BaseMs("mineClickCooldown")` (from `clickCooldownMs`=1500ms).
    Applies `veinClickOffsetX/Y` (both 0 by default) via `_Click`, which
    delegates to `ctx.clicker.ClickSettled(...)`.
  - **Not yet stable**: clicks once immediately if `mineLastClickTime==0`
    (first click while walking toward the vein), then re-clicks if still not
    stable after `walkReclickTimeoutMs` (3000ms) — prevents getting
    permanently stuck if position keeps jittering (e.g. camera movement).

**Multiple simultaneous veins**: the bot does NOT always pick the same one,
nor strictly nearest-by-scan-order — it's nearest-to-`referencePoint` **only
when both colors are found on the exact same tick**; `FindFilledBlock`
itself returns the first verified block encountered by its stack-based
scan (top-down or bottom-up per `mineScanBottomUp`), which for a single color
is effectively "first found by scan order," not "nearest." So: color
selection is distance-based, but within one color's search the specific vein
chosen is whatever the scan order surfaces first — not necessarily nearest of
possibly-multiple same-color veins.

**Vein-color mid-track color switch**: once locked to one color in Track
mode, the bot never re-evaluates whether the *other* color might now be
closer/better — it only tracks the originally-acquired color until it's lost
entirely.

### 2. `clearRed` (`ClearRedPhase`, motherlode.ahk:228-325)

**Purpose**: clears rockfall obstructions (`redColor=0xFF0000`) blocking the
walkway to the hopper. Whole-screen search (rockfalls can appear anywhere),
single color, no click offset.

`ResetForNewCycle()`: resets the phase's own `TargetLock` — called by
`MinePhase` on the `mine -> clearRed` transition.

**Acquire mode** (`!ctx.Get("redHasTarget", false)`): searches
`(0,0)-(A_ScreenWidth,A_ScreenHeight)` for `redColor`. **Not found at all
transitions immediately to `clearYellow`** — the exit condition for this
phase is a clean whole-screen miss, not an explicit "no more rockfalls"
signal from the game. Found: locks target, resets `redLastClickTime=0`,
resets `TargetLock`, stays in `clearRed`.

**Track mode**: re-searches a `redTrackBoxRadiusPx` (200px) box around last
position (camera drift while running toward it). Not found → unlocks
(`redHasTarget=false`), stays in `clearRed` (re-enters Acquire next tick, so
a second rockfall elsewhere on screen would be picked up rather than
necessarily exiting to `clearYellow` — exit only happens when Acquire itself
finds nothing). Found + stable (`redStableTicks`=2) → clicks if cooldown
(`redClearCooldownMs`=6000ms) elapsed. Found + not stable → clicks once
immediately if this is the very first click on this target
(`lastClick==0`), no re-click timeout logic (unlike Mine's
`walkReclickTimeoutMs`) — if a not-yet-stable rockfall target never
stabilizes, it will only get the one initial click ever, relying on the
Track loop continuing to feed `Observe` until it either stabilizes or is
lost.

**What "red" is**: per the in-code comments this models a rockfall
obstruction on the walkway to the hopper — a separate mechanic from the
water wheel (see Known Risks — water wheel handling is a documented gap, not
folded into `clearRed`).

### 3. `clearYellow` (`ClearYellowPhase`, motherlode.ahk:334-409)

**Purpose**: deposits mined pay-dirt into the ore hopper. "Yellow" is the
hopper's overlay color (`yellowColor=0xFFFF00`).

**Exit check runs first, every tick, before any search**:
`ctx.inventory.IsEmpty()` (via the `NotGate(fullGate)` — see Config
Reference) → logs `"Ore deposited. Moving to sack."`, transitions to
`withdrawSack`. This means the phase's own click loop is what empties the
inventory (game mechanic: depositing pay-dirt into the hopper empties
whatever pay-dirt/ore is in inventory), and the phase just keeps
re-clicking the hopper until that happens.

**No acquire/track split like Mine/ClearRed** — every tick does a
whole-screen `FindFilledBlock` for `yellowColor`, seeded with the last known
`yellowTargetX/Y` as the search's reference point (steers
`FindFilledBlock`'s stack exploration toward the last-known location instead
of a blind top-down scan — the hopper doesn't move once found). If not
found: logs `"Cannot see hopper!"`, stays in `clearYellow` — **no timeout
counter of its own**, relies purely on the phase-level `phaseTimeoutBank`
(30000ms) engine-level timeout to eventually stop the engine if the hopper
is genuinely never visible.

If found: `this._lock.Observe(true, cx, cy, &outX, &outY)` — always fed
`found=true` (the hopper is either found or the tick is a no-op above), so
`IsStable()`/`missingTicks` behave differently here than in Mine/ClearRed
(no "not found this tick" path ever reaches `Observe`). One-time settle
delay on first detection (`yellowEntryDelayApplied` flag,
`yellowEntryDelayMs=100`) — needed because `yellowStableTicks=0` makes the
lock "instantly stable," so without this the very first click would fire as
fast as the search resolves. Click cadence: stable → cooldown-gated
(`yellowClickCooldownMs=15000ms`, deliberately long to let the walk-in +
deposit animation finish); not stable → single first click only
(`lastClick==0` check, no re-click-after-timeout logic).

### 4. `withdrawSack` (`WithdrawSackPhase`, motherlode.ahk:419-468)

**Purpose**: runs to the ore sack (fixed point, no color search) and
withdraws its contents.

Exit check first: `ctx.inventory.HasSackItems()` → logs `"Items received
from sack. Moving to bank."`, transitions to `depositBank`.
`HasSackItems()` delegates to the sack gate: `OrGate([sackGateA, sackGateB])`
where `sackGateA = SlotGate(sackGateSlotA=2, ...)`, `sackGateB =
SlotGate(sackGateSlotB=12, ...)` — true if **either** slot 2 or slot 12 is
occupied (confirmed matches ARCHITECTURE.md's description; a gem/processed
ore can land in an unpredictable inventory slot after a sack withdrawal, so
two spread-out slots are OR'd rather than relying on one).

No target search at all — `sackRunX/Y` is a fixed calibrated click point
(the sack itself). Timeout: `sackWaitStartedAt` timestamp set on first tick;
if `(A_TickCount - waitStartedAt) > sackWaitTimeoutMs` (60000ms), logs a
timeout and calls `ctx.engine.Stop(...)` — **stops the whole bot**, does not
retry or fall back. Click cadence: first click gets a pre-click delay
(`sackPreClickDelayMs=800ms`, applied via `ctx.waiter.After` **before** the
click, letting the hopper-drop animation finish) then
`ctx.clicker.ClickSettled`; subsequent re-clicks gated by
`sackReclickCooldownMs` (12000ms) as a pure failsafe re-click, not a
click-cadence mechanism (the sack should only need one click in the normal
case; repeated clicks only happen if the first click didn't register).

### 5. `depositBank` (`DepositBankPhase`, motherlode.ahk:478-532)

**Purpose**: finds and clicks the deposit container (magenta `0xFF00FF`
marker, whole-screen search), waits for the deposit box's "Deposit All"
button image to appear, clicks it.

One-time settle delay (`bankPreDelayApplied` flag, `bankPreClickDelayMs`=
300ms) applied **before** searching for the marker (not after) — the
in-code comment explicitly calls out this ordering as deliberate: searching
first then sleeping would click stale coordinates if the character/camera
kept moving during the sleep (this is the documented "DepositBankPhase
stale-click bug" pattern referenced in ARCHITECTURE.md item 4).

Whole-screen `FindFilledBlock` for `bankColor`. Not found: logs `"Cannot see
deposit container!"`, stays in `depositBank` — again no phase-owned timeout
counter, relies on `phaseTimeoutSack` (90000ms, shared with `withdrawSack`).
Found: clicks immediately (no stability gate at all — this phase clicks the
marker exactly once per visit, unconditionally, the instant it's found),
then calls `this._depositAnchor.WaitFor(ctx.waiter, ctx.timing,
"bankImagePoll", bankImageWaitTimeoutMs=15000, &dx, &dy)` — an `ImageAnchor`
polling `ImageSearch` for `Images/deposit-motherlode.png` (80x72px) inside a
region built from `bankImageAnchorX/Y ± bankImageSearchPaddingPx` (padded to
also cover the full 80x72 image size, lines 899-904). If the image never
appears within the timeout: logs, calls `ctx.engine.Stop(...)` — stops the
bot. If found: clicks the image (deposit-all), logs completion, transitions
to `returnMine1`.

**Marker/anchor**: fixed-color block search for the deposit container
(magenta), then an image-based anchor (not a color) for the "Deposit All"
button — two different detection primitives chained in one phase. Deposit
strategy is deposit-all (single click on the image), not selective — no
withdraw-plan (`Interfaces/Bank.ahk`'s `WithdrawSlot`/withdraw-plan pattern
used by Firemaking/Smelter/Smithing) is used at all; Motherlode never
withdraws anything from the bank — pay-dirt/ore/gems are one-way deposited,
never restocked from the bank.

### 6. `returnMine1` (`ReturnMine1Phase`, motherlode.ahk:542-604)

**Purpose**: leg 1 of the walk from the bank back to the mining spot.

Single-stage phase (unlike `returnMine2`). Every tick: searches a box of
`return1MarkerSearchPaddingPx` (50px) around the calibrated
`return1MarkerX/Y` for a `return1MarkerColor` (`0xFFFF00`, same yellow as the
hopper color — see Known Risks) block of size `return1MarkerW x
return1MarkerH`. Found → logs arrival, applies
`ctx.waiter.After(ctx.timing, "return1PostMarkerDelay")` (100ms, **blocking
inline sleep**, not a scratch-flag-gated one-time delay like other phases'
pattern — since this phase only runs this code path once per cycle right
before transitioning away, a scratch flag isn't needed here), transitions to
`returnMine2`.

Not found: timeout tracked via `return1WaitStartedAt`; exceeding
`return1WaitTimeoutMs` (30000ms) logs and stops the engine. Click cadence:
first click or `> return1ReclickCooldownMs` (12000ms) since last click →
`ctx.clicker.ClickSettled(ctx, return1ClickX, return1ClickY, ...)` (a fixed
waypoint click, not a found-target's coordinates — this phase clicks a
**calibrated fixed point** on the minimap/ground repeatedly until the
**marker** appears, it does not click the marker itself).

### 7. `returnMine2` (`ReturnMine2Phase`, motherlode.ahk:616-738)

**Purpose**: leg 2 of the walk (waypoint + marker wait) plus the final
approach click that puts the character back on the mining spot — a 2-stage
internal state machine (`ctx.Get("return2Stage", 1)`) under one phase name,
confirmed hand-rolled rather than using `Interfaces/Walk.ahk`'s
`Walk`/`Waypoint` classes (per ARCHITECTURE.md, deliberately left alone).

**Stage 1** (`_Stage1`, lines 653-691): identical shape to `returnMine1` —
searches `return2MarkerSearchPaddingPx` (20px) around `return2MarkerX/Y` for
`return2MarkerColor` (`0xFFFF00`, again the same yellow). Found → settle
delay (`return2PostMarkerDelay`=400ms), sets `return2Stage=2`, resets
`return2LastClickTime=0`, stays in `returnMine2` (does NOT change phase name
— the stage transition is internal). Not found → timeout via
`return2WaitStartedAt` vs. `return2WaitTimeoutMs` (30000ms) → stop engine;
otherwise click-cadence identical to `returnMine1`
(`return2ReclickCooldownMs`=12000ms) against the fixed `return2ClickX/Y`
waypoint point.

**Stage 2** (`_Stage2`, lines 695-737): clicks the fixed final approach spot
(`return2FinalClickX/Y`) exactly once (`return2LastClickTime==0` check), then
waits `return2AfterClickWaitMs` (2500ms) with no further searching at all —
this is a blind timed wait, not an arrival-anchor check; the bot assumes the
character has walked to the mining spot after this fixed delay. Once the
wait elapses: logs, then performs the **full per-cycle reset** — every
scratch key touched anywhere in the cycle is zeroed here (`mineHasTarget`,
`mineTargetX/Y`, `mineLastClickTime`, `redHasTarget`, `redTargetX/Y`,
`redLastClickTime`, `yellowTargetX/Y`, `yellowLastClickTime`,
`yellowEntryDelayApplied`, `sackLastClickTime`, `sackWaitStartedAt`,
`bankPreDelayApplied`, `return1LastClickTime`, `return1WaitStartedAt`,
`return2Stage` reset to 1, `return2LastClickTime`, `return2WaitStartedAt`),
calls `ResetForNewCycle()` on every phase in `nextCyclePhases` (which
resets each acquire/track phase's own `TargetLock`), and returns `"mine"` —
completing the loop.

**Exact waypoint/anchor sequence**: bank marker click (magenta,
`depositBank`) → deposit-all image click → `returnMine1` fixed click
(699,1279) waiting for yellow marker near (1321,678) → `returnMine2` stage 1
fixed click (1251,1354) waiting for yellow marker near (1303,433) → stage 2
fixed final click (1491,1023) → blind 2500ms wait → `mine`.

## Config Reference

| Section | Key | Meaning | Value | Misconfiguration impact |
|---|---|---|---|---|
| Tunables | `runnerTickMs` | Engine tick interval | 50 | Too low = CPU waste; too high = sluggish reaction to detections |
| Tunables | `phaseTimeoutMine` | Force-stop if `mine` makes no progress | 180000 | Too low = false-stops during legitimate long vein searches; too high = hangs longer on a truly dead vein search |
| Tunables | `phaseTimeoutBank` | Shared timeout for `clearRed`/`clearYellow` | 30000 | Too low = stops mid-clear during a legitimately long rockfall/hopper search |
| Tunables | `phaseTimeoutSack` | Timeout for `withdrawSack`/`depositBank` | 90000 | Must stay above `sackWaitTimeoutMs`+`bankImageWaitTimeoutMs`-adjacent margins or the engine-level timeout fires before the phase's own internal timeout message |
| Tunables | `phaseTimeoutReturn` | Timeout for `returnMine1`/`returnMine2` | 60000 | Same risk as above vs. `return1WaitTimeoutMs`/`return2WaitTimeoutMs` |
| Tunables | `colorTolerance` | Per-channel tolerance for vein search | 20 | Too low = misses legitimate vein pixels (anti-aliasing); too high = false-matches background scenery as a vein |
| Tunables | `targetLockMoveTolerancePx` | Px movement still counted "stable" | 2 | Too tight = never stabilizes (camera micro-jitter always exceeds it, clicks never reach cooldown-gated cadence); too loose = clicks too early/often |
| Tunables | `mineStableTicks` | Consecutive stable ticks before "arrived" | 2 | Too low = clicks before vein render settles; too high = delayed clicking |
| Tunables | `clickCooldownMs` | Min ms between clicks on a stable vein | 1500 | Too low = spam-clicks (anti-ban risk, wasted clicks); too high = misses mining ticks |
| Tunables | `veinClickOffsetX/Y` | Click offset from block center | 0/0 | Nonzero without recalibration can click off the rock entirely |
| Tunables | `mineScanBottomUp` | Scan vein region bottom-up | 0 | Flip only if clicks land in overlay but miss the rock — wrong value can shift found-point-to-verify-direction mismatch (see `VerifyBlock`'s `directionY`) |
| Tunables | `walkReclickTimeoutMs` | Re-click if still unstable this long | 3000 | Too low = spam re-clicks while walking; too high = can appear stuck |
| Tunables | `clickSettleMs` / `clickSettleJitterPercent` | Delay between mouse-move and click | 100 / 10 | Too low = click can register as a plain tile-click instead of on the hovered target |
| Tunables | `ctrlHoldSettleMs` | Delay after Ctrl-down before Ctrl-up (runMode) | 50 | Too short may not register as a held-Ctrl (force-run) click in-game |
| Tunables | `mineRegionX1/Y1/X2/Y2` | Vein search box | 1068,672,1438,842 | Wrong box = veins outside it are invisible to Acquire mode entirely |
| Tunables | `veinColorLight` / `veinColorDark` | Vein overlay colors | 0x00FF00 / 0x00CE00 | Wrong value = Acquire never finds a vein; bot stalls at `mine` until `phaseTimeoutMine` |
| Tunables | `mineBlockW/H` | Min solid block size counted as a vein | 25/25 | Too large = misses smaller-rendered veins (different zoom/distance); too small = false-positives on noise |
| Tunables | `mineTrackBoxRadiusPx` | Half-width of re-search box once locked | 50 | Too small = loses track on legitimate small movement/lag, forces spurious re-acquire; too large = slower re-search, more false-match risk |
| Tunables | `referencePointX/Y` | Tiebreak point for two simultaneous veins | 960,540 (screen center) | Wrong value biases vein choice incorrectly, e.g. always picks a farther vein |
| Tunables | `redColor` / `redTolerance` | Rockfall overlay color | 0xFF0000 / 0 | Zero tolerance means exact-match only — any slight color drift (lighting/overlay opacity) causes total miss |
| Tunables | `redBlockW/H` | Min rockfall block size | 25/25 | Same risk class as `mineBlockW/H` |
| Tunables | `redTrackBoxRadiusPx` | Re-search box radius while tracking a rockfall | 200 | Large because character walks toward it (camera drift); too small loses track mid-walk |
| Tunables | `redStableTicks` | Stable ticks before clearing click | 2 | Same risk class as `mineStableTicks` |
| Tunables | `redClearCooldownMs` | Min ms between clear-clicks | 6000 | Long, matches clearing-animation duration; too short = spam-clicks mid-animation |
| Tunables | `yellowColor` / `yellowTolerance` | Hopper overlay color | 0xFFFF00 / 12 | Same value is reused (independently configured, but currently identical) for `return1MarkerColor`/`return2MarkerColor` — see Known Risks |
| Tunables | `yellowBlockW/H` | Min hopper block size | 22/22 | Same risk class as vein/rockfall block sizes |
| Tunables | `yellowStableTicks` | Stable ticks before click | 0 (instantly stable) | Relies entirely on `yellowEntryDelayMs` to avoid an instant click — removing that delay without raising this would restore the original too-fast-click bug |
| Tunables | `yellowClickCooldownMs` | Min ms between hopper clicks | 15000 | Deliberately long for deposit animation; too short spam-clicks mid-deposit |
| Tunables | `yellowEntryDelayMs` | One-time delay before first hopper click | 100 | Removing/zeroing reintroduces the "click before overlay settles" bug class |
| Tunables | `sackRunX/Y` | Fixed sack click point | 1825,724 | Wrong coordinates = clicks nothing, sack never gives items, eventually hits `sackWaitTimeoutMs` and stops the bot |
| Tunables | `sackPreClickDelayMs` | Delay before first sack click | 800 | Too short = clicks before hopper-drop animation ends |
| Tunables | `sackReclickCooldownMs` | Min ms between sack re-clicks | 12000 | Too short = spam re-clicks; too long = slow recovery from a missed click |
| Tunables | `sackWaitTimeoutMs` | Max wait for sack items before stopping | 60000 | Too short = false-stops on legitimately slow sack response |
| Tunables | `bankColor` / `bankTolerance` | Deposit container marker color | 0xFF00FF / 0 | Zero tolerance = exact match only; any drift causes total miss, phase stalls at `phaseTimeoutSack` |
| Tunables | `bankBlockW/H` | Min deposit-marker block size | 24/24 | Same risk class |
| Tunables | `bankPreClickDelayMs` | Delay before clicking container | 300 | Too short = clicks before character finishes walking to container |
| Tunables | `bankImageAnchorX/Y` | Calibrated anchor for "Deposit All" image | 775,765 | Wrong anchor + insufficient padding = image never found within its search region, times out and stops the bot |
| Tunables | `bankImageSearchPaddingPx` | Padding around anchor for image search | 20 | Too small = misses the image if the anchor drifts slightly; too large = slower search |
| Tunables | `bankImageWaitTimeoutMs` | Max wait for deposit box image | 15000 | Too short = false-stops if the interface animates in slowly |
| Tunables | `bankImagePollMs` | ImageSearch poll interval while waiting | 100 | Too low = wasted CPU; too high = slower detection |
| Tunables | `return1ClickX/Y` | Fixed waypoint 1 click | 699,1279 | Wrong point = character never starts walking correctly toward waypoint 1 |
| Tunables | `return1MarkerX/Y/W/H` | Waypoint 1 arrival marker | 1321,678,21,21 | Wrong marker = never detects arrival, times out at `return1WaitTimeoutMs`, stops the bot |
| Tunables | `return1MarkerColor` / `return1MarkerTolerance` | Marker color/tolerance | 0xFFFF00 / 0 | Same yellow as hopper — see Known Risks; zero tolerance is exact-match only |
| Tunables | `return1MarkerSearchPaddingPx` | Search box padding around marker point | 50 | Too small = misses marker if position estimate is slightly off |
| Tunables | `return1ReclickCooldownMs` | Min ms between waypoint 1 re-clicks | 12000 | Too short = spam-clicks while walking |
| Tunables | `return1WaitTimeoutMs` | Max wait for waypoint 1 marker | 30000 | Too short = false-stops on a legitimately long walk |
| Tunables | `return1PostMarkerDelayMs` | Delay after marker seen, before next phase | 100 | Removing causes the "instant click on next waypoint" bug class |
| Tunables | `return2ClickX/Y`, `return2MarkerX/Y/W/H`, `return2MarkerColor/Tolerance`, `return2MarkerSearchPaddingPx`, `return2ReclickCooldownMs`, `return2WaitTimeoutMs`, `return2PostMarkerDelayMs` | Same roles as the `return1*` equivalents, for leg 2 | see `.ini` | Same risk classes as `return1*` |
| Tunables | `return2FinalClickX/Y` | Final approach click (mining spot) | 1491,1023 | Wrong point = character doesn't end up on/near the mining spot; `mine` Acquire mode will simply fail to find a vein and stall until `phaseTimeoutMine` |
| Tunables | `return2AfterClickWaitMs` | Blind wait after final click before handoff | 2500 | Too short = `mine` starts searching before character finishes walking, wasting acquire attempts; too long = wasted idle time each cycle |
| Settings | `runMode` | Hold Ctrl (force-run) while clicking | 1 | 0 disables force-run-click, changes in-game click semantics (may not run to target the same way) |
| Settings | `indicatorSlot` | Primary full-inventory slot | 28 | Wrong slot = `IsFull()` never/always true, breaking the mine→clearRed transition |
| Settings | `secondaryIndicatorSlot` | Secondary full-inventory slot (AND'd) | 27 | Same risk — this exists specifically because a lone gem in slot 28 without a full hopper load shouldn't count as "full" |
| Settings | `sackGateSlotA` / `sackGateSlotB` | Sack-received slots (OR'd) | 2 / 12 | Wrong slots = `HasSackItems()` never fires, `withdrawSack` times out and stops the bot every cycle |

## Known Risks & Edge Cases

**Vein depletes mid-mine (OSRS mechanic)** → **Current behavior**: `_Track`'s
`FindFilledBlock` fails on the very next tick after depletion (the overlay
disappears), `mineHasTarget` resets to `false`, next tick re-enters
`_Acquire` and searches the whole `mineRegion` again → **Risk/impact**: this
is a low-risk, handled case — but there's a one-tick lag: the click that was
already in flight/registered on the last "found" tick before depletion could
land on a raw-rock click with nothing to mine (harmless, wastes a fraction
of a second) or occasionally on a *newly spawned* different vein if OSRS
respawns pay-dirt at the exact same overlay position (harmless, would just
be picked up next tick). No explicit "hits counter" or depletion prediction
exists — the bot is purely reactive to the overlay disappearing.

**Two veins simultaneously visible, both far from `referencePoint` but one
much closer to the character's actual position** → **Current behavior**:
`referencePoint` defaults to screen center (960,540), which is a reasonable
proxy for "near the player" but is a fixed calibrated point, not a live
player-position query → **Risk/impact**: if the camera angle/zoom changes
such that screen-center no longer corresponds to "near player," the bot can
consistently prefer the wrong (farther/behind-an-obstacle) vein.

**Water wheel breaking (OSRS mechanic) — CONFIRMED GAP**: The Motherlode
Mine's water wheel can break (a random event) and must be repaired by
clicking it (equivalent to using a hammer on it) before pay-dirt processing
continues; this is a distinct mechanic from both the rockfall obstruction
(`clearRed`) and the hopper deposit (`clearYellow`). **Current behavior**:
no phase, color, or marker anywhere in `motherlode.ahk` or
`auto-motherlode-v2.ini` references a water wheel, strut, or repair
indicator — `clearRed` is explicitly documented (in its own header comment,
lines 219-227) as clearing "rockfall obstacles blocking the hopper walkway,"
not wheel repair. → **Risk/impact**: if the water wheel breaks while this
bot is running unattended, the hopper will stop functioning (in-game) and
`clearYellow`'s deposit loop will never see the inventory empty (since
depositing into a broken hopper doesn't process pay-dirt) — this phase has
no internal timeout counter of its own (see phase 3 above), so it will
click the hopper marker forever every `yellowClickCooldownMs` (15000ms)
until the shared engine-level `phaseTimeoutBank` (30000ms) trips and stops
the bot. **This is a genuine functional gap, not just a documentation gap.**

**Hopper visible but blocked/broken for a non-water-wheel reason** →
**Current behavior**: `clearYellow` only checks `ctx.inventory.IsEmpty()`
as its exit signal — if the hopper is clickable but not actually processing
(any reason), the phase will click every 15s until `phaseTimeoutBank`
(30000ms) — only two click attempts before the engine stops the bot
entirely. → **Risk/impact**: fast, clean failure (stops rather than
infinite-loops), but no automatic recovery/retry logic, no distinction in
the log between "hopper not found" and "hopper found but not processing."

**Sack, deposit-box, or return-waypoint marker never appears (miscalibration
or client state change)** → **Current behavior**: every one of
`withdrawSack`, `depositBank`, `returnMine1`, `returnMine2` has its own
internal wait-timeout that calls `ctx.engine.Stop(...)` cleanly (never an
infinite loop, never a crash) → **Risk/impact**: the bot stops the whole run
rather than recovering or skipping — acceptable failure mode by design, but
means any transient game-side hiccup during these phases (e.g. a genuine
lag spike) halts the entire automated session, not just the current cycle.

**`yellowColor` == `return1MarkerColor` == `return2MarkerColor`
(`0xFFFF00`)** → **Current behavior**: these are three independently
configured `.ini` values that currently share the same literal color by
coincidence (or by design, since OSRS reuses this overlay yellow for both
the hopper and minimap/ground arrow markers) → **Risk/impact**: none today
since each phase searches a different, disjoint screen region (hopper:
whole screen but seeded near last-known hopper position; waypoint markers:
tightly padded boxes around calibrated marker points) — but if a future
edit widens any of these search regions without noticing the shared color,
cross-phase false-positive matches become possible (e.g. `returnMine1`
finding the hopper's yellow overlay instead of its own arrival marker, if
the two regions ever overlap).

**`TargetLock.IsLost()`/`missingTicksToUnlock` is configured but never
consulted** → see Bugs Found This Audit below — not a runtime risk today
(default value of 1 makes it behaviorally equivalent to the direct `!found`
check currently used), but a maintenance trap: raising
`missingTicksToUnlock` in a `TargetLock(...)` constructor call would silently
do nothing, since no phase calls `.IsLost()`.

**Stuck waypoint** (`returnMine1`/`returnMine2` stage 1) → **Current
behavior**: bounded by `return1WaitTimeoutMs`/`return2WaitTimeoutMs`
(30000ms each), re-clicking the fixed waypoint point every
`return{1,2}ReclickCooldownMs` (12000ms, so at most ~2-3 re-clicks before
timeout) → **Risk/impact**: if the character's walk path is obstructed
in-game (e.g. another player blocking a narrow corridor), the same fixed
point gets re-clicked a few times then the bot stops — no path-replanning,
no alternate route.

**`returnMine2` stage 2 has no arrival verification at all** →
**Current behavior**: after the final approach click, the bot waits a fixed
`return2AfterClickWaitMs` (2500ms) and then unconditionally hands off to
`mine`, assuming the character arrived → **Risk/impact**: if the walk takes
longer than 2500ms (e.g. an unexpected obstruction, or a client-side lag
spike), `mine`'s Acquire mode will simply search `mineRegion` and find
nothing (harmless — it just keeps searching, gated only by
`phaseTimeoutMine`=180000ms) — a soft failure, not a crash, but a
significant potential silent stall if it happens repeatedly (e.g. wrong
`return2FinalClickX/Y` calibration would manifest as *every* cycle stalling
at `mine` for up to 3 minutes before the engine stops itself).

**Inventory full mid-cycle in an unexpected phase** → **Current behavior**:
`IsFull()` is checked ONLY in `MinePhase.Run()`. No other phase re-checks
it. → **Risk/impact**: this is by design given the loop shape (inventory can
only refill during `mine`, since every other phase either empties it
(`clearYellow`) or adds a bounded few items (`withdrawSack`'s sack
withdrawal) — but if the sack ever yielded enough items to refill the
inventory to "full" by the indicator gate's definition (slots 27+28 both
occupied) before `depositBank`, the bot would still proceed through
`depositBank`/`returnMine1`/`returnMine2` normally (deposit-all in
`depositBank` empties everything regardless), so this isn't actually
exploitable — but it means "full" is never rechecked as an exit signal
anywhere except at the very top of `mine`, which is worth remembering if a
future change adds a new phase between `withdrawSack` and `mine`.

**Scratch-state reset coverage** → **Current behavior**: two central reset
points exist — `MinePhase`'s inventory-full transition (resets
`clearRed`/`clearYellow`/`withdrawSack`/`depositBank`'s per-cycle keys) and
`ReturnMine2Phase._Stage2`'s completion (resets literally everything,
including its own and `returnMine1`'s keys, plus calls `ResetForNewCycle()`
on all 6 downstream phases). Cross-checked: every scratch key set anywhere
in the file is zeroed in at least one of these two spots. No orphaned
scratch state was found un-reset between cycles.

## Anti-Ban / Human-Like Behavior Notes

`Humanizer(false)` (motherlode.ahk:843) — humanization is constructed but
disabled, matching every other bot in the repo (per ARCHITECTURE.md, a
deliberate no-op left in place rather than removed). Concretely for
Motherlode: `botHumanizer.Offset` (click position jitter) always returns
(0,0), and `botHumanizer.Jitter` (delay jitter) returns `baseMs` unchanged —
so `clickSettleJitterPercent=10` in the `.ini` currently has zero effect
despite being present and documented as "+/- percent jitter." All click
timing is otherwise fixed/deterministic per the configured cooldowns
(`mineClickCooldown`, `redClearCooldownMs`, `yellowClickCooldownMs`, etc.) —
no randomization of poll intervals (`runnerTickMs`=50 is a fixed engine tick)
or click cadence beyond the non-blocking cooldown-timestamp pattern shared
with every phase in the framework. `runMode=1` holds Ctrl during clicks
(force-run), a gameplay behavior choice, not an anti-ban measure.

## Bugs Found This Audit

- **`TargetLock.IsLost()` and its `missingTicksToUnlock` constructor
  parameter are dead code for this bot.** `MinePhase._Track` (line 180-188),
  `ClearRedPhase._Track` (line 292-300) both call `this._lock.Observe(found,
  ...)` but never call `this._lock.IsLost()` anywhere — instead they check
  the same tick's own `found` boolean directly to decide "lost, re-acquire."
  Since every `TargetLock(...)` construction in this file
  (`MinePhase.__New` line 71, `ClearRedPhase.__New` line 237,
  `ClearYellowPhase.__New` line 343) uses the default `missingTicksToUnlock
  := 1`, behavior today is identical either way (missing for 1 tick = lost
  immediately). But this means the `missingTicksToUnlock` parameter cannot
  currently be tuned to add debounce tolerance (e.g. "allow the vein overlay
  to blink out for up to 2 ticks before treating it as depleted") without
  also rewriting the `!found` checks to call `IsLost()` instead — a future
  maintainer changing only the constructor argument would see no effect and
  reasonably conclude the class is broken, when actually it's just unused.

- **`ClearRedPhase`'s not-yet-stable click path has no re-click-after-timeout
  logic**, unlike `MinePhase`'s `walkReclickTimeoutMs` (motherlode.ahk:314-320
  vs. 206-212) — if a rockfall target is found but never stabilizes (e.g.
  persistent camera jitter exceeding `targetLockMoveTolerancePx`), it
  receives exactly one click for the phase's entire dwell time on that
  target, relying solely on the outer `phaseTimeoutBank` (30000ms) to
  eventually recover. Not necessarily wrong (rockfalls may not need
  re-clicking the way a walked-to vein does), but it's an asymmetry worth
  a maintainer's attention if rockfall-clearing proves unreliable live.

- **No water wheel handling anywhere** — see Known Risks above; flagged
  here too since it's a missing feature, not just a risk of existing code.

- **`ReturnMine2Phase._Stage2` has no arrival-anchor verification**, unlike
  every other waypoint step in this bot (which all wait for a color marker)
  — it's a blind timed wait (`return2AfterClickWaitMs`). Inconsistent with
  the rest of the bot's "verify, don't assume" pattern, though not
  necessarily incorrect if the final approach reliably takes less than
  2500ms in practice.

## Future Agent Development Roadmap

- **Add explicit water-wheel-broken detection and a repair phase** (or fold
  repair-clicking into `clearRed`/a new `clearWheel` phase) — the single
  biggest functional gap found this audit. Needs: the wheel's
  broken-state overlay/marker color (measure live in-game), a click
  action (equivalent to using a hammer on it), and a place in the phase
  sequence — likely between `clearRed` and `clearYellow`, or merged into
  `clearRed`'s whole-screen search as a second candidate color the same way
  `MinePhase` already searches two vein-color candidates.
- **Add a real vein-depletion re-acquire audit in-game**: confirm via the
  debug log (`"Lost track of vein or depleted. Finding new vein."`) how
  often this actually fires versus a genuine tracking loss (e.g. camera
  pan) — if depletion is frequent, consider a lighter-weight
  "was-found-last-tick, now-not-found" hit counter to distinguish "vein
  actually depleted" from "one bad tick" before discarding the lock, since
  currently a single missed tick (any `FindFilledBlock` false negative,
  not just true depletion) is enough to force a full-region re-acquire.
- **Wire up `TargetLock.IsLost()`** in `MinePhase`/`ClearRedPhase`, or
  remove `missingTicksToUnlock` from being exposed as tunable if it will
  never be used — currently dead code that could mislead a future editor
  (see Bugs Found This Audit).
- **Consider adding a re-click-after-timeout path to `ClearRedPhase`'s
  not-yet-stable branch**, matching `MinePhase`'s `walkReclickTimeoutMs`
  pattern, if live testing shows rockfalls getting stuck un-cleared after
  one click.
- **Consider replacing `ReturnMine2Phase._Stage2`'s blind wait with a real
  arrival check** (e.g. verify the mine's vein-search region actually shows
  vein overlays, or add a small arrival marker at the mining spot) so a
  slow/obstructed final walk doesn't silently cost up to 3 minutes at
  `mine` before the engine self-stops.
- **If a 6th bot ever needs multi-vein-color acquire/track with distance
  tiebreaking**, this phase's `_Acquire`/`_Track` shape (search N colors,
  pick nearest to a reference point, lock to the winning color) is the
  reference implementation — consider promoting it into
  `Detection/DynamicTarget.ahk`'s `ColorBlockTarget` (currently unused
  scaffolding per ARCHITECTURE.md) rather than re-inlining a third time.
- **Do not touch `ReturnMine1Phase`/`ReturnMine2Phase`'s hand-rolled stage
  machine** to "modernize" it into `Interfaces/Walk.ahk`'s `Walk`/`Waypoint`
  classes without a live-verification pass — this is working, in-game
  verified code; ARCHITECTURE.md already documents this as a deliberate
  leave-alone.
