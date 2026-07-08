; ============================================================
; Logger.ahk
; One instance per bot, constructed with that bot's log file
; path, passed into EngineContext like everything else - no
; direct FileAppend calls anywhere outside this class. Log line
; format matches legacy exactly ("PhaseName: message") so
; existing log-parsing habits keep working. Direct analog of
; lib/Log.ahk's LogLine.
; ============================================================

#Requires AutoHotkey v2.0

class Logger {
    __New(logFilePath) {
        this._logFilePath := logFilePath
    }

    Log(text) {
        line := FormatTime(, "yyyy-MM-dd HH:mm:ss") " " text "`n"
        try {
            FileAppend(line, this._logFilePath)
        } catch {
            ; One retry, matching lib/Log.ahk's existing tolerance for a
            ; transient file lock (e.g. another process reading the log).
            try FileAppend(line, this._logFilePath)
        }
    }
}
