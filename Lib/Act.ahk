; ============================================================
; v8 Lib\Act.ahk - mouse movement, click + keypress primitives
;
; Movement half: ported verbatim from v7\Lib\Act.ahk - HumanGlide is
; a proven minimum-jerk (Flash & Hogan) glide with edge-only tremor,
; tuned for an expert user who already knows exactly where the
; target is. GlideStepDelay's QueryPerformanceCounter busy-wait
; exists because Windows' Sleep()/Pause() rounds any sub-15ms
; request up to a full ~15.6ms tick - confirmed live in v7, not
; re-litigated here.
;
; Click half (this pass, micro 03) - THE HARD GUARANTEE: v7's
; ClickAt took a bare x/y with an optional jitterPx that defaulted
; to a sentinel (-1) meaning "flat CLICK_JITTER_MAX_PX fallback."
; Two v7 call sites fell into that fallback silently (TravelToPoint's
; pinned marker click passed no jitter arg at all; RightClickMenuItem
; fell back when blockW/blockH were omitted) and landed a flat
; +/-40px offset unbounded by the actual target's size - on a small
; marker, that can miss the target's cell entirely.
;
; v8 closes this structurally: ClickAt no longer accepts a bare x/y.
; Every call site must construct a ClickTarget(x, y, w, h) - the
; target's REAL measured size - and JitterInCell mathematically
; cannot produce an offset outside that cell (the +/-25%-of-dimension
; radius is always <= half the cell's own w/h). A caller that thinks
; it's clicking "an arbitrary point" now has to state a size; if it
; doesn't know one, that's a calibration gap, not a Lib default's
; job to paper over. There is no sentinel, no fallback, no size-less
; click path anywhere in v8.
;
; Jitter is also per-axis TRIANGULAR (RandTri) now, not uniform, to
; match every other knob in the movement model (RandTri, MinJerk
; skew, TremorWeight) - v7's uniform-square jitter was the one flat
; distribution left in an otherwise center-weighted design.
; ============================================================

g_PendingModifierKeys := []

; Sub-tick pacing: a QueryPerformanceCounter busy-wait, because
; Sleep()/Pause() cannot deliver real sub-15ms precision on Windows
; (confirmed in v7 standard #29 - raising process timer resolution
; via timeBeginPeriod does NOT tighten AHK's own Sleep()). Spinning
; a core for a few ms, a few dozen times per glide, is nothing.
GlideStepDelay(ms) {
    global g_StopRequested
    static freq := 0
    if (!freq)
        DllCall("QueryPerformanceFrequency", "Int64*", &freq)

    if (g_StopRequested) {
        LogLine("GlideStepDelay: stop flag seen - throwing BotStopped")
        throw BotStopped()
    }

    if (ms > 0) {
        DllCall("QueryPerformanceCounter", "Int64*", &start := 0)
        target := freq * ms // 1000
        loop {
            DllCall("QueryPerformanceCounter", "Int64*", &now := 0)
        } until (now - start >= target)
    }

    if (g_StopRequested) {
        LogLine("GlideStepDelay: stop flag seen after wait - throwing BotStopped")
        throw BotStopped()
    }
}

; Center-weighted random (triangular): mean of two uniforms. Human
; parameter spreads cluster around a typical value; a flat uniform
; spread is itself a statistical tell.
RandTri(lo, hi) {
    return (Random(lo, hi) + Random(lo, hi)) / 2
}

; Minimum-jerk position profile (Flash & Hogan). Zero velocity AND
; acceleration at both ends, bell-shaped velocity between; skew
; warps peak timing without disturbing either endpoint.
MinJerk(t, skew) {
    tw := t ** skew
    return 10 * tw ** 3 - 15 * tw ** 4 + 6 * tw ** 5
}

; Tremor weight in [0,1] for path-position t in [0,1] - a real
; expert's hand isn't shaking mid-flick, it wavers only leaving rest
; and settling onto the target. Nonzero only within edgeFrac of
; either end; flat ZERO across the whole middle.
TremorWeight(t, edgeFrac) {
    d := Min(t, 1 - t)
    if (d >= edgeFrac)
        return 0
    u := 1 - d / edgeFrac
    return u * u
}

; HumanGlide tuning. Decision: "expert user who already knows
; exactly where things are, moves almost instantly" - speed is the
; dominant design goal, small edge-only tremor is cosmetic on top.
; Worked arithmetic (steps = clamp(round(dist/PX_PER_STEP), MIN,
; MAX), delay uniform in [STEP_DELAY_MIN,MAX]ms, avg 3.5ms/step -
; entirely via GlideStepDelay's busy-wait, not Sleep/Pause):
;   100px -> 13 steps -> ~26-65ms (avg ~46ms)
;   240px -> 30 steps (clamp point) -> ~60-150ms (avg ~105ms)
;   500-1500px -> 30 steps (capped) -> ~60-150ms (avg ~105ms) -
;   MAX_STEPS caps SAMPLE COUNT, not step size, so long moves don't
;   get proportionally slower, they just take bigger per-sample jumps.
HUMANMOVE_PX_PER_STEP := 8
HUMANMOVE_MIN_STEPS := 5
HUMANMOVE_MAX_STEPS := 30
HUMANMOVE_STEP_COUNT_JITTER_FRAC := 0.2
HUMANMOVE_STEP_DELAY_MIN_MS := 2
HUMANMOVE_STEP_DELAY_MAX_MS := 5
HUMANMOVE_BOW_MIN_FRAC := 0.04       ; perpendicular arc as a fraction of distance -
HUMANMOVE_BOW_MAX_FRAC := 0.08       ; raised from v7's 0.02/0.05 so EVERY glide
                                      ; reads as a visible curve, never near-straight
HUMANMOVE_SKEW_MIN := 0.85           ; velocity-profile asymmetry (MinJerk skew) -
HUMANMOVE_SKEW_MAX := 1.15           ; real movements rarely peak exactly midway
HUMANMOVE_TREMOR_PX := 1.5           ; peak wobble, ONLY near start/end (TremorWeight)
HUMANMOVE_TREMOR_EDGE_FRAC := 0.15   ; tremor active in the first/last 15% of the
                                      ; path, flat zero across the middle 70%

; Minimum-jerk glide: current mouse position -> (x1,y1) along a
; subtly bowed arc. Consecutive samples that round to the same pixel
; are skipped (no re-sent pixel, no wasted delay). Ends with an
; exact-landing snap to (x1,y1) even if the eased tail stopped short
; - ClickAt clicks at current position, so this is load-bearing.
HumanGlide(x1, y1) {
    global HUMANMOVE_PX_PER_STEP, HUMANMOVE_MIN_STEPS, HUMANMOVE_MAX_STEPS, HUMANMOVE_STEP_COUNT_JITTER_FRAC
    global HUMANMOVE_STEP_DELAY_MIN_MS, HUMANMOVE_STEP_DELAY_MAX_MS
    global HUMANMOVE_BOW_MIN_FRAC, HUMANMOVE_BOW_MAX_FRAC
    global HUMANMOVE_SKEW_MIN, HUMANMOVE_SKEW_MAX
    global HUMANMOVE_TREMOR_PX, HUMANMOVE_TREMOR_EDGE_FRAC

    MouseGetPos(&x0, &y0)
    dx := x1 - x0
    dy := y1 - y0
    dist := Sqrt(dx * dx + dy * dy)
    if (dist < 1) {
        MouseMove(x1, y1, 0)
        return
    }

    bowFrac := RandTri(HUMANMOVE_BOW_MIN_FRAC, HUMANMOVE_BOW_MAX_FRAC)
    bow := dist * bowFrac
    if (Random(0, 1) = 0)
        bow := -bow
    midX := (x0 + x1) / 2 + (-dy / dist) * bow
    midY := (y0 + y1) / 2 + (dx / dist) * bow

    steps := Round(dist / HUMANMOVE_PX_PER_STEP
        * RandTri(1 - HUMANMOVE_STEP_COUNT_JITTER_FRAC, 1 + HUMANMOVE_STEP_COUNT_JITTER_FRAC))
    steps := Max(HUMANMOVE_MIN_STEPS, Min(HUMANMOVE_MAX_STEPS, steps))
    skew := RandTri(HUMANMOVE_SKEW_MIN, HUMANMOVE_SKEW_MAX)

    lastX := "", lastY := ""
    loop steps {
        t := A_Index / steps
        p := MinJerk(t, skew)
        bx := (1 - p) ** 2 * x0 + 2 * (1 - p) * p * midX + p ** 2 * x1
        by := (1 - p) ** 2 * y0 + 2 * (1 - p) * p * midY + p ** 2 * y1

        wobble := HUMANMOVE_TREMOR_PX * TremorWeight(t, HUMANMOVE_TREMOR_EDGE_FRAC)
        px := Round(bx + Random(-wobble, wobble))
        py := Round(by + Random(-wobble, wobble))

        if (px = lastX && py = lastY)
            continue
        MouseMove(px, py, 0)
        lastX := px
        lastY := py
        GlideStepDelay(Random(HUMANMOVE_STEP_DELAY_MIN_MS, HUMANMOVE_STEP_DELAY_MAX_MS))
    }

    if (lastX != x1 || lastY != y1)
        MouseMove(x1, y1, 0)
}

; Public entry point: current mouse position -> (x1,y1), one
; straight HumanGlide. Kept as a thin wrapper (not inlined into
; HumanGlide) so a future cosmetic addition here never needs a
; call-site change.
HumanMove(x1, y1) {
    HumanGlide(x1, y1)
}

; Jitter spans the central CLICK_JITTER_FRAC of each axis of a
; target cell (0.5 -> +/-25% of that dimension, matching v7's
; magnitude), capped by CLICK_JITTER_MAX_PX as an absolute safety
; ceiling only - for any real target in this project the fractional
; radius is far smaller than the ceiling, so the ceiling should
; essentially never bind.
CLICK_JITTER_FRAC := 0.5
CLICK_JITTER_MAX_PX := 40

; A click target with a REQUIRED, real, measured size - the one
; object every click in v8 is built from. Throws if given a
; degenerate size rather than silently allowing an unbounded click;
; a 1x1 "target" is almost certainly a bug (a marker point that was
; never given its real dimensions), not an intentional pixel-exact
; click.
ClickTarget(x, y, w, h) {
    if (w < 1 || h < 1)
        throw ValueError("ClickTarget: w/h must be >= 1 (got " w "x" h ")")
    return {x: x, y: y, w: w, h: h}
}

; Per-axis triangular jitter, structurally bounded within the cell:
; |jx - t.x| <= t.w/2 * CLICK_JITTER_FRAC <= t.w/2, so the jittered
; point can never leave the target's own bounding box on either
; axis. A wide-but-short target (e.g. a context-menu row) naturally
; gets wide-x/narrow-y jitter instead of a flat circular/square
; spread - more realistic AND strictly in-cell.
JitterInCell(t, &jx, &jy) {
    global CLICK_JITTER_FRAC, CLICK_JITTER_MAX_PX
    rx := Min(t.w / 2 * CLICK_JITTER_FRAC, CLICK_JITTER_MAX_PX)
    ry := Min(t.h / 2 * CLICK_JITTER_FRAC, CLICK_JITTER_MAX_PX)
    jx := Round(t.x + RandTri(-rx, rx))
    jy := Round(t.y + RandTri(-ry, ry))
}

; THE one click prologue in v8 (the button param is why
; RightClickMenuItem no longer needs its own copy of this):
; preDelay -> release any stale modifiers -> jitter within the
; target cell -> glide there -> press modifiers (AFTER the glide,
; standard #29: a pre-glide press would leak a held key if F6 threw
; mid-glide, since g_PendingModifierKeys is only set after the
; click) -> settle -> click -> async modifier release -> postDelay.
ClickAt(target, opts := {}) {
    global g_PendingModifierKeys

    button := Opt(opts, "button", "left")
    useCtrl := Opt(opts, "ctrl", false)
    useShift := Opt(opts, "shift", false)
    settleMs := Opt(opts, "settleMs", 100)
    holdMs := Opt(opts, "holdMs", 100)
    preDelayMs := Opt(opts, "preDelayMs", 0)
    postDelayMs := Opt(opts, "postDelayMs", 0)

    if (preDelayMs > 0)
        Pause(preDelayMs)

    ReleasePendingModifiersNow()

    JitterInCell(target, &jx, &jy)
    HumanMove(jx, jy)

    if (useCtrl)
        Send("{Ctrl down}")
    if (useShift)
        Send("{Shift down}")

    Sleep(settleMs)
    Click(button)

    keysToRelease := []
    if (useCtrl)
        keysToRelease.Push("Ctrl")
    if (useShift)
        keysToRelease.Push("Shift")
    if (keysToRelease.Length > 0) {
        g_PendingModifierKeys := keysToRelease
        SetTimer(ReleasePendingModifiersNow, -holdMs)
    }

    if (postDelayMs > 0)
        Pause(postDelayMs)
}

; Releases any modifiers still held from a previous ClickAt and
; cancels its timer. Fired by the timer after holdMs, and
; defensively at the start of every action function - released at
; most once either way.
ReleasePendingModifiersNow() {
    global g_PendingModifierKeys
    if (g_PendingModifierKeys.Length = 0)
        return
    SetTimer(ReleasePendingModifiersNow, 0)
    keys := g_PendingModifierKeys
    for key in keys
        Send("{" key " up}")
    g_PendingModifierKeys := []
    LogLine("ReleasePendingModifiersNow: released " JoinMsg(keys))
}

; Raw Send-syntax key/chord: "{Space}", "{Esc}", "^+{Right}", ... -
; whatever Send() accepts. Same modifier-bleed guard as ClickAt.
PressKey(keys, preDelayMs := 0, postDelayMs := 0) {
    if (preDelayMs > 0)
        Pause(preDelayMs)

    ReleasePendingModifiersNow()

    Send(keys)
    LogLine("PressKey: sent " keys)

    if (postDelayMs > 0)
        Pause(postDelayMs)
}
