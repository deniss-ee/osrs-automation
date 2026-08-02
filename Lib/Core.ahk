; ============================================================
; v8 Lib\Core.ahk - foundational primitives (stop flag, sleep,
; wait, opts unpacking, logging, path globals)
;
; Ported near-verbatim from v7\Lib\Core.ahk (proven, standards
; #1-#30). Only change: LOG_DIR/IMAGES_DIR are now load-time
; globals instead of a `static` computed on first LogLine call -
; v7's static bound the log directory to whichever script loaded
; the Lib first, which was harmless there (only one Bots\ script
; existed) but was never actually correct. Every v8 runnable sits
; one level below the repo root (micro\*.ahk, Bots\*.ahk), so
; A_ScriptDir "\..\logs" / "\..\Images" both resolve to the root's
; own logs\/Images\ (siblings of micro\/Bots\) from any of them -
; no ambiguity, no static needed.
;
; Say vs LogLine convention (made explicit here since v7 used them
; inconsistently - some composites logged failures via LogLine only,
; which never reached the on-screen ToolTip): Say() is for state
; changes and EVERY failure/retry/FAILED line - anything the person
; watching the screen needs to see live. LogLine() is for per-tick
; detail (poll ticks, individual pixel samples) that belongs in the
; log file but would flood the ToolTip if shown live.
; ============================================================

g_StopRequested := false
g_LogName := "unnamed"
POLL_MS_DEFAULT := 100

LOG_DIR := A_ScriptDir "\..\logs"
IMAGES_DIR := A_ScriptDir "\..\Images"

class BotStopped extends Error {
    __New() {
        super.__New("Bot stopped by user")
    }
}

; The one opts unpacker - every composite starts with a run of
; Opt(opts, "name", default) calls. Cannot distinguish "omitted"
; from "explicitly set to defaultValue" - callers that need that
; distinction (e.g. a real value that can legitimately be 0 or an
; array) use opts.HasOwnProp(name) directly instead (see Run.ahk's
; sessionLengthMs).
Opt(opts, name, defaultValue) {
    return opts.HasOwnProp(name) ? opts.%name% : defaultValue
}

; The one scalar-or-[min,max] resolver, rolled fresh at point of use
; (audit pass: previously duplicated inline six times across
; Act/Steps/Session).
RollMs(v) {
    return (v is Array) ? Random(v[1], v[2]) : v
}

; The only sleep in v8. Chunks in 40ms slices so a stop request
; lands within ~40ms instead of blocking through a long Sleep.
; Throws BotStopped, which is never caught anywhere in Lib - it
; propagates all the way to the harness's RunWrapped.
Pause(ms) {
    global g_StopRequested
    static CHUNK_MS := 40

    if (g_StopRequested)
        throw BotStopped()

    remaining := ms
    while (remaining > 0) {
        if (g_StopRequested)
            throw BotStopped()
        chunk := Min(CHUNK_MS, remaining)
        Sleep(chunk)
        remaining -= chunk
    }

    if (g_StopRequested)
        throw BotStopped()
}

; Poll condFn until it returns true or timeoutMs elapses. Returns
; false on timeout (not a throw - timing out is a normal, expected
; outcome for most callers, distinct from BotStopped).
;
; wanderOpts (default "" = off) opts into idle-wandering (Act.ahk's
; WanderNear, via the shared MaybeWander gate) while this specific
; wait is otherwise doing nothing: {chance, checkMs, durationMs,
; region} (region optional, defaults to the full screen) - the
; ONE wander-config shape used everywhere in the project (audit pass:
; previously TrackAndClick/DepositAllToBank each had their own flat
; opt names for this). Deliberately NOT wired into every WaitUntil
; call by default - most waits in this project are short mechanical
; settles or "about to act again very soon" windows (a reclick wait,
; a settle gap) where wandering would be wrong; only a caller that
; explicitly knows this is a genuine "nothing to do but wait" stretch
; passes wanderOpts.
WaitUntil(condFn, timeoutMs, pollMs := 0, wanderOpts := "") {
    if (pollMs = 0)
        pollMs := POLL_MS_DEFAULT

    lastWanderCheckAt := A_TickCount
    startedAt := A_TickCount
    loop {
        if (condFn())
            return true
        if (A_TickCount - startedAt >= timeoutMs)
            return false

        MaybeWander(wanderOpts, &lastWanderCheckAt)

        Pause(pollMs)
    }
}

Say(msg) {
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

LogLine(msg) {
    global g_LogName, LOG_DIR
    try {
        FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " [" g_LogName "] " msg "`n", LOG_DIR "\" g_LogName ".log")
    }
}

TrimLogOnStart(keepLines := 2500) {
    global g_LogName, LOG_DIR
    path := LOG_DIR "\" g_LogName ".log"
    if (!FileExist(path))
        return
    try {
        lines := StrSplit(FileRead(path), "`n")
        if (lines.Length > keepLines) {
            trimmed := ""
            for i, line in lines {
                if (i > lines.Length - keepLines)
                    trimmed .= line "`n"
            }
            FileDelete(path)
            FileAppend(trimmed, path)
        }
    }
}

GameActive() {
    return WinActive("ahk_exe RuneLite.exe") ? true : false
}

CenterX(cornerX, w) {
    return cornerX + w / 2
}

CenterY(cornerY, h) {
    return cornerY + h / 2
}

JoinMsg(arr, sep := "/", mapFn := "") {
    out := ""
    for i, v in arr {
        piece := mapFn ? mapFn(v) : v
        out .= (i > 1 ? sep : "") piece
    }
    return out
}
