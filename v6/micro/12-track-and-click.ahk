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
BLOCK_W      := 39
BLOCK_H      := 39
MAX_ATTEMPTS := 60

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
F6:: {
    global g_StopRequested
    g_StopRequested := true
    LogLine("F6 pressed - stop requested")
}
Esc:: {
    LogLine("Esc pressed - exiting")
    ExitApp()
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
    screenX2 := A_ScreenWidth - 1
    screenY2 := A_ScreenHeight - 1

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
                ; Acquire mode: whole-screen search, no target locked yet.
                found := FindFilledBlock(0, 0, screenX2, screenY2, TARGET_COLOR, COLOR_TOL,
                    BLOCK_W, BLOCK_H, &tx, &ty, , , MAX_ATTEMPTS)
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
                ; Track mode: narrowed box around the last known position,
                ; steered toward it (refX/refY) for a fast re-find.
                rx1 := Max(0, targetX - TRACK_RADIUS_PX)
                ry1 := Max(0, targetY - TRACK_RADIUS_PX)
                rx2 := Min(screenX2, targetX + TRACK_RADIUS_PX)
                ry2 := Min(screenY2, targetY + TRACK_RADIUS_PX)

                found := FindFilledBlock(rx1, ry1, rx2, ry2, TARGET_COLOR, COLOR_TOL,
                    BLOCK_W, BLOCK_H, &nx, &ny, targetX, targetY, MAX_ATTEMPTS)
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

; ---------- detection (identical port to micro 01-03/05/08/11) ----------

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

LogLine("Script loaded. F5=start loop  F6=stop  Esc=exit. Target=" HexColor(TARGET_COLOR)
    . " IndicatorSlot=" INDICATOR_SLOT)
ToolTip("micro 12 ready - F5 to start acquire/track/depleted loop", 20, 20)
