; ============================================================
; v7 micro 21 - acquire/track/click loop (TrackAndClick + TargetLock, M8)
;
; Straight port from v6 Lib\Steps.ahk, no contract change - the biggest
; composite in the project, proven across Woodcutting/Motherlode/
; Motherlode2's entire vein/tree tracking loop. Full design rationale
; (trackRadius vs maxDriftPx tuning, timeoutMs vs progressTimeoutMs) is
; documented in Lib\Steps.ahk directly above TrackAndClick - read that
; before tuning either pair blind.
;
; Loop shape: while `until` is false, ACQUIRE (expanding rings from
; REF_X/REF_Y, then whole region) a target of any TARGET_COLORS color;
; once acquired, TRACK it (narrowed re-search box locked to whichever
; color matched), reject a same-color match too far away as probably a
; different block (maxDriftPx), hold the current target if the exact
; anchor point is still the target color even on a miss tick, and click
; it periodically (cooldown once stable, faster re-click while not yet
; stable) until it depletes (search truly comes up empty) and the loop
; re-acquires.
;
; WHAT IT DOES
;   F5  = run TrackAndClick until UNTIL_SLOT becomes full (a real,
;         cheap until-condition - no need to grind a real 28-slot
;         inventory to test the loop's acquire/track/click mechanics)
;   F6  = request stop (interrupts instantly, mid-track or mid-wait)
;   Esc = exit the script
;
; LIVE CONFIRM (same checks v6 ran per real bot):
;   1. Put a marker of one TARGET_COLORS color near REF_X/REF_Y -
;      confirm it's acquired via an inner ring, then clicked repeatedly
;      with cooldown/re-click cadence visible in the log.
;   2. Move the marker slightly between polls (simulating camera pan) -
;      confirm small drift is tolerated (still tracked, not re-acquired).
;   3. Hide the marker briefly then bring it back within trackRadius -
;      confirm it's still tracked (anchor-hold or re-found), not treated
;      as a brand new acquire.
;   4. Put TWO markers of different TARGET_COLORS colors at different
;      distances from REF_X/REF_Y - confirm the CLOSER one is acquired
;      regardless of list order.
;   5. Fill UNTIL_SLOT (drop an item there) - confirm the loop reports
;      "until-condition met" and returns, stopping the click loop.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v7.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "21-track-and-click"

; ======= EDIT THESE FOR YOUR TEST =======================================
; Same equal-priority multi-color shape as micro 05.
TARGET_COLORS := [0x56FF50, 0x00B809]
COLOR_TOL := 5
BLOCK_W := 25
BLOCK_H := 25
VERIFY_PERCENT := 100

; Reference point + acquire rings - same globals micro 05 uses.
REF_X := CHAR_X
REF_Y := CHAR_Y
ACQUIRE_RADII := [ACQUIRE_PADDING_SMALL, ACQUIRE_PADDING_LARGE]

; Outer bound clamping every ring, the region-wide fallback, AND the
; track-mode re-search box.
gameZone := GameZoneRegion()

; BUG FOUND LIVE (2026-07-23): trackRadius must stay under half the
; real gap to the nearest SAME-colored duplicate, not just maxDriftPx -
; a too-large trackRadius pulls a same-colored neighbor INTO the
; track-mode search box, and track mode's single-color FindFilledBlock
; call returns whichever instance native scan order hits first (NOT
; necessarily the one closer to the last position) - maxDriftPx only
; rejects a bad match AFTER the fact, it can't fix the wrong one being
; found in the first place. Confirmed here: two real veins 46px apart
; (same TARGET_COLORS entry, by design - the user's real veins only
; get distinct colors when there's NO gap between them) were jumping
; between each other with trackRadius=96 (bigger than the 46px gap
; itself, guaranteeing both fell in one search box every tick).
; Fixed by keeping trackRadius well under half of 46px.
TRACK_RADIUS_PX := 16
MAX_DRIFT_PX    := 8   ; see Lib\Steps.ahk's tuning note before changing this

STABLE_TICKS_REQUIRED := 2
MOVE_TOLERANCE_PX     := 8
CLICK_COOLDOWN_MS     := 1500
RECLICK_AFTER_MS      := 3000
CLICK_USE_CTRL        := true

; BUG FOUND LIVE (2026-07-23): v7's async Ctrl release (ClickAt returns
; immediately instead of blocking for holdMs like v6 did) removed a
; ~100ms timing cushion before the next re-search - a vein that does
; NOT actually deplete was being reported "depleted" after every single
; click, because the next check fired too soon after a brief post-click
; visual flicker. POST_CLICK_SETTLE_MS restores that cushion explicitly.
; See Lib\Steps.ahk's tuning note above TrackAndClick for the full story.
POST_CLICK_SETTLE_MS := 100

; Cheap until-condition for testing - fill this slot to end the run
; without grinding a real full inventory.
UNTIL_SLOT := 28

PROGRESS_TIMEOUT_MS := 60000   ; shorter than a real bot's 5min - this is a micro test
OVERALL_TIMEOUT_MS  := 300000
POLL_MS := 100
; ========================================================================

F5:: RunTrackAndClick()
F6:: {
    global g_StopRequested
    g_StopRequested := true
    LogLine("F6 pressed - stop requested")
}
Esc:: {
    LogLine("Esc pressed - exiting")
    ExitApp()
}

RunTrackAndClick() {
    global g_StopRequested, gameZone
    g_StopRequested := false

    Say("micro21: starting TrackAndClick - until slot " UNTIL_SLOT " fills")

    UntilSlotFull() {
        return SlotFull(UNTIL_SLOT)
    }

    t0 := A_TickCount
    try {
        result := TrackAndClick({
            colors: TARGET_COLORS, tol: COLOR_TOL, blockW: BLOCK_W, blockH: BLOCK_H,
            verifyPercent: VERIFY_PERCENT,
            refX: REF_X, refY: REF_Y, acquireRadii: ACQUIRE_RADII, region: gameZone,
            trackRadius: TRACK_RADIUS_PX, maxDriftPx: MAX_DRIFT_PX,
            stableTicks: STABLE_TICKS_REQUIRED, moveTolerancePx: MOVE_TOLERANCE_PX,
            cooldownMs: CLICK_COOLDOWN_MS, reclickAfterMs: RECLICK_AFTER_MS,
            ctrl: CLICK_USE_CTRL, postClickSettleMs: POST_CLICK_SETTLE_MS,
            until: UntilSlotFull,
            timeoutMs: OVERALL_TIMEOUT_MS, progressTimeoutMs: PROGRESS_TIMEOUT_MS,
            pollMs: POLL_MS
        })
    } catch BotStopped {
        Say("micro21: STOPPED by F6 after " (A_TickCount - t0) " ms")
        return
    }
    elapsedMs := A_TickCount - t0

    msg := result
        ? "DONE - slot " UNTIL_SLOT " filled (" elapsedMs " ms)"
        : "STOPPED - timeout fired without until-condition met (" elapsedMs " ms)"
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

LogLine("Script loaded. F5=run TrackAndClick  F6=request stop  Esc=exit."
    . " Targets=" JoinMsg(TARGET_COLORS, "/", HexColor) " ref=" REF_X "," REF_Y " untilSlot=" UNTIL_SLOT)
ToolTip("micro 21 ready - F5 to run", 20, 20)
