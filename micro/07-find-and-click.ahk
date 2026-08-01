; ============================================================
; v8 micro 07 - Steps.ahk pt 1: FindAndClick, ClearAllInstances,
; PickupAppeared
;
; Combines v7 micros 11 (find+click, incl. clickX/clickY pin
; override), 17 (ClearAllInstances), and 22 (PickupAppeared) into
; one micro. Also proves the pin-jitter fix: v7's pin inherited
; jitter sized from the SEARCHED target, not the pin itself; v8's
; pin is its own ClickTarget with its own w/h, so a small pin next
; to a big search target gets small (correctly-sized) jitter.
;
; WHAT IT DOES
;   F5  = FindAndClick, block spec, no pin - clicks the found center
;         directly (jitter sized from the search target itself)
;   F6  = request stop
;   F7  = FindAndClick, SAME search (a big BLOCK_TARGET) but with a
;         small PIN_TARGET as opts.clickTarget - logs both target
;         sizes so you can see the click used the pin's (smaller)
;         size, not the search target's
;   F8  = probe: ClearAllInstances against CLEAR_TARGET in
;         CLEAR_REGION
;   F9  = PickupAppeared against PICKUP_TARGET (image spec),
;         confirmed via CONFIRM_BOX pixel diff
;   F12 = exit
;
; LIVE CONFIRM:
;   1. F5 - clicks land inside the found block, scattered, never the
;      exact same pixel twice.
;   2. F7 - clicks land inside the SMALL pin's box, not scattered
;      across the big search target's box - confirms the pin-jitter
;      fix.
;   3. F8 - repeatedly clicks every matching instance in the region
;      until none remain, then reports cleared; if instances never
;      stop appearing, confirm it reports FAILED at MAX_ITERATIONS
;      rather than looping forever.
;   4. F9 - clicks the transient image once it appears, confirms via
;      the pixel-diff box (e.g. an inventory slot filling), not by
;      re-searching for the image.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v8.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "07-find-and-click"

; ======= EDIT THESE FOR YOUR TEST =======================================
BLOCK_TARGET := {colors: [0x00FF00, 0xFF980A], tol: 5, w: 45, h: 45}
WAIT_TIMEOUT_MS := 15000

; A deliberately SMALL pin near the block target's expected area -
; edit PIN_X/Y to a real point on your screen for a meaningful test.
PIN_TARGET := ClickTarget(1249, 712, 13, 13)

CLEAR_TARGET := {colors: [0x00FF00], tol: 5, w: 20, h: 20}
CLEAR_MAX_ITERATIONS := 200

PICKUP_TARGET := {path: IMAGES_DIR "\air-rune.png", w: 78, h: 20, tol: 5, transColor: "0x00FF00"}
PICKUP_APPEAR_TIMEOUT_MS := 15000
PICKUP_CONFIRM_BOX := {x: 2099, y: 801, w: 72, h: 64}   ; first inventory slot
PICKUP_CONFIRM_TIMEOUT_MS := 5000
; ==========================================================================

RunFindAndClick() {
    return FindAndClick({
        target: BLOCK_TARGET, region: GameZoneRegion(), waitTimeoutMs: WAIT_TIMEOUT_MS,
        label: "micro07", itemLabel: "block target"
    })
}

RunFindAndClickPinned() {
    Say("micro07: search target " BLOCK_TARGET.w "x" BLOCK_TARGET.h ", pin target " PIN_TARGET.w "x" PIN_TARGET.h)
    return FindAndClick({
        target: BLOCK_TARGET, region: GameZoneRegion(), waitTimeoutMs: WAIT_TIMEOUT_MS,
        clickTarget: PIN_TARGET, label: "micro07-pinned", itemLabel: "block target"
    })
}

ProbeClearAll() {
    return ClearAllInstances({
        region: GameZoneRegion(), target: CLEAR_TARGET, maxIterations: CLEAR_MAX_ITERATIONS,
        label: "micro07-clear"
    })
}

RunPickup() {
    return PickupAppeared({
        target: PICKUP_TARGET, region: GameZoneRegion(), appearTimeoutMs: PICKUP_APPEAR_TIMEOUT_MS,
        confirmBox: PICKUP_CONFIRM_BOX, confirmTimeoutMs: PICKUP_CONFIRM_TIMEOUT_MS,
        label: "micro07-pickup"
    })
}

InstallBotHarness({
    run: RunFindAndClick,
    label: "micro07",
    probe: ProbeClearAll,
    extraHotkeys: [
        {key: "F7", handler: RunFindAndClickPinned, label: "pinned-click"},
        {key: "F9", handler: RunPickup, label: "pickup-appeared"}
    ]
})
