; ============================================================
; v7 Lib\Inv.ahk - inventory/bank slot addressing + fullness checks
;
; INV_GRID/BANK_GRID are GridSpec instances with this setup's measured
; calibration (confirmed live, micros 12/13/24). Slot fullness is
; deliberately 4-point sampling against the empty-background UI color -
; slot positions are computed, not searched.
; ============================================================

INV_GRID := GridSpec(2099, 801, 4, 7, 72, 64, 12, 8)

; Single row only (v6's measured limit) - extend rows only after a real
; second-row measurement.
BANK_GRID := GridSpec(625, 203, 999, 1, 72, 64, 24, 0)

SlotCenter(slotIndex, &x, &y) {
    GridCenter(INV_GRID, slotIndex, &x, &y)
}

SlotCorner(slotIndex, &x, &y) {
    GridCorner(INV_GRID, slotIndex, &x, &y)
}

BankSlotCenter(slotIndex, &x, &y) {
    GridCenter(BANK_GRID, slotIndex, &x, &y)
}

; File-level so SlotProbe shares the exact values SlotFull checks -
; never duplicate these into a second function.
SLOT_FULL_OFFSETS := [[0, 0], [-14, -12], [14, -12], [0, 12]]
SLOT_EMPTY_COLOR := 0x3F3629
SLOT_EMPTY_TOL := 5

; True if OCCUPIED: any sample point differs from the empty color.
SlotFull(slotIndex) {
    SlotCenter(slotIndex, &cx, &cy)
    for off in SLOT_FULL_OFFSETS {
        current := PixelGetColor(cx + off[1], cy + off[2])
        if (!ColorClose(current, SLOT_EMPTY_COLOR, SLOT_EMPTY_TOL))
            return true
    }
    return false
}

; Diagnostic twin of SlotFull: logs each sample point's real color and
; verdict. Use when SlotFull disagrees with what you can see.
SlotProbe(slotIndex) {
    SlotCenter(slotIndex, &cx, &cy)
    msg := "SlotProbe " slotIndex " (" cx "," cy "):"
    anyDiffers := false
    for i, off in SLOT_FULL_OFFSETS {
        current := PixelGetColor(cx + off[1], cy + off[2])
        close := ColorClose(current, SLOT_EMPTY_COLOR, SLOT_EMPTY_TOL)
        if (!close)
            anyDiffers := true
        msg .= "`n  [" i "] offset " off[1] "," off[2] " = " HexColor(current)
            . (close ? " (~= empty, tol " SLOT_EMPTY_TOL ")" : " (DIFFERS from empty - occupied signal)")
    }
    msg .= "`n  => SlotFull(" slotIndex ") would report: " (anyDiffers ? "FULL" : "EMPTY")
    return msg
}

AnySlotEmpty() {
    total := INV_GRID.cols * INV_GRID.rows
    loop total {
        if (!SlotFull(A_Index))
            return true
    }
    return false
}

AllSlotsFull(slots) {
    for slot in slots {
        if (!SlotFull(slot))
            return false
    }
    return true
}

AllSlotsEmpty(slots) {
    for slot in slots {
        if (SlotFull(slot))
            return false
    }
    return true
}

; Shift-click drop; settles afterward so the next check isn't racing
; the drop animation.
DropSlot(slotIndex, settleMs := 100, preDelayMs := 0, postDelayMs := 0) {
    if (preDelayMs > 0)
        Pause(preDelayMs)

    SlotCenter(slotIndex, &x, &y)
    ClickAt(x, y, false, true, settleMs)
    Pause(settleMs)

    if (postDelayMs > 0)
        Pause(postDelayMs)
}
