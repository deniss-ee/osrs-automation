; ============================================================
; v6 micro 05 - find + click (composed)
;
; The first real "see -> act" test: search a region for TARGET_COLOR,
; then click the result. This is the shape every real bot step uses.
;
; WHAT IT DOES
;   F5  = search REGION for TARGET_COLOR -> if found, move + settle +
;         click it. Tooltip/log report found coords and whether the
;         click fired.
;   F6  = clear the tooltip
;   Esc = exit the script
;
; FindFilledBlock (Lib\Find.ahk) + ClickAt (Lib\Act.ahk) - both
; promoted here after in-game confirmation during Stage 1.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v6.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "05-find-and-click"

; ======= EDIT THESE FOR YOUR TEST =======================================
TARGET_COLOR := 0xFF00FF   ; the RuneLite marker color to search for
COLOR_TOL := 5          ; per-channel tolerance (0-255)
BLOCK_W := 21         ; required solid block width in px
BLOCK_H := 21         ; required solid block height in px

REGION_X1 := 734
REGION_Y1 := 511
REGION_X2 := 894
REGION_Y2 := 600

USE_CTRL  := true  ; true = force-run (Ctrl-held) click on the found target
; ========================================================================

F5:: FindAndClick()
F6:: {
    ToolTip()
    LogLine("F6 pressed - tooltip cleared")
}
Esc:: {
    LogLine("Esc pressed - exiting")
    ExitApp()
}

FindAndClick() {
    LogLine("Search started: color=" HexColor(TARGET_COLOR) " tol=" COLOR_TOL
        . " block=" BLOCK_W "x" BLOCK_H " region=" REGION_X1 "," REGION_Y1 " -> " REGION_X2 "," REGION_Y2)

    t0 := A_TickCount
    found := FindFilledBlock(REGION_X1, REGION_Y1, REGION_X2, REGION_Y2,
        TARGET_COLOR, COLOR_TOL, BLOCK_W, BLOCK_H, &cx, &cy)
    searchMs := A_TickCount - t0

    if (!found) {
        msg := "NOT FOUND (searched " searchMs " ms) - no click"
        ToolTip(msg, 20, 20)
        LogLine(msg)
        return
    }

    LogLine("Found at " cx "," cy " in " searchMs " ms - clicking")
    ClickAt(cx, cy, USE_CTRL)
    totalMs := A_TickCount - t0

    msg := "FOUND + CLICKED at " cx "," cy " in " searchMs " ms (total " totalMs " ms incl. click)"
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

LogLine("Script loaded. F5=find+click  F6=clear tooltip  Esc=exit. Target=" HexColor(TARGET_COLOR))
ToolTip("micro 05 ready - F5 to find+click", 20, 20)
