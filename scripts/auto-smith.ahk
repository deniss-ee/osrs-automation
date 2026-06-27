; ============================================================
;  auto-smith.ahk
;  Smithing bot, built entirely from the shared lib\ functions -
;  same library auto-smelter.ahk, auto-fisher.ahk and auto-miner.ahk
;  use.
;
;  EXPECTED STARTING STATE: standing near the bank with an empty
;  inventory (or already holding bars - either way, the first
;  ANVIL action only happens once the last inventory slot reads
;  occupied).
;
;  CYCLE:
;    1. Once the last inventory slot is occupied (we've withdrawn
;       bars), play the TO-ANVIL path - this is ONE recorded path
;       that covers the whole walk AND the click on the anvil
;       itself (its last recorded step), since unlike the smelter's
;       furnace this needs to cover real walking distance.
;    2. Press Space to confirm the "make X" dialog the anvil click
;       opens (selects the highlighted/default item).
;    3. Wait for the last inventory slot to go from occupied to
;       EMPTY - same multi-point reference mining/smelting use for
;       "is it full", just waiting for the opposite direction here.
;    4. Play the TO-BANK path (also one recorded path covering the
;       walk AND the click that opens the bank).
;    5. Wait for the Deposit All button (deposit.png) to actually be
;       visible near its known position - see BANK_OPEN_TIMEOUT_MS -
;       instead of guessing how long the walk + bank-open takes,
;       then click it (one click, no right-click menu).
;    6. Withdraw from bank slots 1 and 2 (one click each -
;       "withdraw all" with this user's bank settings, same
;       one-click pattern as every other script's withdrawal).
;    7. Start over from step 1.
;
;  DEBUG LOGGING: every phase transition and bank-detection outcome
;  is timestamped and appended to LOG_FILE (logs\auto-smith-debug.log)
;  via lib\Log.ahk - useful for diagnosing a run after the fact
;  without relying on catching a tooltip live.
;
;  HOTKEYS
;    F1   = start/stop recording the TO-ANVIL path (start walking
;           from the bank, click the anvil as your LAST click before
;           stopping the recording - the "make X" dialog and the
;           Space press are handled automatically by the bot)
;    F2   = save "inventory slot" reference points - EMPTY YOUR
;           INVENTORY first, then press F2 (no need to hover
;           anywhere specific). Samples FOUR points spread around
;           the LAST inventory slot, same mechanism as mining/
;           smelting/fishing - used to detect both "bars withdrawn"
;           (full, triggers the anvil) and "smithing done" (empty).
;    F3   = start/stop recording the TO-BANK path (start walking
;           from the anvil, click the bank booth as your LAST click
;           before stopping - deposit/withdraw are automatic)
;    F5   = start the bot
;    F6   = stop the bot
;    F7   = clear saved config and reload the script
;
;  RUN MODE is a plain setting in the .ini, not a hotkey - same as
;  the other scripts. Open config\auto-smith.ini, find [Settings],
;  set
;
;      runMode=1   (hold Ctrl / run for every click)
;      runMode=0   (never hold Ctrl / always walk - the default)
;
;  then restart the script.
;
;  Config auto-saves to config\auto-smith.ini next to this file.
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
#Include ..\lib\Log.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

; ---------- Config file ----------
global CONFIG := A_ScriptDir "\..\config\auto-smith.ini"

; ---------- Debug log ----------
; Plain text, timestamped, appended to forever - read this after a
; run to see exactly what the bot did, since a tooltip might not
; actually be visible depending on how the game window is running.
global LOG_FILE := A_ScriptDir "\..\logs\auto-smith-debug.log"

; Stops the runner AND records why in the debug log, so a stop
; that happens off-screen (or whose tooltip you miss) is never a
; mystery - just open auto-smith-debug.log afterward.
StopAndLog(taskRunner, reason) {
    global LOG_FILE
    LogLine(LOG_FILE, "STOPPED: " reason)
    StopTaskRunner(taskRunner, reason)
}

; ---------- Tunables ----------
global COLOR_TOLERANCE := 20
global ANVIL_TIMEOUT_MS := 180000        ; max time to wait for the inventory to empty out after starting to smith (3 min) - raise this if you're smithing something slower
global ANVIL_CONFIRM_TICKS := 3          ; require "empty" to read true for this many consecutive ~100ms polls before trusting it (filters a transient glitch)
global ANVIL_SPACE_SETTLE_MS := 100      ; brief wait after pressing Space, before the first emptiness check - just long enough to cover the dialog closing and smithing starting
global PHASE_TIMEOUT_ANVIL := 30000      ; give up and stop if we can't even START smithing (e.g. window unfocused) for this long
global PHASE_TIMEOUT_BANK := 30000       ; give up and stop if banking hangs for 30s straight
global WITHDRAW_SLOT_1_INDEX := 1        ; which bank slot (1-8, left to right - see Grid.ahk's GetBankSlots) to withdraw first
global WITHDRAW_SLOT_2_INDEX := 2        ; which bank slot to withdraw second
global WITHDRAW_INTER_SETTLE_MS := 600   ; pause between the two withdrawal clicks
global WITHDRAW_FINAL_SETTLE_MS := 300   ; pause after the SECOND withdrawal before returning - must be long enough for the inventory display to finish updating, or the next occupancy check reads stale (see BankWithdrawSlot in lib\Bank.ahk)

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
; after the to-bank path's last click (before we even start polling
; for the Deposit All button), and one right after we find AND click
; it. Both apply every time, even if the button was already visible
; the instant we started polling - they're not a substitute for the
; detection itself, just a safety margin.
global BANK_OPEN_SETTLE_MS := 300
global BANK_OPEN_FAILSAFE_DELAY_MS := 300

; ---------- TESTING: humanization disabled ----------
; Click.ahk defaults ENABLE_HUMANIZATION to false (and hard-caps it
; at +/-2px / +/-100ms even if enabled). Set to false here too so
; clicks land on the exact calibrated pixel with exact delays while
; you're testing - flip this to true once you've confirmed the bot
; behaves correctly.
global ENABLE_HUMANIZATION := false

; ---------- Calibrated values (loaded from INI, or empty if unset) ----------
; emptySlotPoints is a list of {x, y, color} - several reference
; points inside the last inventory slot, all captured by one F2
; press. See IsAnyPointOccupied / WaitUntilNotOccupied (Colors.ahk).
global emptySlotPoints := []

; ---------- Run/walk setting - plain config flag, no hotkey ----------
global runMode := false

; ---------- Recorded paths ----------
global toAnvilRecorder := NewPathRecorder()
global toBankRecorder := NewPathRecorder()
global toAnvilSteps := []
global toBankSteps := []

; ---------- Library objects built from the above ----------
global runner := NewTaskRunner(150)

; ---------- Init ----------
Hotkey("~LButton", RecordClick, "Off")
Hotkey("~RButton", RecordClick, "Off")
LoadConfig()

; ============================================================
;  CALIBRATION HOTKEYS
; ============================================================

F1:: ToggleRecording(toAnvilRecorder, "ToAnvil", "WALK-TO-ANVIL")

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

F5:: StartBot()
F6:: StopAndLog(runner, "Stopped (F6)")

F7:: {
    if FileExist(CONFIG)
        FileDelete(CONFIG)
    Reload()
}

; ============================================================
;  PATH RECORDING
; ============================================================

; Starts/stops recording for whichever recorder is passed in.
; Only one path can record at a time - this mirrors the other
; scripts' behavior and avoids interleaving two paths' clicks.
ToggleRecording(recorder, sectionName, label) {
    global toAnvilRecorder, toBankRecorder
    global toAnvilSteps, toBankSteps
    if (recorder["active"]) {
        steps := StopRecording(recorder)
        SavePath(CONFIG, sectionName, steps)
        if (sectionName = "ToAnvil")
            toAnvilSteps := steps
        else
            toBankSteps := steps
        Hotkey("~LButton", RecordClick, "Off")
        Hotkey("~RButton", RecordClick, "Off")
        ShowTipFor(label " recording stopped (" steps.Length " clicks)", 1500)
        return
    }

    if (toAnvilRecorder["active"] || toBankRecorder["active"]) {
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
    global toAnvilRecorder, toBankRecorder, runMode
    activeRecorder := toAnvilRecorder["active"] ? toAnvilRecorder
        : toBankRecorder["active"] ? toBankRecorder
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
    global toAnvilSteps, toBankSteps
    global COLOR_TOLERANCE, WITHDRAW_SLOT_1_INDEX, WITHDRAW_SLOT_2_INDEX
    emptySlotPoints := LoadColorPointList(CONFIG, "InventoryEmptyPoints")

    ; Plain on/off setting, edited directly in the .ini - see the
    ; "RUN MODE" note in the header comment. Not a hotkey.
    runMode := LoadFlag(CONFIG, "Settings", "runMode", false)

    ; Curated tunables - overwrite the hardcoded defaults above from
    ; the .ini if present, so these can be tweaked without editing
    ; this file (e.g. from the control panel).
    COLOR_TOLERANCE := LoadNumber(CONFIG, "Tunables", "colorTolerance", COLOR_TOLERANCE)
    WITHDRAW_SLOT_1_INDEX := LoadNumber(CONFIG, "Tunables", "withdrawSlot1Index", WITHDRAW_SLOT_1_INDEX)
    WITHDRAW_SLOT_2_INDEX := LoadNumber(CONFIG, "Tunables", "withdrawSlot2Index", WITHDRAW_SLOT_2_INDEX)

    toAnvilSteps := LoadPath(CONFIG, "ToAnvil")
    toBankSteps := LoadPath(CONFIG, "ToBank")
}

; ============================================================
;  SETUP VALIDATION
; ============================================================

ValidateSetup() {
    global emptySlotPoints, toAnvilSteps, toBankSteps
    global DEPOSIT_IMG
    v := NewValidator()
    RequireNonEmpty(v, "F2 - inventory slot reference points", emptySlotPoints)
    RequirePath(v, "F1 - walk-to-anvil path", toAnvilSteps)
    RequirePath(v, "F3 - walk-to-bank path", toBankSteps)
    RequireFile(v, "deposit.png (bank deposit image)", DEPOSIT_IMG)
    return ShowValidationErrors(v)
}

StartBot() {
    global toAnvilRecorder, toBankRecorder, runner, LOG_FILE
    global PHASE_TIMEOUT_ANVIL, PHASE_TIMEOUT_BANK
    if (toAnvilRecorder["active"] || toBankRecorder["active"]) {
        ShowTipFor("Finish recording before starting the bot", 1200)
        return
    }
    if (!ValidateSetup())
        return

    AddPhase(runner, "anvil", AnvilPhase, PHASE_TIMEOUT_ANVIL)
    AddPhase(runner, "bank", BankPhase, PHASE_TIMEOUT_BANK)
    StartTaskRunner(runner, "anvil")
    ShowTipFor("Bot started", 1000)
    LogLine(LOG_FILE, "===== Bot started =====")
}

; ============================================================
;  PHASES
; ============================================================

; If the last inventory slot is occupied (we're holding bars), walks
; to the anvil and clicks it, presses Space to confirm the "make X"
; dialog, then waits for the last slot to go from occupied to empty
; (all bars smithed). If it's already empty (e.g. the bank ran out
; of bars to withdraw last trip), skips straight to banking instead
; of wastefully walking to the anvil for nothing.
AnvilPhase(taskRunner) {
    global toAnvilSteps, emptySlotPoints, LOG_FILE
    global COLOR_TOLERANCE, ANVIL_TIMEOUT_MS, ANVIL_CONFIRM_TICKS, ANVIL_SPACE_SETTLE_MS
    if (!RequireOsrsWindowActive()) {
        LogLine(LOG_FILE, "anvil: OSRS window not focused - paused")
        return GoToPhase(taskRunner, "anvil")
    }

    occupied := IsAnyPointOccupied(emptySlotPoints, COLOR_TOLERANCE)
    LogLine(LOG_FILE, "anvil: entered anvil phase, last slot occupied=" occupied)
    if (!occupied)
        return GoToPhase(taskRunner, "bank")

    isRunningFn := () => taskRunner["running"]
    LogLine(LOG_FILE, "anvil: playing walk-to-anvil path (" toAnvilSteps.Length " steps)")
    if (!PlayPathWithGuard(toAnvilSteps, isRunningFn)) {
        StopAndLog(taskRunner, "Walk-to-anvil path failed or was stopped")
        return GoToPhase(taskRunner, "anvil")
    }

    ; Confirms the "make X" dialog the anvil click opened - selects
    ; the highlighted/default item, exactly like pressing Space by
    ; hand.
    LogLine(LOG_FILE, "anvil: pressing Space to confirm make-X dialog")
    HumanKeyPress("Space")
    Sleep(JitterDelay(ANVIL_SPACE_SETTLE_MS))

    ; Smithing happens automatically once started - just wait for
    ; the last slot to empty out. Same multi-point reference the
    ; mining/smelting scripts use for "is it full", just waiting for
    ; the opposite direction, with the same confirm-ticks debounce
    ; so a single transient glitch can't be mistaken for "done".
    emptied := WaitUntilNotOccupied(emptySlotPoints, COLOR_TOLERANCE, ANVIL_TIMEOUT_MS, ANVIL_CONFIRM_TICKS, , isRunningFn)
    LogLine(LOG_FILE, "anvil: wait-until-empty returned " emptied " (false = timed out after " ANVIL_TIMEOUT_MS "ms)")

    ; We made a real attempt (the walk + click + Space happened) -
    ; reset the phase timer so PHASE_TIMEOUT_ANVIL measures "can't
    ; even start smithing for 30s", not "total time spent smithing".
    ResetPhaseTimer(taskRunner)
    return GoToPhase(taskRunner, "bank")
}

; Walks to the bank, deposits everything, withdraws from bank slots
; 1 and 2, then returns to the anvil phase (which will play the
; to-anvil path again on its next entry).
BankPhase(taskRunner) {
    global toAnvilSteps, toBankSteps, LOG_FILE
    global WITHDRAW_SLOT_1_INDEX, WITHDRAW_SLOT_2_INDEX, WITHDRAW_INTER_SETTLE_MS, WITHDRAW_FINAL_SETTLE_MS
    global DEPOSIT_IMG, BANK_OPEN_SETTLE_MS, BANK_OPEN_FAILSAFE_DELAY_MS
    global COLOR_TOLERANCE, emptySlotPoints
    if (!RequireOsrsWindowActive()) {
        LogLine(LOG_FILE, "bank: OSRS window not focused - paused")
        return GoToPhase(taskRunner, "bank")
    }

    LogLine(LOG_FILE, "bank: entered bank phase, playing walk-to-bank path (" toBankSteps.Length " steps)")
    isRunningFn := () => taskRunner["running"]

    if (!PlayPathWithGuard(toBankSteps, isRunningFn)) {
        StopAndLog(taskRunner, "Walk-to-bank path failed or was stopped")
        return GoToPhase(taskRunner, "bank")
    }

    ; Open the bank and deposit everything (shared lib\Bank.ahk).
    LogLine(LOG_FILE, "bank: walk-to-bank path done, depositing")
    if (!BankDepositAll(DEPOSIT_IMG, BANK_OPEN_SETTLE_MS, BANK_OPEN_FAILSAFE_DELAY_MS, , , , , , isRunningFn)) {
        StopAndLog(taskRunner, "Bank never opened (Deposit All button not found)")
        return GoToPhase(taskRunner, "bank")
    }

    ; Withdraw from both slots. The second settle is longer than the
    ; gap between the two clicks because the next phase immediately
    ; checks "is the last slot occupied" - too soon after the click
    ; that reads stale (the inventory display hadn't finished
    ; updating yet), confirmed via the debug log.
    LogLine(LOG_FILE, "bank: deposited, withdrawing slot " WITHDRAW_SLOT_1_INDEX " then " WITHDRAW_SLOT_2_INDEX)
    BankWithdrawSlot(WITHDRAW_SLOT_1_INDEX, WITHDRAW_INTER_SETTLE_MS)
    BankWithdrawSlot(WITHDRAW_SLOT_2_INDEX, WITHDRAW_FINAL_SETTLE_MS)

    occupied := IsAnyPointOccupied(emptySlotPoints, COLOR_TOLERANCE)
    LogLine(LOG_FILE, "bank: done withdrawing, last slot occupied=" occupied " - returning to anvil phase")
    return GoToPhase(taskRunner, "anvil")
}
