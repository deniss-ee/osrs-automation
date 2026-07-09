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

    ; Moves the mouse to a point within a width x height box centered on
    ; (centerX, centerY); pass width=0, height=0 (default) for an exact
    ; single pixel. Returns the actual target point via out-params so a
    ; caller inserting a settle delay (via Waiter) before Press() clicks
    ; the same point that was moved to. No Sleep in this method.
    MoveTo(centerX, centerY, width := 0, height := 0, &targetX := 0, &targetY := 0) {
        this._humanizer.Offset(width, height, &dx, &dy)
        targetX := centerX + dx
        targetY := centerY + dy
        MouseMove(targetX, targetY, 5)
    }

    ; Sends the actual click at the mouse's current position - call after
    ; MoveTo (and any settle delay). No Sleep in this method.
    ;
    ; Named Press, not Click, deliberately: a class method sharing a name
    ; with an AHK builtin function (Click) risks the unqualified call
    ; inside this class resolving to the method itself (self-recursion)
    ; instead of the builtin - caught for real when a same-shaped method
    ; named Click() elsewhere in this class called the builtin Click()
    ; and silently failed. Avoided entirely by never naming a method the
    ; same as a builtin it needs to call.
    Press(button := "Left") {
        if (button = "Right")
            Click("Right")
        else
            Click()
    }

    ; Convenience wrapper: MoveTo + Press back-to-back with no settle delay
    ; in between. Use MoveTo/Press directly (with a Waiter.After() call
    ; between them) wherever a settle delay matters - e.g. game clients
    ; that need a moment to register hover/highlight state on the target
    ; before the click itself is sent (legacy's HumanClick did this via a
    ; jittered ~150ms Sleep between MouseMove and Click). Named ClickAt,
    ; not Click, for the same builtin-name-collision reason as Press above.
    ClickAt(centerX, centerY, width := 0, height := 0, button := "Left") {
        this.MoveTo(centerX, centerY, width, height, &targetX, &targetY)
        this.Press(button)
    }

    ; Holds Ctrl for the duration of a click (OSRS "force run" modifier).
    ; Callers insert any needed settle delay around this via Waiter, same
    ; as plain ClickAt.
    ClickAtWithCtrl(centerX, centerY, width := 0, height := 0, button := "Left") {
        Send("{Ctrl down}")
        this.ClickAt(centerX, centerY, width, height, button)
        Send("{Ctrl up}")
    }
}
