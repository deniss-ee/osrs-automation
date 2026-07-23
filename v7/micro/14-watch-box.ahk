; ============================================================
; v7 micro 14 - pixel-box snapshot + change detection ("watch-box")
;
; Port of v6 micro 10, confirmed live there. Config matches v6's real
; use case exactly: the watched box is an item stack-count readout,
; offset from a SPECIFIC INVENTORY SLOT's top-left corner (SlotCorner,
; Lib\Inv.ahk) - not an arbitrary screen box. TakeSnapshot/HasChanged
; (Lib\Find.ahk) do the actual sampling/diffing.
;
; WHAT IT DOES
;   F7  = trace the box's outline with the mouse (4 corners) - use this
;         FIRST to visually confirm the box actually covers the right
;         area before trusting F5
;   F5  = snapshot the box now, then wait (interruptible, with
;         timeout) until any pixel in it changes
;   F6  = request stop (interrupts the wait, standard across every
;         micro/bot - F5 always starts, F6 always stops)
;   Esc = exit the script
;
; The watched box is ALWAYS BOX_W x BOX_H, offset by BOX_OFFSET_X/Y
; from SLOT_INDEX's corner (Lib\Inv.ahk SlotCorner) - SLOT_INDEX only
; picks WHICH slot's corner the offset is measured from; it never
; changes the box's size.
;
; LIVE CONFIRM: set SLOT_INDEX to a slot holding a stackable item (e.g.
; coins, runes), F7 to confirm the traced box lines up with that slot's
; stack-count digits, then F5 and change the stack (drop/pick up one)
; before the timeout - should report CHANGED. F5 again with nothing
; changing should TIME OUT with no change detected. F6 mid-wait should
; report STOPPED.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v7.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "14-watch-box"

; ======= EDIT THESE FOR YOUR TEST =======================================
; Which inventory slot's corner to offset the box from (1-28, Lib\Inv.ahk
; SlotCorner). The box is ALWAYS BOX_W x BOX_H - SLOT_INDEX never
; changes the SIZE of what's watched, only WHICH slot's corner
; BOX_OFFSET_X/Y is measured from.
SLOT_INDEX := 3

; The stack-count box to watch: BOX_W x BOX_H, offset by
; BOX_OFFSET_X/Y from SLOT_INDEX's corner.
BOX_OFFSET_X := 2
BOX_OFFSET_Y := 0
BOX_W := 52
BOX_H := 16

CHANGE_TOL := 10   ; per-channel tolerance before a pixel counts as "changed"

; Sample budget, NOT a fixed stride - see Lib\Find.ahk's TakeSnapshot.
TARGET_SAMPLES := 50

WAIT_TIMEOUT_MS := 15000
POLL_MS         := 300     ; tick-aligned poll interval
; ========================================================================

; Resolve the box's base corner via SlotCorner (Lib\Inv.ahk), then
; offset BOX_OFFSET_X/Y from it. BOX_W/BOX_H are never touched here;
; they stay exactly what's configured above no matter which slot
; SLOT_INDEX points at.
SlotCorner(SLOT_INDEX, &baseX, &baseY)
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

LogLine("Script loaded. F5=snapshot+watch  F6=request stop  Esc=exit. Box=" BOX_X "," BOX_Y " " BOX_W "x" BOX_H)
ToolTip("micro 14 ready - F5 to snapshot the box and watch for a change", 20, 20)
