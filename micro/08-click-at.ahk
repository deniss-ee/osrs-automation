; ============================================================
; v7 micro 08 - settled click with configurable settle/hold/pre/post delays
;
; Port of v6 micro 04's core mechanics (move, settle, click, optional
; Ctrl-hold), but this is the first NEW-CONTRACT micro (per the v7
; plan): SETTLE_MS/HOLD_MS are no longer hidden statics, and there are
; two brand-new named delays (preDelayMs/postDelayMs) bracketing the
; whole action - the universal pattern every action function in v7
; gets. This micro has to prove BOTH that the click mechanics still
; work AND that the new delay params actually do something observable
; (bracket the action, stay F6-interruptible).
;
; HOLD_MS IS NOW ASYNC (2026-07-22 live finding): holding Ctrl/Shift
; doesn't cost real time (you don't have to "wait" while your finger
; holds a key down), so ClickAt returns immediately after the click -
; the modifier gets released by a background timer after HOLD_MS, not
; a blocking Sleep. Log a SEPARATE "released" line when that timer
; fires so you can see it happen AFTER the reported click duration,
; not folded into it.
;
; WHAT IT DOES
;   F5  = plain click at TARGET_X,TARGET_Y using SETTLE_MS/HOLD_MS/
;         PRE_DELAY_MS/POST_DELAY_MS from the edit block
;   F7  = Ctrl-held click (force-run) at the same point, same delays
;   F6  = request stop (interrupts a delay mid-wait, same as micro 01)
;   Esc = exit the script
;
; LIVE CONFIRM:
;   1. With PRE_DELAY_MS=0/POST_DELAY_MS=0, confirm F5/F7 behave like
;      v6 micro 04 (click lands, force-run works) - but F7's reported
;      duration should now be close to F5's (no +HOLD_MS), with a
;      separate "Ctrl released" log line appearing ~HOLD_MS later.
;   2. Set PRE_DELAY_MS to something visible (e.g. 2000) - confirm the
;      click visibly waits before firing, and that pressing F6 during
;      that wait aborts the click (BotStopped, no click happens) -
;      proving preDelayMs routes through Pause, not a raw Sleep.
;   3. Same test for POST_DELAY_MS - confirm the click fires
;      immediately, THEN waits, and F6 during that wait is also
;      interruptible.
;   4. Fire F7 twice in a row FAST (before HOLD_MS elapses from the
;      first) - confirm the log shows the first click's Ctrl being
;      force-released early (the guard), not bleeding into the second
;      click.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v7.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "08-click-at"

; ======= EDIT THESE FOR YOUR TEST =======================================
TARGET_X := 1630   ; a point you can visually verify - inventory slot,
TARGET_Y := 884    ; ground tile, etc.

SETTLE_MS := 100      ; v6 default - mechanical gap after mouse move, before click
HOLD_MS := 100        ; v6 default - mechanical gap holding Ctrl/Shift after click
PRE_DELAY_MS := 0     ; NEW - interruptible wait BEFORE the whole action (0 = no-op)
POST_DELAY_MS := 0    ; NEW - interruptible wait AFTER the whole action (0 = no-op)
; ========================================================================

F5:: RunClick(false)
F7:: RunClick(true)
F6:: {
    global g_StopRequested
    g_StopRequested := true
    LogLine("F6 pressed - stop requested")
}
Esc:: {
    LogLine("Esc pressed - exiting")
    ExitApp()
}

RunClick(useCtrl) {
    global g_StopRequested
    g_StopRequested := false

    LogLine((useCtrl ? "Ctrl-click" : "Click") " started: target=" TARGET_X "," TARGET_Y
        . " settle=" SETTLE_MS " hold=" HOLD_MS " pre=" PRE_DELAY_MS " post=" POST_DELAY_MS)
    t0 := A_TickCount

    try {
        ClickAt(TARGET_X, TARGET_Y, useCtrl, false, SETTLE_MS, HOLD_MS, PRE_DELAY_MS, POST_DELAY_MS)
    } catch BotStopped as e {
        elapsedMs := A_TickCount - t0
        msg := "STOPPED by F6 after " elapsedMs " ms (click may not have fired - check if pre-delay was interrupted)"
        ToolTip(msg, 20, 20)
        LogLine(msg)
        return
    }

    elapsedMs := A_TickCount - t0
    msg := (useCtrl ? "Ctrl-clicked (force-run)" : "Clicked") " at " TARGET_X "," TARGET_Y " (" elapsedMs " ms, incl. pre/settle/post - hold releases async, not counted here)"
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

LogLine("Script loaded. F5=click  F7=ctrl-click  F6=request stop  Esc=exit. Target=" TARGET_X "," TARGET_Y)
ToolTip("micro 08 ready - F5 click / F7 ctrl-click", 20, 20)
