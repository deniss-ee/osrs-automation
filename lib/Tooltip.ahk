; ============================================================
;  Tooltip.ahk
;  On-screen feedback helpers used by every script for status
;  messages ("Ore #1 saved", "Recording started", etc).
;  No dependencies on any other lib file.
; ============================================================

; Shows a tooltip at a fixed screen position (defaults to the
; top-right corner, out of the way of the game viewport).
; Call HideTip() yourself, or use ShowTipFor() to auto-hide.
ShowTip(text, x := "", y := "") {
    if (x == "")
        x := A_ScreenWidth - 420
    if (y == "")
        y := 40
    ToolTip(text, x, y)
}

; Clears whatever tooltip is currently showing.
HideTip() {
    ToolTip()
}

; Shows a tooltip and automatically hides it after durationMs.
; This is the version most call sites should use, since almost
; every status message is meant to disappear on its own.
ShowTipFor(text, durationMs, x := "", y := "") {
    ShowTip(text, x, y)
    SetTimer(HideTip, -durationMs)
}
