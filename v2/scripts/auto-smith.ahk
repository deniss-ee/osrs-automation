; ============================================================
;  auto-smith.ahk
;  Smithing bot, built entirely from the shared lib\ functions -
;  same library auto-smelter.ahk, auto-cooker.ahk, auto-miner.ahk
;  and auto-fisher.ahk use.
;
;  EXPECTED STARTING STATE: standing near the bank with an empty
;  inventory (or already holding bars - either way, the first ANVIL
;  action only happens once the last inventory slot reads occupied).
;
;  CYCLE (marker-based, same shape as auto-smelter.ahk - no recorded
;  paths anywhere; every "walk" is triggered by clicking a colored
;  plugin marker that the game/plugin handles automatically):
;    1. Find the anvil marker color (ANVIL_MARKER_COLOR) in the
;       calibrated ANVIL search box and click it with a fixed offset -
;       same "marker color, fixed-offset click" pattern
;       auto-smelter.ahk's furnace click uses.
;    2. Wait for smithing-marker.png to appear (the "Smith X" / "make
;       X" dialog), then press ANVIL_KEY (Space by default) to
;       confirm it - exactly like auto-smelter.ahk's SMELT_KEY
;       confirming the "Smelt X" dialog.
;    3. Smithing happens automatically once started - wait for the
;       calibrated last inventory slot to go from full to empty, the
;       same multi-point reference every other script uses for "is it
;       full"/"is it empty".
;    4. Find the bank marker color (BANK_MARKER_COLOR) in the
;       calibrated BANK search box and click it with a fixed offset -
;       same marker-click pattern as step 1, this one walks to and
;       opens the bank automatically.
;    5. Wait for deposit.png (the bank's Deposit All button) and
;       click it - shared lib\Bank.ahk, same as every other script.
;    6. Withdraw from bank slots 1 and 2 (one click each), then start
;       over from step 1.
;
;  WHY THE ANVIL/BANK SEARCH BOXES ARE HARDCODED DEFAULTS, NOT A
;  HOTKEY CALIBRATION: both are fixed, UI-anchored plugin markers, not
;  world/camera-dependent positions - same reasoning as
;  auto-smelter.ahk's SMELTER_SEARCH_*/BANK_SEARCH_*. They're still
;  overridable by hand-editing the .ini if your setup ever differs.
;
;  EXPECTED STARTING STATE (calibration): inventory EMPTY when you
;  press F1.
;
;  HOTKEYS
;    F1   = save "inventory slot" reference points - EMPTY YOUR
;           INVENTORY first, then press F1. Samples FOUR points
;           spread around the LAST inventory slot, same mechanism as
;           every other script's emptySlotPoints - the bot uses these
;           to detect both "bars withdrawn" (full) and "smithing done"
;           (empty).
;    F2   = start the bot
;    F3   = stop the bot
;    F4   = clear saved config and reload the script
;
;  RUN MODE is a plain setting in the .ini, not a hotkey - same as
;  the other scripts. Open config\auto-smith.ini, find [Settings], set
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
global LOG_FILE := A_ScriptDir "\..\logs\auto-smith-debug.log"

; Stops the runner AND records why in the debug log, so a stop that
; happens off-screen (or whose tooltip you miss) is never a mystery -
; just open auto-smith-debug.log afterward.
StopAndLog(taskRunner, reason) {
    global LOG_FILE
    LogLine(LOG_FILE, "STOPPED: " reason)
    StopTaskRunner(taskRunner, reason)
}

; ---------- Humanization: off by default ----------
global ENABLE_HUMANIZATION := false

; ---------- Tunables: inventory check ----------
global COLOR_TOLERANCE := 20
global ANVIL_TIMEOUT_MS := 180000        ; max time to wait for the inventory to empty out after starting to smith (3 min) - raise this if you're smithing something slower
global ANVIL_CONFIRM_TICKS := 2          ; require "empty" to read true for this many consecutive ~100ms polls before trusting it (filters a transient glitch)
global PHASE_TIMEOUT_ANVIL := 30000      ; give up and stop if we can't even START smithing (e.g. window unfocused) for this long
global PHASE_TIMEOUT_BANK := 30000       ; give up and stop if banking hangs for 30s straight
; Right after a bank withdrawal, the inventory display can take a
; moment to actually render freshly-withdrawn bars - an instantaneous
; check right then can misread the slot as still empty even though
; bars were genuinely just withdrawn, which would bounce straight back
; to BankPhase forever without ever clicking the anvil again. Same fix
; as auto-smelter.ahk's SMELT_GUARD_SETTLE_TIMEOUT_MS / auto-cooker.ahk's
; COOK_GUARD_SETTLE_TIMEOUT_MS - give the slot a short grace window to
; settle into "occupied" before believing it's genuinely empty.
global ANVIL_GUARD_SETTLE_TIMEOUT_MS := 3000

; ---------- Tunables: anvil marker ----------
global ANVIL_MARKER_COLOR := 0xFF00FF
global ANVIL_MARKER_TOLERANCE := 20
; 100x75 box centered at (1699,552) - this user's measured position of
; the anvil's plugin marker. Hardcoded default, see header comment for
; why this isn't a hotkey-calibrated region.
global ANVIL_SEARCH_X1 := 1649, ANVIL_SEARCH_Y1 := 515
global ANVIL_SEARCH_X2 := 1749, ANVIL_SEARCH_Y2 := 590
global ANVIL_CLICK_OFFSET_X := 15, ANVIL_CLICK_OFFSET_Y := 15
global ANVIL_SEARCH_TIMEOUT_MS := 8000

; ---------- Tunables: smithing dialog ----------
global SMITHING_MARKER_IMG := A_ScriptDir "\..\images\smithing-marker.png"
global SMITHING_MARKER_IMG_OPTIONS := "*20"
global SMITHING_MARKER_IMG_W := 382
global SMITHING_MARKER_IMG_H := 26
; Top-left (809,247), 382x26 - this user's measured position of the
; make-X dialog's marker, used exactly as given (no center-conversion).
global SMITHING_MARKER_SEARCH_X1 := 809, SMITHING_MARKER_SEARCH_Y1 := 247
global SMITHING_MARKER_SEARCH_X2 := 1191, SMITHING_MARKER_SEARCH_Y2 := 273
global SMITHING_MARKER_TIMEOUT_MS := 15000   ; covers however long the walk-to-anvil + dialog-open takes
global ANVIL_KEY := "Space"                  ; key pressed after the smithing-marker dialog appears - selects the highlighted/default item
global ANVIL_KEY_SETTLE_MS := 300            ; brief wait after pressing ANVIL_KEY, before the first emptiness check - just long enough to cover the dialog closing and smithing starting

; ---------- Tunables: bank marker ----------
global BANK_MARKER_COLOR := 0x0000FF
global BANK_MARKER_TOLERANCE := 20
; 150x100 box centered at (624,756) - this user's measured position of
; the bank plugin marker. Hardcoded default, same reasoning as the
; anvil search box above.
global BANK_SEARCH_X1 := 549, BANK_SEARCH_Y1 := 706
global BANK_SEARCH_X2 := 699, BANK_SEARCH_Y2 := 806
global BANK_CLICK_OFFSET_X := 15, BANK_CLICK_OFFSET_Y := 25
global BANK_SEARCH_TIMEOUT_MS := 8000

global WITHDRAW_SLOT_1_INDEX := 1        ; which bank slot (1-8, left to right - see Grid.ahk's GetBankSlots) to withdraw first
global WITHDRAW_SLOT_2_INDEX := 2        ; which bank slot to withdraw second
global WITHDRAW_INTER_SETTLE_MS := 300   ; pause between the two withdrawal clicks
global WITHDRAW_FINAL_SETTLE_MS := 300   ; pause after the SECOND withdrawal before returning - must be long enough for the inventory display to finish updating, or the next occupancy check reads stale (see BankWithdrawSlot in lib\Bank.ahk)

; Instead of a flat guess for how long the bank-open takes, wait
; until the Deposit All button image is actually visible near its
; known position.
global DEPOSIT_IMG := A_ScriptDir "\..\images\deposit.png"
global BANK_OPEN_SETTLE_MS := 300
global BANK_OPEN_FAILSAFE_DELAY_MS := 300

; ---------- Calibrated values (loaded from INI, or empty if unset) ----------
; emptySlotPoints is a list of {x, y, color} - several reference
; points inside the last inventory slot, all captured by one F1
; press. See IsAnyPointOccupied / WaitUntilNotOccupied (Colors.ahk).
global emptySlotPoints := []

; ---------- Run/walk setting - plain config flag, no hotkey ----------
global runMode := false

; ---------- Library objects built from the above ----------
global runner := NewTaskRunner(150)

; ---------- Init ----------
LoadConfig()

; ============================================================
;  CALIBRATION HOTKEYS
; ============================================================

F1:: {
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

F2:: StartBot()
F3:: StopAndLog(runner, "Stopped (F3)")

F4:: {
    if FileExist(CONFIG)
        FileDelete(CONFIG)
    Reload()
}

; Diagnostic only - doesn't start/stop the bot or change any saved
; value. Runs the EXACT same image search AnvilPhase uses for
; smithing-marker.png, right now, against whatever is on screen - so
; you can open the "make X" dialog by hand, press F5, and get an
; immediate true/false instead of waiting through a full bot cycle.
F5:: {
    global SMITHING_MARKER_SEARCH_X1, SMITHING_MARKER_SEARCH_Y1, SMITHING_MARKER_SEARCH_X2, SMITHING_MARKER_SEARCH_Y2
    global SMITHING_MARKER_IMG, SMITHING_MARKER_IMG_W, SMITHING_MARKER_IMG_H, SMITHING_MARKER_IMG_OPTIONS
    found := FindImageCenter(SMITHING_MARKER_SEARCH_X1, SMITHING_MARKER_SEARCH_Y1, SMITHING_MARKER_SEARCH_X2, SMITHING_MARKER_SEARCH_Y2, SMITHING_MARKER_IMG, SMITHING_MARKER_IMG_W, SMITHING_MARKER_IMG_H, &cx, &cy, SMITHING_MARKER_IMG_OPTIONS)
    if (found)
        ShowTipFor("FOUND smithing-marker.png at " cx "," cy, 3000)
    else
        ShowTipFor("NOT FOUND - searched (" SMITHING_MARKER_SEARCH_X1 "," SMITHING_MARKER_SEARCH_Y1 ") to (" SMITHING_MARKER_SEARCH_X2 "," SMITHING_MARKER_SEARCH_Y2 ") with options '" SMITHING_MARKER_IMG_OPTIONS "'", 3000)
}

; Diagnostic only - same idea as F5, but for the anvil's FF00FF
; marker color instead of the dialog image.
F6:: {
    global ANVIL_SEARCH_X1, ANVIL_SEARCH_Y1, ANVIL_SEARCH_X2, ANVIL_SEARCH_Y2
    global ANVIL_MARKER_COLOR, ANVIL_MARKER_TOLERANCE
    found := PixelSearch(&fx, &fy, ANVIL_SEARCH_X1, ANVIL_SEARCH_Y1, ANVIL_SEARCH_X2, ANVIL_SEARCH_Y2, ANVIL_MARKER_COLOR, ANVIL_MARKER_TOLERANCE)
    if (found)
        ShowTipFor("FOUND anvil marker at " fx "," fy, 3000)
    else
        ShowTipFor("NOT FOUND - searched (" ANVIL_SEARCH_X1 "," ANVIL_SEARCH_Y1 ") to (" ANVIL_SEARCH_X2 "," ANVIL_SEARCH_Y2 ") for " Format("0x{:06X}", ANVIL_MARKER_COLOR) " tol " ANVIL_MARKER_TOLERANCE, 3000)
}

; ============================================================
;  CONFIG LOAD
; ============================================================

LoadConfig() {
    global emptySlotPoints, runMode
    global COLOR_TOLERANCE, WITHDRAW_SLOT_1_INDEX, WITHDRAW_SLOT_2_INDEX
    global ANVIL_SEARCH_X1, ANVIL_SEARCH_Y1, ANVIL_SEARCH_X2, ANVIL_SEARCH_Y2
    global BANK_SEARCH_X1, BANK_SEARCH_Y1, BANK_SEARCH_X2, BANK_SEARCH_Y2

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

    ; Hardcoded search-box defaults (see header comment) - still
    ; overridable by hand-editing the .ini, just never via a hotkey.
    anvilRegion := LoadRegion(CONFIG, "AnvilSearch", ANVIL_SEARCH_X1, ANVIL_SEARCH_Y1, ANVIL_SEARCH_X2, ANVIL_SEARCH_Y2)
    ANVIL_SEARCH_X1 := anvilRegion[1]
    ANVIL_SEARCH_Y1 := anvilRegion[2]
    ANVIL_SEARCH_X2 := anvilRegion[3]
    ANVIL_SEARCH_Y2 := anvilRegion[4]

    bankRegion := LoadRegion(CONFIG, "BankSearch", BANK_SEARCH_X1, BANK_SEARCH_Y1, BANK_SEARCH_X2, BANK_SEARCH_Y2)
    BANK_SEARCH_X1 := bankRegion[1]
    BANK_SEARCH_Y1 := bankRegion[2]
    BANK_SEARCH_X2 := bankRegion[3]
    BANK_SEARCH_Y2 := bankRegion[4]
}

; ============================================================
;  SETUP VALIDATION
; ============================================================

ValidateSetup() {
    global emptySlotPoints, SMITHING_MARKER_IMG, DEPOSIT_IMG
    v := NewValidator()
    RequireNonEmpty(v, "F1 - inventory slot reference points", emptySlotPoints)
    RequireFile(v, "smithing-marker.png (make-X dialog image)", SMITHING_MARKER_IMG)
    RequireFile(v, "deposit.png (bank deposit image)", DEPOSIT_IMG)
    return ShowValidationErrors(v)
}

StartBot() {
    global runner, LOG_FILE, PHASE_TIMEOUT_ANVIL, PHASE_TIMEOUT_BANK
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

; Clicks the anvil marker, confirms the "make X" dialog once
; smithing-marker.png appears, then waits for the calibrated last slot
; to go from occupied to empty (every bar smithed) before moving to
; the bank phase.
AnvilPhase(taskRunner) {
    global emptySlotPoints, runMode, COLOR_TOLERANCE, LOG_FILE
    global ANVIL_MARKER_COLOR, ANVIL_MARKER_TOLERANCE
    global ANVIL_SEARCH_X1, ANVIL_SEARCH_Y1, ANVIL_SEARCH_X2, ANVIL_SEARCH_Y2
    global ANVIL_CLICK_OFFSET_X, ANVIL_CLICK_OFFSET_Y, ANVIL_SEARCH_TIMEOUT_MS
    global SMITHING_MARKER_IMG, SMITHING_MARKER_IMG_OPTIONS, SMITHING_MARKER_IMG_W, SMITHING_MARKER_IMG_H
    global SMITHING_MARKER_SEARCH_X1, SMITHING_MARKER_SEARCH_Y1, SMITHING_MARKER_SEARCH_X2, SMITHING_MARKER_SEARCH_Y2
    global SMITHING_MARKER_TIMEOUT_MS, ANVIL_KEY, ANVIL_KEY_SETTLE_MS
    global ANVIL_TIMEOUT_MS, ANVIL_CONFIRM_TICKS, ANVIL_GUARD_SETTLE_TIMEOUT_MS

    if (!RequireOsrsWindowActive()) {
        LogLine(LOG_FILE, "anvil: OSRS window not focused - paused")
        return GoToPhase(taskRunner, "anvil")
    }

    isRunningFn := () => taskRunner["running"]

    ; If the calibrated slot doesn't read as occupied yet, give it a
    ; short grace window to settle (see ANVIL_GUARD_SETTLE_TIMEOUT_MS
    ; comment above) - a fresh withdrawal can still be rendering. Only
    ; if it NEVER becomes occupied within that window do we treat this
    ; as "the bank ran out of bars" and skip straight to the bank
    ; phase instead of clicking the anvil for nothing.
    if (!WaitUntilOccupied(emptySlotPoints, COLOR_TOLERANCE, ANVIL_GUARD_SETTLE_TIMEOUT_MS, , , isRunningFn)) {
        LogLine(LOG_FILE, "anvil: inventory still empty after settle window - skipping to bank")
        return GoToPhase(taskRunner, "bank")
    }

    if (!WaitForPixelSearch(&fx, &fy, ANVIL_SEARCH_X1, ANVIL_SEARCH_Y1, ANVIL_SEARCH_X2, ANVIL_SEARCH_Y2, ANVIL_MARKER_COLOR, ANVIL_MARKER_TOLERANCE, ANVIL_SEARCH_TIMEOUT_MS, , isRunningFn)) {
        StopAndLog(taskRunner, "Could not find the anvil marker color")
        return GoToPhase(taskRunner, "anvil")
    }

    LogLine(LOG_FILE, "anvil: anvil marker found at " fx "," fy " - clicking with offset")
    HumanClick(fx + ANVIL_CLICK_OFFSET_X, fy + ANVIL_CLICK_OFFSET_Y, 0, 0, runMode)
    ResetPhaseTimer(taskRunner)

    if (!WaitForImageCenter(SMITHING_MARKER_SEARCH_X1, SMITHING_MARKER_SEARCH_Y1, SMITHING_MARKER_SEARCH_X2, SMITHING_MARKER_SEARCH_Y2, SMITHING_MARKER_IMG, SMITHING_MARKER_IMG_W, SMITHING_MARKER_IMG_H, &mcx, &mcy, SMITHING_MARKER_TIMEOUT_MS, SMITHING_MARKER_IMG_OPTIONS, , isRunningFn)) {
        StopAndLog(taskRunner, "Make-X dialog never appeared (smithing-marker.png not found)")
        return GoToPhase(taskRunner, "anvil")
    }

    LogLine(LOG_FILE, "anvil: make-X dialog visible - confirming with " ANVIL_KEY)
    HumanKeyPress(ANVIL_KEY)
    Sleep(JitterDelay(ANVIL_KEY_SETTLE_MS))

    ; Smithing happens automatically once started - just wait for the
    ; calibrated slot to empty out. Same multi-point reference the
    ; mining/smelting scripts use for "is it full", just waiting for
    ; the opposite direction, with the same confirm-ticks debounce so a
    ; single transient glitch can't be mistaken for "done".
    WaitUntilNotOccupied(emptySlotPoints, COLOR_TOLERANCE, ANVIL_TIMEOUT_MS, ANVIL_CONFIRM_TICKS, , isRunningFn)

    ; We made a real attempt (clicked the anvil, confirmed the dialog)
    ; - reset the phase timer so PHASE_TIMEOUT_ANVIL measures "can't
    ; even start smithing for 30s", not "total time spent smithing".
    ResetPhaseTimer(taskRunner)
    LogLine(LOG_FILE, "anvil: inventory emptied - done smithing, moving to bank")
    return GoToPhase(taskRunner, "bank")
}

; Clicks the bank marker, deposits everything, withdraws from bank
; slots 1 and 2 (one click each), then loops back to the anvil phase.
BankPhase(taskRunner) {
    global runMode, LOG_FILE
    global WITHDRAW_SLOT_1_INDEX, WITHDRAW_SLOT_2_INDEX, WITHDRAW_INTER_SETTLE_MS, WITHDRAW_FINAL_SETTLE_MS
    global BANK_MARKER_COLOR, BANK_MARKER_TOLERANCE
    global BANK_SEARCH_X1, BANK_SEARCH_Y1, BANK_SEARCH_X2, BANK_SEARCH_Y2
    global BANK_CLICK_OFFSET_X, BANK_CLICK_OFFSET_Y, BANK_SEARCH_TIMEOUT_MS
    global DEPOSIT_IMG, BANK_OPEN_SETTLE_MS, BANK_OPEN_FAILSAFE_DELAY_MS

    if (!RequireOsrsWindowActive()) {
        LogLine(LOG_FILE, "bank: OSRS window not focused - paused")
        return GoToPhase(taskRunner, "bank")
    }

    isRunningFn := () => taskRunner["running"]

    if (!WaitForPixelSearch(&fx, &fy, BANK_SEARCH_X1, BANK_SEARCH_Y1, BANK_SEARCH_X2, BANK_SEARCH_Y2, BANK_MARKER_COLOR, BANK_MARKER_TOLERANCE, BANK_SEARCH_TIMEOUT_MS, , isRunningFn)) {
        StopAndLog(taskRunner, "Could not find the bank marker color")
        return GoToPhase(taskRunner, "bank")
    }

    LogLine(LOG_FILE, "bank: bank marker found at " fx "," fy " - clicking with offset")
    HumanClick(fx + BANK_CLICK_OFFSET_X, fy + BANK_CLICK_OFFSET_Y, 0, 0, runMode)
    ResetPhaseTimer(taskRunner)

    ; Open the bank and deposit everything (shared lib\Bank.ahk).
    if (!BankDepositAll(DEPOSIT_IMG, BANK_OPEN_SETTLE_MS, BANK_OPEN_FAILSAFE_DELAY_MS, , , , , , isRunningFn)) {
        StopAndLog(taskRunner, "Bank never opened (Deposit All button not found)")
        return GoToPhase(taskRunner, "bank")
    }

    ; Withdraw from both slots. The second settle is longer than the
    ; gap between the two clicks because the next phase immediately
    ; checks "is the last slot occupied" - too soon after the click
    ; that reads stale (the inventory display hadn't finished
    ; updating yet).
    LogLine(LOG_FILE, "bank: deposited, withdrawing slot " WITHDRAW_SLOT_1_INDEX " then " WITHDRAW_SLOT_2_INDEX)
    BankWithdrawSlot(WITHDRAW_SLOT_1_INDEX, WITHDRAW_INTER_SETTLE_MS)
    BankWithdrawSlot(WITHDRAW_SLOT_2_INDEX, WITHDRAW_FINAL_SETTLE_MS)

    LogLine(LOG_FILE, "bank: done withdrawing, returning to anvil phase")
    return GoToPhase(taskRunner, "anvil")
}
