; ============================================================
; v6 micro 08 - travel-and-confirm pattern
; (click somewhere -> wait for a marker to appear -> click elsewhere)
;
; This is the pattern the user actually uses today: start running
; toward a destination, wait until a specific colored marker becomes
; visible in a specific region (confirming arrival/that something
; happened), THEN click a completely different point - not the marker
; itself. Distinct from micro 05 (which clicks the found target).
;
; Composes:
;   - micro 04's settled click (the START click)
;   - micro 02's region search, wrapped in micro 07's interruptible
;     WaitUntil/Pause (the WAIT for the marker)
;   - micro 04's settled click again (the AFTER click, fixed point)
;
; WHAT IT DOES
;   F5  = click START point -> wait up to WAIT_TIMEOUT_MS for
;         MARKER_COLOR to appear in WAIT_REGION -> if it appears,
;         click AFTER point. If F6 is pressed during the wait, stops
;         immediately without clicking AFTER. If it times out, logs
;         and stops without clicking AFTER either.
;   F6  = request stop (interrupts the wait, same as micro 07)
;   Esc = exit the script
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

; ======= EDIT THESE FOR YOUR TEST =======================================
START_X := 1000, START_Y := 720     ; e.g. a point that makes the character start moving
START_USE_CTRL := true              ; true = force-run (Ctrl-held) click

MARKER_COLOR := 0xFF00FF
COLOR_TOL    := 5
BLOCK_W      := 21
BLOCK_H      := 21
MAX_ATTEMPTS := 40

; Where the marker should appear once you've arrived/something happened.
WAIT_REGION_X1 := 787, WAIT_REGION_Y1 := 533, WAIT_REGION_X2 := 808, WAIT_REGION_Y2 := 554
WAIT_TIMEOUT_MS := 15000   ; give up after this long if the marker never appears
POLL_MS         := 300     ; tick-aligned poll interval

AFTER_X := 1153, AFTER_Y := 1037      ; the SEPARATE point to click once confirmed
                                     ; (NOT the marker's own found coordinates)
AFTER_USE_CTRL := true              ; true = force-run (Ctrl-held) click

SETTLE_MS := 150
CHUNK_MS  := 40
; ========================================================================

g_StopRequested := false

F5:: RunFlow()
F6:: {
    global g_StopRequested
    g_StopRequested := true
    LogLine("F6 pressed - stop requested")
}
Esc:: {
    LogLine("Esc pressed - exiting")
    ExitApp()
}

RunFlow() {
    global g_StopRequested
    g_StopRequested := false

    LogLine("Flow started: click start=" START_X "," START_Y
        . " -> wait for marker in " WAIT_REGION_X1 "," WAIT_REGION_Y1 " -> " WAIT_REGION_X2 "," WAIT_REGION_Y2
        . " (timeout " WAIT_TIMEOUT_MS "ms) -> click after=" AFTER_X "," AFTER_Y)
    ToolTip("Clicking start point...", 20, 20)

    ClickAt(START_X, START_Y, START_USE_CTRL)
    LogLine("Clicked start point " START_X "," START_Y . (START_USE_CTRL ? " (ctrl/force-run)" : ""))

    ToolTip("Waiting for marker (F6 to cancel)...", 20, 20)
    t0 := A_TickCount

    try {
        markerAppeared := WaitUntil(MarkerVisible, WAIT_TIMEOUT_MS, POLL_MS)
    } catch BotStopped as e {
        elapsedMs := A_TickCount - t0
        msg := "STOPPED by F6 after " elapsedMs " ms waiting - AFTER click skipped"
        ToolTip(msg, 20, 20)
        LogLine(msg)
        return
    }

    elapsedMs := A_TickCount - t0

    if (!markerAppeared) {
        msg := "TIMED OUT after " elapsedMs " ms - marker never appeared - AFTER click skipped"
        ToolTip(msg, 20, 20)
        LogLine(msg)
        return
    }

    LogLine("Marker confirmed after " elapsedMs " ms - clicking AFTER point (separate from marker location)")
    ClickAt(AFTER_X, AFTER_Y, AFTER_USE_CTRL)

    msg := "DONE: marker confirmed (" elapsedMs " ms), clicked AFTER at " AFTER_X "," AFTER_Y
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

; Settled click at a fixed point. useCtrl=true holds Ctrl for the
; duration (OSRS "force run" modifier) - same shape as v5's
; ClickAtWithCtrl/ClickSettled(runMode). Universal: every click site
; in this script goes through here, so force-run is a one-flag toggle.
ClickAt(x, y, useCtrl := false) {
    if (useCtrl)
        Send("{Ctrl down}")

    MouseMove(x, y, 5)
    Sleep(SETTLE_MS)
    Click()

    if (useCtrl) {
        Sleep(SETTLE_MS)
        Send("{Ctrl up}")
    }
}

; Condition passed to WaitUntil - true the instant the marker is found
; anywhere in WAIT_REGION. Logs each check's outcome.
MarkerVisible() {
    found := FindFilledBlock(WAIT_REGION_X1, WAIT_REGION_Y1, WAIT_REGION_X2, WAIT_REGION_Y2,
        MARKER_COLOR, COLOR_TOL, BLOCK_W, BLOCK_H, &cx, &cy, , , MAX_ATTEMPTS)
    if (found)
        LogLine("MarkerVisible: found at " cx "," cy)
    else
        LogLine("MarkerVisible: not yet visible")
    return found
}

; ---------- interruptible wait (identical port of micro 07) ----------

class BotStopped extends Error {
    __New() {
        super.__New("Bot stopped by user")
    }
}

Pause(ms) {
    global g_StopRequested
    remaining := ms
    while (remaining > 0) {
        if (g_StopRequested)
            throw BotStopped()
        step := Min(CHUNK_MS, remaining)
        Sleep(step)
        remaining -= step
    }
    if (g_StopRequested)
        throw BotStopped()
}

WaitUntil(condFn, timeoutMs, pollMs := 300) {
    startedAt := A_TickCount
    loop {
        if (condFn())
            return true
        if ((A_TickCount - startedAt) >= timeoutMs)
            return false
        Pause(pollMs)
    }
}

; ---------- detection (identical port to micro 01-03/05) ----------

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
        if (maxAttempts > 0 && attempts >= maxAttempts)
            return false

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

LogLine(msg) {
    static logDir := A_ScriptDir "\..\logs"
    static logPath := logDir "\08-wait-marker-then-click.log"
    if (!DirExist(logDir))
        DirCreate(logDir)
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " [08-wait-marker-then-click] " msg "`n", logPath)
}

LogLine("Script loaded. F5=run flow  F6=stop  Esc=exit")
ToolTip("micro 08 ready - F5 to run: click start -> wait for marker -> click after", 20, 20)
