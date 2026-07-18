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
;         - use this FIRST to confirm the layout numbers below actually
;         line up with your inventory before trusting the F5 grid
;   F6  = clear the tooltip
;   Esc = exit the script
;
; Algorithm ported from v5 Interfaces\Inventory.ahk (SlotCenter) and
; Detection\Telemetry.ahk (SlotGate's 4-point sampling + the
; EMPTY = 0x3F3629 background color, which v5's comments say is stable
; across sessions and never needs recalibration).
;
; IMPORTANT: INV_FIRST_X/Y below is v5's last-known value for ITS
; screen setup, NOT necessarily correct for yours - press F7 first
; against slot 1 (top-left) and slot 28 (bottom-right) to confirm
; before trusting F5's grid. Adjust INV_FIRST_X/Y (and slotW/H, gapX/Y
; if needed) until F7 lands dead-center on real slots.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

; ======= EDIT THESE FOR YOUR TEST =======================================
INV_FIRST_X := 2099   ; top-left corner of SLOT 1 (not center)
INV_FIRST_Y := 801
INV_COLS    := 4
INV_ROWS    := 7
INV_SLOT_W  := 72
INV_SLOT_H  := 64
INV_GAP_X   := 12
INV_GAP_Y   := 8

EMPTY_COLOR := 0x3F3629   ; v5's measured empty-slot background color
EMPTY_TOL   := 30

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
    total := INV_COLS * INV_ROWS
    LogLine("Slot check started: " total " slots, layout firstX=" INV_FIRST_X
        . " firstY=" INV_FIRST_Y " slotW=" INV_SLOT_W " slotH=" INV_SLOT_H)

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

        if (Mod(slotIndex, INV_COLS) = 0)
            grid .= "`n"
        else
            grid .= " "
    }

    elapsedMs := A_TickCount - t0
    msg := grid "`n" fullCount "/" total " full (" elapsedMs " ms)"
    ToolTip(msg, 20, 20)
    LogLine("Grid result: " fullCount "/" total " full in " elapsedMs " ms")
}

; ---------- inventory (v5 Inventory.ahk + Telemetry.ahk SlotGate port) ----------

; 1-based, row-major slot index (1 = top-left, left-to-right then
; top-to-bottom) -> that slot's screen-space CENTER.
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

; True if OCCUPIED: any of 4 sample points (center + 3 inset from edges)
; no longer matches the empty-background color.
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

ColorClose(c1, c2, tol) {
    return Abs(((c1 >> 16) & 0xFF) - ((c2 >> 16) & 0xFF)) <= tol
        && Abs(((c1 >> 8) & 0xFF) - ((c2 >> 8) & 0xFF)) <= tol
        && Abs((c1 & 0xFF) - (c2 & 0xFF)) <= tol
}

; ---------- logging ----------

LogLine(msg) {
    static logDir := A_ScriptDir "\..\logs"
    static logPath := logDir "\09-slot-check.log"
    if (!DirExist(logDir))
        DirCreate(logDir)
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " [09-slot-check] " msg "`n", logPath)
}

LogLine("Script loaded. F5=check all slots  F7=move to calibrate slot " CALIBRATE_SLOT "  F6=clear  Esc=exit")
ToolTip("micro 09 ready - F7 to calibrate slot " CALIBRATE_SLOT " first, then F5", 20, 20)
