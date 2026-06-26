; ============================================================
;  auto-fisher.ahk
;  Fishing bot, built entirely from the shared lib\ functions -
;  same library auto-miner.ahk and auto-smelter.ahk use.
;  Detects the fishing spot by IMAGE (ImageSearch), not a single
;  pixel color, since the spot's ripple icon isn't one flat color.
;
;  EXPECTED STARTING STATE: you are standing at the fishing spot
;  with a net already in inventory slot 1 and the rest empty.
;
;  CYCLE:
;    1. Search the calibrated fishing AREA for the spot icon
;       (anch.png) and click its center once - this starts fishing.
;    2. Wait for whichever happens first:
;         a) inventory full -> go bank
;         b) THIS exact spot disappears (it moved or depleted) ->
;            go back to step 1 and find wherever it went
;    3. (bank) Find the calibrated bank-marker color on screen and
;       click it with a fixed offset - this is a marker (e.g. a
;       plugin highlight) that results in walking to and opening
;       the bank.
;    4. Instead of a flat guess for how long that takes, wait until
;       the Deposit All button (deposit.png) is actually visible
;       near its known position - see BANK_OPEN_TIMEOUT_MS.
;    5. Click "Deposit All", then withdraw a fresh net with one
;       click on NET_BANK_SLOT_INDEX - same deposit/withdraw
;       pattern as auto-smelter.ahk's bank phase.
;    6. Play the recorded WALK-TO-FISHING-SPOT path, then start
;       over from step 1.
;
;  WHY THE SPOT-MOVED CHECK CONTINUOUSLY RE-CENTERS INSTEAD OF
;  TRACKING ONE FIXED PIXEL: if we click a spot we aren't standing
;  next to, the character has to walk over, and the camera follows
;  it the WHOLE TIME it's moving - so the spot's ON-SCREEN position
;  keeps drifting, continuously, for as long as the character keeps
;  walking (not just briefly right after the click). A single
;  "wait once, then lock onto a fixed point" approach still goes
;  stale almost immediately for this reason. So instead, every poll
;  re-searches a SMALL BOX around wherever the spot was LAST found
;  and updates that position to the new result - the box slides
;  along with the drift in real time. Only many consecutive polls
;  with nothing found nearby concludes it actually left (not just
;  drifted further than expected). Scoping to a small, sliding box
;  - never the whole area - means a different, unrelated spot
;  appearing elsewhere can't be mistaken for ours still being here
;  (which would otherwise prevent ever detecting "gone" and
;  switching to a new spot) - and we never click again while
;  monitoring, so this can't cause the spam-click bug already fixed
;  in the mining script.
;
;  DEBUG LOGGING: every phase transition and bank-detection outcome
;  is timestamped and appended to LOG_FILE (logs\auto-fisher-debug.log)
;  via lib\Log.ahk - useful for diagnosing a
;  run after the fact without relying on catching a tooltip live.
;
;  HOTKEYS
;    F1   = mark fishing-area corner 1 (hover anywhere near one
;           corner of the patch of water spots can appear in,
;           press F1)
;    F2   = mark fishing-area corner 2 (hover the opposite corner,
;           press F2 - order doesn't matter, corners are sorted
;           automatically)
;    F3   = save "empty inventory slot" reference points - make
;           sure the LAST inventory slot is genuinely empty, then
;           press F3 (no need to hover anywhere specific). Samples
;           FOUR points around the last slot, same mechanism as
;           mining/smelting - this is what later reads as "full".
;    F4   = start/stop recording the WALK-TO-FISHING-SPOT path
;           (start right after withdrawing/depositing at the bank,
;           stop once you're standing back at the exact fishing
;           tile - BEFORE the spot search, that's automatic)
;    F5   = start the bot
;    F6   = stop the bot
;    F7   = clear saved config and reload the script
;
;  RUN MODE is a plain setting in the .ini, not a hotkey - same as
;  the other scripts. Open config\auto-fisher.ini, find [Settings], set
;
;      runMode=1   (hold Ctrl / run for every click)
;      runMode=0   (never hold Ctrl / always walk - the default)
;
;  then restart the script.
;
;  Config auto-saves to config\auto-fisher.ini next to this file.
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
global CONFIG := A_ScriptDir "\..\config\auto-fisher.ini"

; ---------- Debug log ----------
; Plain text, timestamped, appended to forever - read this after a
; run to see exactly what the bot did, since a tooltip might not
; actually be visible depending on how the game window is running.
global LOG_FILE := A_ScriptDir "\..\logs\auto-fisher-debug.log"

; Stops the runner AND records why in the debug log, so a stop
; that happens off-screen (or whose tooltip you miss) is never a
; mystery - just open auto-fisher-debug.log afterward.
StopAndLog(taskRunner, reason) {
    global LOG_FILE
    LogLine(LOG_FILE, "STOPPED: " reason)
    StopTaskRunner(taskRunner, reason)
}

; ---------- Humanization: off by default ----------
; Click.ahk defaults ENABLE_HUMANIZATION to false (exact calibrated
; pixel, exact delays). Even when enabled it's hard-capped at
; +/-2px / +/-100ms. Restated here so it's explicit per script - set
; to true if you ever want the subtle randomized offset/jitter back.
global ENABLE_HUMANIZATION := false

; ---------- Tunables: inventory check ----------
global COLOR_TOLERANCE := 20

; ---------- Tunables: fishing-spot image ----------
global FISH_IMG := A_ScriptDir "\..\images\anch.png"
global FISH_IMG_OPTIONS := "*Trans0x00FF00 *20"   ; ignore the green background, allow some shade variation
global FISH_IMG_W := 64    ; actual pixel size of anch.png - keep in sync if the image file changes
global FISH_IMG_H := 48
global FISH_CLICK_BOX := 10            ; humanized click lands within +/-10px of the spot's true center
; The camera follows the character while it walks toward a spot
; that isn't adjacent yet, so the spot's ON-SCREEN position keeps
; drifting for as long as the character keeps moving - confirmed
; via the debug log (a one-time "anchor" position went stale
; within a couple seconds). FISH_SPOT_RADIUS is generous so the
; tracking box can re-center on the spot's new position each poll
; even with a fair amount of drift between polls. The continuous
; re-centering is what actually solves the drift problem, so
; FISH_SPOT_GONE_CONFIRM_TICKS only needs to filter one-off
; ImageSearch misses (a stray glitch, a momentary overlay) - not
; cover several seconds of expected absence - so it can be small;
; lower it further for a snappier switch, raise it if you ever see
; it switch away from a spot that's clearly still there.
global FISH_SPOT_RADIUS := 70
global FISH_SPOT_GONE_CONFIRM_TICKS := 5   ; 5 x FISH_POLL_MS = 750ms of continuous absence required
global FISH_SETTLE_MS := 600           ; brief wait after clicking, just long enough to cover the click-marker animation itself
global FISH_ACQUIRE_TIMEOUT_MS := 10000 ; after clicking, wait up to this long for the spot to be seen ANYWHERE in the area at least once (covers a walk of any distance) before switching to tight small-box tracking - see FishPhase
global FISH_POLL_MS := 150             ; how often to re-check both exit conditions while fishing, and how often the tracking box gets to re-center on the spot's drifting position
; Safety cap on a single tracked spot: if NEITHER the inventory
; fills NOR the spot leaves within this long, stop instead of
; hanging forever - this should only ever fire if something is
; genuinely broken (focus lost, miscalibrated inventory check),
; never during normal operation. Confirmed via debug log that 2
; minutes was too aggressive: a real fishing spot tracked correctly
; the whole time, simply because filling ~27 inventory slots via
; passive net fishing can legitimately take several minutes.
global FISH_TIMEOUT_MS := 900000       ; 15 minutes
global PHASE_TIMEOUT_FISH := 45000     ; give up and stop if we can't find ANY spot in the area for 45s straight (resets every time we click - see ResetPhaseTimer). Fishing spots can sit "gone" for several real seconds between despawning and respawning nearby - unlike mining rocks, which are basically always immediately visible - so this needs more headroom than the mining template's equivalent or it can mistake a normal respawn gap for being stuck.

; ---------- Tunables: bank marker + deposit ----------
global BANK_MARKER_COLOR := 0x0000FF
global BANK_MARKER_TOLERANCE := 20
global BANK_MARKER_CLICK_OFFSET_X := 10
global BANK_MARKER_CLICK_OFFSET_Y := 30
global BANK_MARKER_SEARCH_TIMEOUT_MS := 8000
; Scanning the WHOLE screen for this color risked matching some
; unrelated blue pixel elsewhere (UI chrome, chat, etc) before ever
; reaching the real marker - restrict the search to the box where
; the marker actually appears. 800x600px box, top-left (1082, 0).
global BANK_MARKER_SEARCH_X1 := 0
global BANK_MARKER_SEARCH_Y1 := 0
global BANK_MARKER_SEARCH_X2 := 800
global BANK_MARKER_SEARCH_Y2 := 800
; Instead of a flat guess for how long the walk-to-bank + bank-open
; takes, wait until the Deposit All button image is actually
; visible near its known position - DEPOSIT_IMG below.
global DEPOSIT_IMG := A_ScriptDir "\..\images\deposit.png"
global DEPOSIT_IMG_OPTIONS := "*20"   ; deposit.png is a direct screenshot of the button (matches its 72x72 size exactly) - just a little shade tolerance, no transparency trick needed
global DEPOSIT_IMG_W := 72
global DEPOSIT_IMG_H := 72
global DEPOSIT_BTN_SEARCH_MARGIN := 20   ; how far past the button's own box to search - the button is a fixed UI element, not a world object, so this only needs to cover minor calibration slack
global BANK_OPEN_TIMEOUT_MS := 15000      ; give up waiting for the bank to visibly open after this long
; Two small settle delays around the bank-open detection: one right
; after clicking to open the bank (before we even start polling for
; the Deposit All button), and one right after we find AND click
; it. Both apply every time, even if the button was already visible
; the instant we started polling - they're not a substitute for the
; detection itself, just a safety margin around it.
global BANK_OPEN_SETTLE_MS := 300
global BANK_OPEN_FAILSAFE_DELAY_MS := 300
global PHASE_TIMEOUT_BANK := 30000
global NET_BANK_SLOT_INDEX := 1   ; which bank slot (1-8, left to right - see Grid.ahk's GetBankSlots) holds the net to withdraw after depositing
global WITHDRAW_SETTLE_MS := 300  ; pause after the withdrawal click before walking back - long enough for the inventory display to finish updating (see BankWithdrawSlot in lib\Bank.ahk)

; ---------- Calibrated values (loaded from INI, or unset) ----------
; emptySlotPoints is a list of {x, y, color} - several reference
; points inside the last inventory slot, all captured by one F3
; press. See IsAnyPointOccupied (Colors.ahk).
global emptySlotPoints := []

; Fishing-area search region (two opposite corners, order-independent).
global fishAreaCorner1 := ""
global FISH_AREA_X1 := 0, FISH_AREA_Y1 := 0, FISH_AREA_X2 := 0, FISH_AREA_Y2 := 0
global lastSearchTipAt := 0

; ---------- Run/walk setting - plain config flag, no hotkey ----------
global runMode := false

; ---------- Recorded path ----------
global toFishingSpotRecorder := NewPathRecorder()
global toFishingSpotSteps := []

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
    global fishAreaCorner1
    MouseGetPos(&mx, &my)
    fishAreaCorner1 := {x: mx, y: my}
    ShowTipFor("Fishing area corner 1 set at " mx ", " my " - now hover the opposite corner and press F2", 2000)
}

F2:: {
    global fishAreaCorner1, FISH_AREA_X1, FISH_AREA_Y1, FISH_AREA_X2, FISH_AREA_Y2
    if (fishAreaCorner1 = "") {
        ShowTipFor("Press F1 first to set the other corner", 1500)
        return
    }
    MouseGetPos(&mx, &my)
    x1 := Min(fishAreaCorner1.x, mx)
    y1 := Min(fishAreaCorner1.y, my)
    x2 := Max(fishAreaCorner1.x, mx)
    y2 := Max(fishAreaCorner1.y, my)
    FISH_AREA_X1 := x1, FISH_AREA_Y1 := y1, FISH_AREA_X2 := x2, FISH_AREA_Y2 := y2
    SaveRegion(CONFIG, "FishArea", x1, y1, x2, y2)
    ShowTipFor("Fishing area saved: (" x1 ", " y1 ") to (" x2 ", " y2 ")", 2000)
}

F3:: {
    global emptySlotPoints
    ; Uses the standard 28-slot inventory grid from Grid.ahk to
    ; find the LAST slot, then samples 4 points spread around it
    ; (GetDefaultSlotOffsets) instead of just its one center pixel
    ; - make sure the last slot is genuinely empty before pressing.
    slots := GetInventorySlots()
    lastSlot := slots[slots.Length]
    points := GetSlotSamplePoints(lastSlot, GetDefaultSlotOffsets())
    for p in points
        p["color"] := PixelGetColor(p["x"], p["y"], "RGB")
    emptySlotPoints := points
    SaveColorPointList(CONFIG, "InventoryEmptyPoints", emptySlotPoints)
    ShowTipFor("Empty-slot reference points saved (make sure last slot was empty!)", 1800)
}

F4:: ToggleRecording(toFishingSpotRecorder, "ToFishingSpot", "WALK-TO-FISHING-SPOT")

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

ToggleRecording(recorder, sectionName, label) {
    global toFishingSpotRecorder, toFishingSpotSteps
    if (recorder["active"]) {
        steps := StopRecording(recorder)
        SavePath(CONFIG, sectionName, steps)
        toFishingSpotSteps := steps
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

; Fires on every click while the recorder is active.
RecordClick(*) {
    global toFishingSpotRecorder, runMode
    if (!toFishingSpotRecorder["active"])
        return

    MouseGetPos(&mx, &my)
    button := InStr(A_ThisHotkey, "RButton") ? "Right" : "Left"
    RecordClickStep(toFishingSpotRecorder, mx, my, button, runMode ? 1 : 0)
}

; ============================================================
;  CONFIG LOAD
; ============================================================

LoadConfig() {
    global emptySlotPoints, runMode, toFishingSpotSteps
    global FISH_AREA_X1, FISH_AREA_Y1, FISH_AREA_X2, FISH_AREA_Y2

    emptySlotPoints := LoadColorPointList(CONFIG, "InventoryEmptyPoints")
    runMode := LoadFlag(CONFIG, "Settings", "runMode", false)
    toFishingSpotSteps := LoadPath(CONFIG, "ToFishingSpot")

    region := LoadRegion(CONFIG, "FishArea")
    FISH_AREA_X1 := region[1]
    FISH_AREA_Y1 := region[2]
    FISH_AREA_X2 := region[3]
    FISH_AREA_Y2 := region[4]
}

; ============================================================
;  SETUP VALIDATION
; ============================================================

ValidateSetup() {
    global emptySlotPoints, toFishingSpotSteps
    global FISH_AREA_X1, FISH_AREA_Y1, FISH_AREA_X2, FISH_AREA_Y2
    global FISH_IMG, DEPOSIT_IMG
    v := NewValidator()
    RequireRegion(v, "F1/F2 - fishing area", FISH_AREA_X1, FISH_AREA_Y1, FISH_AREA_X2, FISH_AREA_Y2)
    RequireNonEmpty(v, "F3 - inventory slot reference points", emptySlotPoints)
    RequirePath(v, "F4 - walk-to-fishing-spot path", toFishingSpotSteps)
    RequireFile(v, "anch.png (fishing spot image)", FISH_IMG)
    RequireFile(v, "deposit.png (bank deposit image)", DEPOSIT_IMG)
    return ShowValidationErrors(v)
}

StartBot() {
    global toFishingSpotRecorder, runner, LOG_FILE
    global PHASE_TIMEOUT_FISH, PHASE_TIMEOUT_BANK
    if (toFishingSpotRecorder["active"]) {
        ShowTipFor("Finish recording before starting the bot", 1200)
        return
    }
    if (!ValidateSetup())
        return

    AddPhase(runner, "fish", FishPhase, PHASE_TIMEOUT_FISH)
    AddPhase(runner, "bank", BankPhase, PHASE_TIMEOUT_BANK)
    StartTaskRunner(runner, "fish")
    ShowTipFor("Bot started", 1000)
    LogLine(LOG_FILE, "===== Bot started =====")
}

; ============================================================
;  PHASES
; ============================================================

; Finds and clicks a fishing spot, then blocks - polling both exit
; conditions every tick - until the inventory fills up or this
; exact spot disappears, whichever happens first.
FishPhase(taskRunner) {
    global emptySlotPoints, runMode, COLOR_TOLERANCE
    global FISH_AREA_X1, FISH_AREA_Y1, FISH_AREA_X2, FISH_AREA_Y2
    global FISH_IMG, FISH_IMG_OPTIONS, FISH_IMG_W, FISH_IMG_H, FISH_CLICK_BOX
    global FISH_SPOT_RADIUS, FISH_SPOT_GONE_CONFIRM_TICKS
    global FISH_SETTLE_MS, FISH_ACQUIRE_TIMEOUT_MS, FISH_POLL_MS, FISH_TIMEOUT_MS
    global lastSearchTipAt, LOG_FILE

    if (!RequireOsrsWindowActive()) {
        LogLine(LOG_FILE, "fish: OSRS window not focused - paused")
        return GoToPhase(taskRunner, "fish")
    }

    ; Only searches for a spot to CLICK while we're not already
    ; attached to one - see the header comment for why this matters.
    if (!FindImageCenter(FISH_AREA_X1, FISH_AREA_Y1, FISH_AREA_X2, FISH_AREA_Y2, FISH_IMG, FISH_IMG_W, FISH_IMG_H, &cx, &cy, FISH_IMG_OPTIONS)) {
        ; Failing to find ANYTHING here is silent by design (it's
        ; the normal "nothing ready yet" tick, happens constantly
        ; for split seconds) - but if it keeps failing for several
        ; seconds straight, that usually means the spot relocated
        ; OUTSIDE the calibrated F1/F2 area rather than just being
        ; momentarily gone. Surface that with an occasional tooltip
        ; (and log line) instead of going silently idle until
        ; PHASE_TIMEOUT_FISH eventually stops the bot.
        if (A_TickCount - lastSearchTipAt > 4000) {
            ShowTipFor("No fishing spot found in the calibrated area - still searching...", 1500)
            LogLine(LOG_FILE, "fish: no spot found in area, still searching")
            lastSearchTipAt := A_TickCount
        }
        return GoToPhase(taskRunner, "fish")   ; nothing there yet - try again next tick
    }

    LogLine(LOG_FILE, "fish: found spot at " cx "," cy " - clicking")
    HumanClick(cx, cy, FISH_CLICK_BOX, FISH_CLICK_BOX, runMode)
    ResetPhaseTimer(taskRunner)

    ; Brief settle so the click-marker animation itself isn't
    ; immediately mistaken for the spot disappearing.
    Sleep(JitterDelay(FISH_SETTLE_MS))

    ; ACQUIRE STAGE: if we clicked a spot far away, the camera can
    ; drift A LOT over the course of the whole walk - potentially
    ; well outside a small box centered on the ORIGINAL click point.
    ; Searching only that small box from the very first poll means
    ; it might never get a single hit before giving up, especially
    ; now that the "gone" threshold is short (see below) - which is
    ; exactly what caused clicking again on a still-valid spot, or
    ; even a different one, while still walking toward the first.
    ; So first, search the WHOLE calibrated area (not a small box,
    ; no position assumed) repeatedly until the spot is seen even
    ; once post-click - this tolerates any amount of drift, however
    ; long the walk takes, bounded by FISH_ACQUIRE_TIMEOUT_MS. Once
    ; acquired, cx/cy reflects a CURRENT real position, and we hand
    ; off to the tight small-box tracking loop below.
    acquired := false
    acquireDeadline := A_TickCount + FISH_ACQUIRE_TIMEOUT_MS
    loop {
        if (IsAnyPointOccupied(emptySlotPoints, COLOR_TOLERANCE)) {
            LogLine(LOG_FILE, "fish: inventory full (during acquire) -> bank")
            return GoToPhase(taskRunner, "bank")
        }
        if (FindImageCenter(FISH_AREA_X1, FISH_AREA_Y1, FISH_AREA_X2, FISH_AREA_Y2, FISH_IMG, FISH_IMG_W, FISH_IMG_H, &cx, &cy, FISH_IMG_OPTIONS)) {
            acquired := true
            break
        }
        if (A_TickCount >= acquireDeadline)
            break   ; never reappeared anywhere in the area - treat as already gone below
        Sleep(FISH_POLL_MS)
    }
    if (!acquired) {
        LogLine(LOG_FILE, "fish: never saw the spot again after clicking (acquire timeout) -> re-search")
        return GoToPhase(taskRunner, "fish")   ; nothing to track - go back and search fresh
    }
    LogLine(LOG_FILE, "fish: acquired at " cx "," cy " - tracking")

    ; TRACK STAGE: now that we have a CURRENT real position, this
    ; loop RE-CENTERS a small box on the spot's position every
    ; single poll - each successful find updates cx/cy to wherever
    ; it was just found, so the box slides along with however much
    ; the camera still pans between polls. Only when it can't be
    ; found ANYWHERE near its last known position for several
    ; consecutive polls in a row do we conclude it actually left
    ; (not just drifted) - scoped to a small box (not the whole
    ; area) specifically so a different, unrelated spot appearing
    ; elsewhere is never mistaken for ours still being here, which
    ; is what lets this correctly switch to a new spot once ours is
    ; truly gone.
    missingStreak := 0
    deadline := A_TickCount + FISH_TIMEOUT_MS
    loop {
        if (IsAnyPointOccupied(emptySlotPoints, COLOR_TOLERANCE)) {
            LogLine(LOG_FILE, "fish: inventory full -> bank")
            return GoToPhase(taskRunner, "bank")
        }

        if (FindImageCenter(cx - FISH_SPOT_RADIUS, cy - FISH_SPOT_RADIUS, cx + FISH_SPOT_RADIUS, cy + FISH_SPOT_RADIUS, FISH_IMG, FISH_IMG_W, FISH_IMG_H, &ncx, &ncy, FISH_IMG_OPTIONS)) {
            cx := ncx
            cy := ncy
            missingStreak := 0
        } else {
            missingStreak += 1
            if (missingStreak >= FISH_SPOT_GONE_CONFIRM_TICKS) {
                ; The spot leaving (after we successfully fished it
                ; for a while) IS real progress, just like the
                ; initial click - reset here too. Without this, the
                ; entire fishing duration we just spent (often much
                ; longer than PHASE_TIMEOUT_FISH) counts as "stuck",
                ; since returning the SAME phase name ("fish") does
                ; NOT reset the timer the way changing phase would -
                ; so the very next tick would immediately see the
                ; phase as timed-out and silently stop the bot
                ; instead of searching for the new spot.
                ResetPhaseTimer(taskRunner)
                LogLine(LOG_FILE, "fish: spot confirmed gone after " missingStreak " misses (last seen near " cx "," cy ") -> re-search")
                return GoToPhase(taskRunner, "fish")   ; moved/depleted - loop will search the area again
            }
        }

        if (A_TickCount >= deadline) {
            StopAndLog(taskRunner, "Fishing timed out - spot never left and inventory never filled")
            return GoToPhase(taskRunner, "fish")
        }
        Sleep(FISH_POLL_MS)
    }
}

; Finds the calibrated bank-marker color, clicks it with a fixed
; offset, waits for the walk + bank-open, deposits everything and
; withdraws a fresh net, then walks back to the fishing spot.
BankPhase(taskRunner) {
    global toFishingSpotSteps, runMode, LOG_FILE
    global BANK_MARKER_COLOR, BANK_MARKER_TOLERANCE, BANK_MARKER_SEARCH_TIMEOUT_MS
    global BANK_MARKER_CLICK_OFFSET_X, BANK_MARKER_CLICK_OFFSET_Y
    global BANK_MARKER_SEARCH_X1, BANK_MARKER_SEARCH_Y1, BANK_MARKER_SEARCH_X2, BANK_MARKER_SEARCH_Y2
    global DEPOSIT_IMG, BANK_OPEN_SETTLE_MS, BANK_OPEN_FAILSAFE_DELAY_MS
    global NET_BANK_SLOT_INDEX, WITHDRAW_SETTLE_MS

    if (!RequireOsrsWindowActive()) {
        LogLine(LOG_FILE, "bank: OSRS window not focused - paused")
        return GoToPhase(taskRunner, "bank")
    }

    LogLine(LOG_FILE, "bank: entered bank phase, searching for marker color")

    ; First pixel matching this color, scanning from the top-left
    ; of the screen (PixelSearch's natural scan order), restricted
    ; to a top-left box - typically a plugin highlight marking the
    ; nearest bank.
    if (!WaitForPixelSearch(&fx, &fy, BANK_MARKER_SEARCH_X1, BANK_MARKER_SEARCH_Y1, BANK_MARKER_SEARCH_X2, BANK_MARKER_SEARCH_Y2, BANK_MARKER_COLOR, BANK_MARKER_TOLERANCE, BANK_MARKER_SEARCH_TIMEOUT_MS)) {
        StopAndLog(taskRunner, "Could not find the bank marker color")
        return GoToPhase(taskRunner, "bank")
    }

    LogLine(LOG_FILE, "bank: marker found at " fx "," fy " - clicking with offset")
    ; The marker pixel itself usually isn't the clickable spot -
    ; offset into the actual bank tile/icon next to it.
    HumanClick(fx + BANK_MARKER_CLICK_OFFSET_X, fy + BANK_MARKER_CLICK_OFFSET_Y, 0, 0, runMode)

    ; Open the bank and deposit everything (shared lib\Bank.ahk).
    if (!BankDepositAll(DEPOSIT_IMG, BANK_OPEN_SETTLE_MS, BANK_OPEN_FAILSAFE_DELAY_MS)) {
        StopAndLog(taskRunner, "Bank never opened (Deposit All button not found)")
        return GoToPhase(taskRunner, "bank")
    }

    LogLine(LOG_FILE, "bank: deposited, withdrawing net from slot " NET_BANK_SLOT_INDEX)
    BankWithdrawSlot(NET_BANK_SLOT_INDEX, WITHDRAW_SETTLE_MS)

    LogLine(LOG_FILE, "bank: playing walk-to-fishing-spot path (" toFishingSpotSteps.Length " steps)")
    isRunningFn := () => taskRunner["running"]
    if (!PlayPathWithGuard(toFishingSpotSteps, isRunningFn)) {
        StopAndLog(taskRunner, "Walk-to-fishing-spot path failed or was stopped")
        return GoToPhase(taskRunner, "bank")
    }

    LogLine(LOG_FILE, "bank: done, returning to fish phase")
    return GoToPhase(taskRunner, "fish")
}
