; ============================================================
; Tools\humanized-mouse.ahk - demo: human-like cursor movement
;
; Standalone demo, not part of Lib\ (single caller so far - no promotion
; to Lib per the promote-on-second-caller rule in PROGRESS.md).
;
; Built on the two-component model of human pointing (Woodworth): a fast
; BALLISTIC submovement that commits before the eye can verify it - so it
; lands ~85-95% of the way, short or occasionally past - then a reaction
; pause, then one or two small CORRECTIVE submovements onto the target.
; Real mouse velocity traces show exactly this: one large bell-shaped
; hump followed by one or two small ones.
;
; That structure is why there's no bolt-on "overshoot" step here anymore:
; overshoot falls out of the primary submovement's aim error for free,
; and the reaction pause + correction is what a real hand does about it.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v7.ahk

CoordMode("Mouse", "Screen")

g_LogName := "humanized-mouse"

; ======= EDIT THESE FOR YOUR TEST ========================================
MOVE_INTERVAL_MS := 350         ; pause after each completed move (demo pacing only)

; --- Per-submovement path shape
PX_PER_STEP := 6                ; average pixels per emitted sample
MIN_STEPS := 6
MAX_STEPS := 55
STEP_COUNT_JITTER_FRAC := 0.2   ; +/- random scale on the raw step count
SKEW_MIN := 0.85                ; velocity-profile asymmetry: <1 peaks earlier
SKEW_MAX := 1.15                ; (real movements rarely peak exactly midway)
BOW_MIN_FRAC := 0.015           ; perpendicular arc as a fraction of distance.
BOW_MAX_FRAC := 0.07            ; Real pointing curves are subtle - a few percent.
TREMOR_PX := 1.2                ; peak off-path wobble, strongest MID-flight

; --- Per-submovement pacing
STEP_DELAY_MIN_MS := 2
STEP_DELAY_MAX_MS := 6
STEP_DELAY_SPEED_MIN := 0.75    ; per-glide multiplier so whole moves vary in pace,
STEP_DELAY_SPEED_MAX := 1.4     ; not just individual steps

; --- Primary (ballistic) submovement aim error
PRIMARY_ERR_MIN_FRAC := 0.04    ; lands this fraction of the distance short...
PRIMARY_ERR_MAX_FRAC := 0.16    ; ...i.e. 84-96% of the way there
PRIMARY_OVERSHOOT_PERCENT := 22 ; ...or, this often, that far PAST it instead
PRIMARY_LATERAL_PX := 6         ; sideways scatter of the landing point

; --- Corrective submovements
MAX_CORRECTIONS := 2
REACTION_MIN_MS := 45           ; visual-feedback delay before a correction
REACTION_MAX_MS := 130
LANDED_PX := 2                  ; close enough - stop correcting
FINAL_APPROACH_PX := 45         ; within this, the next correction goes straight to target
PARTIAL_CORRECTION_MIN := 0.15  ; when still far, a correction covers only part of
PARTIAL_CORRECTION_MAX := 0.40  ; the remaining gap, leaving a smaller one after
; ==========================================================================

; Center-weighted random (triangular): the mean of two uniforms. Human
; parameter spreads cluster around a typical value - a flat uniform spread
; is itself a signature under statistical analysis.
RandTri(lo, hi) {
    return (Random(lo, hi) + Random(lo, hi)) / 2
}

; Minimum-jerk position profile (Flash & Hogan) - the standard model for
; point-to-point human limb movement: zero velocity AND zero acceleration
; at both ends, bell-shaped velocity between. `skew` warps time to shift
; where peak velocity lands without disturbing either endpoint.
MinJerk(t, skew) {
    tw := t ** skew
    return 10 * tw ** 3 - 15 * tw ** 4 + 6 * tw ** 5
}

; ONE submovement: current position -> (x1,y1) along a gently bowed arc
; with a minimum-jerk velocity profile.
;
; Two details that matter for how the END feels:
;   - consecutive samples that round to the SAME pixel are skipped, so the
;     eased tail never sends repeat coordinates (that read as the cursor
;     freezing on arrival - the single biggest "unnatural" artifact);
;   - tremor peaks mid-flight and vanishes at both ends, rather than
;     starting strong and tapering, which made every move begin with a
;     visible twitch.
Glide(x1, y1, bowFrac, tremorPx) {
    MouseGetPos(&x0, &y0)
    dx := x1 - x0
    dy := y1 - y0
    dist := Sqrt(dx * dx + dy * dy)
    if (dist < 1)
        return

    bow := dist * bowFrac
    if (Random(0, 1) = 0)
        bow := -bow
    midX := (x0 + x1) / 2 + (-dy / dist) * bow
    midY := (y0 + y1) / 2 + (dx / dist) * bow

    steps := Round(dist / PX_PER_STEP * RandTri(1 - STEP_COUNT_JITTER_FRAC, 1 + STEP_COUNT_JITTER_FRAC))
    steps := Max(MIN_STEPS, Min(MAX_STEPS, steps))

    skew := RandTri(SKEW_MIN, SKEW_MAX)
    speedMul := RandTri(STEP_DELAY_SPEED_MIN, STEP_DELAY_SPEED_MAX)

    lastX := ""
    lastY := ""
    loop steps {
        t := A_Index / steps
        p := MinJerk(t, skew)
        bx := (1 - p) ** 2 * x0 + 2 * (1 - p) * p * midX + p ** 2 * x1
        by := (1 - p) ** 2 * y0 + 2 * (1 - p) * p * midY + p ** 2 * y1

        wobble := tremorPx * 4 * t * (1 - t)   ; 0 at both ends, peak at midpoint
        px := Round(bx + Random(-wobble, wobble))
        py := Round(by + Random(-wobble, wobble))

        if (px = lastX && py = lastY)
            continue                            ; never re-send the same pixel
        MouseMove(px, py, 0)
        lastX := px
        lastY := py
        Pause(Round(Random(STEP_DELAY_MIN_MS, STEP_DELAY_MAX_MS) * speedMul))
    }
}

; A complete move: one ballistic submovement that deliberately misses,
; then reaction-paused corrections until it's on target.
;
; Lands exactly on (targetX,targetY). Callers wanting a human-looking
; CLICK POINT should randomize the point they pass in - scatter belongs to
; target selection, not to the movement.
HumanMove(targetX, targetY) {
    MouseGetPos(&sx, &sy)
    dx := targetX - sx
    dy := targetY - sy
    dist := Sqrt(dx * dx + dy * dy)
    if (dist < 1)
        return

    ; --- Primary ballistic submovement (open-loop: aims, but misses)
    errFrac := RandTri(PRIMARY_ERR_MIN_FRAC, PRIMARY_ERR_MAX_FRAC)
    if (Random(1, 100) <= PRIMARY_OVERSHOOT_PERCENT)
        errFrac := -errFrac                     ; past the target instead of short
    ux := dx / dist
    uy := dy / dist
    lat := RandTri(-PRIMARY_LATERAL_PX, PRIMARY_LATERAL_PX)
    Glide(targetX - ux * dist * errFrac - uy * lat,
          targetY - uy * dist * errFrac + ux * lat,
          RandTri(BOW_MIN_FRAC, BOW_MAX_FRAC), TREMOR_PX)

    ; --- Corrective submovements, each after a visual-feedback pause
    loop MAX_CORRECTIONS {
        MouseGetPos(&cx, &cy)
        remain := Sqrt((targetX - cx) ** 2 + (targetY - cy) ** 2)
        if (remain <= LANDED_PX)
            break
        Pause(Round(RandTri(REACTION_MIN_MS, REACTION_MAX_MS)))

        if (remain <= FINAL_APPROACH_PX || A_Index = MAX_CORRECTIONS) {
            Glide(targetX, targetY, 0, TREMOR_PX * 0.4)
            break
        }
        f := RandTri(PARTIAL_CORRECTION_MIN, PARTIAL_CORRECTION_MAX)
        Glide(targetX - (targetX - cx) * f, targetY - (targetY - cy) * f,
              RandTri(0, BOW_MIN_FRAC), TREMOR_PX * 0.6)
    }

    MouseMove(targetX, targetY, 0)              ; guarantee exact landing (<=LANDED_PX snap)
}

RunDemo() {
    loop {
        targetX := Random(20, A_ScreenWidth - 20)
        targetY := Random(20, A_ScreenHeight - 20)
        Say("humanized-mouse: moving to " targetX "," targetY)
        HumanMove(targetX, targetY)
        Pause(MOVE_INTERVAL_MS)
    }
}

InstallBotHarness({
    run: RunDemo,
    label: "HumanizedMouse"
})
