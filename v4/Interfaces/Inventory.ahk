; ============================================================
; Inventory.ahk
; Wraps Telemetry gates + inventory slot math (legacy's
; lib/Grid.ahk + lib/Slots.ahk) behind one bot-facing surface.
; A Phase asks "IsFull()"/"IsEmpty()" without knowing whether
; that's backed by a single indicator slot or a full slot scan.
; ============================================================

#Requires AutoHotkey v2.0

class Inventory {
    __New(fullGate, emptyGate) {
        this._fullGate := fullGate     ; a Telemetry gate (SlotGate/SlotSignatureGate)
        this._emptyGate := emptyGate
    }

    IsFull() => this._fullGate.IsSet()

    IsEmpty() => this._emptyGate.IsSet()

    ; Slot coordinate math (which screen x/y a given inventory slot index
    ; occupies) - ported from lib/Grid.ahk in Phase 5.
    SlotCenter(slotIndex, &x, &y) {
        throw Error("Inventory.SlotCenter not yet implemented - ported from lib/Grid.ahk in Phase 5")
    }
}
