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
MAX_ATTEMPTS := 40         ; verify-and-split cap per stage

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

    LogLine("Stage 1 (small): region=" SMALL_X1 "," SMALL_Y1 " -> " SMALL_X2 "," SMALL_Y2)
    if (FindFilledBlock(SMALL_X1, SMALL_Y1, SMALL_X2, SMALL_Y2, TARGET_COLOR, COLOR_TOL, BLOCK_W, BLOCK_H, &cx, &cy, , ,
        MAX_ATTEMPTS)) {
        Report("SMALL", cx, cy, A_TickCount - t0)
        return
    }
    LogLine("Stage 1 (small): not found")

    LogLine("Stage 2 (expanded): region=" EXPANDED_X1 "," EXPANDED_Y1 " -> " EXPANDED_X2 "," EXPANDED_Y2)
    if (FindFilledBlock(EXPANDED_X1, EXPANDED_Y1, EXPANDED_X2, EXPANDED_Y2, TARGET_COLOR, COLOR_TOL, BLOCK_W, BLOCK_H, &
        cx, &cy, , , MAX_ATTEMPTS)) {
        Report("EXPANDED", cx, cy, A_TickCount - t0)
        return
    }
    LogLine("Stage 2 (expanded): not found")

    x2 := A_ScreenWidth - 1
    y2 := A_ScreenHeight - 1
    LogLine("Stage 3 (whole screen): region=0,0 -> " x2 "," y2)
    if (FindFilledBlock(0, 0, x2, y2, TARGET_COLOR, COLOR_TOL, BLOCK_W, BLOCK_H, &cx, &cy, , , MAX_ATTEMPTS)) {
        Report("WHOLE SCREEN", cx, cy, A_TickCount - t0)
        return
    }
    LogLine("Stage 3 (whole screen): not found")

    elapsedMs := A_TickCount - t0
    msg := "NOT FOUND at any stage (" elapsedMs " ms total)"
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

Report(stage, cx, cy, elapsedMs) {
    MouseMove(cx, cy, 5)
    msg := "FOUND via " stage " at " cx "," cy " (" elapsedMs " ms total)"
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

; ---------- detection (identical port to micro 01/02) ----------

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
    static logPath := logDir "\03-dynamic-region.log"
    if (!DirExist(logDir))
        DirCreate(logDir)
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " [03-dynamic-region] " msg "`n", logPath)
}

LogLine("Script loaded. F5=search (small->expanded->whole)  F6=clear tooltip  Esc=exit. Target=" HexColor(TARGET_COLOR))
ToolTip("micro 03 ready - F5 to search", 20, 20)