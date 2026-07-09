; ============================================================
; TargetLock.ahk
; Stability-debounce tracking: the reported position always
; updates to the latest found coordinates (never freezes), while
; IsStable() is a separate flag counting consecutive ticks within
; moveTolerancePx of the previous position - used only to decide
; click cadence, never to stop following a drifting target.
;
; If the target isn't found for missingTicksToUnlock consecutive
; ticks, the stability streak clears, signaling "lost, re-search".
; ============================================================

#Requires AutoHotkey v2.0

class TargetLock {
    __New(stableTicksRequired, moveTolerancePx, missingTicksToUnlock := 1) {
        this._stableTicksRequired := stableTicksRequired
        this._moveTolerancePx := moveTolerancePx
        this._missingTicksToUnlock := missingTicksToUnlock
        this._hasPosition := false
        this._lastX := 0
        this._lastY := 0
        this._stableTicks := 0
        this._missingTicks := 0
    }

    IsStable() => this._stableTicks >= this._stableTicksRequired

    ; True once the target has been missing for missingTicksToUnlock
    ; consecutive ticks - the caller should treat this as "depleted,
    ; search for a new target."
    IsLost() => this._missingTicks >= this._missingTicksToUnlock

    ; Feed one tick's raw find result. Always writes the latest coordinates
    ; via out-params when found=true (never a stale/frozen value).
    Observe(found, x, y, &outX, &outY) {
        if (!found) {
            this._missingTicks += 1
            outX := this._lastX
            outY := this._lastY
            return false
        }
        this._missingTicks := 0

        isStableTick := this._hasPosition
            && Abs(x - this._lastX) <= this._moveTolerancePx
            && Abs(y - this._lastY) <= this._moveTolerancePx

        this._stableTicks := isStableTick ? this._stableTicks + 1 : 0

        this._lastX := x
        this._lastY := y
        this._hasPosition := true

        outX := x
        outY := y
        return true
    }

    Reset() {
        this._hasPosition := false
        this._stableTicks := 0
        this._missingTicks := 0
    }
}
