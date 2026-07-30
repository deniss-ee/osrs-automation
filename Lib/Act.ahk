; ============================================================
; v7 Lib\Act.ahk - mouse movement, click + keypress primitives
;
; All game-input cursor movement goes through WindMouseMove (standard
; #29) - a physics glide, F6-interruptible via Pause on every changed
; pixel. Because it can throw BotStopped mid-glide, ClickAt presses
; Ctrl/Shift AFTER the glide: a pre-glide press would leak a held key
; on F6 (g_PendingModifierKeys is only set after the click, so nothing
; would ever release it). After the press only Sleep+Click run -
; neither throws - so no leak window remains.
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
; RightClickMenuItem's right-click), not after - WindMouseGlide's
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

; ATTEMPTED FIX that made it WORSE (2026-07-27, keeping the postmortem -
; don't redo this): raising the process timer resolution via
; DllCall("winmm\timeBeginPeriod", "UInt", 1) does NOT tighten AHK's
; own Sleep()/Pause() - live-confirmed: bumping WINDMOUSE_STEP_DELAY's
; minimum from 0 to 1ms made every glide slower, not faster, because
; Sleep(1..3) was STILL rounding up to a full ~15.6ms Windows tick
; regardless of timeBeginPeriod, and unlike the old 0..1 range (where
; Sleep(0) was genuinely free ~half the time), the new range never hit
; that free case - so EVERY step started paying the full ~15.6ms tax
; instead of ~half of them. Real fix below: stop going through Sleep()
; entirely for this - a QueryPerformanceCounter busy-wait gives true
; sub-millisecond precision. Spinning a core for 1-3ms, a few dozen
; times per click, is nothing; it's the only way to get real ms-level
; timing on Windows without fighting its scheduler.
WindMouseStepDelay(ms) {
    global g_StopRequested
    static freq := 0
    if (!freq)
        DllCall("QueryPerformanceFrequency", "Int64*", &freq)

    if (g_StopRequested) {
        LogLine("WindMouseStepDelay: stop flag seen - throwing BotStopped")
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
        LogLine("WindMouseStepDelay: stop flag seen after wait - throwing BotStopped")
        throw BotStopped()
    }
}

; WindMouse physics - retuned live 2026-07-27 off the algorithm's
; canonical 9/3/15/12 defaults, which read as too slow AND too straight
; on a real screen. Higher gravity/maxStep means fewer, bigger steps
; (faster overall, since step COUNT - not the physics params - drives
; wall-clock time via WINDMOUSE_STEP_DELAY_*); higher wind means more
; lateral push per step (visible curve, not a straight line).
WINDMOUSE_GRAVITY := 10           ; strength of pull toward the target each step
WINDMOUSE_WIND := 10             ; max random curvature magnitude
WINDMOUSE_MAX_STEP := 15          ; max pixels of velocity per step
WINDMOUSE_TARGET_AREA := 10       ; distance at which wind/step damping engages

; The real speed lever: nothing sets SendMode, so per-step
; MouseMove(...,0) is SendInput-instant and WindMouseStepDelay (the
; spin-wait above, NOT Sleep/Pause) is the ONLY wall-clock pacing - now
; genuinely accurate to the millisecond, so 1-3ms per delayed step is
; the real per-step cost - small enough to stay snappy, large enough to
; still read as a human cadence rather than an instant teleport.
WINDMOUSE_STEP_DELAY_MIN_MS := 1
WINDMOUSE_STEP_DELAY_MAX_MS := 3

; Overshoot-and-correct (standard #29): a real human doesn't always
; land dead-on their first approach - they land a few px off, notice,
; and snap back. WINDMOUSE_OVERSHOOT_CHANCE of moves aim at a random
; point OVERSHOOT_MIN..MAX_PX away from the real target first, pause
; briefly (the "notice" beat), then glide the short remaining distance
; to the exact target. The click itself only ever fires after the
; corrective leg, so this is purely cosmetic - landing is still exact.
WINDMOUSE_OVERSHOOT_CHANCE := 0.35
WINDMOUSE_OVERSHOOT_MIN_PX := 4
WINDMOUSE_OVERSHOOT_MAX_PX := 14
WINDMOUSE_OVERSHOOT_PAUSE_MIN_MS := 30
WINDMOUSE_OVERSHOOT_PAUSE_MAX_MS := 90

; Public entry point: current mouse position -> (x1,y1), with a chance
; of an intentional near-miss + quick correction (see
; WINDMOUSE_OVERSHOOT_* above). The correction leg re-runs the same
; physics glide (WindMouseGlide) over a short distance, so it inherits
; the same F6-interruptibility and exact-landing guarantee.
WindMouseMove(x1, y1) {
    global WINDMOUSE_OVERSHOOT_CHANCE, WINDMOUSE_OVERSHOOT_MIN_PX, WINDMOUSE_OVERSHOOT_MAX_PX
    global WINDMOUSE_OVERSHOOT_PAUSE_MIN_MS, WINDMOUSE_OVERSHOOT_PAUSE_MAX_MS

    if (Random(0.0, 1.0) < WINDMOUSE_OVERSHOOT_CHANCE) {
        angle := Random(0.0, 6.283185307)
        overshootPx := Random(WINDMOUSE_OVERSHOOT_MIN_PX, WINDMOUSE_OVERSHOOT_MAX_PX)
        aimX := Round(x1 + Cos(angle) * overshootPx)
        aimY := Round(y1 + Sin(angle) * overshootPx)
        WindMouseGlide(aimX, aimY)
        Pause(Random(WINDMOUSE_OVERSHOOT_PAUSE_MIN_MS, WINDMOUSE_OVERSHOOT_PAUSE_MAX_MS))
    }
    WindMouseGlide(x1, y1)
}

; WindMouse (BenLand100): current mouse position -> (x1,y1). Gravity
; toward the target plus a wind term damped by 1/sqrt(3) each step and
; re-randomized by 1/sqrt(5) of the remaining distance, so curvature is
; strong early and fades near arrival. Velocity clamps to maxStep
; (itself shrinking inside targetArea) so the cursor decelerates into
; the target. Only moves when the rounded pixel actually changes; ends
; with a snap to the exact target (the loop exits at dist<1, which can
; leave the last sent pixel 1px off - ClickAt clicks at current
; position, so exact landing is load-bearing). Per-step pacing goes
; through WindMouseStepDelay (spin-wait), not Pause/Sleep - see its
; comment for why. Not called directly by anything outside
; WindMouseMove - both the aim leg and the corrective leg of an
; overshoot go through here.
WindMouseGlide(x1, y1) {
    global WINDMOUSE_GRAVITY, WINDMOUSE_WIND, WINDMOUSE_MAX_STEP, WINDMOUSE_TARGET_AREA
    global WINDMOUSE_STEP_DELAY_MIN_MS, WINDMOUSE_STEP_DELAY_MAX_MS

    MouseGetPos(&x, &y)
    vx := 0, vy := 0, wx := 0, wy := 0
    m0 := WINDMOUSE_MAX_STEP
    lastX := Round(x)
    lastY := Round(y)

    loop {
        dx := x1 - x
        dy := y1 - y
        dist := Sqrt(dx * dx + dy * dy)
        if (dist < 1)
            break

        wMag := Min(WINDMOUSE_WIND, dist)
        if (dist >= WINDMOUSE_TARGET_AREA) {
            wx := wx / Sqrt(3) + (Random(0.0, 1.0) * 2 - 1) * wMag / Sqrt(5)
            wy := wy / Sqrt(3) + (Random(0.0, 1.0) * 2 - 1) * wMag / Sqrt(5)
        } else {
            wx := wx / Sqrt(3)
            wy := wy / Sqrt(3)
            if (m0 < 3)
                m0 := Random(0.0, 1.0) * 3 + 3
            else
                m0 := m0 / Sqrt(5)
        }

        vx += wx + WINDMOUSE_GRAVITY * dx / dist
        vy += wy + WINDMOUSE_GRAVITY * dy / dist

        vMag := Sqrt(vx * vx + vy * vy)
        if (vMag > m0) {
            vClip := m0 / 2 + Random(0.0, 1.0) * m0 / 2
            vx := (vx / vMag) * vClip
            vy := (vy / vMag) * vClip
        }

        x += vx
        y += vy

        moveX := Round(x)
        moveY := Round(y)
        if (moveX != lastX || moveY != lastY) {
            MouseMove(moveX, moveY, 0)
            lastX := moveX
            lastY := moveY
            WindMouseStepDelay(Random(WINDMOUSE_STEP_DELAY_MIN_MS, WINDMOUSE_STEP_DELAY_MAX_MS))
        }
    }

    if (lastX != x1 || lastY != y1)
        MouseMove(x1, y1, 0)
}

ClickAt(x, y, useCtrl := false, useShift := false, settleMs := 100, holdMs := 100, preDelayMs := 0, postDelayMs := 0, jitterPx := -1) {
    global g_PendingModifierKeys

    if (preDelayMs > 0)
        Pause(preDelayMs)

    ReleasePendingModifiersNow()

    JitterPoint(x, y, jitterPx, &jx, &jy)
    WindMouseMove(jx, jy)

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
