; ============================================================
; Safety.ahk - v3 REDESIGNED
;
; Guards that the old scripts never had: is the game window
; actually focused, and are these coordinates even sane.
;
; v3 changes: explicit ctx["paused"] state with sustained tooltip
; instead of a silent busy-poll. RequireOsrsWindowActive is now
; ctx-aware and maintains the paused flag.
;
; Depends on: Tooltip.ahk (ShowTip, HideTip)
; ============================================================

#Requires AutoHotkey v2.0

#Include Tooltip.ahk

; True if the window matching winTitle is the current foreground window.
; Default targets RuneLite - change it if you play on the official client
; (e.g. "Old School RuneScape") or have a custom window title.
IsOsrsWindowActive(winTitle := "ahk_exe RuneLite.exe") {
    return WinActive(winTitle) ? true : false
}

; NEW: Maintains an explicit, visible paused state. Updates ctx["paused"]
; to true if the window is not active, showing a sustained tooltip instead
; of a silent busy-poll. Returns true if the window is active (proceed),
; false if paused (caller should return immediately without clicking).
UpdatePausedState(ctx, winTitle := "ahk_exe RuneLite.exe") {
    active := IsOsrsWindowActive(winTitle)
    if (active && ctx["paused"]) {
        ctx["paused"] := false
        HideTip()
    } else if (!active && !ctx["paused"]) {
        ctx["paused"] := true
        ShowTip("OSRS window not focused - PAUSED")
    }
    return active
}

; Sugar wrapper: same call shape as v2's RequireOsrsWindowActive, but now
; also maintains ctx["paused"]. Call this as the first line of every phase.
RequireOsrsWindowActive(ctx, winTitle := "ahk_exe RuneLite.exe") {
    return UpdatePausedState(ctx, winTitle)
}

; True if (x,y) actually falls on the screen. Catches stale calibration
; left over from a different monitor/resolution.
IsCoordOnScreen(x, y) {
    return (x >= 0) && (x < A_ScreenWidth) && (y >= 0) && (y < A_ScreenHeight)
}

; True only if both corners of a search region are on-screen AND properly
; ordered (x1<x2, y1<y2). The old scripts only ever checked "is this
; non-zero", never that the rectangle actually makes sense - a swapped
; pair of corners would fail silently.
IsRegionValid(x1, y1, x2, y2) {
    if (!IsCoordOnScreen(x1, y1) || !IsCoordOnScreen(x2, y2))
        return false
    return (x1 < x2) && (y1 < y2)
}

; Wraps IsCoordOnScreen with a named popup so setup validation can tell
; the user exactly which calibration is bad.
RequireOnScreen(label, x, y) {
    if (IsCoordOnScreen(x, y))
        return true
    MsgBox(label " coordinate (" x ", " y ") is off-screen - recalibrate it.")
    return false
}
