; ============================================================
; Overlay.ahk
; Persistent multi-line on-screen status log, shown top-left by
; default. Legacy's lib/Tooltip.ahk shows a single line, top-right,
; that auto-hides after a fixed duration (ShowTipFor) - this is a
; different shape entirely: a small rolling history of the last
; N log lines, always visible, updated live as the bot runs, so
; you can see the sequence of recent steps at a glance rather
; than only the current one. Reuses the same native ToolTip()
; primitive legacy uses, just multi-line and never auto-hidden.
; ============================================================

#Requires AutoHotkey v2.0

class Overlay {
    __New(maxLines := 8, x := 10, y := 10) {
        this._maxLines := maxLines
        this._x := x
        this._y := y
        this._lines := []
    }

    ; Appends a new line to the rolling history (oldest dropped once over
    ; maxLines) and redraws the tooltip with the full visible history.
    Log(text) {
        this._lines.Push(text)
        while (this._lines.Length > this._maxLines)
            this._lines.RemoveAt(1)

        joined := ""
        for i, line in this._lines
            joined .= (i > 1 ? "`n" : "") line
        ToolTip(joined, this._x, this._y)
    }

    ; Clears the history and hides the tooltip - matches legacy's HideTip
    ; contract (bare ToolTip() with no text hides it).
    Clear() {
        this._lines := []
        ToolTip()
    }
}
