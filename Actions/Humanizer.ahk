; ============================================================
; Humanizer.ahk
; Pure offset/jitter policy object, tunable per-bot as instance
; state - no timing role, that's Waiter's job entirely.
; ============================================================

#Requires AutoHotkey v2.0

class Humanizer {
    __New(enabled := false, maxClickOffsetPx := 2, maxDelayJitterMs := 100) {
        this.enabled := enabled
        this.maxClickOffsetPx := maxClickOffsetPx
        this.maxDelayJitterMs := maxDelayJitterMs
    }

    ; Random offset bounded by +/- maxX/2, +/- maxY/2, capped at
    ; +/- maxClickOffsetPx. Returns 0,0 when disabled.
    Offset(maxX, maxY, &dx, &dy) {
        if (!this.enabled) {
            dx := 0
            dy := 0
            return
        }
        boundX := Min(maxX / 2, this.maxClickOffsetPx)
        boundY := Min(maxY / 2, this.maxClickOffsetPx)
        dx := (maxX > 0) ? Round(Random(-boundX, boundX)) : 0
        dy := (maxY > 0) ? Round(Random(-boundY, boundY)) : 0
    }

    ; Returns baseMs adjusted by +/- jitterPercent, capped at
    ; +/- maxDelayJitterMs, floored at 30ms. Unchanged when disabled.
    ; Passed into Waiter's constructor as its jitterFn.
    Jitter(baseMs, jitterPercent := 15) {
        if (!this.enabled)
            return baseMs
        swing := Min(baseMs * jitterPercent / 100, this.maxDelayJitterMs)
        jittered := baseMs + Random(-swing, swing)
        return Max(30, Round(jittered))
    }
}
