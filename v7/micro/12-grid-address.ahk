; ============================================================
; v7 micro 12 - generalized grid addressing (GridSpec/GridCorner/
; GridCenter/GridCellRegion)
;
; Subsumes v6's SlotCorner/SlotCenter/BankSlotCenter + sudoku.ahk's
; local MenuItemCorner into one parameterized grid module - proving
; the SAME math correctly addresses a completely different grid
; (here: your inventory panel) just by changing the GridSpec, with no
; new code needed per grid shape.
;
; YOU NEED TO CALIBRATE THIS: INV_ORIGIN_X/Y below are placeholders -
; measure your own inventory panel's real top-left corner (slot 1's
; corner, not its center) and real cell size/gaps on your screen (2560x
; 1440, per this session) and fill those in. v6's own INV_FIRST_X/Y=
; 2099,801 were measured on a DIFFERENT setup and are not assumed to
; transfer here.
;
; WHAT IT DOES
;   F5  = GridCenter: move the mouse to slot CELL_INDEX's computed
;         CENTER. Confirm it lands exactly on that inventory slot's
;         middle.
;   F7  = GridCorner: move the mouse to slot CELL_INDEX's computed
;         CORNER (top-left) instead of its center - confirm it lands
;         precisely at the slot's top-left edge, not its middle.
;   F8  = GridCellRegion: log the full [x1,y1,x2,y2] box for
;         CELL_INDEX (no mouse movement) - inspect the numbers against
;         what you'd expect for that slot's real bounding box.
;   F6  = request stop (sets g_StopRequested, standard across every
;         micro/bot - F5 always starts, F6 always stops)
;   Esc = exit the script
;
; LIVE CONFIRM: set CELL_INDEX to 1 (top-left slot), press F5 - mouse
; should land dead-center in your first inventory slot. Try a few more
; indices spread across the grid (e.g. 4 - end of row 1, 5 - start of
; row 2, 28 - last slot) to confirm the row/col math wraps correctly
; at the far corners, not just the first slot. Press F7 on the same
; indices to confirm the corner (not center) lands at the slot's
; top-left, visibly offset from where F5 landed.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v7.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "12-grid-address"

; ======= EDIT THESE FOR YOUR TEST =======================================
; YOUR inventory panel's real measured values - placeholders below,
; calibrate against your actual screen.
INV_ORIGIN_X := 2099   ; slot 1's top-left corner (placeholder - v6's
INV_ORIGIN_Y := 801    ; value, measured on a different setup)
INV_COLS := 4
INV_ROWS := 7
INV_CELL_W := 72
INV_CELL_H := 64
INV_GAP_X := 12
INV_GAP_Y := 8

CELL_INDEX := 7   ; 1-based, row-major - which slot to test
; ========================================================================

invGrid := GridSpec(INV_ORIGIN_X, INV_ORIGIN_Y, INV_COLS, INV_ROWS, INV_CELL_W, INV_CELL_H, INV_GAP_X, INV_GAP_Y)

F5:: RunCenterCheck()
F7:: RunCornerCheck()
F8:: RunRegionCheck()
F6:: {
    global g_StopRequested
    g_StopRequested := true
    LogLine("F6 pressed - stop requested")
}
Esc:: {
    LogLine("Esc pressed - exiting")
    ExitApp()
}

RunCenterCheck() {
    global g_StopRequested, invGrid
    g_StopRequested := false

    GridCenter(invGrid, CELL_INDEX, &x, &y)
    MouseMove(x, y, 5)
    msg := "GridCenter(" CELL_INDEX ") = " x "," y " - mouse moved there"
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

RunCornerCheck() {
    global g_StopRequested, invGrid
    g_StopRequested := false

    GridCorner(invGrid, CELL_INDEX, &x, &y)
    MouseMove(x, y, 5)
    msg := "GridCorner(" CELL_INDEX ") = " x "," y " - mouse moved there"
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

RunRegionCheck() {
    global g_StopRequested, invGrid
    g_StopRequested := false

    region := GridCellRegion(invGrid, CELL_INDEX)
    msg := "GridCellRegion(" CELL_INDEX ") = " region[1] "," region[2] " -> " region[3] "," region[4]
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

LogLine("Script loaded. F5=center  F7=corner  F8=region  F6=request stop  Esc=exit."
    . " Grid origin=" INV_ORIGIN_X "," INV_ORIGIN_Y " cols=" INV_COLS " rows=" INV_ROWS
    . " cell=" INV_CELL_W "x" INV_CELL_H " gap=" INV_GAP_X "," INV_GAP_Y " index=" CELL_INDEX)
ToolTip("micro 12 ready - F5=center F7=corner F8=region", 20, 20)
