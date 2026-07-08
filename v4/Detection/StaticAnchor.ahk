; ============================================================
; StaticAnchor.ahk
; Detection primitives for stable UI elements - PNG matches and
; fixed/calibrated coordinates alike. Both expose the same
; Find(&x, &y) / WaitFor(waiter, profile, key) contract so a
; Phase doesn't care which anchor type it's polling against.
; This is the explicit state-validation gate the brief calls
; for before the engine allows the next macro sequence to fire.
; ============================================================

#Requires AutoHotkey v2.0

; PNG-based anchor - direct analog of FindImageCenter/WaitForImageCenter
; from lib/Images.ahk (deposit interface, empty-sack banner, craft dialog).
class ImageAnchor {
    __New(region, imagePath, options := "") {
        this._region := region   ; {x1, y1, x2, y2}
        this._imagePath := imagePath
        this._options := options
    }

    Find(&x, &y) {
        throw Error("ImageAnchor.Find not yet implemented - ported from lib/Images.ahk in Phase 5")
    }

    ; Polls Find() until it succeeds or timeoutMs elapses, sleeping via the
    ; injected Waiter between attempts (never calls Sleep directly itself).
    WaitFor(waiter, profile, pollKey, timeoutMs, &x, &y) {
        startedAt := A_TickCount
        loop {
            if (this.Find(&x, &y))
                return true
            if ((A_TickCount - startedAt) >= timeoutMs)
                return false
            waiter.After(profile, pollKey)
        }
    }
}

; Fixed-coordinate anchor - a known/calibrated screen position (e.g. the
; sack, minimap waypoints) that legacy clicks by convention without a
; search. Modeled as an anchor (not a bare click) so a Phase treats it
; identically to an ImageAnchor via the same contract.
class FixedPointAnchor {
    __New(x, y) {
        this._x := x
        this._y := y
    }

    Find(&x, &y) {
        x := this._x
        y := this._y
        return true
    }

    WaitFor(waiter, profile, pollKey, timeoutMs, &x, &y) {
        return this.Find(&x, &y)
    }
}
