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
; Syntax verified against AutoHotkey.pdf: ImageSearch(&x, &y, x1, y1,
; x2, y2, imageFile) returns the match's UPPER-LEFT corner, not its
; center - center math (+imageW/2, +imageH/2) must be done by the
; caller, exactly as v5 Detection\StaticAnchor.ahk does. The "*n" option
; prefixed to the path controls shade-of-variation tolerance (0-255,
; default 0 = exact match) - same idea as color tolerance.
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
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

; ======= EDIT THESE FOR YOUR TEST =======================================
IMAGE_PATH := A_ScriptDir "\..\..\Images\deposit-motherlode.png"
IMAGE_W := 72     ; must match the PNG's real pixel size (see list above)
IMAGE_H := 72
IMAGE_TOL := 20      ; shade-of-variation tolerance, 0-255 (0 = exact)

REGION_X1 := 0, REGION_Y1 := 0, REGION_X2 := 2559, REGION_Y2 := 1439
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
    LogLine("Search started: image=" IMAGE_PATH " tol=" IMAGE_TOL
        . " size=" IMAGE_W "x" IMAGE_H " region=" REGION_X1 "," REGION_Y1 " -> " REGION_X2 "," REGION_Y2)

    t0 := A_TickCount
    try {
        found := ImageSearch(&foundX, &foundY, REGION_X1, REGION_Y1, REGION_X2, REGION_Y2,
            "*" IMAGE_TOL " " IMAGE_PATH)
    } catch as exc {
        msg := "ERROR: " exc.Message " (check IMAGE_PATH exists and IMAGE_W/H are correct)"
        ToolTip(msg, 20, 20)
        LogLine(msg)
        return
    }
    elapsedMs := A_TickCount - t0

    if (found) {
        cx := foundX + IMAGE_W // 2
        cy := foundY + IMAGE_H // 2
        MouseMove(cx, cy, 5)
        msg := "FOUND at " cx "," cy " (corner " foundX "," foundY ") in " elapsedMs " ms"
    } else {
        msg := "NOT FOUND (searched " elapsedMs " ms)"
    }
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

; ---------- logging ----------

LogLine(msg) {
    static logDir := A_ScriptDir "\..\logs"
    static logPath := logDir "\06-find-image.log"
    if (!DirExist(logDir))
        DirCreate(logDir)
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " [06-find-image] " msg "`n", logPath)
}

LogLine("Script loaded. F5=search  F6=clear tooltip  Esc=exit. Image=" IMAGE_PATH)
ToolTip("micro 06 ready - F5 to search for image", 20, 20)