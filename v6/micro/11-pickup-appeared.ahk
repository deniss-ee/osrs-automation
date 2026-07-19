; ============================================================
; v6 micro 11 - pickup-appeared (the Mark of Grace pattern)
;
; The first-class building block the user explicitly asked for:
; "find something that just appeared -> click it -> confirm the
; pickup actually landed via a pixel-box diff" - not just "did we
; click", but "did the game state actually change afterward".
;
; Composes everything confirmed so far:
;   - micro 06's PNG search (find the appeared item)
;   - micro 10's watch-box (snapshot BEFORE the click, confirm AFTER)
;   - micro 04/08's settled click (plain or Ctrl-held)
;   - micro 07's interruptible Pause/WaitUntil/BotStopped (both the
;     "wait for it to appear" and "wait for pickup to confirm" phases
;     are interruptible and time-bounded)
;
; Ported from v5 Bots\Agility\agility.ahk's Mark-of-Grace flow
; (lines ~208-264), de-blocked: v5 ran this as a plain nested loop
; with plain Waiter.After calls inside one engine tick, which is
; exactly the kind of blocking loop that defeated its own F6 stop -
; here the whole thing goes through Pause, so F6 always works.
;
; ORDER MATTERS: snapshot the confirm box BEFORE clicking, not after -
; you need the "before" state to detect a change caused by the click.
;
; WHAT IT DOES
;   F5  = wait for the image to appear (timeout) -> snapshot confirm
;         box -> click the found item -> wait for the box to change
;         (timeout) -> report which of the 4 outcomes happened:
;         confirmed / clicked-but-not-confirmed / never-appeared / stopped
;   F7  = trace the confirm box's outline (same as micro 10) - use
;         this first to double check the box still lines up
;   F6  = request stop (interrupts EITHER wait)
;   Esc = exit the script
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

; ======= EDIT THESE FOR YOUR TEST =======================================
IMAGE_PATH := A_ScriptDir "\..\img\air-rune.png"
IMAGE_W    := 78   ; measured from the PNG's own IHDR
IMAGE_H    := 16
IMAGE_TOL  := 5
TRANS_COLOR := "0x00FF00"   ; background color to treat as see-through ("" to disable)

REGION_X1 := 0, REGION_Y1 := 0, REGION_X2 := 2559, REGION_Y2 := 1439
APPEAR_TIMEOUT_MS := 15000   ; give up if the item never appears

CLICK_OFFSET_X := 0   ; offset from the found image's CENTER to the actual
CLICK_OFFSET_Y := 4   ; click point (v5's graceClickOffsetY equivalent - tune if
                       ; the image anchor's center isn't quite the clickable spot)
CLICK_USE_CTRL := true

; Confirmed inventory layout (micro 09) - needed either way, since
; SlotBox() below computes a slot's box from these same numbers.
INV_FIRST_X := 2099, INV_FIRST_Y := 801
INV_COLS := 4, INV_ROWS := 7
INV_SLOT_W := 72, INV_SLOT_H := 64
INV_GAP_X := 12, INV_GAP_Y := 8

; Confirm box - set SLOT_INDEX to watch a WHOLE inventory slot (1-28)
; instead of a custom box. Leave it "" to use BOX_OFFSET_X/Y + BOX_W/H
; below (same defaults as micro 10: the 52x16 counter area at offset
; 2,0 from the inventory block's top-left/slot-1 corner).
SLOT_INDEX := ""
BOX_OFFSET_X := 2, BOX_OFFSET_Y := 0
BOX_W := 52, BOX_H := 16
CHANGE_TOL := 10

; Sample budget, NOT a fixed stride - see micro 10's TakeSnapshot for why
; (a flat stride tuned for a small box gets far too slow on a big one).
TARGET_SAMPLES := 50

CONFIRM_TIMEOUT_MS := 8000   ; give up waiting for the pickup to register
POLL_MS   := 300             ; tick-aligned poll interval (both waits)
CHUNK_MS  := 40
SETTLE_MS := 150
; ========================================================================

; Resolve the confirm box, once at load time (same pattern as micro 10).
if (SLOT_INDEX != "")
    SlotBox(SLOT_INDEX, &BOX_X, &BOX_Y, &BOX_W, &BOX_H)
else {
    BOX_X := INV_FIRST_X + BOX_OFFSET_X
    BOX_Y := INV_FIRST_Y + BOX_OFFSET_Y
}

g_StopRequested := false
g_FoundX := 0
g_FoundY := 0
g_Snapshot := ""

F5:: RunPickup()
F7:: TraceBoxOutline()
F6:: {
    global g_StopRequested
    g_StopRequested := true
    LogLine("F6 pressed - stop requested")
}
Esc:: {
    LogLine("Esc pressed - exiting")
    ExitApp()
}

TraceBoxOutline() {
    corners := [
        [BOX_X, BOX_Y], [BOX_X + BOX_W, BOX_Y],
        [BOX_X + BOX_W, BOX_Y + BOX_H], [BOX_X, BOX_Y + BOX_H], [BOX_X, BOX_Y]
    ]
    LogLine("F7: tracing confirm box outline " BOX_X "," BOX_Y " " BOX_W "x" BOX_H)
    ToolTip("Tracing confirm box outline...", 20, 20)
    for c in corners {
        MouseMove(c[1], c[2], 20)
        Sleep(400)
    }
}

RunPickup() {
    global g_StopRequested, g_FoundX, g_FoundY, g_Snapshot
    g_StopRequested := false

    LogLine("Pickup flow started: image=" IMAGE_PATH " appearTimeout=" APPEAR_TIMEOUT_MS "ms"
        . " confirmBox=" BOX_X "," BOX_Y " " BOX_W "x" BOX_H " confirmTimeout=" CONFIRM_TIMEOUT_MS "ms")
    ToolTip("Waiting for item to appear (F6 to cancel)...", 20, 20)

    t0 := A_TickCount
    try {
        appeared := WaitUntil(ImageAppeared, APPEAR_TIMEOUT_MS, POLL_MS)
    } catch BotStopped as e {
        msg := "STOPPED by F6 after " (A_TickCount - t0) " ms - waiting for appearance"
        ToolTip(msg, 20, 20)
        LogLine(msg)
        return
    }

    if (!appeared) {
        msg := "NEVER APPEARED after " (A_TickCount - t0) " ms - giving up"
        ToolTip(msg, 20, 20)
        LogLine(msg)
        return
    }

    clickX := g_FoundX + CLICK_OFFSET_X
    clickY := g_FoundY + CLICK_OFFSET_Y
    LogLine("Appeared at " g_FoundX "," g_FoundY " after " (A_TickCount - t0) " ms - snapshotting confirm box BEFORE click")

    ; Snapshot BEFORE the click - we need the "before" state to detect
    ; a change caused by the click, not just any change.
    g_Snapshot := TakeSnapshot(BOX_X, BOX_Y, BOX_W, BOX_H, TARGET_SAMPLES)

    ToolTip("Clicking item at " clickX "," clickY "...", 20, 20)
    ClickAt(clickX, clickY, CLICK_USE_CTRL)
    LogLine("Clicked at " clickX "," clickY . (CLICK_USE_CTRL ? " (ctrl/force-run)" : "") " - waiting for pickup confirmation")

    t1 := A_TickCount
    try {
        confirmed := WaitUntil(BoxChanged, CONFIRM_TIMEOUT_MS, POLL_MS)
    } catch BotStopped as e {
        msg := "STOPPED by F6 after click, " (A_TickCount - t1) " ms into confirm wait - pickup NOT confirmed"
        ToolTip(msg, 20, 20)
        LogLine(msg)
        return
    }

    confirmMs := A_TickCount - t1
    totalMs := A_TickCount - t0
    if (confirmed) {
        msg := "PICKUP CONFIRMED (" confirmMs " ms after click, " totalMs " ms total)"
    } else {
        msg := "CLICKED but NOT CONFIRMED - box never changed within " CONFIRM_TIMEOUT_MS "ms (item may be unreachable, or click missed)"
    }
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

; Condition passed to the first WaitUntil - true the instant the image
; is found anywhere in the search region. Stores the found point.
ImageAppeared() {
    global g_FoundX, g_FoundY
    try {
        found := ImageSearch(&foundX, &foundY, REGION_X1, REGION_Y1,
            REGION_X2, REGION_Y2, ImagePattern(IMAGE_PATH, IMAGE_TOL, TRANS_COLOR))
    } catch as exc {
        LogLine("ImageAppeared: ERROR " exc.Message)
        return false
    }
    if (found) {
        g_FoundX := foundX + IMAGE_W // 2
        g_FoundY := foundY + IMAGE_H // 2
        LogLine("ImageAppeared: found at " g_FoundX "," g_FoundY)
        return true
    }
    LogLine("ImageAppeared: not yet visible")
    return false
}

; Condition passed to the second WaitUntil - true the instant the
; confirm box differs from the pre-click snapshot.
BoxChanged() {
    global g_Snapshot
    changed := HasChanged(g_Snapshot, BOX_X, BOX_Y, CHANGE_TOL)
    LogLine("BoxChanged: " (changed ? "CHANGED" : "unchanged"))
    return changed
}

; ---------- image search pattern (universal - port of micro 06) ----------

; Builds the "*tol *TransColor path" ImageSearch pattern string.
; transColor := "" omits the *Trans option entirely.
ImagePattern(path, tol, transColor := "") {
    pattern := "*" tol
    if (transColor != "")
        pattern .= " *Trans" transColor
    return pattern " " path
}

; ---------- click (universal, ctrl-toggleable - port of micro 04/08) ----------

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

; ---------- slot addressing (corner math ported from micro 09/10) ----------

; 1-based, row-major slot index -> that slot's top-left corner + size.
SlotBox(slotIndex, &x, &y, &w, &h) {
    total := INV_COLS * INV_ROWS
    if (slotIndex < 1 || slotIndex > total)
        throw ValueError("SlotBox: slotIndex " slotIndex " out of range (1.." total ")")

    col := Mod(slotIndex - 1, INV_COLS)
    row := (slotIndex - 1) // INV_COLS

    x := INV_FIRST_X + col * (INV_SLOT_W + INV_GAP_X)
    y := INV_FIRST_Y + row * (INV_SLOT_H + INV_GAP_Y)
    w := INV_SLOT_W
    h := INV_SLOT_H
}

; ---------- watch-box (strided port of micro 10) ----------

TakeSnapshot(x, y, w, h, targetSamples := 50) {
    scale := Sqrt(w * h / targetSamples)
    strideX := Max(1, Round(scale))
    strideY := Max(1, Round(scale))

    colors := []
    yy := 0
    while (yy < h) {
        xx := 0
        while (xx < w) {
            colors.Push(PixelGetColor(x + xx, y + yy))
            xx += strideX
        }
        yy += strideY
    }
    return {colors: colors, w: w, h: h, strideX: strideX, strideY: strideY}
}

HasChanged(snapshot, x, y, tol) {
    idx := 1
    yy := 0
    while (yy < snapshot.h) {
        xx := 0
        while (xx < snapshot.w) {
            current := PixelGetColor(x + xx, y + yy)
            if (!ColorClose(current, snapshot.colors[idx], tol))
                return true
            idx += 1
            xx += snapshot.strideX
        }
        yy += snapshot.strideY
    }
    return false
}

ColorClose(c1, c2, tol) {
    return Abs(((c1 >> 16) & 0xFF) - ((c2 >> 16) & 0xFF)) <= tol
        && Abs(((c1 >> 8) & 0xFF) - ((c2 >> 8) & 0xFF)) <= tol
        && Abs((c1 & 0xFF) - (c2 & 0xFF)) <= tol
}

; ---------- interruptible wait (identical port of micro 07/08/10) ----------

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

; ---------- logging ----------

LogLine(msg) {
    static logDir := A_ScriptDir "\..\logs"
    static logPath := logDir "\11-pickup-appeared.log"
    if (!DirExist(logDir))
        DirCreate(logDir)
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " [11-pickup-appeared] " msg "`n", logPath)
}

LogLine("Script loaded. F5=run pickup flow  F7=trace confirm box  F6=stop  Esc=exit")
ToolTip("micro 11 ready - F7 to check confirm box, F5 to run the pickup flow", 20, 20)
