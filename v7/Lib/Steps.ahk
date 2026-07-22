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
; hand-rolled ClearSearchZone - see below).
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
; opts-object style (a plain object, not a Map) is kept for these two -
; unlike the simpler positional-param primitives elsewhere in v7, these
; composites have too many named optional fields (region, ctrl,
; waitTimeoutMs, pollMs, label, itemLabel, clickX/clickY, settleMs,
; preDelayMs, postDelayMs) to read cleanly as a positional list. This
; matches v6's own established shape for exactly this composite - not
; a contradiction of v7's usual positional style, just recognizing
; opts-objects were always the right tool for this many options.
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
; ported here (2026-07-23) - it doesn't correspond to any confirmed use
; case yet. FindAndClickBlock (below) already covers both "a color box
; appears and IS the thing to click" and "wait for a marker, click a
; different pinned point instead" (see micro 11's F8 - clickX/clickY
; pinning). Add FindAndClickImage back if a bot ever needs "wait for a
; PNG, click it directly" as its own shape - don't keep untested,
; speculative code in Lib until then.
; ============================================================

; Right-clicks (x,y) to open a context menu, waits up to waitTimeoutMs
; for a specific menu entry (itemImagePath) to appear in a fixed
; searchBoxSize x searchBoxSize box CENTERED ON the click point, then
; left-clicks its center. Returns false (and does not click, but sends
; Esc to close the menu) if the item never appears - e.g. the
; right-clicked target didn't have that action available.
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
; useCtrl applies ONLY to the follow-up left-click on the menu item,
; not the right-click (Ctrl+right-click has no force-run meaning in
; OSRS - force-run applies to a LEFT click that triggers movement, and
; selecting a menu item can trigger the character walking/running over
; to reach whatever the menu item acts on).
RightClickMenuItem(x, y, itemImagePath, itemW, itemH, itemTol, transColor, waitTimeoutMs, searchBoxSize := 512, settleMs := 100, menuSettleMs := 100, useCtrl := false, preDelayMs := 0, postDelayMs := 0) {
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
        return FindImage(region[1], region[2], region[3], region[4], itemImagePath, itemW, itemH, itemTol, transColor, &cx, &cy)
    }

    found := WaitUntil(ItemVisible, waitTimeoutMs, 150)
    if (!found) {
        LogLine("RightClickMenuItem: item not found in menu (" itemImagePath "), closing menu")
        Send("{Esc}")
        return false
    }

    LogLine("RightClickMenuItem: found menu item at " cx "," cy)
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
        found := FindAnyFilledBlock(region[1], region[2], region[3], region[4], colors, tol, blockW, blockH, &fx, &fy, &fc)
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
