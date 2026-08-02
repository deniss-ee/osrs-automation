; ============================================================
; v8 Lib\Steps.ahk - opts-object composites (search + action)
;
; Every composite's internal LOGIC is ported from v7\Lib\Steps.ahk
; (proven live) - including TrackAndClick's anchor-hold occlusion
; guard, single-color track lock, and click policy, and
; ClickUntilCondition's abort-on-click-failure contract. What changed
; is the SURFACE:
; - Sizes are always spec.w/spec.h (Find.ahk's unified target spec)
;   or an explicit ClickTarget - never blockW/blockH/imageW/imageH.
; - Every click goes through ClickAt(target, opts) - one prologue,
;   button param for left/right, no bare-coordinate path.
; - A "pin" (clicking a fixed/known point instead of the point just
;   found) is always its OWN ClickTarget with its own real w/h - so
;   its jitter is sized from what's actually being clicked, not
;   whatever was searched for (v7 bug: a pin inherited the SEARCHED
;   target's jitter size).
; - FindAndClick replaces v7's WaitThenClick + FindAndClickBlock +
;   FindAndClickImage trio - FindTarget already unifies the
;   block/image dispatch, so the fan-out layer is gone.
;
; Every composite returns false (logged via Say, no throw) on its own
; failure and lets BotStopped propagate from Pause/WaitUntil - never
; swallowed.
; ============================================================

; ---------- find-and-click (wait for target, click it or a pin) ----------

; Waits for opts.target (a Find.ahk spec) to appear in opts.region,
; then clicks it. If opts.clickTarget is given (a ClickTarget - a
; pin), the click lands there instead of the found position, but the
; WAIT still gates on actually finding the target first - the pin
; only overrides WHERE the click lands, never whether we click.
;
; opts: target, waitTimeoutMs (required); region (whole screen),
;   clickTarget, ctrl false, pollMs, settleMs 100 (number or [min,max],
;   rolled fresh via RollMs - the short mechanical glide-arrival->click
;   gap, NOT a reaction delay), label, itemLabel, preDelayMs/
;   postDelayMs 0, wander (default off - see WaitUntil, Core.ahk -
;   passed straight through to the target-appear wait).
;   distractedChance 0 + distractedMs [1000,3000] (number or [min,max])
;   - chance-gated pause BEFORE the search for the target even starts
;   (after preDelayMs, before WaitForTarget) - models attention having
;   been elsewhere (e.g. alt-tabbed) and not yet looking for the
;   target at all, regardless of whether it's already on screen.
;   Deliberately placed before ANY movement toward the target - a
;   version of this that fired after WaitForTarget succeeded had a
;   real live bug: with wander enabled, the search loop's own
;   wandering could coincidentally leave the cursor resting near the
;   target by the time it was found, so the "distraction" pause looked
;   like the cursor had already moved onto the target and just sat
;   there - the opposite of what it's supposed to model. Distinct from
;   settleMs (always-applied, short, mechanical) - this is the same
;   "before search starts" timing as TrackAndClick's acquireDelayChance.
FindAndClick(opts) {
    target := opts.target
    region := Opt(opts, "region", ScreenRegion())
    useCtrl := Opt(opts, "ctrl", false)
    pollMs := Opt(opts, "pollMs", POLL_MS_DEFAULT)
    settleMs := Opt(opts, "settleMs", 100)
    label := Opt(opts, "label", "FindAndClick")
    itemLabel := Opt(opts, "itemLabel", "target")
    preDelayMs := Opt(opts, "preDelayMs", 0)
    postDelayMs := Opt(opts, "postDelayMs", 0)
    wanderOpts := Opt(opts, "wander", "")
    distractedChance := Opt(opts, "distractedChance", 0)
    distractedMs := Opt(opts, "distractedMs", [1000, 3000])

    if (preDelayMs > 0)
        Pause(preDelayMs)

    if (distractedChance > 0 && Random(0.0, 1.0) <= distractedChance) {
        delayMs := RollMs(distractedMs)
        Say(label ": distracted, not looking for " itemLabel " yet (" delayMs "ms / " Round(delayMs / 1000, 1) "s)")
        Pause(delayMs)
    }

    Say(label ": waiting for " itemLabel)
    if (!WaitForTarget(region, target, opts.waitTimeoutMs, &fx, &fy, {pollMs: pollMs, wander: wanderOpts})) {
        Say(label ": " itemLabel " never appeared within " opts.waitTimeoutMs "ms - stopping")
        return false
    }

    resolvedClickTarget := opts.HasOwnProp("clickTarget") ? opts.clickTarget : ClickTarget(fx, fy, target.w, target.h)
    Say(label ": clicking " itemLabel " at " resolvedClickTarget.x "," resolvedClickTarget.y)
    ClickAt(resolvedClickTarget, {ctrl: useCtrl, settleMs: settleMs})

    if (postDelayMs > 0)
        Pause(postDelayMs)
    return true
}

; ---------- clear-all-instances ----------

; Clicks every on-screen instance of opts.target until ONE search
; attempt finds nothing (a static, non-respawning field - so "none
; found right now" is the stop condition, not a timeout). False only
; if maxIterations hits (a click probably isn't registering).
;
; opts: region, target (required); ctrl, settleMs 100 (click settle
;   AND post-click gap), maxIterations 200, label,
;   preDelayMs/postDelayMs.
ClearAllInstances(opts) {
    region := opts.region
    target := opts.target
    useCtrl := Opt(opts, "ctrl", false)
    settleMs := Opt(opts, "settleMs", 100)
    maxIterations := Opt(opts, "maxIterations", 200)
    label := Opt(opts, "label", "ClearAllInstances")
    preDelayMs := Opt(opts, "preDelayMs", 0)
    postDelayMs := Opt(opts, "postDelayMs", 0)

    if (preDelayMs > 0)
        Pause(preDelayMs)

    clicked := 0
    loop maxIterations {
        if (!FindTarget(region, target, &cx, &cy, &fc)) {
            Say(label ": zone clear (" clicked " instance" (clicked = 1 ? "" : "s") " clicked)")
            if (postDelayMs > 0)
                Pause(postDelayMs)
            return true
        }

        Say(label ": clicking instance at " cx "," cy)
        ClickAt(ClickTarget(cx, cy, target.w, target.h), {ctrl: useCtrl, settleMs: settleMs})
        clicked += 1
        Pause(settleMs)
    }

    Say(label ": maxIterations (" maxIterations ") hit - a click may not be registering")
    return false
}

; ---------- pickup-appeared (transient item: wait, click, confirm) ----------

; Waits for a transient item's image, clicks it, then confirms the
; pickup via a before/after snapshot diff of confirmBox (NOT by
; re-searching - a picked-up item is gone, not moved).
;
; opts: target (image spec), appearTimeoutMs, confirmBox {x,y,w,h},
;   confirmTimeoutMs (required); region (whole screen), ctrl false,
;   changeTol 10, targetSamples 50, pollMs, label.
PickupAppeared(opts) {
    target := opts.target
    region := Opt(opts, "region", ScreenRegion())
    useCtrl := Opt(opts, "ctrl", false)
    box := opts.confirmBox
    changeTol := Opt(opts, "changeTol", 10)
    targetSamples := Opt(opts, "targetSamples", 50)
    pollMs := Opt(opts, "pollMs", POLL_MS_DEFAULT)
    label := Opt(opts, "label", "PickupAppeared")

    t0 := A_TickCount
    if (!WaitForTarget(region, target, opts.appearTimeoutMs, &foundX, &foundY, {pollMs: pollMs})) {
        Say(label ": NEVER APPEARED after " (A_TickCount - t0) " ms - giving up")
        return false
    }

    LogLine(label ": appeared at " foundX "," foundY " after " (A_TickCount - t0) " ms - snapshotting confirm box BEFORE click")
    snapshot := TakeSnapshot(box.x, box.y, box.w, box.h, targetSamples)

    Say(label ": clicking item at " foundX "," foundY)
    ClickAt(ClickTarget(foundX, foundY, target.w, target.h), {ctrl: useCtrl})

    t1 := A_TickCount
    if (WaitUntil(() => HasChanged(snapshot, changeTol), opts.confirmTimeoutMs, pollMs)) {
        Say(label ": CONFIRMED (" (A_TickCount - t1) " ms after click, " (A_TickCount - t0) " ms total)")
        return true
    }
    Say(label ": CLICKED but NOT CONFIRMED - box never changed within " opts.confirmTimeoutMs "ms")
    return false
}

; ---------- right-click -> context menu -> click entry ----------

; Right-clicks opts.at (a ClickTarget - the thing being right-clicked,
; with its own real size, so the right-click's jitter is bounded by
; it), waits for the menu-entry image inside a searchBoxSize box
; centered on the click point, clicks its center. Esc closes the menu
; on a miss. menuSettleMs is the gap after the right-click before the
; FIRST search (without it the first search reliably misses the
; still-rendering menu). pollMs defaults to 150, NOT POLL_MS_DEFAULT -
; measured live: the context menu takes at least ~150ms to open, so
; polling faster only burns searches. ctrl applies only to the
; follow-up left-click.
;
; opts: at (ClickTarget), menuItem (image spec), waitTimeoutMs
;   (required); searchBoxSize 512, settleMs 100, menuSettleMs 100,
;   ctrl false, pollMs 150, label, preDelayMs/postDelayMs.
RightClickMenuItem(opts) {
    at := opts.at
    menuItem := opts.menuItem
    settleMs := Opt(opts, "settleMs", 100)
    menuSettleMs := Opt(opts, "menuSettleMs", 100)
    searchBoxSize := Opt(opts, "searchBoxSize", 512)
    pollMs := Opt(opts, "pollMs", 150)
    useCtrl := Opt(opts, "ctrl", false)
    label := Opt(opts, "label", "RightClickMenuItem")
    preDelayMs := Opt(opts, "preDelayMs", 0)
    postDelayMs := Opt(opts, "postDelayMs", 0)

    if (preDelayMs > 0)
        Pause(preDelayMs)

    ClickAt(at, {button: "right", settleMs: settleMs})
    Pause(menuSettleMs)

    region := RegionAround(at.x, at.y, 0, 0, searchBoxSize // 2)
    if (!WaitForTarget(region, menuItem, opts.waitTimeoutMs, &cx, &cy, {pollMs: pollMs})) {
        Say(label ": item not found in menu, closing menu with Esc")
        Send("{Esc}")
        return false
    }

    LogLine(label ": found menu item at " cx "," cy)
    ClickAt(ClickTarget(cx, cy, menuItem.w, menuItem.h), {ctrl: useCtrl, settleMs: settleMs})

    if (postDelayMs > 0)
        Pause(postDelayMs)
    return true
}

; ---------- click-until-condition (patient first wait, then re-click) ----------

; For SHARED/laggy targets: the first click gets a patient
; firstWaitMs; only on a miss does it downgrade to re-clicking every
; reclickMs. click() returning false ABORTS the whole composite (the
; click itself failed, e.g. its own search missed - retrying the
; wait would be waiting on a click that never happened). &neededRetry
; (optional out) reports whether any re-click was needed.
;
; opts: click (closure returning bool), condition, firstWaitMs,
;   reclickMs (required); firstSettleMs 0 (Pause after the FIRST
;   click, before its wait), totalTimeoutMs 0 (0 = retry forever),
;   pollMs, label, itemLabel.
ClickUntilCondition(opts, &neededRetry := false) {
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

; ---------- travel-to-point (click travel marker, confirm arrival) ----------

; Marker click has two modes: PIN (opts.markerClick, a ClickTarget -
; fixed always-clickable point with its own real size, no search or
; wait at all) or SEARCH (opts.marker spec + opts.markerRegion +
; opts.markerWaitTimeoutMs - FindAndClick). Arrival = a block whose
; center lands at opts.arriveAt {x,y} within arrivePosTolPx
; (BlockAtPoint); on a miss, a whole-screen re-probe logs
; found-elsewhere vs not-found-anywhere.
;
; opts: arrive (block spec), arriveAt {x,y}, arrivePosTolPx,
;   arriveWaitTimeoutMs (required); arriveMarginPx 0; PIN mode:
;   markerClick (ClickTarget); SEARCH mode: marker (block spec),
;   markerWaitTimeoutMs (required), markerRegion (whole screen),
;   markerItemLabel; ctrl false, settleMs 100, pollMs, label.
TravelToPoint(opts) {
    arrive := opts.arrive
    arriveAt := opts.arriveAt
    arrivePosTolPx := opts.arrivePosTolPx
    arriveMarginPx := Opt(opts, "arriveMarginPx", 0)
    arriveTol := Opt(arrive, "tol", 5)
    useCtrl := Opt(opts, "ctrl", false)
    settleMs := Opt(opts, "settleMs", 100)
    pollMs := Opt(opts, "pollMs", POLL_MS_DEFAULT)
    label := Opt(opts, "label", "TravelToPoint")

    if (opts.HasOwnProp("markerClick")) {
        Say(label ": clicking pinned marker point " opts.markerClick.x "," opts.markerClick.y)
        ClickAt(opts.markerClick, {ctrl: useCtrl, settleMs: settleMs})
    } else {
        if (!FindAndClick({
            target: opts.marker, region: Opt(opts, "markerRegion", ScreenRegion()),
            waitTimeoutMs: opts.markerWaitTimeoutMs, ctrl: useCtrl, settleMs: settleMs, pollMs: pollMs,
            label: label, itemLabel: Opt(opts, "markerItemLabel", "travel marker")
        }))
            return false
    }

    ArrivedAtPoint() {
        return BlockAtPoint(arriveAt.x, arriveAt.y, arrive.colors, arriveTol,
            arrive.w, arrive.h, arrivePosTolPx, &fx, &fy, &fc, arriveMarginPx)
    }

    Say(label ": waiting for arrival")
    if (!WaitUntil(ArrivedAtPoint, opts.arriveWaitTimeoutMs, pollMs)) {
        sr := ScreenRegion()
        wholeScreenFound := FindAnyFilledBlock(sr[1], sr[2], sr[3], sr[4],
            arrive.colors, arriveTol, arrive.w, arrive.h, &wx, &wy, &wc)
        if (wholeScreenFound) {
            Say(label ": never arrived within " opts.arriveWaitTimeoutMs "ms - but marker WAS found"
                . " elsewhere on screen at " wx "," wy " (expected near " arriveAt.x "," arriveAt.y ") - stopping")
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

; Click the bank/deposit-box marker, wait for + click the deposit-all
; image, optionally confirm via a caller condition. Both clicks
; compose FindAndClick, so a markerClick/depositClick pin follows
; v7's proven gate-then-pin semantics: the SEARCH still gates (we
; wait until the marker/button is actually visible), the pin only
; overrides where the click lands - and in v8 the pin carries its
; own real size, so its jitter is bounded by the pinned target, not
; the searched one.
;
; opts: marker (block spec), markerWaitTimeoutMs, deposit (image
;   spec), depositWaitTimeoutMs (required); markerRegion/
;   depositRegion (whole screen), markerClick/depositClick
;   (ClickTargets), markerItemLabel, depositItemLabel,
;   confirmCondition (+ confirmTimeoutMs, required with it),
;   ctrl false (both clicks), markerCtrl/depositCtrl (each defaults
;   to ctrl - override independently, e.g. run-click the marker but
;   not a UI deposit button), depositSearchDelayMs 0 (number or
;   [min,max], rolled fresh per call - a settle gap before the
;   deposit-button search starts, letting the bank UI actually
;   render instead of searching the instant the marker click lands),
;   settleMs 100 (marker's own click-settle; number or [min,max]),
;   depositSettleMs (defaults to settleMs - override to tune the
;   deposit button's click-settle independently, e.g. the marker is a
;   reflexive/known-position click while the deposit button isn't),
;   depositDistractedChance 0 + depositDistractedMs [1000,3000]
;   (FindAndClick's distractedChance/distractedMs, applied ONLY to the
;   deposit-button click, never the marker - fires AFTER
;   depositSearchDelayMs but BEFORE the deposit-button search even
;   starts, modeling having been doing something else and not yet
;   looking, regardless of whether the button already rendered; see
;   FindAndClick's own doc comment for why it's placed there), pollMs,
;   label, preDelayMs/postDelayMs 0 (postDelayMs
;   only runs on the final SUCCESS return), wander (default off - the
;   unified {chance, checkMs, durationMs, region} shape, see
;   MaybeWander/WaitUntil, Act.ahk/Core.ahk) applied to ALL THREE of
;   this composite's waits (marker search, deposit-button search,
;   post-deposit confirm) - these are genuine "nothing to do but
;   wait" stretches, same spirit as TrackAndClick's stable-tracking
;   idle branch.
DepositAllToBank(opts) {
    useCtrl := Opt(opts, "ctrl", false)
    markerCtrl := Opt(opts, "markerCtrl", useCtrl)
    depositCtrl := Opt(opts, "depositCtrl", useCtrl)
    depositSearchDelayMs := Opt(opts, "depositSearchDelayMs", 0)
    pollMs := Opt(opts, "pollMs", POLL_MS_DEFAULT)
    settleMs := Opt(opts, "settleMs", 100)
    depositSettleMs := Opt(opts, "depositSettleMs", settleMs)
    depositDistractedChance := Opt(opts, "depositDistractedChance", 0)
    depositDistractedMs := Opt(opts, "depositDistractedMs", [1000, 3000])
    label := Opt(opts, "label", "DepositAllToBank")
    preDelayMs := Opt(opts, "preDelayMs", 0)
    postDelayMs := Opt(opts, "postDelayMs", 0)
    wanderOpts := Opt(opts, "wander", "")

    if (preDelayMs > 0)
        Pause(preDelayMs)

    markerOpts := {
        target: opts.marker, region: Opt(opts, "markerRegion", ScreenRegion()),
        waitTimeoutMs: opts.markerWaitTimeoutMs, ctrl: markerCtrl, settleMs: settleMs, pollMs: pollMs,
        label: label, itemLabel: Opt(opts, "markerItemLabel", "bank marker"), wander: wanderOpts
    }
    if (opts.HasOwnProp("markerClick"))
        markerOpts.clickTarget := opts.markerClick
    if (!FindAndClick(markerOpts))
        return false

    resolvedDepositDelay := RollMs(depositSearchDelayMs)
    depositOpts := {
        target: opts.deposit, region: Opt(opts, "depositRegion", ScreenRegion()),
        waitTimeoutMs: opts.depositWaitTimeoutMs, ctrl: depositCtrl, settleMs: depositSettleMs, pollMs: pollMs,
        label: label, itemLabel: Opt(opts, "depositItemLabel", "deposit button"),
        preDelayMs: resolvedDepositDelay, wander: wanderOpts,
        distractedChance: depositDistractedChance, distractedMs: depositDistractedMs
    }
    if (opts.HasOwnProp("depositClick"))
        depositOpts.clickTarget := opts.depositClick
    if (!FindAndClick(depositOpts))
        return false

    if (!opts.HasOwnProp("confirmCondition")) {
        if (postDelayMs > 0)
            Pause(postDelayMs)
        return true
    }

    Say(label ": waiting for inventory to confirm the deposit")
    if (!WaitUntil(opts.confirmCondition, opts.confirmTimeoutMs, pollMs, wanderOpts)) {
        Say(label ": deposit not confirmed within " opts.confirmTimeoutMs "ms - stopping (may not have registered)")
        return false
    }

    Say(label ": deposit confirmed")
    if (postDelayMs > 0)
        Pause(postDelayMs)
    return true
}

; ---------- verify-slots-and-drop (pointer-walk classify-or-drop) ----------

; Returns a MAKER: call once per verification run, then call the
; returned closure each poll tick. A pointer walks slots startSlot ->
; endSlot; an EMPTY slot returns false (still waiting for it to fill
; - this runs during active gathering); a filled slot is classified
; against opts.target (image spec) inside its own cell
; (GridCellRegion - the one definition of a cell's box) - match
; advances the pointer, non-match is shift-dropped and the SAME slot
; re-checked next call. True once endSlot is confirmed a match.
;
; opts: startSlot/endSlot, target (image spec - w/h should match the
;   slot's cell size) (required); dropSettleMs 100, label.
VerifySlotsAndDrop(opts) {
    startSlot := opts.startSlot
    endSlot := opts.endSlot
    target := opts.target
    dropSettleMs := Opt(opts, "dropSettleMs", 100)
    label := Opt(opts, "label", "VerifySlotsAndDrop")

    slot := startSlot

    return CheckNext

    CheckNext() {
        if (slot > endSlot)
            return true

        if (!SlotFull(slot))
            return false

        region := GridCellRegion(INV_GRID, slot)
        isMatch := FindTarget(region, target, &fx, &fy, &fc)

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

; ---------- restock plan ([slot, clicks] pairs) ----------

; Clicks a plan of [slotIndex, clickCount] pairs against the bank
; grid. Every click is its own real ClickAt (own jitter roll).
; opts: plan (required); ctrl false, settleMs 100, label.
RunRestockPlan(opts) {
    plan := opts.plan
    useCtrl := Opt(opts, "ctrl", false)
    settleMs := Opt(opts, "settleMs", 100)

    for entry in plan {
        BankSlotCenter(entry[1], &x, &y)
        loop entry[2]
            ClickAt(ClickTarget(x, y, BANK_GRID.cellW, BANK_GRID.cellH), {ctrl: useCtrl, settleMs: settleMs})
    }
    return true
}

; ---------- target lock (stability tracker for TrackAndClick) ----------

; Ported from v7 minus the unused missingTicks/IsLost machinery
; (dead code there - TrackAndClick handles loss via its own found
; logic and never consulted IsLost).
class TargetLock {
    __New(stableTicksRequired, moveTolerancePx) {
        this._stableTicksRequired := stableTicksRequired
        this._moveTolerancePx := moveTolerancePx
        this._hasPosition := false
        this._lastX := 0
        this._lastY := 0
        this._stableTicks := 0
    }

    IsStable() => this._stableTicks >= this._stableTicksRequired

    Observe(found, x, y, &outX, &outY) {
        if (!found) {
            outX := this._lastX
            outY := this._lastY
            return false
        }

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
    }
}

; ---------- track-and-click (acquire/track/drift-reject/anchor-hold) ----------

; Acquire (expanding rings from refX/refY, then region-wide, closest
; match wins across all of target.colors), then track (narrow
; single-color re-search box around the last position, locked to the
; ACQUIRED color) and click on a cadence until `until` is true. On a
; track miss, the anchor point is re-probed before conceding
; depletion (transient occlusion guard - HARD RULE ported from v7:
; never concede depletion while the exact anchor pixel is still the
; locked color).
;
; TUNING (v7 standards #15/#16, confirmed live):
; - trackRadius AND maxDriftPx must BOTH stay well under half the gap
;   to the nearest SAME-colored duplicate - track mode's
;   FindFilledBlock returns the scan-order FIRST match in the box.
; - postClickSettleMs (default 0, number or [min,max] rolled fresh per
;   click via RollMs): a target with post-click flicker reads as
;   falsely depleted without ~100-150ms here at minimum.
; - progressTimeoutMs resets on any acquire/depletion/click/live
;   tracked tick; timeoutMs is the absolute backstop.
; - cooldownMs (default 0 = disabled): ONE real click per acquired
;   target is the human baseline - once stable, TrackAndClick just
;   watches. Set cooldownMs > 0 only for a target that genuinely
;   needs periodic re-interaction; the not-yet-stable branch still
;   reclicks after reclickAfterMs regardless (miss recovery).
;
; opts: target (block spec), refX/refY, trackRadius, reclickAfterMs
;   (number or [min,max], re-rolled fresh at every (re)acquire and
;   after every reclick), until (required); acquireRadii [], region
;   (whole screen), maxDriftPx 40, stableTicks 2, moveTolerancePx 10,
;   cooldownMs 0, ctrl false, clickSettleMs 100, postClickSettleMs 0,
;   timeoutMs 1800000, progressTimeoutMs 300000, pollMs,
;   preDelayMs/postDelayMs 0 (postDelayMs only on the until-met
;   SUCCESS return), acquireDelayChance 0 + acquireDelayMs (number or
;   [min,max], rolled fresh) - chance-gated pause right before EACH
;   fresh acquisition search starts (first target of the run and
;   every re-acquire after a depletion) - models "took a moment to
;   spot the next target," a different concept from MaybeTakeBreak's
;   step-away semantics. wander (default off - the unified {chance,
;   checkMs, durationMs, region} shape, see MaybeWander/WaitUntil,
;   Act.ahk/Core.ahk) - while STABLE and not clicking (genuinely idling,
;   watching the target), roams the cursor anywhere on screen, never
;   landing on the target's own cell. postClickDriftChance 0 +
;   postClickDriftFrac [0,0.25] (fraction of A_ScreenHeight, RandTri-
;   weighted toward the middle of the range) - after EVERY real click
;   (both the stable-click and initial/re-click branches), chance-
;   gated glide away from wherever the cursor just clicked, clamped to
;   `region` - a real hand doesn't stay frozen on the clicked pixel.
TrackAndClick(opts) {
    target := opts.target
    tol := Opt(target, "tol", 5)
    verifyPercent := Opt(target, "verifyPercent", 100)
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
    clickSettleMs := Opt(opts, "clickSettleMs", 100)
    postClickSettleMs := Opt(opts, "postClickSettleMs", 0)
    untilFn := opts.until
    timeoutMs := Opt(opts, "timeoutMs", 1800000)
    progressTimeoutMs := Opt(opts, "progressTimeoutMs", 300000)
    pollMs := Opt(opts, "pollMs", POLL_MS_DEFAULT)
    preDelayMs := Opt(opts, "preDelayMs", 0)
    postDelayMs := Opt(opts, "postDelayMs", 0)
    acquireDelayChance := Opt(opts, "acquireDelayChance", 0)
    acquireDelayMs := Opt(opts, "acquireDelayMs", [5000, 10000])
    wanderOpts := Opt(opts, "wander", "")
    postClickDriftChance := Opt(opts, "postClickDriftChance", 0)
    postClickDriftFrac := Opt(opts, "postClickDriftFrac", [0, 0.25])

    if (preDelayMs > 0)
        Pause(preDelayMs)

    NextReclickThreshold() {
        if (reclickAfterMs is Array)
            return Random(reclickAfterMs[1], reclickAfterMs[2])
        return reclickAfterMs
    }

    ; Every click leaves the cursor sitting exactly on the clicked
    ; pixel - a real hand doesn't stay frozen there. Rolls
    ; postClickDriftChance; on a hit, glides to a random point at a
    ; RandTri-weighted (center-weighted, not flat - same reasoning as
    ; every other distance/duration in this file) distance of
    ; postClickDriftFrac (fraction of A_ScreenHeight, default 0-25%)
    ; from wherever the cursor currently is, in a random direction,
    ; clamped to `region`.
    DriftAfterClick() {
        if (postClickDriftChance <= 0 || Random(0.0, 1.0) > postClickDriftChance)
            return
        MouseGetPos(&fromX, &fromY)
        distPx := RandTri(postClickDriftFrac[1], postClickDriftFrac[2]) * A_ScreenHeight
        angle := Random(0.0, 6.283185307)
        tx := Max(region[1], Min(region[3], Round(fromX + Cos(angle) * distPx)))
        ty := Max(region[2], Min(region[4], Round(fromY + Sin(angle) * distPx)))
        Say("TrackAndClick: drifting after click (" Round(distPx) "px)")
        HumanMove(tx, ty)
    }

    lock := TargetLock(stableTicksRequired, moveTolerancePx)
    hasTarget := false
    targetX := 0, targetY := 0
    lockedColor := target.colors[1]
    lastClickTime := 0
    reclickThreshold := NextReclickThreshold()
    lastWanderCheckAt := A_TickCount
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
            if (acquireDelayChance > 0 && Random(0.0, 1.0) <= acquireDelayChance) {
                delayMs := RollMs(acquireDelayMs)
                Say("TrackAndClick: taking a moment to spot the next target (" delayMs "ms / " Round(delayMs / 1000, 1) "s)")
                Pause(delayMs)
            }

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
                found := AcquireClosestInBox(rx1, ry1, rx2, ry2, target.colors, tol, target.w, target.h, verifyPercent, refX, refY, &tx, &ty, &foundColor)
                if (found) {
                    stageLabel := "ring " radius
                    break
                }
                Say("Acquire ring " radius ": not found (" (A_TickCount - tStage) " ms)")
            }
            if (!found) {
                found := AcquireClosestInBox(region[1], region[2], region[3], region[4], target.colors, tol, target.w, target.h, verifyPercent, refX, refY, &tx, &ty, &foundColor)
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
            found := FindFilledBlock(rx1, ry1, rx2, ry2, lockedColor, tol, target.w, target.h, &nx, &ny, verifyPercent)
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
                ; A live, tracked target is progress on its own - not just
                ; a click - or the stable branch's no-reclick default would
                ; falsely trip progressTimeoutMs on a target that's being
                ; chopped/mined just fine.
                lastProgressAt := A_TickCount

                if (lock.IsStable()) {
                    if (cooldownMs > 0 && (lastClickTime == 0 || (A_TickCount - lastClickTime) > cooldownMs)) {
                        ClickAt(ClickTarget(outX, outY, target.w, target.h), {ctrl: useCtrl, settleMs: clickSettleMs})
                        lastClickTime := A_TickCount
                        Say("Clicked STABLE target at " outX "," outY " (search " searchMs " ms)")
                        resolvedPostClickSettleMs := RollMs(postClickSettleMs)
                        if (resolvedPostClickSettleMs > 0)
                            Pause(resolvedPostClickSettleMs)
                        DriftAfterClick()
                    } else {
                        Say("Tracking stable target at " outX "," outY " (search " searchMs " ms)")
                        MaybeWander(wanderOpts, &lastWanderCheckAt, outX, outY, Max(target.w, target.h) / 2)
                    }
                } else {
                    if (lastClickTime == 0 || (A_TickCount - lastClickTime) > reclickThreshold) {
                        ClickAt(ClickTarget(outX, outY, target.w, target.h), {ctrl: useCtrl, settleMs: clickSettleMs})
                        lastClickTime := A_TickCount
                        reclickThreshold := NextReclickThreshold()
                        lastProgressAt := A_TickCount
                        Say("Clicked initial/re-click target at " outX "," outY " (search " searchMs " ms)")
                        resolvedPostClickSettleMs := RollMs(postClickSettleMs)
                        if (resolvedPostClickSettleMs > 0)
                            Pause(resolvedPostClickSettleMs)
                        DriftAfterClick()
                    } else {
                        Say("Tracking not-yet-stable target at " outX "," outY " (search " searchMs " ms)")
                    }
                }
            }
        }

        Pause(pollMs)
    }
}
