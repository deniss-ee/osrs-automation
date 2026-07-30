; ============================================================
; v7 Lib\Core.ahk - stop flag, interruptible wait, logging, shared defaults
; ============================================================

g_StopRequested := false
g_LogName := "unnamed"

; Project-wide poll default. Scripts still display POLL_MS := 100 in
; their own config block (standard #24) - this is the Lib-side fallback.
POLL_MS_DEFAULT := 100

class BotStopped extends Error {
    __New() {
        super.__New("Bot stopped by user")
    }
}

; Reads opts.name with a fallback - the ONE way every composite unpacks
; its optional opts fields.
Opt(opts, name, defaultValue) {
    return opts.HasOwnProp(name) ? opts.%name% : defaultValue
}

; The ONLY sleep in v7. 40ms chunks so a stop request (F6) lands within
; one chunk; throws BotStopped when g_StopRequested is set.
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

; Polls condFn via Pause until true or timeoutMs. False on timeout;
; BotStopped propagates from Pause, never swallowed.
WaitUntil(condFn, timeoutMs, pollMs?) {
    if (!IsSet(pollMs))
        pollMs := POLL_MS_DEFAULT
    startedAt := A_TickCount
    loop {
        if (condFn())
            return true
        if ((A_TickCount - startedAt) >= timeoutMs)
            return false
        Pause(pollMs)
    }
}

; Status line: on-screen ToolTip + log, always together.
Say(msg) {
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

; Shared logger; g_LogName (set once per script) picks the file.
LogLine(msg) {
    global g_LogName
    static logDir := A_ScriptDir "\..\logs"
    if (!DirExist(logDir))
        DirCreate(logDir)
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " [" g_LogName "] " msg "`n", logDir "\" g_LogName ".log")
}

; Call once at script start (after g_LogName is set) to cap log growth.
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

; True while RuneLite is the foreground window (confirmed live: the real
; process is RuneLite.exe, not a javaw/launcher wrapper).
GameActive() {
    return WinActive("ahk_exe RuneLite.exe") ? true : false
}

; Corner+size -> center. Calibration is always a top-left corner + W/H
; (standard #2) - centers are derived here, never hand-typed.
CenterX(cornerX, w) => cornerX + w // 2
CenterY(cornerY, h) => cornerY + h // 2

; Joins an array into "a/b/c" for log lines; optional mapFn transforms
; each element (e.g. HexColor for a colors array).
JoinMsg(arr, sep := "/", mapFn?) {
    msg := ""
    for i, v in arr {
        piece := IsSet(mapFn) ? mapFn(v) : v
        msg .= (i = 1 ? "" : sep) piece
    }
    return msg
}
