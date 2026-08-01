; ============================================================
; v7 micro 04 - region-limited color block search + RegionAround
;
; Same search as micro 03, but confined to a rectangle built by
; RegionAround(cornerX, cornerY, w, h, marginPx) from a corner-measured
; marker area, instead of the whole screen. This validates BOTH
; FindFilledBlock's region-limiting behavior (port of v6 micro 02, no
; contract change) AND the new RegionAround helper (moved into
; Find.ahk from v6's Steps.ahk) in one pass, since one exists only to
; feed the other here.
;
; TARGET_COLORS is an array (standard - see Find.ahk's file header):
; add/remove candidate colors freely.
;
; WHAT IT DOES
;   F5  = compute the region via RegionAround(AREA_X, AREA_Y, AREA_W,
;         AREA_H, MARGIN_PX), search it for any color in TARGET_COLORS,
;         move mouse onto it (no click), tooltip + log result
;   F6  = request stop (sets g_StopRequested, standard across every
;         micro/bot - F5 always starts, F6 always stops)
;   Esc = exit the script
;
; LIVE CONFIRM: set AREA_X/Y/W/H to a box around where your marker
; actually sits (not the marker's own exact coords - the point is to
; prove the padded region still finds it), press F5, confirm mouse
; lands on the marker and the log/tooltip says "inside region". Then
; move the marker outside the region (or shrink MARGIN_PX) to confirm
; NOT FOUND correctly fires instead of a false match from elsewhere.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v7.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "04-find-color-region"

; ======= EDIT THESE FOR YOUR TEST =======================================
TARGET_COLORS := [0xFFB232]   ; array of candidate colors - add/remove freely
COLOR_TOL := 5          ; per-channel tolerance (0-255)
BLOCK_W := 17          ; required solid block width in px
BLOCK_H := 17          ; required solid block height in px

; Corner-measured area the marker sits in (top-left corner + size),
; NOT the marker's own tight coords - RegionAround pads it.
AREA_X := 1634
AREA_Y := 764
AREA_W := 60
AREA_H := 36
MARGIN_PX := 16
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

    region := RegionAround(AREA_X, AREA_Y, AREA_W, AREA_H, MARGIN_PX)
    x1 := region[1], y1 := region[2], x2 := region[3], y2 := region[4]

    LogLine("Search started: colors=" JoinMsg(TARGET_COLORS, "/", HexColor) " tol=" COLOR_TOL
        . " block=" BLOCK_W "x" BLOCK_H " area=" AREA_X "," AREA_Y "," AREA_W "x" AREA_H
        . " margin=" MARGIN_PX " -> region=" x1 "," y1 " -> " x2 "," y2)

    t0 := A_TickCount
    found := FindAnyFilledBlock(x1, y1, x2, y2, TARGET_COLORS, COLOR_TOL, BLOCK_W, BLOCK_H, &cx, &cy, &foundColor)
    elapsedMs := A_TickCount - t0

    if (found) {
        inRegion := (cx >= x1 && cx <= x2 && cy >= y1 && cy <= y2)
        MouseMove(cx, cy, 5)
        msg := "FOUND " HexColor(foundColor) " at " cx "," cy " in " elapsedMs " ms"
            . (inRegion ? " (inside region - correct)" : " (OUTSIDE region! bug)")
    } else {
        msg := "NOT FOUND any of " JoinMsg(TARGET_COLORS, "/", HexColor) " in region (searched " elapsedMs " ms)"
    }
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

LogLine("Script loaded. F5=search region  F6=request stop  Esc=exit. Targets=" JoinMsg(TARGET_COLORS, "/", HexColor)
    . " Area=" AREA_X "," AREA_Y "," AREA_W "x" AREA_H " margin=" MARGIN_PX)
ToolTip("micro 04 ready - F5 to search region", 20, 20)
