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
#Include ColorSearch.ahk

; Searches a screen region for a solid block of `color` (within
; `tolerance`), sized at least reqW x reqH, tracked via a
; TargetLock. Find(&x, &y) => bool satisfies the plain Detection
; contract (found this tick, at the latest real position - never
; frozen); IsStable()/IsLost() expose the TargetLock's side flags
; for phases that need legacy's exact stability-gated click cadence.
class ColorBlockTarget {
    __New(region, color, tolerance, reqW, reqH, lock) {
        this._region := region   ; {x1, y1, x2, y2}
        this._color := color
        this._tolerance := tolerance
        this._reqW := reqW
        this._reqH := reqH
        this._lock := lock
    }

    ; Plain Detection contract: true if found this tick, with the latest
    ; real coordinates (not a frozen lock point).
    Find(&x, &y) {
        found := this._FindRawBlock(&rawX, &rawY)
        return this._lock.Observe(found, rawX, rawY, &x, &y)
    }

    ; True once the position has been stable for the configured number of
    ; consecutive ticks - legacy uses this to decide "mining" vs "walking"
    ; tooltip text and which click-cadence branch to take, never to stop
    ; tracking the target's real position.
    IsStable() => this._lock.IsStable()

    ; True once the target has gone missing for long enough that the caller
    ; should treat it as depleted/lost and re-search (legacy: resets
    ; mineTargetX/Y to 0 and logs "Lost track of vein or depleted").
    IsLost() => this._lock.IsLost()

    Reset() => this._lock.Reset()

    ; Raw single-tick block search, no stability applied. Direct call into
    ; ColorSearch.FindFilledBlock over this target's own region/color/size.
    _FindRawBlock(&x, &y) {
        return ColorSearch.FindFilledBlock(
            this._region["x1"], this._region["y1"], this._region["x2"], this._region["y2"],
            this._color, this._tolerance, this._reqW, this._reqH, &x, &y)
    }

    ; Re-targets this tracker onto a different color and region without
    ; constructing a new instance - used when MinePhase's acquisition step
    ; locks onto whichever of the light/dark vein colors was found, then
    ; hands tracking off to this same tracker for the narrowed 100x100 box.
    Retarget(region, color) {
        this._region := region
        this._color := color
        this._lock.Reset()
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
