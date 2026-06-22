; ============================================================
;  movement.ahk - MOVING THE MOUSE AND CLICKING
; ------------------------------------------------------------
;  ELI5: Every click the bot makes (clicking ore, walking,
;  banking) goes through this one function. Centralizing it here
;  means if you ever want to tweak HOW a click happens (speed,
;  hold a modifier key, etc.) you only have to change it in one
;  place instead of hunting through the whole script.
; ============================================================

#Requires AutoHotkey v2.0

; --------------------------------------------------------------
; DoClick: moves the mouse to (x, y), waits a moment so the game
; "sees" the cursor arrive before clicking (like a human would),
; then clicks. `holdCtrl` is used for the recorded back-to-mine
; path when run mode is enabled, since holding Ctrl while
; clicking is this game's "force run to this tile" shortcut.
; --------------------------------------------------------------
DoClick(x, y, holdCtrl := false) {
    if (holdCtrl) {
        Send("{Ctrl down}")
        Sleep(50)
    }

    MouseMove(x, y, 5)
    Sleep(150)

    if (holdCtrl) {
        Click(x, y)
        Sleep(50)
        Send("{Ctrl up}")
        return
    }

    Click(x, y)
}
