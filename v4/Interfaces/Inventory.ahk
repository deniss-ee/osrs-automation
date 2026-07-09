; ============================================================
; Inventory.ahk
; Wraps Telemetry gates + inventory slot math behind one
; bot-facing surface. A Phase asks "IsFull()"/"IsEmpty()" without
; knowing whether that's a single indicator slot or a full scan.
; ============================================================

#Requires AutoHotkey v2.0

class Inventory {
    ; layout: {firstX, firstY, cols, rows, slotW, slotH, gapX, gapY} - the
    ; TOP-LEFT corner of slot 1 (not center), so calibration numbers are
    ; measured the same way everywhere.
    ;
    ; fullGate/emptyGate/sackGate are Telemetry gates constructed AFTER
    ; this Inventory (they need SlotCenter()), then attached via the
    ; setters - avoids a constructor cycle. Any may be left unset ("")
    ; if a bot never needs that check.
    __New(layout, fullGate := "", emptyGate := "", sackGate := "") {
        this._layout := layout
        this._fullGate := fullGate
        this._emptyGate := emptyGate
        this._sackGate := sackGate
    }

    SetFullGate(gate) => this._fullGate := gate

    SetEmptyGate(gate) => this._emptyGate := gate

    ; Distinct from full/empty - "did the sack put something in the
    ; inventory" (WithdrawSackPhase).
    SetSackGate(gate) => this._sackGate := gate

    IsFull() => this._fullGate.IsSet()

    IsEmpty() => this._emptyGate.IsSet()

    HasSackItems() => this._sackGate.IsSet()

    ; Given a 1-based, row-major slot index (1 = top-left, reading
    ; left-to-right then top-to-bottom), returns that slot's screen-space
    ; CENTER via out-params. Corner-based math because a slot's corner is
    ; measured directly, then shifted by half width/height - a corner
    ; pixel is almost always background even when the slot is full.
    SlotCenter(slotIndex, &x, &y) {
        l := this._layout
        total := l["cols"] * l["rows"]
        if (slotIndex < 1 || slotIndex > total)
            throw Error("Inventory.SlotCenter: slotIndex " slotIndex " out of range (1.." total ")")

        col := Mod(slotIndex - 1, l["cols"])
        row := (slotIndex - 1) // l["cols"]

        cornerX := l["firstX"] + col * (l["slotW"] + l["gapX"])
        cornerY := l["firstY"] + row * (l["slotH"] + l["gapY"])

        x := cornerX + l["slotW"] // 2
        y := cornerY + l["slotH"] // 2
    }
}
