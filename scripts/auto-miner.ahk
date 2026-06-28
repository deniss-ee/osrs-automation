; ============================================================
;  auto-miner.ahk
;  Single-fixed-spot (or multi-spot, priority-ordered) ore
;  gathering bot, built ENTIRELY from the shared lib\ functions -
;  no raw PixelGetColor / Click / MouseMove calls live in this
;  file. If you ever feel like you need one, it almost certainly
;  belongs in lib\ instead so every future script can use it too.
;
;  Promoted out of templates\single-ore-template.ahk to the
;  project root - despite the old name, this is a real, actively-
;  used mining script (supports any number of calibrated ore
;  spots via repeated F1 presses), not just a teaching example.
;  Still doubles as a reference if you want to copy it as a
;  starting point for a new gathering script - see the footer.
;
;  HOTKEYS
;    F1   = save a new ore spot - hover an ore, press F1. Press F1
;           AGAIN on a different ore to add another spot; there's
;           no limit. Saved spots are checked in the order you
;           added them: if more than one is showing its "ready"
;           color at the same moment, the earliest-added one wins.
;           Once the bot clicks ANY spot, it waits for that exact
;           spot to visibly deplete before it looks at any of the
;           others again - a second ore becoming ready never
;           interrupts the one currently being mined.
;    F2   = save "empty inventory slot" reference points - EMPTY
;           YOUR INVENTORY first, then press F2 (no need to hover
;           anywhere specific). This samples FOUR points spread
;           around the LAST inventory slot (not just its one
;           center pixel) so the bot can tell "occupied" vs
;           "empty" for ANY item, no per-item recalibration
;           needed - and isn't fooled by an item icon that happens
;           to have a gap exactly where a single sampled pixel
;           would land.
;    F4   = start/stop recording the WALK-BACK-TO-MINE path
;           (while recording, every left/right click you make is
;           captured as a step - walk back to the mining spot and
;           press F4 again to stop. By default this only deposits
;           and walks back - see WITHDRAW AFTER DEPOSIT below if
;           you also want it to withdraw one item before walking
;           back)
;
;  WALKING TO THE BANK is no longer a recorded path - same as
;  auto-fisher.ahk, the bot searches for a fixed blue marker color
;  (a plugin overlay marking the nearest bank) and clicks it with a
;  fixed offset, which triggers the game/plugin's own automated
;  walk-and-open. Only the walk BACK to the mining spot still needs
;  a recorded path (F4), since there's no equivalent marker for that.
;    F5   = start the bot
;    F6   = stop the bot
;    F7   = clear saved config and reload the script
;
;  RUN MODE is just a plain setting in the .ini, not a hotkey -
;  no stamina-orb color reading, no live toggling. Open
;  config\auto-miner.ini, find the [Settings] section, and set
;
;      runMode=1   (hold Ctrl / run for every click)
;      runMode=0   (never hold Ctrl / always walk - the default)
;
;  then restart the script. This one setting controls every click
;  this script makes, both while gathering and while walking
;  recorded paths.
;
;  WITHDRAW AFTER DEPOSIT is the same kind of plain .ini setting,
;  also under [Settings]:
;
;      withdrawAfterDeposit=1   (after depositing, withdraw one item
;                                 from WITHDRAW_AFTER_DEPOSIT_SLOT_INDEX)
;      withdrawAfterDeposit=0   (deposit only, walk straight back -
;                                 the default, same as before this
;                                 setting existed)
;
;  Lets two .ini profiles share this same script file while only one
;  of them withdraws something after banking.
;
;  Config auto-saves to config\auto-miner.ini next to this file.
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
global CONFIG := A_ScriptDir "\..\config\miner-m-coal.ini"

; ---------- Tunables ----------
global COLOR_TOLERANCE := 20
global ORE_CLICK_BOX := 12      ; humanized click lands within +/-12px of the sampled ore pixel
global ORE_DEPLETE_TIMEOUT_MS := 30000   ; after clicking, wait up to this long for the ore pixel to change before allowing another click
global ORE_DEPLETE_CONFIRM_TICKS := 2    ; require the ore pixel to read as "changed" for this many consecutive ~10ms polls (the depletion-wait loop sleeps 10ms for fast spot-switching) before trusting it - filters out a single transient glitch (e.g. right as you arrive back from the bank) being mistaken for the rock actually depleting
global PHASE_TIMEOUT_MINE := 15000   ; give up and stop if NO ore click happens for 15s straight (resets every time we click - see ResetPhaseTimer)
global PHASE_TIMEOUT_BANK := 30000   ; give up and stop if banking hangs for 30s straight
global WITHDRAW_AFTER_DEPOSIT_SLOT_INDEX := 1   ; which bank slot (1-8, left to right - see Grid.ahk's GetBankSlots) to withdraw from when withdrawAfterDeposit is on
global WITHDRAW_AFTER_DEPOSIT_SETTLE_MS := 300   ; pause after that withdrawal click before walking back - needs to be long enough for the inventory display to finish updating (see the comment at its use below), but otherwise lower this for a snappier cycle

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

; ---------- Bank marker (walk-to-bank, no recorded path needed) ----------
; Same exact values as auto-fisher.ahk's BANK_MARKER_* - a fixed blue
; plugin overlay marking the nearest bank, clicked with a fixed offset
; rather than walked to via a recorded path.
global BANK_MARKER_COLOR := 0x0000FF
global BANK_MARKER_TOLERANCE := 20
global BANK_MARKER_CLICK_OFFSET_X := 10
global BANK_MARKER_CLICK_OFFSET_Y := 30
global BANK_MARKER_SEARCH_TIMEOUT_MS := 8000
global BANK_MARKER_SEARCH_X1 := 538
global BANK_MARKER_SEARCH_Y1 := 337
global BANK_MARKER_SEARCH_X2 := 688
global BANK_MARKER_SEARCH_Y2 := 487

; INITIAL_CLICK_DELAY (defined in lib\Paths.ahk, currently 0) is
; the wait before the very FIRST click of any path playback. It's
; a single global setting rather than something stored per-path -
; tweak it there if you want to add a delay or randomize it later.

; ---------- Humanization: off by default ----------
; Click.ahk defaults ENABLE_HUMANIZATION to false (exact calibrated
; pixel, exact delays). Even when enabled it's hard-capped at
; +/-2px / +/-100ms. Restated here so it's explicit per script - set
; to true if you ever want the subtle randomized offset/jitter back.
global ENABLE_HUMANIZATION := false

; ---------- Calibrated values (loaded from INI, or 0/-1 if unset) ----------
; oreSpots is a list of {x, y, color} - one per F1 press, earliest
; first. See MinePhase below for how priority order is used.
global oreSpots := []
; emptySlotPoints is a list of {x, y, color} - several reference
; points inside the last inventory slot, all captured by one F2
; press. See IsAnyPointOccupied (Colors.ahk) for how they're used.
global emptySlotPoints := []

; ---------- Run/walk setting - plain config flag, no stamina-orb reading, no hotkey ----------
global runMode := false
; ---------- Withdraw-after-deposit setting - plain config flag, no hotkey ----------
global withdrawAfterDeposit := false

; ---------- Recorded paths ----------
; Only the walk-BACK-to-mine path is recorded now - walking TO the
; bank is marker-based (see BANK_MARKER_* above), same as
; auto-fisher.ahk.
global backToMineRecorder := NewPathRecorder()
global backToMineSteps := []

; ---------- Library objects built from the above ----------
global runner := NewTaskRunner(150)

; ---------- Init ----------
Hotkey("~LButton", RecordClick, "Off")
Hotkey("~RButton", RecordClick, "Off")
LoadConfig()

; ============================================================
;  CALIBRATION HOTKEYS
; ============================================================

F1:: {
    global oreSpots
    MouseGetPos(&mx, &my)
    color := PixelGetColor(mx, my, "RGB")
    oreSpots.Push(Map("x", mx, "y", my, "color", color))
    SaveColorPointList(CONFIG, "OreSpots", oreSpots)
    ShowTipFor("Ore spot #" oreSpots.Length " saved", 1200)
}

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

F4:: ToggleRecording(backToMineRecorder, "BackToMine", "WALK-BACK-TO-MINE")

; Diagnostic only - doesn't change any saved value. Reads the LIVE
; color at each calibrated empty-slot point right now and compares
; it to what F2 saved, so you can check (with the inventory actually
; full) whether the item sitting in the last slot is being judged
; "occupied" or is - wrongly - reading close enough to the
; calibrated empty color to pass as still empty (this is the failure
; mode for dark ores like coal, whose icon color can be close to a
; dark slot background within COLOR_TOLERANCE).
F8:: {
    global emptySlotPoints, COLOR_TOLERANCE
    if (emptySlotPoints.Length = 0) {
        ShowTipFor("No empty-slot points saved yet - press F2 first", 1500)
        return
    }
    msg := "Live vs saved (tolerance " COLOR_TOLERANCE "):`n"
    anyOccupied := false
    for i, p in emptySlotPoints {
        live := PixelGetColor(p["x"], p["y"], "RGB")
        occupied := IsSlotOccupied(p["x"], p["y"], p["color"], COLOR_TOLERANCE)
        if (occupied)
            anyOccupied := true
        msg .= "  pt" i ": saved " Format("0x{:06X}", p["color"]) " live " Format("0x{:06X}", live) " -> " (occupied ? "OCCUPIED" : "reads empty") "`n"
    }
    msg .= "Overall: " (anyOccupied ? "OCCUPIED (would go to bank)" : "reads as EMPTY (would keep mining)")
    ShowTipFor(msg, 6000)
}

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

; Starts/stops recording for the walk-back-to-mine recorder. Only
; one path is recorded in this script now (walking to the bank is
; marker-based - see BANK_MARKER_* above), but this keeps the same
; shape as the other scripts' multi-recorder ToggleRecording in case
; a future copy of this template adds more paths.
ToggleRecording(recorder, sectionName, label) {
    global backToMineRecorder, backToMineSteps
    if (recorder["active"]) {
        steps := StopRecording(recorder)
        SavePath(CONFIG, sectionName, steps)
        backToMineSteps := steps
        Hotkey("~LButton", RecordClick, "Off")
        Hotkey("~RButton", RecordClick, "Off")
        ShowTipFor(label " recording stopped (" steps.Length " clicks)", 1500)
        return
    }

    StartRecording(recorder, sectionName)
    Hotkey("~LButton", RecordClick, "On")
    Hotkey("~RButton", RecordClick, "On")
    ShowTipFor(label " recording started - click your route, then press the key again to stop", 2200)
}

; Fires on every click while the recorder is active, handing off to
; Paths.ahk's RecordClickStep along with whatever runMode is
; currently set to.
RecordClick(*) {
    global backToMineRecorder, runMode
    activeRecorder := backToMineRecorder["active"] ? backToMineRecorder : ""
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
    global oreSpots, emptySlotPoints, runMode, withdrawAfterDeposit
    global backToMineSteps
    global COLOR_TOLERANCE, WITHDRAW_AFTER_DEPOSIT_SLOT_INDEX
    oreSpots := LoadColorPointList(CONFIG, "OreSpots")

    emptySlotPoints := LoadColorPointList(CONFIG, "InventoryEmptyPoints")

    ; Plain on/off settings, edited directly in the .ini - see the
    ; "RUN MODE" / "WITHDRAW AFTER DEPOSIT" notes in the header
    ; comment. Neither is a hotkey.
    runMode := LoadFlag(CONFIG, "Settings", "runMode", false)
    withdrawAfterDeposit := LoadFlag(CONFIG, "Settings", "withdrawAfterDeposit", false)

    ; Curated tunables - overwrite the hardcoded defaults above from
    ; the .ini if present, so these can be tweaked without editing
    ; this file (e.g. from the control panel).
    COLOR_TOLERANCE := LoadNumber(CONFIG, "Tunables", "colorTolerance", COLOR_TOLERANCE)
    WITHDRAW_AFTER_DEPOSIT_SLOT_INDEX := LoadNumber(CONFIG, "Tunables", "withdrawSlotIndex", WITHDRAW_AFTER_DEPOSIT_SLOT_INDEX)

    backToMineSteps := LoadPath(CONFIG, "BackToMine")
}

; ============================================================
;  SETUP VALIDATION
; ============================================================

ValidateSetup() {
    global oreSpots, emptySlotPoints, backToMineSteps
    global DEPOSIT_IMG
    v := NewValidator()
    RequireNonEmpty(v, "F1 - at least one ore spot", oreSpots)
    RequireNonEmpty(v, "F2 - empty inventory slot reference points", emptySlotPoints)
    RequirePath(v, "F4 - walk-back-to-mine path", backToMineSteps)
    RequireFile(v, "deposit.png (bank deposit image)", DEPOSIT_IMG)
    return ShowValidationErrors(v)
}

StartBot() {
    global backToMineRecorder, runner
    global PHASE_TIMEOUT_MINE, PHASE_TIMEOUT_BANK
    if (backToMineRecorder["active"]) {
        ShowTipFor("Finish recording before starting the bot", 1200)
        return
    }
    if (!ValidateSetup())
        return

    AddPhase(runner, "mine", MinePhase, PHASE_TIMEOUT_MINE)
    AddPhase(runner, "bank", BankPhase, PHASE_TIMEOUT_BANK)
    StartTaskRunner(runner, "mine")
    ShowTipFor("Bot started", 1000)
}

; ============================================================
;  PHASES
; ============================================================

; Gathers from whichever calibrated ore spot is ready, in
; priority order. Switches to the "bank" phase the moment the
; last inventory slot is occupied.
MinePhase(taskRunner) {
    global oreSpots, emptySlotPoints, runMode
    global COLOR_TOLERANCE, ORE_CLICK_BOX, ORE_DEPLETE_TIMEOUT_MS, ORE_DEPLETE_CONFIRM_TICKS
    if (!RequireOsrsWindowActive())
        return GoToPhase(taskRunner, "mine")

    ; Outer loop: keeps scanning/clicking spots internally, without
    ; returning control to the TaskRunner, for as long as a spot is
    ; ready. Returning "mine" after every single depletion would mean
    ; waiting for the TaskRunner's own tick interval (NewTaskRunner's
    ; 150ms) to elapse before the next spot is even looked at - this
    ; loop removes that round-trip so switching to the next ready
    ; spot happens immediately once the current one is confirmed
    ; depleted. Only returns to the TaskRunner (still "mine") once NO
    ; spot is currently ready, so it doesn't busy-loop forever.
    loop {
        if (!taskRunner["running"])
            return GoToPhase(taskRunner, "mine")

        if (IsAnyPointOccupied(emptySlotPoints, COLOR_TOLERANCE))
            return GoToPhase(taskRunner, "bank")

        ; Check every saved spot IN ORDER - the first one currently
        ; showing its "ready" color wins (earlier-saved = higher
        ; priority, only matters when more than one is ready at once).
        clickedSpot := false
        for spot in oreSpots {
            if (!IsColorAt(spot["x"], spot["y"], spot["color"], COLOR_TOLERANCE))
                continue

            ; Click ONCE, then wait for THIS spot's pixel to actually
            ; change away from its "ready" color before we even
            ; consider clicking anything again - including other spots.
            ; Without this wait the bot would spam-click the same swing
            ; animation every ~150ms, which interrupts mining in OSRS
            ; (re-clicking something you're already mining cancels the
            ; action) - so the rock never actually depletes. Because
            ; this call blocks, a second ore becoming ready while we're
            ; still waiting here is never even looked at until this one
            ; is done.
            HumanClick(spot["x"], spot["y"], ORE_CLICK_BOX, ORE_CLICK_BOX, runMode)
            Sleep(250) ; brief settle before the first depletion check

            ; Wait here until EITHER this rock depletes OR the inventory
            ; fills, whichever happens first - a plain depletion-only
            ; wait has no way to notice the inventory filling up WHILE
            ; it's still mining the current rock (the normal case, since
            ; mining the rock currently being clicked is exactly what
            ; fills the last slot): the rock usually doesn't visually
            ; deplete at all once you can't collect any more from it, so
            ; the wait would run the full ORE_DEPLETE_TIMEOUT_MS with the
            ; inventory already full before the next "mine" tick ever
            ; re-checked it.
            depleteDeadline := A_TickCount + ORE_DEPLETE_TIMEOUT_MS
            changedStreak := 0
            loop {
                if (!taskRunner["running"])
                    return GoToPhase(taskRunner, "mine")
                if (IsAnyPointOccupied(emptySlotPoints, COLOR_TOLERANCE)) {
                    ResetPhaseTimer(taskRunner)
                    return GoToPhase(taskRunner, "bank")
                }
                if (!IsColorAt(spot["x"], spot["y"], spot["color"], COLOR_TOLERANCE)) {
                    changedStreak += 1
                    if (changedStreak >= ORE_DEPLETE_CONFIRM_TICKS)
                        break
                } else {
                    changedStreak := 0
                }
                if (A_TickCount >= depleteDeadline)
                    break
                Sleep(10)
            }

            ; We made real progress (a click happened) - reset the
            ; phase timer so PHASE_TIMEOUT_MINE measures "no clicks for
            ; 15s", not "total time spent mining", otherwise a long
            ; successful gathering session would eventually trip the
            ; timeout and stop itself for no reason.
            ResetPhaseTimer(taskRunner)
            clickedSpot := true
            break   ; re-scan from the top of oreSpots immediately - see outer loop comment
        }

        if (!clickedSpot)
            return GoToPhase(taskRunner, "mine")   ; nothing ready - yield back to the TaskRunner tick
    }
}

; Clicks the bank marker (triggers the game/plugin's own automated
; walk-and-open, same as auto-fisher.ahk - no recorded path needed
; for this leg), deposits everything, optionally withdraws one item
; (see withdrawAfterDeposit / WITHDRAW_AFTER_DEPOSIT_SLOT_INDEX),
; then walks back via the recorded path.
BankPhase(taskRunner) {
    global backToMineSteps, withdrawAfterDeposit, WITHDRAW_AFTER_DEPOSIT_SLOT_INDEX, WITHDRAW_AFTER_DEPOSIT_SETTLE_MS
    global DEPOSIT_IMG, BANK_OPEN_SETTLE_MS, BANK_OPEN_FAILSAFE_DELAY_MS
    global BANK_MARKER_COLOR, BANK_MARKER_TOLERANCE, BANK_MARKER_SEARCH_TIMEOUT_MS
    global BANK_MARKER_CLICK_OFFSET_X, BANK_MARKER_CLICK_OFFSET_Y
    global BANK_MARKER_SEARCH_X1, BANK_MARKER_SEARCH_Y1, BANK_MARKER_SEARCH_X2, BANK_MARKER_SEARCH_Y2
    global runMode
    if (!RequireOsrsWindowActive())
        return GoToPhase(taskRunner, "bank")

    isRunningFn := () => taskRunner["running"]

    ; First pixel matching this color, scanning from the top-left of
    ; the screen (PixelSearch's natural scan order), restricted to a
    ; top-left box - typically a plugin highlight marking the
    ; nearest bank.
    if (!WaitForPixelSearch(&fx, &fy, BANK_MARKER_SEARCH_X1, BANK_MARKER_SEARCH_Y1, BANK_MARKER_SEARCH_X2, BANK_MARKER_SEARCH_Y2, BANK_MARKER_COLOR, BANK_MARKER_TOLERANCE, BANK_MARKER_SEARCH_TIMEOUT_MS, , isRunningFn)) {
        StopTaskRunner(taskRunner, "Could not find the bank marker color")
        return GoToPhase(taskRunner, "bank")
    }

    ; The marker pixel itself usually isn't the clickable spot -
    ; offset into the actual bank tile/icon next to it.
    HumanClick(fx + BANK_MARKER_CLICK_OFFSET_X, fy + BANK_MARKER_CLICK_OFFSET_Y, 0, 0, runMode)
    ResetPhaseTimer(taskRunner)

    ; Open the bank and deposit everything (shared lib\Bank.ahk).
    if (!BankDepositAll(DEPOSIT_IMG, BANK_OPEN_SETTLE_MS, BANK_OPEN_FAILSAFE_DELAY_MS, , , , , , isRunningFn)) {
        StopTaskRunner(taskRunner, "Bank never opened (Deposit All button not found)")
        return GoToPhase(taskRunner, "bank")
    }

    ; Optionally withdraw one item before walking back - see the
    ; withdrawAfterDeposit / WITHDRAW_AFTER_DEPOSIT_* settings.
    if (withdrawAfterDeposit)
        BankWithdrawSlot(WITHDRAW_AFTER_DEPOSIT_SLOT_INDEX, WITHDRAW_AFTER_DEPOSIT_SETTLE_MS)

    if (!PlayPathWithGuard(backToMineSteps, isRunningFn)) {
        StopTaskRunner(taskRunner, "Walk-back path failed or was stopped")
        return GoToPhase(taskRunner, "bank")
    }

    return GoToPhase(taskRunner, "mine")
}

; ============================================================
;  HOW TO BUILD YOUR OWN GATHERING SCRIPT FROM THIS TEMPLATE
;
;  1. Copy this file to a new name next to it (project root,
;     alongside lib\, so the #Include paths still resolve).
;  2. Add one calibration hotkey per value YOUR script needs
;     (extra ore spots, search regions, etc.) - copy the F1/F2
;     pattern: MouseGetPos/PixelGetColor -> a Save* call from
;     ConfigStore.ahk -> ShowTipFor.
;  3. Build any extra recorders you need at the top
;     (NewPathRecorder() per path).
;  4. Register your phases with AddPhase(runner, name, fn,
;     timeoutMs) - keep each phase a single responsibility.
;  5. Extend ValidateSetup() with one RequireX line per new
;     calibration value.
;  6. Wire start/stop hotkeys exactly like F5/F6 above.
;  7. Calibrate via your F-keys in order, record any paths, set
;     runMode=1 or 0 in the .ini if you want this script to run
;     instead of walk, then start. Never write a raw
;     PixelGetColor/Click/MouseMove call directly in your script -
;     if you need one, it belongs in lib\ instead, so the next
;     script gets it for free too.
; ============================================================
