; ============================================================
; SharedPhases.ahk
; Generic Phase classes reused across bots wherever their shape
; is identical apart from names/keys - not framework primitives
; (those stay in Phase.ahk), but not bot-specific either.
; ============================================================

#Requires AutoHotkey v2.0

#Include Phase.ahk

; ============================================================
; PressAndWaitEmptyPhase - presses a key once to confirm a
; dialog, then waits (the game runs the action on its own) until
; the inventory empties. Used by Firemaking's "burn logs" and
; Smelter's "smelt ore" - identical shape, different key/dialog.
;
; Exit: once inventory is empty, transitions to nextPhaseName.
; ============================================================
class PressAndWaitEmptyPhase extends Phase {
    __New(name, keyAction, key, spaceSettleKey, nextPhaseName) {
        super.__New(name)
        this._keyAction := keyAction
        this._key := key
        this._spaceSettleKey := spaceSettleKey
        this._nextPhaseName := nextPhaseName
    }

    ResetForNewCycle() {
        ; keyPressed is reset by the withdraw phase's per-cycle reset.
    }

    Run(ctx) {
        if (ctx.windowFocus != "" && !ctx.windowFocus.IsActive())
            return this.name

        if (!ctx.Get("keyPressed", false)) {
            this._keyAction.Press(this._key)
            ctx.waiter.After(ctx.timing, this._spaceSettleKey)
            ctx.Set("keyPressed", true)
            ctx.Log(this.name ": Pressed " this._key " to confirm dialog")
            ctx.failsafe.ResetPhaseTimer(ctx)
            return this.name
        }

        if (ctx.inventory.IsEmpty()) {
            ctx.Log(this.name ": Inventory empty. Moving to bank.")
            return this._nextPhaseName
        }

        return this.name
    }
}

; ============================================================
; GoToBankPhase - verifies a fixed-point color marker, clicks
; it, then waits for a bank-open image to appear. Used by
; Firemaking (a pure detection signal, never clicked further)
; and Smelter (the same image is then clicked as deposit-all by
; the phase after this one) - identical up to this point.
;
; Exit: once the bank-open image is found, transitions to
; nextPhaseName.
; ============================================================
class GoToBankPhase extends Phase {
    __New(markerX, markerY, markerW, markerH, markerColor, markerTolerance, searchPaddingPx, reclickCooldownMs, markerWaitTimeoutMs, bankOpenAnchor, bankOpenWaitTimeoutMs, bankOpenPollKey, nextPhaseName, runMode := false) {
        super.__New("goToBank")
        this._markerX := markerX
        this._markerY := markerY
        this._markerW := markerW
        this._markerH := markerH
        this._markerColor := markerColor
        this._markerTolerance := markerTolerance
        this._searchPaddingPx := searchPaddingPx
        this._reclickCooldownMs := reclickCooldownMs
        this._markerWaitTimeoutMs := markerWaitTimeoutMs
        this._bankOpenAnchor := bankOpenAnchor
        this._bankOpenWaitTimeoutMs := bankOpenWaitTimeoutMs
        this._bankOpenPollKey := bankOpenPollKey
        this._nextPhaseName := nextPhaseName
        this._runMode := runMode
    }

    ResetForNewCycle() {
        ; Scratch timestamps are reset by the withdraw phase's per-cycle
        ; reset.
    }

    Run(ctx) {
        if (ctx.windowFocus != "" && !ctx.windowFocus.IsActive())
            return "goToBank"

        if (!ctx.Get("bankMarkerClicked", false)) {
            rx1 := Max(0, this._markerX - this._searchPaddingPx)
            ry1 := Max(0, this._markerY - this._searchPaddingPx)
            rx2 := Min(A_ScreenWidth, this._markerX + this._searchPaddingPx)
            ry2 := Min(A_ScreenHeight, this._markerY + this._searchPaddingPx)

            found := ColorSearch.FindFilledBlock(rx1, ry1, rx2, ry2,
                this._markerColor, this._markerTolerance, this._markerW, this._markerH, &cx, &cy)

            if (!found) {
                waitStartedAt := ctx.Get("bankMarkerWaitStartedAt", 0)
                if (waitStartedAt == 0) {
                    ctx.Set("bankMarkerWaitStartedAt", A_TickCount)
                } else if ((A_TickCount - waitStartedAt) > this._markerWaitTimeoutMs) {
                    ctx.Log("GoToBankPhase: Timed out waiting for the bank marker - stopping")
                    ctx.engine.Stop("Timed out waiting for bank marker")
                    return "goToBank"
                }

                lastClick := ctx.Get("bankMarkerLastClickTime", 0)
                if (lastClick == 0 || (A_TickCount - lastClick) > this._reclickCooldownMs) {
                    ctx.clicker.ClickSettled(ctx, this._markerX, this._markerY, this._runMode)
                    ctx.Set("bankMarkerLastClickTime", A_TickCount)
                    ctx.Log("GoToBankPhase: Clicked bank marker at [" this._markerX ", " this._markerY "]")
                    ctx.failsafe.ResetPhaseTimer(ctx)
                }
                return "goToBank"
            }

            ctx.Log("GoToBankPhase: Found bank marker at [" cx ", " cy "]")
            ctx.clicker.ClickSettled(ctx, cx, cy, this._runMode)
            ctx.Set("bankMarkerClicked", true)
            ctx.failsafe.ResetPhaseTimer(ctx)
        }

        ctx.Log("GoToBankPhase: Waiting for bank interface...")
        if (!this._bankOpenAnchor.WaitFor(ctx.waiter, ctx.timing, this._bankOpenPollKey, this._bankOpenWaitTimeoutMs, &dx, &dy)) {
            ctx.Log("GoToBankPhase: Timed out waiting for bank interface - stopping")
            ctx.engine.Stop("Timed out waiting for bank interface")
            return "goToBank"
        }

        ctx.Log("GoToBankPhase: Bank interface open.")
        return this._nextPhaseName
    }
}
