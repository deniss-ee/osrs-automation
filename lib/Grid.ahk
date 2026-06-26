; ============================================================
;  Grid.ahk
;  Coordinate presets for OSRS UI grids (inventory, bank,
;  deposit-all button) on this user's client window layout.
;  All defaults below came from direct on-screen measurement
;  and remain fully overridable - if the client window ever
;  moves or resizes, recalibrate the corners and pass new
;  values into these functions instead of editing them.
;  No dependencies on any other lib file.
; ============================================================

; Generic linear-interpolation grid generator. Given the position
; of the first cell and the position of the last cell (both using
; the SAME anchor point - e.g. both top-left corners, or both
; centers - don't mix them) plus how many columns/rows the grid
; has, returns every cell's position using that same anchor, in
; row-major order (index 1 = top-left, reading left-to-right then
; top-to-bottom - same order you'd read the slots visually).
;
; Each returned entry is a Map: {x, y, index, col, row}
BuildGrid(firstX, firstY, lastX, lastY, cols, rows) {
    stepX := (cols > 1) ? (lastX - firstX) / (cols - 1) : 0
    stepY := (rows > 1) ? (lastY - firstY) / (rows - 1) : 0

    cells := []
    index := 1
    loop rows {
        row := A_Index - 1
        loop cols {
            col := A_Index - 1
            x := Round(firstX + col * stepX)
            y := Round(firstY + row * stepY)
            cells.Push(Map("x", x, "y", y, "index", index, "col", col + 1, "row", row + 1))
            index += 1
        }
    }
    return cells
}

; Standard OSRS backpack: 4 columns x 7 rows = 28 slots, each
; 72x64px. firstX/firstY and lastX/lastY are the TOP-LEFT corner
; of slot 1 and slot 28 (matching how the bank slots and the
; deposit-all button below were measured - corner + size, not
; center). The grid is built from those corners, then every cell
; is shifted by half its width/height so the returned x,y is the
; true CENTER - the point both clicks and color checks should
; target, since a corner pixel is almost always plain background
; even when the slot is full.
GetInventorySlots(firstX := 2099, firstY := 801, lastX := 2351, lastY := 1233) {
    w := 72, h := 64
    slots := BuildGrid(firstX, firstY, lastX, lastY, 4, 7)
    for slot in slots {
        slot["x"] += w // 2
        slot["y"] += h // 2
        slot["w"] := w
        slot["h"] := h
    }
    return slots
}

; Bank item slots, one visible row of 8, each 72x64px, fixed
; y, x stepping by a constant amount. This is a flat hardcoded
; list rather than a generic multi-row grid - the bank window
; scrolls instead of showing more rows on screen, so there's no
; "last slot" to interpolate from the way the inventory has.
; baseX/y are the TOP-LEFT corner of slot 1 (same corner+size
; convention as GetInventorySlots/GetDepositAllButton) - converted
; to each slot's true center below. Defaults come from this
; user's measured corners: 625, 721, 817, 913, 1009, 1105, 1201,
; 1297 @ y=203.
GetBankSlots(baseX := 625, y := 203, step := 96, count := 8) {
    w := 72, h := 64
    slots := []
    loop count {
        index := A_Index
        x := baseX + (index - 1) * step
        slots.Push(Map("x", x + w // 2, "y", y + h // 2, "w", w, "h", h, "index", index))
    }
    return slots
}

; The bank's "Deposit all inventory" button, as a single named
; clickable region. Default is this user's measured button:
; 72x72px box, top-left (1327, 963) -> center (1363, 999).
GetDepositAllButton(x := 1363, y := 999, w := 72, h := 72) {
    return Map("x", x, "y", y, "w", w, "h", h)
}

; A sane default spread of sample points for a 72x64 slot, as
; [dx, dy] offsets from its center: dead center, plus three more
; inset from the edges (not flush against them - some item icons
; don't quite reach the edge either). Tuned to land inside
; virtually any OSRS item icon regardless of its exact shape, for
; use with GetSlotSamplePoints() + Colors.ahk's IsAnyPointOccupied.
GetDefaultSlotOffsets() {
    return [[0, 0], [-14, -12], [14, -12], [0, 12]]
}

; Given a slot {x, y, ...} (as returned by GetInventorySlots /
; GetBankSlots) and a list of [dx, dy] offsets from its center,
; returns the absolute {x, y} for each - several points to sample
; inside one slot instead of trusting its single center pixel.
GetSlotSamplePoints(slot, offsets) {
    points := []
    for off in offsets
        points.Push(Map("x", slot["x"] + off[1], "y", slot["y"] + off[2]))
    return points
}
