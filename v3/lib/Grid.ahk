; ============================================================
; Grid.ahk
; Coordinate presets for OSRS UI grids (inventory, bank,
; deposit-all button) on this user's client window layout.
; All defaults below came from direct on-screen measurement
; and remain fully overridable - if the client window ever
; moves or resizes, recalibrate the corners and pass new
; values into these functions instead of editing them.
; No dependencies on any other lib file.
; ============================================================

#Requires AutoHotkey v2.0

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
; 72x64px. Gaps are NOT uniform: 12px horizontally between columns,
; 8px vertically between rows. This user's measured layout,
; hardcoded as the canonical reference (not just default parameters)
; so any future code can rely on these exact numbers without
; depending on a caller never overriding them:
;
;   container top-left (1615, 801), 324x496px
;   slot 1 (top-left)      top-left corner (1615, 801)
;   slot 28 (bottom-right) top-left corner (1867, 1233)
;   4 columns x 7 rows, each slot 72x64px, 12px horizontal / 8px vertical gaps
;
;     [] [] [] []
;     [] [] [] []
;     [] [] [] []
;     [] [] [] []
;     [] [] [] []
;     [] [] [] []
;     [] [] [] []
;
global INVENTORY_FIRST_X := 1615, INVENTORY_FIRST_Y := 801
global INVENTORY_LAST_X := 1867, INVENTORY_LAST_Y := 1233
global INVENTORY_COLS := 4, INVENTORY_ROWS := 7
global INVENTORY_SLOT_W := 72, INVENTORY_SLOT_H := 64
global INVENTORY_GAP_X := 12, INVENTORY_GAP_Y := 8

; Hardcoded empty-slot background color, measured directly from
; v3\images\inv-empty.png (a 324x496px screenshot of the fully empty
; inventory, captured at this same container position). Sampled all
; 28 slots' GetDefaultSlotOffsets() points from that file: every slot
; reads ~(63,54,41) give or take 2-5 per channel (faint texture noise).
; This single constant is the basis for Slots.ahk's hardcoded
; emptiness check - no per-session calibration needed, since an empty
; slot's background never changes between game sessions.
global INVENTORY_EMPTY_COLOR := 0x3F3629

; firstX/firstY and lastX/lastY are the TOP-LEFT corner of slot 1
; and slot 28 (matching how the bank slots and the deposit-all
; button below were measured - corner + size, not center). The
; grid is built from those corners, then every cell is shifted by
; half its width/height so the returned x,y is the true CENTER -
; the point both clicks and color checks should target, since a
; corner pixel is almost always plain background even when the
; slot is full. Defaults to the hardcoded INVENTORY_* constants
; above - pass explicit values only if a different client layout
; ever needs calibrating.
GetInventorySlots(firstX := INVENTORY_FIRST_X, firstY := INVENTORY_FIRST_Y, lastX := INVENTORY_LAST_X, lastY := INVENTORY_LAST_Y) {
    w := INVENTORY_SLOT_W, h := INVENTORY_SLOT_H
    slots := BuildGrid(firstX, firstY, lastX, lastY, INVENTORY_COLS, INVENTORY_ROWS)
    for slot in slots {
        slot["x"] += w // 2
        slot["y"] += h // 2
        slot["w"] := w
        slot["h"] := h
    }
    return slots
}

; Precomputed, ready-to-use list of all 28 inventory slot centers
; at this user's hardcoded layout (INVENTORY_* above) - for code
; that just needs "the" slot list without calling GetInventorySlots()
; itself. Each entry is the same {x, y, index, col, row, w, h} shape
; GetInventorySlots() returns.
global INVENTORY_SLOTS := GetInventorySlots()

; Bank item slots, one visible row of 8, each 72x64px, fixed
; y, x stepping by a constant amount. This is a flat hardcoded
; list rather than a generic multi-row grid - the bank window
; scrolls instead of showing more rows on screen, so there's no
; "last slot" to interpolate from the way the inventory has.
; baseX/y are the TOP-LEFT corner of slot 1 (same corner+size
; convention as GetInventorySlots/GetDepositAllButton) - converted
; to each slot's true center below. Container is 744x64px at
; top-left (383, 203), 8 slots of 72x64px with 24px margins
; between them (step = 72 + 24 = 96). Defaults come from this
; user's measured corners: 383, 479, 575, 671, 767, 863, 959,
; 1055 @ y=203.
GetBankSlots(baseX := 383, y := 203, step := 96, count := 8) {
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
; 72x72px box, top-left (1085, 963) -> center (1121, 999).
GetDepositAllButton(x := 1121, y := 999, w := 72, h := 72) {
    return Map("x", x, "y", y, "w", w, "h", h)
}

; The deposit-all button's reference image (v3\images\deposit.png),
; as a ready-to-use {file, w, h, x1, y1, x2, y2} spec for
; WaitForImageNearButton/ImageSearch calls - doubles as the "is the
; bank actually open" signal. Search region is the button's own
; 72x72px box, top-left (1085, 963).
GetDepositButtonImage() {
    return Map("file", A_ScriptDir "\..\images\deposit.png", "w", 72, "h", 72,
                "x1", 1085, "y1", 963, "x2", 1085 + 72, "y2", 963 + 72, "options", "")
}

; Indicator image for an opened Smelting/Cooking action menu
; (v3\images\smelt-cook.png), 70x60px, top-left (929, 1081). Once
; this is visible, any of 1/2/3/Space confirms the action and it
; continues automatically - use as a Marker.ahk "confirm" image.
GetSmeltCookIndicatorImage() {
    return Map("file", A_ScriptDir "\..\images\smelt-cook.png", "w", 70, "h", 60,
                "x1", 929, "y1", 1081, "x2", 929 + 70, "y2", 1081 + 60, "options", "")
}

; Indicator image for an opened Crafting action menu
; (v3\images\craft.png), 382x34px, top-left (929, 1081). Once this
; is visible, Space confirms the action and it continues
; automatically - use as a Marker.ahk "confirm" image.
GetCraftIndicatorImage() {
    return Map("file", A_ScriptDir "\..\images\craft.png", "w", 382, "h", 34,
                "x1", 929, "y1", 1081, "x2", 929 + 382, "y2", 1081 + 34, "options", "")
}

; A sane default spread of sample points for a 72x64 slot, as
; [dx, dy] offsets from its center: dead center, plus three more
; inset from the edges (not flush against them - some item icons
; don't quite reach the edge either). Tuned to land inside
; virtually any OSRS item icon regardless of its exact shape, for
; use with GetSlotSamplePoints() + Colors.ahk's occupancy checks.
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
