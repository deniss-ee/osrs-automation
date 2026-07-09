; ============================================================
; Inventory.ahk
; Wraps Telemetry gates + inventory slot math (legacy's
; lib/Grid.ahk + lib/Slots.ahk) behind one bot-facing surface.
; A Phase asks "IsFull()"/"IsEmpty()" without knowing whether
; that's backed by a single indicator slot or a full slot scan.
; ============================================================

#Requires AutoHotkey v2.0

class Inventory {
    ; layout: {firstX, firstY, cols, rows, slotW, slotH, gapX, gapY} - the
    ; TOP-LEFT corner of slot 1, matching lib/Grid.ahk's corner+size
    ; convention (not center) so calibration numbers are measured the same
    ; way in both places. This user's measured layout: firstX=2099,
    ; firstY=801, 4 cols x 7 rows, 72x64px slots, 12px horizontal / 8px
    ; vertical gaps (no outer padding).
    ;
    ; fullGate/emptyGate are Telemetry gates (e.g. SlotGate) constructed
    ; AFTER this Inventory (they need to call back into its SlotCenter()),
    ; then attached via SetFullGate/SetEmptyGate - avoids a constructor
    ; cycle between Inventory and its gates. Either may be left unset
    ; ("") if a bot never needs that particular check (e.g. MinePhase only
    ; ever calls IsFull(), never IsEmpty()).
    __New(layout, fullGate := "", emptyGate := "", sackGate := "") {
        this._layout := layout
        this._fullGate := fullGate
        this._emptyGate := emptyGate
        this._sackGate := sackGate
    }

    SetFullGate(gate) => this._fullGate := gate

    SetEmptyGate(gate) => this._emptyGate := gate

    ; A distinct gate from full/empty - "did withdrawing from the ore sack
    ; put something in the inventory" (WithdrawSackPhase), backed by an
    ; OrGate over two spread-out slots since a gem can land in either.
    SetSackGate(gate) => this._sackGate := gate

    IsFull() => this._fullGate.IsSet()

    IsEmpty() => this._emptyGate.IsSet()

    HasSackItems() => this._sackGate.IsSet()

    ; Slot coordinate math - given a 1-based, row-major slot index (1 = top-
    ; left, reading left-to-right then top-to-bottom, matching lib/Grid.ahk's
    ; BuildGrid/GetInventorySlots indexing exactly), returns that slot's
    ; screen-space CENTER via out-params. Corner-based like legacy (not
    ; center-based) because a slot's corner is measured directly off-screen,
    ; then shifted by half width/height here - a corner pixel is almost
    ; always plain background even when the slot is full, so clicks/color
    ; checks must target the center, never the corner itself.
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
