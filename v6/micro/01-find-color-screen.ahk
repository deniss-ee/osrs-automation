; ============================================================
; v6 micro 01 - whole-screen color block search
;
; WHAT IT DOES
;   F5  = search the whole screen for a solid block of TARGET_COLOR,
;         move the mouse onto it (NO click), show result in a tooltip,
;         log every step to v6\logs\01-find-color-screen.log
;   F6  = clear the tooltip
;   Esc = exit the script
;
; Algorithm ported from v5 Detection\ColorSearch.ahk (FindFilledBlock,
; VerifyBlock, ColorClose, IsColorAt), minus the bottom-up scan option.
; Syntax verified against AutoHotkey.pdf (PixelSearch, PixelGetColor,
; FormatTime). Note: v2's PixelGetColor always returns RGB - the "RGB"
; mode word used in v5 is a v1 leftover and is NOT passed here.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

; ======= EDIT THESE FOR YOUR TEST =======================================
TARGET_COLOR := 0xFF00FF   ; the RuneLite marker color to search for
COLOR_TOL := 5         ; per-channel tolerance (0-255)
BLOCK_W := 21         ; required solid block width in px
BLOCK_H := 21         ; required solid block height in px
MAX_ATTEMPTS := 3         ; verify-and-split cap (speed safety valve)
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
    x2 := A_ScreenWidth - 1
    y2 := A_ScreenHeight - 1
    LogLine("Search started: color=" HexColor(TARGET_COLOR) " tol=" COLOR_TOL
    . " block=" BLOCK_W "x" BLOCK_H " region=0,0 -> " x2 "," y2 " (whole screen)")

    t0 := A_TickCount
    found := FindFilledBlock(0, 0, x2, y2, TARGET_COLOR, COLOR_TOL, BLOCK_W, BLOCK_H, &cx, &cy, , , MAX_ATTEMPTS)
    elapsedMs := A_TickCount - t0

    if (found) {
        MouseMove(cx, cy, 5)
        msg := "FOUND " HexColor(TARGET_COLOR) " at " cx "," cy " in " elapsedMs " ms"
    } else {
        msg := "NOT FOUND " HexColor(TARGET_COLOR) " (searched " elapsedMs " ms)"
    }
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

; ---------- detection (v5 ColorSearch port, top-down only) ----------

; Each RGB channel of c1 within tol of c2's channel.
ColorClose(c1, c2, tol) {
    return Abs(((c1 >> 16) & 0xFF) - ((c2 >> 16) & 0xFF)) <= tol
    && Abs(((c1 >> 8) & 0xFF) - ((c2 >> 8) & 0xFF)) <= tol
    && Abs((c1 & 0xFF) - (c2 & 0xFF)) <= tol
}

IsColorAt(x, y, color, tol) {
    return ColorClose(PixelGetColor(x, y), color, tol)
}

; Fast 5-point cross-check that a reqW x reqH block anchored at (x,y) is
; solidly filled. Checks 75% of the requested size (safe against edge
; anti-aliasing). Always extends downward (top-down scan only in v6).
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

; Searches [x1,y1]-[x2,y2] top-down for a continuous block of `color` at
; least reqW x reqH. Writes the verified block's center to &cx/&cy.
; Iterative verify-and-split (stack, not recursion): each false-positive
; pixel splits the remaining area into "rest of row" + "everything below".
; refX/refY (optional) steer the split order toward an expected location.
; maxAttempts caps total verify cycles so a common color can't stall us.
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
            ; Explore whichever sub-rectangle contains the reference point
            ; first (LIFO stack - pushed last is searched next); if neither
            ; contains it, prefer the vertically closer one.
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
    static logPath := logDir "\01-find-color-screen.log"
    if (!DirExist(logDir))
        DirCreate(logDir)
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " [01-find-color-screen] " msg "`n", logPath)
}

LogLine("Script loaded. F5=search  F6=clear tooltip  Esc=exit. Target=" HexColor(TARGET_COLOR))
ToolTip("micro 01 ready - F5 to search", 20, 20)