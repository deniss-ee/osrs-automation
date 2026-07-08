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

class SlotGate {
    __New(slotIndex, tolerance) {
        this._slotIndex := slotIndex
        this._tolerance := tolerance
    }

    IsSet() {
        throw Error("SlotGate.IsSet not yet implemented - ported from lib/Slots.ahk in Phase 5")
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
