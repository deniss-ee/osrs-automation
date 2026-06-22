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
;  Ctrl+R = toggle run mode (used during the back-to-mine walk)
;
;  Config auto-saves to miner_part1.ini next to this script.
;
;  ELI5 FILE MAP: this entry-point file only holds the global
;  variables (the bot's "memory") and the hotkeys (F1-F8, Ctrl+R).
;  The actual logic lives in lib/*.ahk, split by what it does:
;    lib/config.ahk     - save/load settings to the .ini file
;    lib/detection.ahk   - "is this pixel the right color?" checks
;    lib/movement.ahk    - the one function that clicks the mouse
;    lib/paths.ahk       - record/replay the to-bank & back paths
;    lib/mining.ahk       - the main mining + banking loop
;    lib/ui.ahk            - the on-screen tooltip messages
;  #Include just pastes those files' code in here, so the whole
;  thing behaves as one program - splitting it up is purely for
;  readability, nothing about how the bot behaves has changed.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

#Include lib\config.ahk
#Include lib\detection.ahk
#Include lib\movement.ahk
#Include lib\paths.ahk
#Include lib\mining.ahk
#Include lib\ui.ahk

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
