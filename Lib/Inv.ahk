; ============================================================
; v6 Lib\Inv.ahk - inventory addressing + pixel-box snapshot/diff
;
; INV_LAYOUT constants + SlotCenter/SlotFull: byte-identical port from
; micros 09/12 (md5-verified). SlotCorner: byte-identical port from
; micros 10/11 (renamed from v5's SlotBox - returns ONLY a corner,
; never a size; see the header comment in the micros for the bug this
; fixed). TakeSnapshot/HasChanged: byte-identical strided port from
; micro 10 (verbatim in 10/11).
;
; Layout is defined ONCE here (confirmed screen-accurate across all of
; Stage 1) instead of every micro/bot redeclaring the same 8 constants.
; EMPTY_COLOR/EMPTY_TOL are likewise fixed calibration constants, not
; per-bot config - v5's own comments call EMPTY_COLOR stable across
; sessions and never needing recalibration.
; ============================================================

INV_FIRST_X := 2099, INV_FIRST_Y := 801
INV_COLS := 4, INV_ROWS := 7
INV_SLOT_W := 72, INV_SLOT_H := 64
INV_GAP_X := 12, INV_GAP_Y := 8

; ---------- inventory addressing ----------

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

; 1-based, row-major slot index -> that slot's top-left CORNER only -
; no size output. A caller offsets a box of its own choosing from this
; corner; the box's size never changes based on which slot it's
; offset from (this was a real bug in v5's SlotBox, fixed here).
SlotCorner(slotIndex, &x, &y) {
    total := INV_COLS * INV_ROWS
    if (slotIndex < 1 || slotIndex > total)
        throw ValueError("SlotCorner: slotIndex " slotIndex " out of range (1.." total ")")

    col := Mod(slotIndex - 1, INV_COLS)
    row := (slotIndex - 1) // INV_COLS

    x := INV_FIRST_X + col * (INV_SLOT_W + INV_GAP_X)
    y := INV_FIRST_Y + row * (INV_SLOT_H + INV_GAP_Y)
}

; True if OCCUPIED: any sample point no longer matches the empty-
; background color.
;
; BUG FIXED LIVE (2026-07-20): the original 4-point sample (center + 3
; corners) + a fairly loose tolerance (30) let some item icons read as
; "empty" - a particular log sprite's art happened to be background-
; colored at all 4 of those exact pixel offsets, so a genuinely full
; slot (blocking the whole "inventory full -> bank" transition) was
; silently misreported as empty. First fix attempt widened to 9 sample
; points, but PixelGetColor's ~5-7ms fixed per-call cost made that
; noticeably slower per check (called every poll tick via the
; inventory-full condition) - reverted back to 4 points and instead
; tightened the tolerance from 30 to 5 (a real item's color needs to be
; within 5 per channel of EMPTY_COLOR at ALL 4 points to slip through
; now, vs. 30 before - much narrower room for a coincidental match)
; without paying for more PixelGetColor calls. Try 3 points next if 4
; still isn't fast enough - keep tolerance tight if you do.
SlotFull(slotIndex) {
    static offsets := [[0, 0], [-14, -12], [14, -12], [0, 12]]
    static EMPTY_COLOR := 0x3F3629
    static EMPTY_TOL := 5

    SlotCenter(slotIndex, &cx, &cy)
    for off in offsets {
        current := PixelGetColor(cx + off[1], cy + off[2])
        if (!ColorClose(current, EMPTY_COLOR, EMPTY_TOL))
            return true
    }
    return false
}

; ---------- watch-box (pixel-box snapshot + change detection) ----------
;
; Samples roughly targetSamples points spread evenly across a w x h box
; whose top-left corner is x,y - NOT every pixel (exhaustive sampling
; measured ~6 SECONDS for an 832-pixel box; strided sampling took
; ~350ms - see working rule 8). The stride is DERIVED from box size +
; targetSamples, not fixed, so a big box and a small box both cost
; about the same regardless of raw pixel area. Returns one snapshot
; object bundling the samples with the stride/size used to take them,
; so HasChanged always re-samples at the exact same points.
TakeSnapshot(x, y, w, h, targetSamples := 50) {
    scale := Sqrt(w * h / targetSamples)
    strideX := Max(1, Round(scale))
    strideY := Max(1, Round(scale))

    colors := []
    yy := 0
    while (yy < h) {
        xx := 0
        while (xx < w) {
            colors.Push(PixelGetColor(x + xx, y + yy))
            xx += strideX
        }
        yy += strideY
    }
    return {colors: colors, w: w, h: h, strideX: strideX, strideY: strideY}
}

; True if any sampled point now differs from the snapshot's baseline.
; x,y: the box's CURRENT top-left corner (usually unchanged from the
; snapshot, but kept separate in case the box legitimately moves).
HasChanged(snapshot, x, y, tol) {
    idx := 1
    yy := 0
    while (yy < snapshot.h) {
        xx := 0
        while (xx < snapshot.w) {
            current := PixelGetColor(x + xx, y + yy)
            if (!ColorClose(current, snapshot.colors[idx], tol))
                return true
            idx += 1
            xx += snapshot.strideX
        }
        yy += snapshot.strideY
    }
    return false
}
