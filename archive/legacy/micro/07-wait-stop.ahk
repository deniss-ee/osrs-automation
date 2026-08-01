; ============================================================
; v6 micro 07 - interruptible wait + stop hotkey (THE SAFETY KEYSTONE)
;
; v5's problem: several bots block inside one engine tick (e.g. a
; polling loop with plain Sleep calls), so the F6 stop hotkey can't
; interrupt mid-wait - the user has to wait out the whole timeout.
;
; This micro proves the fix: Pause() sleeps in small 40ms chunks and
; checks a global stop flag between each chunk. A hotkey runs as its
; own thread and can set that flag while Pause() is mid-sleep - by
; default AHK lets a new hotkey thread interrupt a running one (see
; AutoHotkey.pdf, Remarks on Threads/#MaxThreadsPerHotkey), so F6 takes
; effect within one chunk (~40ms), not after the full wait.
;
; WHAT IT DOES
;   F5  = start a 30 second wait (WaitUntil with a condition that never
;         becomes true - simulates "waiting for something that isn't
;         happening")
;   F6  = request stop (sets the flag Pause() checks)
;   Esc = exit the script immediately (hard escape, bypasses everything)
;
; Pause/WaitUntil/BotStopped live in Lib\Core.ahk - promoted here after
; in-game confirmation during Stage 1 (this micro's version, with its
; own diagnostic LogLine calls at each stop-flag check, was canonical).
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v6.ahk

CoordMode("ToolTip", "Screen")

g_LogName := "07-wait-stop"

; ======= EDIT THESE FOR YOUR TEST =======================================
WAIT_TIMEOUT_MS := 30000   ; the wait F5 starts (should NOT need to run this long)
POLL_MS         := 300     ; how often WaitUntil re-checks its condition (tick-aligned)
; ========================================================================

F5:: StartWait()
F6:: {
    global g_StopRequested
    g_StopRequested := true
    LogLine("F6 pressed - stop requested")
}
Esc:: {
    LogLine("Esc pressed - exiting")
    ExitApp()
}

; A condition that never becomes true - forces WaitUntil to run the
; full timeout UNLESS F6 interrupts it first.
NeverTrue() {
    return false
}

StartWait() {
    global g_StopRequested
    g_StopRequested := false
    LogLine("Wait started: timeout=" WAIT_TIMEOUT_MS "ms pollMs=" POLL_MS "ms - press F6 to stop early")
    ToolTip("Waiting up to " WAIT_TIMEOUT_MS / 1000 "s - press F6 to stop", 20, 20)

    t0 := A_TickCount
    try {
        result := WaitUntil(NeverTrue, WAIT_TIMEOUT_MS, POLL_MS)
        elapsedMs := A_TickCount - t0
        msg := result ? "Condition became true (" elapsedMs " ms)"
            : "TIMED OUT after " elapsedMs " ms (full " WAIT_TIMEOUT_MS "ms wait - F6 was NOT pressed in time)"
    } catch BotStopped as e {
        elapsedMs := A_TickCount - t0
        msg := "STOPPED by F6 after " elapsedMs " ms (requested stop landed quickly)"
    }

    ToolTip(msg, 20, 20)
    LogLine(msg)
}

LogLine("Script loaded. F5=start 30s wait  F6=request stop  Esc=exit")
ToolTip("micro 07 ready - F5 to start a long wait, F6 to stop it early", 20, 20)
