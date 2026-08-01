; ============================================================
; v8 micro 11 - Steps.ahk pt 3: TrackAndClick + TargetLock
;
; Ported from v7 micro 21 - the biggest single composite: acquire a
; target near a reference point, hold an anchor across ticks
; (TargetLock), reject sudden jumps beyond maxDriftPx, wait for
; stableTicks before the first click, then re-click on a randomized
; cadence while continuing to verify presence, until `until()` is
; satisfied or a timeout fires.
;
; WHAT IT DOES
;   F5  = run TrackAndClick against TREE_TARGET near CHAR_X/CHAR_Y,
;         until INVENTORY_FULL_SLOT reports full
;   F6  = request stop
;   F8  = probe: SlotProbe(INVENTORY_FULL_SLOT) - see the raw
;         sample-point colors driving the `until` condition
;   F12 = exit
;
; LIVE CONFIRM:
;   1. F5 - acquires the nearest match to CHAR_X/Y, clicks it once
;         it's stable (not on the very first noisy sample), keeps
;         tracking without re-clicking until RECLICK_AFTER_MS
;         elapses, re-acquires cleanly if the target visually
;         changes/depletes and a new one appears nearby.
;   2. Deliberately let the target go fully out of the search
;      region/off-screen - confirm it does NOT immediately fail, it
;      keeps trying to reacquire until PROGRESS_TIMEOUT_MS, THEN
;      fails cleanly.
;   3. Confirm clicks land inside the tracked block's own cell
;      (jitter bounded by TREE_TARGET.w/h), never the exact same
;      pixel twice.
;   4. F8 - probe output matches what the inventory slot actually
;      shows.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v8.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "11-track-and-click"

; ======= EDIT THESE FOR YOUR TEST =======================================
TREE_TARGET := {colors: [0x00FF00], tol: 5, w: 45, h: 45}

ACQUIRE_RADII := [160, 320]
TRACK_RADIUS_PX := 96
MAX_DRIFT_PX := 64
STABLE_TICKS_REQUIRED := 2
MOVE_TOLERANCE_PX := 4
COOLDOWN_MS := 0
RECLICK_AFTER_MS := [3000, 6000]
CLICK_SETTLE_MS := 100
POST_CLICK_SETTLE_MS := 100

INVENTORY_FULL_SLOT := 28
PROGRESS_TIMEOUT_MS := 300000
OVERALL_TIMEOUT_MS := 1800000
POLL_MS := 200
; ==========================================================================

RunTrack() {
    return TrackAndClick({
        target: TREE_TARGET, refX: CHAR_X, refY: CHAR_Y,
        acquireRadii: ACQUIRE_RADII, region: GameZoneRegion(),
        trackRadius: TRACK_RADIUS_PX, maxDriftPx: MAX_DRIFT_PX,
        stableTicks: STABLE_TICKS_REQUIRED, moveTolerancePx: MOVE_TOLERANCE_PX,
        cooldownMs: COOLDOWN_MS, reclickAfterMs: RECLICK_AFTER_MS,
        clickSettleMs: CLICK_SETTLE_MS, postClickSettleMs: POST_CLICK_SETTLE_MS,
        until: () => SlotFull(INVENTORY_FULL_SLOT),
        timeoutMs: OVERALL_TIMEOUT_MS, progressTimeoutMs: PROGRESS_TIMEOUT_MS, pollMs: POLL_MS,
        label: "micro11"
    })
}

ProbeSlot() {
    Say(SlotProbe(INVENTORY_FULL_SLOT))
}

InstallBotHarness({
    run: RunTrack,
    label: "micro11",
    probe: ProbeSlot
})
