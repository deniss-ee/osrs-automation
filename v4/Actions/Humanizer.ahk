; ============================================================
; Humanizer.ahk
; Pure offset/jitter policy object - no timing role (that's
; Waiter's job entirely, see ruleset 3.4). Replaces legacy's
; global ENABLE_HUMANIZATION/MAX_CLICK_OFFSET_PX/MAX_DELAY_JITTER_MS
; switches (lib/Click.ahk) with instance state so it can be
; toggled/tuned per-bot without a global flag.
; ============================================================

#Requires AutoHotkey v2.0

class Humanizer {
    __New(enabled := false, maxClickOffsetPx := 2, maxDelayJitterMs := 100) {
        this.enabled := enabled
        this.maxClickOffsetPx := maxClickOffsetPx
        this.maxDelayJitterMs := maxDelayJitterMs
    }

    ; Random offset bounded by +/- maxX/2, +/- maxY/2, capped at
    ; +/- maxClickOffsetPx. Returns 0,0 when disabled. Matches
    ; lib/Click.ahk's RandomOffset contract exactly.
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
    ; +/- maxDelayJitterMs, floored at 30ms. Returns baseMs unchanged
    ; when disabled. Matches lib/Click.ahk's JitterDelay contract exactly.
    ; This is the function passed into Waiter's constructor as its jitterFn.
    Jitter(baseMs, jitterPercent := 15) {
        if (!this.enabled)
            return baseMs
        swing := Min(baseMs * jitterPercent / 100, this.maxDelayJitterMs)
        jittered := baseMs + Random(-swing, swing)
        return Max(30, Round(jittered))
    }
}
