; ============================================================
; v6 micro 10 - pixel-box snapshot + change detection ("watch-box")
;
; Snapshots every pixel in a small box, then later tells you whether
; ANY of them changed - used to confirm something actually happened
; (an item landed in a slot, a counter ticked up) independent of any
; full/empty color check. This is the building block micro 11 (the
; Mark-of-Grace pickup pattern) will poll through WaitUntil.
;
; Algorithm ported from v5 Interfaces\SlotSignature.ahk (Snapshot /
; HasChanged), but STRIDED rather than exhaustive: v5 sampled every
; single pixel, which is fine for the tiny boxes it targeted but costs
; ~5-7ms per PixelGetColor call (same fixed per-call overhead documented
; in Detection\ColorSearch.ahk) - an 832-pixel box (52x16) took ~6
; SECONDS to snapshot exhaustively (measured live in this project's own
; test log). Sampling ~TARGET_SAMPLES points instead of every pixel
; (same idea as ColorSearch's sampleRate/rowStep) keeps that fast - while
; still reliably catching a digit/counter change, since a changed glyph
; alters many neighboring pixels, not just one isolated one.
;
; The stride is DERIVED from box size + TARGET_SAMPLES, not a flat
; constant - a stride tuned for a small box (a thin counter) silently
; got far too slow when reused on a bigger box (a whole 72x64 inventory
; slot: 288 samples at stride 4 took ~2 SECONDS, also measured live) -
; deriving it means any box size costs about the same.
;
; WHAT IT DOES
;   F7  = trace the box's outline with the mouse (4 corners) - use this
;         FIRST to visually confirm the box actually covers the right
;         area before trusting F5
;   F5  = snapshot the box now, then wait (interruptible, with
;         timeout) until any pixel in it changes
;   F6  = request stop (interrupts the wait, same as micros 07/08)
;   Esc = exit the script
;
; The box to watch is resolved ONE OF TWO WAYS (see SLOT_INDEX below):
;   - SLOT_INDEX set (1-28): watches that WHOLE inventory slot (its
;     full corner+size, via SlotBox - same corner math as micro 09's
;     SlotCenter) - e.g. "did an item appear in slot 2".
;   - SLOT_INDEX left "": watches a CUSTOM box at BOX_OFFSET_X/Y +
;     BOX_W/H relative to the inventory block's own top-left corner
;     (slot 1's corner, confirmed in micro 09 as 2099,801) - for things
;     that aren't a whole slot, like a counter (default: the 52x16
;     counter area at offset 2,0).
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

; ======= EDIT THESE FOR YOUR TEST =======================================
; Confirmed inventory layout (micro 09) - needed either way, since
; SlotBox() below computes a slot's box from these same numbers.
INV_FIRST_X := 2099, INV_FIRST_Y := 801
INV_COLS := 4, INV_ROWS := 7
INV_SLOT_W := 72, INV_SLOT_H := 64
INV_GAP_X := 12, INV_GAP_Y := 8

; Set SLOT_INDEX to watch a WHOLE inventory slot (1-28) - e.g. "did an
; item appear in slot 2". Leave it "" to instead watch a CUSTOM box via
; BOX_OFFSET_X/Y + BOX_W/H below (e.g. a counter that isn't a whole
; slot, like the Mark of Grace count).
SLOT_INDEX := "2"

; Custom box (only used when SLOT_INDEX is "") - offset from the
; inventory block's own top-left corner (slot 1's corner).
BOX_OFFSET_X := 2
BOX_OFFSET_Y := 0
BOX_W := 52
BOX_H := 16

CHANGE_TOL := 10   ; per-channel tolerance before a pixel counts as "changed"

; Sample budget, NOT a fixed stride: stride is computed from box size so
; a big box (a whole slot) and a small box (a thin counter) both cost
; about the same regardless of their raw pixel area. See TakeSnapshot.
TARGET_SAMPLES := 50

WAIT_TIMEOUT_MS := 15000
POLL_MS         := 300     ; tick-aligned poll interval
CHUNK_MS        := 40
; ========================================================================

; Resolve the box to watch, once at load time: a whole slot (SlotBox,
; ported from micro 09's SlotCenter corner math) or the custom offset box.
if (SLOT_INDEX != "")
    SlotBox(SLOT_INDEX, &BOX_X, &BOX_Y, &BOX_W, &BOX_H)
else {
    BOX_X := INV_FIRST_X + BOX_OFFSET_X
    BOX_Y := INV_FIRST_Y + BOX_OFFSET_Y
}

g_StopRequested := false
g_Snapshot := ""

F5:: RunWatch()
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

; Moves the mouse around the box's 4 corners in sequence so you can
; visually confirm it lines up with the real counter area before
; trusting F5 - traces top-left -> top-right -> bottom-right ->
; bottom-left -> back to top-left, pausing briefly at each corner.
TraceBoxOutline() {
    corners := [
        [BOX_X, BOX_Y],
        [BOX_X + BOX_W, BOX_Y],
        [BOX_X + BOX_W, BOX_Y + BOX_H],
        [BOX_X, BOX_Y + BOX_H],
        [BOX_X, BOX_Y]
    ]
    LogLine("F7: tracing box outline " BOX_X "," BOX_Y " " BOX_W "x" BOX_H)
    ToolTip("Tracing box outline...", 20, 20)
    for c in corners {
        MouseMove(c[1], c[2], 20)
        Sleep(400)
    }
    ToolTip("Box: " BOX_X "," BOX_Y " to " (BOX_X + BOX_W) "," (BOX_Y + BOX_H), 20, 20)
}

RunWatch() {
    global g_StopRequested, g_Snapshot
    g_StopRequested := false

    LogLine("Watch started: box=" BOX_X "," BOX_Y " " BOX_W "x" BOX_H " tol=" CHANGE_TOL
        . " timeout=" WAIT_TIMEOUT_MS "ms")

    t0Snap := A_TickCount
    g_Snapshot := TakeSnapshot(BOX_X, BOX_Y, BOX_W, BOX_H, TARGET_SAMPLES)
    LogLine("Snapshot taken (" g_Snapshot.colors.Length " samples, stride "
        . g_Snapshot.strideX "x" g_Snapshot.strideY ") in " (A_TickCount - t0Snap) " ms")
    ToolTip("Snapshot taken - waiting for change (F6 to cancel)", 20, 20)

    t0 := A_TickCount
    try {
        changed := WaitUntil(BoxChanged, WAIT_TIMEOUT_MS, POLL_MS)
    } catch BotStopped as e {
        elapsedMs := A_TickCount - t0
        msg := "STOPPED by F6 after " elapsedMs " ms waiting"
        ToolTip(msg, 20, 20)
        LogLine(msg)
        return
    }

    elapsedMs := A_TickCount - t0
    msg := changed ? "CHANGED after " elapsedMs " ms" : "TIMED OUT after " elapsedMs " ms - no change detected"
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

BoxChanged() {
    global g_Snapshot
    t0Check := A_TickCount
    changed := HasChanged(g_Snapshot, BOX_X, BOX_Y, CHANGE_TOL)
    LogLine("BoxChanged: " (changed ? "CHANGED" : "unchanged") " (" (A_TickCount - t0Check) " ms)")
    return changed
}

; ---------- slot addressing (corner math ported from micro 09's SlotCenter) ----------

; 1-based, row-major slot index -> that slot's top-left corner + size
; (a watch-box needs a corner+size, not a center point like micro 09's
; SlotCenter - same math, just not shifted to the middle).
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

; ---------- watch-box (v5 SlotSignature port, strided) ----------

; Samples roughly targetSamples points spread evenly across a w x h box
; whose top-left corner is x,y - NOT every pixel (see header comment for
; why). The stride is DERIVED from box size + targetSamples, not fixed,
; so a big box (a whole slot) and a small box (a thin counter) both cost
; about the same regardless of raw pixel area - a flat stride tuned for
; one box size silently gets far too slow (or too sparse) on another.
; Returns one snapshot object bundling the samples with the stride/size
; used to take them, so HasChanged always re-samples at the exact same
; points - a caller can't accidentally pass a mismatched stride.
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

; True if any sampled point now differs from the snapshot's baseline.
; x,y: the box's CURRENT top-left corner (usually unchanged from the
; snapshot, but kept separate in case the box legitimately moves).
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

; ---------- interruptible wait (identical port of micro 07/08) ----------

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
    static logPath := logDir "\10-watch-box.log"
    if (!DirExist(logDir))
        DirCreate(logDir)
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " [10-watch-box] " msg "`n", logPath)
}

LogLine("Script loaded. F5=snapshot+watch  F6=stop  Esc=exit. Box=" BOX_X "," BOX_Y " " BOX_W "x" BOX_H)
ToolTip("micro 10 ready - F5 to snapshot the box and watch for a change", 20, 20)
