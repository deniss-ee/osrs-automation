; ============================================================
; TargetLock.ahk
; Shared stability-debounce + stall/dissolve detection, used by
; DynamicTarget implementations. Generalizes the tick-counter
; pattern repeated per-phase in legacy (mineStableTicks,
; redStableTicks, etc.): a candidate position is only "locked"
; after N consecutive ticks within a small radius of the last
; seen position, and the lock is dropped if the position goes
; missing or stops changing for too long (the "3 clicks with no
; change -> wait for it to dissolve" behavior from the brief).
; ============================================================

#Requires AutoHotkey v2.0

class TargetLock {
    __New(stableTicksRequired, moveTolerancePx, missingTicksToUnlock := 2) {
        this._stableTicksRequired := stableTicksRequired
        this._moveTolerancePx := moveTolerancePx
        this._missingTicksToUnlock := missingTicksToUnlock
        this._locked := false
        this._lockedX := 0
        this._lockedY := 0
        this._stableTicks := 0
        this._missingTicks := 0
    }

    IsLocked() => this._locked

    LockedX() => this._lockedX

    LockedY() => this._lockedY

    ; Feed one tick's raw find result (found flag + coords). Returns true
    ; once the position has been stable for enough consecutive ticks.
    Observe(found, x, y) {
        if (!found) {
            this._missingTicks += 1
            if (this._missingTicks >= this._missingTicksToUnlock)
                this.Reset()
            return this._locked
        }
        this._missingTicks := 0

        if (this._locked) {
            dx := Abs(x - this._lockedX)
            dy := Abs(y - this._lockedY)
            if (dx <= this._moveTolerancePx && dy <= this._moveTolerancePx)
                return true
            ; Moved too far - re-lock onto the new position from scratch.
            this.Reset()
        }

        if (this._stableTicks = 0 || Abs(x - this._lastX) > this._moveTolerancePx || Abs(y - this._lastY) > this._moveTolerancePx) {
            this._stableTicks := 1
        } else {
            this._stableTicks += 1
        }
        this._lastX := x
        this._lastY := y

        if (this._stableTicks >= this._stableTicksRequired) {
            this._locked := true
            this._lockedX := x
            this._lockedY := y
        }
        return this._locked
    }

    Reset() {
        this._locked := false
        this._stableTicks := 0
        this._missingTicks := 0
    }
}
