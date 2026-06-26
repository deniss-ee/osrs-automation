; ============================================================
;  auto-motherlode.ahk
;  Motherlode Mine bot, built entirely from the shared lib\
;  functions - same library auto-miner.ahk, auto-smelter.ahk,
;  auto-fisher.ahk and auto-smith.ahk use. Detects mining spots by
;  IMAGE (ImageSearch), not a single pixel color, since each spot
;  is a colored circle overlay that can be semi-transparent over
;  different backgrounds - a single calibrated color (the approach
;  the legacy motherlode-miner.ahk uses) can't reliably bracket
;  that drift. This is a brand-new script, not a port - there is
;  no prior working baseline to compare against.
;
;  THE SIX SPOT IMAGES: every mining spot on screen is a colored
;  circle, corner-keyed with #0000FF so ImageSearch can treat that
;  as transparent and match just the circle. Each state is actually
;  TWO images bracketing the shade range the overlay's translucency
;  can land in over different backgrounds - one direct color, one
;  semi-transparent blend:
;    full.png / semifull.png    = green  = minable, click it
;    empty.png / semiempty.png  = yellow = just depleted
;    none.png  / seminone.png   = red    = nothing minable right
;                                  now, stop for now
;  FindAnyImageCenter (lib\Images.ahk) searches for either image of
;  a pair as one logical match, with a moderate per-channel shade
;  tolerance (SPOT_IMG_OPTIONS) - wide enough to cover both
;  reference shades, but not so wide it risks bleeding into a
;  different state's color range.
;
;  EXPECTED STARTING STATE: standing in the mining area with an
;  empty inventory, at least one mining spot visible.
;
;  CYCLE:
;    1. Search the calibrated MINING AREA for a green spot
;       (full.png/semifull.png) and click its center.
;    2. The camera can pan while walking to/working a spot, so the
;       wait-for-depletion loop continuously RE-CENTERS a small box
;       on wherever the spot was last found (same technique as
;       auto-fisher.ahk's FishPhase) rather than watching one fixed
;       point - but that box only re-centers on full/semifull matches,
;       and while actively being mined a spot shows a live "timer"
;       overlay that matches neither full/semifull nor empty/semiempty
;       (a 7th visual state none of the six reference PNGs cover), so
;       the box can drift off the spot's real position over the whole
;       mining duration if the camera pans. So "Depleted" is an
;       EXPLICIT positive match on empty.png/semiempty.png (yellow)
;       ANYWHERE in the calibrated mining area, not just the drifted
;       box - unlike green (several other veins normally show
;       green/semi-full at once, making "another green spot exists
;       somewhere" useless as a signal - see bug history), yellow is a
;       brief, comparatively rare transition state, so a stray match
;       elsewhere is unlikely and low-cost (worst case: one early
;       re-scan). There is no "missing -> assume depleted" fallback -
;       a "matched neither" poll is ignored and the wait just keeps
;       polling until yellow actually appears (or the hard
;       SPOT_DEPLETE_TIMEOUT_MS safety net fires).
;    3. The instant a spot depletes, re-scan immediately for another
;       green spot (auto-miner.ahk's tight inner loop - no waiting
;       for the next task-runner tick) until none are found.
;    4. When the inventory is full, find the calibrated bank/hopper
;       marker color (#FFFF00) in the calibrated BANK MARKER AREA
;       and click it with a fixed offset - this is a single click,
;       deposit is fully automated by the game (the character runs
;       to the hopper and deposits on its own). There's no "deposit
;       done" pixel to poll for, so just wait out a flat tunable/
;       jittered duration (DEPOSIT_RUN_WAIT_MS - same idea as the
;       legacy motherlode-miner.ahk's hardcoded 10s wait, just
;       named/tunable/jittered) before playing the recorded RUN-BACK
;       path back to the mining spot.
;    5. If a red spot (none.png/seminone.png) is found instead of
;       any green spot, the mining flow for this area is done for
;       now - stop the bot.
;
;  HOTKEYS
;    F1   = mark mining-area corner 1 (hover near one corner of the
;           area mining spots can appear in, press F1)
;    F2   = mark mining-area corner 2 (hover the opposite corner,
;           press F2 - order doesn't matter, corners are sorted
;           automatically)
;    F3   = save "empty inventory slot" reference points - EMPTY
;           YOUR INVENTORY first, then press F3 (no need to hover
;           anywhere specific). Samples FOUR points around the LAST
;           inventory slot, same mechanism as every other script.
;    F4   = mark bank/hopper marker search-area corner 1
;    F5   = mark bank/hopper marker search-area corner 2 (saves
;           region - order doesn't matter)
;    F6   = start/stop recording the RUN-BACK path (from the hopper,
;           once the automated deposit run finishes, back to a
;           mining spot - start right after the deposit animation
;           would end, stop once you're standing at a mining spot)
;    F7   = start the bot
;    F8   = stop the bot
;    F9   = clear saved config and reload the script
;
;  RUN MODE is a plain setting in the .ini, not a hotkey - same as
;  the other scripts. Open config\auto-motherlode.ini, find
;  [Settings], set
;
;      runMode=1   (hold Ctrl / run for every click)
;      runMode=0   (never hold Ctrl / always walk - the default)
;
;  then restart the script.
;
;  DEBUG LOGGING: every phase transition and bank-detection outcome
;  is timestamped and appended to LOG_FILE
;  (logs\auto-motherlode-debug.log) via lib\Log.ahk.
;
;  Config auto-saves to config\auto-motherlode.ini next to this file.
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
#Include ..\lib\Validate.ahk
#Include ..\lib\TaskRunner.ahk
#Include ..\lib\Log.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

; ---------- Config file ----------
global CONFIG := A_ScriptDir "\..\config\auto-motherlode.ini"

; ---------- Debug log ----------
; Plain text, timestamped, appended to forever - read this after a
; run to see exactly what the bot did, since a tooltip might not
; actually be visible depending on how the game window is running.
global LOG_FILE := A_ScriptDir "\..\logs\auto-motherlode-debug.log"

; Stops the runner AND records why in the debug log, so a stop that
; happens off-screen (or whose tooltip you miss) is never a mystery -
; just open auto-motherlode-debug.log afterward.
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

; ---------- Tunables: mining-spot images ----------
global SPOT_FULL_IMAGES  := [A_ScriptDir "\..\images\full.png", A_ScriptDir "\..\images\semifull.png"]
global SPOT_EMPTY_IMAGES := [A_ScriptDir "\..\images\empty.png", A_ScriptDir "\..\images\semiempty.png"]
global SPOT_NONE_IMAGES  := [A_ScriptDir "\..\images\none.png", A_ScriptDir "\..\images\seminone.png"]
global SPOT_IMG_W := 52, SPOT_IMG_H := 52
; Corners are blue-keyed (#0000FF) per the PNGs themselves - *Trans
; treats that as transparent. *40 brackets BOTH reference shades of
; whichever state is being searched for (e.g. green's direct #00FF00
; and its semi-transparent blend #23BA0B) - tune this if green/
; yellow/red ever cross-match each other.
global SPOT_IMG_OPTIONS := "*Trans0x0000FF *40"
global SPOT_CLICK_BOX := 12           ; humanized click lands within +/-12px of the spot's true center
global SPOT_CLICK_SETTLE_MS := 300    ; brief wait after clicking, before the first depletion check
; Small box half-size around the clicked spot's found center, slid
; to follow the spot's on-screen drift each poll (camera pans while
; the character walks to/works a spot) while waiting for it to show
; yellow - same continuous re-centering technique as auto-fisher.ahk.
global SPOT_DEPLETE_RADIUS := 40
global SPOT_DEPLETE_TIMEOUT_MS := 60000
global SPOT_DEPLETE_CONFIRM_TICKS := 2   ; require an explicit yellow match for this many consecutive polls before trusting it - filters a single transient glitch. A real depleted spot renders yellow immediately and consistently, so this can stay fast.
global SPOT_POLL_MS := 150
global PHASE_TIMEOUT_MINE := 45000    ; give up and stop if no click happens for 45s straight (resets every time we click - see ResetPhaseTimer). Veins can take a while to regenerate after going red.
global PHASE_TIMEOUT_BANK := 30000

; ---------- Tunables: bank/hopper marker + deposit ----------
global BANK_MARKER_COLOR := 0xFFFF00
global BANK_MARKER_TOLERANCE := 20
global BANK_MARKER_CLICK_OFFSET_X := 10, BANK_MARKER_CLICK_OFFSET_Y := 20
global BANK_MARKER_SEARCH_TIMEOUT_MS := 8000
; The hopper click triggers the game's own automated run-there-and-
; deposit animation - there's no "deposit done" pixel to poll for,
; so just wait out a flat tunable/jittered duration before walking
; back. Same idea as the legacy motherlode-miner.ahk's hardcoded
; Sleep(10000) after its bank click, just named/tunable/jittered
; instead of a bare literal. Sanity-check this against your own
; actual run+deposit time before relying on it unattended.
global DEPOSIT_RUN_WAIT_MS := 10000

; ---------- Calibrated values (loaded from INI, or unset) ----------
; Mining-area search region (two opposite corners, order-independent).
global miningAreaCorner1 := ""
global MINING_AREA_X1 := 0, MINING_AREA_Y1 := 0, MINING_AREA_X2 := 0, MINING_AREA_Y2 := 0

; Bank/hopper marker search region (two opposite corners, order-independent).
global bankAreaCorner1 := ""
global BANK_AREA_X1 := 0, BANK_AREA_Y1 := 0, BANK_AREA_X2 := 0, BANK_AREA_Y2 := 0

; emptySlotPoints is a list of {x, y, color} - several reference
; points inside the last inventory slot, all captured by one F3
; press. See IsAnyPointOccupied (Colors.ahk).
global emptySlotPoints := []

global lastSearchTipAt := 0

; ---------- Run/walk setting - plain config flag, no hotkey ----------
global runMode := false

; ---------- Recorded path ----------
global runBackRecorder := NewPathRecorder()
global runBackSteps := []

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
    global miningAreaCorner1
    MouseGetPos(&mx, &my)
    miningAreaCorner1 := {x: mx, y: my}
    ShowTipFor("Mining area corner 1 set at " mx ", " my " - now hover the opposite corner and press F2", 2000)
}

F2:: {
    global miningAreaCorner1, MINING_AREA_X1, MINING_AREA_Y1, MINING_AREA_X2, MINING_AREA_Y2
    if (miningAreaCorner1 = "") {
        ShowTipFor("Press F1 first to set the other corner", 1500)
        return
    }
    MouseGetPos(&mx, &my)
    x1 := Min(miningAreaCorner1.x, mx)
    y1 := Min(miningAreaCorner1.y, my)
    x2 := Max(miningAreaCorner1.x, mx)
    y2 := Max(miningAreaCorner1.y, my)
    MINING_AREA_X1 := x1, MINING_AREA_Y1 := y1, MINING_AREA_X2 := x2, MINING_AREA_Y2 := y2
    SaveRegion(CONFIG, "MiningArea", x1, y1, x2, y2)
    ShowTipFor("Mining area saved: (" x1 ", " y1 ") to (" x2 ", " y2 ")", 2000)
}

F3:: {
    global emptySlotPoints
    ; Uses the standard 28-slot inventory grid from Grid.ahk to find
    ; the LAST slot, then samples 4 points spread around it
    ; (GetDefaultSlotOffsets) instead of just its one center pixel -
    ; make sure your inventory is empty before pressing this.
    slots := GetInventorySlots()
    lastSlot := slots[slots.Length]
    points := GetSlotSamplePoints(lastSlot, GetDefaultSlotOffsets())
    for p in points
        p["color"] := PixelGetColor(p["x"], p["y"], "RGB")
    emptySlotPoints := points
    SaveColorPointList(CONFIG, "InventoryEmptyPoints", emptySlotPoints)
    ShowTipFor("Empty-slot reference points saved (make sure inventory was empty!)", 1800)
}

F4:: {
    global bankAreaCorner1
    MouseGetPos(&mx, &my)
    bankAreaCorner1 := {x: mx, y: my}
    ShowTipFor("Bank/hopper marker area corner 1 set at " mx ", " my " - now hover the opposite corner and press F5", 2000)
}

F5:: {
    global bankAreaCorner1, BANK_AREA_X1, BANK_AREA_Y1, BANK_AREA_X2, BANK_AREA_Y2
    if (bankAreaCorner1 = "") {
        ShowTipFor("Press F4 first to set the other corner", 1500)
        return
    }
    MouseGetPos(&mx, &my)
    x1 := Min(bankAreaCorner1.x, mx)
    y1 := Min(bankAreaCorner1.y, my)
    x2 := Max(bankAreaCorner1.x, mx)
    y2 := Max(bankAreaCorner1.y, my)
    BANK_AREA_X1 := x1, BANK_AREA_Y1 := y1, BANK_AREA_X2 := x2, BANK_AREA_Y2 := y2
    SaveRegion(CONFIG, "BankMarkerArea", x1, y1, x2, y2)
    ShowTipFor("Bank/hopper marker area saved: (" x1 ", " y1 ") to (" x2 ", " y2 ")", 2000)
}

F6:: ToggleRecording(runBackRecorder, "RunBack", "RUN-BACK")

F7:: StartBot()
F8:: StopAndLog(runner, "Stopped (F8)")

F9:: {
    if FileExist(CONFIG)
        FileDelete(CONFIG)
    Reload()
}

; ============================================================
;  PATH RECORDING
; ============================================================

ToggleRecording(recorder, sectionName, label) {
    global runBackRecorder, runBackSteps
    if (recorder["active"]) {
        steps := StopRecording(recorder)
        SavePath(CONFIG, sectionName, steps)
        runBackSteps := steps
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
    global runBackRecorder, runMode
    if (!runBackRecorder["active"])
        return

    MouseGetPos(&mx, &my)
    button := InStr(A_ThisHotkey, "RButton") ? "Right" : "Left"
    RecordClickStep(runBackRecorder, mx, my, button, runMode ? 1 : 0)
}

; ============================================================
;  CONFIG LOAD
; ============================================================

LoadConfig() {
    global emptySlotPoints, runMode, runBackSteps
    global MINING_AREA_X1, MINING_AREA_Y1, MINING_AREA_X2, MINING_AREA_Y2
    global BANK_AREA_X1, BANK_AREA_Y1, BANK_AREA_X2, BANK_AREA_Y2

    emptySlotPoints := LoadColorPointList(CONFIG, "InventoryEmptyPoints")
    runMode := LoadFlag(CONFIG, "Settings", "runMode", false)
    runBackSteps := LoadPath(CONFIG, "RunBack")

    miningRegion := LoadRegion(CONFIG, "MiningArea")
    MINING_AREA_X1 := miningRegion[1]
    MINING_AREA_Y1 := miningRegion[2]
    MINING_AREA_X2 := miningRegion[3]
    MINING_AREA_Y2 := miningRegion[4]

    bankRegion := LoadRegion(CONFIG, "BankMarkerArea")
    BANK_AREA_X1 := bankRegion[1]
    BANK_AREA_Y1 := bankRegion[2]
    BANK_AREA_X2 := bankRegion[3]
    BANK_AREA_Y2 := bankRegion[4]
}

; ============================================================
;  SETUP VALIDATION
; ============================================================

ValidateSetup() {
    global emptySlotPoints, runBackSteps
    global MINING_AREA_X1, MINING_AREA_Y1, MINING_AREA_X2, MINING_AREA_Y2
    global BANK_AREA_X1, BANK_AREA_Y1, BANK_AREA_X2, BANK_AREA_Y2
    v := NewValidator()
    RequireRegion(v, "F1/F2 - mining area", MINING_AREA_X1, MINING_AREA_Y1, MINING_AREA_X2, MINING_AREA_Y2)
    RequireNonEmpty(v, "F3 - empty inventory slot reference points", emptySlotPoints)
    RequireRegion(v, "F4/F5 - bank/hopper marker area", BANK_AREA_X1, BANK_AREA_Y1, BANK_AREA_X2, BANK_AREA_Y2)
    RequirePath(v, "F6 - run-back path", runBackSteps)
    RequireFile(v, "full.png (minable spot image)", A_ScriptDir "\..\images\full.png")
    RequireFile(v, "semifull.png (minable spot image)", A_ScriptDir "\..\images\semifull.png")
    RequireFile(v, "empty.png (depleted spot image)", A_ScriptDir "\..\images\empty.png")
    RequireFile(v, "semiempty.png (depleted spot image)", A_ScriptDir "\..\images\semiempty.png")
    RequireFile(v, "none.png (no minable spots image)", A_ScriptDir "\..\images\none.png")
    RequireFile(v, "seminone.png (no minable spots image)", A_ScriptDir "\..\images\seminone.png")
    return ShowValidationErrors(v)
}

StartBot() {
    global runBackRecorder, runner, LOG_FILE
    global PHASE_TIMEOUT_MINE, PHASE_TIMEOUT_BANK
    if (runBackRecorder["active"]) {
        ShowTipFor("Finish recording before starting the bot", 1200)
        return
    }
    if (!ValidateSetup())
        return

    AddPhase(runner, "mine", MinePhase, PHASE_TIMEOUT_MINE)
    AddPhase(runner, "bank", BankPhase, PHASE_TIMEOUT_BANK)
    StartTaskRunner(runner, "mine")
    ShowTipFor("Bot started", 1000)
    LogLine(LOG_FILE, "===== Bot started =====")
}

; ============================================================
;  PHASES
; ============================================================

; Finds and clicks a green (minable) spot, waits for it to show
; yellow (depleted) - tracking its on-screen drift the whole time -
; then immediately re-scans for another green spot. Switches to the
; "bank" phase the moment the last inventory slot is occupied, and
; stops the bot entirely if a red (none-minable) spot is found
; instead of any green one.
MinePhase(taskRunner) {
    global emptySlotPoints, runMode, COLOR_TOLERANCE
    global MINING_AREA_X1, MINING_AREA_Y1, MINING_AREA_X2, MINING_AREA_Y2
    global SPOT_FULL_IMAGES, SPOT_EMPTY_IMAGES, SPOT_NONE_IMAGES, SPOT_IMG_W, SPOT_IMG_H, SPOT_IMG_OPTIONS
    global SPOT_CLICK_BOX, SPOT_CLICK_SETTLE_MS
    global SPOT_DEPLETE_RADIUS, SPOT_DEPLETE_TIMEOUT_MS, SPOT_DEPLETE_CONFIRM_TICKS, SPOT_POLL_MS
    global lastSearchTipAt, LOG_FILE

    if (!RequireOsrsWindowActive()) {
        LogLine(LOG_FILE, "mine: OSRS window not focused - paused")
        return GoToPhase(taskRunner, "mine")
    }

    ; Outer loop: keeps scanning/clicking spots internally, without
    ; returning control to the TaskRunner, for as long as a green
    ; spot is found - removes the round-trip wait for the next
    ; task-runner tick between one spot depleting and the next one
    ; being clicked (same technique as auto-miner.ahk's MinePhase).
    loop {
        if (IsAnyPointOccupied(emptySlotPoints, COLOR_TOLERANCE)) {
            LogLine(LOG_FILE, "mine: inventory full -> bank")
            return GoToPhase(taskRunner, "bank")
        }

        if (FindAnyImageCenter(MINING_AREA_X1, MINING_AREA_Y1, MINING_AREA_X2, MINING_AREA_Y2, SPOT_FULL_IMAGES, SPOT_IMG_W, SPOT_IMG_H, &cx, &cy, &matchedImg, SPOT_IMG_OPTIONS)) {
            LogLine(LOG_FILE, "mine: found minable spot at " cx "," cy " - clicking")
            HumanClick(cx, cy, SPOT_CLICK_BOX, SPOT_CLICK_BOX, runMode)
            ResetPhaseTimer(taskRunner)
            Sleep(JitterDelay(SPOT_CLICK_SETTLE_MS))

            ; Wait for this spot to show yellow (depleted). A small
            ; tracking box slides to follow the clicked spot's on-screen
            ; drift each poll, re-centering on every FULL/semifull match
            ; (the camera pans while the character walks to/works a
            ; spot, so a fixed point goes stale almost immediately - same
            ; issue auto-fisher.ahk solves the same way) - but that box
            ; is ONLY used for the still-minable check. While actively
            ; being mined, a spot shows a live "timer" overlay that
            ; matches neither full/semifull nor empty/semiempty (a 7th
            ; visual state none of the six reference PNGs cover), so
            ; cx/cy stop updating the moment mining starts and don't
            ; move again until the spot is either still-green or yellow -
            ; meaning the box can silently drift off the spot's real
            ; position during the entire mining duration if the camera
            ; pans at all. So the YELLOW check searches the WHOLE
            ; calibrated mining area instead of the drifted box - a
            ; bug where the bot would sit through the full
            ; SPOT_DEPLETE_TIMEOUT_MS without ever seeing yellow (even
            ; though the spot visibly turned yellow in-game) turned out
            ; to be exactly this: the tracking box had drifted off target
            ; by the time depletion happened, not a real absence of the
            ; yellow state. This re-opens the same "another spot
            ; elsewhere" question that made the green/full case unusable
            ; (see bug history) - but yellow is a brief, comparatively
            ; rare transition state (unlike green, which several OTHER
            ; veins normally show continuously at the same time), so a
            ; stray match elsewhere is far less likely and not nearly as
            ; costly: worst case it re-scans a beat early and re-clicks
            ; whichever full/semifull spot is found (possibly the same
            ; one, still mid-mine - harmless). The ONLY ways out of this
            ; loop are inventory-full, an explicit yellow/semi-yellow
            ; match anywhere in the mining area, or the hard
            ; SPOT_DEPLETE_TIMEOUT_MS safety net. A "matched neither"
            ; poll (the timer overlay) is simply ignored - box stays put,
            ; wait continues.
            deadline := A_TickCount + SPOT_DEPLETE_TIMEOUT_MS
            yellowStreak := 0
            loop {
                if (IsAnyPointOccupied(emptySlotPoints, COLOR_TOLERANCE)) {
                    ResetPhaseTimer(taskRunner)
                    LogLine(LOG_FILE, "mine: inventory full (while depleting) -> bank")
                    return GoToPhase(taskRunner, "bank")
                }

                bx1 := cx - SPOT_DEPLETE_RADIUS
                by1 := cy - SPOT_DEPLETE_RADIUS
                bx2 := cx + SPOT_DEPLETE_RADIUS
                by2 := cy + SPOT_DEPLETE_RADIUS

                if (FindAnyImageCenter(bx1, by1, bx2, by2, SPOT_FULL_IMAGES, SPOT_IMG_W, SPOT_IMG_H, &ncx, &ncy, &matchedImg, SPOT_IMG_OPTIONS)) {
                    ; Still minable - slide the box to the new position.
                    cx := ncx
                    cy := ncy
                    yellowStreak := 0
                } else if (FindAnyImageCenter(MINING_AREA_X1, MINING_AREA_Y1, MINING_AREA_X2, MINING_AREA_Y2, SPOT_EMPTY_IMAGES, SPOT_IMG_W, SPOT_IMG_H, &ecx, &ecy, &matchedImg, SPOT_IMG_OPTIONS)) {
                    ; Search the WHOLE mining area for yellow, not just the
                    ; tracked box - see the comment above this loop for why.
                    yellowStreak += 1
                    if (yellowStreak >= SPOT_DEPLETE_CONFIRM_TICKS) {
                        ResetPhaseTimer(taskRunner)
                        LogLine(LOG_FILE, "mine: spot depleted (yellow confirmed) near " cx "," cy)
                        break
                    }
                } else {
                    ; Neither matched - normal mid-mining (timer overlay).
                    ; Don't move the box, don't count this against the
                    ; spot, just keep waiting for an explicit yellow match.
                    yellowStreak := 0
                }

                if (A_TickCount >= deadline) {
                    LogLine(LOG_FILE, "mine: depletion wait timed out near " cx "," cy " (never saw yellow)")
                    break
                }
                Sleep(SPOT_POLL_MS)
            }
            continue   ; re-scan the whole area immediately for the next green spot
        }

        ; No green anywhere - check for the "done for now" signal.
        if (FindAnyImageCenter(MINING_AREA_X1, MINING_AREA_Y1, MINING_AREA_X2, MINING_AREA_Y2, SPOT_NONE_IMAGES, SPOT_IMG_W, SPOT_IMG_H, &rcx, &rcy, &matchedImg, SPOT_IMG_OPTIONS)) {
            StopAndLog(taskRunner, "No minable spots (red) - stopping for now")
            return GoToPhase(taskRunner, "mine")
        }

        ; Neither green nor red found yet (e.g. mid fade/animation) -
        ; surface that with an occasional tooltip/log line if it
        ; keeps happening, instead of going silently idle.
        if (A_TickCount - lastSearchTipAt > 4000) {
            ShowTipFor("No minable or empty spots found in the calibrated area - still searching...", 1500)
            LogLine(LOG_FILE, "mine: no full/empty/none spot found in area, still searching")
            lastSearchTipAt := A_TickCount
        }
        return GoToPhase(taskRunner, "mine")   ; yield to next tick
    }
}

; Finds the calibrated bank/hopper marker color, clicks it with a
; fixed offset (one click - the game runs there and deposits on its
; own), waits out a flat tunable duration covering that automated
; run+deposit animation, then plays the recorded run-back path to a
; mining spot.
BankPhase(taskRunner) {
    global runBackSteps, runMode, LOG_FILE
    global BANK_AREA_X1, BANK_AREA_Y1, BANK_AREA_X2, BANK_AREA_Y2
    global BANK_MARKER_COLOR, BANK_MARKER_TOLERANCE, BANK_MARKER_SEARCH_TIMEOUT_MS
    global BANK_MARKER_CLICK_OFFSET_X, BANK_MARKER_CLICK_OFFSET_Y
    global DEPOSIT_RUN_WAIT_MS

    if (!RequireOsrsWindowActive()) {
        LogLine(LOG_FILE, "bank: OSRS window not focused - paused")
        return GoToPhase(taskRunner, "bank")
    }

    LogLine(LOG_FILE, "bank: searching for hopper marker color")
    if (!WaitForPixelSearch(&fx, &fy, BANK_AREA_X1, BANK_AREA_Y1, BANK_AREA_X2, BANK_AREA_Y2, BANK_MARKER_COLOR, BANK_MARKER_TOLERANCE, BANK_MARKER_SEARCH_TIMEOUT_MS)) {
        StopAndLog(taskRunner, "Could not find the bank/hopper marker color")
        return GoToPhase(taskRunner, "bank")
    }

    LogLine(LOG_FILE, "bank: marker found at " fx "," fy " - clicking with offset")
    HumanClick(fx + BANK_MARKER_CLICK_OFFSET_X, fy + BANK_MARKER_CLICK_OFFSET_Y, 0, 0, runMode)
    ResetPhaseTimer(taskRunner)

    ; The hopper click triggers the game's own automated run-there-
    ; and-deposit animation - there's no "deposit done" pixel to poll
    ; for, so just wait out a flat tunable/jittered duration (same
    ; idea as legacy motherlode-miner.ahk's hardcoded 10s wait).
    Sleep(JitterDelay(DEPOSIT_RUN_WAIT_MS))

    LogLine(LOG_FILE, "bank: playing run-back path (" runBackSteps.Length " steps)")
    isRunningFn := () => taskRunner["running"]
    if (!PlayPathWithGuard(runBackSteps, isRunningFn)) {
        StopAndLog(taskRunner, "Run-back path failed or was stopped")
        return GoToPhase(taskRunner, "bank")
    }

    LogLine(LOG_FILE, "bank: done, returning to mine phase")
    return GoToPhase(taskRunner, "mine")
}
