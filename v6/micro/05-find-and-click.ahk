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
MAX_ATTEMPTS := 40         ; verify-and-split cap

REGION_X1 := 734
REGION_Y1 := 511
REGION_X2 := 894
REGION_Y2 := 600

SETTLE_MS := 150   ; mechanical delay between move and click (v6 default)
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
        TARGET_COLOR, COLOR_TOL, BLOCK_W, BLOCK_H, &cx, &cy, , , MAX_ATTEMPTS)
    searchMs := A_TickCount - t0

    if (!found) {
        msg := "NOT FOUND (searched " searchMs " ms) - no click"
        ToolTip(msg, 20, 20)
        LogLine(msg)
        return
    }

    LogLine("Found at " cx "," cy " in " searchMs " ms - clicking")
    MouseMove(cx, cy, 5)
    Sleep(SETTLE_MS)
    Click()
    totalMs := A_TickCount - t0

    msg := "FOUND + CLICKED at " cx "," cy " (search " searchMs " ms, total " totalMs " ms)"
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

; ---------- detection (identical port to micro 01-03) ----------

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
    static logPath := logDir "\05-find-and-click.log"
    if (!DirExist(logDir))
        DirCreate(logDir)
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " [05-find-and-click] " msg "`n", logPath)
}

LogLine("Script loaded. F5=find+click  F6=clear tooltip  Esc=exit. Target=" HexColor(TARGET_COLOR))
ToolTip("micro 05 ready - F5 to find+click", 20, 20)