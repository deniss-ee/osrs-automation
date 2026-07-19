; ============================================================
; v6 micro 02 - region-limited color block search
;
; Same search as micro 01, but confined to a rectangle you define
; instead of the whole screen. Proves a region cuts out anything
; outside it (a real perf win: less area = fewer PixelSearch rows).
;
; WHAT IT DOES
;   F5  = search REGION (drawn in yellow via a 1px border overlay while
;         searching) for TARGET_COLOR, move mouse onto it (no click),
;         tooltip + log result, log every step
;   F6  = clear the tooltip
;   Esc = exit the script
;
; Algorithm identical to micro 01 (same FindFilledBlock port) - the
; only difference is the region passed in is smaller than the screen.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

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

; ---------- detection (fast native block search - identical across micros) ----------
;
; SPEED OVERHAUL (2026-07-19): the old verify-and-split loop paid a
; stack of ~7ms pixel-API calls per rejected candidate, so whole-screen
; speed depended on how much of the color was elsewhere on screen
; (measured live: 42 yellow UI specks cost ~3s). Replaced with ONE
; native ImageSearch for a solid reqW x reqH block of the color: only
; a full-size solid block can match, decoys/specks cost nothing, and
; whole-screen search runs at a constant ~100-200 ms no matter what
; else is visible. Syntax verified against AutoHotkey.pdf: ImageSearch
; accepts a bitmap handle as "HBITMAP:*" handle, and *n allows n shades
; of variation per RGB channel (same semantics as PixelSearch tolerance).

; Builds (and caches per color+size) the solid-color in-memory bitmap
; that ImageSearch matches against.
SolidBlockBitmap(color, w, h) {
    static cache := Map()
    key := color "_" w "x" h
    if (cache.Has(key))
        return cache[key]

    hdc := DllCall("GetDC", "ptr", 0, "ptr")
    memDC := DllCall("CreateCompatibleDC", "ptr", hdc, "ptr")
    hbm := DllCall("CreateCompatibleBitmap", "ptr", hdc, "int", w, "int", h, "ptr")
    oldBmp := DllCall("SelectObject", "ptr", memDC, "ptr", hbm, "ptr")

    ; GDI COLORREF is 0x00BBGGRR - swap R and B from the 0xRRGGBB value
    bgr := ((color & 0xFF) << 16) | (color & 0xFF00) | ((color >> 16) & 0xFF)
    brush := DllCall("CreateSolidBrush", "uint", bgr, "ptr")
    rect := Buffer(16, 0)
    NumPut("int", 0, "int", 0, "int", w, "int", h, rect)
    DllCall("FillRect", "ptr", memDC, "ptr", rect, "ptr", brush)

    DllCall("DeleteObject", "ptr", brush)
    DllCall("SelectObject", "ptr", memDC, "ptr", oldBmp, "ptr")
    DllCall("DeleteDC", "ptr", memDC)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdc)

    cache[key] := hbm
    return hbm
}

; True if a solid block of `color` at least reqW x reqH (scaled by
; verifyPercent) exists in the region; &cx/&cy get the center of the
; matched area. verifyPercent 100 = strict full size; lower it only if
; a real target's soft/anti-aliased edges make the strict match miss.
FindFilledBlock(x1, y1, x2, y2, color, tol, reqW, reqH, &cx, &cy, verifyPercent := 100) {
    t0 := A_TickCount
    bmpW := Max(1, reqW * verifyPercent // 100)
    bmpH := Max(1, reqH * verifyPercent // 100)
    hbm := SolidBlockBitmap(color, bmpW, bmpH)

    if (!ImageSearch(&fx, &fy, x1, y1, x2, y2, "*" tol " HBITMAP:*" hbm)) {
        LogLine("FindFilledBlock: not found (" bmpW "x" bmpH " " HexColor(color) " tol=" tol ", " (A_TickCount - t0) " ms)")
        return false
    }
    cx := fx + bmpW // 2
    cy := fy + bmpH // 2
    LogLine("FindFilledBlock: found at " cx "," cy " (" bmpW "x" bmpH " " HexColor(color) " tol=" tol ", " (A_TickCount - t0) " ms)")
    return true
}

; ---------- logging ----------

HexColor(c) {
    return Format("0x{:06X}", c)
}

LogLine(msg) {
    static logDir := A_ScriptDir "\..\logs"
    static logPath := logDir "\02-find-color-region.log"
    if (!DirExist(logDir))
        DirCreate(logDir)
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " [02-find-color-region] " msg "`n", logPath)
}

LogLine("Script loaded. F5=search  F6=clear tooltip  Esc=exit. Target=" HexColor(TARGET_COLOR)
. " Region=" REGION_X1 "," REGION_Y1 " -> " REGION_X2 "," REGION_Y2)
ToolTip("micro 02 ready - F5 to search region", 20, 20)