; ============================================================
; Analyzes a recording from Tools\record-movement.ahk and reports
; real statistics about this user's actual mouse movement - tick
; speed distribution, movement-segment curvature (path length vs
; straight-line distance), and segment duration/distance/speed -
; intended as calibration input for tuning HumanGlide/WanderNear's
; constants (HUMANMOVE_*, WanderNear's step-delay/pxPerStep ranges)
; against real behavior instead of guessed defaults.
;
; This script reports RAW STATISTICS ONLY - it does not compute or
; print "suggested constants." Turning these numbers into actual
; tuning changes needs a human (or Claude) look at the real numbers
; together with how the current defaults feel live; a formula here
; would risk manufacturing false precision.
;
; METHOD
;   A "tick" is the movement between two consecutive recorded samples.
;   A tick is STILL if its distance is under PAUSE_THRESHOLD_PX. A
;   "movement segment" is a maximal run of ticks that isn't broken by
;   PAUSE_MIN_TICKS or more consecutive still ticks in a row (short
;   blips of stillness inside otherwise-continuous motion don't split
;   a segment - only a sustained pause does). For each segment:
;   straight-line distance (start sample to end sample), actual path
;   length (sum of every tick's distance), duration, and speed
;   (straight-line distance / duration) are computed; curvature is
;   path length / straight-line distance (1.0 = perfectly straight,
;   higher = more curved/wandering).
;
; WHAT IT DOES
;   F5 = read INPUT_PATH, print full stats to the log
;   F12 = exit (this is a one-shot analysis, no F6 stop needed)
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\Lib\v8.ahk

CoordMode("ToolTip", "Screen")

g_LogName := "analyze-movement"

; ======= EDIT THESE FOR YOUR TEST =======================================
INPUT_PATH := A_ScriptDir "\..\logs\movement-recording.csv"
PAUSE_THRESHOLD_PX := 3
PAUSE_MIN_TICKS := 5
; ==========================================================================

Stats(arr) {
    if (arr.Length = 0)
        return {min: 0, max: 0, avg: 0, n: 0}
    mn := arr[1], mx := arr[1], sum := 0
    for v in arr {
        sum += v
        if (v < mn)
            mn := v
        if (v > mx)
            mx := v
    }
    return {min: mn, max: mx, avg: sum / arr.Length, n: arr.Length}
}

RunAnalyze() {
    if (!FileExist(INPUT_PATH)) {
        Say("analyze-movement: " INPUT_PATH " not found - run record-movement.ahk first")
        return false
    }

    raw := FileRead(INPUT_PATH)
    lines := StrSplit(raw, "`n", "`r")

    xs := [], ys := [], ts := []
    loop lines.Length {
        if (A_Index = 1)   ; header row
            continue
        line := lines[A_Index]
        if (line = "")
            continue
        parts := StrSplit(line, ",")
        if (parts.Length < 3)
            continue
        ts.Push(Number(parts[1]))
        xs.Push(Number(parts[2]))
        ys.Push(Number(parts[3]))
    }

    n := xs.Length
    if (n < 3) {
        Say("analyze-movement: only " n " usable samples - recording too short or empty")
        return false
    }

    tickDists := []
    loop n - 1 {
        i := A_Index
        dx := xs[i + 1] - xs[i]
        dy := ys[i + 1] - ys[i]
        tickDists.Push(Sqrt(dx * dx + dy * dy))
    }

    segments := []
    segStartTick := 1
    stillRun := 0
    inSegment := false
    loop tickDists.Length {
        i := A_Index
        if (tickDists[i] >= PAUSE_THRESHOLD_PX) {
            if (!inSegment) {
                segStartTick := i
                inSegment := true
            }
            stillRun := 0
        } else {
            stillRun += 1
            if (inSegment && stillRun >= PAUSE_MIN_TICKS) {
                segEndTick := i - stillRun
                if (segEndTick >= segStartTick)
                    segments.Push({startSample: segStartTick, endSample: segEndTick + 1})
                inSegment := false
            }
        }
    }
    if (inSegment)
        segments.Push({startSample: segStartTick, endSample: tickDists.Length + 1})

    ; pause durations: gaps between one segment's end and the next segment's start
    pauseDurations := []
    loop segments.Length - 1 {
        i := A_Index
        gapStartSample := segments[i].endSample
        gapEndSample := segments[i + 1].startSample
        if (gapEndSample > gapStartSample)
            pauseDurations.Push(ts[gapEndSample] - ts[gapStartSample])
    }

    curvatures := [], segDurations := [], segDistances := [], segSpeeds := []
    for seg in segments {
        s := seg.startSample, e := seg.endSample
        if (e <= s)
            continue
        straightDist := Sqrt((xs[e] - xs[s]) ** 2 + (ys[e] - ys[s]) ** 2)
        pathLen := 0
        loop e - s {
            i := s + A_Index - 1
            dx := xs[i + 1] - xs[i], dy := ys[i + 1] - ys[i]
            pathLen += Sqrt(dx * dx + dy * dy)
        }
        durationMs := ts[e] - ts[s]
        if (straightDist < 5 || durationMs <= 0)
            continue
        curvatures.Push(pathLen / straightDist)
        segDurations.Push(durationMs)
        segDistances.Push(straightDist)
        segSpeeds.Push(straightDist / durationMs)
    }

    tickStats := Stats(tickDists)
    curvStats := Stats(curvatures)
    durStats := Stats(segDurations)
    distStats := Stats(segDistances)
    speedStats := Stats(segSpeeds)
    pauseStats := Stats(pauseDurations)

    totalDurationS := Round((ts[n] - ts[1]) / 1000, 1)
    Say("analyze-movement: " n " samples over " totalDurationS "s, " segments.Length " movement segments, " pauseDurations.Length " pauses")

    LogLine("analyze-movement: === per-tick distance (px between consecutive samples) ===")
    LogLine("analyze-movement: min=" Round(tickStats.min, 2) " avg=" Round(tickStats.avg, 2) " max=" Round(tickStats.max, 2) " (n=" tickStats.n ")")

    LogLine("analyze-movement: === segment curvature (path length / straight-line distance, 1.0=dead straight) ===")
    LogLine("analyze-movement: min=" Round(curvStats.min, 3) " avg=" Round(curvStats.avg, 3) " max=" Round(curvStats.max, 3) " (n=" curvStats.n ")")

    LogLine("analyze-movement: === segment duration (ms) ===")
    LogLine("analyze-movement: min=" Round(durStats.min) " avg=" Round(durStats.avg) " max=" Round(durStats.max))

    LogLine("analyze-movement: === segment straight-line distance (px) ===")
    LogLine("analyze-movement: min=" Round(distStats.min) " avg=" Round(distStats.avg) " max=" Round(distStats.max))

    LogLine("analyze-movement: === segment speed (px/ms, straight-line distance / duration) ===")
    LogLine("analyze-movement: min=" Round(speedStats.min, 3) " avg=" Round(speedStats.avg, 3) " max=" Round(speedStats.max, 3))

    LogLine("analyze-movement: === pause duration between segments (ms) ===")
    LogLine("analyze-movement: min=" Round(pauseStats.min) " avg=" Round(pauseStats.avg) " max=" Round(pauseStats.max) " (n=" pauseStats.n ")")

    Say("analyze-movement: DONE - see logs\analyze-movement.log for full stats")
    return true
}

InstallBotHarness({
    run: RunAnalyze,
    label: "analyze-movement"
})
