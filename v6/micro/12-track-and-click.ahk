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
;         the per-channel delta vs EVERY color in TARGET_COLORS, and
;         the minimum tolerance that would match each - use this FIRST
;         whenever a new color "isn't found" (on-screen rendering often
;         blends/shades the configured pure hex)
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
; confirm the until-condition stops the loop cleanly. If two targets
; sit close enough that their highlight boxes visually merge, or if
; different trees/veins render in different overlay shades, add more
; entries to TARGET_COLORS (see config below) - every color in the
; list is searched every acquire attempt with EQUAL priority (none is
; favored by list order); track mode then locks onto whichever color
; actually matched, same as v5 Motherlode's light/dark vein pattern.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

; ======= EDIT THESE FOR YOUR TEST =======================================
; One or more candidate colors, ALL equal priority - none is favored by
; list order or position. Acquire searches EVERY entry, every attempt
; (v5 Motherlode's veinColorLight/veinColorDark pattern generalized to
; any count: the SAME conceptual target can render in different overlay
; shades depending on lighting/depth, or multiple distinct targets can
; use different marker colors). If more than one color matches in the
; same attempt, the one whose match would come first in a natural
; top-to-bottom/left-to-right scan wins - as if every color were
; searched in a single unified pass, NOT "whichever is listed first."
; Track mode then LOCKS onto whichever color actually matched and
; re-searches only that one from then on - exactly like v5's real
; _Acquire/_Track split, not a blend of every color at once.
TARGET_COLORS := [0x00FF00, 0x00B809]

COLOR_TOL    := 5
BLOCK_W      := 31
BLOCK_H      := 31

; How much of BLOCK_W/H must match as one solid block, in percent.
; 100 = strict full size (a 32x32 same-color decoy can never pass a
; 39x39 request). Lower slightly (e.g. 90) only if a real target's
; soft/anti-aliased edges make the strict match miss - F8-probe first.
VERIFY_PERCENT := 100

TRACK_RADIUS_PX := 220   ; narrowed search box half-size once a target is locked

; Max px a found match may be from the last known position and still be
; accepted as "the same target." The old candidate-loop FindFilledBlock
; steered its search toward a ref point when multiple same-color blocks
; existed; the native ImageSearch replacement has no such steering - it
; returns whatever match it finds first in the region, which can be a
; DIFFERENT same-colored tree if two are within TRACK_RADIUS_PX of each
; other. Without this gate, that wrong match gets silently adopted as
; the tracked target (looks like "switched to another vein while the
; original was still there"). Keep this well below TRACK_RADIUS_PX -
; legitimate drift (camera/perspective shift) is small; a jump this
; large means a different block, not the same one moving.
MAX_DRIFT_PX := 40

; Pacing below is Motherlode-tuned (v5 Bots\Motherlode\motherlode.ahk /
; auto-motherlode-v2.ini: mineStableTicks=2, clickCooldownMs=1500,
; walkReclickTimeoutMs=3000), NOT Woodcutting's slower tree-pace numbers
; (3/4000/9000) this micro originally shipped with - a real bot's own
; .ini picks whichever pace fits it in Stage 2, these are just this
; micro's calibration defaults. Still exact multiples of the 300ms
; tick-aligned poll grid (1500=5x300, 3000=10x300).
STABLE_TICKS_REQUIRED := 2    ; consecutive within-tolerance ticks before "stable"
MOVE_TOLERANCE_PX     := 10   ; how much drift still counts as "the same spot"
MISSING_TICKS_TO_UNLOCK := 1  ; ported from TargetLock for fidelity (see header - unused by the control flow below, exactly as in real Woodcutting)

CLICK_COOLDOWN_MS       := 1500   ; re-click cadence once STABLE (tick-aligned)
WALK_RECLICK_TIMEOUT_MS := 3000   ; re-click cadence while NOT YET stable (still walking toward it)
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
SETTLE_MS := 100
CTRL_HOLD_MS := 100   ; ctrl-click only: held between the click firing and Ctrl release -
                       ; NOT redundant with SETTLE_MS (see ClickAt comment) - do not remove
OVERALL_TIMEOUT_MS := 600000   ; safety failsafe - stop if nothing meets the until-condition this
                                ; long. 90s, then 5 min, were both too tight for slower trees
                                ; (yew etc. take a lot longer than 28 slots-worth of normal/
                                ; willow chops) - 10 min gives real chopping room while still
                                ; catching a genuinely stuck bot.
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
; on-screen color under the cursor, the per-channel difference from
; EVERY color in TARGET_COLORS, and the minimum tolerance each would
; need. If the reported color differs from what you configured, the
; on-screen rendering is blended/shaded - use the REPORTED value.
ProbeColor() {
    MouseGetPos(&mx, &my)
    actual := PixelGetColor(mx, my)

    msg := "PROBE at " mx "," my ": actual=" HexColor(actual)
    for i, configured in TARGET_COLORS
        msg .= (i = 1 ? "  " : "  |  ") ProbeAgainst(actual, "TARGET_COLORS[" i "]", configured)
    Say(msg)
}

; Formats one color's comparison for ProbeColor - shared so every
; entry in TARGET_COLORS reads identically.
ProbeAgainst(actual, label, configured) {
    dR := Abs(((actual >> 16) & 0xFF) - ((configured >> 16) & 0xFF))
    dG := Abs(((actual >> 8) & 0xFF) - ((configured >> 8) & 0xFF))
    dB := Abs((actual & 0xFF) - (configured & 0xFF))
    minTol := Max(dR, dG, dB)

    return label "=" HexColor(configured) " delta R/G/B=" dR "/" dG "/" dB
        . " -> " (minTol <= COLOR_TOL
            ? "MATCHES at current tol " COLOR_TOL
            : "needs tol >= " minTol " (or set " label " := " HexColor(actual) ")")
}

RunTrackAndClick() {
    global g_StopRequested
    g_StopRequested := false

    colorsMsg := ""
    for i, c in TARGET_COLORS
        colorsMsg .= (i = 1 ? "" : "/") HexColor(c)
    LogLine("TrackAndClick started: colors=" colorsMsg " tol=" COLOR_TOL
        . " block=" BLOCK_W "x" BLOCK_H " trackRadius=" TRACK_RADIUS_PX
        . " indicatorSlot=" INDICATOR_SLOT " overallTimeout=" OVERALL_TIMEOUT_MS "ms")
    ToolTip("TrackAndClick running - F6 to stop", 20, 20)

    lock := TargetLock(STABLE_TICKS_REQUIRED, MOVE_TOLERANCE_PX, MISSING_TICKS_TO_UNLOCK)
    hasTarget := false
    targetX := 0, targetY := 0
    lockedColor := TARGET_COLORS[1]
    lastClickTime := 0
    t0 := A_TickCount

    try {
        loop {
            if (SlotFull(INDICATOR_SLOT)) {
                Say("UNTIL-CONDITION MET: indicator slot " INDICATOR_SLOT " is full - stopping ("
                    . (A_TickCount - t0) " ms total)")
                return
            }

            if ((A_TickCount - t0) > OVERALL_TIMEOUT_MS) {
                Say("OVERALL TIMEOUT after " (A_TickCount - t0) " ms - stopping (safety failsafe, until-condition never met)")
                return
            }

            if (!hasTarget) {
                ; Acquire mode: whole screen, EVERY color in
                ; TARGET_COLORS searched every attempt - no color is
                ; favored by list order. If more than one matches, the
                ; one whose match would come first in a natural
                ; top-to-bottom/left-to-right scan wins (smallest y,
                ; then smallest x) - as if every color were searched in
                ; one unified pass. The native solid-block search costs
                ; the same no matter how much of a color is elsewhere on
                ; screen, so no region limiting needed either way.
                tSearch := A_TickCount
                found := false
                for color in TARGET_COLORS {
                    if (FindFilledBlock(0, 0, A_ScreenWidth - 1, A_ScreenHeight - 1,
                        color, COLOR_TOL, BLOCK_W, BLOCK_H, &cx, &cy, VERIFY_PERCENT)) {
                        if (!found || cy < ty || (cy = ty && cx < tx)) {
                            found := true
                            tx := cx, ty := cy, foundColor := color
                        }
                    }
                }
                searchMs := A_TickCount - tSearch
                if (found) {
                    hasTarget := true
                    targetX := tx, targetY := ty
                    lockedColor := foundColor
                    lastClickTime := 0
                    lock.Reset()
                    Say("Acquired new target at " tx "," ty " (" HexColor(lockedColor) ") in " searchMs " ms")
                } else {
                    Say("Acquire: not found (searched " searchMs " ms)")
                }
            } else {
                ; Track mode: narrowed box around the last known position.
                rx1 := Max(0, targetX - TRACK_RADIUS_PX)
                ry1 := Max(0, targetY - TRACK_RADIUS_PX)
                rx2 := Min(A_ScreenWidth - 1, targetX + TRACK_RADIUS_PX)
                ry2 := Min(A_ScreenHeight - 1, targetY + TRACK_RADIUS_PX)

                ; Locked to whichever color acquire actually matched
                ; (lockedColor) - track never re-checks the other
                ; candidate color, exactly like v5 Motherlode's _Track.
                tSearch := A_TickCount
                found := FindFilledBlock(rx1, ry1, rx2, ry2, lockedColor, COLOR_TOL,
                    BLOCK_W, BLOCK_H, &nx, &ny, VERIFY_PERCENT)
                searchMs := A_TickCount - tSearch

                if (found) {
                    drift := Max(Abs(nx - targetX), Abs(ny - targetY))
                    if (drift > MAX_DRIFT_PX) {
                        Say("Track: found " HexColor(lockedColor) " block at " nx "," ny " but " drift
                            "px from last position " targetX "," targetY " (max drift " MAX_DRIFT_PX
                            ") - likely a DIFFERENT block, rejecting")
                        found := false
                    }
                }

                ; HARD RULE: never concede depletion/switch targets while
                ; the exact point we've been clicking is still the target
                ; color. A miss this tick (nothing in the box, or a
                ; rejected too-far match) can just be transient occlusion
                ; (xp-drop text, the mouse cursor, chat) - the tree hasn't
                ; actually gone anywhere. Only when THIS anchor pixel
                ; itself stops matching do we treat the target as truly
                ; gone and allow a fresh (unbiased) whole-screen re-acquire.
                if (!found && IsColorAt(targetX, targetY, lockedColor, COLOR_TOL)) {
                    Say("Track: search missed this tick, but anchor point " targetX "," targetY
                        " is still " HexColor(lockedColor) " - holding current target, not switching")
                    found := true
                    nx := targetX, ny := targetY
                }

                lock.Observe(found, found ? nx : 0, found ? ny : 0, &outX, &outY)

                if (!found) {
                    Say("Target depleted or lost - re-acquiring (searched " searchMs " ms)")
                    hasTarget := false
                    targetX := 0, targetY := 0
                } else {
                    targetX := outX, targetY := outY

                    if (lock.IsStable()) {
                        if (lastClickTime == 0 || (A_TickCount - lastClickTime) > CLICK_COOLDOWN_MS) {
                            ClickAt(outX, outY, CLICK_USE_CTRL)
                            lastClickTime := A_TickCount
                            Say("Clicked STABLE target at " outX "," outY " (search " searchMs " ms)")
                        } else {
                            Say("Tracking stable target at " outX "," outY " (cooldown active, search " searchMs " ms)")
                        }
                    } else {
                        if (lastClickTime == 0 || (A_TickCount - lastClickTime) > WALK_RECLICK_TIMEOUT_MS) {
                            ClickAt(outX, outY, CLICK_USE_CTRL)
                            lastClickTime := A_TickCount
                            Say("Clicked initial/re-click target at " outX "," outY " (search " searchMs " ms)")
                        } else {
                            Say("Tracking not-yet-stable target at " outX "," outY " (search " searchMs " ms)")
                        }
                    }
                }
            }

            Pause(POLL_MS)
        }
    } catch BotStopped as e {
        Say("STOPPED by F6 after " (A_TickCount - t0) " ms")
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

; ---------- pixel helpers (SlotFull's until-condition + the track-mode anchor check) ----------

ColorClose(c1, c2, tol) {
    return Abs(((c1 >> 16) & 0xFF) - ((c2 >> 16) & 0xFF)) <= tol
        && Abs(((c1 >> 8) & 0xFF) - ((c2 >> 8) & 0xFF)) <= tol
        && Abs((c1 & 0xFF) - (c2 & 0xFF)) <= tol
}

IsColorAt(x, y, color, tol) {
    return ColorClose(PixelGetColor(x, y), color, tol)
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

; ---------- logging ----------

HexColor(c) {
    return Format("0x{:06X}", c)
}

; Every per-tick status (acquire/track/click/hold/stop) goes through
; this, not LogLine directly - keeps the on-screen ToolTip showing
; exactly what the log just recorded (which coordinate it's mining,
; searched/clicked/held/re-acquired), matching the live status readout
; a real Motherlode-style bot shows on screen, not just in the log file.
Say(msg) {
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

LogLine(msg) {
    static logDir := A_ScriptDir "\..\logs"
    static logPath := logDir "\12-track-and-click.log"
    if (!DirExist(logDir))
        DirCreate(logDir)
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " [12-track-and-click] " msg "`n", logPath)
}

startColorsMsg := ""
for i, c in TARGET_COLORS
    startColorsMsg .= (i = 1 ? "" : "/") HexColor(c)
LogLine("Script loaded. F5=start loop  F8=probe color under cursor  F6=stop  Esc=exit. Targets=" startColorsMsg
    . " IndicatorSlot=" INDICATOR_SLOT " VerifyPercent=" VERIFY_PERCENT)
ToolTip("micro 12 ready - F8 to probe a color, F5 to start the loop", 20, 20)
