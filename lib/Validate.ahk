; ============================================================
; Validate.ahk - v3 REDESIGNED
;
; Setup-validation accumulator. Check every calibration value
; needed and report ALL problems in one popup, instead of stopping
; at the first failure.
;
; v3 additions: RequireSlotSignature, RequireTargetRegion for the
; new primitives (Slots.ahk, Targeting.ahk).
;
; Depends on: Safety.ahk (IsCoordOnScreen, IsRegionValid)
; ============================================================

#Requires AutoHotkey v2.0

#Include Safety.ahk

NewValidator() {
    return Map("errors", [])
}

; -1 is the "not calibrated yet" sentinel for colors.
RequireColor(validator, label, color) {
    if (color = -1)
        validator["errors"].Push(label " is not set")
}

; 0,0 is the "never calibrated" sentinel for coords.
; A non-zero coord that's off-screen also flags (stale calibration).
RequireCoord(validator, label, x, y) {
    if (x = 0 && y = 0) {
        validator["errors"].Push(label " is not set")
        return
    }
    if (!IsCoordOnScreen(x, y))
        validator["errors"].Push(label " (" x ", " y ") is off-screen - recalibrate it")
}

; Checks that a region (x1,y1,x2,y2) is properly defined and on-screen.
RequireRegion(validator, label, x1, y1, x2, y2) {
    if (x1 = 0 && y1 = 0 && x2 = 0 && y2 = 0) {
        validator["errors"].Push(label " is not set")
        return
    }
    if (!IsRegionValid(x1, y1, x2, y2))
        validator["errors"].Push(label " is invalid (off-screen or corners out of order) - recalibrate it")
}

; NEW: Checks that a slot signature has been calibrated (has a slot index and points).
RequireSlotSignature(validator, label, sig) {
    if (sig["slot"] = 0 || sig["points"].Length = 0)
        validator["errors"].Push(label " is not calibrated")
}

; NEW: Checks that a target region (for NPC/enemy targeting) is valid.
RequireTargetRegion(validator, label, region) {
    if (region["color"] = -1)
        validator["errors"].Push(label " color is not set")
    if (!IsRegionValid(region["x1"], region["y1"], region["x2"], region["y2"]))
        validator["errors"].Push(label " region is invalid - recalibrate it")
}

; Checks that a recorded path has steps.
RequirePath(validator, label, steps) {
    if (steps.Length = 0)
        validator["errors"].Push(label " has not been recorded")
}

; Generic "this list needs at least one entry" check - for lists that
; aren't recorded paths (e.g. ore spot list, calibrated points).
RequireNonEmpty(validator, label, list) {
    if (list.Length = 0)
        validator["errors"].Push(label " is empty")
}

; Checks that a required asset file (e.g. ImageSearch reference image)
; actually exists on disk - catches missing/renamed files at startup.
RequireFile(validator, label, path) {
    if (!FileExist(path))
        validator["errors"].Push(label " not found at: " path)
}

HasErrors(validator) {
    return validator["errors"].Length > 0
}

; If there are accumulated errors, joins them into one MsgBox and returns false.
; Otherwise returns true. Designed to be the final line of ValidateSetup().
ShowValidationErrors(validator, title := "Setup incomplete") {
    if (!HasErrors(validator))
        return true

    msg := ""
    for err in validator["errors"]
        msg .= "- " err "`n"
    MsgBox(msg, title)
    return false
}
