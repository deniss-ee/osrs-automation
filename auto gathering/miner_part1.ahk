
; ============================================================
;  OSRS Miner (Part 1 + Part 2) - AHK 2.0
;  F1 = ore #1 position + color
;  F2 = ore #2 position + color
;  F3 = inventory slot position + default color (empty slot)
;  F4 = start/stop record TO-BANK path
;  F5 = start/stop record BACK-TO-MINE path
;  F6 = Start full miner
;  F7 = Stop miner
;  F8 = Clear saved config
;
;  Config auto-saves to miner_part1.ini next to this script.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

; ---------- Config file ----------
global CONFIG := A_ScriptDir "\miner_part1.ini"

; ---------- Setup state ----------
global ore1X := 0
global ore1Y := 0
global ore1FullColor := -1

global ore2X := 0
global ore2Y := 0
global ore2FullColor := -1

global invX := 0
global invY := 0
global invDefaultColor := -1

global enableRun := false

; ---------- Runtime state ----------
global running := false
global waitingForOre := false
global currentTarget := 0
global targetLockUntil := 0
global ore1MissingStreak := 0
global ore2MissingStreak := 0

; ---------- Recorded paths ----------
global recordingActive := false
global recordingPathName := ""
global lastRecordTick := 0
global toBankPath := []
global backToMinePath := []
global toBankTailDelay := 0
global backToMineTailDelay := 0

; ---------- Tunables ----------
global LOOP_INTERVAL := 150
global COLOR_TOLERANCE := 20
global TARGET_LOCK_MS := 1000
global MISSING_CONFIRM_TICKS := 2

; ---------- Init ----------
Hotkey("~LButton", RecordPathClick, "Off")

; ---------- Load saved config ----------
LoadConfig()

; ============================================================
;  SETUP HOTKEYS
; ============================================================

F1:: {
    global ore1X, ore1Y, ore1FullColor
    MouseGetPos(&ore1X, &ore1Y)
    ore1FullColor := PixelGetColor(ore1X, ore1Y, "RGB")
    SaveConfig()
    ShowTip("F1 set ore #1: " ore1X "," ore1Y " color=" ore1FullColor)
    SetTimer(HideTip, -2000)
}

F2:: {
    global ore2X, ore2Y, ore2FullColor
    MouseGetPos(&ore2X, &ore2Y)
    ore2FullColor := PixelGetColor(ore2X, ore2Y, "RGB")
    SaveConfig()
    ShowTip("F2 set ore #2: " ore2X "," ore2Y " color=" ore2FullColor)
    SetTimer(HideTip, -2000)
}

F3:: {
    global invX, invY, invDefaultColor
    MouseGetPos(&invX, &invY)
    invDefaultColor := PixelGetColor(invX, invY, "RGB")
    SaveConfig()
    ShowTip("F3 set inventory slot: " invX "," invY " color=" invDefaultColor)
    SetTimer(HideTip, -2000)
}

F4:: {
    TogglePathRecording("toBank")
}

F5:: {
    TogglePathRecording("backToMine")
}

^r:: {
    global enableRun
    enableRun := !enableRun
    status := enableRun ? "ENABLED" : "DISABLED"
    ShowTip("Run mode " status)
    SetTimer(HideTip, -1500)
}

F6:: {
    global running, waitingForOre, currentTarget, recordingActive

    if (!ValidateSetup())
        return

    if (recordingActive) {
        MsgBox("Stop path recording first (F4/F5).", "Recording active", 48)
        return
    }

    running := true
    waitingForOre := false
    currentTarget := 0

    ShowTip("Running full miner")
    SetTimer(HideTip, -1500)
    SetTimer(MainLoop, LOOP_INTERVAL)
}

F7:: {
    StopMining("Stopped")
}

F8:: {
    global CONFIG
    if FileExist(CONFIG)
        FileDelete(CONFIG)
    Reload()
}

; ============================================================
;  CONFIG SAVE / LOAD
; ============================================================

SaveConfig() {
    global CONFIG
    global ore1X, ore1Y, ore1FullColor
    global ore2X, ore2Y, ore2FullColor
    global invX, invY, invDefaultColor
    global enableRun
    global toBankPath, backToMinePath
    global toBankTailDelay, backToMineTailDelay

    IniWrite(ore1X,         CONFIG, "Ore1", "x")
    IniWrite(ore1Y,         CONFIG, "Ore1", "y")
    IniWrite(ore1FullColor, CONFIG, "Ore1", "color")

    IniWrite(ore2X,         CONFIG, "Ore2", "x")
    IniWrite(ore2Y,         CONFIG, "Ore2", "y")
    IniWrite(ore2FullColor, CONFIG, "Ore2", "color")

    IniWrite(invX,              CONFIG, "Inv", "x")
    IniWrite(invY,              CONFIG, "Inv", "y")
    IniWrite(invDefaultColor,   CONFIG, "Inv", "color")

    IniWrite(enableRun,     CONFIG, "Run", "enabled")

    SavePathToIni("ToBank", toBankPath)
    SavePathToIni("BackToMine", backToMinePath)

    IniWrite(toBankTailDelay,   CONFIG, "ToBank", "tail_delay")
    IniWrite(backToMineTailDelay, CONFIG, "BackToMine", "tail_delay")
}

SavePathToIni(section, path) {
    global CONFIG
    IniWrite(path.Length, CONFIG, section, "count")

    i := 1
    for _, step in path {
        IniWrite(step["x"],     CONFIG, section, "step" i "_x")
        IniWrite(step["y"],     CONFIG, section, "step" i "_y")
        IniWrite(step["delay"], CONFIG, section, "step" i "_delay")
        i += 1
    }
}

LoadConfig() {
    global CONFIG
    global ore1X, ore1Y, ore1FullColor
    global ore2X, ore2Y, ore2FullColor
    global invX, invY, invDefaultColor
    global enableRun
    global toBankPath, backToMinePath
    global toBankTailDelay, backToMineTailDelay

    if !FileExist(CONFIG)
        return

    ore1X         := Integer(IniRead(CONFIG, "Ore1", "x", 0))
    ore1Y         := Integer(IniRead(CONFIG, "Ore1", "y", 0))
    ore1FullColor := Integer(IniRead(CONFIG, "Ore1", "color", -1))

    ore2X         := Integer(IniRead(CONFIG, "Ore2", "x", 0))
    ore2Y         := Integer(IniRead(CONFIG, "Ore2", "y", 0))
    ore2FullColor := Integer(IniRead(CONFIG, "Ore2", "color", -1))

    invX              := Integer(IniRead(CONFIG, "Inv", "x", 0))
    invY              := Integer(IniRead(CONFIG, "Inv", "y", 0))
    invDefaultColor   := Integer(IniRead(CONFIG, "Inv", "color", -1))

    enableRun := Integer(IniRead(CONFIG, "Run", "enabled", 0))

    toBankPath := LoadPathFromIni("ToBank")
    backToMinePath := LoadPathFromIni("BackToMine")
    toBankTailDelay := Integer(IniRead(CONFIG, "ToBank", "tail_delay", 0))
    backToMineTailDelay := Integer(IniRead(CONFIG, "BackToMine", "tail_delay", 0))

    ShowTip("Loaded saved miner config")
    SetTimer(HideTip, -1500)
}

LoadPathFromIni(section) {
    global CONFIG

    path := []
    count := Integer(IniRead(CONFIG, section, "count", 0))
    i := 1
    while (i <= count) {
        x := Integer(IniRead(CONFIG, section, "step" i "_x", 0))
        y := Integer(IniRead(CONFIG, section, "step" i "_y", 0))
        d := Integer(IniRead(CONFIG, section, "step" i "_delay", 250))

        if (x != 0 || y != 0)
            path.Push(Map("x", x, "y", y, "delay", d))

        i += 1
    }

    return path
}

; ============================================================
;  VALIDATION
; ============================================================

ValidateSetup() {
    global ore1FullColor, ore2FullColor, invDefaultColor
    global toBankPath, backToMinePath

    msg := ""
    if (ore1FullColor = -1)
        msg .= "F1 - ore #1 position + color`n"
    if (ore2FullColor = -1)
        msg .= "F2 - ore #2 position + color`n"
    if (invDefaultColor = -1)
        msg .= "F3 - inventory slot`n"
    if (toBankPath.Length = 0)
        msg .= "F4 - record TO-BANK path`n"
    if (backToMinePath.Length = 0)
        msg .= "F5 - record BACK-TO-MINE path`n"

    if (msg != "") {
        MsgBox("Missing setup:`n" msg, "Setup incomplete", 48)
        return false
    }

    return true
}

; ============================================================
;  PART 1: MINING LOOP
; ============================================================

MainLoop() {
    global running, waitingForOre, currentTarget, targetLockUntil
    global ore1MissingStreak, ore2MissingStreak
    global ore1X, ore1Y, ore1FullColor
    global ore2X, ore2Y, ore2FullColor
    global COLOR_TOLERANCE, TARGET_LOCK_MS, MISSING_CONFIRM_TICKS

    if (!running)
        return

    ; Step 1: inventory full check first.
    if (IsInventoryFull()) {
        waitingForOre := false
        currentTarget := 0
        targetLockUntil := 0
        ore1MissingStreak := 0
        ore2MissingStreak := 0
        ShowTip("Inventory full - going to bank")
        SetTimer(MainLoop, 0)
        GoBankAndReturn()
        return
    }

    ore1Ready := ColorClose(PixelGetColor(ore1X, ore1Y, "RGB"), ore1FullColor, COLOR_TOLERANCE)
    ore2Ready := ColorClose(PixelGetColor(ore2X, ore2Y, "RGB"), ore2FullColor, COLOR_TOLERANCE)

    ; Keep current target stable for a short time to prevent instant flip-flops.
    if (currentTarget = 1) {
        if (ore1Ready) {
            ore1MissingStreak := 0
            waitingForOre := false
            return
        }
        ore1MissingStreak += 1
        if (A_TickCount < targetLockUntil || ore1MissingStreak < MISSING_CONFIRM_TICKS)
            return
        currentTarget := 0
    }

    if (currentTarget = 2) {
        if (ore2Ready) {
            ore2MissingStreak := 0
            waitingForOre := false
            return
        }
        ore2MissingStreak += 1
        if (A_TickCount < targetLockUntil || ore2MissingStreak < MISSING_CONFIRM_TICKS)
            return
        currentTarget := 0
    }

    ; Step 2/3: prioritize ore #1, then fallback to ore #2.
    if (ore1Ready) {
        waitingForOre := false
        currentTarget := 1
        ore1MissingStreak := 0
        ore2MissingStreak := 0
        targetLockUntil := A_TickCount + TARGET_LOCK_MS
        ShowTip("Mining ore #1")
        DoClick(ore1X, ore1Y)
        SetTimer(HideTip, -1000)
        return
    }

    if (ore2Ready) {
        waitingForOre := false
        currentTarget := 2
        ore1MissingStreak := 0
        ore2MissingStreak := 0
        targetLockUntil := A_TickCount + TARGET_LOCK_MS
        ShowTip("Mining ore #2")
        DoClick(ore2X, ore2Y)
        SetTimer(HideTip, -1000)
        return
    }

    ; If both empty, wait for whichever respawns first using the same tolerance-wait style.
    if (!waitingForOre) {
        waitingForOre := true
        currentTarget := 0
        ShowTip("Both ores empty - waiting respawn")
        SetTimer(MainLoop, 0)

        target := WaitForEitherOreTolerance(ore1X, ore1Y, ore1FullColor, ore2X, ore2Y, ore2FullColor, COLOR_TOLERANCE)
        if (!running)
            return

        if (IsInventoryFull()) {
            StopMining("Inventory full")
            return
        }

        if (target = 1) {
            currentTarget := 1
            waitingForOre := false
            ore1MissingStreak := 0
            ore2MissingStreak := 0
            targetLockUntil := A_TickCount + TARGET_LOCK_MS
            ShowTip("Ore #1 respawned - mining")
            DoClick(ore1X, ore1Y)
        } else if (target = 2) {
            currentTarget := 2
            waitingForOre := false
            ore1MissingStreak := 0
            ore2MissingStreak := 0
            targetLockUntil := A_TickCount + TARGET_LOCK_MS
            ShowTip("Ore #2 respawned - mining")
            DoClick(ore2X, ore2Y)
        }

        SetTimer(HideTip, -1200)
        SetTimer(MainLoop, LOOP_INTERVAL)
    }
}

; ============================================================
;  PART 2: BANKING + RETURN (BLOCKING)
; ============================================================

GoBankAndReturn() {
    global running, waitingForOre, currentTarget, targetLockUntil
    global ore1MissingStreak, ore2MissingStreak
    global invX, invY, enableRun

    if (!PlayPath("toBank")) {
        StopMining("Stopped during TO-BANK path")
        return
    }

    if (!running)
        return

    ; Deposit logic copied from woodcutter approach.
    MouseMove(invX, invY, 5)
    Sleep(500)
    Click("Right", invX, invY)
    Sleep(500)
    Click(invX, invY)
    Sleep(500)

    delayMult := enableRun ? 0.55 : 1.0
    if (!PlayPath("backToMine", delayMult, enableRun)) {
        StopMining("Stopped during BACK-TO-MINE path")
        return
    }

    if (!running)
        return

    waitingForOre := true
    currentTarget := 0
    targetLockUntil := 0
    ore1MissingStreak := 0
    ore2MissingStreak := 0
    ShowTip("Back at mine - resuming")
    SetTimer(HideTip, -1200)
    SetTimer(MainLoop, LOOP_INTERVAL)
}

; ============================================================
;  PATH RECORDING / PLAYBACK
; ============================================================

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

PathLabel(pathName) {
    return (pathName = "toBank") ? "TO-BANK" : "BACK-TO-MINE"
}

RoundDelay(ms) {
    rounded := Round(ms / 50) * 50
    return (rounded < 50) ? 50 : rounded
}

; ============================================================
;  HELPERS
; ============================================================

ShowTip(text) {
    ; Fixed tooltip position to avoid covering the cursor/click target.
    x := A_ScreenWidth - 420
    y := 40
    ToolTip(text, x, y)
}

HideTip() {
    ToolTip()
}

StopMining(reason := "Stopped") {
    global running, waitingForOre, currentTarget, recordingActive, targetLockUntil
    global ore1MissingStreak, ore2MissingStreak
    running := false
    waitingForOre := false
    currentTarget := 0
    targetLockUntil := 0
    ore1MissingStreak := 0
    ore2MissingStreak := 0

    if (recordingActive) {
        recordingActive := false
        Hotkey("~LButton", RecordPathClick, "Off")
    }

    SetTimer(MainLoop, 0)
    ShowTip(reason)
    SetTimer(HideTip, -1500)
}

DoClick(x, y, holdCtrl := false) {
    if (holdCtrl) {
        Send("{Ctrl down}")
        Sleep(50)
    }

    MouseMove(x, y, 5)
    Sleep(150)

    if (holdCtrl) {
        Click(x, y)
        Sleep(50)
        Send("{Ctrl up}")
        return
    }

    Click(x, y)
}

IsInventoryFull() {
    global invX, invY, invDefaultColor
    return PixelGetColor(invX, invY, "RGB") != invDefaultColor
}

WaitForEitherOreTolerance(x1, y1, color1, x2, y2, color2, tol) {
    global running
    loop {
        if (!running)
            return 0

        c1 := PixelGetColor(x1, y1, "RGB")
        if (ColorClose(c1, color1, tol))
            return 1

        c2 := PixelGetColor(x2, y2, "RGB")
        if (ColorClose(c2, color2, tol))
            return 2

        Sleep(100)
    }
}

ColorClose(c1, c2, tol) {
    r1 := (c1 >> 16) & 0xFF
    g1 := (c1 >> 8)  & 0xFF
    b1 := c1 & 0xFF

    r2 := (c2 >> 16) & 0xFF
    g2 := (c2 >> 8)  & 0xFF
    b2 := c2 & 0xFF

    return (Abs(r1 - r2) <= tol && Abs(g1 - g2) <= tol && Abs(b1 - b2) <= tol)
}
