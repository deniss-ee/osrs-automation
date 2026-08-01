; ============================================================
; v8 micro 01 - harness + stop-flag validation (Core.ahk, Bot.ahk)
;
; Combines v7 micros 01 (Pause/WaitUntil stop-interrupt), 02
; (focus-guard/GameActive), and 26 (InstallBotHarness wiring) into
; one micro, since all three are "does the harness/stop plumbing
; work" - the foundation everything else builds on.
;
; The one genuinely NEW thing under test here vs v7: F7 is an
; extraHotkeys entry that runs a REAL interruptible loop (30s
; Pause-based wait). In v7, extraHotkeys handlers did not get
; g_StopRequested reset or BotStopped caught (only opts.run did) -
; so pressing F6 once, then F7, would abort F7 instantly (stale
; flag), and F6 during a live F7 run would crash with an uncaught
; exception. v8's WrapHandler (Bot.ahk) wraps every handler
; uniformly, so F7 must behave exactly like F5: run cleanly, stop
; cleanly on F6, report DONE/STOPPED.
;
; WHAT IT DOES
;   F5  = run a 30s Pause-based wait (never completes on its own
;         inside 30s unless you let it) then reports DONE
;   F6  = request stop (must land within ~40ms, any time, any run)
;   F7  = extraHotkeys entry - the SAME 30s wait, run via the
;         non-F5 path, to prove WrapHandler treats it identically
;   F8  = probe - logs GameActive() (RuneLite focused?) and returns
;         false once (to see a FAILED report), true after
;   F12 = exit
;
; LIVE CONFIRM:
;   1. F5 - starts, "ready" tooltip updates; F6 within a couple
;      seconds - stops within ~40ms, Says "STOPPED by F6".
;   2. Press F5, let it run past 30s uninterrupted - Says "DONE".
;   3. Press F6 once with NOTHING running (stale flag from test 1),
;      then immediately F7 - the run must NOT abort instantly. This
;      is the stale-flag regression check.
;   4. Start F7, press F6 mid-run - stops within ~40ms, same as F5.
;   5. F8 twice - first call Says "FAILED - still loaded, F5 to
;      restart" (probe deliberately returns false once), second
;      call Says "DONE" (GameActive() logged both times regardless).
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v8.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "01-harness-stop"

WAIT_MS := 30000

g_ProbeCallCount := 0

RunWait() {
    Say("micro01: waiting " WAIT_MS "ms (or until F6)")
    Pause(WAIT_MS)
    Say("micro01: wait completed uninterrupted")
    return true
}

ProbeFocus() {
    global g_ProbeCallCount
    g_ProbeCallCount += 1
    Say("micro01: GameActive()=" GameActive() " (call " g_ProbeCallCount ")")
    return (g_ProbeCallCount = 1) ? false : true
}

InstallBotHarness({
    run: RunWait,
    label: "micro01",
    probe: ProbeFocus,
    extraHotkeys: [
        {key: "F7", handler: RunWait, label: "micro01-F7"}
    ]
})
