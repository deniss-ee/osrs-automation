; ============================================================
; v6 micro 08 - travel-and-confirm pattern
; (click somewhere -> wait for a marker to appear -> click elsewhere)
;
; This is the pattern the user actually uses today: start running
; toward a destination, wait until a specific colored marker becomes
; visible in a specific region (confirming arrival/that something
; happened), THEN click a completely different point - not the marker
; itself. Distinct from micro 05 (which clicks the found target).
;
; WHAT IT DOES
;   F5  = click START point -> wait up to WAIT_TIMEOUT_MS for
;         MARKER_COLOR to appear in WAIT_REGION -> if it appears,
;         click AFTER point. If F6 is pressed during the wait, stops
;         immediately without clicking AFTER. If it times out, logs
;         and stops without clicking AFTER either.
;   F6  = request stop (interrupts the wait, same as micro 07)
;   Esc = exit the script
;
; ClickAt (Lib\Act.ahk), FindFilledBlock (Lib\Find.ahk), and
; Pause/WaitUntil/BotStopped (Lib\Core.ahk) - all promoted here after
; in-game confirmation during Stage 1.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v6.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "08-wait-marker-then-click"

; ======= EDIT THESE FOR YOUR TEST =======================================
START_X := 1000, START_Y := 720     ; e.g. a point that makes the character start moving
START_USE_CTRL := true              ; true = force-run (Ctrl-held) click

MARKER_COLOR := 0xFF00FF
COLOR_TOL    := 5
BLOCK_W      := 11
BLOCK_H      := 11

; Where the marker should appear once you've arrived/something happened.
WAIT_REGION_X1 := 716, WAIT_REGION_Y1 := 543, WAIT_REGION_X2 := 737, WAIT_REGION_Y2 := 564
WAIT_TIMEOUT_MS := 15000   ; give up after this long if the marker never appears
POLL_MS         := 300     ; tick-aligned poll interval

AFTER_X := 1153, AFTER_Y := 1037      ; the SEPARATE point to click once confirmed
                                     ; (NOT the marker's own found coordinates)
AFTER_USE_CTRL := true              ; true = force-run (Ctrl-held) click
; ========================================================================

F5:: RunFlow()
F6:: {
    global g_StopRequested
    g_StopRequested := true
    LogLine("F6 pressed - stop requested")
}
Esc:: {
    LogLine("Esc pressed - exiting")
    ExitApp()
}

RunFlow() {
    global g_StopRequested
    g_StopRequested := false

    LogLine("Flow started: click start=" START_X "," START_Y
        . " -> wait for marker in " WAIT_REGION_X1 "," WAIT_REGION_Y1 " -> " WAIT_REGION_X2 "," WAIT_REGION_Y2
        . " (timeout " WAIT_TIMEOUT_MS "ms) -> click after=" AFTER_X "," AFTER_Y)
    ToolTip("Clicking start point...", 20, 20)

    ClickAt(START_X, START_Y, START_USE_CTRL)
    LogLine("Clicked start point " START_X "," START_Y . (START_USE_CTRL ? " (ctrl/force-run)" : ""))

    ToolTip("Waiting for marker (F6 to cancel)...", 20, 20)
    t0 := A_TickCount

    try {
        markerAppeared := WaitUntil(MarkerVisible, WAIT_TIMEOUT_MS, POLL_MS)
    } catch BotStopped as e {
        elapsedMs := A_TickCount - t0
        msg := "STOPPED by F6 after " elapsedMs " ms waiting - AFTER click skipped"
        ToolTip(msg, 20, 20)
        LogLine(msg)
        return
    }

    elapsedMs := A_TickCount - t0

    if (!markerAppeared) {
        msg := "TIMED OUT after " elapsedMs " ms - marker never appeared - AFTER click skipped"
        ToolTip(msg, 20, 20)
        LogLine(msg)
        return
    }

    LogLine("Marker confirmed after " elapsedMs " ms - clicking AFTER point (separate from marker location)")
    ClickAt(AFTER_X, AFTER_Y, AFTER_USE_CTRL)

    msg := "DONE: marker confirmed (" elapsedMs " ms), clicked AFTER at " AFTER_X "," AFTER_Y
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

; Condition passed to WaitUntil - true the instant the marker is found
; anywhere in WAIT_REGION. Logs each check's outcome.
MarkerVisible() {
    t0 := A_TickCount
    found := FindFilledBlock(WAIT_REGION_X1, WAIT_REGION_Y1, WAIT_REGION_X2, WAIT_REGION_Y2,
        MARKER_COLOR, COLOR_TOL, BLOCK_W, BLOCK_H, &cx, &cy)
    searchMs := A_TickCount - t0
    if (found)
        LogLine("MarkerVisible: found at " cx "," cy " in " searchMs " ms")
    else
        LogLine("MarkerVisible: not yet visible (searched " searchMs " ms)")
    return found
}

LogLine("Script loaded. F5=run flow  F6=stop  Esc=exit")
ToolTip("micro 08 ready - F5 to run: click start -> wait for marker -> click after", 20, 20)
