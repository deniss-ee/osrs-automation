; ============================================================
; v7 micro 15 - state-indicator watcher (WatchIndicator)
;
; New gap primitive, no v6 precedent (v6 never had a dedicated
; presence/absence watcher - see the v7 plan's "state-indicator
; watcher IN" decision). Real use case: watching a health bar. Two
; directions share one primitive:
;   - watch for the bar's color(s) to go ABSENT (target died)
;   - watch for the bar's color(s) to become PRESENT (target acquired)
; Both are just WatchIndicator(..., targetState) with the presence
; check inverted internally - see Lib\Find.ahk.
;
; WHAT IT DOES
;   F5  = watch for PRESENT: waits until any of TARGET_COLORS shows at
;         the marker point, or WAIT_TIMEOUT_MS elapses
;   F7  = watch for ABSENT: waits until NONE of TARGET_COLORS shows at
;         the marker point (e.g. healthbar gone = target died)
;   F6  = request stop (sets g_StopRequested, standard across every
;         micro/bot - F5 always starts, F6 always stops)
;   Esc = exit the script
;
; Both hotkeys report whether the target state was ALREADY true at the
; very first sample (before any waiting happened) vs. observed as a
; genuine transition during the wait - this is the guard described in
; Lib\Find.ahk's WatchIndicator header.
;
; LIVE CONFIRM: point MARKER_X/MARKER_Y (a corner-measured 1x1 marker,
; center derived same as every other micro) at a spot on an enemy's
; health bar. With the bar visible, press F5 - should report "already
; PRESENT at start" immediately. Then press F7 and kill (or let die)
; the target before WAIT_TIMEOUT_MS - should report a genuine
; transition to absent, NOT "already true". Press F7 again with no bar
; showing - should report "already ABSENT at start" immediately. F6
; mid-wait should interrupt with BotStopped.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v7.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "15-state-indicator"

; ======= EDIT THESE FOR YOUR TEST =======================================
; Corner-measured marker position (top-left corner of a 1x1 sample
; point) - the ONE position input, same convention as every other
; micro. Point this at a pixel on the health bar you want to watch.
TARGET_COLORS := [0xCC5D02]   ; array of healthbar colors - add/remove freely
COLOR_TOL := 10
MARKER_X := 1249
MARKER_Y := 735

WAIT_TIMEOUT_MS := 15000
POLL_MS         := 300
; ========================================================================

; Derived center - a 1x1 marker's "center" is just its corner, same
; CenterX/CenterY call every micro uses (w=1,h=1 collapses to the
; corner itself).
CENTER_X := CenterX(MARKER_X, 1)
CENTER_Y := CenterY(MARKER_Y, 1)

F5:: RunWatchPresent()
F7:: RunWatchAbsent()
F6:: {
    global g_StopRequested
    g_StopRequested := true
    LogLine("F6 pressed - stop requested")
}
Esc:: {
    LogLine("Esc pressed - exiting")
    ExitApp()
}

RunWatchPresent() {
    global g_StopRequested
    g_StopRequested := false

    LogLine("F5: watching for PRESENT at " CENTER_X "," CENTER_Y " targets=" JoinMsg(TARGET_COLORS, "/", HexColor))
    ToolTip("Watching for PRESENT (F6 to cancel)...", 20, 20)

    t0 := A_TickCount
    try {
        result := WatchIndicator(CENTER_X, CENTER_Y, TARGET_COLORS, COLOR_TOL, "present", WAIT_TIMEOUT_MS, POLL_MS, &alreadyTrue)
    } catch BotStopped {
        msg := "STOPPED by F6 after " (A_TickCount - t0) " ms waiting for PRESENT"
        ToolTip(msg, 20, 20)
        LogLine(msg)
        return
    }
    elapsedMs := A_TickCount - t0

    if (!result) {
        msg := "TIMED OUT after " elapsedMs " ms - never became PRESENT"
    } else if (alreadyTrue) {
        msg := "ALREADY PRESENT at start (" elapsedMs " ms)"
    } else {
        msg := "BECAME PRESENT after " elapsedMs " ms (genuine transition)"
    }
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

RunWatchAbsent() {
    global g_StopRequested
    g_StopRequested := false

    LogLine("F7: watching for ABSENT at " CENTER_X "," CENTER_Y " targets=" JoinMsg(TARGET_COLORS, "/", HexColor))
    ToolTip("Watching for ABSENT (F6 to cancel)...", 20, 20)

    t0 := A_TickCount
    try {
        result := WatchIndicator(CENTER_X, CENTER_Y, TARGET_COLORS, COLOR_TOL, "absent", WAIT_TIMEOUT_MS, POLL_MS, &alreadyTrue)
    } catch BotStopped {
        msg := "STOPPED by F6 after " (A_TickCount - t0) " ms waiting for ABSENT"
        ToolTip(msg, 20, 20)
        LogLine(msg)
        return
    }
    elapsedMs := A_TickCount - t0

    if (!result) {
        msg := "TIMED OUT after " elapsedMs " ms - never became ABSENT"
    } else if (alreadyTrue) {
        msg := "ALREADY ABSENT at start (" elapsedMs " ms)"
    } else {
        msg := "BECAME ABSENT after " elapsedMs " ms (genuine transition - e.g. target died)"
    }
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

LogLine("Script loaded. F5=watch PRESENT  F7=watch ABSENT  F6=request stop  Esc=exit."
    . " Marker=" CENTER_X "," CENTER_Y " targets=" JoinMsg(TARGET_COLORS, "/", HexColor) " tol=" COLOR_TOL)
ToolTip("micro 15 ready - F5=watch present  F7=watch absent", 20, 20)
