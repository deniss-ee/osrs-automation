; ============================================================
; v6 Lib\Steps.ahk - composite building blocks
;
; TrackAndClick: the acquire/track/depleted loop from micro 12,
; generalized from micro 12's script-level globals into an opts
; object so any bot can call it with its own colors/region/pacing.
; Loop body, tie-break, drift-reject, and anchor-hold logic are
; unchanged from the confirmed micro 12 design - only the config
; plumbing changed (globals -> opts.*).
;
; PickupAppeared: same generalization of micro 11's pickup flow.
;
; FindAndClickBlock/FindAndClickImage: the one-shot "wait for a marker/
; image, then click it" shape (promoted 2026-07-20).
;
; ClickUntilCondition/TravelToPoint: two shapes promoted 2026-07-21 from
; Motherlode2 once each had a real second caller - the patient-first-
; wait/re-click retry loop (hopper + sack) and the click-marker/confirm-
; arrival-at-a-point/whole-screen-diagnostic travel step (GoToSackArea +
; ReturnToMine) respectively. See each function's own header for details.
;
; DepositAllToBank: the "click a bank/deposit marker -> click deposit-all
; image -> optionally confirm the inventory emptied" shape, promoted
; 2026-07-21 across Woodcutting's Bank(), Motherlode2's WithdrawAndBankOnce
; tail, and Crafting's deposit steps.
;
; opts is a plain object (not a Map) - same {key: value} shape as the
; Find-spec sketch in the plan file.
; ============================================================

; opts:
;   colors        - array of candidate colors, equal priority (required)
;   tol           - per-channel tolerance (default 5)
;   blockW/blockH - required solid block size (required)
;   verifyPercent - block-match strictness, 100 = strict (default 100)
;   refX/refY     - character's on-screen point, used for acquire proximity (required)
;   acquireRadii  - array of expanding square-ring half-sizes tried before
;                   the region-wide fallback (default [] = region-wide only)
;   region        - [x1,y1,x2,y2] outer bound clamping BOTH the acquire rings/
;                   fallback AND the track-mode re-search box (default whole
;                   screen). Added 2026-07-22 for Motherlode2's re-measured
;                   680x540 vein area - narrowing this makes every underlying
;                   Find* call scan far fewer pixels than a whole-screen search.
;   trackRadius   - half-size of the narrowed re-search box once locked (required)
;   maxDriftPx    - reject a track match this far from the last position (default 40)
;
;   TUNING trackRadius vs maxDriftPx (learned live tuning Woodcutting,
;   2026-07-20 - a same-color-neighbor scenario like Motherlode's
;   veinColorLight/veinColorDark, or several same-sized blocks in a row,
;   makes this worth getting right):
;     - trackRadius is the SEARCH NET: "how far from the last known spot
;       do I even look." Too small and legitimate camera pan/walking
;       moves the target clean out of the search box (reported as
;       "not found" even though it's still on screen).
;     - maxDriftPx is a SUSPICION CHECK applied AFTER a match is found
;       inside that net: "this match is far enough from last tick that
;       it's probably a DIFFERENT same-colored block standing nearby,
;       not the one I'm tracking - reject it." It exists purely to stop
;       hijacking a same-colored neighbor's position as if it were drift.
;     - A DIFFERENT-colored neighbor is already excluded by FindFilledBlock's
;       own color filter during track mode (it only searches `lockedColor`)
;       - maxDriftPx only matters when a SECOND instance of the SAME
;         locked color can appear within roughly maxDriftPx of the real
;         target (e.g. two vein patches of the same shade near each other).
;         If every nearby block is a visibly different color (e.g. 4
;         differently-colored ~33x33 blocks in a row), this risk is much
;         lower and maxDriftPx can be set generously.
;     - Measure your real per-tick drift first: watch the log for
;       "found ... but Npx from last position ... rejecting" lines that
;       are clearly still the SAME target (not a real re-acquire) - that
;       N is your floor. In this codebase's own test session, normal
;       camera pan while walking toward a ~77x77 tree needed ~120px of
;       tolerance; 40px was far too tight and caused false "depleted,
;       re-acquire" cascades that could land on a different candidate
;       color entirely (looked like a color-priority bug, wasn't one).
;     - Suggested starting point for a same-size-block-row layout like
;       Motherlode's (several ~30-35px blocks spaced out, each its own
;       color): `trackRadius` ~150-180, `maxDriftPx` ~100-130 (matches
;       the measured-good value above - drift speed is about camera/
;       character movement, not block size). Keep `maxDriftPx` under
;       roughly half of `trackRadius`, and well under the on-screen
;       distance to the nearest SAME-colored duplicate if one exists.
;   stableTicks   - consecutive in-tolerance ticks before "stable" (default 2)
;   moveTolerancePx - px drift still counted "stable" (default 10)
;   cooldownMs    - min ms between clicks once stable (required)
;   reclickAfterMs - re-click cadence while not yet stable (required)
;   ctrl          - hold Ctrl (force-run) while clicking (default false)
;   until         - zero-arg function; loop stops (returns true) once it's true (required)
;   timeoutMs     - ABSOLUTE backstop for the whole phase; loop stops (returns
;                   false) past this no matter what (default 1800000 / 30min)
;   progressTimeoutMs - the REAL safety net; loop stops (returns false) if
;                   nothing has been acquired, depleted, or clicked for this
;                   long (default 300000 / 5min)
;   pollMs        - tick-aligned loop interval (default 300)
;
;   TIMEOUTMS VS PROGRESSTIMEOUTMS (learned live tuning Woodcutting,
;   2026-07-20): a single fixed `timeoutMs` counting the WHOLE phase is the
;   wrong shape for "did this get stuck" - a phase that's working perfectly
;   just legitimately takes longer some runs (farther trees, slower
;   respawns, walking after a bank trip all eat into the same budget), so a
;   tight total-time cap fires on a genuinely healthy run and looks
;   identical in the log to a real stall (confirmed live: a phase that
;   depleted 4 real trees at a completely normal ~2min cadence still hit a
;   600000ms total cap and got killed, because the total was tight, not
;   because anything was wrong). `progressTimeoutMs` fixes this by
;   resetting its clock on any real evidence of activity (an acquire, a
;   depletion, or a click) - it only fires when NOTHING has happened for
;   that long, which is what "stuck" actually means. `timeoutMs` stays as a
;   generous absolute backstop underneath it, purely for the pathological
;   case where something keeps generating progress signals without the
;   until-condition ever actually being reached.
;
; Returns true if `until` became true, false if either timeout fires.
; Throws BotStopped (propagated from Pause) if the user stops mid-loop -
; never swallowed here, same as WaitUntil.
TrackAndClick(opts) {
    colors := opts.colors
    tol := opts.HasOwnProp("tol") ? opts.tol : 5
    blockW := opts.blockW
    blockH := opts.blockH
    verifyPercent := opts.HasOwnProp("verifyPercent") ? opts.verifyPercent : 100
    refX := opts.refX
    refY := opts.refY
    acquireRadii := opts.HasOwnProp("acquireRadii") ? opts.acquireRadii : []
    region := opts.HasOwnProp("region") ? opts.region : [0, 0, A_ScreenWidth - 1, A_ScreenHeight - 1]
    trackRadius := opts.trackRadius
    maxDriftPx := opts.HasOwnProp("maxDriftPx") ? opts.maxDriftPx : 40
    stableTicksRequired := opts.HasOwnProp("stableTicks") ? opts.stableTicks : 2
    moveTolerancePx := opts.HasOwnProp("moveTolerancePx") ? opts.moveTolerancePx : 10
    cooldownMs := opts.cooldownMs
    reclickAfterMs := opts.reclickAfterMs
    useCtrl := opts.HasOwnProp("ctrl") ? opts.ctrl : false
    untilFn := opts.until
    timeoutMs := opts.HasOwnProp("timeoutMs") ? opts.timeoutMs : 1800000
    progressTimeoutMs := opts.HasOwnProp("progressTimeoutMs") ? opts.progressTimeoutMs : 300000
    pollMs := opts.HasOwnProp("pollMs") ? opts.pollMs : 300

    lock := TargetLock(stableTicksRequired, moveTolerancePx)
    hasTarget := false
    targetX := 0, targetY := 0
    lockedColor := colors[1]
    lastClickTime := 0
    t0 := A_TickCount
    lastProgressAt := A_TickCount

    loop {
        if (untilFn()) {
            Say("TrackAndClick: until-condition met (" (A_TickCount - t0) " ms total)")
            return true
        }

        if ((A_TickCount - t0) > timeoutMs) {
            Say("TrackAndClick: OVERALL TIMEOUT after " (A_TickCount - t0) " ms - stopping (until-condition never met)")
            return false
        }

        if ((A_TickCount - lastProgressAt) > progressTimeoutMs) {
            Say("TrackAndClick: NO PROGRESS for " (A_TickCount - lastProgressAt)
                " ms (nothing acquired/depleted/clicked) - stopping (until-condition never met)")
            return false
        }

        if (!hasTarget) {
            ; Acquire mode: expanding rings centered on refX/refY (near ->
            ; far), then the whole screen as the final fallback. Every
            ; color in `colors` is searched in each stage (equal priority,
            ; per AcquireClosestInBox) - a match in an inner ring is by
            ; construction closer than anything only findable in a wider
            ; stage, so stopping at the first stage that finds anything is
            ; both correct AND fast.
            tSearch := A_TickCount
            found := false
            stageLabel := ""
            for radius in acquireRadii {
                rx1 := Max(region[1], refX - radius)
                ry1 := Max(region[2], refY - radius)
                rx2 := Min(region[3], refX + radius)
                ry2 := Min(region[4], refY + radius)

                tStage := A_TickCount
                found := AcquireClosestInBox(rx1, ry1, rx2, ry2, colors, tol, blockW, blockH, verifyPercent, refX, refY, &tx, &ty, &foundColor)
                if (found) {
                    stageLabel := "ring " radius
                    break
                }
                Say("Acquire ring " radius ": not found (" (A_TickCount - tStage) " ms)")
            }
            if (!found) {
                found := AcquireClosestInBox(region[1], region[2], region[3], region[4], colors, tol, blockW, blockH, verifyPercent, refX, refY, &tx, &ty, &foundColor)
                stageLabel := "region-wide"
            }
            searchMs := A_TickCount - tSearch
            if (found) {
                hasTarget := true
                targetX := tx, targetY := ty
                lockedColor := foundColor
                lastClickTime := 0
                lock.Reset()
                lastProgressAt := A_TickCount
                Say("Acquired new target at " tx "," ty " (" HexColor(lockedColor) ", " stageLabel ", " searchMs " ms)")
            } else {
                Say("Acquire: not found (searched " searchMs " ms)")
            }
        } else {
            ; Track mode: narrowed box around the last known position,
            ; locked to whichever color acquire actually matched.
            rx1 := Max(region[1], targetX - trackRadius)
            ry1 := Max(region[2], targetY - trackRadius)
            rx2 := Min(region[3], targetX + trackRadius)
            ry2 := Min(region[4], targetY + trackRadius)

            tSearch := A_TickCount
            found := FindFilledBlock(rx1, ry1, rx2, ry2, lockedColor, tol, blockW, blockH, &nx, &ny, verifyPercent)
            searchMs := A_TickCount - tSearch

            if (found) {
                drift := Max(Abs(nx - targetX), Abs(ny - targetY))
                if (drift > maxDriftPx) {
                    Say("Track: found " HexColor(lockedColor) " block at " nx "," ny " but " drift
                        "px from last position " targetX "," targetY " (max drift " maxDriftPx
                        ") - likely a DIFFERENT block, rejecting")
                    found := false
                }
            }

            ; HARD RULE: never concede depletion/switch targets while the
            ; exact point we've been clicking is still the target color -
            ; a miss this tick can just be transient occlusion.
            if (!found && IsColorAt(targetX, targetY, lockedColor, tol)) {
                Say("Track: search missed this tick, but anchor point " targetX "," targetY
                    " is still " HexColor(lockedColor) " - holding current target, not switching")
                found := true
                nx := targetX, ny := targetY
            }

            lock.Observe(found, found ? nx : 0, found ? ny : 0, &outX, &outY)

            if (!found) {
                Say("Target depleted or lost - re-acquiring (searched " searchMs " ms)")
                hasTarget := false
                targetX := 0, targetY := 0
                lastProgressAt := A_TickCount
            } else {
                targetX := outX, targetY := outY

                if (lock.IsStable()) {
                    if (lastClickTime == 0 || (A_TickCount - lastClickTime) > cooldownMs) {
                        ClickAt(outX, outY, useCtrl)
                        lastClickTime := A_TickCount
                        lastProgressAt := A_TickCount
                        Say("Clicked STABLE target at " outX "," outY " (search " searchMs " ms)")
                    } else {
                        Say("Tracking stable target at " outX "," outY " (cooldown active, search " searchMs " ms)")
                    }
                } else {
                    if (lastClickTime == 0 || (A_TickCount - lastClickTime) > reclickAfterMs) {
                        ClickAt(outX, outY, useCtrl)
                        lastClickTime := A_TickCount
                        lastProgressAt := A_TickCount
                        Say("Clicked initial/re-click target at " outX "," outY " (search " searchMs " ms)")
                    } else {
                        Say("Tracking not-yet-stable target at " outX "," outY " (search " searchMs " ms)")
                    }
                }
            }
        }

        Pause(pollMs)
    }
}

; ---------- target lock (verbatim port of v5 Detection\TargetLock.ahk) ----------

class TargetLock {
    __New(stableTicksRequired, moveTolerancePx, missingTicksToUnlock := 1) {
        this._stableTicksRequired := stableTicksRequired
        this._moveTolerancePx := moveTolerancePx
        this._missingTicksToUnlock := missingTicksToUnlock
        this._hasPosition := false
        this._lastX := 0
        this._lastY := 0
        this._stableTicks := 0
        this._missingTicks := 0
    }

    IsStable() => this._stableTicks >= this._stableTicksRequired

    IsLost() => this._missingTicks >= this._missingTicksToUnlock

    Observe(found, x, y, &outX, &outY) {
        if (!found) {
            this._missingTicks += 1
            outX := this._lastX
            outY := this._lastY
            return false
        }
        this._missingTicks := 0

        isStableTick := this._hasPosition
            && Abs(x - this._lastX) <= this._moveTolerancePx
            && Abs(y - this._lastY) <= this._moveTolerancePx

        this._stableTicks := isStableTick ? this._stableTicks + 1 : 0

        this._lastX := x
        this._lastY := y
        this._hasPosition := true

        outX := x
        outY := y
        return true
    }

    Reset() {
        this._hasPosition := false
        this._stableTicks := 0
        this._missingTicks := 0
    }
}

; ---------- pickup-appeared (the Mark-of-Grace pattern) ----------
;
; opts:
;   imagePath, imageW, imageH   - the appeared item's image (required)
;   imageTol      - shade-of-variation tolerance (default 5)
;   transColor    - background see-through color, "" to disable (default "")
;   region        - [x1,y1,x2,y2] to search for the image (default whole screen)
;   appearTimeoutMs - give up if the image never appears (required)
;   clickOffsetX/Y  - offset from the found image's center to the actual click point (default 0,0)
;   ctrl          - hold Ctrl (force-run) while clicking (default false)
;   confirmBox    - {x, y, w, h} snapshotted BEFORE the click, polled AFTER (required)
;   changeTol     - per-channel tolerance before a pixel counts as "changed" (default 10)
;   targetSamples - sample budget for the confirm box snapshot (default 50)
;   confirmTimeoutMs - give up waiting for the pickup to register (required)
;   pollMs        - tick-aligned poll interval for both waits (default 300)
;
; Returns true if the confirm box changed after the click (pickup
; confirmed), false if the image never appeared or the box never
; changed. Throws BotStopped (propagated from WaitUntil/Pause) if the
; user stops mid-flow - never swallowed here.
PickupAppeared(opts) {
    imagePath := opts.imagePath
    imageW := opts.imageW
    imageH := opts.imageH
    imageTol := opts.HasOwnProp("imageTol") ? opts.imageTol : 5
    transColor := opts.HasOwnProp("transColor") ? opts.transColor : ""
    region := opts.HasOwnProp("region") ? opts.region : [0, 0, A_ScreenWidth - 1, A_ScreenHeight - 1]
    appearTimeoutMs := opts.appearTimeoutMs
    clickOffsetX := opts.HasOwnProp("clickOffsetX") ? opts.clickOffsetX : 0
    clickOffsetY := opts.HasOwnProp("clickOffsetY") ? opts.clickOffsetY : 0
    useCtrl := opts.HasOwnProp("ctrl") ? opts.ctrl : false
    box := opts.confirmBox
    changeTol := opts.HasOwnProp("changeTol") ? opts.changeTol : 10
    targetSamples := opts.HasOwnProp("targetSamples") ? opts.targetSamples : 50
    confirmTimeoutMs := opts.confirmTimeoutMs
    pollMs := opts.HasOwnProp("pollMs") ? opts.pollMs : 300

    foundX := 0, foundY := 0
    ImageAppeared() {
        found := FindImage(region[1], region[2], region[3], region[4], imagePath, imageW, imageH, imageTol, transColor, &fx, &fy)
        if (found) {
            foundX := fx, foundY := fy
        }
        return found
    }

    t0 := A_TickCount
    appeared := WaitUntil(ImageAppeared, appearTimeoutMs, pollMs)
    if (!appeared) {
        Say("PickupAppeared: NEVER APPEARED after " (A_TickCount - t0) " ms - giving up")
        return false
    }

    clickX := foundX + clickOffsetX
    clickY := foundY + clickOffsetY
    LogLine("PickupAppeared: appeared at " foundX "," foundY " after " (A_TickCount - t0) " ms - snapshotting confirm box BEFORE click")

    ; Snapshot BEFORE the click - the "before" state is what lets
    ; HasChanged detect a change caused by the click, not just any change.
    snapshot := TakeSnapshot(box.x, box.y, box.w, box.h, targetSamples)

    Say("PickupAppeared: clicking item at " clickX "," clickY)
    ClickAt(clickX, clickY, useCtrl)

    BoxChangedNow() {
        return HasChanged(snapshot, box.x, box.y, changeTol)
    }

    t1 := A_TickCount
    confirmed := WaitUntil(BoxChangedNow, confirmTimeoutMs, pollMs)
    if (confirmed) {
        Say("PickupAppeared: CONFIRMED (" (A_TickCount - t1) " ms after click, " (A_TickCount - t0) " ms total)")
        return true
    }
    Say("PickupAppeared: CLICKED but NOT CONFIRMED - box never changed within " confirmTimeoutMs "ms")
    return false
}

; ---------- find-and-click (one-shot marker/image click, no tracking) ----------
;
; The "wait for a one-shot marker to appear, then click it" shape -
; promoted here (2026-07-20) after appearing independently 5 times
; (block variant: Motherlode's hopper/entrance/bank-marker/exit clicks,
; Woodcutting's bank-marker click) and 3 times (image variant:
; Motherlode's sack/deposit-image clicks, Woodcutting's deposit-image
; click). Pure mechanical extraction of the closure+WaitUntil+ClickAt
; shape those call sites already had - no new logic. Unlike
; PickupAppeared above, there's no before/after confirm-box diff here;
; callers that need to confirm the click registered do that separately
; (e.g. AllSlotsFull/AllSlotsEmpty, !SlotFull, AnySlotEmpty).
;
; Common opts for both:
;   region        - [x1,y1,x2,y2] to search (default whole screen)
;   clickOffsetX/Y - offset applied to the click point before clicking
;                   (default 0,0) - e.g. Motherlode's MLBANK_CLICK_OFFSET_Y
;   clickX/clickY - click HERE instead of the live-found position (default:
;                   click wherever Find*/ImageSearch actually matched). Use
;                   this for a static UI marker whose exact screen position
;                   is already known/measured - Find* still gates the wait
;                   (confirms something matching is actually visible before
;                   clicking) but a search region is inherently loose (only
;                   guarantees SOME WxH/image match inside it, not that the
;                   match's own reported center is exactly your measured
;                   point - e.g. if the true on-screen colored area is
;                   larger than the declared block size, multiple positions
;                   satisfy the search and ImageSearch returns whichever it
;                   hits first, not necessarily centered on the real target).
;                   Omit for a genuinely moving/variable-position target
;                   (e.g. Motherlode's world markers) where the found
;                   position IS the only correct click point.
;   ctrl          - hold Ctrl (force-run) while clicking (default false)
;   waitTimeoutMs - give up if the marker/image never appears (required)
;   pollMs        - tick-aligned poll interval (default 300)
;   label         - Say()/log message prefix, e.g. "Hopper" (default the function name)
;   itemLabel     - what's being searched/clicked, e.g. "hopper marker" (default "target")
;
; Returns true if found+clicked, false (logged, no throw) if it never
; appeared within waitTimeoutMs. Throws BotStopped (propagated from
; WaitUntil/Pause) if the user stops mid-wait - never swallowed here,
; same as every other wait in this codebase.
FindAndClickBlock(opts) {
    color := opts.color
    tol := opts.tol
    blockW := opts.blockW
    blockH := opts.blockH
    region := opts.HasOwnProp("region") ? opts.region : [0, 0, A_ScreenWidth - 1, A_ScreenHeight - 1]
    clickOffsetX := opts.HasOwnProp("clickOffsetX") ? opts.clickOffsetX : 0
    clickOffsetY := opts.HasOwnProp("clickOffsetY") ? opts.clickOffsetY : 0
    useCtrl := opts.HasOwnProp("ctrl") ? opts.ctrl : false
    waitTimeoutMs := opts.waitTimeoutMs
    pollMs := opts.HasOwnProp("pollMs") ? opts.pollMs : 300
    label := opts.HasOwnProp("label") ? opts.label : "FindAndClickBlock"
    itemLabel := opts.HasOwnProp("itemLabel") ? opts.itemLabel : "target"

    foundX := 0, foundY := 0
    Visible() {
        found := FindFilledBlock(region[1], region[2], region[3], region[4], color, tol, blockW, blockH, &fx, &fy)
        if (found) {
            foundX := fx, foundY := fy
        }
        return found
    }

    Say(label ": waiting for " itemLabel)
    found := WaitUntil(Visible, waitTimeoutMs, pollMs)
    if (!found) {
        Say(label ": " itemLabel " never appeared within " waitTimeoutMs "ms - stopping")
        return false
    }

    targetX := opts.HasOwnProp("clickX") ? opts.clickX : foundX
    targetY := opts.HasOwnProp("clickY") ? opts.clickY : foundY
    clickX := targetX + clickOffsetX
    clickY := targetY + clickOffsetY
    Say(label ": clicking " itemLabel " at " clickX "," clickY)
    ClickAt(clickX, clickY, useCtrl)
    return true
}

; ---------- click-until-condition (patient first wait, then re-click) ----------
;
; The "click a thing, wait patiently for a condition, and if it doesn't
; hold yet re-click every N ms until it does" shape - promoted here
; (2026-07-21) once it appeared in BOTH Motherlode2's DepositHopper()
; (hopper deposit, capped retry budget) and WithdrawAndBankOnce() (sack
; withdrawal, uncapped retry). It exists because these targets are
; SHARED/laggy: one click doesn't always register the effect right away
; (a backed-up hopper still draining, sack items arriving late), so the
; first click gets a generous patient wait and only on a miss does it
; downgrade to hammering re-clicks - never spamming when one click was
; enough.
;
; opts:
;   click         - zero-arg closure that performs the click and returns
;                   bool; false means the marker/image never appeared, so
;                   abort the whole thing (required). Callers pass e.g.
;                   () => FindAndClickBlock({...}) or () => FindAndClickImage({...}).
;   condition     - zero-arg closure; the loop succeeds (returns true) the
;                   instant this is true (required)
;   firstWaitMs   - patient wait after the FIRST click (required)
;   reclickMs     - wait between re-clicks after that first wait (required)
;   firstSettleMs - optional Pause right after the FIRST click, BEFORE its
;                   wait, for a target whose follow-up UI needs a moment to
;                   settle (default 0 = none)
;   totalTimeoutMs- 0 = retry forever; >0 = give up + return false once this
;                   much time has elapsed across the whole loop (default 0)
;   pollMs        - tick-aligned poll interval for the condition wait (default 300)
;   label         - Say()/log prefix (default "ClickUntilCondition")
;   itemLabel     - what's being waited on, e.g. "inventory to clear" (default "condition")
;
; &neededRetry (optional out) - set true if the loop ever had to re-click
;   past the first wait (a caller that cares - like the hopper's
;   g_HopperWasFull stall heuristic - reads it; one that doesn't - like the
;   sack - just omits the argument entirely).
;
; Returns true once `condition` holds, false if `click()` ever fails or
; totalTimeoutMs is exceeded. Throws BotStopped (propagated from the inner
; click's WaitUntil, from WaitUntil(condition,...), and from Pause) if the
; user stops mid-loop - never swallowed here, same as every other wait.
ClickUntilCondition(opts, &neededRetry?) {
    click := opts.click
    condition := opts.condition
    firstWaitMs := opts.firstWaitMs
    reclickMs := opts.reclickMs
    firstSettleMs := opts.HasOwnProp("firstSettleMs") ? opts.firstSettleMs : 0
    totalTimeoutMs := opts.HasOwnProp("totalTimeoutMs") ? opts.totalTimeoutMs : 0
    pollMs := opts.HasOwnProp("pollMs") ? opts.pollMs : 300
    label := opts.HasOwnProp("label") ? opts.label : "ClickUntilCondition"
    itemLabel := opts.HasOwnProp("itemLabel") ? opts.itemLabel : "condition"

    neededRetry := false
    t0 := A_TickCount
    firstAttempt := true
    loop {
        if (!click())
            return false

        if (firstAttempt && firstSettleMs > 0) {
            Say(label ": settling " firstSettleMs "ms before checking " itemLabel)
            Pause(firstSettleMs)
        }

        waitMs := firstAttempt ? firstWaitMs : reclickMs
        firstAttempt := false
        if (WaitUntil(condition, waitMs, pollMs))
            return true

        neededRetry := true

        if (totalTimeoutMs > 0 && (A_TickCount - t0) > totalTimeoutMs) {
            Say(label ": " itemLabel " not met after " totalTimeoutMs "ms total - stopping")
            return false
        }
        Say(label ": " itemLabel " not met after " (A_TickCount - t0) "ms - re-clicking")
    }
}

; ---------- travel-to-point (click a travel marker, confirm arrival) ----------
;
; The "click a travel marker, then wait for a block to show up at an EXACT
; expected point (not just anywhere on screen), with a whole-screen
; diagnostic on failure" shape - promoted here (2026-07-21) from
; Motherlode2's GoToSackArea() and ReturnToMine(), which are identical
; apart from their marker/arrival constants. Reuses FindAndClickBlock for
; the click and BlockAtPoint for the exact-point arrival; the whole-screen
; FindFilledBlock fallback on a miss (found-elsewhere vs not-found-anywhere)
; lives here so every caller gets that same debugging aid for free.
;
; opts (flat, house style):
;   markerColor/markerTol/markerBlockW/markerBlockH - the travel marker block (required)
;   markerWaitTimeoutMs   - give up if the marker never appears (required)
;   markerRegion          - [x1,y1,x2,y2] to search for the marker (default whole screen)
;   markerClickOffsetX/Y  - offset applied to the marker's found center before clicking
;                           (default 0,0) - e.g. when the marker's raw center isn't the
;                           real clickable spot
;   markerItemLabel       - label for the marker in logs (default "travel marker")
;   arriveColor/arriveTol/arriveBlockW/arriveBlockH - the arrival block (required)
;   arriveCornerX/arriveCornerY - the arrival block's measured top-left CORNER
;                           (required) - the expected CENTER is computed here via
;                           Lib\Core.ahk's CenterX/CenterY, never stored by the caller
;   arrivePosTolPx        - slack around that center (BlockAtPoint's posTolPx) (required)
;   arriveWaitTimeoutMs   - give up if arrival never confirms (required)
;   ctrl                  - hold Ctrl while clicking the marker (default false)
;   pollMs                - poll interval for the arrival wait (default 300)
;   label                 - Say()/log prefix (default "TravelToPoint")
;
; Returns true on confirmed arrival, false (logged, no throw) if the marker
; never appears or arrival never confirms. Throws BotStopped if the user
; stops mid-travel - never swallowed here.
TravelToPoint(opts) {
    markerColor := opts.markerColor
    markerTol := opts.markerTol
    markerBlockW := opts.markerBlockW
    markerBlockH := opts.markerBlockH
    markerWaitTimeoutMs := opts.markerWaitTimeoutMs
    markerRegion := opts.HasOwnProp("markerRegion") ? opts.markerRegion : [0, 0, A_ScreenWidth - 1, A_ScreenHeight - 1]
    markerClickOffsetX := opts.HasOwnProp("markerClickOffsetX") ? opts.markerClickOffsetX : 0
    markerClickOffsetY := opts.HasOwnProp("markerClickOffsetY") ? opts.markerClickOffsetY : 0
    markerItemLabel := opts.HasOwnProp("markerItemLabel") ? opts.markerItemLabel : "travel marker"
    arriveColor := opts.arriveColor
    arriveTol := opts.arriveTol
    arriveBlockW := opts.arriveBlockW
    arriveBlockH := opts.arriveBlockH
    arriveX := CenterX(opts.arriveCornerX, arriveBlockW)
    arriveY := CenterY(opts.arriveCornerY, arriveBlockH)
    arrivePosTolPx := opts.arrivePosTolPx
    arriveWaitTimeoutMs := opts.arriveWaitTimeoutMs
    useCtrl := opts.HasOwnProp("ctrl") ? opts.ctrl : false
    pollMs := opts.HasOwnProp("pollMs") ? opts.pollMs : 300
    label := opts.HasOwnProp("label") ? opts.label : "TravelToPoint"

    if (!FindAndClickBlock({
        color: markerColor, tol: markerTol, blockW: markerBlockW, blockH: markerBlockH,
        region: markerRegion, clickOffsetX: markerClickOffsetX, clickOffsetY: markerClickOffsetY,
        ctrl: useCtrl, waitTimeoutMs: markerWaitTimeoutMs, pollMs: pollMs,
        label: label, itemLabel: markerItemLabel
    }))
        return false

    ArrivedAtPoint() {
        return BlockAtPoint(arriveX, arriveY, arriveColor, arriveTol,
            arriveBlockW, arriveBlockH, arrivePosTolPx, &fx, &fy)
    }

    Say(label ": waiting for arrival")
    arrived := WaitUntil(ArrivedAtPoint, arriveWaitTimeoutMs, pollMs)
    if (!arrived) {
        wholeScreenFound := FindFilledBlock(0, 0, A_ScreenWidth - 1, A_ScreenHeight - 1,
            arriveColor, arriveTol, arriveBlockW, arriveBlockH, &wx, &wy)
        if (wholeScreenFound) {
            Say(label ": never arrived within " arriveWaitTimeoutMs "ms - but marker WAS found"
                . " elsewhere on screen at " wx "," wy " (expected near " arriveX "," arriveY ") - stopping")
        } else {
            Say(label ": never arrived within " arriveWaitTimeoutMs
                . "ms - marker not found ANYWHERE on screen, not just near the expected point - stopping")
        }
        return false
    }

    Say(label ": arrived")
    return true
}

; Same shape as FindAndClickBlock but for a PNG (FindImage) instead of
; a solid color block.
;
; Additional/different opts:
;   imagePath, imageW, imageH  - required, the image's real pixel size
;   tol           - shade-of-variation tolerance (default 5)
;   transColor    - background see-through color, "" to disable (default "")
; (region/clickOffsetX/Y/ctrl/waitTimeoutMs/pollMs/label/itemLabel same as FindAndClickBlock)
FindAndClickImage(opts) {
    imagePath := opts.imagePath
    imageW := opts.imageW
    imageH := opts.imageH
    tol := opts.HasOwnProp("tol") ? opts.tol : 5
    transColor := opts.HasOwnProp("transColor") ? opts.transColor : ""
    region := opts.HasOwnProp("region") ? opts.region : [0, 0, A_ScreenWidth - 1, A_ScreenHeight - 1]
    clickOffsetX := opts.HasOwnProp("clickOffsetX") ? opts.clickOffsetX : 0
    clickOffsetY := opts.HasOwnProp("clickOffsetY") ? opts.clickOffsetY : 0
    useCtrl := opts.HasOwnProp("ctrl") ? opts.ctrl : false
    waitTimeoutMs := opts.waitTimeoutMs
    pollMs := opts.HasOwnProp("pollMs") ? opts.pollMs : 300
    label := opts.HasOwnProp("label") ? opts.label : "FindAndClickImage"
    itemLabel := opts.HasOwnProp("itemLabel") ? opts.itemLabel : "target"

    foundX := 0, foundY := 0
    Visible() {
        found := FindImage(region[1], region[2], region[3], region[4], imagePath, imageW, imageH, tol, transColor, &fx, &fy)
        if (found) {
            foundX := fx, foundY := fy
        }
        return found
    }

    Say(label ": waiting for " itemLabel)
    found := WaitUntil(Visible, waitTimeoutMs, pollMs)
    if (!found) {
        Say(label ": " itemLabel " never appeared within " waitTimeoutMs "ms - stopping")
        return false
    }

    targetX := opts.HasOwnProp("clickX") ? opts.clickX : foundX
    targetY := opts.HasOwnProp("clickY") ? opts.clickY : foundY
    clickX := targetX + clickOffsetX
    clickY := targetY + clickOffsetY
    Say(label ": clicking " itemLabel " at " clickX "," clickY)
    ClickAt(clickX, clickY, useCtrl)
    return true
}

; ---------- deposit-all-to-bank (marker -> deposit image -> confirm) ----------
;
; The "click a bank/deposit marker, click the deposit-all image, then
; (optionally) confirm the inventory actually emptied" shape - promoted
; here (2026-07-21) once it existed in Woodcutting's Bank(), Motherlode2's
; WithdrawAndBankOnce() tail, and Crafting's deposit steps. The confirm
; step is OPTIONAL: Woodcutting/Motherlode2 verify the deposit registered
; (via a caller-supplied condition), Crafting just deposits and moves on
; to restocking, so it omits the condition. Marker/deposit searches take
; an optional region (Crafting constrains both to a small box; the others
; search whole-screen).
;
; opts:
;   markerColor/markerTol/markerBlockW/markerBlockH - the bank/deposit marker (required)
;   markerWaitTimeoutMs   - give up if the marker never appears (required)
;   markerRegion          - [x1,y1,x2,y2] to search for the marker (default whole screen)
;   markerClickOffsetY    - Y offset applied to the marker click (default 0)
;   markerClickX/markerClickY - click HERE instead of the live-found marker
;                           position (default: found position) - see
;                           FindAndClickBlock's clickX/clickY doc; use for a
;                           static marker whose exact position is known
;   markerItemLabel       - log label (default "deposit-box marker")
;   depositImagePath/depositImageW/depositImageH - the "deposit all" image (required)
;   depositTol            - shade-of-variation tolerance (default 5)
;   depositTransColor     - background see-through color, "" to disable (default "")
;   depositWaitTimeoutMs  - give up if the deposit box never opens (required)
;   depositRegion         - [x1,y1,x2,y2] to search for the image (default whole screen)
;   depositClickX/depositClickY - same idea as markerClickX/Y, for the
;                           deposit-image click (default: found position)
;   depositItemLabel      - log label (default "deposit box")
;   confirmCondition      - OPTIONAL zero-arg closure; true once the deposit registered.
;                           Omit to skip the confirm step (return true right after the
;                           deposit click).
;   confirmTimeoutMs      - how long to wait for confirmCondition (required only if it's given)
;   ctrl                  - hold Ctrl while clicking (default false)
;   pollMs                - poll interval (default 300)
;   label                 - Say()/log prefix (default "DepositAllToBank")
;
; Returns true if the marker + deposit both clicked (and confirmCondition
; held within confirmTimeoutMs, when given); false (logged, no throw)
; otherwise. Throws BotStopped if the user stops mid-deposit - never
; swallowed here.
DepositAllToBank(opts) {
    wholeScreen := [0, 0, A_ScreenWidth - 1, A_ScreenHeight - 1]
    markerRegion := opts.HasOwnProp("markerRegion") ? opts.markerRegion : wholeScreen
    depositRegion := opts.HasOwnProp("depositRegion") ? opts.depositRegion : wholeScreen
    markerClickOffsetY := opts.HasOwnProp("markerClickOffsetY") ? opts.markerClickOffsetY : 0
    markerItemLabel := opts.HasOwnProp("markerItemLabel") ? opts.markerItemLabel : "deposit-box marker"
    depositTol := opts.HasOwnProp("depositTol") ? opts.depositTol : 5
    depositTransColor := opts.HasOwnProp("depositTransColor") ? opts.depositTransColor : ""
    depositItemLabel := opts.HasOwnProp("depositItemLabel") ? opts.depositItemLabel : "deposit box"
    useCtrl := opts.HasOwnProp("ctrl") ? opts.ctrl : false
    pollMs := opts.HasOwnProp("pollMs") ? opts.pollMs : 300
    label := opts.HasOwnProp("label") ? opts.label : "DepositAllToBank"

    markerOpts := {
        color: opts.markerColor, tol: opts.markerTol, blockW: opts.markerBlockW, blockH: opts.markerBlockH,
        region: markerRegion, clickOffsetY: markerClickOffsetY, ctrl: useCtrl,
        waitTimeoutMs: opts.markerWaitTimeoutMs, pollMs: pollMs, label: label, itemLabel: markerItemLabel
    }
    if (opts.HasOwnProp("markerClickX"))
        markerOpts.clickX := opts.markerClickX
    if (opts.HasOwnProp("markerClickY"))
        markerOpts.clickY := opts.markerClickY
    if (!FindAndClickBlock(markerOpts))
        return false

    depositOpts := {
        imagePath: opts.depositImagePath, imageW: opts.depositImageW, imageH: opts.depositImageH,
        tol: depositTol, transColor: depositTransColor, region: depositRegion, ctrl: useCtrl,
        waitTimeoutMs: opts.depositWaitTimeoutMs, pollMs: pollMs, label: label, itemLabel: depositItemLabel
    }
    if (opts.HasOwnProp("depositClickX"))
        depositOpts.clickX := opts.depositClickX
    if (opts.HasOwnProp("depositClickY"))
        depositOpts.clickY := opts.depositClickY
    if (!FindAndClickImage(depositOpts))
        return false

    if (!opts.HasOwnProp("confirmCondition"))
        return true

    Say(label ": waiting for inventory to confirm the deposit")
    if (!WaitUntil(opts.confirmCondition, opts.confirmTimeoutMs, pollMs)) {
        Say(label ": deposit not confirmed within " opts.confirmTimeoutMs "ms - stopping (may not have registered)")
        return false
    }

    Say(label ": deposit confirmed")
    return true
}

; ---------- withdraw plan (restock N clicks per bank slot) ----------
;
; Runs a "withdraw plan" - a list of [slot, clicks] pairs (same shape
; TEMPLATES.md's Firemaking/Smelter specs call "for each (slot, clicks):
; Click [bank slot N] x clicks"). Promoted here (2026-07-22) once it
; existed independently in Crafting's and Smithing's restock steps.
; BankSlotCenter (Lib\Inv.ahk) maps each entry's slot to a screen point,
; clicked that many times before moving to the next entry - no fullness
; check, matches what was asked for exactly.
RunRestockPlan(plan, ctrl := false) {
    for entry in plan {
        BankSlotCenter(entry[1], &x, &y)
        loop entry[2]
            ClickAt(x, y, ctrl)
    }
}

; ---------- region-around-a-corner (small search box, not whole-screen) ----------
;
; Constrains a find to a small box around a known top-left corner instead
; of a whole-screen search. Built directly from the corner - no center
; step needed for a bounding box, just corner-margin to corner+size+margin.
; Promoted here (2026-07-22) once it existed byte-identical in Crafting
; and Smithing (each with its own SEARCH_MARGIN_PX global) - marginPx is
; now an explicit param instead, so callers stay free to tune it per-bot
; without a naming collision. Clamps to 0 so a corner near the screen
; edge (e.g. Crafting's CRAFT_START at 176,715) doesn't push the region
; negative - ImageSearch can't take that.
RegionAround(cornerX, cornerY, w, h, marginPx := 40) {
    x1 := Max(0, cornerX - marginPx)
    y1 := Max(0, cornerY - marginPx)
    return [x1, y1, cornerX + w + marginPx, cornerY + h + marginPx]
}
