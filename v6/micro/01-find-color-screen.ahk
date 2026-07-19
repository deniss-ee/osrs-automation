; ============================================================
; v6 micro 01 - whole-screen color block search
;
; WHAT IT DOES
;   F5  = search the whole screen for a solid block of TARGET_COLOR,
;         move the mouse onto it (NO click), show result in a tooltip,
;         log every step to v6\logs\01-find-color-screen.log
;   F6  = clear the tooltip
;   Esc = exit the script
;
; Detection now lives in Lib\Find.ahk (FindFilledBlock) - promoted
; here after in-game confirmation during Stage 1. This file just
; wires the F5/F6/Esc harness around it.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v6.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "01-find-color-screen"

; ======= EDIT THESE FOR YOUR TEST =======================================
TARGET_COLOR := 0xFF00FF   ; the RuneLite marker color to search for
COLOR_TOL := 5         ; per-channel tolerance (0-255)
BLOCK_W := 21         ; required solid block width in px
BLOCK_H := 21         ; required solid block height in px
; ========================================================================

F5:: RunSearch()
F6:: {
    ToolTip()
    LogLine("F6 pressed - tooltip cleared")
}
Esc:: {
    LogLine("Esc pressed - exiting")
    ExitApp()
}

RunSearch() {
    x2 := A_ScreenWidth - 1
    y2 := A_ScreenHeight - 1
    LogLine("Search started: color=" HexColor(TARGET_COLOR) " tol=" COLOR_TOL
        . " block=" BLOCK_W "x" BLOCK_H " region=0,0 -> " x2 "," y2 " (whole screen)")

    t0 := A_TickCount
    found := FindFilledBlock(0, 0, x2, y2, TARGET_COLOR, COLOR_TOL, BLOCK_W, BLOCK_H, &cx, &cy)
    elapsedMs := A_TickCount - t0

    if (found) {
        MouseMove(cx, cy, 5)
        msg := "FOUND " HexColor(TARGET_COLOR) " at " cx "," cy " in " elapsedMs " ms"
    } else {
        msg := "NOT FOUND " HexColor(TARGET_COLOR) " (searched " elapsedMs " ms)"
    }
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

LogLine("Script loaded. F5=search  F6=clear tooltip  Esc=exit. Target=" HexColor(TARGET_COLOR))
ToolTip("micro 01 ready - F5 to search", 20, 20)
