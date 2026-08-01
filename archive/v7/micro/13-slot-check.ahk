; ============================================================
; v7 micro 13 - inventory slot check (SlotFull family on Grid)
;
; Port of v6 micro 09, confirmed live there - regression proof that
; Grid.ahk's math (confirmed in micro 12) produces IDENTICAL slot
; centers to v6's original hand-rolled SlotCenter, now that SlotCenter/
; SlotCorner are thin wrappers over GridCenter/GridCorner instead of
; their own col/row/gap arithmetic.
;
; WHAT IT DOES
;   F5  = check all 28 slots, show a 4x7 grid of F(ull)/E(mpty) in a
;         tooltip, log every slot's result
;   F7  = move the mouse to CALIBRATE_SLOT's computed center (no click)
;         - confirms Inv.ahk's INV_GRID layout still lines up
;   F8  = SlotProbe(CALIBRATE_SLOT) - diagnostic: logs the actual color
;         at each of the 4 sample points + whether it reads as empty
;   F6  = request stop (sets g_StopRequested, standard across every
;         micro/bot - F5 always starts, F6 always stops)
;   Esc = exit the script
;
; LIVE CONFIRM: F7 on slot 1 and slot 28 - confirm both land dead-center
; on the real inventory slots (same check as micro 12, but now through
; SlotCenter). F5 with a KNOWN mix of full/empty slots in your
; inventory - confirm the F/E grid matches what you can see. If any
; slot disagrees with what you see, press F8 on that slot and check
; which sample point is wrong before assuming SLOT_EMPTY_COLOR/TOL need
; retuning.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v7.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "13-slot-check"

; ======= EDIT THESE FOR YOUR TEST =======================================
CALIBRATE_SLOT := 1   ; which slot F7/F8 target - try 1, then 28
; ========================================================================

F5:: CheckAllSlots()
F7:: RunCalibrateCheck()
F8:: RunProbe()
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

    SlotCenter(CALIBRATE_SLOT, &x, &y)
    MouseMove(x, y, 5)
    msg := "F7: moved to slot " CALIBRATE_SLOT " computed center " x "," y
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

RunProbe() {
    global g_StopRequested
    g_StopRequested := false

    msg := SlotProbe(CALIBRATE_SLOT)
    ToolTip(msg, 20, 20)
    LogLine(msg)
}

CheckAllSlots() {
    global g_StopRequested
    g_StopRequested := false

    total := INV_GRID.cols * INV_GRID.rows
    LogLine("Slot check started: " total " slots (layout from Lib\Inv.ahk INV_GRID)")

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

        if (Mod(slotIndex, INV_GRID.cols) = 0)
            grid .= "`n"
        else
            grid .= " "
    }

    elapsedMs := A_TickCount - t0
    msg := RTrim(grid, "`n") "`n" fullCount "/" total " full (" elapsedMs " ms)"
    ToolTip(msg, 20, 20)
    LogLine("Grid result: " fullCount "/" total " full in " elapsedMs " ms")
}

LogLine("Script loaded. F5=check all slots  F7=move to calibrate slot " CALIBRATE_SLOT
    . "  F8=probe slot " CALIBRATE_SLOT "  F6=request stop  Esc=exit")
ToolTip("micro 13 ready - F7 to calibrate slot " CALIBRATE_SLOT ", then F5", 20, 20)
