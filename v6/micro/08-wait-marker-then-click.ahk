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
BLOCK_W      := 11
BLOCK_H      := 11

; Where the marker should appear once you've arrived/something happened.
WAIT_REGION_X1 := 716, WAIT_REGION_Y1 := 543, WAIT_REGION_X2 := 737, WAIT_REGION_Y2 := 564
WAIT_TIMEOUT_MS := 15000   ; give up after this long if the marker never appears
POLL_MS         := 300     ; tick-aligned poll interval

AFTER_X := 1153, AFTER_Y := 1037      ; the SEPARATE point to click once confirmed
                                     ; (NOT the marker's own found coordinates)
AFTER_USE_CTRL := true              ; true = force-run (Ctrl-held) click

SETTLE_MS := 100
CTRL_HOLD_MS := 100   ; ctrl-click only: held between the click firing and Ctrl release -
                       ; NOT redundant with SETTLE_MS (see ClickAt comment) - do not remove
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

; Condition passed to WaitUntil - true the instant the marker is found
; anywhere in WAIT_REGION. Logs each check's outcome.
MarkerVisible() {
    t0 := A_TickCount
    found := FindFilledBlock(WAIT_REGION_X1, WAIT_REGION_Y1, WAIT_REGION_X2, WAIT_REGION_Y2,
        MARKER_COLOR, COLOR_TOL, BLOCK_W, BLOCK_H, &cx, &cy)
    searchMs := A_TickCount - t0
    if (found)
        LogLine("MarkerVisible: found at " cx "," cy " in " searchMs " ms")
    else
        LogLine("MarkerVisible: not yet visible (searched " searchMs " ms)")
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
        if (g_StopRequested) {
            LogLine("Pause: stop flag seen - throwing BotStopped")
            throw BotStopped()
        }
        step := Min(CHUNK_MS, remaining)
        Sleep(step)
        remaining -= step
    }
    if (g_StopRequested) {
        LogLine("Pause: stop flag seen at end of wait - throwing BotStopped")
        throw BotStopped()
    }
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
    static logPath := logDir "\08-wait-marker-then-click.log"
    if (!DirExist(logDir))
        DirCreate(logDir)
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " [08-wait-marker-then-click] " msg "`n", logPath)
}

LogLine("Script loaded. F5=run flow  F6=stop  Esc=exit")
ToolTip("micro 08 ready - F5 to run: click start -> wait for marker -> click after", 20, 20)
