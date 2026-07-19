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
;                   the whole-screen fallback (default [] = whole screen only)
;   trackRadius   - half-size of the narrowed re-search box once locked (required)
;   maxDriftPx    - reject a track match this far from the last position (default 40)
;   stableTicks   - consecutive in-tolerance ticks before "stable" (default 2)
;   moveTolerancePx - px drift still counted "stable" (default 10)
;   cooldownMs    - min ms between clicks once stable (required)
;   reclickAfterMs - re-click cadence while not yet stable (required)
;   ctrl          - hold Ctrl (force-run) while clicking (default false)
;   until         - zero-arg function; loop stops (returns true) once it's true (required)
;   timeoutMs     - overall failsafe; loop stops (returns false) past this (default 600000)
;   pollMs        - tick-aligned loop interval (default 300)
;
; Returns true if `until` became true, false on overall timeout. Throws
; BotStopped (propagated from Pause) if the user stops mid-loop - never
; swallowed here, same as WaitUntil.
TrackAndClick(opts) {
    colors := opts.colors
    tol := opts.HasOwnProp("tol") ? opts.tol : 5
    blockW := opts.blockW
    blockH := opts.blockH
    verifyPercent := opts.HasOwnProp("verifyPercent") ? opts.verifyPercent : 100
    refX := opts.refX
    refY := opts.refY
    acquireRadii := opts.HasOwnProp("acquireRadii") ? opts.acquireRadii : []
    trackRadius := opts.trackRadius
    maxDriftPx := opts.HasOwnProp("maxDriftPx") ? opts.maxDriftPx : 40
    stableTicksRequired := opts.HasOwnProp("stableTicks") ? opts.stableTicks : 2
    moveTolerancePx := opts.HasOwnProp("moveTolerancePx") ? opts.moveTolerancePx : 10
    cooldownMs := opts.cooldownMs
    reclickAfterMs := opts.reclickAfterMs
    useCtrl := opts.HasOwnProp("ctrl") ? opts.ctrl : false
    untilFn := opts.until
    timeoutMs := opts.HasOwnProp("timeoutMs") ? opts.timeoutMs : 600000
    pollMs := opts.HasOwnProp("pollMs") ? opts.pollMs : 300

    lock := TargetLock(stableTicksRequired, moveTolerancePx)
    hasTarget := false
    targetX := 0, targetY := 0
    lockedColor := colors[1]
    lastClickTime := 0
    t0 := A_TickCount

    loop {
        if (untilFn()) {
            Say("TrackAndClick: until-condition met (" (A_TickCount - t0) " ms total)")
            return true
        }

        if ((A_TickCount - t0) > timeoutMs) {
            Say("TrackAndClick: OVERALL TIMEOUT after " (A_TickCount - t0) " ms - stopping (until-condition never met)")
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
                rx1 := Max(0, refX - radius)
                ry1 := Max(0, refY - radius)
                rx2 := Min(A_ScreenWidth - 1, refX + radius)
                ry2 := Min(A_ScreenHeight - 1, refY + radius)

                tStage := A_TickCount
                found := AcquireClosestInBox(rx1, ry1, rx2, ry2, colors, tol, blockW, blockH, verifyPercent, refX, refY, &tx, &ty, &foundColor)
                if (found) {
                    stageLabel := "ring " radius
                    break
                }
                Say("Acquire ring " radius ": not found (" (A_TickCount - tStage) " ms)")
            }
            if (!found) {
                found := AcquireClosestInBox(0, 0, A_ScreenWidth - 1, A_ScreenHeight - 1, colors, tol, blockW, blockH, verifyPercent, refX, refY, &tx, &ty, &foundColor)
                stageLabel := "whole screen"
            }
            searchMs := A_TickCount - tSearch
            if (found) {
                hasTarget := true
                targetX := tx, targetY := ty
                lockedColor := foundColor
                lastClickTime := 0
                lock.Reset()
                Say("Acquired new target at " tx "," ty " (" HexColor(lockedColor) ", " stageLabel ", " searchMs " ms)")
            } else {
                Say("Acquire: not found (searched " searchMs " ms)")
            }
        } else {
            ; Track mode: narrowed box around the last known position,
            ; locked to whichever color acquire actually matched.
            rx1 := Max(0, targetX - trackRadius)
            ry1 := Max(0, targetY - trackRadius)
            rx2 := Min(A_ScreenWidth - 1, targetX + trackRadius)
            ry2 := Min(A_ScreenHeight - 1, targetY + trackRadius)

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
            } else {
                targetX := outX, targetY := outY

                if (lock.IsStable()) {
                    if (lastClickTime == 0 || (A_TickCount - lastClickTime) > cooldownMs) {
                        ClickAt(outX, outY, useCtrl)
                        lastClickTime := A_TickCount
                        Say("Clicked STABLE target at " outX "," outY " (search " searchMs " ms)")
                    } else {
                        Say("Tracking stable target at " outX "," outY " (cooldown active, search " searchMs " ms)")
                    }
                } else {
                    if (lastClickTime == 0 || (A_TickCount - lastClickTime) > reclickAfterMs) {
                        ClickAt(outX, outY, useCtrl)
                        lastClickTime := A_TickCount
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
