; ============================================================
; v7 micro 23 - click a travel marker, confirm arrival (TravelToPoint)
;
; Port from v6 Lib\Steps.ahk (GoToSackArea/ReturnToMine's shared shape,
; confirmed live there), with three v7 contract changes:
; markerClickOffsetX/Y are GONE (v7's hard rule against click-offset
; compensation); markerColors/arriveColors are now arrays (the v7
; standard) instead of single scalar colors; and a markerClickX/
; markerClickY PIN mode was added (2026-07-23) for a travel marker
; that's a genuinely fixed, always-clickable point - not worth a color
; search at all. This micro uses PIN mode for the marker step.
;
; Real shape: click a travel marker (here: a fixed pinned point, e.g. a
; mine entrance/exit), then wait for a DIFFERENT block to appear at an
; EXACT expected point (confirming arrival at the destination) - not
; just "some block appeared somewhere." On a miss, does a whole-screen
; diagnostic search for the arrival marker to distinguish "found
; elsewhere" (position wrong) from "not found anywhere" (never arrived
; at all).
;
; WHAT IT DOES
;   F5  = TravelToPoint: click the pinned marker point (MARKER_CLICK_X/Y),
;         wait for the arrival marker (ARRIVE_*) to appear at its exact
;         expected point, with a whole-screen diagnostic fallback on miss
;   F6  = request stop (sets g_StopRequested, standard across every
;         micro/bot - F5 always starts, F6 always stops)
;   Esc = exit the script
;
; LIVE CONFIRM: set MARKER_CLICK_X/Y to a real fixed clickable travel
; point and ARRIVE_CORNER_X/Y to where the arrival marker should appear
; once you've arrived. Press F5 - confirm the pinned point gets
; clicked, then confirm arrival is detected once the arrival marker
; shows up at the expected point. Also test: arrival marker shows up
; but NOT at the expected point (should report "found elsewhere") and
; arrival marker never shows up anywhere (should report "not found
; anywhere").
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v7.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "23-travel-to-point"

; ======= EDIT THESE FOR YOUR TEST =======================================
; The travel marker - a fixed, always-clickable point (PIN mode, no
; color search). Same corner/point convention as every other micro.
MARKER_CLICK_X := 1335
MARKER_CLICK_Y := 842
CLICK_USE_CTRL := true   ; force-run to the marker

; The arrival block - a DIFFERENT marker expected at a known corner
; once travel completes. Same corner-measured convention as micro 06.
ARRIVE_COLORS := [0x0B5C11]
ARRIVE_TOL := 5
ARRIVE_BLOCK_W := 33
ARRIVE_BLOCK_H := 33
ARRIVE_CORNER_X := 1746
ARRIVE_CORNER_Y := 823
ARRIVE_POS_TOL_PX := 15
ARRIVE_WAIT_TIMEOUT_MS := 20000

POLL_MS := 100
; ========================================================================

F5:: RunTravel()
F6:: {
    global g_StopRequested
    g_StopRequested := true
    LogLine("F6 pressed - stop requested")
}
Esc:: {
    LogLine("Esc pressed - exiting")
    ExitApp()
}

RunTravel() {
    global g_StopRequested
    g_StopRequested := false

    Say("micro23: starting travel")

    t0 := A_TickCount
    try {
        result := TravelToPoint({
            markerClickX: MARKER_CLICK_X, markerClickY: MARKER_CLICK_Y,
            ctrl: CLICK_USE_CTRL,
            arriveColors: ARRIVE_COLORS, arriveTol: ARRIVE_TOL,
            arriveBlockW: ARRIVE_BLOCK_W, arriveBlockH: ARRIVE_BLOCK_H,
            arriveCornerX: ARRIVE_CORNER_X, arriveCornerY: ARRIVE_CORNER_Y,
            arrivePosTolPx: ARRIVE_POS_TOL_PX,
            arriveWaitTimeoutMs: ARRIVE_WAIT_TIMEOUT_MS,
            pollMs: POLL_MS,
            label: "micro23"
        })
    } catch BotStopped {
        Say("micro23: STOPPED by F6 after " (A_TickCount - t0) " ms")
        return
    }
    elapsedMs := A_TickCount - t0

    msg := result
        ? "ARRIVED (" elapsedMs " ms)"
        : "FAILED - marker missing or never arrived (" elapsedMs " ms, see log for detail)"
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

LogLine("Script loaded. F5=travel  F6=request stop  Esc=exit."
    . " Marker(pin)=" MARKER_CLICK_X "," MARKER_CLICK_Y " Arrive=" JoinMsg(ARRIVE_COLORS, "/", HexColor)
    . " at " ARRIVE_CORNER_X "," ARRIVE_CORNER_Y)
ToolTip("micro 23 ready - F5 to travel", 20, 20)
