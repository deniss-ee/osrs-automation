; ============================================================
; v7 Lib\Act.ahk - mouse movement, click + keypress primitives
;
; All game-input cursor movement goes through HumanMove (standard #29)
; - a fast minimum-jerk glide, F6-interruptible via GlideStepDelay on
; every changed pixel. Because it can throw BotStopped mid-glide,
; ClickAt presses Ctrl/Shift AFTER the glide: a pre-glide press would
; leak a held key on F6 (g_PendingModifierKeys is only set after the
; click, so nothing would ever release it). After the press only
; Sleep+Click run - neither throws - so no leak window remains.
;
; ClickAt releases Ctrl/Shift ASYNCHRONOUSLY (standard #7): holding a
; key costs no real time, so ClickAt returns right after the click and
; a background timer lets go after holdMs. The guard against modifier
; bleed: every action function calls ReleasePendingModifiersNow() at
; its own start, forcing any still-pending release before new input.
;
; preDelayMs/postDelayMs (standard #8) bracket every action, route
; through Pause (F6-interruptible), default 0. settleMs/holdMs stay
; Sleep - tiny mechanical gaps, not scheduling choices. postDelayMs=0
; between ClickAt and PressKey means a true zero gap (load-bearing for
; seller's click-then-immediate-Esc).
; ============================================================

g_PendingModifierKeys := []

; Click-point jitter (standard #29): every click on a fixed UI asset
; (bank buttons, menu items) previously landed the EXACT same pixel
; every time - FindImage always returns the identical center for a
; static asset, so nothing upstream naturally varies it. A real person
; also clicks more sloppily on a BIGGER target than a small one, so
; jitter is PROPORTIONAL to the target's own size, not a flat amount:
; BlockJitterPx(w, h) = CLICK_JITTER_PERCENT of the target's smaller
; dimension, capped at CLICK_JITTER_MAX_PX. Every composite that knows
; its target's real size (TrackAndClick's blockW/blockH, an image's
; w/h, a grid cell's cellW/cellH) computes BlockJitterPx and passes it
; into ClickAt's trailing jitterPx param; the sentinel -1 (ClickAt's
; default) falls back to the flat CLICK_JITTER_MAX_PX for the rare
; call with no size info at all (e.g. a pinned marker point). Applied
; to the point BEFORE the glide (JitterPoint, called from ClickAt and
; RightClickMenuItem's right-click), not after - HumanGlide's
; exact-landing guarantee still holds, it just aims at a slightly
; different spot each time. CLICK_JITTER_MAX_PX raised to 40 (from an
; earlier flat 3, then a hand-tuned 10) so it acts as a safety ceiling
; only - it should essentially never clip a real proportional value in
; this project (largest target is the ~80px deposit button, 25% of
; which is 20px).
CLICK_JITTER_PERCENT := 0.25
CLICK_JITTER_MAX_PX := 40

; Proportional jitter radius for a target of size w x h - the smaller
; dimension governs so jitter never exceeds the target's own tightest
; axis (e.g. a wide-but-short context menu row is bounded by its
; height, not its width).
BlockJitterPx(w, h) {
    global CLICK_JITTER_PERCENT, CLICK_JITTER_MAX_PX
    return Round(Min(Min(w, h) * CLICK_JITTER_PERCENT, CLICK_JITTER_MAX_PX))
}

; jitterPx = -1 (sentinel) falls back to the flat CLICK_JITTER_MAX_PX -
; used when the caller has no target size to compute a proportional
; value from.
JitterPoint(x, y, jitterPx, &jx, &jy) {
    global CLICK_JITTER_MAX_PX
    if (jitterPx = -1)
        jitterPx := CLICK_JITTER_MAX_PX
    jx := x + Random(-jitterPx, jitterPx)
    jy := y + Random(-jitterPx, jitterPx)
}

; Sub-tick pacing (was WindMouseStepDelay - kept, renamed, body
; unchanged): 2026-07-27 postmortem, still true - raising the process
; timer resolution via DllCall("winmm\timeBeginPeriod", "UInt", 1) does
; NOT tighten AHK's own Sleep()/Pause(); a request for Sleep(1..3) was
; live-confirmed to still round up to a full ~15.6ms Windows tick
; regardless. The only way to get real sub-tick precision on this
; system is to not go through Sleep() at all - a QueryPerformanceCounter
; busy-wait. Spinning a core for a few ms, a few dozen times per glide,
; is nothing. Used by HumanGlide's per-step pacing.
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

; Center-weighted random (triangular): mean of two uniforms. Promoted
; from Tools\humanized-mouse.ahk unchanged - human parameter spreads
; cluster around a typical value; a flat uniform spread is itself a
; statistical tell.
RandTri(lo, hi) {
    return (Random(lo, hi) + Random(lo, hi)) / 2
}

; Minimum-jerk position profile (Flash & Hogan) - promoted unchanged
; from Tools\humanized-mouse.ahk. Zero velocity AND acceleration at
; both ends, bell-shaped velocity between; skew warps peak timing
; without disturbing either endpoint.
MinJerk(t, skew) {
    tw := t ** skew
    return 10 * tw ** 3 - 15 * tw ** 4 + 6 * tw ** 5
}

; Tremor weight in [0,1] for path-position t in [0,1] - the INVERSE of
; Tools\humanized-mouse.ahk's original mid-flight-peaked wobble
; (standard #29, 2026-07-30 rewrite): a real expert's hand isn't
; shaking mid-flick, it wavers only leaving rest and settling onto the
; target. Nonzero only within edgeFrac of either end; flat ZERO across
; the whole middle so a fast glide reads as clean and controlled, not
; shaky throughout. d = distance from the nearest end (0 at either
; endpoint, 0.5 at the midpoint); u ramps 1 (at the very end) -> 0 (at
; the edge-band boundary); squaring gives a zero-slope ease into the
; flat zero region, so tremor fades out rather than visibly cutting off.
TremorWeight(t, edgeFrac) {
    d := Min(t, 1 - t)
    if (d >= edgeFrac)
        return 0
    u := 1 - d / edgeFrac
    return u * u
}

; HumanGlide tuning (standard #29, 2026-07-30 rewrite - replaces
; WindMouse). Decision: "expert user who already knows exactly where
; things are, moves almost instantly" - speed is the dominant design
; goal here, small edge-only tremor is cosmetic on top. Worked
; arithmetic (steps = clamp(round(dist/PX_PER_STEP), MIN, MAX), delay
; uniform in [STEP_DELAY_MIN,MAX]ms, avg 3.5ms/step - entirely via
; GlideStepDelay's busy-wait, not Sleep/Pause):
;   100px -> 13 steps -> ~26-65ms (avg ~46ms)
;   240px -> 30 steps (clamp point) -> ~60-150ms (avg ~105ms)
;   500-1500px -> 30 steps (capped) -> ~60-150ms (avg ~105ms) - MAX_STEPS
;   caps SAMPLE COUNT, not step size, so long moves don't get
;   proportionally slower, they just take bigger per-sample jumps.
; This is a conservative upper bound - samples near the eased ends
; often round to the same pixel and get skipped (no delay paid), so
; real elapsed time is normally below this table. The 2026-07-27
; WindMouse tuning saga got bitten hard by NOT doing this arithmetic up
; front before retuning - don't repeat that, redo this table if these
; change.
HUMANMOVE_PX_PER_STEP := 8
HUMANMOVE_MIN_STEPS := 5
HUMANMOVE_MAX_STEPS := 30
HUMANMOVE_STEP_COUNT_JITTER_FRAC := 0.2
HUMANMOVE_STEP_DELAY_MIN_MS := 2
HUMANMOVE_STEP_DELAY_MAX_MS := 5
HUMANMOVE_BOW_MIN_FRAC := 0.04       ; perpendicular arc as a fraction of distance -
HUMANMOVE_BOW_MAX_FRAC := 0.08       ; raised floor (was 0.02/0.05) so EVERY glide
                                      ; reads as a visible curve, never a near-straight
                                      ; line on short/unlucky RandTri rolls - still
                                      ; kept subtle so a low-sample-count fast glide
                                      ; reads as one clean curve, not a polygon
HUMANMOVE_SKEW_MIN := 0.85           ; velocity-profile asymmetry (MinJerk skew) -
HUMANMOVE_SKEW_MAX := 1.15           ; real movements rarely peak exactly midway
HUMANMOVE_TREMOR_PX := 1.5           ; peak wobble, ONLY near start/end (TremorWeight)
HUMANMOVE_TREMOR_EDGE_FRAC := 0.15   ; tremor active in the first/last 15% of the
                                      ; path, flat zero across the middle 70%

; Minimum-jerk glide: current mouse position -> (x1,y1) along a subtly
; bowed arc (promoted/adapted from Tools\humanized-mouse.ahk's Glide -
; standard #29, 2026-07-30 rewrite, replaces WindMouseGlide). No
; ballistic-miss/correction phase here (that lived in the source file's
; own HumanMove, not promoted) - JitterPoint/BlockJitterPx already pick
; a slightly-off aim point before this is ever called, so this is a
; single, fast, precise glide straight to the exact target it's given.
; Consecutive samples that round to the same pixel are skipped (no
; re-sent pixel, no wasted delay). Ends with an exact-landing snap to
; (x1,y1) even if the eased tail stopped short - ClickAt clicks at
; current position, so this is load-bearing. Not called directly by
; anything except HumanMove.
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

; Public entry point: current mouse position -> (x1,y1), one straight
; HumanGlide. No ballistic-miss/correction pass (standard #29,
; 2026-07-30) - the caller (ClickAt/RightClickMenuItem) already picked
; a slightly-off aim point via JitterPoint before calling this, so a
; second, independent "aim error" model here would double-humanize the
; same decision and cost real time for no visual benefit. HumanGlide's
; own exact-landing snap guarantees this always lands precisely on
; (x1,y1). Kept as a thin wrapper (not inlined into HumanGlide) so a
; future cosmetic addition here never needs a call-site change.
HumanMove(x1, y1) {
    HumanGlide(x1, y1)
}

ClickAt(x, y, useCtrl := false, useShift := false, settleMs := 100, holdMs := 100, preDelayMs := 0, postDelayMs := 0, jitterPx := -1) {
    global g_PendingModifierKeys

    if (preDelayMs > 0)
        Pause(preDelayMs)

    ReleasePendingModifiersNow()

    JitterPoint(x, y, jitterPx, &jx, &jy)
    HumanMove(jx, jy)

    if (useCtrl)
        Send("{Ctrl down}")
    if (useShift)
        Send("{Shift down}")

    Sleep(settleMs)
    Click()

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

; Releases any modifiers still held from a previous ClickAt and cancels
; its timer. Fired by the timer after holdMs, and defensively at the
; start of every action function - released at most once either way.
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
