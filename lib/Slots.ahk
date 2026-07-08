; ============================================================
; Slots.ahk - NEW
;
; Generalized arbitrary-slot, direction-agnostic change detection.
; Replaces v2's binary occupied/empty checks + hardcoded last/second-to-last
; slot limitation. v3's centerpiece generalization.
;
; A slot signature is: {slot: 1-28, points: [{x, y, color}, ...]}
; Calibrate once with the slot in whatever state you want to detect changes FROM.
; Then use HasSlotChanged / WaitForSlotChange to detect ANY change from that
; baseline, regardless of direction (occupied→empty, empty→occupied, item→different-item).
;
; Depends on: Colors.ahk (ColorClose), Grid.ahk (GetInventorySlots, GetDefaultSlotOffsets, GetSlotSamplePoints), Context.ahk (CtxIsRunning)
; ============================================================

#Requires AutoHotkey v2.0

#Include Colors.ahk
#Include Grid.ahk
#Include Context.ahk

; Calibrates a slot signature for any inventory slot (1-28).
; Samples N reference points' CURRENT color as the baseline.
; Returns Map("slot", slotIndex, "points", points) where each point has {x, y, color}.
;
; slotIndex: 1-28 (row-major: slot 1 top-left, slot 28 bottom-right)
; offsets: [dx, dy] list from slot center (defaults to GetDefaultSlotOffsets if omitted)
CalibrateSlotSignature(slotIndex, offsets := "") {
    if (offsets = "")
        offsets := GetDefaultSlotOffsets()

    slots := GetInventorySlots()
    if (slotIndex < 1 || slotIndex > slots.Length) {
        MsgBox("Invalid slot index " slotIndex " (must be 1-28)")
        return Map("slot", 0, "points", [])
    }

    slot := slots[slotIndex]
    points := GetSlotSamplePoints(slot, offsets)
    for p in points
        p["color"] := PixelGetColor(p["x"], p["y"], "RGB")

    return Map("slot", slotIndex, "points", points)
}

; Direction-agnostic: true if ANY sampled point's CURRENT color no longer matches
; (within tol) its CALIBRATED baseline color. Detects any change from calibration,
; regardless of which way (empty→occupied, occupied→empty, item→different-item).
HasSlotChanged(sig, tol := 15) {
    for p in sig["points"] {
        current := PixelGetColor(p["x"], p["y"], "RGB")
        if (!ColorClose(current, p["color"], tol))
            return true
    }
    return false
}

; The inverse: true only if EVERY sampled point still matches the baseline.
IsSlotUnchanged(sig, tol := 15) {
    return !HasSlotChanged(sig, tol)
}

; Polls HasSlotChanged(sig) until true for `confirmTicks` consecutive polls,
; or times out. This is the single primitive replacing both v2's:
; - WaitUntilOccupied (baseline=empty)
; - WaitUntilNotOccupied (baseline=full/raw-food/whatever)
; Same call, different calibration.
;
; v3: ctx is required (first param), confirmTicks defaults to 3.
WaitForSlotChange(ctx, sig, tol, timeoutMs, confirmTicks := 3, pollMs := 100) {
    deadline := A_TickCount + timeoutMs
    streak := 0
    loop {
        if (!CtxIsRunning(ctx))
            return false
        if (HasSlotChanged(sig, tol)) {
            streak += 1
            if (streak >= confirmTicks)
                return true
        } else {
            streak := 0
        }
        if (A_TickCount >= deadline)
            return false
        Sleep(pollMs)
    }
}

; The inverse wait: polls until the slot reads BACK to matching its baseline again
; (rarely needed, included for symmetry - e.g. "wait until this slot returns to empty
; after I deposit").
;
; v3: ctx is required (first param), confirmTicks defaults to 3.
WaitForSlotUnchanged(ctx, sig, tol, timeoutMs, confirmTicks := 3, pollMs := 100) {
    deadline := A_TickCount + timeoutMs
    streak := 0
    loop {
        if (!CtxIsRunning(ctx))
            return false
        if (IsSlotUnchanged(sig, tol)) {
            streak += 1
            if (streak >= confirmTicks)
                return true
        } else {
            streak := 0
        }
        if (A_TickCount >= deadline)
            return false
        Sleep(pollMs)
    }
}

; Re-calibrates a signature's baseline to the slot's CURRENT state - useful for
; chained checks. E.g. "slot 1 now has the withdrawn net (occupied) → recalibrate
; → later wait for it to change AGAIN when consumed". One signature, two calibrations,
; no need for separate named signatures.
RecaptureSlotSignature(sig) {
    return CalibrateSlotSignature(sig["slot"])
}

; ============================================================
; Hardcoded emptiness check - NO runtime calibration
; ============================================================
;
; An empty OSRS inventory slot's background is a fixed color that never
; changes between sessions (measured once from v3\images\inv-empty.png,
; baked into Grid.ahk as INVENTORY_EMPTY_COLOR). This builds a slot
; signature against that hardcoded constant instead of a live-captured
; baseline, so it plugs directly into the existing HasSlotChanged/
; WaitForSlotChange/WaitForSlotUnchanged machinery above with zero new
; polling logic - just a different baseline source. Global for every
; bot: no calibration hotkey, no per-script setup, just call IsSlotEmpty/
; WaitForSlotEmpty with the slot index you care about.

; Same shape as CalibrateSlotSignature's return value, but every point's
; "baseline" color is the hardcoded INVENTORY_EMPTY_COLOR instead of a
; live screen sample.
GetEmptySlotSignature(slotIndex, offsets := "") {
    if (offsets = "")
        offsets := GetDefaultSlotOffsets()

    slots := GetInventorySlots()
    slot := slots[slotIndex]
    points := GetSlotSamplePoints(slot, offsets)
    for p in points
        p["color"] := INVENTORY_EMPTY_COLOR

    return Map("slot", slotIndex, "points", points)
}

; True if every sampled point in this slot currently matches the
; hardcoded empty-background color - no calibration required.
IsSlotEmpty(slotIndex, tol := 15, offsets := "") {
    return IsSlotUnchanged(GetEmptySlotSignature(slotIndex, offsets), tol)
}

; The inverse: true if ANY sampled point no longer looks like empty
; background (i.e. an item is occupying the slot).
IsSlotOccupied(slotIndex, tol := 15, offsets := "") {
    return !IsSlotEmpty(slotIndex, tol, offsets)
}

; Polls IsSlotEmpty(slotIndex) until it's true for `confirmTicks`
; consecutive polls, or times out. Use this to wait for a stack to
; deplete to zero (e.g. an ore stack used up by smelting) without ever
; calibrating a baseline first.
WaitForSlotEmpty(ctx, slotIndex, tol, timeoutMs, confirmTicks := 3, pollMs := 100, offsets := "") {
    return WaitForSlotUnchanged(ctx, GetEmptySlotSignature(slotIndex, offsets), tol, timeoutMs, confirmTicks, pollMs)
}

; The inverse wait: polls until the slot becomes occupied (e.g. waiting
; for a freshly-withdrawn item to land in a slot).
WaitForSlotOccupied(ctx, slotIndex, tol, timeoutMs, confirmTicks := 3, pollMs := 100, offsets := "") {
    return WaitForSlotChange(ctx, GetEmptySlotSignature(slotIndex, offsets), tol, timeoutMs, confirmTicks, pollMs)
}
