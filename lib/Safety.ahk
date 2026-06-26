; ============================================================
;  Safety.ahk
;  Guards that the old scripts never had: is the game window
;  actually focused, and are these coordinates even sane.
;
;  Depends on: Tooltip.ahk (ShowTipFor)
; ============================================================

#Include Tooltip.ahk

; True if the window matching winTitle is the current foreground
; window. Default targets RuneLite - change it if you play on
; the official client (e.g. "Old School RuneScape") or have a
; custom window title.
IsOsrsWindowActive(winTitle := "ahk_exe RuneLite.exe") {
    return WinActive(winTitle) ? true : false
}

; Same check as IsOsrsWindowActive, but shows a tooltip and
; returns false instead of silently letting the caller continue.
; Call this as the very first line of every main-loop phase so a
; tabbed-out client pauses the bot instead of clicking blind.
RequireOsrsWindowActive(winTitle := "ahk_exe RuneLite.exe") {
    if (IsOsrsWindowActive(winTitle))
        return true
    ShowTipFor("OSRS window not focused - paused", 1000)
    return false
}

; True if (x,y) actually falls on the screen. Catches stale
; calibration left over from a different monitor/resolution.
IsCoordOnScreen(x, y) {
    return (x >= 0) && (x < A_ScreenWidth) && (y >= 0) && (y < A_ScreenHeight)
}

; True only if both corners of a search region are on-screen
; AND properly ordered (x1<x2, y1<y2). The old scripts only ever
; checked "is this non-zero", never that the rectangle actually
; makes sense - a swapped pair of corners would fail silently.
IsRegionValid(x1, y1, x2, y2) {
    if (!IsCoordOnScreen(x1, y1) || !IsCoordOnScreen(x2, y2))
        return false
    return (x1 < x2) && (y1 < y2)
}

; Wraps IsCoordOnScreen with a named popup so setup validation
; can tell the user exactly which calibration is bad.
RequireOnScreen(label, x, y) {
    if (IsCoordOnScreen(x, y))
        return true
    MsgBox(label " coordinate (" x ", " y ") is off-screen - recalibrate it.")
    return false
}
