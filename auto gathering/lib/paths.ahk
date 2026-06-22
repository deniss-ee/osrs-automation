; ============================================================
;  paths.ahk - RECORDING AND REPLAYING WALKING ROUTES
; ------------------------------------------------------------
;  ELI5: Instead of programming "walk to the bank" step by step
;  in code, we let YOU walk there once while the bot watches
;  (records) every click you make and how long you waited
;  between clicks. Later, the bot "replays" those exact same
;  clicks at the exact same timing to retrace your steps.
;
;  NEW in this version: every recorded click also remembers
;  whether YOU want the character to be running on that specific
;  click (press F9 to toggle this mid-recording). Combined with
;  stamina.ahk's ShouldRun(), this means you can mark "run this
;  long stretch, walk this short corner" - per coordinate, not
;  one all-or-nothing switch for the whole path.
; ============================================================

#Requires AutoHotkey v2.0

; --------------------------------------------------------------
; PathLabel: turns the internal key ("toBank") into the friendly
; text shown in tooltips/GUI ("TO-BANK"). Tiny helper so we don't
; repeat this if/else everywhere we show a path name to the user.
; --------------------------------------------------------------
PathLabel(pathName) {
    return (pathName = "toBank") ? "TO-BANK" : "BACK-TO-MINE"
}

; --------------------------------------------------------------
; RoundDelay: rounds a millisecond delay to the nearest 50ms.
; ELI5: real human click timing is messy down to the millisecond
; (153ms, 147ms, 161ms...) and storing all that exact noise adds
; nothing useful - rounding keeps the INI file readable and the
; replayed timing close enough to feel natural.
; --------------------------------------------------------------
RoundDelay(ms) {
    rounded := Round(ms / 50) * 50
    return (rounded < 50) ? 50 : rounded
}

; --------------------------------------------------------------
; ToggleRecordRun: bound to F9. While recording a path, pressing
; this flips whether the NEXT clicks you record will be tagged
; "run := true". It only affects clicks recorded AFTER you press
; it - already-recorded steps keep whatever flag they had.
; --------------------------------------------------------------
ToggleRecordRun() {
    global State
    State["recordNextStepRun"] := !State["recordNextStepRun"]
    status := State["recordNextStepRun"] ? "RUN" : "WALK"
    State["statusText"] := "Recording mode: " status " (next clicks)"
}

; --------------------------------------------------------------
; TogglePathRecording: start recording if nothing is recording,
; or stop+save if this same path is already being recorded.
; This mirrors the old script's F4/F5 behavior, just generalized
; to work for any path name.
; --------------------------------------------------------------
TogglePathRecording(pathName, onRecordClick) {
    global State

    if (!State["recordingActive"]) {
        State["recordingActive"] := true
        State["recordingPathName"] := pathName
        State["lastRecordTick"] := A_TickCount
        State["recordNextStepRun"] := false
        State["paths"][pathName] := []

        ; ~LButton means "let the click still reach the game normally,
        ; we're just ALSO listening for it" - the ~ tilde prefix is
        ; AHK's way of saying "don't swallow this key, just notice it".
        Hotkey("~LButton", onRecordClick, "On")
        State["statusText"] := "Recording " PathLabel(pathName) "... click your route, press same hotkey to stop"
        return
    }

    if (State["recordingPathName"] != pathName) {
        State["statusText"] := "Already recording " PathLabel(State["recordingPathName"]) ". Stop that first."
        return
    }

    State["recordingActive"] := false
    Hotkey("~LButton", onRecordClick, "Off")

    tail := 0
    if (State["lastRecordTick"] > 0)
        tail := RoundDelay(A_TickCount - State["lastRecordTick"])
    State["pathTailDelay"][pathName] := tail

    SaveConfig()

    count := State["paths"][pathName].Length
    State["statusText"] := "Saved " PathLabel(pathName) " with " count " steps, tail=" tail "ms"
}

; --------------------------------------------------------------
; RecordPathClick: fired on every left click while recording is
; active. Captures where the click landed and how long it had
; been since the previous click, tagging it with whatever
; run/walk mode is currently toggled (see ToggleRecordRun above).
; --------------------------------------------------------------
RecordPathClick(*) {
    global State
    if (!State["recordingActive"])
        return

    MouseGetPos(&x, &y)
    now := A_TickCount
    delay := now - State["lastRecordTick"]
    if (delay < 50)
        delay := 50

    step := Map("x", x, "y", y, "delay", RoundDelay(delay), "run", State["recordNextStepRun"])
    State["paths"][State["recordingPathName"]].Push(step)
    State["lastRecordTick"] := now

    count := State["paths"][State["recordingPathName"]].Length
    State["statusText"] := "Recording " PathLabel(State["recordingPathName"]) " | step " count
}

; --------------------------------------------------------------
; PlayPath: replays a recorded path. For EVERY step, asks
; stamina.ahk's ShouldRun() whether THIS specific click should be
; done while "running" - if so, we send a Ctrl-click (the in-game
; convention many setups use to force a run-move) and shrink the
; wait time to mimic faster travel; otherwise it's a normal click
; at the originally recorded pace.
;
; Includes the stuck-path failsafe: if total elapsed time blows
; past our rough estimate * pathTimeoutMultiplier, we bail out
; instead of clicking forever (e.g. character stuck on terrain).
; Returns true if it finished, false if stopped/timed-out.
; --------------------------------------------------------------
PlayPath(pathName) {
    global State
    path := State["paths"][pathName]
    tail := State["pathTailDelay"][pathName]

    if (path.Length = 0) {
        State["statusText"] := PathLabel(pathName) " path is empty - nothing to play"
        return false
    }

    estimatedMs := EstimatePathDuration(path, tail)
    timeoutMs := estimatedMs * State["pathTimeoutMultiplier"]
    startTick := A_TickCount

    State["statusText"] := "Playing " PathLabel(pathName) "..."

    for step in path {
        if (!State["running"])
            return false

        if (CheckPanicCorner()) {
            StopMining("Panic corner triggered during path")
            return false
        }

        if (A_TickCount - startTick > timeoutMs) {
            StopMining("Path timeout - possibly stuck (" PathLabel(pathName) ")")
            return false
        }

        runThisStep := ShouldRun(step)
        ; Running covers ground faster, so we shrink the recorded
        ; delay a bit to match - 0.55x mirrors the old script's
        ; fixed run-speed multiplier, now applied per-step instead
        ; of to the whole path.
        stepDelay := runThisStep ? Round(step["delay"] * 0.55) : step["delay"]

        SleepJittered(stepDelay)
        DoAction(step["x"], step["y"], runThisStep ? "ctrlClick" : "click")
    }

    if (tail > 0)
        SleepJittered(tail)

    return true
}
