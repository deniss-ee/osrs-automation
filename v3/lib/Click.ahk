; ============================================================
; Click.ahk
; The one click primitive every script should use. Adds a
; small random offset and delay jitter BY DEFAULT (not an
; opt-in flag) - the old scripts clicked the exact same pixel
; every single time with a fixed delay, which is both easy to
; detect and fragile (a single dead/edge pixel breaks the
; whole script). No dependencies on any other lib file.
;
; ENABLE_HUMANIZATION is a single global switch to turn all of
; that off (e.g. while testing, so clicks land on the exact
; calibrated pixel and delays are exact). Flip it back to true
; for normal use - nothing else needs to change.
; ============================================================

#Requires AutoHotkey v2.0

global ENABLE_HUMANIZATION := false

; Hard caps on how far humanization is ever allowed to push a click
; or a delay, regardless of how big a box or base delay a call site
; passes in. Keeps the randomization subtle everywhere by default
; instead of needing every call site to pass small numbers itself.
global MAX_CLICK_OFFSET_PX := 2
global MAX_DELAY_JITTER_MS := 100

; Random offset bounded by +/- maxX/2, +/- maxY/2, but never more
; than +/- MAX_CLICK_OFFSET_PX in either direction - returned via
; the by-ref out params dx/dy. Call like: RandomOffset(72, 64, &dx, &dy)
; Always returns 0,0 while ENABLE_HUMANIZATION is false.
RandomOffset(maxX, maxY, &dx, &dy) {
    global ENABLE_HUMANIZATION, MAX_CLICK_OFFSET_PX
    if (!ENABLE_HUMANIZATION) {
        dx := 0
        dy := 0
        return
    }
    boundX := Min(maxX / 2, MAX_CLICK_OFFSET_PX)
    boundY := Min(maxY / 2, MAX_CLICK_OFFSET_PX)
    dx := (maxX > 0) ? Round(Random(-boundX, boundX)) : 0
    dy := (maxY > 0) ? Round(Random(-boundY, boundY)) : 0
}

; Returns baseMs adjusted by a random +/- jitterPercent, capped at
; +/- MAX_DELAY_JITTER_MS regardless of how large baseMs is, and
; floored at 30ms so jitter never produces a near-zero/negative
; sleep. Returns baseMs unchanged while ENABLE_HUMANIZATION is false.
JitterDelay(baseMs, jitterPercent := 15) {
    global ENABLE_HUMANIZATION, MAX_DELAY_JITTER_MS
    if (!ENABLE_HUMANIZATION)
        return baseMs
    swing := Min(baseMs * jitterPercent / 100, MAX_DELAY_JITTER_MS)
    jittered := baseMs + Random(-swing, swing)
    return Max(30, Round(jittered))
}

; The standard click. Picks a random point within a
; width x height box centered on (centerX, centerY) - pass
; width=0, height=0 (the default) for an exact single pixel,
; e.g. a small calibration target. Optionally holds Ctrl for
; the duration of the click (OSRS's "force run" click modifier).
HumanClick(centerX, centerY, width := 0, height := 0, holdCtrl := false, button := "Left") {
    RandomOffset(width, height, &dx, &dy)
    targetX := centerX + dx
    targetY := centerY + dy

    if (holdCtrl) {
        Send("{Ctrl down}")
        Sleep(JitterDelay(50))
    }

    MouseMove(targetX, targetY, 5)
    Sleep(JitterDelay(150))

    if (button = "Right")
        Click(targetX, targetY, "Right")
    else
        Click(targetX, targetY)

    if (holdCtrl) {
        Sleep(JitterDelay(50))
        Send("{Ctrl up}")
    }
}

; Sends a single named key (e.g. "Space" to confirm a "make X"
; dialog) followed by the same jittered settle pause every click
; already gets, so a keypress isn't an instantly-obvious exception
; to how every other action in a script behaves.
HumanKeyPress(key, delayMs := 150) {
    Send("{" key "}")
    Sleep(JitterDelay(delayMs))
}
