; ============================================================
; v7 micro 29 - HumanGlide path-shape proof (not a new bot micro,
; a one-off diagnostic to answer "is this actually curved, not a
; straight line?")
;
; micro 27 already proves landing accuracy (err=0px) and pace, but
; only ever checks start/end - it never looks at the shape of the
; path in between. This script traces every point the real Bezier
; math in Lib\Act.ahk\HumanGlide would visit for one glide, dumps
; them to logs\29-path-trace.csv, and reports max perpendicular
; deviation from the dead-straight start->end line - a true
; straight-line move deviates 0px everywhere, HumanGlide's bow
; should show a clearly nonzero peak (HUMANMOVE_BOW_MIN/MAX_FRAC of
; the total distance, currently 2-5%).
;
; This mirrors HumanGlide's own math (same Lib globals, same
; MinJerk/RandTri calls) rather than calling HumanGlide itself,
; because HumanGlide only exposes its result via real MouseMove
; calls - there's no return value or callback to intercept points
; from without changing production code for a one-off check.
;
; WHAT IT DOES
;   F5  = trace one glide from the current cursor position to a
;         random point, write logs\29-path-trace.csv, report the
;         straight-line distance and the max perpendicular
;         deviation (px) + at what t it occurs
;   F12 = exit
;
; HOW TO READ THE RESULT
;   maxDevPx should be clearly > 0 (a straight line scores 0) and
;   roughly BOW_MIN_FRAC..BOW_MAX_FRAC (2-5%) of distPx. Open the
;   CSV in Excel/a text editor and eyeball the x,y columns - they
;   should trace a shallow arc, not a straight ramp.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v7.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

g_LogName := "29-path-trace"

MARGIN_PX := 20
PLAYBACK_STEP_DELAY_MS := 2   ; slow-motion only, for watching the shape live -
                                ; real HumanGlide pacing (2-5ms/step) is unaffected

TracePath(x0, y0, x1, y1) {
    dx := x1 - x0
    dy := y1 - y0
    dist := Sqrt(dx * dx + dy * dy)

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

    points := []
    points.Push({t: 0, x: x0, y: y0})

    maxDev := 0
    maxDevT := 0
    loop steps {
        t := A_Index / steps
        p := MinJerk(t, skew)
        bx := (1 - p) ** 2 * x0 + 2 * (1 - p) * p * midX + p ** 2 * x1
        by := (1 - p) ** 2 * y0 + 2 * (1 - p) * p * midY + p ** 2 * y1

        wobble := HUMANMOVE_TREMOR_PX * TremorWeight(t, HUMANMOVE_TREMOR_EDGE_FRAC)
        px := Round(bx + Random(-wobble, wobble))
        py := Round(by + Random(-wobble, wobble))
        points.Push({t: t, x: px, y: py})

        ; perpendicular distance from (px,py) to the straight line x0,y0 -> x1,y1
        dev := Abs(dy * px - dx * py + x1 * y0 - y1 * x0) / dist
        if (dev > maxDev) {
            maxDev := dev
            maxDevT := t
        }
    }

    return {points: points, maxDev: maxDev, maxDevT: maxDevT, dist: dist, steps: steps}
}

RunTrace() {
    targetX := Random(MARGIN_PX, A_ScreenWidth - MARGIN_PX)
    targetY := Random(MARGIN_PX, A_ScreenHeight - MARGIN_PX)
    MouseGetPos(&fromX, &fromY)

    result := TracePath(fromX, fromY, targetX, targetY)

    csvPath := A_ScriptDir "\..\logs\29-path-trace.csv"
    f := FileOpen(csvPath, "w")
    f.WriteLine("t,x,y")
    for pt in result.points
        f.WriteLine(Round(pt.t, 3) "," pt.x "," pt.y)
    f.Close()

    Say("path-trace: " Round(result.dist) "px straight-line, " result.steps " steps, "
        . "maxDev=" Round(result.maxDev, 1) "px at t=" Round(result.maxDevT, 2)
        . " (straight line would be maxDev=0) -> " csvPath)

    ; also actually move the cursor along the same shape, slowed down so the
    ; curve is visible to the eye (real HumanGlide is fast - this playback
    ; is not representative of live speed, only of shape)
    for pt in result.points {
        MouseMove(pt.x, pt.y, 0)
        Pause(PLAYBACK_STEP_DELAY_MS)
    }
}

InstallBotHarness({
    run: RunTrace,
    label: "PathTrace"
})
