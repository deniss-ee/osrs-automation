; ============================================================
; v8 Lib\Inv.ahk - inventory + bank slot addressing on top of Grid.ahk
;
; Ported near-verbatim from v7\Lib\Inv.ahk. BANK_GRID's origin/cell
; size/gapX are v7's real live-measured values (confirmed micro
; 09-grid-inventory, 2026-08-01); row 1 (slots 1-8) is trustworthy.
; v7 modeled the whole bank as a single 999-column row (a hack that
; defeats GridCorner's own range check - index 998 would silently
; resolve to an off-screen x of ~95,000 rather than throwing); v8
; keeps the real measurement but bounds it to 8 real columns instead.
; Rows beyond 1 are STILL UNMEASURED (v6/v7 never scrolled/measured a
; second bank row) - live-measure before trusting any slot index > 8.
;
; DropSlot now clicks via ClickAt(ClickTarget(...), {shift: true})
; instead of a bare-coordinate ClickAt call - jitter is bounded by
; the real inventory cell size (72x64), same guarantee as every
; other click in v8.
; ============================================================

INV_GRID := GridSpec(2099, 801, 4, 7, 72, 64, 12, 8)

; origin/cellW/cellH/gapX ported from v7's real live-measured value
; (Lib\Inv.ahk: GridSpec(625, 203, 999, 1, 72, 64, 24, 0)) - v6/v7 never
; measured past a single row, so v7 modeled it as one 999-column row (a
; hack that defeats GridCorner's own range check: index 998 silently
; resolves to an off-screen x of ~95,000 instead of throwing). v8 keeps
; the real single-row measurement but bounds it honestly - STILL A
; PLACEHOLDER for rows/gapY beyond row 1: live-measure a real second
; row before trusting any slot index > 8 against a real bank.
BANK_GRID := GridSpec(625, 203, 8, 1, 72, 64, 24, 0)

SLOT_FULL_OFFSETS := [[0, 0], [-14, -12], [14, -12], [0, 12]]
SLOT_EMPTY_COLOR := 0x3F3629
SLOT_EMPTY_TOL := 5

SlotCenter(slotIndex, &x, &y) {
    GridCenter(INV_GRID, slotIndex, &x, &y)
}

SlotCorner(slotIndex, &x, &y) {
    GridCorner(INV_GRID, slotIndex, &x, &y)
}

BankSlotCenter(slotIndex, &x, &y) {
    GridCenter(BANK_GRID, slotIndex, &x, &y)
}

; A slot counts as "full" if ANY of the sample offsets around its
; center is NOT the empty-slot background color - a few sample
; points tolerate icon variety better than a single center pixel.
SlotFull(slotIndex) {
    SlotCenter(slotIndex, &cx, &cy)
    for offset in SLOT_FULL_OFFSETS {
        px := cx + offset[1]
        py := cy + offset[2]
        if (!IsColorAt(px, py, SLOT_EMPTY_COLOR, SLOT_EMPTY_TOL))
            return true
    }
    return false
}

; Diagnostic string: reports each sample offset's actual color vs
; the expected empty color, for calibration.
SlotProbe(slotIndex) {
    SlotCenter(slotIndex, &cx, &cy)
    out := "slot " slotIndex " (" cx "," cy "): "
    for offset in SLOT_FULL_OFFSETS {
        px := cx + offset[1]
        py := cy + offset[2]
        c := PixelGetColor(px, py)
        empty := IsColorAt(px, py, SLOT_EMPTY_COLOR, SLOT_EMPTY_TOL)
        out .= "[" offset[1] "," offset[2] "]=" HexColor(c) (empty ? "(empty)" : "(filled)") " "
    }
    return out
}

AnySlotEmpty() {
    loop INV_GRID.cols * INV_GRID.rows {
        if (!SlotFull(A_Index))
            return true
    }
    return false
}

AllSlotsFull(slots) {
    for slotIndex in slots {
        if (!SlotFull(slotIndex))
            return false
    }
    return true
}

AllSlotsEmpty(slots) {
    for slotIndex in slots {
        if (SlotFull(slotIndex))
            return false
    }
    return true
}

; Shift-click drop of one inventory slot; settles afterward so the
; next check isn't racing the drop animation. Jitter bounded by the
; slot's own CELL size, centered on the slot CENTER (ClickTarget's
; x/y is the jitter cell's center - using the corner here would spill
; half the clicks outside the slot).
DropSlot(slotIndex, settleMs := 100, preDelayMs := 0, postDelayMs := 0) {
    global INV_GRID
    if (preDelayMs > 0)
        Pause(preDelayMs)

    SlotCenter(slotIndex, &x, &y)
    ClickAt(ClickTarget(x, y, INV_GRID.cellW, INV_GRID.cellH), {shift: true, settleMs: settleMs})
    Pause(settleMs)

    if (postDelayMs > 0)
        Pause(postDelayMs)
}
