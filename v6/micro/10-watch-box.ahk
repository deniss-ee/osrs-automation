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
; test log). Sampling every STRIDE_Xth column / STRIDE_Yth row instead
; (same idea as ColorSearch's sampleRate/rowStep) cuts an 832-pixel box
; to ~52 samples - fast enough to poll every tick - while still reliably
; catching a digit/counter change, since a changed glyph alters many
; neighboring pixels, not just one isolated one.
;
; WHAT IT DOES
;   F7  = trace the box's outline with the mouse (4 corners) - use this
;         FIRST to visually confirm BOX_X/Y/W/H actually covers the
;         counter area before trusting F5
;   F5  = snapshot the box now, then wait (interruptible, with
;         timeout) until any pixel in it changes
;   F6  = request stop (interrupts the wait, same as micros 07/08)
;   Esc = exit the script
;
; Default box = a numeric counter area (52x16px) at offset (x=2, y=0)
; relative to the inventory block's own top-left corner. ASSUMPTION:
; "inventory block top-left" = slot 1's top-left corner as confirmed in
; micro 09 (2099,801) - if your counter isn't actually there, use F7
; below to trace the box's outline with the mouse and correct BOX_X/Y.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

; ======= EDIT THESE FOR YOUR TEST =======================================
INV_BLOCK_X := 2099   ; inventory block's top-left corner (micro 09's confirmed slot-1 corner)
INV_BLOCK_Y := 801

BOX_OFFSET_X := 2     ; the counter box's offset from the inventory block's corner
BOX_OFFSET_Y := 0
BOX_W := 52
BOX_H := 16

BOX_X := INV_BLOCK_X + BOX_OFFSET_X   ; top-left corner of the box to watch
BOX_Y := INV_BLOCK_Y + BOX_OFFSET_Y
CHANGE_TOL := 10   ; per-channel tolerance before a pixel counts as "changed"

STRIDE_X := 4   ; sample every STRIDE_Xth column instead of every column
STRIDE_Y := 4   ; sample every STRIDE_Yth row instead of every row

WAIT_TIMEOUT_MS := 15000
POLL_MS         := 300     ; tick-aligned poll interval
CHUNK_MS        := 40
; ========================================================================

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
    g_Snapshot := TakeSnapshot(BOX_X, BOX_Y, BOX_W, BOX_H, STRIDE_X, STRIDE_Y)
    LogLine("Snapshot taken (" g_Snapshot.colors.Length " samples, stride " STRIDE_X "x" STRIDE_Y
        . ") in " (A_TickCount - t0Snap) " ms")
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

; ---------- watch-box (v5 SlotSignature port, strided) ----------

; Samples every STRIDE_Xth column / STRIDE_Yth row of a w x h box whose
; top-left corner is x,y - NOT every pixel (see header comment for why).
; Returns one snapshot object bundling the samples with the stride/size
; used to take them, so HasChanged always re-samples at the exact same
; points - a caller can't accidentally pass a mismatched stride.
TakeSnapshot(x, y, w, h, strideX := 4, strideY := 4) {
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
