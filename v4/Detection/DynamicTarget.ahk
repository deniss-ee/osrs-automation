; ============================================================
; DynamicTarget.ahk
; Detection primitives for color/pixel/area queries - the ~95%
; case in the legacy codebase (FindFilledBlock-driven vein,
; rockfall, hopper, bank-chest, marker detection). Every class
; here exposes Find(&x, &y) => bool per the Detection contract,
; backed by a TargetLock for stability debouncing.
; ============================================================

#Requires AutoHotkey v2.0

#Include TargetLock.ahk

; Searches a screen region for a solid block of `color` (within
; `tolerance`), sized at least reqW x reqH, then only reports it
; found once TargetLock confirms it's stable. Direct class analog
; of FindFilledBlock + the per-phase stability-tick loop in legacy.
class ColorBlockTarget {
    __New(region, color, tolerance, reqW, reqH, lock) {
        this._region := region   ; {x1, y1, x2, y2}
        this._color := color
        this._tolerance := tolerance
        this._reqW := reqW
        this._reqH := reqH
        this._lock := lock
    }

    Find(&x, &y) {
        found := this._FindRawBlock(&rawX, &rawY)
        isStable := this._lock.Observe(found, rawX, rawY)
        if (isStable) {
            x := this._lock.LockedX()
            y := this._lock.LockedY()
            return true
        }
        return false
    }

    ; True if the lock was dropped due to the target going missing/moving
    ; away entirely (as opposed to just not-yet-stable) - a Phase uses this
    ; to distinguish "still searching" from "target depleted/dissolved".
    WasLost() => !this._lock.IsLocked() && this._lock._missingTicks > 0

    ; Raw single-tick block search, no stability applied. Backed by the
    ; same iterative stack-based search + cross-check verification as
    ; legacy's FindFilledBlock (implementation ported in Phase 4/5).
    _FindRawBlock(&x, &y) {
        throw Error("ColorBlockTarget._FindRawBlock not yet implemented - ported from lib/Colors.ahk in Phase 5")
    }
}

; Distance-based acquisition variant: finds the nearest matching color
; block to a reference point (e.g. character center), rather than the
; first/only match. Direct analog of lib/Targeting.ahk's nearest-block
; selection used by auto-attack.ahk.
class NearestColorTarget extends ColorBlockTarget {
    __New(region, color, tolerance, reqW, reqH, lock, referencePoint) {
        super.__New(region, color, tolerance, reqW, reqH, lock)
        this._referencePoint := referencePoint   ; {x, y} or a fn () => {x, y}
    }

    _FindRawBlock(&x, &y) {
        throw Error("NearestColorTarget._FindRawBlock not yet implemented - ported from lib/Targeting.ahk in Phase 5")
    }
}
