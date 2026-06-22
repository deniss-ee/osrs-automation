; ============================================================
;  paths.ahk - RECORDING AND REPLAYING WALKING ROUTES
; ------------------------------------------------------------
;  ELI5: Instead of programming "walk to the bank" step by step,
;  we let YOU walk there once while the bot watches (records)
;  every click you make and how long you waited between clicks.
;  Later, the bot "replays" those same clicks at the same timing
;  to retrace your steps automatically.
; ============================================================

#Requires AutoHotkey v2.0

; --------------------------------------------------------------
; TogglePathRecording: pressing the path's hotkey (F4 or F5) the
; first time starts recording; pressing it again stops and saves.
; We listen for left-clicks via the "~LButton" hotkey while
; recording is active (the "~" means "let the click still reach
; the game too, don't swallow it - just also notice it").
; --------------------------------------------------------------
TogglePathRecording(pathName) {
    global recordingActive, recordingPathName, lastRecordTick
    global toBankPath, backToMinePath
    global toBankTailDelay, backToMineTailDelay

    if (!recordingActive) {
        recordingActive := true
        recordingPathName := pathName
        lastRecordTick := A_TickCount

        if (pathName = "toBank")
            toBankPath := []
        else
            backToMinePath := []

        if (pathName = "toBank")
            toBankTailDelay := 0
        else
            backToMineTailDelay := 0

        Hotkey("~LButton", RecordPathClick, "On")
        ShowTip("Recording " PathLabel(pathName) "... Click route, press same hotkey to stop")
        return
    }

    if (recordingPathName != pathName) {
        ShowTip("Already recording " PathLabel(recordingPathName) ". Stop that first")
        SetTimer(HideTip, -1800)
        return
    }

    recordingActive := false
    Hotkey("~LButton", RecordPathClick, "Off")

    tail := 0
    if (lastRecordTick > 0)
        tail := RoundDelay(A_TickCount - lastRecordTick)

    if (pathName = "toBank")
        toBankTailDelay := tail
    else
        backToMineTailDelay := tail

    SaveConfig()

    count := (pathName = "toBank") ? toBankPath.Length : backToMinePath.Length
    ShowTip("Saved " PathLabel(pathName) " with " count " steps, tail=" tail "ms")
    SetTimer(HideTip, -1600)
}

; --------------------------------------------------------------
; RecordPathClick: fires on every left click while recording is
; active. Remembers where you clicked and how long it had been
; since your last recorded click (so playback can reproduce the
; same pacing later).
; --------------------------------------------------------------
RecordPathClick(*) {
    global recordingActive, recordingPathName, lastRecordTick
    global toBankPath, backToMinePath

    if (!recordingActive)
        return

    MouseGetPos(&x, &y)
    now := A_TickCount

    delay := now - lastRecordTick
    if (delay < 50)
        delay := 50

    step := Map("x", x, "y", y, "delay", RoundDelay(delay))

    if (recordingPathName = "toBank") {
        toBankPath.Push(step)
        count := toBankPath.Length
    } else {
        backToMinePath.Push(step)
        count := backToMinePath.Length
    }

    lastRecordTick := now
    ShowTip("Recording " PathLabel(recordingPathName) " | step " count)
}

; --------------------------------------------------------------
; PlayPath: replays a recorded path - waits the recorded delay,
; then clicks, for every step. `delayMultiplier` shrinks the wait
; time when run mode is on (faster travel = less waiting between
; clicks), and `useCtrlClick` holds Ctrl during clicks for the
; same reason (this game's force-run shortcut).
; Returns false early if the user presses Stop mid-path.
; --------------------------------------------------------------
PlayPath(pathName, delayMultiplier := 1.0, useCtrlClick := false) {
    global running, toBankPath, backToMinePath
    global toBankTailDelay, backToMineTailDelay

    path := (pathName = "toBank") ? toBankPath : backToMinePath
    tail := (pathName = "toBank") ? toBankTailDelay : backToMineTailDelay
    if (path.Length = 0) {
        ShowTip(PathLabel(pathName) " path empty")
        SetTimer(HideTip, -1500)
        return false
    }

    ShowTip("Playing " PathLabel(pathName) "...")
    for _, step in path {
        if (!running)
            return false

        stepDelay := Round(step["delay"] * delayMultiplier)
        Sleep(stepDelay)
        DoClick(step["x"], step["y"], useCtrlClick)
    }

    if (tail > 0)
        Sleep(Round(tail * delayMultiplier))

    return true
}

; --------------------------------------------------------------
; PathLabel: turns the internal key ("toBank") into the friendly
; text shown in tooltips ("TO-BANK").
; --------------------------------------------------------------
PathLabel(pathName) {
    return (pathName = "toBank") ? "TO-BANK" : "BACK-TO-MINE"
}

; --------------------------------------------------------------
; RoundDelay: rounds a millisecond delay to the nearest 50ms, with
; a 50ms floor. Real human click timing is messy down to the
; millisecond - rounding keeps the INI file readable without
; meaningfully changing how the replay feels.
; --------------------------------------------------------------
RoundDelay(ms) {
    rounded := Round(ms / 50) * 50
    return (rounded < 50) ? 50 : rounded
}
