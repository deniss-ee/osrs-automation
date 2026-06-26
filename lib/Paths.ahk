; ============================================================
;  Paths.ahk
;  One canonical path record/playback engine, replacing the two
;  incompatible formats the old scripts used (miner-3/motherlode
;  stored the first click separately from the rest; smelter-1
;  stored it as a normal step). Here, the first click is simply
;  steps[1] - there is no special case anywhere.
;
;  A "path" is just an Array of step Maps:
;    {x, y, pause, button := "Left", running := 0}
;  `pause` is how long to wait AFTER clicking this step, before
;  doing whatever comes next (the next step's click, or finishing
;  the path if this was the last step). There is no separate
;  "tail delay" - the last step's own pause covers that.
;
;  The wait BEFORE the very first click of a path is a separate,
;  global setting (INITIAL_CLICK_DELAY below) rather than something
;  stored per-path, since it's not really "part of the path" - it's
;  how long you wait before starting to walk it at all.
;
;  Depends on: Click.ahk (HumanClick, JitterDelay)
; ============================================================

#Include Click.ahk

global MIN_RECORDED_DELAY := 50

; Wait before the first click of ANY path playback. Hardcoded to
; 0 for now (click immediately) - might add randomization here
; later instead of per-path storage.
global INITIAL_CLICK_DELAY := 0

; Rounds a duration down to the nearest 50ms, with a 50ms floor.
; Keeps recorded INI files small and avoids storing
; impossible 1ms gaps from a double-click.
RoundDelay(ms) {
    rounded := Floor(ms / 50) * 50
    return Max(MIN_RECORDED_DELAY, rounded)
}

; ---- Recording ----

; Fresh recorder bundle. One of these per path you want to record
; (e.g. one for "to bank", one for "back to mine").
NewPathRecorder() {
    return Map("active", false, "name", "", "lastTick", 0, "steps", [])
}

; Begins recording: clears any previous steps for this recorder
; and starts the inter-click delay clock.
StartRecording(recorder, pathName) {
    recorder["active"] := true
    recorder["name"] := pathName
    recorder["steps"] := []
    recorder["lastTick"] := A_TickCount
}

; Ends recording: the time since the last click becomes that
; click's `pause` (the wait after it, before the path is
; considered finished), then returns the finished steps array.
StopRecording(recorder) {
    if (recorder["steps"].Length > 0) {
        lastStep := recorder["steps"][recorder["steps"].Length]
        lastStep["pause"] := RoundDelay(A_TickCount - recorder["lastTick"])
    }
    recorder["active"] := false
    return recorder["steps"]
}

; Call this from your ~LButton / ~RButton hotkey while
; recorder["active"] is true. The time since the PREVIOUS click
; becomes that previous step's `pause` (the wait after it, before
; this one) - this new step's own pause is set later, either by
; the next click or by StopRecording.
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

; Scales a recorded pause down while running (OSRS's run speed
; roughly compresses travel time to ~53.5% of walk time). Purely
; optional - only call this if you want the legacy run-speed
; behavior; most scripts can just use the recorded pause as-is.
ApplyRunningDelayScale(delayMs, wasRunning, scaleFactor := 0.535) {
    return wasRunning ? Round(delayMs * scaleFactor) : delayMs
}

; Plays back a recorded path: waits INITIAL_CLICK_DELAY, then for
; each step clicks via HumanClick and waits that step's (jittered)
; pause before moving on. Returns true once every step has played;
; this simple version has no abort/timeout support - use
; PlayPathWithGuard for that.
PlayPath(steps, jitter := true, scaleRunDelay := true) {
    if (steps.Length = 0)
        return true

    Sleep(INITIAL_CLICK_DELAY)
    for step in steps {
        wasRunning := (step["running"] = 1)
        HumanClick(step["x"], step["y"], 0, 0, wasRunning, step["button"])

        basePause := scaleRunDelay ? ApplyRunningDelayScale(step["pause"], wasRunning) : step["pause"]
        Sleep(jitter ? JitterDelay(basePause) : basePause)
    }
    return true
}

; Same as PlayPath, but aborts early (returns false) if either:
;   - runningVarGetter() (a zero-arg function returning the
;     script's global "should I still be going" flag) becomes
;     false at any point, or
;   - timeoutMs > 0 and total playback time exceeds it.
; This replaces the scattered "if (!running) return false" checks
; that were copy-pasted into every step of the old scripts.
PlayPathWithGuard(steps, runningVarGetter, timeoutMs := 0) {
    if (steps.Length = 0)
        return true

    startTick := A_TickCount
    Sleep(INITIAL_CLICK_DELAY)

    for step in steps {
        if (!runningVarGetter())
            return false
        if (timeoutMs > 0 && (A_TickCount - startTick) > timeoutMs)
            return false

        wasRunning := (step["running"] = 1)
        HumanClick(step["x"], step["y"], 0, 0, wasRunning, step["button"])

        if (!runningVarGetter())
            return false

        pause := JitterDelay(ApplyRunningDelayScale(step["pause"], wasRunning))
        Sleep(pause)
    }

    return true
}
