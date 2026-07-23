; ============================================================
; v7 micro 20 - patient-first-wait, then re-click (ClickUntilCondition)
;
; Straight port from v6 Lib\Steps.ahk (no contract change) - confirmed
; live there in motherlode2's hopper-deposit and sack-withdrawal steps.
; Real shape: click a SHARED/laggy target (e.g. a hopper another player
; might be using), wait patiently the first time, and only re-click if
; the condition still isn't met after that patient wait - never spam
; clicking when one click was enough.
;
; This micro's test scenario: click a marker block (same shape as
; micro 11's FindAndClickBlock), then wait for a specific EMPTY
; inventory slot to become FULL (same shape v6's sack-withdrawal wait
; used - "did an item arrive yet" - just easier to trigger by hand than
; a hopper drain: pick up/withdraw anything into WATCH_SLOT). If it
; doesn't fill within FIRST_WAIT_MS, re-click every RECLICK_MS until it
; does, or TOTAL_TIMEOUT_MS is hit.
;
; WHAT IT DOES
;   F5  = ClickUntilCondition: click the marker block, wait for
;         WATCH_SLOT to become FULL (patient first wait, then re-click loop)
;   F6  = request stop (sets g_StopRequested, standard across every
;         micro/bot - F5 always starts, F6 always stops)
;   Esc = exit the script
;
; LIVE CONFIRM: make sure WATCH_SLOT starts EMPTY, with a clickable
; marker at MARKER_X/Y. Press F5, then manually put an item into
; WATCH_SLOT (any item, any way - pick one up, withdraw one) WITHIN
; FIRST_WAIT_MS - confirm it reports success with neededRetry=false
; (one click was enough, no re-click happened). Then retest: press F5,
; wait PAST FIRST_WAIT_MS before filling the slot - confirm the log
; shows a re-click firing, and the run still succeeds once the slot
; fills (neededRetry=true this time). Also test the marker not being
; present at all (click() should fail cleanly) and a slot that never
; fills (TOTAL_TIMEOUT_MS should fire).
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v7.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "20-click-until-condition"

; ======= EDIT THESE FOR YOUR TEST =======================================
; Same block color/size/marker shape as micro 11 - the thing to click.
TARGET_COLORS := [0xCFA10F]
COLOR_TOL := 5
BLOCK_W := 5
BLOCK_H := 5
MARKER_X := 854
MARKER_Y := 445
MARGIN_PX := 4
CLICK_WAIT_TIMEOUT_MS := 5000   ; how long FindAndClickBlock itself waits for the marker

; The slot the condition watches - keep this EMPTY before testing.
WATCH_SLOT := 5

FIRST_WAIT_MS   := 4000    ; patient wait after the first click
RECLICK_MS      := 2000    ; wait between re-clicks after that
TOTAL_TIMEOUT_MS := 30000  ; give up entirely after this much total time
POLL_MS         := 300
; ========================================================================

searchRegion := RegionAround(MARKER_X, MARKER_Y, BLOCK_W, BLOCK_H, MARGIN_PX)

F5:: RunClickUntilCondition()
F6:: {
    global g_StopRequested
    g_StopRequested := true
    LogLine("F6 pressed - stop requested")
}
Esc:: {
    LogLine("Esc pressed - exiting")
    ExitApp()
}

RunClickUntilCondition() {
    global g_StopRequested, searchRegion
    g_StopRequested := false

    Say("micro20: starting - click marker, wait for slot " WATCH_SLOT " to fill")

    ClickMarker() {
        return FindAndClickBlock({
            colors: TARGET_COLORS, tol: COLOR_TOL, blockW: BLOCK_W, blockH: BLOCK_H,
            region: searchRegion, waitTimeoutMs: CLICK_WAIT_TIMEOUT_MS,
            label: "micro20", itemLabel: "marker block"
        })
    }

    SlotFilled() {
        return SlotFull(WATCH_SLOT)
    }

    t0 := A_TickCount
    try {
        result := ClickUntilCondition({
            click: ClickMarker,
            condition: SlotFilled,
            firstWaitMs: FIRST_WAIT_MS,
            reclickMs: RECLICK_MS,
            totalTimeoutMs: TOTAL_TIMEOUT_MS,
            pollMs: POLL_MS,
            label: "micro20",
            itemLabel: "slot " WATCH_SLOT " to fill"
        }, &neededRetry)
    } catch BotStopped {
        Say("micro20: STOPPED by F6 after " (A_TickCount - t0) " ms")
        return
    }
    elapsedMs := A_TickCount - t0

    msg := result
        ? "DONE - slot " WATCH_SLOT " filled (" elapsedMs " ms, neededRetry=" neededRetry ")"
        : "FAILED - marker missing or timed out (" elapsedMs " ms)"
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

LogLine("Script loaded. F5=click-until-condition  F6=request stop  Esc=exit."
    . " Marker=" MARKER_X "," MARKER_Y " watchSlot=" WATCH_SLOT)
ToolTip("micro 20 ready - F5 to run", 20, 20)
