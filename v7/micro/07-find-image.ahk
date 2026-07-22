; ============================================================
; v7 micro 07 - PNG image search (M2)
;
; Port of v6 micro 06, confirmed live there. Second sensor type:
; finding a known PNG on screen instead of a solid color. Same shape
; as color search (region in, found flag + center point out).
;
; Single image only, not an array (a deliberate exception to the
; colors-are-always-an-array standard): a different image asset has
; its own distinct pixel size, so a multi-candidate image array would
; need {path,w,h} entries, not a flat list - no current bot needs more
; than one candidate image at a time, so this stays single until one
; does.
;
; Search box is EXACT, not padded: PNG markers sit at one fixed known
; screen position (unlike a roaming color target), so this uses
; RegionAround(MARKER_X, MARKER_Y, IMAGE_W, IMAGE_H, 0) - marginPx=0
; reuses the same box-building code as micro 04 with zero slack,
; rather than hand-writing a new "exact box" formula. This is a
; script-local position (like 04/06's MARKER_X/Y), NOT a Lib global -
; v6's own bots show different deposit/bank markers measured at
; different screen positions per bot, so there's no single universal
; "the bank is always here" fact to hoist into Lib.
;
; TRANS_COLOR: this project's PNGs are captured with #00FF00 as the
; background - ImageSearch's *TransN option treats that exact color as
; see-through instead of requiring it to actually match. NOTE: AHK's
; named color "Green" = 0x008000 (a darker shade), NOT 0x00FF00 (that
; one's named "Lime") - use the explicit hex form to avoid targeting
; the wrong color.
;
; WHAT IT DOES
;   F5  = search the exact MARKER_X,MARKER_Y box (sized IMAGE_W x
;         IMAGE_H) for IMAGE_PATH; if found, move mouse to its center
;         (no click), tooltip + log the result
;   F6  = request stop (sets g_StopRequested, standard across every
;         micro/bot - F5 always starts, F6 always stops)
;   Esc = exit the script
;
; LIVE CONFIRM: set MARKER_X/MARKER_Y to the real on-screen top-left
; corner of a known PNG asset (deposit-motherlode.png ships in
; v7\Images at 80x72 as a placeholder test asset - swap IMAGE_PATH/W/H
; for whatever marker you actually have on screen), press F5, confirm
; the mouse lands on its center. Also test NOT FOUND with the marker
; not currently visible (e.g. wrong game screen/menu open).
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v7.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "07-find-image"

; ======= EDIT THESE FOR YOUR TEST =======================================
IMAGE_PATH := A_ScriptDir "\..\Images\deposit-motherlode.png"
IMAGE_W := 80          ; must match the PNG's real pixel size
IMAGE_H := 72
IMAGE_TOL := 5          ; shade-of-variation tolerance, 0-255 (0 = exact)
TRANS_COLOR := "0x00FF00"   ; background color to treat as see-through ("" to disable)

; Corner-measured marker position (top-left corner) - the ONE position
; input, same convention as 04/06. Exact box, no padding (see header).
MARKER_X := 775
MARKER_Y := 765
MARGIN_PX := 0     ; named, not a bare literal - exact box, no slack (see header)
; ========================================================================

; Derived exact search box - RegionAround with marginPx=0 (no slack),
; reusing the same box-building code as micro 04 instead of a new
; hand-written formula.
region := RegionAround(MARKER_X, MARKER_Y, IMAGE_W, IMAGE_H, MARGIN_PX)
REGION_X1 := region[1]
REGION_Y1 := region[2]
REGION_X2 := region[3]
REGION_Y2 := region[4]

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

    LogLine("Search started: image=" IMAGE_PATH " tol=" IMAGE_TOL " trans=" TRANS_COLOR
        . " size=" IMAGE_W "x" IMAGE_H " region=" REGION_X1 "," REGION_Y1 " -> " REGION_X2 "," REGION_Y2)

    t0 := A_TickCount
    found := FindImage(REGION_X1, REGION_Y1, REGION_X2, REGION_Y2, IMAGE_PATH, IMAGE_W, IMAGE_H, IMAGE_TOL, TRANS_COLOR, &cx, &cy)
    elapsedMs := A_TickCount - t0

    if (found) {
        MouseMove(cx, cy, 5)
        msg := "FOUND at " cx "," cy " in " elapsedMs " ms"
    } else {
        msg := "NOT FOUND (searched " elapsedMs " ms)"
    }
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

LogLine("Script loaded. F5=search  F6=request stop  Esc=exit. Image=" IMAGE_PATH
    . " at " MARKER_X "," MARKER_Y)
ToolTip("micro 07 ready - F5 to search for image", 20, 20)
