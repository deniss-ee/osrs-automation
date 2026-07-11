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

; True once a slot's contents change from whatever they were at Calibrate()
; time - unlike SlotGate (occupied vs. a fixed empty-background color),
; this detects "the item itself changed" (e.g. ore -> bar), which never
; empties the slot's background, so SlotGate/NotGate can't see it.
class SlotSignatureGate {
    __New(slotIndex, tolerance, inventory, offsets := "") {
        this._slotIndex := slotIndex
        this._tolerance := tolerance
        this._inventory := inventory
        this._offsets := offsets != "" ? offsets : SlotSampling.DefaultOffsets()
        this._baseline := ""
    }

    ; Snapshots the current sampled colors as the comparison baseline -
    ; must be called once while the pre-transform item is visible (e.g.
    ; right after confirming a "smelt X" dialog, while ore still shows).
    Calibrate() {
        this._inventory.SlotCenter(this._slotIndex, &cx, &cy)
        snapshot := []
        for off in this._offsets
            snapshot.Push(PixelGetColor(cx + off[1], cy + off[2], "RGB"))
        this._baseline := snapshot
    }

    ; True once any sampled point no longer matches its calibrated baseline
    ; color - the item in the slot changed (or the slot emptied, which also
    ; differs from a non-empty baseline).
    IsSet() {
        if (this._baseline = "")
            throw Error("SlotSignatureGate.IsSet: Calibrate() was never called")

        this._inventory.SlotCenter(this._slotIndex, &cx, &cy)
        for i, off in this._offsets {
            current := PixelGetColor(cx + off[1], cy + off[2], "RGB")
            if (!ColorSearch.ColorClose(current, this._baseline[i], this._tolerance))
                return true
        }
        return false
    }
}

; Checks a fixed screen point against an arbitrary color, on demand - unlike
; the slot-anchored gates above, this isn't tied to Inventory/SlotCenter, and
; it distinguishes WHICH of several candidate colors is present rather than
; reporting a single on/off state. Used for combat-indicator pixels (e.g. an
; HP-bar overlay that takes one color while fighting, another on a kill).
class PixelColorGate {
    __New(x, y, tolerance) {
        this._x := x
        this._y := y
        this._tolerance := tolerance
    }

    ; True if the live pixel currently matches `color` within tolerance.
    Matches(color) {
        return ColorSearch.IsColorAt(this._x, this._y, color, this._tolerance)
    }
}
