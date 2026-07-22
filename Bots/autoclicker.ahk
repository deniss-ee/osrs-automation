; ============================================================
; v6 Auto-clicker - simple single-point clicker utility
;
; Not tied to any specific game activity - clicks one fixed on-screen
; point repeatedly on a delay. The target coordinate is set from
; wherever the mouse currently is, not hardcoded.
;
; WHAT IT DOES
;   F7  = set the click target to the current mouse position
;   F5  = start clicking the target every CLICK_DELAY_MS
;   F6  = stop clicking
;   F12 = exit the script
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v6.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "autoclicker"
TrimLogOnStart()

; ======= EDIT THESE FOR YOUR TEST =======================================
CLICK_DELAY_MS := 100   ; delay between clicks - tune to taste
CLICK_USE_CTRL := false
; ========================================================================

g_TargetX := 0
g_TargetY := 0
g_HasTarget := false

F7:: SetTarget()
F5:: RunClicker()
F6:: {
    global g_StopRequested
    g_StopRequested := true
    LogLine("F6 pressed - stop requested")
}
; F12 (exit) is defined once in Lib\v6.ahk, shared by every bot.

SetTarget() {
    global g_TargetX, g_TargetY, g_HasTarget
    MouseGetPos(&mx, &my)
    g_TargetX := mx, g_TargetY := my
    g_HasTarget := true
    Say("Target set to " g_TargetX "," g_TargetY)
}

RunClicker() {
    global g_StopRequested, g_HasTarget, g_TargetX, g_TargetY

    if (!g_HasTarget) {
        Say("No target set - press F7 over the spot you want to click first")
        return
    }

    g_StopRequested := false
    Say("Auto-clicker started: " g_TargetX "," g_TargetY " every " CLICK_DELAY_MS "ms")

    ; No per-click logging here on purpose - at a 300ms default delay
    ; that would flood the log fast (this project's own TrimLogOnStart
    ; exists specifically because unbounded log growth is a real
    ; problem). Start/stop are logged; individual clicks aren't.
    try {
        loop {
            ClickAt(g_TargetX, g_TargetY, CLICK_USE_CTRL)
            Pause(CLICK_DELAY_MS)
        }
    } catch BotStopped as e {
        Say("STOPPED by F6")
    }
}

LogLine("Script loaded. F7=set target  F5=start  F6=stop  F12=exit.")
ToolTip("autoclicker ready - F7 to set target, F5 to start", 20, 20)
