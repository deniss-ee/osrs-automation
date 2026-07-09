; ============================================================
; Telemetry.ahk
; Lightweight boolean gates that flip the engine between
; primary routines (e.g. mine <-> bank). Two strategies seen in
; legacy, both exposed as IsSet() => bool per the Detection
; contract so a Phase doesn't care which strategy backs the gate:
; - SlotGate: single calibrated indicator slot, occupied/empty
;   (lib/Slots.ahk's IsSlotOccupied/IsSlotEmpty)
; - SlotSignatureGate: snapshot-then-diff a slot (or set of
;   slots) to detect "item transformed" (raw -> cooked), not
;   just presence (cooker/smith/smelter's CalibrateSlotSignature
;   + WaitForSlotChange/WaitForSlotUnchanged)
; ============================================================

#Requires AutoHotkey v2.0

#Include ColorSearch.ahk

; Hardcoded empty-slot background color - measured once from a fully empty
; inventory screenshot, never changes between game sessions. Matches
; lib/Grid.ahk's INVENTORY_EMPTY_COLOR exactly, so v4's occupancy check
; needs no per-session calibration, same as legacy. A static class constant,
; not a global, per the v4 no-globals rule (ruleset 3.2).
class InventoryColors {
    static EMPTY := 0x3F3629
}

; Sample offsets from a slot's center: dead center, plus three more inset
; from the edges - tuned to land inside virtually any item icon regardless
; of shape. Matches lib/Grid.ahk's GetDefaultSlotOffsets exactly.
class SlotSampling {
    static DefaultOffsets() {
        return [[0, 0], [-14, -12], [14, -12], [0, 12]]
    }
}

; True if the slot is OCCUPIED (any sampled point no longer matches the
; hardcoded empty-background color) - direct analog of lib/Slots.ahk's
; IsSlotOccupied(slotIndex, tol) using the hardcoded-color variant (no
; runtime calibration), which is what MinePhase's indicator-slot check uses.
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

; Inverts another gate's IsSet() - used where a Phase needs "empty" (e.g.
; ClearYellowPhase.IsEmpty()) but the only calibrated gate available reports
; "occupied" (a SlotGate). Keeps SlotGate itself single-purpose (reports
; occupancy only) rather than growing an inverted mode of its own.
class NotGate {
    __New(gate) {
        this._gate := gate
    }

    IsSet() => !this._gate.IsSet()
}

; True only when ALL wrapped gates are set - used for the Motherlode
; inventory-full check, which needs BOTH slot 27 and slot 28 occupied to
; count as genuinely full. A lone gem can land in slot 28 without the
; hopper ever collecting it (gems aren't ore, so they never leave that
; slot), which would make a slot-28-only check falsely report "full"
; forever after a single gem, even with 26 empty slots underneath it.
; Requiring slot 27 too means a gem alone in 28 (with 27 still empty)
; correctly reads as not full.
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

; True when ANY wrapped gate is set - used for the Motherlode
; withdraw-from-sack check, which treats the inventory as "received
; something" if EITHER of two spread-out slots (2 or 12) is occupied -
; checking two slots instead of one guards against a gem landing in
; whichever slot happens to be checked, since gems can appear in any slot.
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
