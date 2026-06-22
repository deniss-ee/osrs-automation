; ============================================================
;  main.ahk - START HERE
; ------------------------------------------------------------
;  ELI5: This is the file you actually run (double-click or
;  "Run Script"). It doesn't DO much itself - its job is to:
;    1. #Include every lib/*.ahk file (paste their code in,
;       like assembling puzzle pieces into one program).
;    2. Load your saved settings.
;    3. Build the GUI window.
;    4. Set up hotkeys (F1-F9) so they call the right functions.
;
;  HOTKEY CHEAT SHEET:
;    F1  = add a gathering spot under your mouse cursor
;    F2  = calibrate inventory slot under your mouse cursor
;    F3  = calibrate stamina orb EMPTY (drain energy first)
;    F4  = record/stop TO-BANK path
;    F5  = record/stop BACK-TO-MINE path
;    F6  = Start the bot
;    F7  = STOP the bot (also: throw mouse into top-left corner)
;    F8  = clear saved config and reload the script fresh
;    F9  = while recording a path, toggle RUN vs WALK for the
;          next clicks you record (per-coordinate control)
;    F10 = calibrate stamina orb FULL (let energy refill first)
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

; ---- assemble all the modules. Order matters a little: state.ahk
; must come first since everything else reads/writes `State`. ----
#Include lib\state.ahk
#Include lib\config.ahk
#Include lib\detection.ahk
#Include lib\stamina.ahk
#Include lib\failsafe.ahk
#Include lib\movement.ahk
#Include lib\paths.ahk
#Include lib\gathering.ahk
#Include lib\gui.ahk

; ---- pick which profile (.ini) to use. One profile = one set of
; spots/paths/calibration, e.g. "mining_2ore", "fishing_spot1". ----
global ActiveProfile := "mining_2ore"
State["configPath"] := A_ScriptDir "\profiles\" ActiveProfile ".ini"

; ---- make sure the profiles folder exists before we try to save into it ----
if !DirExist(A_ScriptDir "\profiles")
    DirCreate(A_ScriptDir "\profiles")

RegisterGatheringSteps()
LoadConfig()
BuildGui()

; ============================================================
;  HOTKEYS
; ============================================================

F1:: {
    global State
    MouseGetPos(&x, &y)
    if (!ValidateCoordOrWarn(x, y, "gathering spot"))
        return
    color := PixelGetColor(x, y, "RGB")
    name := "Spot " (State["spots"].Length + 1)
    State["spots"].Push(Map("name", name, "x", x, "y", y, "color", color, "enabled", true))
    SaveConfig()
    RefreshGuiLists()
    State["statusText"] := "Added " name " at " x "," y
}

F2:: {
    global State
    MouseGetPos(&x, &y)
    if (!ValidateCoordOrWarn(x, y, "inventory slot"))
        return
    State["invX"] := x
    State["invY"] := y
    State["invDefaultColor"] := PixelGetColor(x, y, "RGB")
    SaveConfig()
    State["statusText"] := "Inventory slot set at " x "," y
}

F3:: {
    CalibrateOrbEmpty()
    SaveConfig()
}

F10:: {
    CalibrateOrbFull()
    SaveConfig()
}

F4:: {
    TogglePathRecording("toBank", RecordPathClick)
    RefreshGuiLists()
}
F5:: {
    TogglePathRecording("backToMine", RecordPathClick)
    RefreshGuiLists()
}
F9:: ToggleRecordRun()

F6:: {
    global State
    if (!ValidateSetup())
        return
    if (State["recordingActive"]) {
        MsgBox("Stop path recording first (F4/F5).", "Recording active", 48)
        return
    }
    State["running"] := true
    State["paused"] := false
    RunGatheringCycle()
}

F7:: StopMining("Stopped (F7)")

F8:: {
    global State
    if FileExist(State["configPath"])
        FileDelete(State["configPath"])
    Reload()
}
