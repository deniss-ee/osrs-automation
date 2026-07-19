; ============================================================
; v6 micro 04 - single settled click
;
; Proves the click primitive every other block uses: move mouse to a
; fixed point, settle briefly (let the client register hover state),
; then click. Includes a Ctrl-held variant (OSRS "force run").
;
; No search involved - hardcode a point you can verify by eye (e.g. an
; inventory slot center, or a ground tile).
;
; WHAT IT DOES
;   F5  = plain click at TARGET_X, TARGET_Y
;   F7  = Ctrl-held click at TARGET_X, TARGET_Y (force-run click)
;   F6  = clear the tooltip
;   Esc = exit the script
;
; ClickAt lives in Lib\Act.ahk - promoted here after in-game
; confirmation during Stage 1.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v6.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "04-click-at"

; ======= EDIT THESE FOR YOUR TEST =======================================
TARGET_X := 1400   ; a point you can visually verify - inventory slot,
TARGET_Y := 696   ; ground tile, etc.
; ========================================================================

F5:: RunClick(false)
F7:: RunClick(true)
F6:: {
    ToolTip()
    LogLine("F6 pressed - tooltip cleared")
}
Esc:: {
    LogLine("Esc pressed - exiting")
    ExitApp()
}

RunClick(useCtrl) {
    LogLine((useCtrl ? "Ctrl-click" : "Click") " started: target=" TARGET_X "," TARGET_Y)
    t0 := A_TickCount

    ClickAt(TARGET_X, TARGET_Y, useCtrl)

    elapsedMs := A_TickCount - t0
    msg := (useCtrl ? "Ctrl-clicked (force-run)" : "Clicked") " at " TARGET_X "," TARGET_Y " (" elapsedMs " ms incl. settle)"
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

LogLine("Script loaded. F5=click  F7=ctrl-click  F6=clear tooltip  Esc=exit. Target=" TARGET_X "," TARGET_Y)
ToolTip("micro 04 ready - F5 click / F7 ctrl-click", 20, 20)
