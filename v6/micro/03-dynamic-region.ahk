; ============================================================
; v6 micro 03 - dynamic search area
;
; Proves a bot can widen its own search area at runtime when the
; target isn't where expected - the pattern v5 Agility uses after a
; Mark-of-Grace detour (dynamicSearchActive): try a small region first
; (fast, cheap), then a bigger one, then the whole screen, only as
; needed.
;
; WHAT IT DOES
;   F5  = try SMALL region -> if not found, try EXPANDED region -> if
;         not found, try WHOLE SCREEN. Tooltip reports which stage
;         found it (or that all three missed). No click.
;   F6  = clear the tooltip
;   Esc = exit the script
;
; Same FindFilledBlock port as micros 01/02 - only difference is this
; one calls it up to three times with growing regions instead of once.
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

; Stage 1: small region - where the target normally is.
SMALL_X1 := 734, SMALL_Y1 := 511, SMALL_X2 := 894, SMALL_Y2 := 600

; Stage 2: expanded region - wider net if stage 1 misses.
EXPANDED_X1 := 400, EXPANDED_Y1 := 300, EXPANDED_X2 := 1400, EXPANDED_Y2 := 900

; Stage 3: whole screen - last resort.
; (computed from A_ScreenWidth/Height at search time)
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
    t0 := A_TickCount

    tStage := A_TickCount
    LogLine("Stage 1 (small): region=" SMALL_X1 "," SMALL_Y1 " -> " SMALL_X2 "," SMALL_Y2)
    if (FindFilledBlock(SMALL_X1, SMALL_Y1, SMALL_X2, SMALL_Y2, TARGET_COLOR, COLOR_TOL, BLOCK_W, BLOCK_H, &cx, &cy)) {
        Report("SMALL", cx, cy, A_TickCount - t0)
        return
    }
    LogLine("Stage 1 (small): not found (searched " (A_TickCount - tStage) " ms)")

    tStage := A_TickCount
    LogLine("Stage 2 (expanded): region=" EXPANDED_X1 "," EXPANDED_Y1 " -> " EXPANDED_X2 "," EXPANDED_Y2)
    if (FindFilledBlock(EXPANDED_X1, EXPANDED_Y1, EXPANDED_X2, EXPANDED_Y2, TARGET_COLOR, COLOR_TOL, BLOCK_W, BLOCK_H, &
        cx, &cy)) {
        Report("EXPANDED", cx, cy, A_TickCount - t0)
        return
    }
    LogLine("Stage 2 (expanded): not found (searched " (A_TickCount - tStage) " ms)")

    x2 := A_ScreenWidth - 1
    y2 := A_ScreenHeight - 1
    tStage := A_TickCount
    LogLine("Stage 3 (whole screen): region=0,0 -> " x2 "," y2)
    if (FindFilledBlock(0, 0, x2, y2, TARGET_COLOR, COLOR_TOL, BLOCK_W, BLOCK_H, &cx, &cy)) {
        Report("WHOLE SCREEN", cx, cy, A_TickCount - t0)
        return
    }
    LogLine("Stage 3 (whole screen): not found (searched " (A_TickCount - tStage) " ms)")

    ; "ms total" (not "in N ms"/"(searched N ms)" like the other micros)
    ; is deliberate here, not a drift - this elapsed figure is cumulative
    ; across all 3 stages, not one search call, so it needs its own
    ; wording to avoid implying it's a single search's duration.
    elapsedMs := A_TickCount - t0
    msg := "NOT FOUND at any stage (" elapsedMs " ms total)"
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

; elapsedMs here is cumulative from RunSearch's t0 across every stage
; tried so far, not just the one that matched - "ms total" reflects that
; (matches the "not found" messages above, kept deliberately distinct
; from the single-search "in N ms" wording used elsewhere).
Report(stage, cx, cy, elapsedMs) {
    MouseMove(cx, cy, 5)
    msg := "FOUND via " stage " at " cx "," cy " (" elapsedMs " ms total)"
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
    static logPath := logDir "\03-dynamic-region.log"
    if (!DirExist(logDir))
        DirCreate(logDir)
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " [03-dynamic-region] " msg "`n", logPath)
}

LogLine("Script loaded. F5=search (small->expanded->whole)  F6=clear tooltip  Esc=exit. Target=" HexColor(TARGET_COLOR))
ToolTip("micro 03 ready - F5 to search", 20, 20)