; ============================================================
; v7 Lib\Core.ahk - stop flag, interruptible wait, logging
;
; Built incrementally, one function per micro (see the v7 plan's
; build-order rule): Pause/WaitUntil/Say/LogLine/TrimLogOnStart/
; BotStopped for micro 01, GameActive for micro 02. CenterX/CenterY
; pulled forward to micro 06 - the corner+size calibration convention
; (never hand a function a precomputed center) means ANY micro whose
; EDIT block takes a corner+size marker needs these, not just Grid
; addressing. JoinMsg also pulled forward to micro 06 - the "every
; color config is an array" standard means every script now needs to
; log an array nicely, not just once a bot-level status line needs it.
; Do not add functions here ahead of the micro that will exercise them.
;
; Ported byte-identical in behavior from v6 Lib\Core.ahk (Pause,
; WaitUntil, Say, LogLine, TrimLogOnStart, BotStopped) - that file was
; itself promoted from v6 micro 07 after live confirmation. No
; contract changes for this micro.
; ============================================================

g_StopRequested := false
g_LogName := "unnamed"

class BotStopped extends Error {
    __New() {
        super.__New("Bot stopped by user")
    }
}

; The ONLY sleep function in v7. Sleeps in small chunks, checking the
; stop flag between each - so a stop request lands within one chunk
; instead of after the full requested duration. 40ms chunking is an
; internal interrupt-latency constant, not a caller-tunable timing
; unit.
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
; Returns false on timeout; throws BotStopped if a stop fires mid-poll
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

; Every per-tick status goes through this, not LogLine directly - keeps
; the on-screen ToolTip showing exactly what the log just recorded.
Say(msg) {
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

; Shared logger. g_LogName is set once near the top of each micro/bot
; script so every script gets its own v7\logs\<name>.log file without
; LogLine needing a name argument at every call site.
LogLine(msg) {
    global g_LogName
    static logDir := A_ScriptDir "\..\logs"
    if (!DirExist(logDir))
        DirCreate(logDir)
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " [" g_LogName "] " msg "`n", logDir "\" g_LogName ".log")
}

; Call once at script start (after g_LogName is set) to keep a bot's
; log file from growing unbounded across long/overnight AFK sessions.
TrimLogOnStart(keepLines := 2500) {
    global g_LogName
    logDir := A_ScriptDir "\..\logs"
    logPath := logDir "\" g_LogName ".log"
    if (!FileExist(logPath))
        return
    try {
        lines := StrSplit(FileRead(logPath), "`n")
        if (lines.Length <= keepLines)
            return
        trimmed := ""
        startAt := lines.Length - keepLines + 1
        loop keepLines {
            trimmed .= lines[startAt + A_Index - 1] "`n"
        }
        FileDelete(logPath)
        FileAppend(trimmed, logPath)
    }
}

; Confirmed live in v6 micro 13: the real foreground process is
; literally RuneLite.exe (class SunAwtFrame), not a javaw/launcher
; wrapper - "ahk_exe RuneLite.exe" correctly reported ACTIVE while
; focused and not-active when another window had focus, across
; multiple focus/unfocus transitions. Chosen over the title-substring
; candidate (also correct) since exe name doesn't depend on the
; RuneLite window title, which includes the logged-in account name.
GameActive() {
    return WinActive("ahk_exe RuneLite.exe") ? true : false
}

; Corner+size -> center, for the coordinate constant blocks at the top
; of every micro/bot file. Enforces the corner-measured calibration
; convention: a marker/area is always defined as X,Y (top-left corner)
; + W,H, never a precomputed center point typed out by hand - callers
; use CenterX(cornerX, w) / CenterY(cornerY, h) per axis instead.
CenterX(cornerX, w) => cornerX + w // 2
CenterY(cornerY, h) => cornerY + h // 2

; Joins an array into an "a/b/c" string for log/status lines. Optional
; mapFn transforms each element first (e.g. HexColor for a colors
; array). mapFn is an optional param (IsSet-guarded) so passing a Func
; object is safe - no object-vs-"" compare.
JoinMsg(arr, sep := "/", mapFn?) {
    msg := ""
    for i, v in arr {
        piece := IsSet(mapFn) ? mapFn(v) : v
        msg .= (i = 1 ? "" : sep) piece
    }
    return msg
}
