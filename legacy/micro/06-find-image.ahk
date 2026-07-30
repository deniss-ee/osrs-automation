; ============================================================
; v6 micro 06 - PNG image search
;
; Proves the second sensor type: finding a known PNG on screen instead
; of a solid color. Same shape as color search (region in, found flag +
; center point out) so bot code can treat both the same way later.
;
; WHAT IT DOES
;   F5  = search REGION for IMAGE_PATH; if found, move mouse to its
;         center (no click), tooltip + log the result
;   F6  = clear the tooltip
;   Esc = exit the script
;
; TRANS_COLOR: this project's PNGs are captured with #00FF00 as the
; background - ImageSearch's *TransN option treats that exact color as
; see-through instead of requiring it to actually match. NOTE: AHK's
; named color "Green" = 0x008000 (a darker shade), NOT 0x00FF00 (that
; one's named "Lime") - use the explicit hex form to avoid targeting
; the wrong color.
;
; Existing PNGs in root Images\ and their real pixel dimensions
; (measured from each file's IHDR chunk - AHK cannot query this):
;   bb-item.png           94 x 22
;   craft-marker-1.png     70 x 60
;   craft-marker-2.png     74 x 74
;   deposit-default.png    72 x 72
;   deposit-motherlode.png 80 x 72
;   mog-item.png          134 x 22
;   take-bb.png           194 x 30
;
; FindImage lives in Lib\Find.ahk - promoted here after in-game
; confirmation during Stage 1 (fixed a real IMAGE_W bug, 72 -> 80,
; during the final audit; whole-screen fallback made resolution-
; agnostic at the same time).
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v6.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "06-find-image"

; ======= EDIT THESE FOR YOUR TEST =======================================
IMAGE_PATH := A_ScriptDir "\..\Images\deposit-motherlode.png"
IMAGE_W := 80     ; must match the PNG's real pixel size (see list above)
IMAGE_H := 72
IMAGE_TOL := 5      ; shade-of-variation tolerance, 0-255 (0 = exact)
TRANS_COLOR := "0x00FF00"   ; background color to treat as see-through ("" to disable)

REGION_X1 := 0, REGION_Y1 := 0, REGION_X2 := A_ScreenWidth - 1, REGION_Y2 := A_ScreenHeight - 1
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

LogLine("Script loaded. F5=search  F6=clear tooltip  Esc=exit. Image=" IMAGE_PATH)
ToolTip("micro 06 ready - F5 to search for image", 20, 20)
