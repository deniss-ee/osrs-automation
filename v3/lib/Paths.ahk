; ============================================================
; Paths.ahk - v3 REDESIGNED
;
; Record/playback engine for mouse-click walking paths.
; v3 change: Only the guarded form exists (renamed PlayPath).
; The unguarded v2 PlayPath() has no v3 equivalent - the footgun
; is structurally absent.
;
; A "path" is an Array of step Maps: {x, y, pause, button := "Left", running := 0}
; `pause` is the wait AFTER clicking this step, before the next.
; The last step's pause covers the wait before the path is done.
;
; Depends on: Click.ahk (HumanClick, JitterDelay), Context.ahk (CtxIsRunning)
; ============================================================

#Requires AutoHotkey v2.0

#Include Click.ahk
#Include Context.ahk

global MIN_RECORDED_DELAY := 50

; Wait before the first click of ANY path. Currently hardcoded to 0
; (click immediately) - might add randomization here later instead of
; per-path storage.
global INITIAL_CLICK_DELAY := 0

; Rounds a duration down to the nearest 50ms, with a 50ms floor.
; Keeps recorded INI files small and avoids storing impossible 1ms gaps.
RoundDelay(ms) {
    rounded := Floor(ms / 50) * 50
    return Max(MIN_RECORDED_DELAY, rounded)
}

; ---- Recording ----

; Fresh recorder bundle. One of these per path (e.g. one for "to bank",
; one for "back to mine").
NewPathRecorder() {
    return Map("active", false, "name", "", "lastTick", 0, "steps", [])
}

; Begins recording: clears any previous steps and starts the inter-click timer.
StartRecording(recorder, pathName) {
    recorder["active"] := true
    recorder["name"] := pathName
    recorder["steps"] := []
    recorder["lastTick"] := A_TickCount
}

; Ends recording: the time since the last click becomes that click's pause.
StopRecording(recorder) {
    if (recorder["steps"].Length > 0) {
        lastStep := recorder["steps"][recorder["steps"].Length]
        lastStep["pause"] := RoundDelay(A_TickCount - recorder["lastTick"])
    }
    recorder["active"] := false
    return recorder["steps"]
}

; Call this from ~LButton / ~RButton hotkey while recorder["active"] is true.
; The time since the PREVIOUS click becomes that previous step's pause.
RecordClickStep(recorder, x, y, button := "Left", runningFlag := 0) {
    now := A_TickCount
    if (recorder["steps"].Length > 0) {
        prevStep := recorder["steps"][recorder["steps"].Length]
        prevStep["pause"] := RoundDelay(now - recorder["lastTick"])
    }
    recorder["steps"].Push(Map("x", x, "y", y, "pause", 0, "button", button, "running", runningFlag))
    recorder["lastTick"] := now
}

; ---- Playback ----

; Scales a recorded pause down while running (OSRS run speed ~53.5% of walk time).
; Purely optional - only call if needed; most scripts can use the recorded pause as-is.
ApplyRunningDelayScale(delayMs, wasRunning, scaleFactor := 0.535) {
    return wasRunning ? Round(delayMs * scaleFactor) : delayMs
}

; Plays back a recorded path: waits INITIAL_CLICK_DELAY, then for each step
; clicks and waits that step's pause. Aborts immediately (returns false) if
; CtxIsRunning(ctx) becomes false (Stop hotkey pressed) or if timeoutMs > 0
; and total time exceeds it. Returns true on full playback completion.
;
; v3: ctx is required (first param), replaces optional runningVarGetter closure.
PlayPath(ctx, steps, timeoutMs := 0) {
    if (steps.Length = 0)
        return true

    startTick := A_TickCount
    Sleep(INITIAL_CLICK_DELAY)

    for step in steps {
        if (!CtxIsRunning(ctx))
            return false
        if (timeoutMs > 0 && (A_TickCount - startTick) > timeoutMs)
            return false

        wasRunning := (step["running"] = 1)
        HumanClick(step["x"], step["y"], 0, 0, wasRunning, step["button"])

        if (!CtxIsRunning(ctx))
            return false

        pause := JitterDelay(ApplyRunningDelayScale(step["pause"], wasRunning))
        Sleep(pause)
    }

    return true
}
