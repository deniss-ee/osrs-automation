; ============================================================
; Log.ahk
; Minimal append-only debug logging - writes a timestamped line
; to a text file. Useful when a tooltip might not actually be
; visible (e.g. the game is running in a fullscreen mode that
; draws over it) or when you need a record of what happened
; across a whole run, not just a 1-2 second flash of text.
; No dependencies on any other lib file.
; ============================================================

#Requires AutoHotkey v2.0

LogLine(logFile, text) {
    FileAppend(FormatTime(A_Now, "HH:mm:ss") " " text "`n", logFile)
}
