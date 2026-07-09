; ============================================================
; WindowFocus.ahk
; Guard a Phase checks before clicking: is the game window
; actually focused right now - without it, a Phase would keep
; clicking even if RuneLite lost focus (alt-tab, a notification,
; a second monitor).
; ============================================================

#Requires AutoHotkey v2.0

class WindowFocus {
    __New(winTitle := "ahk_exe RuneLite.exe") {
        this._winTitle := winTitle
    }

    IsActive() => WinActive(this._winTitle) ? true : false
}
