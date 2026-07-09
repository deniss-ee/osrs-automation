; ============================================================
; WindowFocus.ahk
; Guards that a Phase should check before clicking: is the game
; window actually focused right now. Direct port of legacy's
; lib/Safety.ahk (IsOsrsWindowActive/RequireOsrsWindowActive) -
; v4 previously had NO equivalent anywhere, meaning MinePhase
; would happily keep computing FindFilledBlock results and
; issuing MouseMove/Click calls even if RuneLite lost focus
; entirely (alt-tab, a notification stealing focus, clicking a
; second monitor) - a real gap every legacy phase guarded
; against but v4 didn't.
; ============================================================

#Requires AutoHotkey v2.0

class WindowFocus {
    __New(winTitle := "ahk_exe RuneLite.exe") {
        this._winTitle := winTitle
    }

    IsActive() => WinActive(this._winTitle) ? true : false
}
