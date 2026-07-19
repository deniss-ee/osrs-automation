; ============================================================
; v6 micro 12 - acquire/track/depleted loop ("TrackAndClick")
;
; The biggest composite so far: click a target, keep tracking it in a
; narrowed box as it's worked, re-click on a cadence, detect depletion
; (color stops matching) and re-acquire a fresh target - until an
; "until" condition is met (here: an inventory indicator slot full,
; the exact same condition real Woodcutting/Motherlode/AutoFighter use).
;
; Ported faithfully from v5 Detection\TargetLock.ahk (the stability
; debounce class, verbatim) + Bots\Woodcutting\woodcutting.ahk's
; ChopWoodPhase (the acquire/track control flow) - including the real
; production behavior that a single not-found tick means "depleted,
; re-acquire immediately" (TargetLock.IsLost()/missingTicksToUnlock
; exists in the class but ChopWoodPhase never actually calls IsLost() -
; it just acts on FindFilledBlock's own found=false directly).
;
; Composes: FindFilledBlock (01/02/03/05/08/11), ClickAt (04/05/08/11),
; Pause/WaitUntil/BotStopped (07/08/10/11), SlotCenter/SlotFull (09) as
; the until-condition.
;
; WHAT IT DOES
;   F8  = COLOR PROBE: hover any pixel, get its TRUE on-screen color,
;         the per-channel delta vs TARGET_COLOR, and the minimum
;         tolerance that would match - use this FIRST whenever a new
;         color "isn't found" (on-screen rendering often blends/shades
;         the configured pure hex)
;   F5  = start the loop: acquire a target -> track/click it -> on
;         depletion (color stops matching), re-acquire -> repeat, until
;         the indicator slot is full OR the overall failsafe timeout
;         elapses. Every tick logged (acquire/track/click/stable state).
;   F6  = request stop (interrupts instantly, same as all prior micros)
;   Esc = exit the script
;
; TEST IT: use the same marker color you've been testing with. Move it
; to simulate a target moving (walk toward it), hide it to simulate
; depletion (should re-acquire), and fill your indicator slot to
; confirm the until-condition stops the loop cleanly.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

; ======= EDIT THESE FOR YOUR TEST =======================================
TARGET_COLOR := 0xFFFF00
COLOR_TOL    := 5
BLOCK_W      := 33
BLOCK_H      := 33

; How much of BLOCK_W/H must match as one solid block, in percent.
; 100 = strict full size (a 32x32 same-color decoy can never pass a
; 39x39 request). Lower slightly (e.g. 90) only if a real target's
; soft/anti-aliased edges make the strict match miss - F8-probe first.
VERIFY_PERCENT := 100

TRACK_RADIUS_PX := 220   ; narrowed search box half-size once a target is locked

STABLE_TICKS_REQUIRED := 3    ; consecutive within-tolerance ticks before "stable"
MOVE_TOLERANCE_PX     := 10   ; how much drift still counts as "the same spot"
MISSING_TICKS_TO_UNLOCK := 1  ; ported from TargetLock for fidelity (see header - unused by the control flow below, exactly as in real Woodcutting)

CLICK_COOLDOWN_MS       := 4000   ; re-click cadence once STABLE (tick-aligned)
WALK_RECLICK_TIMEOUT_MS := 9000   ; re-click cadence while NOT YET stable (still walking toward it)
CLICK_USE_CTRL := true

; Until-condition: the same inventory-full check as micro 09, reusing
; its confirmed layout. Indicator slot 28 matches v5's convention.
INV_FIRST_X := 2099, INV_FIRST_Y := 801
INV_COLS := 4, INV_ROWS := 7
INV_SLOT_W := 72, INV_SLOT_H := 64
INV_GAP_X := 12, INV_GAP_Y := 8
EMPTY_COLOR := 0x3F3629
EMPTY_TOL   := 30
INDICATOR_SLOT := 28

POLL_MS  := 300    ; tick-aligned loop interval
CHUNK_MS := 40
SETTLE_MS := 150
OVERALL_TIMEOUT_MS := 90000   ; safety failsafe - stop if nothing meets the until-condition this long
; ========================================================================

g_StopRequested := false

F5:: RunTrackAndClick()
F8:: ProbeColor()
F6:: {
    global g_StopRequested
    g_StopRequested := true
    LogLine("F6 pressed - stop requested")
}
Esc:: {
    LogLine("Esc pressed - exiting")
    ExitApp()
}

; Calibration probe (AutoHotkey.pdf's official method for determining
; color IDs: "Color IDs can be determined using Window Spy or via
; PixelGetColor"). Hover the target block, press F8: reports the TRUE
; on-screen color under the cursor, the per-channel difference from the
; configured TARGET_COLOR, and the minimum COLOR_TOL that would match.
; If the reported color differs from what you configured, the on-screen
; rendering is blended/shaded - use the REPORTED value as TARGET_COLOR.
ProbeColor() {
    MouseGetPos(&mx, &my)
    actual := PixelGetColor(mx, my)

    dR := Abs(((actual >> 16) & 0xFF) - ((TARGET_COLOR >> 16) & 0xFF))
    dG := Abs(((actual >> 8) & 0xFF) - ((TARGET_COLOR >> 8) & 0xFF))
    dB := Abs((actual & 0xFF) - (TARGET_COLOR & 0xFF))
    minTol := Max(dR, dG, dB)

    msg := "PROBE at " mx "," my ": actual=" HexColor(actual)
        . "  configured=" HexColor(TARGET_COLOR)
        . "  delta R/G/B=" dR "/" dG "/" dB
        . "  -> " (minTol <= COLOR_TOL
            ? "MATCHES at current tol " COLOR_TOL
            : "needs tol >= " minTol " (or set TARGET_COLOR := " HexColor(actual) ")")
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

RunTrackAndClick() {
    global g_StopRequested
    g_StopRequested := false

    LogLine("TrackAndClick started: color=" HexColor(TARGET_COLOR) " tol=" COLOR_TOL
        . " block=" BLOCK_W "x" BLOCK_H " trackRadius=" TRACK_RADIUS_PX
        . " indicatorSlot=" INDICATOR_SLOT " overallTimeout=" OVERALL_TIMEOUT_MS "ms")
    ToolTip("TrackAndClick running - F6 to stop", 20, 20)

    lock := TargetLock(STABLE_TICKS_REQUIRED, MOVE_TOLERANCE_PX, MISSING_TICKS_TO_UNLOCK)
    hasTarget := false
    targetX := 0, targetY := 0
    lastClickTime := 0
    t0 := A_TickCount

    try {
        loop {
            if (SlotFull(INDICATOR_SLOT)) {
                msg := "UNTIL-CONDITION MET: indicator slot " INDICATOR_SLOT " is full - stopping ("
                    . (A_TickCount - t0) " ms total)"
                ToolTip(msg, 20, 20)
                LogLine(msg)
                return
            }

            if ((A_TickCount - t0) > OVERALL_TIMEOUT_MS) {
                msg := "OVERALL TIMEOUT after " (A_TickCount - t0) " ms - stopping (safety failsafe, until-condition never met)"
                ToolTip(msg, 20, 20)
                LogLine(msg)
                return
            }

            if (!hasTarget) {
                ; Acquire mode: whole screen. The native solid-block
                ; search costs the same no matter how much of the color
                ; is elsewhere on screen, so no region limiting needed.
                found := FindFilledBlock(0, 0, A_ScreenWidth - 1, A_ScreenHeight - 1,
                    TARGET_COLOR, COLOR_TOL, BLOCK_W, BLOCK_H, &tx, &ty, VERIFY_PERCENT)
                if (found) {
                    hasTarget := true
                    targetX := tx, targetY := ty
                    lastClickTime := 0
                    lock.Reset()
                    LogLine("Acquired new target at " tx "," ty)
                } else {
                    LogLine("Acquire: not found")
                }
            } else {
                ; Track mode: narrowed box around the last known position.
                rx1 := Max(0, targetX - TRACK_RADIUS_PX)
                ry1 := Max(0, targetY - TRACK_RADIUS_PX)
                rx2 := Min(A_ScreenWidth - 1, targetX + TRACK_RADIUS_PX)
                ry2 := Min(A_ScreenHeight - 1, targetY + TRACK_RADIUS_PX)

                found := FindFilledBlock(rx1, ry1, rx2, ry2, TARGET_COLOR, COLOR_TOL,
                    BLOCK_W, BLOCK_H, &nx, &ny, VERIFY_PERCENT)
                lock.Observe(found, found ? nx : 0, found ? ny : 0, &outX, &outY)

                if (!found) {
                    LogLine("Target depleted or lost - re-acquiring")
                    hasTarget := false
                    targetX := 0, targetY := 0
                } else {
                    targetX := outX, targetY := outY

                    if (lock.IsStable()) {
                        if (lastClickTime == 0 || (A_TickCount - lastClickTime) > CLICK_COOLDOWN_MS) {
                            ClickAt(outX, outY, CLICK_USE_CTRL)
                            lastClickTime := A_TickCount
                            LogLine("Clicked STABLE target at " outX "," outY)
                        } else {
                            LogLine("Tracking stable target at " outX "," outY " (cooldown active)")
                        }
                    } else {
                        if (lastClickTime == 0 || (A_TickCount - lastClickTime) > WALK_RECLICK_TIMEOUT_MS) {
                            ClickAt(outX, outY, CLICK_USE_CTRL)
                            lastClickTime := A_TickCount
                            LogLine("Clicked initial/re-click target at " outX "," outY)
                        } else {
                            LogLine("Tracking not-yet-stable target at " outX "," outY)
                        }
                    }
                }
            }

            Pause(POLL_MS)
        }
    } catch BotStopped as e {
        msg := "STOPPED by F6 after " (A_TickCount - t0) " ms"
        ToolTip(msg, 20, 20)
        LogLine(msg)
    }
}

; ---------- target lock (verbatim port of v5 Detection\TargetLock.ahk) ----------

class TargetLock {
    __New(stableTicksRequired, moveTolerancePx, missingTicksToUnlock := 1) {
        this._stableTicksRequired := stableTicksRequired
        this._moveTolerancePx := moveTolerancePx
        this._missingTicksToUnlock := missingTicksToUnlock
        this._hasPosition := false
        this._lastX := 0
        this._lastY := 0
        this._stableTicks := 0
        this._missingTicks := 0
    }

    IsStable() => this._stableTicks >= this._stableTicksRequired

    IsLost() => this._missingTicks >= this._missingTicksToUnlock

    Observe(found, x, y, &outX, &outY) {
        if (!found) {
            this._missingTicks += 1
            outX := this._lastX
            outY := this._lastY
            return false
        }
        this._missingTicks := 0

        isStableTick := this._hasPosition
            && Abs(x - this._lastX) <= this._moveTolerancePx
            && Abs(y - this._lastY) <= this._moveTolerancePx

        this._stableTicks := isStableTick ? this._stableTicks + 1 : 0

        this._lastX := x
        this._lastY := y
        this._hasPosition := true

        outX := x
        outY := y
        return true
    }

    Reset() {
        this._hasPosition := false
        this._stableTicks := 0
        this._missingTicks := 0
    }
}

; ---------- click (universal, ctrl-toggleable - port of micro 04/05/08/11) ----------

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

; ---------- inventory until-condition (port of micro 09) ----------

SlotCenter(slotIndex, &x, &y) {
    total := INV_COLS * INV_ROWS
    if (slotIndex < 1 || slotIndex > total)
        throw ValueError("SlotCenter: slotIndex " slotIndex " out of range (1.." total ")")

    col := Mod(slotIndex - 1, INV_COLS)
    row := (slotIndex - 1) // INV_COLS

    cornerX := INV_FIRST_X + col * (INV_SLOT_W + INV_GAP_X)
    cornerY := INV_FIRST_Y + row * (INV_SLOT_H + INV_GAP_Y)

    x := cornerX + INV_SLOT_W // 2
    y := cornerY + INV_SLOT_H // 2
}

SlotFull(slotIndex) {
    static offsets := [[0, 0], [-14, -12], [14, -12], [0, 12]]

    SlotCenter(slotIndex, &cx, &cy)
    for off in offsets {
        current := PixelGetColor(cx + off[1], cy + off[2])
        if (!ColorClose(current, EMPTY_COLOR, EMPTY_TOL))
            return true
    }
    return false
}

; ---------- pixel helper (used by the SlotFull until-condition) ----------

ColorClose(c1, c2, tol) {
    return Abs(((c1 >> 16) & 0xFF) - ((c2 >> 16) & 0xFF)) <= tol
        && Abs(((c1 >> 8) & 0xFF) - ((c2 >> 8) & 0xFF)) <= tol
        && Abs((c1 & 0xFF) - (c2 & 0xFF)) <= tol
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

; ---------- interruptible wait (identical port of micro 07/08/10/11) ----------

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

; ---------- logging ----------

HexColor(c) {
    return Format("0x{:06X}", c)
}

LogLine(msg) {
    static logDir := A_ScriptDir "\..\logs"
    static logPath := logDir "\12-track-and-click.log"
    if (!DirExist(logDir))
        DirCreate(logDir)
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " [12-track-and-click] " msg "`n", logPath)
}

LogLine("Script loaded. F5=start loop  F8=probe color under cursor  F6=stop  Esc=exit. Target=" HexColor(TARGET_COLOR)
    . " IndicatorSlot=" INDICATOR_SLOT " VerifyPercent=" VERIFY_PERCENT)
ToolTip("micro 12 ready - F8 to probe a color, F5 to start the loop", 20, 20)
