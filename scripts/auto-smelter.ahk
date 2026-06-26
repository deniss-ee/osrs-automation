; ============================================================
;  auto-smelter.ahk
;  Smelting bot, built entirely from the shared lib\ functions -
;  same library that auto-miner.ahk and the rest of this folder's
;  scripts share. This replaces
;  smelter-1.ahk's logic with the newer, hardened building blocks
;  (multi-point inventory check, confirm-ticks debounce, pause-
;  after-click paths, humanized clicks).
;
;  EXPECTED STARTING STATE: you are standing at the smelter with
;  a full inventory of ore.
;
;  CYCLE:
;    1. Play the SMELT path (click the furnace, click "Smelt All"
;       or whatever starts smelting your whole inventory).
;    2. Wait for the last inventory slot to go from full to empty -
;       this is the SAME multi-point reference the mining script
;       uses for "is it full", just waiting for the opposite
;       direction (here, empty means "all the ore got smelted").
;    3. Play the TO-BANK path, then wait until the Deposit All
;       button (deposit.png) is actually visible near its known
;       position - see BANK_OPEN_TIMEOUT_MS - instead of guessing
;       how long the walk + bank-open takes, then click it (one
;       click, no right-click menu).
;    4. Withdraw a fresh stack of ore - one click on a single bank
;       slot (WITHDRAW_SLOT_INDEX below - "withdraw all" with this
;       user's bank settings, same one-click pattern as deposit).
;    5. Play the TO-SMELTER path, then start over from step 1.
;
;  HOTKEYS
;    F1   = start/stop recording the SMELT path (click the
;           furnace, click whatever starts smelting - record this
;           with a full inventory of ore in hand)
;    F2   = save "inventory slot" reference points - EMPTY YOUR
;           INVENTORY first, then press F2 (no need to hover
;           anywhere specific). Samples FOUR points spread around
;           the LAST inventory slot, exactly like the mining
;           script's F2 - the bot uses these to detect BOTH "ore
;           ran out" (here) and could detect "inventory full" too
;           if you ever needed that check in a script built from
;           this one.
;    F3   = start/stop recording the WALK-TO-BANK path (start
;           right after smelting finishes, stop once you've
;           arrived at the bank - BEFORE touching deposit, since
;           that's handled automatically by the bot)
;    F4   = start/stop recording the WALK-TO-SMELTER path (start
;           right after withdrawing ore, stop once you've arrived
;           back at the furnace - BEFORE clicking it, since the
;           SMELT path handles that)
;    F5   = start the bot
;    F6   = stop the bot
;    F7   = clear saved config and reload the script
;
;  RUN MODE is a plain setting in the .ini, not a hotkey - same as
;  the mining script. Open config\auto-smelter.ini, find [Settings], set
;
;      runMode=1   (hold Ctrl / run for every click)
;      runMode=0   (never hold Ctrl / always walk - the default)
;
;  then restart the script.
;
;  Config auto-saves to config\auto-smelter.ini next to this file.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

#Include ..\lib\Tooltip.ahk
#Include ..\lib\Colors.ahk
#Include ..\lib\Images.ahk
#Include ..\lib\Safety.ahk
#Include ..\lib\ConfigStore.ahk
#Include ..\lib\Grid.ahk
#Include ..\lib\Click.ahk
#Include ..\lib\Paths.ahk
#Include ..\lib\Bank.ahk
#Include ..\lib\Validate.ahk
#Include ..\lib\TaskRunner.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

; ---------- Config file ----------
global CONFIG := A_ScriptDir "\..\config\auto-smelter.ini"

; ---------- Tunables ----------
global COLOR_TOLERANCE := 20
global SMELT_TIMEOUT_MS := 180000        ; max time to wait for the inventory to empty out after starting a smelt (3 min) - raise this if you smelt a slower ore/bar
global SMELT_CONFIRM_TICKS := 2          ; require "empty" to read true for this many consecutive ~100ms polls before trusting it (filters a transient glitch)
global PHASE_TIMEOUT_SMELT := 30000      ; give up and stop if we can't even START a smelt attempt (e.g. window unfocused) for this long
global PHASE_TIMEOUT_BANK := 30000       ; give up and stop if banking hangs for 30s straight
global WITHDRAW_SLOT_INDEX := 4          ; which bank slot (1-8, left to right - see Grid.ahk's GetBankSlots) holds the ore to withdraw after depositing. May change later.
global WITHDRAW_SETTLE_MS := 300         ; pause after the withdrawal click before walking back - long enough for the inventory display to finish updating (see BankWithdrawSlot in lib\Bank.ahk)

; Instead of a flat guess for how long the walk-to-bank + bank-open
; takes, wait until the Deposit All button image is actually
; visible near its known position.
global DEPOSIT_IMG := A_ScriptDir "\..\images\deposit.png"
global DEPOSIT_IMG_OPTIONS := "*20"   ; deposit.png is a direct screenshot of the button (matches its 72x72 size exactly) - just a little shade tolerance, no transparency trick needed
global DEPOSIT_IMG_W := 72
global DEPOSIT_IMG_H := 72
global DEPOSIT_BTN_SEARCH_MARGIN := 20   ; how far past the button's own box to search - the button is a fixed UI element, not a world object, so this only needs to cover minor calibration slack
global BANK_OPEN_TIMEOUT_MS := 15000      ; give up waiting for the bank to visibly open after this long
; Two small settle delays around the bank-open detection: one right
; after the walk-to-bank path's last click (before we even start
; polling for the Deposit All button), and one right after we find
; AND click it. Both apply every time, even if the button was
; already visible the instant we started polling - they're not a
; substitute for the detection itself, just a safety margin.
global BANK_OPEN_SETTLE_MS := 300
global BANK_OPEN_FAILSAFE_DELAY_MS := 300

; ---------- Humanization: off by default ----------
; Click.ahk defaults ENABLE_HUMANIZATION to false (exact calibrated
; pixel, exact delays). Even when enabled it's hard-capped at
; +/-2px / +/-100ms. Restated here so it's explicit per script - set
; to true if you ever want the subtle randomized offset/jitter back.
global ENABLE_HUMANIZATION := false

; ---------- Calibrated values (loaded from INI, or empty if unset) ----------
; emptySlotPoints is a list of {x, y, color} - several reference
; points inside the last inventory slot, all captured by one F2
; press. See IsAnyPointOccupied / WaitUntilNotOccupied (Colors.ahk).
global emptySlotPoints := []

; ---------- Run/walk setting - plain config flag, no hotkey ----------
global runMode := false

; ---------- Recorded paths ----------
global smeltRecorder := NewPathRecorder()
global toBankRecorder := NewPathRecorder()
global toSmelterRecorder := NewPathRecorder()
global smeltSteps := []
global toBankSteps := []
global toSmelterSteps := []

; ---------- Library objects built from the above ----------
global runner := NewTaskRunner(150)

; ---------- Init ----------
Hotkey("~LButton", RecordClick, "Off")
Hotkey("~RButton", RecordClick, "Off")
LoadConfig()

; ============================================================
;  CALIBRATION HOTKEYS
; ============================================================

F1:: ToggleRecording(smeltRecorder, "Smelt", "SMELT ACTION")

F2:: {
    global emptySlotPoints
    ; Uses the standard 28-slot inventory grid from Grid.ahk to
    ; find the LAST slot, then samples 4 points spread around it
    ; (GetDefaultSlotOffsets) instead of just its one center pixel
    ; - make sure your inventory is empty before pressing this.
    slots := GetInventorySlots()
    lastSlot := slots[slots.Length]
    points := GetSlotSamplePoints(lastSlot, GetDefaultSlotOffsets())
    for p in points
        p["color"] := PixelGetColor(p["x"], p["y"], "RGB")
    emptySlotPoints := points
    SaveColorPointList(CONFIG, "InventoryEmptyPoints", emptySlotPoints)
    ShowTipFor("Empty-slot reference points saved (make sure inventory was empty!)", 1800)
}

F3:: ToggleRecording(toBankRecorder, "ToBank", "WALK-TO-BANK")
F4:: ToggleRecording(toSmelterRecorder, "ToSmelter", "WALK-TO-SMELTER")

F5:: StartBot()
F6:: StopTaskRunner(runner, "Stopped (F6)")

F7:: {
    if FileExist(CONFIG)
        FileDelete(CONFIG)
    Reload()
}

; ============================================================
;  PATH RECORDING
; ============================================================

; Starts/stops recording for whichever recorder is passed in.
; Only one path can record at a time - this mirrors the mining
; script's behavior and avoids interleaving two paths' clicks.
ToggleRecording(recorder, sectionName, label) {
    global smeltRecorder, toBankRecorder, toSmelterRecorder
    global smeltSteps, toBankSteps, toSmelterSteps
    if (recorder["active"]) {
        steps := StopRecording(recorder)
        SavePath(CONFIG, sectionName, steps)
        if (sectionName = "Smelt")
            smeltSteps := steps
        else if (sectionName = "ToBank")
            toBankSteps := steps
        else
            toSmelterSteps := steps
        Hotkey("~LButton", RecordClick, "Off")
        Hotkey("~RButton", RecordClick, "Off")
        ShowTipFor(label " recording stopped (" steps.Length " clicks)", 1500)
        return
    }

    if (smeltRecorder["active"] || toBankRecorder["active"] || toSmelterRecorder["active"]) {
        ShowTipFor("Already recording another path - finish that first", 1200)
        return
    }

    StartRecording(recorder, sectionName)
    Hotkey("~LButton", RecordClick, "On")
    Hotkey("~RButton", RecordClick, "On")
    ShowTipFor(label " recording started - click your route, then press the key again to stop", 2200)
}

; Fires on every click while a recorder is active. Figures out
; which recorder is the active one and which mouse button was
; used, then hands off to Paths.ahk's RecordClickStep along with
; whatever runMode is currently set to.
RecordClick(*) {
    global smeltRecorder, toBankRecorder, toSmelterRecorder, runMode
    activeRecorder := smeltRecorder["active"] ? smeltRecorder
        : toBankRecorder["active"] ? toBankRecorder
        : toSmelterRecorder["active"] ? toSmelterRecorder
        : ""
    if (activeRecorder = "")
        return

    MouseGetPos(&mx, &my)
    button := InStr(A_ThisHotkey, "RButton") ? "Right" : "Left"
    RecordClickStep(activeRecorder, mx, my, button, runMode ? 1 : 0)
}

; ============================================================
;  CONFIG LOAD
; ============================================================

LoadConfig() {
    global emptySlotPoints, runMode
    global smeltSteps, toBankSteps, toSmelterSteps
    emptySlotPoints := LoadColorPointList(CONFIG, "InventoryEmptyPoints")

    ; Plain on/off setting, edited directly in the .ini - see the
    ; "RUN MODE" note in the header comment. Not a hotkey.
    runMode := LoadFlag(CONFIG, "Settings", "runMode", false)

    smeltSteps := LoadPath(CONFIG, "Smelt")
    toBankSteps := LoadPath(CONFIG, "ToBank")
    toSmelterSteps := LoadPath(CONFIG, "ToSmelter")
}

; ============================================================
;  SETUP VALIDATION
; ============================================================

ValidateSetup() {
    global emptySlotPoints, smeltSteps, toBankSteps, toSmelterSteps
    global DEPOSIT_IMG
    v := NewValidator()
    RequireNonEmpty(v, "F2 - inventory slot reference points", emptySlotPoints)
    RequirePath(v, "F1 - smelt action path", smeltSteps)
    RequirePath(v, "F3 - walk-to-bank path", toBankSteps)
    RequirePath(v, "F4 - walk-to-smelter path", toSmelterSteps)
    RequireFile(v, "deposit.png (bank deposit image)", DEPOSIT_IMG)
    return ShowValidationErrors(v)
}

StartBot() {
    global smeltRecorder, toBankRecorder, toSmelterRecorder, runner
    global PHASE_TIMEOUT_SMELT, PHASE_TIMEOUT_BANK
    if (smeltRecorder["active"] || toBankRecorder["active"] || toSmelterRecorder["active"]) {
        ShowTipFor("Finish recording before starting the bot", 1200)
        return
    }
    if (!ValidateSetup())
        return

    AddPhase(runner, "smelt", SmeltPhase, PHASE_TIMEOUT_SMELT)
    AddPhase(runner, "bank", BankPhase, PHASE_TIMEOUT_BANK)
    StartTaskRunner(runner, "smelt")
    ShowTipFor("Bot started", 1000)
}

; ============================================================
;  PHASES
; ============================================================

; Starts a smelt cycle (the recorded SMELT path: click furnace,
; click smelt-all), then waits for the last inventory slot to go
; from full to empty - i.e. every bit of ore has been smelted -
; before moving to the bank phase.
SmeltPhase(taskRunner) {
    global smeltSteps, emptySlotPoints
    global COLOR_TOLERANCE, SMELT_TIMEOUT_MS, SMELT_CONFIRM_TICKS
    if (!RequireOsrsWindowActive())
        return GoToPhase(taskRunner, "smelt")

    ; If the last slot already reads as empty, there's no ore to
    ; smelt (e.g. the bank ran out of ore to withdraw last trip) -
    ; skip straight to restocking instead of wastefully clicking
    ; the furnace and the smelt-all button for nothing, only to
    ; have WaitUntilNotOccupied below immediately read "already
    ; empty" anyway.
    if (!IsAnyPointOccupied(emptySlotPoints, COLOR_TOLERANCE))
        return GoToPhase(taskRunner, "bank")

    isRunningFn := () => taskRunner["running"]
    if (!PlayPathWithGuard(smeltSteps, isRunningFn)) {
        StopTaskRunner(taskRunner, "Smelt action failed or was stopped")
        return GoToPhase(taskRunner, "smelt")
    }

    ; Smelting happens automatically once started - just wait for
    ; the last slot to empty out. Same multi-point reference the
    ; mining script uses for "is it full", just waiting for the
    ; opposite direction, with the same confirm-ticks debounce so
    ; a single transient glitch can't be mistaken for "done".
    WaitUntilNotOccupied(emptySlotPoints, COLOR_TOLERANCE, SMELT_TIMEOUT_MS, SMELT_CONFIRM_TICKS)

    ; We made a real attempt (the smelt path played) - reset the
    ; phase timer so PHASE_TIMEOUT_SMELT measures "can't even start
    ; a smelt attempt for 30s", not "total time spent smelting".
    ResetPhaseTimer(taskRunner)
    return GoToPhase(taskRunner, "bank")
}

; Walks to the bank, deposits everything, withdraws a fresh stack
; of ore from one specific bank slot, then walks back to the
; smelter.
BankPhase(taskRunner) {
    global toBankSteps, toSmelterSteps, WITHDRAW_SLOT_INDEX, WITHDRAW_SETTLE_MS
    global DEPOSIT_IMG, BANK_OPEN_SETTLE_MS, BANK_OPEN_FAILSAFE_DELAY_MS
    if (!RequireOsrsWindowActive())
        return GoToPhase(taskRunner, "bank")

    isRunningFn := () => taskRunner["running"]

    if (!PlayPathWithGuard(toBankSteps, isRunningFn)) {
        StopTaskRunner(taskRunner, "Walk-to-bank path failed or was stopped")
        return GoToPhase(taskRunner, "bank")
    }

    ; Open the bank and deposit everything (shared lib\Bank.ahk).
    if (!BankDepositAll(DEPOSIT_IMG, BANK_OPEN_SETTLE_MS, BANK_OPEN_FAILSAFE_DELAY_MS)) {
        StopTaskRunner(taskRunner, "Bank never opened (Deposit All button not found)")
        return GoToPhase(taskRunner, "bank")
    }

    ; Withdraw a fresh stack of ore from the slot that holds it.
    BankWithdrawSlot(WITHDRAW_SLOT_INDEX, WITHDRAW_SETTLE_MS)

    if (!PlayPathWithGuard(toSmelterSteps, isRunningFn)) {
        StopTaskRunner(taskRunner, "Walk-to-smelter path failed or was stopped")
        return GoToPhase(taskRunner, "bank")
    }

    return GoToPhase(taskRunner, "smelt")
}
