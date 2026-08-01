; ============================================================
; v8 micro 02 - HumanGlide movement validation (Act.ahk movement half)
;
; Combines v7 micros 27 (endpoint accuracy + pacing) and 29 (path
; shape / curvature diagnostic) into one micro - both exercise the
; same HumanGlide code, one checks the ends, the other checks the
; middle.
;
; WHAT IT DOES
;   F5  = endless random glides, one log line per move: distance,
;         elapsed ms, landing error (must be 0px every time - the
;         exact-landing snap in HumanGlide guarantees this)
;   F6  = request stop (lands mid-glide - GlideStepDelay checks the
;         stop flag on every changed pixel)
;   F7  = one-shot path trace: glide from current position to a
;         random point, log max perpendicular deviation from the
;         dead-straight line (0 = straight line, HumanGlide's bow
;         should read clearly nonzero, ~4-8% of distance per the
;         raised HUMANMOVE_BOW_MIN/MAX_FRAC)
;   F12 = exit
;
; LIVE CONFIRM:
;   1. F5 - each move is a visible, subtly curved glide, tremor only
;      right at start/end, pace reads as near-instant/expert.
;   2. err=0px on every logged move.
;   3. F6 mid-glide - stops cleanly, no stuck input.
;   4. F7 - maxDev is clearly > 0 and roughly matches the bow
;      fraction range; open logs\02-human-move.log to see the raw
;      numbers if the tooltip scrolls past too fast.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v8.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "02-human-move"

MARGIN_PX := 20
MOVE_INTERVAL_MS := 200

RunHumanMove() {
    Say("human-move: pxPerStep=" HUMANMOVE_PX_PER_STEP " steps=" HUMANMOVE_MIN_STEPS ".." HUMANMOVE_MAX_STEPS
        . " bow=" HUMANMOVE_BOW_MIN_FRAC ".." HUMANMOVE_BOW_MAX_FRAC)
    loop {
        targetX := Random(MARGIN_PX, A_ScreenWidth - MARGIN_PX)
        targetY := Random(MARGIN_PX, A_ScreenHeight - MARGIN_PX)
        MouseGetPos(&fromX, &fromY)
        distPx := Round(Sqrt((targetX - fromX) ** 2 + (targetY - fromY) ** 2))

        t0 := A_TickCount
        HumanMove(targetX, targetY)
        elapsedMs := A_TickCount - t0

        MouseGetPos(&landX, &landY)
        errPx := Round(Sqrt((targetX - landX) ** 2 + (targetY - landY) ** 2))
        Say("human-move: " distPx "px in " elapsedMs "ms, err=" errPx "px")

        Pause(MOVE_INTERVAL_MS)
    }
}

; Mirrors HumanGlide's own math (same globals, same RandTri/MinJerk
; calls) rather than calling HumanGlide itself, since HumanGlide only
; exposes its result via real MouseMove calls - there's no return
; value to intercept sample points from.
TracePath() {
    MouseGetPos(&x0, &y0)
    x1 := Random(MARGIN_PX, A_ScreenWidth - MARGIN_PX)
    y1 := Random(MARGIN_PX, A_ScreenHeight - MARGIN_PX)

    dx := x1 - x0
    dy := y1 - y0
    dist := Sqrt(dx * dx + dy * dy)
    if (dist < 1) {
        Say("path-trace: start=end, skipping")
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

    maxDev := 0
    maxDevT := 0
    loop steps {
        t := A_Index / steps
        p := MinJerk(t, skew)
        bx := (1 - p) ** 2 * x0 + 2 * (1 - p) * p * midX + p ** 2 * x1
        by := (1 - p) ** 2 * y0 + 2 * (1 - p) * p * midY + p ** 2 * y1

        dev := Abs(dy * bx - dx * by + x1 * y0 - y1 * x0) / dist
        if (dev > maxDev) {
            maxDev := dev
            maxDevT := t
        }
    }

    Say("path-trace: " Round(dist) "px straight-line, " steps " steps, "
        . "maxDev=" Round(maxDev, 1) "px at t=" Round(maxDevT, 2)
        . " (straight line would be 0)")

    HumanMove(x1, y1)
}

InstallBotHarness({
    run: RunHumanMove,
    label: "HumanMove",
    extraHotkeys: [
        {key: "F7", handler: TracePath, label: "path-trace"}
    ]
})
