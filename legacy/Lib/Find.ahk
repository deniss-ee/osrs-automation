; ============================================================
; v6 Lib\Find.ahk - detection primitives
;
; FindFilledBlock/SolidBlockBitmap/HexColor: byte-identical port from
; micros 01/02/03/05/08/12 (md5-verified across all six during Stage 1's
; final audit). ImagePattern: byte-identical port from micros 06/11.
; FindImage: NEW - a thin, mechanical extraction of the ImageSearch +
; center-math flow that was inlined in both 06's RunSearch and 11's
; ImageAppeared (identical logic in both, just not yet a named
; function) - not a behavior change, just factoring out the duplication
; so bots don't have to hand-roll it a third time. ColorClose/IsColorAt:
; byte-identical port from micro 09 (ColorClose) and 12 (IsColorAt).
; AcquireClosestInBox: parameterized port of micro 12's proximity
; tie-break helper (originally read TARGET_COLORS/REF_X/REF_Y etc. as
; script-level globals; here they're explicit params so any script/bot
; can call it with its own config, not just the one micro that defined
; it).
; ============================================================

; ---------- detection (fast native block search) ----------
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

; ---------- image search ----------

; Builds the "*tol *TransColor path" ImageSearch pattern string.
; transColor := "" omits the *Trans option entirely.
ImagePattern(path, tol, transColor := "") {
    pattern := "*" tol
    if (transColor != "")
        pattern .= " *Trans" transColor
    return pattern " " path
}

; Searches [x1,y1]-[x2,y2] for the image at path (w x h, its real pixel
; size - ImageSearch returns the match's UPPER-LEFT corner, not its
; center, so the caller-supplied w/h drive the center math); &cx/&cy
; get the center of the matched area.
FindImage(x1, y1, x2, y2, path, w, h, tol, transColor, &cx, &cy) {
    t0 := A_TickCount
    try {
        found := ImageSearch(&fx, &fy, x1, y1, x2, y2, ImagePattern(path, tol, transColor))
    } catch as exc {
        LogLine("FindImage: ERROR " exc.Message)
        return false
    }
    if (!found) {
        LogLine("FindImage: not found (" path ", " (A_TickCount - t0) " ms)")
        return false
    }
    cx := fx + w // 2
    cy := fy + h // 2
    LogLine("FindImage: found at " cx "," cy " (" path ", " (A_TickCount - t0) " ms)")
    return true
}

; ---------- color helpers ----------

HexColor(c) {
    return Format("0x{:06X}", c)
}

ColorClose(c1, c2, tol) {
    return Abs(((c1 >> 16) & 0xFF) - ((c2 >> 16) & 0xFF)) <= tol
        && Abs(((c1 >> 8) & 0xFF) - ((c2 >> 8) & 0xFF)) <= tol
        && Abs((c1 & 0xFF) - (c2 & 0xFF)) <= tol
}

IsColorAt(x, y, color, tol) {
    return ColorClose(PixelGetColor(x, y), color, tol)
}

; ---------- waypoint arrival (exact-position block check) ----------

; Waits for a color block whose CENTER lands exactly at (expectedCx,
; expectedCy) - not just "this color is somewhere on screen". Used by
; Motherlode's GoToSackArea()/ReturnToMine() arrival checks; promoted
; here (2026-07-20, moved verbatim from Bots\motherlode.ahk) since it's
; a generic "confirm arrival at a fixed waypoint" primitive, not
; Motherlode-specific logic - the same "click waypoint, wait for a
; marker at a known position" shape TEMPLATES.md's original Motherlode
; spec describes for its `return` phase, likely reusable by future
; walking bots (Agility, Firemaking). Outputs the real matched center
; via &fx/&fy (only meaningful when true is returned).
BlockAtPoint(expectedCx, expectedCy, color, tol, blockW, blockH, posTolPx, &fx, &fy) {
    static MARGIN_PX := 40   ; search slack around the expected block area

    found := FindFilledBlock(expectedCx - blockW // 2 - MARGIN_PX, expectedCy - blockH // 2 - MARGIN_PX,
        expectedCx + blockW // 2 + MARGIN_PX, expectedCy + blockH // 2 + MARGIN_PX,
        color, tol, blockW, blockH, &mx, &my)
    if (!found)
        return false

    if (Abs(mx - expectedCx) > posTolPx || Abs(my - expectedCy) > posTolPx)
        return false

    fx := mx, fy := my
    return true
}

; ---------- proximity acquire (multi-color, equal priority) ----------

; Searches every color in `colors` within [x1,y1]-[x2,y2] and returns
; the match closest to refX,refY (squared-distance compare - no need
; for the actual distance, just which is smaller - same tie-break v5
; Motherlode's _Acquire uses when multiple candidates match), NOT scan
; order. Every color is searched every call - none is favored by list
; order (see micro 12's TARGET_COLORS design).
AcquireClosestInBox(x1, y1, x2, y2, colors, tol, blockW, blockH, verifyPercent, refX, refY, &tx, &ty, &foundColor) {
    found := false
    bestDist := 0
    for color in colors {
        if (FindFilledBlock(x1, y1, x2, y2, color, tol, blockW, blockH, &cx, &cy, verifyPercent)) {
            dist := (cx - refX) ** 2 + (cy - refY) ** 2
            if (!found || dist < bestDist) {
                found := true
                bestDist := dist
                tx := cx, ty := cy, foundColor := color
            }
        }
    }
    return found
}
