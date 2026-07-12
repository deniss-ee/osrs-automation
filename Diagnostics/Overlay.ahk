; ============================================================
; Overlay.ahk
; Persistent multi-line on-screen status log (top-left by
; default) - a rolling history of the last N log lines, always
; visible, updated live via the native ToolTip() primitive.
; ============================================================

#Requires AutoHotkey v2.0

class Overlay {
    __New(maxLines := 8, x := 10, y := 10) {
        this._maxLines := maxLines
        this._x := x
        this._y := y
        this._lines := []
    }

    ; Appends a line (oldest dropped once over maxLines) and redraws.
    Log(text) {
        this._lines.Push(text)
        while (this._lines.Length > this._maxLines)
            this._lines.RemoveAt(1)

        joined := ""
        for i, line in this._lines
            joined .= (i > 1 ? "`n" : "") line
        ToolTip(joined, this._x, this._y)
    }

    ; Clears the history and hides the tooltip.
    Clear() {
        this._lines := []
        ToolTip()
    }
}
