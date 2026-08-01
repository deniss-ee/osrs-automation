; ============================================================
; v7 Lib\Steps.ahk - composite building blocks (search + action)
;
; Every composite takes ONE opts object (standard #13); primitives stay
; positional. Shared field names: path/w/h/tol/transColor (image spec),
; colors/tol/blockW/blockH (block spec), region, ctrl, settleMs,
; waitTimeoutMs, pollMs (default POLL_MS_DEFAULT), label, itemLabel,
; preDelayMs/postDelayMs (default 0, standard #8).
;
; clickOffsetX/Y do NOT exist (standard #6) - a mis-click means
; re-measure. clickX/clickY PINNING (click a static point after the
; search confirms presence) is the legitimate concept that stays.
;
; Every composite returns false (logged, no throw) on its own failure
; and lets BotStopped propagate from Pause/WaitUntil - never swallowed.
; ============================================================

; ---------- right-click -> context menu -> click entry ----------
;
; Right-clicks (x,y), waits for the menu-entry image inside a
; searchBoxSize box centered on the click point, clicks its center.
; Sends Esc to close the menu if the entry never appears.
; settleMs covers BOTH clicks; menuSettleMs is the gap after the
; right-click before the FIRST search (without it the first search
; reliably misses the still-rendering menu - see standard #11).
; ctrl applies only to the follow-up left-click.
;
; opts: x/y, path/w/h/tol/transColor, waitTimeoutMs (required);
;   searchBoxSize 512, settleMs 100, menuSettleMs 100, ctrl false,
;   pollMs 150 (NOT POLL_MS_DEFAULT - measured live: the context menu
;   takes at least ~150ms to open after the right-click, so polling
;   faster only burns searches on a menu that can't be there yet),
;   blockW/blockH (optional - the right-click target's own size, for
;   proportional click jitter; omit if x/y is an arbitrary point with
;   no known size), label, preDelayMs/postDelayMs.
; Both clicks are jittered (standard #29): the right-click by
; blockW/blockH if given (else the flat default), the menu-item click
; by the item image's own w/h.
RightClickMenuItem(opts) {
    x := opts.x
    y := opts.y
    settleMs := Opt(opts, "settleMs", 100)
    menuSettleMs := Opt(opts, "menuSettleMs", 100)
    searchBoxSize := Opt(opts, "searchBoxSize", 512)
    pollMs := Opt(opts, "pollMs", 150)
    useCtrl := Opt(opts, "ctrl", false)
    label := Opt(opts, "label", "RightClickMenuItem")
    preDelayMs := Opt(opts, "preDelayMs", 0)
    postDelayMs := Opt(opts, "postDelayMs", 0)
    targetJitterPx := (opts.HasOwnProp("blockW") && opts.HasOwnProp("blockH"))
        ? BlockJitterPx(opts.blockW, opts.blockH) : -1

    if (preDelayMs > 0)
        Pause(preDelayMs)

    ReleasePendingModifiersNow()

    JitterPoint(x, y, targetJitterPx, &jx, &jy)
    HumanMove(jx, jy)
    Sleep(settleMs)
    Click("Right")
    Sleep(menuSettleMs)

    region := RegionAround(x, y, 0, 0, searchBoxSize // 2)
    cx := 0, cy := 0
    ItemVisible() {
        return FindImage(region[1], region[2], region[3], region[4],
            opts.path, opts.w, opts.h, opts.tol, opts.transColor, &cx, &cy)
    }

    if (!WaitUntil(ItemVisible, opts.waitTimeoutMs, pollMs)) {
        LogLine(label ": item not found in menu (" opts.path "), closing menu")
        Send("{Esc}")
        return false
    }

    LogLine(label ": found menu item at " cx "," cy)
    ClickAt(cx, cy, useCtrl, false, settleMs, 100, 0, 0, BlockJitterPx(opts.w, opts.h))

    if (postDelayMs > 0)
        Pause(postDelayMs)
    return true
}

; ---------- wait-then-click engine (shared by block/image variants) ----------
;
; findFn(&fx,&fy) is the only difference between FindAndClickBlock and
; FindAndClickImage - everything else (wait, pin-or-found click, delays,
; logging) lives once here. Click jitter (standard #29) is proportional
; to whatever size opts carries - blockW/blockH (FindAndClickBlock) or
; w/h (FindAndClickImage) - both flow through untouched from the
; caller's opts, so this reads whichever pair is actually present.
WaitThenClick(findFn, opts, defaultLabel) {
    useCtrl := Opt(opts, "ctrl", false)
    pollMs := Opt(opts, "pollMs", POLL_MS_DEFAULT)
    settleMs := Opt(opts, "settleMs", 100)
    label := Opt(opts, "label", defaultLabel)
    itemLabel := Opt(opts, "itemLabel", "target")
    preDelayMs := Opt(opts, "preDelayMs", 0)
    postDelayMs := Opt(opts, "postDelayMs", 0)
    jitterPx := -1
    if (opts.HasOwnProp("blockW") && opts.HasOwnProp("blockH"))
        jitterPx := BlockJitterPx(opts.blockW, opts.blockH)
    else if (opts.HasOwnProp("w") && opts.HasOwnProp("h"))
        jitterPx := BlockJitterPx(opts.w, opts.h)

    if (preDelayMs > 0)
        Pause(preDelayMs)

    foundX := 0, foundY := 0
    Visible() {
        found := findFn(&fx, &fy)
        if (found)
            foundX := fx, foundY := fy
        return found
    }

    Say(label ": waiting for " itemLabel)
    if (!WaitUntil(Visible, opts.waitTimeoutMs, pollMs)) {
        Say(label ": " itemLabel " never appeared within " opts.waitTimeoutMs "ms - stopping")
        return false
    }

    targetX := Opt(opts, "clickX", foundX)
    targetY := Opt(opts, "clickY", foundY)
    Say(label ": clicking " itemLabel " at " targetX "," targetY)
    ClickAt(targetX, targetY, useCtrl, false, settleMs, 100, 0, 0, jitterPx)

    if (postDelayMs > 0)
        Pause(postDelayMs)
    return true
}

; Wait for a color block (any of opts.colors), click it (or the
; clickX/clickY pin). opts: colors/tol/blockW/blockH, waitTimeoutMs
; (required); verifyPercent 100, region (whole screen), clickX/clickY,
; ctrl, pollMs, settleMs, label, itemLabel, preDelayMs/postDelayMs.
FindAndClickBlock(opts) {
    region := Opt(opts, "region", ScreenRegion())
    verifyPercent := Opt(opts, "verifyPercent", 100)
    Find(&fx, &fy) {
        return FindAnyFilledBlock(region[1], region[2], region[3], region[4],
            opts.colors, opts.tol, opts.blockW, opts.blockH, &fx, &fy, &fc, verifyPercent)
    }
    return WaitThenClick(Find, opts, "FindAndClickBlock")
}

; PNG sibling of FindAndClickBlock. opts: path/w/h/tol/transColor,
; waitTimeoutMs (required); region, clickX/clickY, ctrl, pollMs,
; settleMs, label, itemLabel, preDelayMs/postDelayMs.
FindAndClickImage(opts) {
    region := Opt(opts, "region", ScreenRegion())
    Find(&fx, &fy) {
        return FindImage(region[1], region[2], region[3], region[4],
            opts.path, opts.w, opts.h, opts.tol, opts.transColor, &fx, &fy)
    }
    return WaitThenClick(Find, opts, "FindAndClickImage")
}

; ---------- clear-all-instances ----------
;
; Clicks every on-screen instance of an image until ONE search attempt
; finds nothing (a static, non-respawning field - so "none found right
; now" is the stop condition, not a timeout). False only if
; maxIterations hits (a click probably isn't registering).
;
; opts: region, path/w/h/tol/transColor (required); ctrl, settleMs 100
;   (click settle AND post-click gap), maxIterations 200, label,
;   preDelayMs/postDelayMs.
ClearAllInstances(opts) {
    region := opts.region
    useCtrl := Opt(opts, "ctrl", false)
    settleMs := Opt(opts, "settleMs", 100)
    maxIterations := Opt(opts, "maxIterations", 200)
    label := Opt(opts, "label", "ClearAllInstances")
    preDelayMs := Opt(opts, "preDelayMs", 0)
    postDelayMs := Opt(opts, "postDelayMs", 0)

    if (preDelayMs > 0)
        Pause(preDelayMs)

    jitterPx := BlockJitterPx(opts.w, opts.h)

    clicked := 0
    loop maxIterations {
        found := FindImage(region[1], region[2], region[3], region[4],
            opts.path, opts.w, opts.h, opts.tol, opts.transColor, &cx, &cy)
        if (!found) {
            Say(label ": zone clear (" clicked " instance" (clicked = 1 ? "" : "s") " clicked)")
            if (postDelayMs > 0)
                Pause(postDelayMs)
            return true
        }

        Say(label ": clicking instance at " cx "," cy)
        ClickAt(cx, cy, useCtrl, false, settleMs, 100, 0, 0, jitterPx)
        clicked += 1
        Pause(settleMs)
    }

    Say(label ": maxIterations (" maxIterations ") hit - a click may not be registering")
    return false
}

; ---------- verify-slots-and-drop (pointer-walk classify-or-drop) ----------
;
; Returns a MAKER: call once per verification run, then call the
; returned closure each poll tick. A pointer walks slots startSlot->
; endSlot; a filled slot is classified against the reference image in
; its own cell - match advances the pointer, non-match (e.g. a gem) is
; shift-dropped and re-checked. True once endSlot is confirmed a match.
;
; opts: startSlot/endSlot, path/w/h/tol/transColor (required - w/h
;   should match the slot's cell size); dropSettleMs 100, label.
VerifySlotsAndDrop(opts) {
    startSlot := opts.startSlot
    endSlot := opts.endSlot
    dropSettleMs := Opt(opts, "dropSettleMs", 100)
    label := Opt(opts, "label", "VerifySlotsAndDrop")

    slot := startSlot

    return CheckNext

    CheckNext() {
        if (slot > endSlot)
            return true

        if (!SlotFull(slot))
            return false

        SlotCorner(slot, &cx, &cy)
        isMatch := FindImage(cx, cy, cx + opts.w - 1, cy + opts.h - 1,
            opts.path, opts.w, opts.h, opts.tol, opts.transColor, &fx, &fy)

        if (isMatch) {
            Say(label ": slot " slot " confirmed match")
            slot += 1
            return slot > endSlot
        }

        Say(label ": slot " slot " is NOT a match - dropping it")
        DropSlot(slot, dropSettleMs)
        return false
    }
}

; ---------- click-until-condition (patient first wait, then re-click) ----------
;
; For SHARED/laggy targets (hopper, sack): the first click gets a
; patient firstWaitMs; only on a miss does it downgrade to re-clicking
; every reclickMs. &neededRetry (optional out) reports whether any
; re-click was needed - motherlode2's stall heuristic reads it.
;
; opts: click (closure returning bool; false aborts), condition,
;   firstWaitMs, reclickMs (required); firstSettleMs 0 (Pause after the
;   FIRST click, before its wait), totalTimeoutMs 0 (0 = retry forever),
;   pollMs, label, itemLabel.
ClickUntilCondition(opts, &neededRetry?) {
    click := opts.click
    condition := opts.condition
    firstWaitMs := opts.firstWaitMs
    reclickMs := opts.reclickMs
    firstSettleMs := Opt(opts, "firstSettleMs", 0)
    totalTimeoutMs := Opt(opts, "totalTimeoutMs", 0)
    pollMs := Opt(opts, "pollMs", POLL_MS_DEFAULT)
    label := Opt(opts, "label", "ClickUntilCondition")
    itemLabel := Opt(opts, "itemLabel", "condition")

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

; ---------- track-and-click (M8: acquire/track/drift-reject/anchor-hold) ----------
;
; Acquire (expanding rings from refX/refY, then region-wide, closest
; match wins across all colors), then track (narrow single-color
; re-search box around the last position) and click on a cadence until
; `until` is true. On a track miss, the anchor point is re-probed
; before conceding depletion (transient occlusion guard).
;
; TUNING (standards #15/#16 - both confirmed live):
; - trackRadius (search net) AND maxDriftPx (post-match reject) must
;   BOTH stay well under half the gap to the nearest SAME-colored
;   duplicate - track mode's FindFilledBlock returns the scan-order
;   FIRST match in the box, not the closest one.
; - postClickSettleMs (default 0): v7's async Ctrl release fires the
;   next re-search ~100ms sooner than v6 did; a target with any
;   post-click flicker reads as falsely depleted without ~100-150ms here.
; - progressTimeoutMs resets on any acquire/depletion/click ("stuck"
;   detector); timeoutMs is the absolute backstop.
; - cooldownMs (default 0 = disabled, standard #29): ONE real click per
;   acquired target is the human baseline - once stable, TrackAndClick
;   just watches, it doesn't keep re-clicking a tree/rock you're
;   already chopping/mining. Set cooldownMs > 0 only for a target that
;   genuinely needs periodic re-interaction to keep progressing; the
;   not-yet-stable branch still reclicks after reclickAfterMs
;   regardless (miss recovery - the first click may not have landed).
;
; opts: colors, blockW/blockH, refX/refY, trackRadius,
;   reclickAfterMs, until (required); tol 5, verifyPercent 100,
;   acquireRadii [], region (whole screen), maxDriftPx 40, stableTicks 2,
;   moveTolerancePx 10, ctrl false, postClickSettleMs 0, cooldownMs 0,
;   timeoutMs 1800000, progressTimeoutMs 300000, pollMs,
;   preDelayMs/postDelayMs 0 (bracket the whole composite, standard #8 -
;   postDelayMs only runs on the `until`-met SUCCESS return, not on
;   timeout/no-progress, same convention as FindAndClickBlock).
; reclickAfterMs accepts either a plain number (fixed wait, old
; behaviour) or a [min, max] array - a real person doesn't wait exactly
; the same beat before re-clicking a miss every time. Re-rolled fresh
; each time a target is (re)acquired and after every reclick, not once
; per script run.
TrackAndClick(opts) {
    colors := opts.colors
    tol := Opt(opts, "tol", 5)
    blockW := opts.blockW
    blockH := opts.blockH
    verifyPercent := Opt(opts, "verifyPercent", 100)
    refX := opts.refX
    refY := opts.refY
    acquireRadii := Opt(opts, "acquireRadii", [])
    region := Opt(opts, "region", ScreenRegion())
    trackRadius := opts.trackRadius
    maxDriftPx := Opt(opts, "maxDriftPx", 40)
    stableTicksRequired := Opt(opts, "stableTicks", 2)
    moveTolerancePx := Opt(opts, "moveTolerancePx", 10)
    cooldownMs := Opt(opts, "cooldownMs", 0)
    reclickAfterMs := opts.reclickAfterMs
    useCtrl := Opt(opts, "ctrl", false)
    postClickSettleMs := Opt(opts, "postClickSettleMs", 0)
    untilFn := opts.until
    timeoutMs := Opt(opts, "timeoutMs", 1800000)
    progressTimeoutMs := Opt(opts, "progressTimeoutMs", 300000)
    pollMs := Opt(opts, "pollMs", POLL_MS_DEFAULT)
    preDelayMs := Opt(opts, "preDelayMs", 0)
    postDelayMs := Opt(opts, "postDelayMs", 0)

    if (preDelayMs > 0)
        Pause(preDelayMs)

    NextReclickThreshold() {
        if (reclickAfterMs is Array)
            return Random(reclickAfterMs[1], reclickAfterMs[2])
        return reclickAfterMs
    }

    ; Click jitter (standard #29) proportional to the tracked block's
    ; own size - computed once, the block size never changes mid-run.
    jitterPx := BlockJitterPx(blockW, blockH)

    lock := TargetLock(stableTicksRequired, moveTolerancePx)
    hasTarget := false
    targetX := 0, targetY := 0
    lockedColor := colors[1]
    lastClickTime := 0
    reclickThreshold := NextReclickThreshold()
    t0 := A_TickCount
    lastProgressAt := A_TickCount

    loop {
        if (untilFn()) {
            Say("TrackAndClick: until-condition met (" (A_TickCount - t0) " ms total)")
            if (postDelayMs > 0)
                Pause(postDelayMs)
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
            ; Acquire: rings near->far, then region-wide fallback. A match
            ; in an inner ring is by construction closer than anything only
            ; findable wider, so stopping at the first hit is correct.
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
                reclickThreshold := NextReclickThreshold()
                lock.Reset()
                lastProgressAt := A_TickCount
                Say("Acquired new target at " tx "," ty " (" HexColor(lockedColor) ", " stageLabel ", " searchMs " ms)")
            } else {
                Say("Acquire: not found (searched " searchMs " ms)")
            }
        } else {
            ; Track: narrow box around the last position, locked to the
            ; acquired color.
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

            ; HARD RULE: never concede depletion while the exact anchor
            ; point is still the target color - a miss can be occlusion.
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
                ; A live, tracked target is progress on its own - not just a
                ; click - or disabling the stable-branch reclick below (the
                ; standard #29 default) would falsely trip progressTimeoutMs
                ; on a target that's being chopped/mined just fine.
                lastProgressAt := A_TickCount

                if (lock.IsStable()) {
                    if (cooldownMs > 0 && (lastClickTime == 0 || (A_TickCount - lastClickTime) > cooldownMs)) {
                        ClickAt(outX, outY, useCtrl, false, 100, 100, 0, 0, jitterPx)
                        lastClickTime := A_TickCount
                        Say("Clicked STABLE target at " outX "," outY " (search " searchMs " ms)")
                        if (postClickSettleMs > 0)
                            Pause(postClickSettleMs)
                    } else {
                        Say("Tracking stable target at " outX "," outY " (search " searchMs " ms)")
                    }
                } else {
                    if (lastClickTime == 0 || (A_TickCount - lastClickTime) > reclickThreshold) {
                        ClickAt(outX, outY, useCtrl, false, 100, 100, 0, 0, jitterPx)
                        lastClickTime := A_TickCount
                        reclickThreshold := NextReclickThreshold()
                        lastProgressAt := A_TickCount
                        Say("Clicked initial/re-click target at " outX "," outY " (search " searchMs " ms)")
                        if (postClickSettleMs > 0)
                            Pause(postClickSettleMs)
                    } else {
                        Say("Tracking not-yet-stable target at " outX "," outY " (search " searchMs " ms)")
                    }
                }
            }
        }

        Pause(pollMs)
    }
}

; ---------- target lock (stability/miss tracker for TrackAndClick) ----------

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

; ---------- pickup-appeared (transient item: wait, click, confirm) ----------
;
; Waits for a transient item's image, clicks it, then confirms the
; pickup via a before/after snapshot diff of confirmBox (NOT by
; re-searching - a picked-up item is gone, not moved).
;
; opts: imagePath/imageW/imageH, appearTimeoutMs, confirmBox {x,y,w,h},
;   confirmTimeoutMs (required); imageTol 5, transColor "", region
;   (whole screen), ctrl false, changeTol 10, targetSamples 50, pollMs,
;   label.
PickupAppeared(opts) {
    imageTol := Opt(opts, "imageTol", 5)
    transColor := Opt(opts, "transColor", "")
    region := Opt(opts, "region", ScreenRegion())
    useCtrl := Opt(opts, "ctrl", false)
    box := opts.confirmBox
    changeTol := Opt(opts, "changeTol", 10)
    targetSamples := Opt(opts, "targetSamples", 50)
    pollMs := Opt(opts, "pollMs", POLL_MS_DEFAULT)
    label := Opt(opts, "label", "PickupAppeared")

    foundX := 0, foundY := 0
    ImageAppeared() {
        found := FindImage(region[1], region[2], region[3], region[4],
            opts.imagePath, opts.imageW, opts.imageH, imageTol, transColor, &fx, &fy)
        if (found)
            foundX := fx, foundY := fy
        return found
    }

    t0 := A_TickCount
    if (!WaitUntil(ImageAppeared, opts.appearTimeoutMs, pollMs)) {
        Say(label ": NEVER APPEARED after " (A_TickCount - t0) " ms - giving up")
        return false
    }

    LogLine(label ": appeared at " foundX "," foundY " after " (A_TickCount - t0) " ms - snapshotting confirm box BEFORE click")

    snapshot := TakeSnapshot(box.x, box.y, box.w, box.h, targetSamples)

    Say(label ": clicking item at " foundX "," foundY)
    ClickAt(foundX, foundY, useCtrl, false, 100, 100, 0, 0, BlockJitterPx(opts.imageW, opts.imageH))

    BoxChangedNow() {
        return HasChanged(snapshot, box.x, box.y, changeTol)
    }

    t1 := A_TickCount
    if (WaitUntil(BoxChangedNow, opts.confirmTimeoutMs, pollMs)) {
        Say(label ": CONFIRMED (" (A_TickCount - t1) " ms after click, " (A_TickCount - t0) " ms total)")
        return true
    }
    Say(label ": CLICKED but NOT CONFIRMED - box never changed within " opts.confirmTimeoutMs "ms")
    return false
}

; ---------- travel-to-point (click travel marker, confirm arrival) ----------
;
; Marker click has two modes: PIN (markerClickX/markerClickY given -
; fixed always-clickable point, no search or wait at all) or SEARCH
; (markerColors/etc. required - FindAndClickBlock). Arrival = a block
; whose center lands at the expected point (BlockAtPoint); on a miss,
; a whole-screen re-probe logs found-elsewhere vs not-found-anywhere.
;
; opts: arriveColors/arriveTol/arriveBlockW/arriveBlockH,
;   arriveCornerX/arriveCornerY (corner - center is derived),
;   arrivePosTolPx, arriveWaitTimeoutMs (required); arriveMarginPx 0;
;   PIN mode: markerClickX/markerClickY; SEARCH mode: markerColors/
;   markerTol/markerBlockW/markerBlockH/markerWaitTimeoutMs (required),
;   markerRegion (whole screen), markerItemLabel; ctrl false,
;   settleMs 100, pollMs, label.
TravelToPoint(opts) {
    arriveColors := opts.arriveColors
    arriveTol := opts.arriveTol
    arriveBlockW := opts.arriveBlockW
    arriveBlockH := opts.arriveBlockH
    arriveX := CenterX(opts.arriveCornerX, arriveBlockW)
    arriveY := CenterY(opts.arriveCornerY, arriveBlockH)
    arrivePosTolPx := opts.arrivePosTolPx
    arriveMarginPx := Opt(opts, "arriveMarginPx", 0)
    useCtrl := Opt(opts, "ctrl", false)
    settleMs := Opt(opts, "settleMs", 100)
    pollMs := Opt(opts, "pollMs", POLL_MS_DEFAULT)
    label := Opt(opts, "label", "TravelToPoint")

    if (opts.HasOwnProp("markerClickX") && opts.HasOwnProp("markerClickY")) {
        Say(label ": clicking pinned marker point " opts.markerClickX "," opts.markerClickY)
        ClickAt(opts.markerClickX, opts.markerClickY, useCtrl, false, settleMs)
    } else {
        if (!FindAndClickBlock({
            colors: opts.markerColors, tol: opts.markerTol,
            blockW: opts.markerBlockW, blockH: opts.markerBlockH,
            region: Opt(opts, "markerRegion", ScreenRegion()), settleMs: settleMs,
            ctrl: useCtrl, waitTimeoutMs: opts.markerWaitTimeoutMs, pollMs: pollMs,
            label: label, itemLabel: Opt(opts, "markerItemLabel", "travel marker")
        }))
            return false
    }

    ArrivedAtPoint() {
        return BlockAtPoint(arriveX, arriveY, arriveColors, arriveTol,
            arriveBlockW, arriveBlockH, arrivePosTolPx, &fx, &fy, &fc, arriveMarginPx)
    }

    Say(label ": waiting for arrival")
    if (!WaitUntil(ArrivedAtPoint, opts.arriveWaitTimeoutMs, pollMs)) {
        sr := ScreenRegion()
        wholeScreenFound := FindAnyFilledBlock(sr[1], sr[2], sr[3], sr[4],
            arriveColors, arriveTol, arriveBlockW, arriveBlockH, &wx, &wy, &wc)
        if (wholeScreenFound) {
            Say(label ": never arrived within " opts.arriveWaitTimeoutMs "ms - but marker WAS found"
                . " elsewhere on screen at " wx "," wy " (expected near " arriveX "," arriveY ") - stopping")
        } else {
            Say(label ": never arrived within " opts.arriveWaitTimeoutMs
                . "ms - marker not found ANYWHERE on screen, not just near the expected point - stopping")
        }
        return false
    }

    Say(label ": arrived")
    return true
}

; ---------- deposit-all-to-bank (marker -> deposit image -> confirm) ----------
;
; Click the bank/deposit-box marker (per-script config - standard #17),
; wait for + click the deposit-all image (position usually the
; BANK_DEPOSIT_IMAGE_* Lib globals), optionally confirm via a caller
; condition. markerClickX/Y / depositClickX/Y pin the click points.
;
; opts: markerColors/markerTol/markerBlockW/markerBlockH,
;   markerWaitTimeoutMs, depositImagePath/depositImageW/depositImageH,
;   depositWaitTimeoutMs (required); markerRegion/depositRegion (whole
;   screen), markerClickX/markerClickY, depositClickX/depositClickY,
;   depositTol 5, depositTransColor "", markerItemLabel,
;   depositItemLabel, confirmCondition (+ confirmTimeoutMs, required
;   with it), ctrl false, pollMs, label, preDelayMs/postDelayMs 0
;   (bracket the whole composite, standard #8 - postDelayMs only runs
;   on the final SUCCESS return, not on a marker/deposit/confirm failure).
DepositAllToBank(opts) {
    useCtrl := Opt(opts, "ctrl", false)
    pollMs := Opt(opts, "pollMs", POLL_MS_DEFAULT)
    label := Opt(opts, "label", "DepositAllToBank")
    preDelayMs := Opt(opts, "preDelayMs", 0)
    postDelayMs := Opt(opts, "postDelayMs", 0)

    if (preDelayMs > 0)
        Pause(preDelayMs)

    markerOpts := {
        colors: opts.markerColors, tol: opts.markerTol, blockW: opts.markerBlockW, blockH: opts.markerBlockH,
        region: Opt(opts, "markerRegion", ScreenRegion()), ctrl: useCtrl,
        waitTimeoutMs: opts.markerWaitTimeoutMs, pollMs: pollMs, label: label,
        itemLabel: Opt(opts, "markerItemLabel", "deposit-box marker")
    }
    if (opts.HasOwnProp("markerClickX"))
        markerOpts.clickX := opts.markerClickX
    if (opts.HasOwnProp("markerClickY"))
        markerOpts.clickY := opts.markerClickY
    if (!FindAndClickBlock(markerOpts))
        return false

    depositOpts := {
        path: opts.depositImagePath, w: opts.depositImageW, h: opts.depositImageH,
        tol: Opt(opts, "depositTol", 5), transColor: Opt(opts, "depositTransColor", ""),
        region: Opt(opts, "depositRegion", ScreenRegion()), ctrl: useCtrl,
        waitTimeoutMs: opts.depositWaitTimeoutMs, pollMs: pollMs, label: label,
        itemLabel: Opt(opts, "depositItemLabel", "deposit box")
    }
    if (opts.HasOwnProp("depositClickX"))
        depositOpts.clickX := opts.depositClickX
    if (opts.HasOwnProp("depositClickY"))
        depositOpts.clickY := opts.depositClickY
    if (!FindAndClickImage(depositOpts))
        return false

    if (!opts.HasOwnProp("confirmCondition")) {
        if (postDelayMs > 0)
            Pause(postDelayMs)
        return true
    }

    Say(label ": waiting for inventory to confirm the deposit")
    if (!WaitUntil(opts.confirmCondition, opts.confirmTimeoutMs, pollMs)) {
        Say(label ": deposit not confirmed within " opts.confirmTimeoutMs "ms - stopping (may not have registered)")
        return false
    }

    Say(label ": deposit confirmed")
    if (postDelayMs > 0)
        Pause(postDelayMs)
    return true
}

; ---------- restock plan ([slot, clicks] pairs, standard #20) ----------

RunRestockPlan(plan, ctrl := false) {
    global BANK_GRID
    jitterPx := BlockJitterPx(BANK_GRID.cellW, BANK_GRID.cellH)
    for entry in plan {
        BankSlotCenter(entry[1], &x, &y)
        loop entry[2]
            ClickAt(x, y, ctrl, false, 100, 100, 0, 0, jitterPx)
    }
}

; ---------- gather-bank-loop (forever: gather -> bank -> repeat) ----------
;
; Deliberately thin: the bot builds gather/bank closures from other
; composites; this loop just repeats them until either fails, F6 stops,
; or maxCycles is hit. "Cut gathering short on a bank stall" decisions
; belong INSIDE the gather closure (it owns that state), not here. Same
; rule for session-length/breaks (standard #30): the loop only checks
; at the gather/bank seam, never interrupts mid-unit.
;
; opts: gather, bank (closures returning bool, required); maxCycles 0
;   (0 = forever), label; breakChance 0 (0..1, disabled by default),
;   breakMs (SESSION_BREAK_MS_DEFAULT, standard #30), sessionLengthMs
;   (number or [min,max]; OMIT to disable - not a 0 sentinel, since a
;   real value can be an array).
;
; Running out of session time is a CLEAN stop (returns true), same
; convention as maxCycles - it is not a failure.
GatherBankLoop(opts) {
    gather := opts.gather
    bank := opts.bank
    maxCycles := Opt(opts, "maxCycles", 0)
    label := Opt(opts, "label", "GatherBankLoop")

    breakChance := Opt(opts, "breakChance", 0)
    breakMs := Opt(opts, "breakMs", SESSION_BREAK_MS_DEFAULT)
    sessionExpired := opts.HasOwnProp("sessionLengthMs")
        ? NewSessionTimer({sessionLengthMs: opts.sessionLengthMs, label: label})
        : false

    cycle := 0
    loop {
        cycle += 1
        Say(label ": cycle " cycle " - gathering")
        if (!gather()) {
            Say(label ": gather failed on cycle " cycle " - stopping")
            return false
        }

        Say(label ": cycle " cycle " - banking")
        if (!bank()) {
            Say(label ": bank failed on cycle " cycle " - stopping")
            return false
        }

        if (sessionExpired && sessionExpired()) {
            Say(label ": session length elapsed after cycle " cycle " - stopping cleanly")
            return true
        }

        if (maxCycles > 0 && cycle >= maxCycles) {
            Say(label ": reached maxCycles (" maxCycles ") - stopping")
            return true
        }

        if (breakChance > 0)
            MaybeTakeBreak({chance: breakChance, breakMs: breakMs, label: label})
    }
}
