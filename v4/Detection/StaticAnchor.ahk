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
    ; imageW/imageH: the PNG's own pixel dimensions, supplied by the caller
    ; (not read from the file at runtime) - AHK's ImageSearch has no way to
    ; query an image's size, and legacy's FindImageCenter takes the same
    ; explicit w/h parameters for exactly this reason.
    __New(region, imagePath, imageW, imageH, options := "") {
        this._region := region   ; {x1, y1, x2, y2}
        this._imagePath := imagePath
        this._imageW := imageW
        this._imageH := imageH
        this._options := options   ; e.g. "*20" for ImageSearch's shade-variation tolerance
    }

    ; ImageSearch returns the match's upper-left corner; converts to the
    ; image's center point, matching legacy's FindImageCenter exactly.
    Find(&x, &y) {
        r := this._region
        pattern := this._options != "" ? this._options " " this._imagePath : this._imagePath
        if (!ImageSearch(&foundX, &foundY, r["x1"], r["y1"], r["x2"], r["y2"], pattern))
            return false
        x := foundX + this._imageW // 2
        y := foundY + this._imageH // 2
        return true
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
