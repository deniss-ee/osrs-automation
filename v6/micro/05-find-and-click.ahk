; ============================================================
; v6 micro 05 - find + click (composed)
;
; The first real "see -> act" test: search a region for TARGET_COLOR
; (micro 02's search), then click the result (micro 04's settled
; click). This is the shape every real bot step will use.
;
; WHAT IT DOES
;   F5  = search REGION for TARGET_COLOR -> if found, move + settle +
;         click it. Tooltip/log report found coords and whether the
;         click fired.
;   F6  = clear the tooltip
;   Esc = exit the script
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

REGION_X1 := 734
REGION_Y1 := 511
REGION_X2 := 894
REGION_Y2 := 600

SETTLE_MS := 100      ; mechanical delay between move and click (v6 default minimum)
CTRL_HOLD_MS := 100   ; ctrl-click only: held between the click firing and Ctrl release -
                       ; NOT redundant with SETTLE_MS (see ClickAt comment) - do not remove
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

; ---------- click (universal, ctrl-toggleable - port of micro 04) ----------

ClickAt(x, y, useCtrl := false) {
    if (useCtrl)
        Send("{Ctrl down}")

    MouseMove(x, y, 5)
    Sleep(SETTLE_MS)
    Click()

    ; CTRL_HOLD_MS is load-bearing, not redundant with SETTLE_MS - a prior
    ; attempt to remove it broke force-run in-game. Click() being
    ; synchronous only means the OS input queue accepted the down/up
    ; pair; it says nothing about whether OSRS's own client (reading
    ; input on its own thread/tick) has processed it yet. Releasing
    ; Ctrl too soon risks the client seeing the click without the held
    ; modifier, so the character walks instead of runs. v5's production
    ; Click.ahk holds this same gap (ctrlHoldSettleMs, default 100 in
    ; every bot's .ini) for exactly this reason.
    if (useCtrl) {
        Sleep(CTRL_HOLD_MS)
        Send("{Ctrl up}")
    }
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
    static logPath := logDir "\05-find-and-click.log"
    if (!DirExist(logDir))
        DirCreate(logDir)
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " [05-find-and-click] " msg "`n", logPath)
}

LogLine("Script loaded. F5=find+click  F6=clear tooltip  Esc=exit. Target=" HexColor(TARGET_COLOR))
ToolTip("micro 05 ready - F5 to find+click", 20, 20)