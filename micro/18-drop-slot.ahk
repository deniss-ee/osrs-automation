; ============================================================
; v7 micro 18 - shift-click drop a slot's contents (DropSlot)
;
; Promoted from v6 motherlode2.ahk's shift-drop helper (confirmed live
; there - used to discard a gem that failed a pay-dirt image check).
; CONTRACT CHANGE from v6: settleMs is a real parameter now (default
; 100, the v7-wide default), not a hardcoded GEM_DROP_SETTLE_MS
; file-local constant.
;
; WHAT IT DOES
;   F5  = SlotFull check on TEST_SLOT before dropping (so you can see
;         the before/after in the log), then DropSlot(TEST_SLOT),
;         then SlotFull again to confirm it emptied
;   F7  = move the mouse to TEST_SLOT's computed center (no click) -
;         confirm it lines up with a real slot before trusting F5
;   F6  = request stop (sets g_StopRequested, standard across every
;         micro/bot - F5 always starts, F6 always stops)
;   Esc = exit the script
;
; LIVE CONFIRM: put a stackable/droppable item in TEST_SLOT, F7 to
; confirm the slot position is right, then F5 - confirm SlotFull
; reports FULL before, the item visibly gets shift-dropped, and
; SlotFull reports EMPTY after. Also confirm F5 on an already-empty
; slot doesn't error (shift-clicking empty space is harmless, just a
; no-op click).
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v7.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "18-drop-slot"

; ======= EDIT THESE FOR YOUR TEST =======================================
TEST_SLOT := 10   ; which inventory slot to drop - try a few different ones
SETTLE_MS := 100
; ========================================================================

F5:: RunDrop()
F7:: RunCalibrateCheck()
F6:: {
    global g_StopRequested
    g_StopRequested := true
    LogLine("F6 pressed - stop requested")
}
Esc:: {
    LogLine("Esc pressed - exiting")
    ExitApp()
}

RunCalibrateCheck() {
    global g_StopRequested
    g_StopRequested := false

    SlotCenter(TEST_SLOT, &x, &y)
    MouseMove(x, y, 5)
    msg := "F7: moved to slot " TEST_SLOT " computed center " x "," y
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

RunDrop() {
    global g_StopRequested
    g_StopRequested := false

    beforeFull := SlotFull(TEST_SLOT)
    LogLine("Before drop: slot " TEST_SLOT " = " (beforeFull ? "FULL" : "empty"))

    DropSlot(TEST_SLOT, SETTLE_MS)

    afterFull := SlotFull(TEST_SLOT)
    msg := "DropSlot(" TEST_SLOT "): before=" (beforeFull ? "FULL" : "empty")
        . " after=" (afterFull ? "FULL" : "empty")
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

LogLine("Script loaded. F5=drop test slot  F7=calibrate (move to slot)  F6=request stop  Esc=exit."
    . " TestSlot=" TEST_SLOT)
ToolTip("micro 18 ready - F7 to calibrate slot " TEST_SLOT ", then F5 to drop", 20, 20)
