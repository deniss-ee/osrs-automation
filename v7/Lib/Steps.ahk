; ============================================================
; v7 Lib\Steps.ahk - composite building blocks (search + action together)
;
; Built incrementally, one composite per micro, same as every other
; Lib file. RightClickMenuItem for micro 10 (the gap primitive from
; the original scope decision - right-click -> context menu -> click a
; specific entry, needed for AutoFighterLoot if it's ever built. No
; current v6 bot uses this, so it's genuinely new ground, not a port).
; FindAndClickBlock for micro 11 (M7 full mode, color only - see below).
; ClearAllInstances for micro 17 (promoted from v6 sudoku.ahk's
; hand-rolled ClearSearchZone - see below). VerifySlotsAndDrop for
; micro 19 (generalized from v6 motherlode2.ahk's MineFullnessCheck
; pointer-walk - see below). ClickUntilCondition for micro 20 (straight
; port, no contract change, from v6 Lib\Steps.ahk - already proven
; there in motherlode2's DepositHopper/WithdrawAndBankOnce, see below).
; TrackAndClick + TargetLock for micro 21 (M8, the biggest composite in
; the project - straight port from v6 Lib\Steps.ahk, proven there
; across Woodcutting/Motherlode/Motherlode2's entire vein/tree tracking
; loop - see below for the full acquire/track/drift/anchor design).
; PickupAppeared for micro 22 (v6's Mark-of-Grace pattern - port with
; clickOffsetX/Y REMOVED, per the v7 hard rule against click-offset
; compensation - see below). TravelToPoint for micro 23 (v6's
; GoToSackArea/ReturnToMine shape, generalized - port with
; markerClickOffsetX/Y REMOVED and color/arriveColor upgraded to
; colors/arriveColors arrays, per the v7 standards - see below).
;
; Micro 18 (wait-marker-then-click, M9 two-stage shape) was DROPPED
; (2026-07-23) after live confirmation that it duplicated micro 11:
; FindAndClickBlock with a clickX/clickY pin already covers "wait for
; a marker, then click a different point" - the only thing micro 18
; would have added on top was one extra ClickAt before the wait, which
; is not a real Lib composite's job (a bot that needs a start click
; first just calls ClickAt, then FindAndClickBlock pinned). Do not
; re-add WaitMarkerThenClick without a real scenario FindAndClickBlock
; genuinely can't cover.
;
; RULE (2026-07-23, applies to every composite in this file, present
; and future): EVERY Steps composite takes a single opts object (a
; plain object, not a Map) - RightClickMenuItem, FindAndClickBlock,
; ClearAllInstances all do. Composites inherently accumulate many named
; optional fields (region, ctrl, waitTimeoutMs, pollMs, label,
; clickX/clickY, settleMs, menuSettleMs, preDelayMs, postDelayMs...)
; and a long positional list with skipped-slot commas is exactly the
; readability failure opts style exists to prevent. Detection/action
; PRIMITIVES (Find.ahk, Act.ahk, Grid.ahk, Inv.ahk) stay positional -
; that's the layer split: primitives positional, composites opts.
; Shared opts field names are standardized too: path/w/h/tol/transColor
; for an image spec, colors/tol/blockW/blockH for a block spec, ctrl,
; settleMs, waitTimeoutMs, pollMs, label, preDelayMs/postDelayMs.
;
; CONTRACT CHANGE from v6: clickOffsetX/Y are GONE, not just defaulted
; to 0 - v7's hard rule is no click-offset compensation constants
; anywhere; a click that needs an offset to land correctly means the
; marker/size was measured wrong, so re-measure instead. clickX/clickY
; PINNING stays (an explicit override to click a static point instead
; of the found position) - that's a different, legitimate concept, not
; a compensation hack. `colors` is an array now (the v7 standard, see
; Find.ahk's header) instead of a single scalar color.
;
; FindAndClickImage (v6's PNG-flavored sibling) was deliberately NOT
; ported at first (2026-07-23) - it didn't correspond to any confirmed
; use case yet. ADDED for micro 24 (2026-07-23) once DepositAllToBank
; became a real, confirmed caller needing exactly "wait for a PNG
; (the deposit-all image), click it directly" - see below.
;
; GatherBankLoop for micro 25 (2026-07-23) - generalized from v6
; motherlode2.ahk's RunFullLoop/FullCycle/MineLoop shape (confirmed live
; there across many mine->hopper->sack->bank->return laps). Bots supply
; their own gather/bank closures (already built from TrackAndClick,
; ClickUntilCondition, TravelToPoint, DepositAllToBank etc.) - this
; composite is just the outer forever-loop plus the one real policy
; decision motherlode2 needed live: what to do when banking needed
; retries (see failurePolicy below).
; ============================================================

; Right-clicks (opts.x, opts.y) to open a context menu, waits up to
; opts.waitTimeoutMs for a specific menu entry (opts.path) to appear in
; a fixed searchBoxSize x searchBoxSize box CENTERED ON the click
; point, then left-clicks its center. Returns false (and does not
; click, but sends Esc to close the menu) if the item never appears -
; e.g. the right-clicked target didn't have that action available.
;
; opts:
;   x/y                     - required, the point to right-click
;   path/w/h/tol/transColor - required, menu-entry image spec (M2 core)
;   waitTimeoutMs           - required, give up if the entry never appears
;   searchBoxSize           - fixed box centered on the click point (default 512)
;   settleMs                - shared by both clicks (default 100, see below)
;   menuSettleMs            - gap after the right-click, before the FIRST
;                             search attempt (default 100, see below)
;   ctrl                    - hold Ctrl on the menu-item click ONLY (default false)
;   label                   - log prefix (default "RightClickMenuItem")
;   preDelayMs/postDelayMs  - bracket the whole composite (default 0)
;
; searchBoxSize is a fixed box around the click point, NOT derived from
; itemW/itemH - context menus can open in different directions
; depending on screen position and have several other entries besides
; the one being searched for, so the search area is sized independently
; of the one item's own image size. Built via RegionAround(x, y, 0, 0,
; searchBoxSize // 2) - a 0x0 "item" padded by half the box size on
; every side gives an exact searchBoxSize square centered on (x,y).
;
; settleMs is shared by BOTH clicks this composite makes: the initial
; right-click (MouseMove -> Sleep(settleMs) -> Click, same pattern
; ClickAt itself uses - a right-click with NO settle can fire before
; the client registers the new hover target, missing or right-clicking
; the wrong thing) AND the follow-up left-click on the found menu item
; (passed through to ClickAt instead of using its own hidden default).
;
; menuSettleMs is a SEPARATE gap, after the right-click fires and
; before the FIRST menu-item search attempt (not before the click
; itself - that's settleMs's job). Without it, the first search fires
; with zero gap after the click, which reliably misses (the context
; menu hasn't rendered yet) and falls through to a full pollMs (150ms)
; wait before the second attempt succeeds - wasting time rather than
; saving it. Confirmed live (2026-07-23): a 421ms total broke down as
; ~right-click settle + miss + full 150ms poll wait + hit + left-click
; settle; menuSettleMs replaces the wasted miss-then-150ms-wait with
; one deliberate wait, so the first real check usually succeeds.
; ctrl applies ONLY to the follow-up left-click on the menu item,
; not the right-click (Ctrl+right-click has no force-run meaning in
; OSRS - force-run applies to a LEFT click that triggers movement, and
; selecting a menu item can trigger the character walking/running over
; to reach whatever the menu item acts on).
RightClickMenuItem(opts) {
    x := opts.x
    y := opts.y
    path := opts.path
    w := opts.w
    h := opts.h
    tol := opts.tol
    transColor := opts.transColor
    waitTimeoutMs := opts.waitTimeoutMs
    searchBoxSize := opts.HasOwnProp("searchBoxSize") ? opts.searchBoxSize : 512
    settleMs := opts.HasOwnProp("settleMs") ? opts.settleMs : 100
    menuSettleMs := opts.HasOwnProp("menuSettleMs") ? opts.menuSettleMs : 100
    useCtrl := opts.HasOwnProp("ctrl") ? opts.ctrl : false
    label := opts.HasOwnProp("label") ? opts.label : "RightClickMenuItem"
    preDelayMs := opts.HasOwnProp("preDelayMs") ? opts.preDelayMs : 0
    postDelayMs := opts.HasOwnProp("postDelayMs") ? opts.postDelayMs : 0

    if (preDelayMs > 0)
        Pause(preDelayMs)

    ReleasePendingModifiersNow()

    MouseMove(x, y, 5)
    Sleep(settleMs)
    Click(x, y, "Right")
    Sleep(menuSettleMs)

    region := RegionAround(x, y, 0, 0, searchBoxSize // 2)
    cx := 0, cy := 0
    ItemVisible() {
        return FindImage(region[1], region[2], region[3], region[4], path, w, h, tol, transColor, &cx, &cy)
    }

    found := WaitUntil(ItemVisible, waitTimeoutMs, 150)
    if (!found) {
        LogLine(label ": item not found in menu (" path "), closing menu")
        Send("{Esc}")
        return false
    }

    LogLine(label ": found menu item at " cx "," cy)
    ClickAt(cx, cy, useCtrl, false, settleMs)

    if (postDelayMs > 0)
        Pause(postDelayMs)
    return true
}

; ---------- find-and-click (one-shot wait-then-click, M7 full) ----------
;
; Waits up to opts.waitTimeoutMs for a solid-color block to appear
; (any color in opts.colors), then clicks it - at its found center, or
; at opts.clickX/clickY if given (an explicit pin, e.g. a static UI
; button whose search-verified presence doesn't change where a caller
; wants to click). No click-offset compensation - see file header.
;
; opts:
;   colors/tol/blockW/blockH - required, array + block spec (M1/M5 core)
;   verifyPercent - block-match strictness, 100 = strict (default 100) -
;                   see Find.ahk's FindFilledBlock doc comment; exposed
;                   here for config consistency with AcquireClosestInBox/
;                   TrackAndClick, which already take it
;   region        - [x1,y1,x2,y2] to search (default whole screen)
;   clickX/clickY - optional pin - click here instead of the found center
;   ctrl          - hold Ctrl (force-run) while clicking (default false)
;   waitTimeoutMs - give up if the block never appears (required)
;   pollMs        - tick-aligned poll interval (default 300)
;   settleMs      - passed through to ClickAt (default 100)
;   label         - Say()/log prefix (default "FindAndClickBlock")
;   itemLabel     - what's being searched/clicked (default "target")
;   preDelayMs/postDelayMs - bracket the whole composite (default 0)
;
; Returns true if found+clicked, false (logged, no throw) if it never
; appeared within waitTimeoutMs. Throws BotStopped (propagated from
; WaitUntil/Pause) if the user stops mid-wait.
FindAndClickBlock(opts) {
    colors := opts.colors
    tol := opts.tol
    blockW := opts.blockW
    blockH := opts.blockH
    verifyPercent := opts.HasOwnProp("verifyPercent") ? opts.verifyPercent : 100
    region := opts.HasOwnProp("region") ? opts.region : [0, 0, A_ScreenWidth - 1, A_ScreenHeight - 1]
    useCtrl := opts.HasOwnProp("ctrl") ? opts.ctrl : false
    waitTimeoutMs := opts.waitTimeoutMs
    pollMs := opts.HasOwnProp("pollMs") ? opts.pollMs : 300
    settleMs := opts.HasOwnProp("settleMs") ? opts.settleMs : 100
    label := opts.HasOwnProp("label") ? opts.label : "FindAndClickBlock"
    itemLabel := opts.HasOwnProp("itemLabel") ? opts.itemLabel : "target"
    preDelayMs := opts.HasOwnProp("preDelayMs") ? opts.preDelayMs : 0
    postDelayMs := opts.HasOwnProp("postDelayMs") ? opts.postDelayMs : 0

    if (preDelayMs > 0)
        Pause(preDelayMs)

    foundX := 0, foundY := 0, foundColor := 0
    Visible() {
        found := FindAnyFilledBlock(region[1], region[2], region[3], region[4], colors, tol, blockW, blockH, &fx, &fy, &fc, verifyPercent)
        if (found) {
            foundX := fx, foundY := fy, foundColor := fc
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
    Say(label ": clicking " itemLabel " at " targetX "," targetY)
    ClickAt(targetX, targetY, useCtrl, false, settleMs)

    if (postDelayMs > 0)
        Pause(postDelayMs)
    return true
}

; ---------- find-and-click-image (one-shot wait-then-click, PNG sibling of FindAndClickBlock) ----------
;
; Same shape as FindAndClickBlock, but waits for a single PNG (FindImage)
; instead of a solid-color block. Added for micro 24's real caller
; (DepositAllToBank needs to wait for the "deposit all" image, then
; click it) - see this file's header for why it wasn't ported earlier.
; No click-offset compensation, same as FindAndClickBlock.
;
; opts:
;   path/w/h/tol/transColor - required, image spec (M2 core)
;   region        - [x1,y1,x2,y2] to search (default whole screen)
;   clickX/clickY - optional pin - click here instead of the found center
;   ctrl          - hold Ctrl (force-run) while clicking (default false)
;   waitTimeoutMs - give up if the image never appears (required)
;   pollMs        - tick-aligned poll interval (default 300)
;   settleMs      - passed through to ClickAt (default 100)
;   label         - Say()/log prefix (default "FindAndClickImage")
;   itemLabel     - what's being searched/clicked (default "target")
;   preDelayMs/postDelayMs - bracket the whole composite (default 0)
;
; Returns true if found+clicked, false (logged, no throw) if it never
; appeared within waitTimeoutMs. Throws BotStopped (propagated from
; WaitUntil/Pause) if the user stops mid-wait.
FindAndClickImage(opts) {
    path := opts.path
    w := opts.w
    h := opts.h
    tol := opts.tol
    transColor := opts.transColor
    region := opts.HasOwnProp("region") ? opts.region : [0, 0, A_ScreenWidth - 1, A_ScreenHeight - 1]
    useCtrl := opts.HasOwnProp("ctrl") ? opts.ctrl : false
    waitTimeoutMs := opts.waitTimeoutMs
    pollMs := opts.HasOwnProp("pollMs") ? opts.pollMs : 300
    settleMs := opts.HasOwnProp("settleMs") ? opts.settleMs : 100
    label := opts.HasOwnProp("label") ? opts.label : "FindAndClickImage"
    itemLabel := opts.HasOwnProp("itemLabel") ? opts.itemLabel : "target"
    preDelayMs := opts.HasOwnProp("preDelayMs") ? opts.preDelayMs : 0
    postDelayMs := opts.HasOwnProp("postDelayMs") ? opts.postDelayMs : 0

    if (preDelayMs > 0)
        Pause(preDelayMs)

    foundX := 0, foundY := 0
    Visible() {
        found := FindImage(region[1], region[2], region[3], region[4], path, w, h, tol, transColor, &fx, &fy)
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
    Say(label ": clicking " itemLabel " at " targetX "," targetY)
    ClickAt(targetX, targetY, useCtrl, false, settleMs)

    if (postDelayMs > 0)
        Pause(postDelayMs)
    return true
}

; ---------- clear-all-instances (repeat-click until a search comes up empty) ----------
;
; Promoted from v6 sudoku.ahk's hand-rolled ClearSearchZone (2026-07-20
; bug note there: the search zone is a STATIC, non-respawning field of
; icons, so the correct stop condition is "a single search attempt
; right now found nothing" - NOT a timeout like FindAndClickBlock/
; WaitForImage use. Confirmed live in v6 sudoku.ahk. Only one caller
; there, so it stayed local until this rewrite's "promotions" decision
; (ClearAllInstances IN) made it a real Lib composite.
;
; Repeatedly finds+clicks every on-screen instance of an image within
; a region until a single search attempt finds nothing. Returns true
; once the zone is clear (logs how many were clicked), false only if
; maxIterations is hit (a click probably isn't registering - a clean
; stop rather than spinning forever). Throws BotStopped (propagated
; from Pause) if the user stops mid-clear - never swallowed.
;
; opts:
;   region                      - required, [x1,y1,x2,y2] to search
;   path/w/h/tol/transColor     - required, image spec (M2 core)
;   ctrl                        - hold Ctrl while clicking (default false)
;   settleMs                    - passed through to ClickAt, and the gap
;                                  after each click before re-searching
;                                  (default 100)
;   maxIterations               - safety cap (default 200)
;   label                       - Say()/log prefix (default "ClearAllInstances")
;   preDelayMs/postDelayMs      - bracket the whole composite (default 0)
ClearAllInstances(opts) {
    region := opts.region
    path := opts.path
    w := opts.w
    h := opts.h
    tol := opts.tol
    transColor := opts.transColor
    useCtrl := opts.HasOwnProp("ctrl") ? opts.ctrl : false
    settleMs := opts.HasOwnProp("settleMs") ? opts.settleMs : 100
    maxIterations := opts.HasOwnProp("maxIterations") ? opts.maxIterations : 200
    label := opts.HasOwnProp("label") ? opts.label : "ClearAllInstances"
    preDelayMs := opts.HasOwnProp("preDelayMs") ? opts.preDelayMs : 0
    postDelayMs := opts.HasOwnProp("postDelayMs") ? opts.postDelayMs : 0

    if (preDelayMs > 0)
        Pause(preDelayMs)

    clicked := 0
    loop maxIterations {
        found := FindImage(region[1], region[2], region[3], region[4], path, w, h, tol, transColor, &cx, &cy)
        if (!found) {
            Say(label ": zone clear (" clicked " instance" (clicked = 1 ? "" : "s") " clicked)")
            if (postDelayMs > 0)
                Pause(postDelayMs)
            return true
        }

        Say(label ": clicking instance at " cx "," cy)
        ClickAt(cx, cy, useCtrl, false, settleMs)
        clicked += 1
        Pause(settleMs)
    }

    Say(label ": maxIterations (" maxIterations ") hit - a click may not be registering")
    return false
}

; ---------- verify-slots-and-drop (pointer-walk classify-or-drop) ----------
;
; Generalized from v6 motherlode2.ahk's MineFullnessCheck (confirmed
; live there): a pointer walks inventory slots startSlot->endSlot in
; order. A still-empty slot at the pointer just means "not done yet."
; Once the pointer's slot fills, it's classified against a reference
; image sized to fit that slot's own Grid cell (path/w/h/tol/
; transColor) - a match advances the pointer; a non-match (e.g. a gem
; landing where pay-dirt was expected) gets shift-dropped (DropSlot)
; and the SAME slot is re-checked next call, since dropping doesn't
; move the pointer.
;
; Returns a MAKER function, not the check itself - the pointer is
; per-instance state that must survive across many polled calls (the
; same shape TargetLock/TrackAndClick need, per the v7 plan), so this
; returns a closure bundling that state instead of requiring the caller
; to thread a byref pointer through every call. Call the maker ONCE per
; verification run (e.g. once per mining trip before InventoryFull());
; call the returned function each poll tick - it returns true once
; endSlot is confirmed a real match (everything from startSlot to
; endSlot is verified, no gems anywhere), false otherwise.
;
; opts:
;   startSlot/endSlot          - required, 1-based inclusive slot range to walk
;   path/w/h/tol/transColor    - required, reference image spec (M2 core) -
;                                 w/h should match the slot's own cell size
;                                 (e.g. INV_GRID's cellW/cellH) so the check
;                                 stays confined to that one slot
;   dropSettleMs               - passed through to DropSlot (default 100)
;   label                      - Say()/log prefix (default "VerifySlotsAndDrop")
VerifySlotsAndDrop(opts) {
    startSlot := opts.startSlot
    endSlot := opts.endSlot
    path := opts.path
    w := opts.w
    h := opts.h
    tol := opts.tol
    transColor := opts.transColor
    dropSettleMs := opts.HasOwnProp("dropSettleMs") ? opts.dropSettleMs : 100
    label := opts.HasOwnProp("label") ? opts.label : "VerifySlotsAndDrop"

    slot := startSlot

    return CheckNext

    CheckNext() {
        if (slot > endSlot)
            return true

        if (!SlotFull(slot))
            return false

        SlotCorner(slot, &cx, &cy)
        isMatch := FindImage(cx, cy, cx + w - 1, cy + h - 1, path, w, h, tol, transColor, &fx, &fy)

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
; Straight port from v6 Lib\Steps.ahk, no contract change - confirmed
; live there in motherlode2's DepositHopper() (hopper deposit, capped
; retry budget) and WithdrawAndBankOnce() (sack withdrawal, uncapped
; retry). The "click a thing, wait patiently for a condition, and if it
; doesn't hold yet re-click every N ms until it does" shape - exists
; because these targets are SHARED/laggy: one click doesn't always
; register the effect right away (a backed-up hopper still draining,
; sack items arriving late), so the first click gets a generous patient
; wait and only on a miss does it downgrade to hammering re-clicks -
; never spamming when one click was enough.
;
; opts:
;   click         - zero-arg closure that performs the click and returns
;                   bool; false means the marker/image never appeared, so
;                   abort the whole thing (required). Callers pass e.g.
;                   () => FindAndClickBlock({...}).
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
;   past the first wait (a caller that cares - like a hopper's stall
;   heuristic - reads it; one that doesn't just omits the argument).
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

; ---------- track-and-click (M8: acquire/track/drift-reject/anchor-hold) ----------
;
; Straight port from v6 Lib\Steps.ahk, no contract change - the biggest
; composite in the project, proven across Woodcutting/Motherlode/
; Motherlode2's entire vein/tree tracking loop. `colors` is already an
; array (was even before the v7 standard existed - TrackAndClick is
; where the "equal priority multi-color" idea originated).
;
; opts:
;   colors        - array of candidate colors, equal priority (required)
;   tol           - per-channel tolerance (default 5)
;   blockW/blockH - required solid block size (required)
;   verifyPercent - block-match strictness, 100 = strict (default 100)
;   refX/refY     - character's on-screen point, used for acquire proximity (required)
;   acquireRadii  - array of expanding square-ring half-sizes tried before
;                   the region-wide fallback (default [] = region-wide only)
;   region        - [x1,y1,x2,y2] outer bound clamping BOTH the acquire rings/
;                   fallback AND the track-mode re-search box (default whole screen)
;   trackRadius   - half-size of the narrowed re-search box once locked (required)
;   maxDriftPx    - reject a track match this far from the last position (default 40)
;
;   TUNING trackRadius vs maxDriftPx (learned live tuning in v6, worth
;   keeping - a same-color-neighbor scenario makes this worth getting right):
;     - trackRadius is the SEARCH NET: how far from the last known spot to
;       even look. Too small and legitimate camera pan/walking moves the
;       target clean out of the search box (reported "not found" even
;       though it's still on screen).
;     - maxDriftPx is a SUSPICION CHECK applied AFTER a match is found
;       inside that net: "this match is far enough from last tick that
;       it's probably a DIFFERENT same-colored block standing nearby, not
;       the one being tracked - reject it." Only matters when a SECOND
;       instance of the SAME locked color can appear within roughly
;       maxDriftPx of the real target - a different-colored neighbor is
;       already excluded by track mode only searching lockedColor.
;     - Measure real per-tick drift from the log ("found ... but Npx from
;       last position ... rejecting" lines that are clearly still the
;       SAME target, not a real re-acquire) - that N is the floor. v6's
;       own tuning: normal camera pan while walking toward a ~77x77 tree
;       needed ~120px; 40px was far too tight and caused false
;       "depleted, re-acquire" cascades that could land on a different
;       candidate color entirely. Keep maxDriftPx under roughly half of
;       trackRadius, and well under the distance to the nearest
;       SAME-colored duplicate if one exists.
;     - BUG FOUND LIVE (2026-07-23, v7 micro 21): trackRadius ITSELF must
;       also stay under roughly half the distance to the nearest
;       SAME-colored duplicate - not just maxDriftPx. Track mode's
;       re-search is a single-color FindFilledBlock call, which returns
;       whichever match native scan order hits FIRST inside the box, NOT
;       necessarily the one closest to the last position. If trackRadius
;       is big enough that a same-colored neighbor falls inside the same
;       search box, which instance gets found each tick becomes
;       essentially arbitrary - maxDriftPx can only reject a bad match
;       AFTER the fact, it can't make FindFilledBlock return the right
;       one in the first place. Confirmed live: two real veins 46px
;       apart (same color by design - this user's convention is same
;       color when there's a gap, distinct colors only when veins are
;       adjacent with no gap) jumped between each other with
;       trackRadius=96 (bigger than the gap itself, so both fell inside
;       one search box every tick) - fixed by shrinking trackRadius to
;       well under half the real measured gap.
;   stableTicks     - consecutive in-tolerance ticks before "stable" (default 2)
;   moveTolerancePx - px drift still counted "stable" (default 10)
;   cooldownMs      - min ms between clicks once stable (required)
;   reclickAfterMs  - re-click cadence while not yet stable (required)
;   ctrl            - hold Ctrl (force-run) while clicking (default false)
;   postClickSettleMs - pause right after each click, before the loop's next
;                   re-search (default 0). BUG FOUND LIVE (2026-07-23, v7
;                   micro 21): v7's ClickAt releases Ctrl ASYNCHRONOUSLY
;                   (a deliberate, confirmed micro 08 change - holding a
;                   key costs no real time, so ClickAt returns immediately
;                   instead of blocking for holdMs like v6's did). That
;                   incidentally removed a ~100ms timing cushion v6 had
;                   for free (its synchronous hold meant the NEXT re-search
;                   always fired ~100ms later than v7's now does). If the
;                   real target has ANY brief post-click visual flicker
;                   (a hit animation frame, a client-side highlight), that
;                   tighter v7 timing can catch it mid-flicker, read "not
;                   found", and falsely declare a perfectly healthy target
;                   depleted - confirmed live: a vein that does NOT deplete
;                   was reported "depleted or lost" after literally every
;                   single click. postClickSettleMs restores an explicit,
;                   configurable version of that cushion without
;                   reintroducing a blocking Ctrl-hold.
;   until           - zero-arg function; loop stops (returns true) once it's true (required)
;   timeoutMs       - ABSOLUTE backstop for the whole phase; loop stops (returns
;                     false) past this no matter what (default 1800000 / 30min)
;   progressTimeoutMs - the REAL safety net; loop stops (returns false) if
;                     nothing has been acquired, depleted, or clicked for this
;                     long (default 300000 / 5min)
;   pollMs          - tick-aligned loop interval (default 300)
;
;   TIMEOUTMS VS PROGRESSTIMEOUTMS (learned live tuning in v6): a single
;   fixed timeoutMs counting the WHOLE phase is the wrong shape for "did
;   this get stuck" - a phase that's working perfectly just legitimately
;   takes longer some runs (farther trees, slower respawns, walking after
;   a bank trip all eat into the same budget), so a tight total-time cap
;   fires on a genuinely healthy run and looks identical in the log to a
;   real stall. progressTimeoutMs fixes this by resetting its clock on
;   any real evidence of activity (an acquire, a depletion, or a click) -
;   it only fires when NOTHING has happened for that long, which is what
;   "stuck" actually means. timeoutMs stays as a generous absolute
;   backstop underneath it.
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
    postClickSettleMs := opts.HasOwnProp("postClickSettleMs") ? opts.postClickSettleMs : 0
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
                        if (postClickSettleMs > 0)
                            Pause(postClickSettleMs)
                    } else {
                        Say("Tracking stable target at " outX "," outY " (cooldown active, search " searchMs " ms)")
                    }
                } else {
                    if (lastClickTime == 0 || (A_TickCount - lastClickTime) > reclickAfterMs) {
                        ClickAt(outX, outY, useCtrl)
                        lastClickTime := A_TickCount
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

; ---------- target lock (verbatim port of v5 Detection\TargetLock.ahk, via v6) ----------

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
; Port from v6 Lib\Steps.ahk with clickOffsetX/Y REMOVED - v7's hard
; rule is no click-offset compensation constants anywhere (see file
; header); the click lands directly at the found image's center. Waits
; for a transient item to appear on screen, clicks it, then confirms
; the pickup actually registered via a before/after pixel-box snapshot
; diff (TakeSnapshot/HasChanged, micro 14) around wherever the caller
; expects visible proof (e.g. an inventory slot or a status counter) -
; NOT by re-searching for the image again, since a picked-up item is
; gone, not moved, so there's nothing left to re-find.
;
; opts:
;   imagePath/imageW/imageH - the appeared item's image (required)
;   imageTol      - shade-of-variation tolerance (default 5)
;   transColor    - background see-through color, "" to disable (default "")
;   region        - [x1,y1,x2,y2] to search for the image (default whole screen)
;   appearTimeoutMs - give up if the image never appears (required)
;   ctrl          - hold Ctrl (force-run) while clicking (default false)
;   confirmBox    - {x, y, w, h} snapshotted BEFORE the click, polled AFTER (required)
;   changeTol     - per-channel tolerance before a pixel counts as "changed" (default 10)
;   targetSamples - sample budget for the confirm box snapshot (default 50)
;   confirmTimeoutMs - give up waiting for the pickup to register (required)
;   pollMs        - tick-aligned poll interval for both waits (default 300)
;   label         - Say()/log prefix (default "PickupAppeared")
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
    useCtrl := opts.HasOwnProp("ctrl") ? opts.ctrl : false
    box := opts.confirmBox
    changeTol := opts.HasOwnProp("changeTol") ? opts.changeTol : 10
    targetSamples := opts.HasOwnProp("targetSamples") ? opts.targetSamples : 50
    confirmTimeoutMs := opts.confirmTimeoutMs
    pollMs := opts.HasOwnProp("pollMs") ? opts.pollMs : 300
    label := opts.HasOwnProp("label") ? opts.label : "PickupAppeared"

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
        Say(label ": NEVER APPEARED after " (A_TickCount - t0) " ms - giving up")
        return false
    }

    LogLine(label ": appeared at " foundX "," foundY " after " (A_TickCount - t0) " ms - snapshotting confirm box BEFORE click")

    ; Snapshot BEFORE the click - the "before" state is what lets
    ; HasChanged detect a change caused by the click, not just any change.
    snapshot := TakeSnapshot(box.x, box.y, box.w, box.h, targetSamples)

    Say(label ": clicking item at " foundX "," foundY)
    ClickAt(foundX, foundY, useCtrl)

    BoxChangedNow() {
        return HasChanged(snapshot, box.x, box.y, changeTol)
    }

    t1 := A_TickCount
    confirmed := WaitUntil(BoxChangedNow, confirmTimeoutMs, pollMs)
    if (confirmed) {
        Say(label ": CONFIRMED (" (A_TickCount - t1) " ms after click, " (A_TickCount - t0) " ms total)")
        return true
    }
    Say(label ": CLICKED but NOT CONFIRMED - box never changed within " confirmTimeoutMs "ms")
    return false
}

; ---------- travel-to-point (click a travel marker, confirm arrival) ----------
;
; Port from v6 Lib\Steps.ahk (GoToSackArea/ReturnToMine's shared shape),
; with two v7 contract changes: markerClickOffsetX/Y are GONE (v7's hard
; rule against click-offset compensation - see file header), and
; markerColor/arriveColor are now markerColors/arriveColors ARRAYS (the
; v7 standard, see Find.ahk's header) instead of single scalar colors.
;
; The "click a travel marker, then wait for a block to show up at an
; EXACT expected point (not just anywhere on screen), with a
; whole-screen diagnostic on failure" shape. Reuses FindAndClickBlock
; for the click and BlockAtPoint for the exact-point arrival check; the
; whole-screen FindAnyFilledBlock fallback on a miss (found-elsewhere
; vs not-found-anywhere) lives here so every caller gets that same
; debugging aid for free.
;
; MARKER CLICK MODE (added 2026-07-23): a travel marker is sometimes a
; genuinely fixed, known point (e.g. a UI button, or a spot that never
; visually changes) rather than something worth color-searching for at
; all. Give markerClickX/markerClickY instead of markerColors/etc. to
; skip the color search entirely and ClickAt that fixed point directly -
; the same "pin vs search" distinction FindAndClickBlock's clickX/clickY
; already draws (micro 11's F8), just applied to skip the WAIT too,
; since there's nothing to wait for at a point that's simply always
; clickable. markerColors/markerTol/markerBlockW/markerBlockH/
; markerWaitTimeoutMs are only required in SEARCH mode (no
; markerClickX/Y given).
;
; opts:
;   markerClickX/markerClickY - fixed point to click directly, no search
;                           (SEARCH MODE fields below are ignored if given)
;   markerColors/markerTol/markerBlockW/markerBlockH - the travel marker
;                           block (required in SEARCH mode, colors array)
;   markerWaitTimeoutMs   - give up if the marker never appears (required in SEARCH mode)
;   markerRegion          - [x1,y1,x2,y2] to search for the marker (default whole screen)
;   markerItemLabel       - label for the marker in logs (default "travel marker")
;   arriveColors/arriveTol/arriveBlockW/arriveBlockH - the arrival block
;                           (required, colors array)
;   arriveCornerX/arriveCornerY - the arrival block's measured top-left CORNER
;                           (required) - the expected CENTER is computed here via
;                           Lib\Core.ahk's CenterX/CenterY, never stored by the caller
;   arrivePosTolPx        - slack around that center (BlockAtPoint's posTolPx) (required)
;   arriveWaitTimeoutMs   - give up if arrival never confirms (required)
;   ctrl                  - hold Ctrl while clicking the marker (default false)
;   settleMs              - passed through to ClickAt in PIN mode only (default 100)
;   pollMs                - poll interval for the arrival wait (default 300)
;   label                 - Say()/log prefix (default "TravelToPoint")
;
; Returns true on confirmed arrival, false (logged, no throw) if the marker
; never appears (SEARCH mode) or arrival never confirms. Throws BotStopped
; if the user stops mid-travel - never swallowed here.
TravelToPoint(opts) {
    arriveColors := opts.arriveColors
    arriveTol := opts.arriveTol
    arriveBlockW := opts.arriveBlockW
    arriveBlockH := opts.arriveBlockH
    arriveX := CenterX(opts.arriveCornerX, arriveBlockW)
    arriveY := CenterY(opts.arriveCornerY, arriveBlockH)
    arrivePosTolPx := opts.arrivePosTolPx
    arriveWaitTimeoutMs := opts.arriveWaitTimeoutMs
    useCtrl := opts.HasOwnProp("ctrl") ? opts.ctrl : false
    settleMs := opts.HasOwnProp("settleMs") ? opts.settleMs : 100
    pollMs := opts.HasOwnProp("pollMs") ? opts.pollMs : 300
    label := opts.HasOwnProp("label") ? opts.label : "TravelToPoint"

    if (opts.HasOwnProp("markerClickX") && opts.HasOwnProp("markerClickY")) {
        Say(label ": clicking pinned marker point " opts.markerClickX "," opts.markerClickY)
        ClickAt(opts.markerClickX, opts.markerClickY, useCtrl, false, settleMs)
    } else {
        markerColors := opts.markerColors
        markerTol := opts.markerTol
        markerBlockW := opts.markerBlockW
        markerBlockH := opts.markerBlockH
        markerWaitTimeoutMs := opts.markerWaitTimeoutMs
        markerRegion := opts.HasOwnProp("markerRegion") ? opts.markerRegion : [0, 0, A_ScreenWidth - 1, A_ScreenHeight - 1]
        markerItemLabel := opts.HasOwnProp("markerItemLabel") ? opts.markerItemLabel : "travel marker"

        if (!FindAndClickBlock({
            colors: markerColors, tol: markerTol, blockW: markerBlockW, blockH: markerBlockH,
            region: markerRegion, settleMs: settleMs,
            ctrl: useCtrl, waitTimeoutMs: markerWaitTimeoutMs, pollMs: pollMs,
            label: label, itemLabel: markerItemLabel
        }))
            return false
    }

    ArrivedAtPoint() {
        return BlockAtPoint(arriveX, arriveY, arriveColors, arriveTol,
            arriveBlockW, arriveBlockH, arrivePosTolPx, &fx, &fy, &fc)
    }

    Say(label ": waiting for arrival")
    arrived := WaitUntil(ArrivedAtPoint, arriveWaitTimeoutMs, pollMs)
    if (!arrived) {
        wholeScreenFound := FindAnyFilledBlock(0, 0, A_ScreenWidth - 1, A_ScreenHeight - 1,
            arriveColors, arriveTol, arriveBlockW, arriveBlockH, &wx, &wy, &wc)
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

; ---------- deposit-all-to-bank (marker -> deposit image -> confirm) ----------
;
; Port from v6 Lib\Steps.ahk (the shape existed in Woodcutting's Bank(),
; Motherlode2's WithdrawAndBankOnce() tail, and Crafting's deposit
; steps), with two v7 contract changes: markerClickOffsetY is GONE (no
; click-offset compensation anywhere in v7), and markerColor is now
; markerColors, an array (the v7 standard). The confirm step is
; OPTIONAL: some bots verify the deposit registered (a caller-supplied
; condition), others just deposit and move on to restocking.
;
; opts:
;   markerColors/markerTol/markerBlockW/markerBlockH - the bank/deposit marker
;                           (required, colors array)
;   markerWaitTimeoutMs   - give up if the marker never appears (required)
;   markerRegion          - [x1,y1,x2,y2] to search for the marker (default whole screen)
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
    markerItemLabel := opts.HasOwnProp("markerItemLabel") ? opts.markerItemLabel : "deposit-box marker"
    depositTol := opts.HasOwnProp("depositTol") ? opts.depositTol : 5
    depositTransColor := opts.HasOwnProp("depositTransColor") ? opts.depositTransColor : ""
    depositItemLabel := opts.HasOwnProp("depositItemLabel") ? opts.depositItemLabel : "deposit box"
    useCtrl := opts.HasOwnProp("ctrl") ? opts.ctrl : false
    pollMs := opts.HasOwnProp("pollMs") ? opts.pollMs : 300
    label := opts.HasOwnProp("label") ? opts.label : "DepositAllToBank"

    markerOpts := {
        colors: opts.markerColors, tol: opts.markerTol, blockW: opts.markerBlockW, blockH: opts.markerBlockH,
        region: markerRegion, ctrl: useCtrl,
        waitTimeoutMs: opts.markerWaitTimeoutMs, pollMs: pollMs, label: label, itemLabel: markerItemLabel
    }
    if (opts.HasOwnProp("markerClickX"))
        markerOpts.clickX := opts.markerClickX
    if (opts.HasOwnProp("markerClickY"))
        markerOpts.clickY := opts.markerClickY
    if (!FindAndClickBlock(markerOpts))
        return false

    depositOpts := {
        path: opts.depositImagePath, w: opts.depositImageW, h: opts.depositImageH,
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
; Port from v6 Lib\Steps.ahk. Runs a "withdraw plan" - a list of
; [slot, clicks] pairs. BankSlotCenter (Lib\Inv.ahk) maps each entry's
; slot to a screen point, clicked that many times before moving to the
; next entry - no fullness check, matches what was asked for exactly.
RunRestockPlan(plan, ctrl := false) {
    for entry in plan {
        BankSlotCenter(entry[1], &x, &y)
        loop entry[2]
            ClickAt(x, y, ctrl)
    }
}

; ---------- gather-bank-loop (forever: gather until full -> bank -> repeat) ----------
;
; Generalized from v6 motherlode2.ahk's RunFullLoop/FullCycle/MineLoop
; (confirmed live across many mine->hopper->sack->bank->return laps).
; This composite is deliberately thin - it does NOT know about
; TrackAndClick, hoppers, sacks, or travel markers. A bot builds its own
; gather/bank closures out of whatever composites its scenario needs
; (TrackAndClick, ClickUntilCondition, TravelToPoint, DepositAllToBank,
; RunRestockPlan, ...) and hands them here as zero-arg functions; this
; loop just repeats gather->bank forever until one of them fails, F6
; stops, or maxCycles is hit.
;
; opts:
;   gather        - zero-arg closure; gathers until "full" (or whatever
;                   the bot's own until-condition means), returns bool
;                   (required). Typically wraps TrackAndClick.
;   bank          - zero-arg closure; travels to the bank, deposits,
;                   restocks, travels back - whatever one full bank trip
;                   means for this bot, returns bool (required).
;   onGatherFailed - "stop" (default) or a caller-supplied policy: this
;                   is intentionally left as a plain bool return - see
;                   below for why there's no separate "retry" mode here.
;   maxCycles     - 0 = forever (default), >0 = stop after this many
;                   completed gather+bank cycles (mainly for testing -
;                   a real bot leaves this at 0 and relies on F6/failure)
;   label         - Say()/log prefix (default "GatherBankLoop")
;
;   FAILURE POLICY (why this is simpler than the plan's original
;   "retry-bank vs stop" idea): motherlode2's real g_HopperWasFull
;   heuristic isn't "retry banking" at all - it's "a bank-phase step
;   needed retries, so CUT GATHERING SHORT and go bank now instead of
;   continuing to gather" (see motherlode2.ahk's MineLoop hopper-cycle
;   comment). That decision is made INSIDE the gather closure itself
;   (which already knows its own hopper-cycle count and stall signal),
;   not by this outer loop - GatherBankLoop can't make that call without
;   duplicating knowledge the bot-specific closure already has. So the
;   only policy this composite owns is the boring, universal one: gather
;   failed or bank failed => stop the whole loop cleanly (false, logged).
;   A bot wanting motherlode2's "cut gathering short" behavior does it
;   the same way motherlode2 did - its `gather` closure reads its own
;   stall flag and returns early (true, having gathered less) instead of
;   pushing through more cycles.
;
; Returns false immediately (logged, no throw) the first time `gather`
; or `bank` returns false. Returns true only if maxCycles is given and
; reached. Throws BotStopped (propagated from whatever Pause/WaitUntil
; the gather/bank closures use internally) if the user stops mid-loop -
; never swallowed here.
GatherBankLoop(opts) {
    gather := opts.gather
    bank := opts.bank
    maxCycles := opts.HasOwnProp("maxCycles") ? opts.maxCycles : 0
    label := opts.HasOwnProp("label") ? opts.label : "GatherBankLoop"

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

        if (maxCycles > 0 && cycle >= maxCycles) {
            Say(label ": reached maxCycles (" maxCycles ") - stopping")
            return true
        }
    }
}
