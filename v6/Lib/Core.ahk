; ============================================================
; v6 Lib\Core.ahk - stop flag, interruptible wait, logging, focus check
;
; Promoted from micro 07 (Pause/WaitUntil/BotStopped, canonical -
; the only version with its own diagnostic LogLine calls at each
; stop-flag check), micro 12 (Say), and micro 13's confirmed winning
; WinActive criterion (GameActive). Byte-identical logic to the
; micros it came from - only LogLine's storage is now shared (keyed
; by g_LogName, set once per script) instead of each file hardcoding
; its own log path.
;
; BotRun/BotStop are NOT here - no micro tested a reusable "wrap the
; bot loop" harness, each micro/bot's F5/F6 hotkeys are still hand-
; wired. Design that alongside the first real bot (Motherlode), not
; speculatively here.
; ============================================================

g_StopRequested := false
g_LogName := "unnamed"

class BotStopped extends Error {
    __New() {
        super.__New("Bot stopped by user")
    }
}

; The ONLY sleep function in v6. Sleeps in small chunks, checking the
; stop flag between each - so a stop request lands within one chunk
; instead of after the full requested duration. 40ms chunking is an
; internal interrupt-latency constant, not a caller-tunable timing
; unit (see AutoHotkey.pdf-verified Pause/WaitUntil design in the
; plan file).
Pause(ms) {
    global g_StopRequested
    static CHUNK_MS := 40
    remaining := ms
    while (remaining > 0) {
        if (g_StopRequested) {
            LogLine("Pause: stop flag seen - throwing BotStopped")
            throw BotStopped()
        }
        step := Min(CHUNK_MS, remaining)
        Sleep(step)
        remaining -= step
    }
    if (g_StopRequested) {
        LogLine("Pause: stop flag seen at end of wait - throwing BotStopped")
        throw BotStopped()
    }
}

; Polls condFn via Pause until it returns true or timeoutMs elapses.
; Returns false on timeout; throws BotStopped if F6 fires mid-poll
; (propagates up through Pause - never swallowed here).
WaitUntil(condFn, timeoutMs, pollMs := 300) {
    startedAt := A_TickCount
    loop {
        if (condFn())
            return true
        if ((A_TickCount - startedAt) >= timeoutMs)
            return false
        Pause(pollMs)
    }
}

; Every per-tick status (acquire/track/click/hold/stop) goes through
; this, not LogLine directly - keeps the on-screen ToolTip showing
; exactly what the log just recorded, matching the live status
; readout a real Motherlode-style bot shows on screen.
Say(msg) {
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

; Shared logger. g_LogName is set once near the top of each micro/bot
; script (e.g. g_LogName := "12-track-and-click") so every script still
; gets its own v6\logs\<name>.log file without LogLine needing a name
; argument at every call site (dozens of call sites across Find/Act/
; Inv/Steps would otherwise all need updating).
LogLine(msg) {
    global g_LogName
    static logDir := A_ScriptDir "\..\logs"
    if (!DirExist(logDir))
        DirCreate(logDir)
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " [" g_LogName "] " msg "`n", logDir "\" g_LogName ".log")
}

; Confirmed live in micro 13 (v6\logs\13-focus-guard.log, 2026-07-19):
; the real foreground process is literally RuneLite.exe (class
; SunAwtFrame), not a javaw/launcher wrapper - "ahk_exe RuneLite.exe"
; correctly reported ACTIVE while focused and not-active when another
; window (File Explorer) was focused, confirmed across multiple
; focus/unfocus transitions. Chosen over the title-substring candidate
; (also correct in the log) since exe name doesn't depend on the
; RuneLite window title, which includes the logged-in account name.
GameActive() {
    return WinActive("ahk_exe RuneLite.exe") ? true : false
}
