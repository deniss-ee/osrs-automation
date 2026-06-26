; ============================================================
;  OSRS Mother Lode Miner (PixelSearch-based) - AHK 2.0
;  F1 = ore search area top-left corner
;  F2 = ore search area bottom-right corner
;  F3 = ore color (bright green)
;  F4 = inventory slot position + default color (empty slot)
;  F5 = bank search area top-left corner
;  F6 = bank search area bottom-right corner
;  F7 = bank color
;  F8 = start/stop record BACK-TO-MINE path
;  F9 = start full miner
;  F10 = stop miner
;  F11 = clear saved config
;  ^r = toggle run mode (per-step flag during recording)
;
;  Uses PixelSearch to find ore within a defined region,
;  then monitors the clicked location for color change (depletion).
;  Loops until inventory full, then banks and returns.
;
;  Config auto-saves to motherlode-miner.ini next to this script.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

; ---------- Config file ----------
global CONFIG := A_ScriptDir "\motherlode-miner.ini"

; ---------- Setup state: Ore search area ----------
global oreSearchX1 := 0
global oreSearchY1 := 0
global oreSearchX2 := 0
global oreSearchY2 := 0

; ---------- Setup state: Ore color ----------
global oreColor := -1

; ---------- Setup state: Bank search area ----------
global bankSearchX1 := 0
global bankSearchY1 := 0
global bankSearchX2 := 0
global bankSearchY2 := 0

; ---------- Setup state: Bank color ----------
global bankColor := -1

; ---------- Setup state: Inventory ----------
global invX := 0
global invY := 0
global invDefaultColor := -1

; ---------- Setup state: Run mode toggle ----------
global enableRun := false

; ---------- Runtime state ----------
global running := false
global mining := false
global currentMiningX := 0
global currentMiningY := 0
global miningStartTime := 0
global currentSpotMissingStreak := 0

; ---------- Recorded paths (BACK-TO-MINE only) ----------
global recordingActive := false
global recordingPathName := ""
global lastRecordTick := 0
global backToMinePath := []
global backToMineTailDelay := 0

; ---------- First-click coords + run flag (BACK-TO-MINE) ----------
global backToMineFirstX := 0
global backToMineFirstY := 0
global backToMineFirstRunning := 0

; ---------- Tunables ----------
global LOOP_INTERVAL := 150
global COLOR_TOLERANCE := 20
global MINING_COLOR_TOLERANCE := 40
global SEARCH_RETRY_INTERVAL := 150
global MINING_CHECK_INTERVAL := 200
global PATH_INITIAL_DELAY := 250
global ORE_DEPLETED_CONFIRM_TICKS := 3

; ---------- Init ----------
Hotkey("~LButton", RecordPathClick, "Off")

; ---------- Load saved config ----------
LoadConfig()

; ============================================================
;  SETUP HOTKEYS
; ============================================================

F1:: {
    global oreSearchX1, oreSearchY1
    MouseGetPos(&oreSearchX1, &oreSearchY1)
    SaveConfig()
    ShowTip("F1 set ore search area top-left: " oreSearchX1 "," oreSearchY1)
    SetTimer(HideTip, -2000)
}

F2:: {
    global oreSearchX2, oreSearchY2
    MouseGetPos(&oreSearchX2, &oreSearchY2)
    SaveConfig()
    ShowTip("F2 set ore search area bottom-right: " oreSearchX2 "," oreSearchY2)
    SetTimer(HideTip, -2000)
}

F3:: {
    global oreColor
    MouseGetPos(&x, &y)
    oreColor := PixelGetColor(x, y, "RGB")
    SaveConfig()
    ShowTip("F3 set ore color: " oreColor " at " x "," y)
    SetTimer(HideTip, -2000)
}

F4:: {
    global invX, invY, invDefaultColor
    MouseGetPos(&invX, &invY)
    invDefaultColor := PixelGetColor(invX, invY, "RGB")
    SaveConfig()
    ShowTip("F4 set inventory slot: " invX "," invY " color=" invDefaultColor)
    SetTimer(HideTip, -2000)
}

F5:: {
    global bankSearchX1, bankSearchY1
    MouseGetPos(&bankSearchX1, &bankSearchY1)
    SaveConfig()
    ShowTip("F5 set bank search area top-left: " bankSearchX1 "," bankSearchY1)
    SetTimer(HideTip, -2000)
}

F6:: {
    global bankSearchX2, bankSearchY2
    MouseGetPos(&bankSearchX2, &bankSearchY2)
    SaveConfig()
    ShowTip("F6 set bank search area bottom-right: " bankSearchX2 "," bankSearchY2)
    SetTimer(HideTip, -2000)
}

F7:: {
    global bankColor
    MouseGetPos(&x, &y)
    bankColor := PixelGetColor(x, y, "RGB")
    SaveConfig()
    ShowTip("F7 set bank color: " bankColor " at " x "," y)
    SetTimer(HideTip, -2000)
}

F8:: {
    TogglePathRecording("backToMine")
}

^r:: {
    global enableRun
    enableRun := !enableRun
    status := enableRun ? "ENABLED" : "DISABLED"
    ShowTip("Run mode " status)
    SetTimer(HideTip, -1500)
}

F9:: {
    global running, mining, recordingActive, currentMiningX, currentMiningY, miningStartTime, currentSpotMissingStreak

    if (!ValidateSetup())
        return

    if (recordingActive) {
        MsgBox("Stop path recording first (F8).", "Recording active", 48)
        return
    }

    running := true
    mining := false
    currentMiningX := 0
    currentMiningY := 0
    miningStartTime := 0
    currentSpotMissingStreak := 0

    ShowTip("Starting mother lode miner")
    SetTimer(HideTip, -1500)
    SetTimer(MainLoop, LOOP_INTERVAL)
}

F10:: {
    StopMining("Stopped")
}

F11:: {
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
    global oreSearchX1, oreSearchY1, oreSearchX2, oreSearchY2
    global oreColor
    global bankSearchX1, bankSearchY1, bankSearchX2, bankSearchY2
    global bankColor
    global invX, invY, invDefaultColor
    global enableRun
    global backToMinePath
    global backToMineTailDelay
    global backToMineFirstX, backToMineFirstY, backToMineFirstRunning

    IniWrite(oreSearchX1, CONFIG, "OreSearchArea", "x1")
    IniWrite(oreSearchY1, CONFIG, "OreSearchArea", "y1")
    IniWrite(oreSearchX2, CONFIG, "OreSearchArea", "x2")
    IniWrite(oreSearchY2, CONFIG, "OreSearchArea", "y2")

    IniWrite(oreColor, CONFIG, "OreColor", "color")

    IniWrite(bankSearchX1, CONFIG, "BankSearchArea", "x1")
    IniWrite(bankSearchY1, CONFIG, "BankSearchArea", "y1")
    IniWrite(bankSearchX2, CONFIG, "BankSearchArea", "x2")
    IniWrite(bankSearchY2, CONFIG, "BankSearchArea", "y2")

    IniWrite(bankColor, CONFIG, "BankColor", "color")

    IniWrite(invX,            CONFIG, "Inv", "x")
    IniWrite(invY,            CONFIG, "Inv", "y")
    IniWrite(invDefaultColor, CONFIG, "Inv", "color")

    IniWrite(enableRun, CONFIG, "Run", "enabled")

    SavePathToIni("BackToMine", backToMinePath, backToMineFirstX, backToMineFirstY, backToMineFirstRunning)

    IniWrite(backToMineTailDelay, CONFIG, "BackToMine", "tail_delay")
}

SavePathToIni(section, path, firstX, firstY, firstRunning) {
    global CONFIG

    IniWrite(firstX,       CONFIG, section, "first_x")
    IniWrite(firstY,       CONFIG, section, "first_y")
    IniWrite(firstRunning, CONFIG, section, "first_running")
    IniWrite(path.Length,  CONFIG, section, "count")

    i := 1
    for _, step in path {
        IniWrite(step["x"],       CONFIG, section, "step" i "_x")
        IniWrite(step["y"],       CONFIG, section, "step" i "_y")
        IniWrite(step["delay"],   CONFIG, section, "step" i "_delay")
        IniWrite(step["running"], CONFIG, section, "step" i "_running")
        i += 1
    }
}

LoadConfig() {
    global CONFIG
    global oreSearchX1, oreSearchY1, oreSearchX2, oreSearchY2
    global oreColor
    global bankSearchX1, bankSearchY1, bankSearchX2, bankSearchY2
    global bankColor
    global invX, invY, invDefaultColor
    global enableRun
    global backToMinePath
    global backToMineTailDelay
    global backToMineFirstX, backToMineFirstY, backToMineFirstRunning

    if !FileExist(CONFIG)
        return

    oreSearchX1 := Integer(IniRead(CONFIG, "OreSearchArea", "x1", 0))
    oreSearchY1 := Integer(IniRead(CONFIG, "OreSearchArea", "y1", 0))
    oreSearchX2 := Integer(IniRead(CONFIG, "OreSearchArea", "x2", 0))
    oreSearchY2 := Integer(IniRead(CONFIG, "OreSearchArea", "y2", 0))

    oreColor := Integer(IniRead(CONFIG, "OreColor", "color", -1))

    bankSearchX1 := Integer(IniRead(CONFIG, "BankSearchArea", "x1", 0))
    bankSearchY1 := Integer(IniRead(CONFIG, "BankSearchArea", "y1", 0))
    bankSearchX2 := Integer(IniRead(CONFIG, "BankSearchArea", "x2", 0))
    bankSearchY2 := Integer(IniRead(CONFIG, "BankSearchArea", "y2", 0))

    bankColor := Integer(IniRead(CONFIG, "BankColor", "color", -1))

    invX            := Integer(IniRead(CONFIG, "Inv", "x", 0))
    invY            := Integer(IniRead(CONFIG, "Inv", "y", 0))
    invDefaultColor := Integer(IniRead(CONFIG, "Inv", "color", -1))

    enableRun := Integer(IniRead(CONFIG, "Run", "enabled", 0))

    backToMineFirstX       := Integer(IniRead(CONFIG, "BackToMine", "first_x",       0))
    backToMineFirstY       := Integer(IniRead(CONFIG, "BackToMine", "first_y",       0))
    backToMineFirstRunning := Integer(IniRead(CONFIG, "BackToMine", "first_running", 0))

    backToMinePath := LoadPathFromIni("BackToMine")

    backToMineTailDelay := Integer(IniRead(CONFIG, "BackToMine", "tail_delay", 0))

    ShowTip("Loaded saved miner config")
    SetTimer(HideTip, -1500)
}

LoadPathFromIni(section) {
    global CONFIG

    path  := []
    count := Integer(IniRead(CONFIG, section, "count", 0))
    i := 1
    while (i <= count) {
        x := Integer(IniRead(CONFIG, section, "step" i "_x",       0))
        y := Integer(IniRead(CONFIG, section, "step" i "_y",       0))
        d := Integer(IniRead(CONFIG, section, "step" i "_delay",   250))
        r := Integer(IniRead(CONFIG, section, "step" i "_running", 0))

        if (x != 0 || y != 0)
            path.Push(Map("x", x, "y", y, "delay", d, "running", r))

        i += 1
    }

    return path
}

; ============================================================
;  VALIDATION
; ============================================================

ValidateSetup() {
    global oreSearchX1, oreSearchX2, oreSearchY1, oreSearchY2, oreColor, invDefaultColor
    global bankSearchX1, bankSearchX2, bankSearchY1, bankSearchY2, bankColor
    global backToMinePath, backToMineFirstX

    msg := ""
    if (oreSearchX1 = 0 || oreSearchY1 = 0)
        msg .= "F1 - ore search area top-left`n"
    if (oreSearchX2 = 0 || oreSearchY2 = 0)
        msg .= "F2 - ore search area bottom-right`n"
    if (oreColor = -1)
        msg .= "F3 - ore color`n"
    if (invDefaultColor = -1)
        msg .= "F4 - inventory slot`n"
    if (bankSearchX1 = 0 || bankSearchY1 = 0)
        msg .= "F5 - bank search area top-left`n"
    if (bankSearchX2 = 0 || bankSearchY2 = 0)
        msg .= "F6 - bank search area bottom-right`n"
    if (bankColor = -1)
        msg .= "F7 - bank color`n"
    if (backToMineFirstX = 0 && backToMinePath.Length = 0)
        msg .= "F8 - record BACK-TO-MINE path`n"

    if (msg != "") {
        MsgBox("Missing setup:`n" msg, "Setup incomplete", 48)
        return false
    }

    return true
}

; ============================================================
;  MAIN MINING LOOP
; ============================================================

MainLoop() {
    global running, mining, currentMiningX, currentMiningY, miningStartTime, currentSpotMissingStreak
    global oreSearchX1, oreSearchY1, oreSearchX2, oreSearchY2, oreColor
    global COLOR_TOLERANCE, MINING_COLOR_TOLERANCE, SEARCH_RETRY_INTERVAL, MINING_CHECK_INTERVAL, ORE_DEPLETED_CONFIRM_TICKS

    if (!running)
        return

    ; Step 1: Check if inventory full.
    if (IsInventoryFull()) {
        mining := false
        currentMiningX := 0
        currentMiningY := 0
        miningStartTime := 0
        currentSpotMissingStreak := 0
        ShowTip("Inventory full - going to bank")
        SetTimer(MainLoop, 0)
        GoBankAndReturn()
        return
    }

    ; Step 2: If mining a location, check for ore depletion.
    if (mining) {
        ; Give the game a moment to animate the ore change after clicking (200ms buffer).
        if (A_TickCount - miningStartTime < 200)
            return

        currentColor := PixelGetColor(currentMiningX, currentMiningY, "RGB")
        if (IsStillOreColor(currentColor, oreColor, MINING_COLOR_TOLERANCE)) {
            ; Ore still present, keep mining.
            currentSpotMissingStreak := 0
            return
        }
        ; Require consecutive non-matches to avoid transient visual flicker.
        currentSpotMissingStreak += 1
        if (currentSpotMissingStreak < ORE_DEPLETED_CONFIRM_TICKS)
            return
        ; Ore depleted, switch to search mode.
        mining := false
        currentMiningX := 0
        currentMiningY := 0
        currentSpotMissingStreak := 0
        ShowTip("Ore depleted - searching for next")
        SetTimer(HideTip, -1000)
        return
    }

    ; Step 3: Not mining, search for ore.
    if (PixelSearch(&foundX, &foundY, oreSearchX1, oreSearchY1, oreSearchX2, oreSearchY2, oreColor, COLOR_TOLERANCE)) {
        ; Found ore, click it and enter mining state.
        currentMiningX := foundX
        currentMiningY := foundY
        mining := true
        miningStartTime := A_TickCount
        currentSpotMissingStreak := 0
        ShowTip("Found ore at " foundX "," foundY " - mining")
        DoClick(foundX, foundY)
        SetTimer(HideTip, -1200)
        return
    }

    ; No ore found, retry search on next loop interval.
    ShowTip("No ore found - retrying")
    SetTimer(HideTip, -1000)
}

; ============================================================
;  BANKING + RETURN (BLOCKING)
; ============================================================

GoBankAndReturn() {
    global running, mining, currentMiningX, currentMiningY, miningStartTime, currentSpotMissingStreak
    global bankSearchX1, bankSearchY1, bankSearchX2, bankSearchY2, bankColor
    global COLOR_TOLERANCE

    ; Step 1: Search for and click the bank.
    ShowTip("Searching for bank...")
    bankFound := false
    attemptCount := 0
    maxAttempts := 20  ; ~3 seconds at 150ms intervals

    while (!bankFound && attemptCount < maxAttempts && running) {
        if (PixelSearch(&bankX, &bankY, bankSearchX1, bankSearchY1, bankSearchX2, bankSearchY2, bankColor, COLOR_TOLERANCE)) {
            bankFound := true
            bankClickX := bankX + 25
            bankClickY := bankY + 25
            ShowTip("Found bank - clicking at " bankClickX "," bankClickY)
            DoClick(bankClickX, bankClickY)
            ; Bank auto-deploys ore after interaction.
            Sleep(10000)
        } else {
            attemptCount += 1
            Sleep(150)
        }
    }

    if (!bankFound) {
        StopMining("Could not find bank")
        return
    }

    if (!running)
        return

    ; Step 2: Play back BACK-TO-MINE path.
    if (!PlayPath("backToMine")) {
        StopMining("Stopped during BACK-TO-MINE path")
        return
    }

    if (!running)
        return

    mining := false
    currentMiningX := 0
    currentMiningY := 0
    miningStartTime := 0
    currentSpotMissingStreak := 0
    ShowTip("Back at mine - resuming")
    SetTimer(HideTip, -1200)
    SetTimer(MainLoop, LOOP_INTERVAL)
}

; ============================================================
;  PATH RECORDING / PLAYBACK
; ============================================================

TogglePathRecording(pathName) {
    global recordingActive, recordingPathName, lastRecordTick
    global backToMinePath
    global backToMineTailDelay
    global backToMineFirstX, backToMineFirstY

    if (!recordingActive) {
        recordingActive := true
        recordingPathName := pathName
        lastRecordTick := A_TickCount

        backToMinePath := []
        backToMineTailDelay := 0
        backToMineFirstX := 0
        backToMineFirstY := 0
        backToMineFirstRunning := 0

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

    backToMineTailDelay := tail

    SaveConfig()

    count := backToMinePath.Length
    ShowTip("Saved " PathLabel(pathName) " with " count " steps (+ first click), tail=" tail "ms")
    SetTimer(HideTip, -1600)
}

RecordPathClick(*) {
    global recordingActive, recordingPathName, lastRecordTick
    global backToMinePath
    global backToMineFirstX, backToMineFirstY, backToMineFirstRunning
    global enableRun

    if (!recordingActive)
        return

    MouseGetPos(&x, &y)
    now := A_TickCount

    delay := now - lastRecordTick
    if (delay < 50)
        delay := 50

    ; First click: store coords + run flag, do NOT push to steps array.
    if (backToMinePath.Length = 0) {
        backToMineFirstX := x
        backToMineFirstY := y
        backToMineFirstRunning := enableRun ? 1 : 0
        lastRecordTick := now
        runLabel := enableRun ? " [RUN]" : ""
        ShowTip("Recording " PathLabel(recordingPathName) " | first click (" x "," y ")" runLabel)
        return
    }

    ; Subsequent clicks: store with delay + run flag.
    step := Map("x", x, "y", y, "delay", RoundDelay(delay), "running", enableRun ? 1 : 0)

    backToMinePath.Push(step)
    count := backToMinePath.Length

    runLabel := enableRun ? " [RUN]" : ""
    lastRecordTick := now
    ShowTip("Recording " PathLabel(recordingPathName) " | step " count runLabel)
}

PlayPath(pathName) {
    global running, backToMinePath
    global backToMineTailDelay
    global backToMineFirstX, backToMineFirstY, backToMineFirstRunning
    global PATH_INITIAL_DELAY

    path         := backToMinePath
    tail         := backToMineTailDelay
    firstX       := backToMineFirstX
    firstY       := backToMineFirstY
    firstRunning := backToMineFirstRunning

    if (firstX = 0 && firstY = 0) {
        ShowTip(PathLabel(pathName) " path has no first click set")
        SetTimer(HideTip, -1500)
        return false
    }

    ShowTip("Playing " PathLabel(pathName) "...")

    ; Hardcoded 250ms pause, then first click.
    Sleep(PATH_INITIAL_DELAY)
    if (!running)
        return false
    DoClick(firstX, firstY, firstRunning = 1)

    ; Walk recorded steps.
    prevRunning := firstRunning
    loop path.Length {
        i := A_Index
        step := path[i]

        if (!running)
            return false

        ; Delay scaled by whatever running flag was set at the previous location.
        stepDelay := (prevRunning = 1) ? Round(step["delay"] * 0.535) : step["delay"]
        Sleep(stepDelay)

        if (!running)
            return false

        DoClick(step["x"], step["y"], step["running"] = 1)

        prevRunning := step["running"]
    }

    ; Tail delay — scaled by the last step's running flag.
    if (tail > 0)
        Sleep((prevRunning = 1) ? Round(tail * 0.535) : tail)

    return true
}

PathLabel(pathName) {
    return "BACK-TO-MINE"
}

RoundDelay(ms) {
    rounded := Round(ms / 50) * 50
    return (rounded < 50) ? 50 : rounded
}

; ============================================================
;  HELPERS
; ============================================================

ShowTip(text) {
    x := A_ScreenWidth - 420
    y := 40
    ToolTip(text, x, y)
}

HideTip() {
    ToolTip()
}

StopMining(reason := "Stopped") {
    global running, mining, currentMiningX, currentMiningY, miningStartTime, currentSpotMissingStreak, recordingActive
    running := false
    mining := false
    currentMiningX := 0
    currentMiningY := 0
    miningStartTime := 0
    currentSpotMissingStreak := 0

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

ColorClose(c1, c2, tol) {
    r1 := (c1 >> 16) & 0xFF
    g1 := (c1 >> 8)  & 0xFF
    b1 := c1 & 0xFF

    r2 := (c2 >> 16) & 0xFF
    g2 := (c2 >> 8)  & 0xFF
    b2 := c2 & 0xFF

    return (Abs(r1 - r2) <= tol && Abs(g1 - g2) <= tol && Abs(b1 - b2) <= tol)
}

IsStillOreColor(currentColor, baseOreColor, tol) {
    ; Accept either a close RGB match OR any clearly green-dominant shade.
    if (ColorClose(currentColor, baseOreColor, tol))
        return true

    r := (currentColor >> 16) & 0xFF
    g := (currentColor >> 8)  & 0xFF
    b := currentColor & 0xFF

    return (g >= r + 30 && g >= b + 30 && g >= 100)
}
