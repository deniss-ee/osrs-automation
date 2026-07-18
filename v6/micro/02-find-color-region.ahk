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
MAX_ATTEMPTS := 40         ; verify-and-split cap (speed safety valve)

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
        TARGET_COLOR, COLOR_TOL, BLOCK_W, BLOCK_H, &cx, &cy, , , MAX_ATTEMPTS)
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

; ---------- detection (identical port to micro 01) ----------

ColorClose(c1, c2, tol) {
    return Abs(((c1 >> 16) & 0xFF) - ((c2 >> 16) & 0xFF)) <= tol
    && Abs(((c1 >> 8) & 0xFF) - ((c2 >> 8) & 0xFF)) <= tol
    && Abs((c1 & 0xFF) - (c2 & 0xFF)) <= tol
}

IsColorAt(x, y, color, tol) {
    return ColorClose(PixelGetColor(x, y), color, tol)
}

VerifyBlock(x, y, color, tol, reqW, reqH) {
    checkW := reqW * 3 // 4
    checkH := reqH * 3 // 4
    if (!IsColorAt(x + checkW // 2, y + checkH // 2, color, tol))
        return false
    if (!IsColorAt(x, y + checkH // 2, color, tol))
        return false
    if (!IsColorAt(x + checkW // 2, y, color, tol))
        return false
    if (!IsColorAt(x + checkW - 1, y + checkH // 2, color, tol))
        return false
    if (!IsColorAt(x + checkW // 2, y + checkH - 1, color, tol))
        return false
    return true
}

FindFilledBlock(x1, y1, x2, y2, color, tol, reqW, reqH, &cx, &cy, refX := "", refY := "", maxAttempts := 40) {
    hasRef := (refX != "" && refY != "")
    stack := [[x1, y1, x2, y2]]
    attempts := 0

    while (stack.Length > 0) {
        if (maxAttempts > 0 && attempts >= maxAttempts) {
            LogLine("FindFilledBlock: gave up after " attempts " verify attempts (maxAttempts)")
            return false
        }

        rect := stack.Pop()
        rx1 := rect[1], ry1 := rect[2], rx2 := rect[3], ry2 := rect[4]

        if (rx1 > rx2 || ry1 > ry2)
            continue

        if (!PixelSearch(&foundX, &foundY, rx1, ry1, rx2, ry2, color, tol))
            continue

        attempts += 1

        if (VerifyBlock(foundX, foundY, color, tol, reqW, reqH)) {
            cx := Min(Max(foundX + reqW // 2, x1), x2)
            cy := Min(Max(foundY + reqH // 2, y1), y2)
            LogLine("FindFilledBlock: verified block on attempt " attempts " at " cx "," cy)
            return true
        }

        restOfRow := [foundX + 1, foundY, rx2, foundY]
        below := [rx1, foundY + 1, rx2, ry2]

        if (hasRef) {
            restContainsRef := (refY = foundY && refX >= restOfRow[1] && refX <= restOfRow[3])
            belowContainsRef := (refY >= below[2] && refY <= below[4])
            if (restContainsRef && !belowContainsRef) {
                stack.Push(below), stack.Push(restOfRow)
            } else if (belowContainsRef && !restContainsRef) {
                stack.Push(restOfRow), stack.Push(below)
            } else if (Abs(refY - foundY) <= Abs(refY - below[2])) {
                stack.Push(below), stack.Push(restOfRow)
            } else {
                stack.Push(restOfRow), stack.Push(below)
            }
        } else {
            stack.Push(below), stack.Push(restOfRow)
        }
    }

    return false
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