; ============================================================
; v6 micro 09 - inventory slot check
;
; Proves the inventory-reading primitive: given the 28-slot grid's
; layout (top-left corner of slot 1 + size/gaps), compute each slot's
; center and sample 4 points around it to tell full vs. empty.
;
; WHAT IT DOES
;   F5  = check all 28 slots, show a 4x7 grid of F(ull)/E(mpty) in a
;         tooltip, log every slot's result
;   F7  = move the mouse to CALIBRATE_SLOT's computed center (no click)
;         - confirms the Lib\Inv.ahk layout still lines up with your
;         inventory
;   F6  = clear the tooltip
;   Esc = exit the script
;
; SlotCenter/SlotFull now live in Lib\Inv.ahk, along with the confirmed
; INV_FIRST_X/Y=2099,801 layout (cols=4, rows=7, slotW/H=72,64,
; gapX/Y=12,8) - recalibrate directly in Lib\Inv.ahk if the client
; window ever moves/resizes, not in this file.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v6.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "09-slot-check"

; ======= EDIT THESE FOR YOUR TEST =======================================
CALIBRATE_SLOT := 28   ; which slot F7 moves the mouse to - try 1, then 28
; ========================================================================

F5:: CheckAllSlots()
F7:: {
    SlotCenter(CALIBRATE_SLOT, &x, &y)
    MouseMove(x, y, 5)
    msg := "F7: moved to slot " CALIBRATE_SLOT " computed center " x "," y
    ToolTip(msg, 20, 20)
    LogLine(msg)
}
F6:: {
    ToolTip()
    LogLine("F6 pressed - tooltip cleared")
}
Esc:: {
    LogLine("Esc pressed - exiting")
    ExitApp()
}

CheckAllSlots() {
    total := 28
    LogLine("Slot check started: " total " slots (layout from Lib\Inv.ahk)")

    t0 := A_TickCount
    grid := ""
    fullCount := 0

    loop total {
        slotIndex := A_Index
        full := SlotFull(slotIndex)
        SlotCenter(slotIndex, &cx, &cy)
        LogLine("Slot " slotIndex " (" cx "," cy "): " (full ? "FULL" : "empty"))

        grid .= (full ? "F" : "E")
        if (full)
            fullCount += 1

        if (Mod(slotIndex, 4) = 0)
            grid .= "`n"
        else
            grid .= " "
    }

    elapsedMs := A_TickCount - t0
    ; loop above already ends the grid with "`n" after the last slot
    ; (a full row) - trim it so the summary line doesn't get a blank
    ; line before it.
    msg := RTrim(grid, "`n") "`n" fullCount "/" total " full (" elapsedMs " ms)"
    ToolTip(msg, 20, 20)
    LogLine("Grid result: " fullCount "/" total " full in " elapsedMs " ms")
}

LogLine("Script loaded. F5=check all slots  F7=move to calibrate slot " CALIBRATE_SLOT "  F6=clear  Esc=exit")
ToolTip("micro 09 ready - F7 to calibrate slot " CALIBRATE_SLOT ", then F5", 20, 20)
