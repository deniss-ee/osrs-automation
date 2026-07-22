; ============================================================
; v7 micro 03 - whole-screen color block search
;
; Port of v6 micro 01, confirmed live there. Detection lives in
; Lib\Find.ahk (FindAnyFilledBlock, using the synthesized-bitmap
; ImageSearch fast path); this file just wires the F5/F6/Esc harness
; around it.
;
; TARGET_COLORS is an array (standard - see Find.ahk's file header):
; add/remove candidate colors freely, no restructuring needed even
; though this micro only ever had one color to search for.
;
; WHAT IT DOES
;   F5  = search the whole screen for a solid block of any color in
;         TARGET_COLORS, move the mouse onto it (NO click), show result
;         in a tooltip, log every step to v7\logs\03-find-color-screen.log
;   F6  = request stop (sets g_StopRequested, standard across every
;         micro/bot - F5 always starts, F6 always stops)
;   Esc = exit the script
;
; LIVE CONFIRM: place a solid-color marker (BLOCK_W x BLOCK_H, e.g. a
; RuneLite overlay or a filled paint square) on screen, press F5, and
; confirm the mouse cursor lands on it. Also test NOT FOUND with no
; marker present.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v7.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "03-find-color-screen"

; ======= EDIT THESE FOR YOUR TEST =======================================
TARGET_COLORS := [0x56FF50]   ; array of candidate colors - add/remove freely
COLOR_TOL := 5         ; per-channel tolerance (0-255)
BLOCK_W := 55         ; required solid block width in px
BLOCK_H := 55         ; required solid block height in px
; ========================================================================

F5:: RunSearch()
F6:: {
    global g_StopRequested
    g_StopRequested := true
    LogLine("F6 pressed - stop requested")
}
Esc:: {
    LogLine("Esc pressed - exiting")
    ExitApp()
}

RunSearch() {
    global g_StopRequested
    g_StopRequested := false

    x2 := A_ScreenWidth - 1
    y2 := A_ScreenHeight - 1
    LogLine("Search started: colors=" JoinMsg(TARGET_COLORS, "/", HexColor) " tol=" COLOR_TOL
        . " block=" BLOCK_W "x" BLOCK_H " region=0,0 -> " x2 "," y2 " (whole screen)")

    t0 := A_TickCount
    found := FindAnyFilledBlock(0, 0, x2, y2, TARGET_COLORS, COLOR_TOL, BLOCK_W, BLOCK_H, &cx, &cy, &foundColor)
    elapsedMs := A_TickCount - t0

    if (found) {
        MouseMove(cx, cy, 5)
        msg := "FOUND " HexColor(foundColor) " at " cx "," cy " in " elapsedMs " ms"
    } else {
        msg := "NOT FOUND any of " JoinMsg(TARGET_COLORS, "/", HexColor) " (searched " elapsedMs " ms)"
    }
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

LogLine("Script loaded. F5=search  F6=clear tooltip  Esc=exit. Targets=" JoinMsg(TARGET_COLORS, "/", HexColor))
ToolTip("micro 03 ready - F5 to search", 20, 20)
