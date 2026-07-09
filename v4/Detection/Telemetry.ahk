; ============================================================
; Telemetry.ahk
; Lightweight boolean gates that flip the engine between primary
; routines (e.g. mine <-> bank), all exposed as IsSet() => bool
; so a Phase doesn't care which strategy backs the gate:
; - SlotGate: single calibrated indicator slot, occupied/empty
; - SlotSignatureGate: snapshot-then-diff a slot to detect
;   "item transformed" (raw -> cooked), not just presence
; ============================================================

#Requires AutoHotkey v2.0

#Include ColorSearch.ahk

; Empty-slot background color, measured once - never changes between
; sessions, so no per-session calibration is needed.
class InventoryColors {
    static EMPTY := 0x3F3629
}

; Sample offsets from a slot's center: dead center, plus three more inset
; from the edges - tuned to land inside virtually any item icon.
class SlotSampling {
    static DefaultOffsets() {
        return [[0, 0], [-14, -12], [14, -12], [0, 12]]
    }
}

; True if the slot is OCCUPIED (any sampled point no longer matches the
; empty-background color).
class SlotGate {
    __New(slotIndex, tolerance, inventory, offsets := "") {
        this._slotIndex := slotIndex
        this._tolerance := tolerance
        this._inventory := inventory   ; an Inventory, for SlotCenter()
        this._offsets := offsets != "" ? offsets : SlotSampling.DefaultOffsets()
    }

    ; True when the slot is occupied (an item is present).
    IsSet() {
        this._inventory.SlotCenter(this._slotIndex, &cx, &cy)
        for off in this._offsets {
            px := cx + off[1]
            py := cy + off[2]
            current := PixelGetColor(px, py, "RGB")
            if (!ColorSearch.ColorClose(current, InventoryColors.EMPTY, this._tolerance))
                return true   ; this point no longer looks like empty background
        }
        return false
    }
}

; Inverts another gate's IsSet() - used where a Phase needs "empty" but
; the only calibrated gate reports "occupied" (a SlotGate).
class NotGate {
    __New(gate) {
        this._gate := gate
    }

    IsSet() => !this._gate.IsSet()
}

; True only when ALL wrapped gates are set - e.g. Motherlode's
; inventory-full check needs both slot 27 and 28 occupied, since a gem
; can land in 28 without the hopper ever collecting it.
class AndGate {
    __New(gates) {
        this._gates := gates
    }

    IsSet() {
        for gate in this._gates {
            if (!gate.IsSet())
                return false
        }
        return true
    }
}

; True when ANY wrapped gate is set - e.g. Motherlode's
; withdraw-from-sack check treats two slots as OR, since a gem can land
; in either one.
class OrGate {
    __New(gates) {
        this._gates := gates
    }

    IsSet() {
        for gate in this._gates {
            if (gate.IsSet())
                return true
        }
        return false
    }
}

class SlotSignatureGate {
    __New(slotIndex, tolerance) {
        this._slotIndex := slotIndex
        this._tolerance := tolerance
        this._baseline := ""
    }

    ; Snapshots the current slot color/state as the comparison baseline -
    ; must be called once before IsSet() is meaningful (e.g. right after
    ; placing raw food in the range).
    Calibrate() {
        throw Error("SlotSignatureGate.Calibrate not yet implemented - ported from lib/Slots.ahk in Phase 5")
    }

    ; True once the slot differs from the calibrated baseline.
    IsSet() {
        throw Error("SlotSignatureGate.IsSet not yet implemented - ported from lib/Slots.ahk in Phase 5")
    }
}
