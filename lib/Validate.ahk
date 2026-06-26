; ============================================================
;  Validate.ahk
;  Setup-validation accumulator. Lets a script check every
;  calibration value it needs and report ALL problems in one
;  popup, instead of stopping at the first missing F-key.
;
;  Typical use, inside your script's own ValidateSetup():
;
;     ValidateSetup() {
;         v := NewValidator()
;         RequireColor(v, "F1 - ore color", oreColor)
;         RequireCoord(v, "F1 - ore position", oreX, oreY)
;         RequirePath(v, "F4 - to-bank path", toBankPath)
;         return ShowValidationErrors(v)
;     }
;
;  Depends on: Safety.ahk (IsCoordOnScreen, IsRegionValid)
; ============================================================

#Include Safety.ahk

NewValidator() {
    return Map("errors", [])
}

; -1 is this codebase's "not calibrated yet" sentinel for colors.
RequireColor(validator, label, color) {
    if (color = -1)
        validator["errors"].Push(label " is not set")
}

; 0,0 is this codebase's "never calibrated" sentinel for coords.
; A non-zero coord that's off-screen is ALSO flagged - that
; usually means the calibration is stale (e.g. saved on a
; different monitor setup) rather than genuinely unset.
RequireCoord(validator, label, x, y) {
    if (x = 0 && y = 0) {
        validator["errors"].Push(label " is not set")
        return
    }
    if (!IsCoordOnScreen(x, y))
        validator["errors"].Push(label " (" x ", " y ") is off-screen - recalibrate it")
}

RequireRegion(validator, label, x1, y1, x2, y2) {
    if (x1 = 0 && y1 = 0 && x2 = 0 && y2 = 0) {
        validator["errors"].Push(label " is not set")
        return
    }
    if (!IsRegionValid(x1, y1, x2, y2))
        validator["errors"].Push(label " is invalid (off-screen or corners out of order) - recalibrate it")
}

RequirePath(validator, label, steps) {
    if (steps.Length = 0)
        validator["errors"].Push(label " has not been recorded")
}

; Generic "this list needs at least one entry" check - for things
; that aren't a recorded path, e.g. a list of calibrated ore spots.
RequireNonEmpty(validator, label, list) {
    if (list.Length = 0)
        validator["errors"].Push(label " is empty")
}

; Checks that a required asset file (e.g. an ImageSearch reference
; image) actually exists on disk - catches a missing/renamed file at
; startup instead of a confusing failure deep inside a phase later.
RequireFile(validator, label, path) {
    if (!FileExist(path))
        validator["errors"].Push(label " not found at: " path)
}

HasErrors(validator) {
    return validator["errors"].Length > 0
}

; If there are any accumulated errors, joins them into one
; MsgBox and returns false. Otherwise returns true. Designed to
; be the final line of a script's ValidateSetup().
ShowValidationErrors(validator, title := "Setup incomplete") {
    if (!HasErrors(validator))
        return true

    msg := ""
    for err in validator["errors"]
        msg .= "- " err "`n"
    MsgBox(msg, title)
    return false
}
