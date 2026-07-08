; ============================================================
; Marker.ahk - NEW
;
; Generalized marker-click → wait-for-confirm → press-key → wait-for-slot-change
; sequence. Replaces the 5-line hand-assembled sequence every smelter/cooker/smith
; currently implements, giving future bots this pattern for free.
;
; Depends on: Colors.ahk (WaitForPixelSearch, WaitForPixelColor), Images.ahk (WaitForImageCenter, WaitUntilImageGone), Click.ahk (HumanClick, HumanKeyPress), Slots.ahk (WaitForSlotChange), TaskRunner.ahk (ResetPhaseTimer), Context.ahk
; ============================================================

#Requires AutoHotkey v2.0

#Include Colors.ahk
#Include Images.ahk
#Include Click.ahk
#Include Slots.ahk
#Include TaskRunner.ahk
#Include Context.ahk

; Step 1: Find and click a marker.
; marker: {color, tolerance, x1, y1, x2, y2, clickOffsetX, clickOffsetY}
; Returns true on success, false if marker was never found within markerTimeoutMs.
; Calls ResetPhaseTimer internally on success.
DoMarkerAction(ctx, marker, markerTimeoutMs, confirm := "", confirmTimeoutMs := 0, actionKey := "", keySettleMs := 100) {
    if (!WaitForPixelSearch(ctx, &fx, &fy, marker["x1"], marker["y1"], marker["x2"], marker["y2"], marker["color"], marker["tolerance"], markerTimeoutMs))
        return false

    HumanClick(fx + marker["clickOffsetX"], fy + marker["clickOffsetY"], 0, 0, ctx["runMode"])
    ResetPhaseTimer(ctx["runner"])

    ; Step 2 (optional): Wait for a confirmation signal (image or pixel)
    if (confirm != "") {
        if (confirm.Has("file")) {
            if (!WaitForImageCenter(ctx, confirm["x1"], confirm["y1"], confirm["x2"], confirm["y2"], confirm["file"], confirm["w"], confirm["h"], &cx, &cy, confirmTimeoutMs, confirm.Has("options") ? confirm["options"] : ""))
                return false
        } else {
            if (!WaitForPixelColor(ctx, confirm["x"], confirm["y"], confirm["color"], confirm["tolerance"], confirmTimeoutMs))
                return false
        }
    }

    ; Step 3 (optional): Press a key (e.g. Space to confirm a "Make" dialog)
    if (actionKey != "") {
        HumanKeyPress(actionKey)
        Sleep(JitterDelay(keySettleMs))
    }

    return true
}

; The full smelter/cooker/smith-shaped cycle in ONE call:
; 1. Find and click marker
; 2. Wait for confirmation (image or pixel, optional)
; 3. Press a key (optional)
; 4. Block until a slot signature changes
; Returns true on full success, false if any step failed.
DoMarkerActionAndWaitForSlotChange(ctx, marker, markerTimeoutMs, confirm, confirmTimeoutMs, actionKey, keySettleMs, sig, slotTol, slotTimeoutMs, slotConfirmTicks := 3) {
    if (!DoMarkerAction(ctx, marker, markerTimeoutMs, confirm, confirmTimeoutMs, actionKey, keySettleMs))
        return false

    result := WaitForSlotChange(ctx, sig, slotTol, slotTimeoutMs, slotConfirmTicks)
    if (result)
        ResetPhaseTimer(ctx["runner"])

    return result
}
