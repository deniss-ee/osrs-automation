; ============================================================
; v7 Lib\Inv.ahk - inventory slot addressing + fullness checks
;
; INV_GRID is a GridSpec instance (Grid.ahk) using the calibration
; confirmed live in micro 12 (2099,801 / 4 cols x 7 rows / 72x64 cells
; / 12,8 gaps) - the same numbers v6 measured, confirmed still correct
; on this setup. SlotCenter/SlotCorner are thin wrappers over
; GridCenter/GridCorner so calling code reads the same as v6's did,
; even though the math itself now lives once in Grid.ahk.
;
; SlotFull/SlotProbe/AnySlotEmpty/AllSlotsFull/AllSlotsEmpty: ported
; byte-identical in behavior from v6 Lib\Inv.ahk (confirmed live there,
; v6 micros 09/12). SLOT_FULL_OFFSETS/SLOT_EMPTY_COLOR/SLOT_EMPTY_TOL
; are the same fixed values v6 confirmed - the empty-slot background
; color is a UI skin color, not a screen coordinate, so it's expected
; to hold across setups/resolutions; SlotProbe (micro 13) is the tool
; to re-verify this live if it ever doesn't match.
; ============================================================

INV_GRID := GridSpec(2099, 801, 4, 7, 72, 64, 12, 8)

SlotCenter(slotIndex, &x, &y) {
    GridCenter(INV_GRID, slotIndex, &x, &y)
}

SlotCorner(slotIndex, &x, &y) {
    GridCorner(INV_GRID, slotIndex, &x, &y)
}

; File-level (not function-static) so SlotProbe shares the exact same
; values SlotFull actually checks against - duplicating these into a
; second function risks the two silently drifting apart.
SLOT_FULL_OFFSETS := [[0, 0], [-14, -12], [14, -12], [0, 12]]
SLOT_EMPTY_COLOR := 0x3F3629
SLOT_EMPTY_TOL := 5

; True if OCCUPIED: any of the 4 sample points no longer matches the
; empty-background color. Positions are computed, not searched - see
; the v7 plan's deliberate decision to keep this single-point/fixed-
; sample rather than a box-based search.
SlotFull(slotIndex) {
    SlotCenter(slotIndex, &cx, &cy)
    for off in SLOT_FULL_OFFSETS {
        current := PixelGetColor(cx + off[1], cy + off[2])
        if (!ColorClose(current, SLOT_EMPTY_COLOR, SLOT_EMPTY_TOL))
            return true
    }
    return false
}

; Diagnostic twin of SlotFull - logs the actual on-screen color at each
; sample point plus whether it's within tolerance of "empty", instead
; of just the true/false result. Use against a slot you can SEE is
; occupied whenever SlotFull disagrees - tells you exactly which
; sample point(s) are the problem, so tuning comes from real measured
; colors instead of another guess.
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

; True if ANY slot (1..INV_GRID cols*rows) reads not-full (empty).
AnySlotEmpty() {
    total := INV_GRID.cols * INV_GRID.rows
    loop total {
        if (!SlotFull(A_Index))
            return true
    }
    return false
}

; True if EVERY slot in the given list reads full.
AllSlotsFull(slots) {
    for slot in slots {
        if (!SlotFull(slot))
            return false
    }
    return true
}

; True if EVERY slot in the given list reads empty.
AllSlotsEmpty(slots) {
    for slot in slots {
        if (SlotFull(slot))
            return false
    }
    return true
}
