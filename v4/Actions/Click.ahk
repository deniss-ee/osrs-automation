; ============================================================
; Click.ahk
; Pure click execution - mouse move + click, zero Sleep calls.
; Offset humanization (spatial) is applied here via an injected
; Humanizer; delay humanization (temporal) is NOT this class's
; job - that's applied by the Phase via Waiter calls that wrap
; the Click() call. Legacy's HumanClick fused both concerns into
; one function; v4 splits them per ruleset 3.4.
; ============================================================

#Requires AutoHotkey v2.0

class Clicker {
    __New(humanizer) {
        this._humanizer := humanizer
    }

    ; Clicks within a width x height box centered on (centerX, centerY);
    ; pass width=0, height=0 (default) for an exact single pixel. No Sleep
    ; anywhere in this method - callers wrap it with Waiter.After() calls
    ; for any pre/post settle delay they need.
    Click(centerX, centerY, width := 0, height := 0, button := "Left") {
        this._humanizer.Offset(width, height, &dx, &dy)
        targetX := centerX + dx
        targetY := centerY + dy

        MouseMove(targetX, targetY, 5)
        if (button = "Right")
            Click(targetX, targetY, "Right")
        else
            Click(targetX, targetY)
    }

    ; Holds Ctrl for the duration of a click (OSRS "force run" modifier).
    ; Callers insert any needed settle delay around this via Waiter, same
    ; as plain Click().
    ClickWithCtrl(centerX, centerY, width := 0, height := 0, button := "Left") {
        Send("{Ctrl down}")
        this.Click(centerX, centerY, width, height, button)
        Send("{Ctrl up}")
    }
}
