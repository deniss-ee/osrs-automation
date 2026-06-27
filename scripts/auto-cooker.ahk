; ============================================================
;  auto-cooker.ahk
;  Cooking bot, built entirely from the shared lib\ functions -
;  same library auto-smelter.ahk, auto-miner.ahk, auto-fisher.ahk
;  and auto-smith.ahk use.
;
;  EXPECTED STARTING STATE: standing near the bank with a full
;  inventory of uncooked food.
;
;  CYCLE:
;    1. Find the campfire marker color (CAMPFIRE_MARKER_COLOR) in
;       the calibrated CAMPFIRE search box and click it with a
;       fixed offset - same "marker color, fixed-offset click"
;       pattern auto-fisher.ahk/auto-motherlode.ahk use for their
;       bank markers. This is a plugin highlight, not the campfire's
;       own pixel - clicking it walks to and clicks the campfire
;       automatically.
;    2. Wait for cooking-marker.png to appear (the "Cook X" dialog),
;       then press COOK_CONFIRM_KEY (Space by default) to confirm it
;       - exactly like auto-smelter.ahk's SMELT_KEY confirming the
;       "Smelt X" dialog.
;    3. Cooking happens automatically once started - wait for the
;       calibrated LAST inventory slot's color to change away from
;       raw food's color (cooked or burnt, doesn't matter which) -
;       the same multi-point reference/occupancy check every other
;       script uses for "is it full"/"is it empty", just checking for
;       "no longer the calibrated color" instead.
;    4. Find the bank-run marker color (BANK_RUN_MARKER_COLOR) in the
;       calibrated BANK-RUN search box and click it with a fixed
;       offset - same marker-click pattern as step 1, this one walks
;       to and opens the bank automatically.
;    5. Wait for deposit.png (the bank's Deposit All button) and
;       click it - shared lib\Bank.ahk, same as every other script.
;    6. Withdraw a fresh stack of raw food from WITHDRAW_SLOT_INDEX
;       (bank slot 1 by default), then start over from step 1.
;
;  WHY THE CAMPFIRE/BANK-RUN SEARCH BOXES ARE HARDCODED DEFAULTS, NOT
;  A HOTKEY CALIBRATION: both are fixed, UI-anchored plugin markers,
;  not world/camera-dependent positions - same reasoning as
;  auto-fisher.ahk's BANK_MARKER_SEARCH_X1/Y1/X2/Y2 (hardcoded
;  defaults, never calibrated via a hotkey, because that marker
;  doesn't move with the camera either). They're still overridable by
;  hand-editing the .ini if your setup ever differs.
;
;  EXPECTED STARTING STATE (calibration): raw food sitting in the
;  LAST inventory slot when you press F1.
;
;  HOTKEYS
;    F1   = save "raw food" reference points - make sure the LAST
;           inventory slot holds RAW (uncooked) food, then press F1.
;           Samples FOUR points spread around that slot, same
;           mechanism as every other script's emptySlotPoints - the
;           bot waits for this exact color to go away to know cooking
;           finished.
;    F2   = start the bot
;    F3   = stop the bot
;    F4   = clear saved config and reload the script
;
;  RUN MODE is a plain setting in the .ini, not a hotkey - same as
;  the other scripts. Open config\auto-cooker.ini, find [Settings], set
;
;      runMode=1   (hold Ctrl / run for every click)
;      runMode=0   (never hold Ctrl / always walk - the default)
;
;  then restart the script.
;
;  Config auto-saves to config\auto-cooker.ini next to this file.
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
global CONFIG := A_ScriptDir "\..\config\auto-cooker.ini"

; ---------- Debug log ----------
global LOG_FILE := A_ScriptDir "\..\logs\auto-cooker-debug.log"

; Stops the runner AND records why in the debug log, so a stop that
; happens off-screen (or whose tooltip you miss) is never a mystery -
; just open auto-cooker-debug.log afterward.
StopAndLog(taskRunner, reason) {
    global LOG_FILE
    LogLine(LOG_FILE, "STOPPED: " reason)
    StopTaskRunner(taskRunner, reason)
}

; ---------- Humanization: off by default ----------
global ENABLE_HUMANIZATION := false

; ---------- Tunables: inventory check ----------
global COLOR_TOLERANCE := 20

; ---------- Tunables: campfire marker ----------
global CAMPFIRE_MARKER_COLOR := 0xFF00FF
global CAMPFIRE_MARKER_TOLERANCE := 20
; 250x250 box, top-left (1621,376) - this user's measured position of
; the campfire's plugin marker. Hardcoded default, see header comment
; for why this isn't a hotkey-calibrated region.
global CAMPFIRE_SEARCH_X1 := 1621, CAMPFIRE_SEARCH_Y1 := 376
global CAMPFIRE_SEARCH_X2 := 1871, CAMPFIRE_SEARCH_Y2 := 626
global CAMPFIRE_CLICK_OFFSET_X := 20, CAMPFIRE_CLICK_OFFSET_Y := 20
global CAMPFIRE_SEARCH_TIMEOUT_MS := 8000

; ---------- Tunables: cooking dialog ----------
global COOKING_MARKER_IMG := A_ScriptDir "\..\images\cooking-marker.png"
global COOKING_MARKER_IMG_OPTIONS := "*20"   ; direct screenshot, matches its exact size - just a little shade tolerance, no transparency trick needed
global COOKING_MARKER_IMG_W := 436
global COOKING_MARKER_IMG_H := 32
; Top-left (125,1081), 436x32 - this user's measured position of the
; "Cook X" dialog's marker. Hardcoded default, same reasoning as the
; campfire/bank-run search boxes.
global COOKING_MARKER_SEARCH_X1 := 125, COOKING_MARKER_SEARCH_Y1 := 1081
global COOKING_MARKER_SEARCH_X2 := 561, COOKING_MARKER_SEARCH_Y2 := 1113
global COOKING_MARKER_TIMEOUT_MS := 15000   ; covers however long the walk-to-campfire + dialog-open takes
global COOK_CONFIRM_KEY := "Space"          ; key pressed to confirm the "Cook X" dialog - same role as auto-smelter.ahk's SMELT_KEY
global COOK_KEY_SETTLE_MS := 100            ; brief wait after pressing COOK_CONFIRM_KEY, before the first "still raw" check

; ---------- Tunables: cooking completion ----------
global COOK_DONE_TIMEOUT_MS := 180000       ; max time to wait for the last slot's color to change (3 min) - raise this if cooking a slower food
global COOK_DONE_CONFIRM_TICKS := 2         ; require "changed" to read true for this many consecutive polls before trusting it (filters a transient glitch)
; Right after a bank withdrawal, the inventory display can take a
; moment to actually render ~28 freshly-withdrawn (non-stacking) raw
; items - confirmed via the debug log: the very first poll of the next
; CookPhase read the last slot as "still not raw" immediately after
; "done, returning to cook phase", even though raw food genuinely had
; just been withdrawn. A single instantaneous check can't tell that
; apart from a real "bank ran out of raw food" case, so instead of
; trusting an instant read, this gives the slot a short grace window
; to settle into "raw" before believing it's genuinely empty/depleted.
global COOK_GUARD_SETTLE_TIMEOUT_MS := 3000
global PHASE_TIMEOUT_COOK := 30000          ; give up and stop if we can't even START a cook attempt (e.g. window unfocused) for this long
global PHASE_TIMEOUT_BANK := 30000          ; give up and stop if banking hangs for 30s straight

; ---------- Tunables: bank-run marker ----------
global BANK_RUN_MARKER_COLOR := 0x0000FF
global BANK_RUN_MARKER_TOLERANCE := 20
; 250x250 box, top-left (448,1030) - this user's measured position of
; the bank-run plugin marker. Hardcoded default, same reasoning as the
; campfire search box above.
global BANK_RUN_SEARCH_X1 := 448, BANK_RUN_SEARCH_Y1 := 1030
global BANK_RUN_SEARCH_X2 := 698, BANK_RUN_SEARCH_Y2 := 1280
global BANK_RUN_CLICK_OFFSET_X := 20, BANK_RUN_CLICK_OFFSET_Y := 20
global BANK_RUN_SEARCH_TIMEOUT_MS := 8000

; ---------- Tunables: bank deposit/withdraw ----------
; deposit.png's default search position (lib\Grid.ahk's
; GetDepositAllButton) is already this user's measured button -
; top-left (1327,963), 72x72 -> center (1363,999) - so no new region
; is needed here, BankDepositAll() is used exactly as every other
; script uses it.
global DEPOSIT_IMG := A_ScriptDir "\..\images\deposit.png"
global BANK_OPEN_SETTLE_MS := 300
global BANK_OPEN_FAILSAFE_DELAY_MS := 300
global WITHDRAW_SLOT_INDEX := 1             ; which bank slot (1-8, left to right - see Grid.ahk's GetBankSlots) holds the raw food to withdraw
global WITHDRAW_SETTLE_MS := 300            ; pause after the withdrawal click before the next cook attempt - needs to be long enough for the inventory display to finish updating

; ---------- Calibrated values (loaded from INI, or empty if unset) ----------
; rawFoodPoints is a list of {x, y, color} - several reference points
; inside the last inventory slot, sampled while RAW food sits there,
; all captured by one F1 press. See IsAnyPointOccupied/WaitUntilOccupied
; (Colors.ahk) - "occupied" here means "no longer this calibrated raw
; color", i.e. cooked or burnt.
global rawFoodPoints := []

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
    global rawFoodPoints
    ; Uses the standard 28-slot inventory grid from Grid.ahk to find
    ; the LAST slot, then samples 4 points spread around it
    ; (GetDefaultSlotOffsets) instead of just its one center pixel -
    ; make sure raw food is sitting in that slot before pressing.
    slots := GetInventorySlots()
    lastSlot := slots[slots.Length]
    points := GetSlotSamplePoints(lastSlot, GetDefaultSlotOffsets())
    for p in points
        p["color"] := PixelGetColor(p["x"], p["y"], "RGB")
    rawFoodPoints := points
    SaveColorPointList(CONFIG, "RawFoodPoints", rawFoodPoints)
    ShowTipFor("Raw-food reference points saved (make sure last slot held RAW food!)", 1800)
}

F2:: StartBot()
F3:: StopAndLog(runner, "Stopped (F3)")

F4:: {
    if FileExist(CONFIG)
        FileDelete(CONFIG)
    Reload()
}

; ============================================================
;  CONFIG LOAD
; ============================================================

LoadConfig() {
    global rawFoodPoints, runMode
    global COLOR_TOLERANCE
    global CAMPFIRE_SEARCH_X1, CAMPFIRE_SEARCH_Y1, CAMPFIRE_SEARCH_X2, CAMPFIRE_SEARCH_Y2
    global BANK_RUN_SEARCH_X1, BANK_RUN_SEARCH_Y1, BANK_RUN_SEARCH_X2, BANK_RUN_SEARCH_Y2
    global WITHDRAW_SLOT_INDEX

    rawFoodPoints := LoadColorPointList(CONFIG, "RawFoodPoints")
    runMode := LoadFlag(CONFIG, "Settings", "runMode", false)

    ; Curated tunables - overwrite the hardcoded defaults above from
    ; the .ini if present, so these can be tweaked without editing
    ; this file.
    COLOR_TOLERANCE := LoadNumber(CONFIG, "Tunables", "colorTolerance", COLOR_TOLERANCE)
    WITHDRAW_SLOT_INDEX := LoadNumber(CONFIG, "Tunables", "withdrawSlotIndex", WITHDRAW_SLOT_INDEX)

    ; Hardcoded search-box defaults (see header comment) - still
    ; overridable by hand-editing the .ini, just never via a hotkey.
    campfireRegion := LoadRegion(CONFIG, "CampfireSearch", CAMPFIRE_SEARCH_X1, CAMPFIRE_SEARCH_Y1, CAMPFIRE_SEARCH_X2, CAMPFIRE_SEARCH_Y2)
    CAMPFIRE_SEARCH_X1 := campfireRegion[1]
    CAMPFIRE_SEARCH_Y1 := campfireRegion[2]
    CAMPFIRE_SEARCH_X2 := campfireRegion[3]
    CAMPFIRE_SEARCH_Y2 := campfireRegion[4]

    bankRunRegion := LoadRegion(CONFIG, "BankRunSearch", BANK_RUN_SEARCH_X1, BANK_RUN_SEARCH_Y1, BANK_RUN_SEARCH_X2, BANK_RUN_SEARCH_Y2)
    BANK_RUN_SEARCH_X1 := bankRunRegion[1]
    BANK_RUN_SEARCH_Y1 := bankRunRegion[2]
    BANK_RUN_SEARCH_X2 := bankRunRegion[3]
    BANK_RUN_SEARCH_Y2 := bankRunRegion[4]
}

; ============================================================
;  SETUP VALIDATION
; ============================================================

ValidateSetup() {
    global rawFoodPoints, COOKING_MARKER_IMG, DEPOSIT_IMG
    v := NewValidator()
    RequireNonEmpty(v, "F1 - raw-food reference points", rawFoodPoints)
    RequireFile(v, "cooking-marker.png (cook dialog image)", COOKING_MARKER_IMG)
    RequireFile(v, "deposit.png (bank deposit image)", DEPOSIT_IMG)
    return ShowValidationErrors(v)
}

StartBot() {
    global runner, LOG_FILE, PHASE_TIMEOUT_COOK, PHASE_TIMEOUT_BANK
    if (!ValidateSetup())
        return

    AddPhase(runner, "cook", CookPhase, PHASE_TIMEOUT_COOK)
    AddPhase(runner, "bank", BankPhase, PHASE_TIMEOUT_BANK)
    StartTaskRunner(runner, "cook")
    ShowTipFor("Bot started", 1000)
    LogLine(LOG_FILE, "===== Bot started =====")
}

; ============================================================
;  PHASES
; ============================================================

; Clicks the campfire marker, confirms the "Cook X" dialog, then waits
; for the calibrated last slot's color to change away from raw food
; (cooked or burnt - either way, cooking finished) before moving to
; the bank phase.
CookPhase(taskRunner) {
    global rawFoodPoints, runMode, COLOR_TOLERANCE, LOG_FILE
    global CAMPFIRE_MARKER_COLOR, CAMPFIRE_MARKER_TOLERANCE
    global CAMPFIRE_SEARCH_X1, CAMPFIRE_SEARCH_Y1, CAMPFIRE_SEARCH_X2, CAMPFIRE_SEARCH_Y2
    global CAMPFIRE_CLICK_OFFSET_X, CAMPFIRE_CLICK_OFFSET_Y, CAMPFIRE_SEARCH_TIMEOUT_MS
    global COOKING_MARKER_IMG, COOKING_MARKER_IMG_OPTIONS, COOKING_MARKER_IMG_W, COOKING_MARKER_IMG_H
    global COOKING_MARKER_SEARCH_X1, COOKING_MARKER_SEARCH_Y1, COOKING_MARKER_SEARCH_X2, COOKING_MARKER_SEARCH_Y2
    global COOKING_MARKER_TIMEOUT_MS, COOK_CONFIRM_KEY, COOK_KEY_SETTLE_MS
    global COOK_DONE_TIMEOUT_MS, COOK_DONE_CONFIRM_TICKS, COOK_GUARD_SETTLE_TIMEOUT_MS

    if (!RequireOsrsWindowActive()) {
        LogLine(LOG_FILE, "cook: OSRS window not focused - paused")
        return GoToPhase(taskRunner, "cook")
    }

    isRunningFn := () => taskRunner["running"]

    ; If the calibrated slot doesn't read as raw yet, give it a short
    ; grace window to settle (see COOK_GUARD_SETTLE_TIMEOUT_MS comment
    ; above) - a fresh withdrawal can still be rendering. Only if it
    ; NEVER becomes raw within that window do we treat this as "the
    ; bank trip couldn't restock raw food" and skip straight to the
    ; bank phase instead of clicking the campfire for nothing - same
    ; guard auto-smelter.ahk's SmeltPhase uses, just settle-tolerant.
    if (!WaitUntilNotOccupied(rawFoodPoints, COLOR_TOLERANCE, COOK_GUARD_SETTLE_TIMEOUT_MS, , , isRunningFn)) {
        LogLine(LOG_FILE, "cook: last slot still not raw after settle window - skipping to bank")
        return GoToPhase(taskRunner, "bank")
    }

    if (!WaitForPixelSearch(&fx, &fy, CAMPFIRE_SEARCH_X1, CAMPFIRE_SEARCH_Y1, CAMPFIRE_SEARCH_X2, CAMPFIRE_SEARCH_Y2, CAMPFIRE_MARKER_COLOR, CAMPFIRE_MARKER_TOLERANCE, CAMPFIRE_SEARCH_TIMEOUT_MS, , isRunningFn)) {
        StopAndLog(taskRunner, "Could not find the campfire marker color")
        return GoToPhase(taskRunner, "cook")
    }

    LogLine(LOG_FILE, "cook: campfire marker found at " fx "," fy " - clicking with offset")
    HumanClick(fx + CAMPFIRE_CLICK_OFFSET_X, fy + CAMPFIRE_CLICK_OFFSET_Y, 0, 0, runMode)
    ResetPhaseTimer(taskRunner)

    if (!WaitForImageCenter(COOKING_MARKER_SEARCH_X1, COOKING_MARKER_SEARCH_Y1, COOKING_MARKER_SEARCH_X2, COOKING_MARKER_SEARCH_Y2, COOKING_MARKER_IMG, COOKING_MARKER_IMG_W, COOKING_MARKER_IMG_H, &mcx, &mcy, COOKING_MARKER_TIMEOUT_MS, COOKING_MARKER_IMG_OPTIONS, , isRunningFn)) {
        StopAndLog(taskRunner, "Cook dialog never appeared (cooking-marker.png not found)")
        return GoToPhase(taskRunner, "cook")
    }

    LogLine(LOG_FILE, "cook: cook dialog visible - confirming with " COOK_CONFIRM_KEY)
    HumanKeyPress(COOK_CONFIRM_KEY)
    Sleep(JitterDelay(COOK_KEY_SETTLE_MS))

    ; Cooking happens automatically once started - just wait for the
    ; calibrated slot's color to change away from raw (cooked or
    ; burnt, doesn't matter which). Same confirm-ticks debounce as
    ; every other "wait for a state change" check in this codebase.
    WaitUntilOccupied(rawFoodPoints, COLOR_TOLERANCE, COOK_DONE_TIMEOUT_MS, COOK_DONE_CONFIRM_TICKS, , isRunningFn)

    ; We made a real attempt (clicked the campfire, confirmed the
    ; dialog) - reset the phase timer so PHASE_TIMEOUT_COOK measures
    ; "can't even start a cook attempt for 30s", not "total time spent
    ; cooking".
    ResetPhaseTimer(taskRunner)
    LogLine(LOG_FILE, "cook: last slot changed - done cooking, moving to bank")
    return GoToPhase(taskRunner, "bank")
}

; Clicks the bank-run marker, deposits everything, withdraws a fresh
; stack of raw food from WITHDRAW_SLOT_INDEX, then loops back to the
; cook phase.
BankPhase(taskRunner) {
    global runMode, LOG_FILE
    global BANK_RUN_MARKER_COLOR, BANK_RUN_MARKER_TOLERANCE
    global BANK_RUN_SEARCH_X1, BANK_RUN_SEARCH_Y1, BANK_RUN_SEARCH_X2, BANK_RUN_SEARCH_Y2
    global BANK_RUN_CLICK_OFFSET_X, BANK_RUN_CLICK_OFFSET_Y, BANK_RUN_SEARCH_TIMEOUT_MS
    global DEPOSIT_IMG, BANK_OPEN_SETTLE_MS, BANK_OPEN_FAILSAFE_DELAY_MS
    global WITHDRAW_SLOT_INDEX, WITHDRAW_SETTLE_MS

    if (!RequireOsrsWindowActive()) {
        LogLine(LOG_FILE, "bank: OSRS window not focused - paused")
        return GoToPhase(taskRunner, "bank")
    }

    isRunningFn := () => taskRunner["running"]

    if (!WaitForPixelSearch(&fx, &fy, BANK_RUN_SEARCH_X1, BANK_RUN_SEARCH_Y1, BANK_RUN_SEARCH_X2, BANK_RUN_SEARCH_Y2, BANK_RUN_MARKER_COLOR, BANK_RUN_MARKER_TOLERANCE, BANK_RUN_SEARCH_TIMEOUT_MS, , isRunningFn)) {
        StopAndLog(taskRunner, "Could not find the bank-run marker color")
        return GoToPhase(taskRunner, "bank")
    }

    LogLine(LOG_FILE, "bank: bank-run marker found at " fx "," fy " - clicking with offset")
    HumanClick(fx + BANK_RUN_CLICK_OFFSET_X, fy + BANK_RUN_CLICK_OFFSET_Y, 0, 0, runMode)
    ResetPhaseTimer(taskRunner)

    ; Open the bank and deposit everything (shared lib\Bank.ahk).
    if (!BankDepositAll(DEPOSIT_IMG, BANK_OPEN_SETTLE_MS, BANK_OPEN_FAILSAFE_DELAY_MS, , , , , , isRunningFn)) {
        StopAndLog(taskRunner, "Bank never opened (Deposit All button not found)")
        return GoToPhase(taskRunner, "bank")
    }

    LogLine(LOG_FILE, "bank: deposited, withdrawing raw food from slot " WITHDRAW_SLOT_INDEX)
    BankWithdrawSlot(WITHDRAW_SLOT_INDEX, WITHDRAW_SETTLE_MS)

    LogLine(LOG_FILE, "bank: done, returning to cook phase")
    return GoToPhase(taskRunner, "cook")
}
