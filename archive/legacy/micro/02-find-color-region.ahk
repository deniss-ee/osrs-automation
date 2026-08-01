; ============================================================
; v6 micro 02 - region-limited color block search
;
; Same search as micro 01, but confined to a rectangle you define
; instead of the whole screen.
;
; WHAT IT DOES
;   F5  = search REGION for TARGET_COLOR, move mouse onto it (no click),
;         tooltip + log result, log every step
;   F6  = clear the tooltip
;   Esc = exit the script
;
; Detection lives in Lib\Find.ahk (FindFilledBlock) - promoted here
; after in-game confirmation during Stage 1.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v6.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "02-find-color-region"

; ======= EDIT THESE FOR YOUR TEST =======================================
TARGET_COLOR := 0xFF00FF   ; the RuneLite marker color to search for
COLOR_TOL := 5          ; per-channel tolerance (0-255)
BLOCK_W := 21         ; required solid block width in px
BLOCK_H := 21         ; required solid block height in px

; The search rectangle - EDIT to cover only part of your game view
; (e.g. left half, or a box around where you expect the marker).
REGION_X1 := 734
REGION_Y1 := 511
REGION_X2 := 894
REGION_Y2 := 600
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
    LogLine("Search started: color=" HexColor(TARGET_COLOR) " tol=" COLOR_TOL
        . " block=" BLOCK_W "x" BLOCK_H " region=" REGION_X1 "," REGION_Y1 " -> " REGION_X2 "," REGION_Y2)

    t0 := A_TickCount
    found := FindFilledBlock(REGION_X1, REGION_Y1, REGION_X2, REGION_Y2,
        TARGET_COLOR, COLOR_TOL, BLOCK_W, BLOCK_H, &cx, &cy)
    elapsedMs := A_TickCount - t0

    if (found) {
        inRegion := (cx >= REGION_X1 && cx <= REGION_X2 && cy >= REGION_Y1 && cy <= REGION_Y2)
        MouseMove(cx, cy, 5)
        msg := "FOUND " HexColor(TARGET_COLOR) " at " cx "," cy " in " elapsedMs " ms"
            . (inRegion ? " (inside region - correct)" : " (OUTSIDE region! bug)")
    } else {
        msg := "NOT FOUND " HexColor(TARGET_COLOR) " in region (searched " elapsedMs " ms)"
    }
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

LogLine("Script loaded. F5=search  F6=clear tooltip  Esc=exit. Target=" HexColor(TARGET_COLOR)
. " Region=" REGION_X1 "," REGION_Y1 " -> " REGION_X2 "," REGION_Y2)
ToolTip("micro 02 ready - F5 to search region", 20, 20)
