; ============================================================
; Click.ahk
; Pure click execution - mouse move + click, zero Sleep calls.
; Offset humanization (spatial) is applied here via an injected
; Humanizer; delay humanization (temporal) is the Phase's job via
; Waiter calls wrapping the click.
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
    ; Named Press, not Click: a method sharing a name with an AHK builtin
    ; (Click) can resolve to itself instead of the builtin (self-recursion) -
    ; never name a method the same as a builtin it needs to call.
    Press(button := "Left") {
        if (button = "Right")
            Click("Right")
        else
            Click()
    }

    ; Convenience wrapper: MoveTo + Press back-to-back, no settle delay.
    ; Use MoveTo/Press directly (with a Waiter.After() between them)
    ; wherever a settle delay matters - e.g. letting the client register
    ; hover state before the click fires.
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

    ; The standard settled click every Phase uses: MoveTo -> clickSettle
    ; delay -> Press, optionally wrapped in a held Ctrl (OSRS "force run")
    ; with its own ctrlHoldSettle delay before release. Takes ctx since the
    ; settle delays are Waiter/TimingProfile-driven, not this class's own
    ; state - replaces the identical _Click(ctx,x,y) every Phase used to
    ; hand-roll.
    ClickSettled(ctx, x, y, runMode := false, button := "Left") {
        if (runMode)
            Send("{Ctrl down}")

        this.MoveTo(x, y, 0, 0, &targetX, &targetY)
        ctx.waiter.After(ctx.timing, "clickSettle")
        this.Press(button)

        if (runMode) {
            ctx.waiter.After(ctx.timing, "ctrlHoldSettle")
            Send("{Ctrl up}")
        }
    }
}
