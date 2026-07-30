; ============================================================
; v6 micro 10 - pixel-box snapshot + change detection ("watch-box")
;
; Snapshots every pixel in a small box, then later tells you whether
; ANY of them changed - used to confirm something actually happened
; (an item landed in a slot, a counter ticked up) independent of any
; full/empty color check. This is the building block micro 11 (the
; Mark-of-Grace pickup pattern) polls through WaitUntil.
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
; The watched box is ALWAYS BOX_W x BOX_H, offset by BOX_OFFSET_X/Y from
; a corner - SLOT_INDEX only picks WHICH corner:
;   - SLOT_INDEX left "": offset from the inventory block's own
;     top-left corner (slot 1's corner) - the default, for a counter
;     near slot 1 (e.g. the 52x16 Mark of Grace count area at offset 2,0).
;   - SLOT_INDEX set (1-28): offset from THAT slot's corner instead
;     (Lib\Inv.ahk's SlotCorner) - e.g. the same counter, but watched
;     near slot 2 instead of slot 1. Setting SLOT_INDEX to 1 must
;     therefore give the EXACT same box as leaving it "" - it does NOT
;     switch to watching the whole 72x64 slot.
;
; TakeSnapshot/HasChanged (Lib\Inv.ahk), SlotCorner (Lib\Inv.ahk), and
; Pause/WaitUntil/BotStopped (Lib\Core.ahk) - all promoted here after
; in-game confirmation during Stage 1.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v6.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "10-watch-box"

; ======= EDIT THESE FOR YOUR TEST =======================================
; Set SLOT_INDEX to offset the box below from a DIFFERENT slot's corner
; instead of slot 1's - e.g. watching the same counter but positioned
; near slot 2 instead of slot 1. Leave it "" to use slot 1's own corner.
; Either way the box is ALWAYS BOX_W x BOX_H - SLOT_INDEX never changes
; the SIZE of what's watched, only WHICH slot's corner BOX_OFFSET_X/Y
; is measured from.
SLOT_INDEX := "6"

; The box to watch: BOX_W x BOX_H, offset by BOX_OFFSET_X/Y from
; whichever corner SLOT_INDEX resolves to (slot 1's corner by default).
BOX_OFFSET_X := 2
BOX_OFFSET_Y := 0
BOX_W := 52
BOX_H := 16

CHANGE_TOL := 10   ; per-channel tolerance before a pixel counts as "changed"

; Sample budget, NOT a fixed stride - see Lib\Inv.ahk's TakeSnapshot.
TARGET_SAMPLES := 50

WAIT_TIMEOUT_MS := 15000
POLL_MS         := 300     ; tick-aligned poll interval
; ========================================================================

; Resolve the box's base corner - a specific slot's corner (SlotCorner)
; if SLOT_INDEX is set, else slot 1's own corner (INV_FIRST_X/Y, from
; Lib\Inv.ahk) - then offset BOX_OFFSET_X/Y from it. BOX_W/BOX_H are
; never touched here; they stay exactly what's configured above no
; matter which slot SLOT_INDEX points at.
if (SLOT_INDEX != "")
    SlotCorner(SLOT_INDEX, &baseX, &baseY)
else {
    baseX := INV_FIRST_X
    baseY := INV_FIRST_Y
}
BOX_X := baseX + BOX_OFFSET_X
BOX_Y := baseY + BOX_OFFSET_Y

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

LogLine("Script loaded. F5=snapshot+watch  F6=stop  Esc=exit. Box=" BOX_X "," BOX_Y " " BOX_W "x" BOX_H)
ToolTip("micro 10 ready - F5 to snapshot the box and watch for a change", 20, 20)
