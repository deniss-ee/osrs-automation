; ============================================================
;  auto-smelter.ahk
;  Smelting bot, built entirely from the shared lib\ functions -
;  same library auto-cooker.ahk, auto-miner.ahk, auto-fisher.ahk
;  and auto-smith.ahk use.
;
;  EXPECTED STARTING STATE: standing near the bank with a full
;  inventory of ore.
;
;  CYCLE (marker-based, same shape as auto-cooker.ahk - no recorded
;  paths anywhere; every "walk" is triggered by clicking a colored
;  plugin marker that the game/plugin handles automatically):
;    1. Find the furnace marker color (SMELTER_MARKER_COLOR) in the
;       calibrated SMELTER search box and click it with a fixed
;       offset - same "marker color, fixed-offset click" pattern
;       auto-cooker.ahk's campfire click uses.
;    2. Wait for smelting-marker.png to appear (the "Smelt X"
;       dialog), then press SMELT_KEY (Space by default, or a number
;       key like "1"/"2"/"3") to confirm it - exactly like
;       auto-cooker.ahk's COOK_CONFIRM_KEY confirming the "Cook X"
;       dialog.
;    3. Smelting happens automatically once started - wait for the
;       calibrated inventory slot (last, or second-to-last - see
;       checkPreviousSlot below) to go from full to empty, the same
;       multi-point reference every other script uses for "is it
;       full"/"is it empty".
;    4. Find the bank marker color (BANK_MARKER_COLOR) in the
;       calibrated BANK search box and click it with a fixed offset -
;       same marker-click pattern as step 1, this one walks to and
;       opens the bank automatically.
;    5. Wait for deposit.png (the bank's Deposit All button) and
;       click it - shared lib\Bank.ahk, same as every other script.
;    6. Withdraw a fresh stack of materials following
;       WITHDRAW_SEQUENCE below - an ORDERED list of {slot, count}
;       entries (e.g. slot 1 twice, then slot 2 once), then start
;       over from step 1.
;
;  WHY THE SMELTER/BANK SEARCH BOXES ARE HARDCODED DEFAULTS, NOT A
;  HOTKEY CALIBRATION: both are fixed, UI-anchored plugin markers, not
;  world/camera-dependent positions - same reasoning as
;  auto-cooker.ahk's CAMPFIRE_SEARCH_*/BANK_RUN_SEARCH_*. They're
;  still overridable by hand-editing the .ini if your setup ever
;  differs.
;
;  EXPECTED STARTING STATE (calibration): inventory EMPTY when you
;  press F1.
;
;  HOTKEYS
;    F1   = save "inventory slot" reference points - EMPTY YOUR
;           INVENTORY first, then press F1. Samples FOUR points
;           spread around the LAST inventory slot (or the
;           SECOND-TO-LAST slot if checkPreviousSlot=1 in the .ini -
;           see below), same mechanism as every other script's
;           emptySlotPoints - the bot uses these to detect both "ore
;           ran out" and "inventory full".
;    F2   = start the bot
;    F3   = stop the bot
;    F4   = clear saved config and reload the script
;
;  RUN MODE is a plain setting in the .ini, not a hotkey - same as
;  the other scripts. Open config\auto-smelter.ini, find [Settings], set
;
;      runMode=1   (hold Ctrl / run for every click)
;      runMode=0   (never hold Ctrl / always walk - the default)
;
;  CHECK-PREVIOUS-SLOT is also a plain .ini flag, not a hotkey -
;  some smelting recipes (or some inventory layouts) never actually
;  fill the very last slot even when "full" (e.g. an odd ore count
;  that always leaves slot 28 empty), which would make the
;  last-slot reference useless. Set
;
;      checkPreviousSlot=1   (F1 calibrates/checks the SECOND-TO-
;                              LAST slot, slot 27, instead of 28)
;      checkPreviousSlot=0   (the default - last slot, slot 28)
;
;  then re-run F1 and restart the script (this changes WHICH slot
;  F1 samples, so existing calibration must be redone after
;  flipping it).
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
#Include ..\lib\Bank.ahk
#Include ..\lib\Validate.ahk
#Include ..\lib\TaskRunner.ahk
#Include ..\lib\Log.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

; ---------- Config file ----------
global CONFIG := A_ScriptDir "\..\config\auto-smelter.ini"

; ---------- Debug log ----------
global LOG_FILE := A_ScriptDir "\..\logs\auto-smelter-debug.log"

; Stops the runner AND records why in the debug log, so a stop that
; happens off-screen (or whose tooltip you miss) is never a mystery -
; just open auto-smelter-debug.log afterward.
StopAndLog(taskRunner, reason) {
    global LOG_FILE
    LogLine(LOG_FILE, "STOPPED: " reason)
    StopTaskRunner(taskRunner, reason)
}

; ---------- Humanization: off by default ----------
global ENABLE_HUMANIZATION := false

; ---------- Tunables: inventory check ----------
global COLOR_TOLERANCE := 20
global SMELT_TIMEOUT_MS := 180000        ; max time to wait for the inventory to empty out after starting a smelt (3 min) - raise this if you smelt a slower ore/bar
global SMELT_CONFIRM_TICKS := 2          ; require "empty" to read true for this many consecutive ~100ms polls before trusting it (filters a transient glitch)
; Right after a bank withdrawal, the inventory display can take a
; moment to actually render ~28 freshly-withdrawn (non-stacking) ore -
; an instantaneous check right then can misread the slot as still
; empty even though ore was genuinely just withdrawn, which would
; bounce straight back to BankPhase forever without ever clicking the
; furnace again. Same fix as auto-cooker.ahk's COOK_GUARD_SETTLE_TIMEOUT_MS -
; give the slot a short grace window to settle into "occupied" before
; believing it's genuinely empty.
global SMELT_GUARD_SETTLE_TIMEOUT_MS := 3000
global PHASE_TIMEOUT_SMELT := 30000      ; give up and stop if we can't even START a smelt attempt (e.g. window unfocused) for this long
global PHASE_TIMEOUT_BANK := 30000       ; give up and stop if banking hangs for 30s straight

; ---------- Tunables: furnace marker ----------
global SMELTER_MARKER_COLOR := 0xFF00FF
global SMELTER_MARKER_TOLERANCE := 20
; 125x150 box centered at (1800,393) - this user's measured position of
; the furnace's plugin marker. Hardcoded default, see header comment
; for why this isn't a hotkey-calibrated region.
global SMELTER_SEARCH_X1 := 1738, SMELTER_SEARCH_Y1 := 318
global SMELTER_SEARCH_X2 := 1863, SMELTER_SEARCH_Y2 := 468
global SMELTER_CLICK_OFFSET_X := 15, SMELTER_CLICK_OFFSET_Y := 25
global SMELTER_SEARCH_TIMEOUT_MS := 8000

; ---------- Tunables: smelting dialog ----------
global SMELTING_MARKER_IMG := A_ScriptDir "\..\images\smelting-marker.png"
; This capture is noticeably noisier than auto-cooker.ahk's
; cooking-marker.png (18KB vs 4KB for a similar-size crop, far more
; unique colors sampled) - likely some compression/anti-aliasing
; artifact from how it was captured. *20 was too strict a shade
; tolerance for a file this noisy and never matched live - raised to
; *60 to compensate.
global SMELTING_MARKER_IMG_OPTIONS := "*20"
global SMELTING_MARKER_IMG_W := 386
global SMELTING_MARKER_IMG_H := 32
; Top-left (185,1081), 386x32, confirmed correct against this user's
; setup - widened by a 10px margin on every side (search box is now
; LARGER than the image) so a few pixels of position drift still
; finds it, since ImageSearch only requires the image to fit
; somewhere inside the search box, not fill it exactly.
global SMELTING_MARKER_SEARCH_X1 := 175, SMELTING_MARKER_SEARCH_Y1 := 1071
global SMELTING_MARKER_SEARCH_X2 := 581, SMELTING_MARKER_SEARCH_Y2 := 1123
global SMELTING_MARKER_TIMEOUT_MS := 15000   ; covers however long the walk-to-furnace + dialog-open takes
global SMELT_KEY := "Space"              ; key pressed after the smelting-marker dialog appears - "Space" selects the highlighted/default bar, or use a number key ("1","2","3") if the dialog needs a specific bar selected
global SMELT_KEY_SETTLE_MS := 100        ; brief wait after pressing SMELT_KEY, before the first emptiness check - just long enough to cover the dialog closing and smelting starting

; ---------- Tunables: bank marker ----------
global BANK_MARKER_COLOR := 0x0000FF
global BANK_MARKER_TOLERANCE := 20
; 200x150 box centered at (432,987) - this user's measured position of
; the bank plugin marker. Hardcoded default, same reasoning as the
; furnace search box above.
global BANK_SEARCH_X1 := 332, BANK_SEARCH_Y1 := 912
global BANK_SEARCH_X2 := 532, BANK_SEARCH_Y2 := 1062
global BANK_CLICK_OFFSET_X := 15, BANK_CLICK_OFFSET_Y := 25
global BANK_SEARCH_TIMEOUT_MS := 8000

; Ordered withdraw plan: an array of {slot, count} entries, each
; one bank slot index (1-8, left to right - see Grid.ahk's
; GetBankSlots) and how many times to click it in a row before
; moving to the next entry. Lets a trip withdraw from more than one
; bank slot (e.g. two different raw materials) and click some of
; them more than once (e.g. a slot whose "withdraw all" doesn't
; cover a full inventory's worth on its own). Example below:
; withdraws bank slot 1 twice, then bank slot 2 once.
global WITHDRAW_SEQUENCE := [
    Map("slot", 1, "count", 2),
    Map("slot", 2, "count", 1)
]
global WITHDRAW_INTER_SETTLE_MS := 600   ; pause after every withdrawal click EXCEPT the very last one in the whole sequence
global WITHDRAW_FINAL_SETTLE_MS := 300   ; pause after the LAST withdrawal click in the sequence - must be long enough for the inventory display to finish updating, or the next occupancy check reads stale (see BankWithdrawSlot in lib\Bank.ahk)

; Instead of a flat guess for how long the bank-open takes, wait
; until the Deposit All button image is actually visible near its
; known position.
global DEPOSIT_IMG := A_ScriptDir "\..\images\deposit.png"
global BANK_OPEN_SETTLE_MS := 300
global BANK_OPEN_FAILSAFE_DELAY_MS := 300

; ---------- Calibrated values (loaded from INI, or empty if unset) ----------
; emptySlotPoints is a list of {x, y, color} - several reference
; points inside the calibrated slot (last, or second-to-last if
; checkPreviousSlot is set), all captured by one F1 press. See
; IsAnyPointOccupied / WaitUntilNotOccupied (Colors.ahk).
global emptySlotPoints := []

; ---------- Run/walk setting - plain config flag, no hotkey ----------
global runMode := false

; ---------- Inventory-full reference slot - plain config flag, no hotkey ----------
; false (default) = F1 calibrates/checks the LAST inventory slot.
; true = F1 calibrates/checks the SECOND-TO-LAST slot instead, for
; recipes/layouts where the very last slot never actually fills.
global checkPreviousSlot := false

; ---------- Library objects built from the above ----------
global runner := NewTaskRunner(150)

; ---------- Init ----------
LoadConfig()

; ============================================================
;  CALIBRATION HOTKEYS
; ============================================================

F1:: {
    global emptySlotPoints, checkPreviousSlot
    ; Uses the standard 28-slot inventory grid from Grid.ahk to
    ; find the LAST slot (or the SECOND-TO-LAST slot if
    ; checkPreviousSlot is set), then samples 4 points spread
    ; around it (GetDefaultSlotOffsets) instead of just its one
    ; center pixel - make sure your inventory is empty before
    ; pressing this.
    slots := GetInventorySlots()
    slotIndex := checkPreviousSlot ? slots.Length - 1 : slots.Length
    targetSlot := slots[slotIndex]
    points := GetSlotSamplePoints(targetSlot, GetDefaultSlotOffsets())
    for p in points
        p["color"] := PixelGetColor(p["x"], p["y"], "RGB")
    emptySlotPoints := points
    SaveColorPointList(CONFIG, "InventoryEmptyPoints", emptySlotPoints)
    ShowTipFor("Empty-slot reference points saved (slot " slotIndex " of " slots.Length ") - make sure inventory was empty!", 1800)
}

F2:: StartBot()
F3:: StopAndLog(runner, "Stopped (F3)")

F4:: {
    if FileExist(CONFIG)
        FileDelete(CONFIG)
    Reload()
}

; Diagnostic only - doesn't start/stop the bot or change any saved
; value. Runs the EXACT same image search SmeltPhase uses for
; smelting-marker.png, right now, against whatever is on screen -
; so you can open the "Smelt X" dialog by hand, press F5, and get an
; immediate true/false instead of waiting through a full bot cycle
; to find out whether the image search itself is the problem.
F5:: {
    global SMELTING_MARKER_SEARCH_X1, SMELTING_MARKER_SEARCH_Y1, SMELTING_MARKER_SEARCH_X2, SMELTING_MARKER_SEARCH_Y2
    global SMELTING_MARKER_IMG, SMELTING_MARKER_IMG_W, SMELTING_MARKER_IMG_H, SMELTING_MARKER_IMG_OPTIONS
    found := FindImageCenter(SMELTING_MARKER_SEARCH_X1, SMELTING_MARKER_SEARCH_Y1, SMELTING_MARKER_SEARCH_X2, SMELTING_MARKER_SEARCH_Y2, SMELTING_MARKER_IMG, SMELTING_MARKER_IMG_W, SMELTING_MARKER_IMG_H, &cx, &cy, SMELTING_MARKER_IMG_OPTIONS)
    if (found)
        ShowTipFor("FOUND smelting-marker.png at " cx "," cy, 3000)
    else
        ShowTipFor("NOT FOUND - searched (" SMELTING_MARKER_SEARCH_X1 "," SMELTING_MARKER_SEARCH_Y1 ") to (" SMELTING_MARKER_SEARCH_X2 "," SMELTING_MARKER_SEARCH_Y2 ") with options '" SMELTING_MARKER_IMG_OPTIONS "'", 3000)
}

; Diagnostic only - same idea as F5, but for the furnace's FF00FF
; marker color instead of the dialog image. Run this RIGHT NOW (bot
; doesn't need to be running) while the furnace marker is visible on
; screen, to find out whether the search box/color/tolerance are the
; problem, independent of everything else in the cycle.
F6:: {
    global SMELTER_SEARCH_X1, SMELTER_SEARCH_Y1, SMELTER_SEARCH_X2, SMELTER_SEARCH_Y2
    global SMELTER_MARKER_COLOR, SMELTER_MARKER_TOLERANCE
    found := PixelSearch(&fx, &fy, SMELTER_SEARCH_X1, SMELTER_SEARCH_Y1, SMELTER_SEARCH_X2, SMELTER_SEARCH_Y2, SMELTER_MARKER_COLOR, SMELTER_MARKER_TOLERANCE)
    if (found)
        ShowTipFor("FOUND furnace marker at " fx "," fy, 3000)
    else
        ShowTipFor("NOT FOUND - searched (" SMELTER_SEARCH_X1 "," SMELTER_SEARCH_Y1 ") to (" SMELTER_SEARCH_X2 "," SMELTER_SEARCH_Y2 ") for " Format("0x{:06X}", SMELTER_MARKER_COLOR) " tol " SMELTER_MARKER_TOLERANCE, 3000)
}

; ============================================================
;  CONFIG LOAD
; ============================================================

LoadConfig() {
    global emptySlotPoints, runMode, checkPreviousSlot
    global COLOR_TOLERANCE, SMELT_KEY, WITHDRAW_SEQUENCE
    global SMELTER_SEARCH_X1, SMELTER_SEARCH_Y1, SMELTER_SEARCH_X2, SMELTER_SEARCH_Y2
    global BANK_SEARCH_X1, BANK_SEARCH_Y1, BANK_SEARCH_X2, BANK_SEARCH_Y2

    emptySlotPoints := LoadColorPointList(CONFIG, "InventoryEmptyPoints")

    ; Plain on/off settings, edited directly in the .ini - see the
    ; "RUN MODE" / "CHECK-PREVIOUS-SLOT" notes in the header
    ; comment. Neither one is a hotkey.
    runMode := LoadFlag(CONFIG, "Settings", "runMode", false)
    checkPreviousSlot := LoadFlag(CONFIG, "Settings", "checkPreviousSlot", false)

    ; Curated tunables - overwrite the hardcoded defaults above from
    ; the .ini if present, so these can be tweaked without editing
    ; this file (e.g. from the control panel).
    COLOR_TOLERANCE := LoadNumber(CONFIG, "Tunables", "colorTolerance", COLOR_TOLERANCE)
    SMELT_KEY := LoadString(CONFIG, "Tunables", "smeltKey", SMELT_KEY)
    ; WITHDRAW_SEQUENCE keeps its hardcoded array (set above) as the
    ; fallback default if the ini section is empty/unset - LoadSlotSequence
    ; returns [] for "never saved", which isn't a usable withdraw plan.
    loadedSequence := LoadSlotSequence(CONFIG, "WithdrawSequence")
    if (loadedSequence.Length > 0)
        WITHDRAW_SEQUENCE := loadedSequence

    ; Hardcoded search-box defaults (see header comment) - still
    ; overridable by hand-editing the .ini, just never via a hotkey.
    smelterRegion := LoadRegion(CONFIG, "SmelterSearch", SMELTER_SEARCH_X1, SMELTER_SEARCH_Y1, SMELTER_SEARCH_X2, SMELTER_SEARCH_Y2)
    SMELTER_SEARCH_X1 := smelterRegion[1]
    SMELTER_SEARCH_Y1 := smelterRegion[2]
    SMELTER_SEARCH_X2 := smelterRegion[3]
    SMELTER_SEARCH_Y2 := smelterRegion[4]

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
    global emptySlotPoints, SMELTING_MARKER_IMG, DEPOSIT_IMG, WITHDRAW_SEQUENCE
    v := NewValidator()
    RequireNonEmpty(v, "F1 - inventory slot reference points", emptySlotPoints)
    RequireFile(v, "smelting-marker.png (smelt dialog image)", SMELTING_MARKER_IMG)
    RequireFile(v, "deposit.png (bank deposit image)", DEPOSIT_IMG)
    RequireNonEmpty(v, "WITHDRAW_SEQUENCE (withdraw plan)", WITHDRAW_SEQUENCE)
    return ShowValidationErrors(v)
}

StartBot() {
    global runner, LOG_FILE, PHASE_TIMEOUT_SMELT, PHASE_TIMEOUT_BANK
    if (!ValidateSetup())
        return

    AddPhase(runner, "smelt", SmeltPhase, PHASE_TIMEOUT_SMELT)
    AddPhase(runner, "bank", BankPhase, PHASE_TIMEOUT_BANK)
    StartTaskRunner(runner, "smelt")
    ShowTipFor("Bot started", 1000)
    LogLine(LOG_FILE, "===== Bot started =====")
}

; ============================================================
;  PHASES
; ============================================================

; Clicks the furnace marker, confirms the "Smelt X" dialog once
; smelting-marker.png appears, then waits for the calibrated slot to
; go from occupied to empty (every bit of ore smelted) before moving
; to the bank phase.
SmeltPhase(taskRunner) {
    global emptySlotPoints, runMode, COLOR_TOLERANCE, LOG_FILE
    global SMELTER_MARKER_COLOR, SMELTER_MARKER_TOLERANCE
    global SMELTER_SEARCH_X1, SMELTER_SEARCH_Y1, SMELTER_SEARCH_X2, SMELTER_SEARCH_Y2
    global SMELTER_CLICK_OFFSET_X, SMELTER_CLICK_OFFSET_Y, SMELTER_SEARCH_TIMEOUT_MS
    global SMELTING_MARKER_IMG, SMELTING_MARKER_IMG_OPTIONS, SMELTING_MARKER_IMG_W, SMELTING_MARKER_IMG_H
    global SMELTING_MARKER_SEARCH_X1, SMELTING_MARKER_SEARCH_Y1, SMELTING_MARKER_SEARCH_X2, SMELTING_MARKER_SEARCH_Y2
    global SMELTING_MARKER_TIMEOUT_MS, SMELT_KEY, SMELT_KEY_SETTLE_MS
    global SMELT_TIMEOUT_MS, SMELT_CONFIRM_TICKS, SMELT_GUARD_SETTLE_TIMEOUT_MS

    if (!RequireOsrsWindowActive()) {
        LogLine(LOG_FILE, "smelt: OSRS window not focused - paused")
        return GoToPhase(taskRunner, "smelt")
    }

    isRunningFn := () => taskRunner["running"]

    ; If the calibrated slot doesn't read as occupied yet, give it a
    ; short grace window to settle (see SMELT_GUARD_SETTLE_TIMEOUT_MS
    ; comment above) - a fresh withdrawal can still be rendering. Only
    ; if it NEVER becomes occupied within that window do we treat this
    ; as "the bank ran out of ore to withdraw" and skip straight to the
    ; bank phase instead of clicking the furnace for nothing.
    if (!WaitUntilOccupied(emptySlotPoints, COLOR_TOLERANCE, SMELT_GUARD_SETTLE_TIMEOUT_MS, , , isRunningFn)) {
        LogLine(LOG_FILE, "smelt: inventory still empty after settle window - skipping to bank")
        return GoToPhase(taskRunner, "bank")
    }

    if (!WaitForPixelSearch(&fx, &fy, SMELTER_SEARCH_X1, SMELTER_SEARCH_Y1, SMELTER_SEARCH_X2, SMELTER_SEARCH_Y2, SMELTER_MARKER_COLOR, SMELTER_MARKER_TOLERANCE, SMELTER_SEARCH_TIMEOUT_MS, , isRunningFn)) {
        StopAndLog(taskRunner, "Could not find the furnace marker color")
        return GoToPhase(taskRunner, "smelt")
    }

    LogLine(LOG_FILE, "smelt: furnace marker found at " fx "," fy " - clicking with offset")
    HumanClick(fx + SMELTER_CLICK_OFFSET_X, fy + SMELTER_CLICK_OFFSET_Y, 0, 0, runMode)
    ResetPhaseTimer(taskRunner)

    if (!WaitForImageCenter(SMELTING_MARKER_SEARCH_X1, SMELTING_MARKER_SEARCH_Y1, SMELTING_MARKER_SEARCH_X2, SMELTING_MARKER_SEARCH_Y2, SMELTING_MARKER_IMG, SMELTING_MARKER_IMG_W, SMELTING_MARKER_IMG_H, &mcx, &mcy, SMELTING_MARKER_TIMEOUT_MS, SMELTING_MARKER_IMG_OPTIONS, , isRunningFn)) {
        StopAndLog(taskRunner, "Smelt dialog never appeared (smelting-marker.png not found)")
        return GoToPhase(taskRunner, "smelt")
    }

    LogLine(LOG_FILE, "smelt: smelt dialog visible - confirming with " SMELT_KEY)
    HumanKeyPress(SMELT_KEY)
    Sleep(JitterDelay(SMELT_KEY_SETTLE_MS))

    ; Smelting happens automatically once started - just wait for
    ; the calibrated slot to empty out. Same multi-point reference
    ; the mining script uses for "is it full", just waiting for the
    ; opposite direction, with the same confirm-ticks debounce so a
    ; single transient glitch can't be mistaken for "done".
    WaitUntilNotOccupied(emptySlotPoints, COLOR_TOLERANCE, SMELT_TIMEOUT_MS, SMELT_CONFIRM_TICKS, , isRunningFn)

    ; We made a real attempt (clicked the furnace, confirmed the
    ; dialog) - reset the phase timer so PHASE_TIMEOUT_SMELT measures
    ; "can't even start a smelt attempt for 30s", not "total time
    ; spent smelting".
    ResetPhaseTimer(taskRunner)
    LogLine(LOG_FILE, "smelt: inventory emptied - done smelting, moving to bank")
    return GoToPhase(taskRunner, "bank")
}

; Clicks the bank marker, deposits everything, withdraws materials
; following WITHDRAW_SEQUENCE (one or more bank slots, each clicked
; its configured number of times in a row), then loops back to the
; smelt phase.
BankPhase(taskRunner) {
    global runMode, LOG_FILE, WITHDRAW_SEQUENCE
    global WITHDRAW_INTER_SETTLE_MS, WITHDRAW_FINAL_SETTLE_MS
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

    ; Withdraw every {slot, count} entry in WITHDRAW_SEQUENCE, in
    ; order, clicking each slot its configured number of times in a
    ; row before moving to the next entry. Every click except the
    ; very last one in the whole sequence uses the shorter inter-
    ; click settle; the last one uses the longer final settle so the
    ; inventory display has time to catch up before the next phase
    ; checks occupancy.
    totalClicks := 0
    for entry in WITHDRAW_SEQUENCE
        totalClicks += entry["count"]

    clicksDone := 0
    for entry in WITHDRAW_SEQUENCE {
        loop entry["count"] {
            clicksDone += 1
            settle := (clicksDone = totalClicks) ? WITHDRAW_FINAL_SETTLE_MS : WITHDRAW_INTER_SETTLE_MS
            BankWithdrawSlot(entry["slot"], settle)
        }
    }

    LogLine(LOG_FILE, "bank: done withdrawing, returning to smelt phase")
    return GoToPhase(taskRunner, "smelt")
}
