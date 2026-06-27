; ============================================================
;  auto-motherlode.ahk
;  Motherlode Mine bot - MINING ONLY. No inventory check, no bank
;  phase. This is a direct adaptation of auto-fisher.ahk's FishPhase,
;  not a new design: every previous version of this script (see
;  docs\DOCUMENTATION.md's bug history, #16-#23) tried to tell a
;  depleted vein apart from a busy area's other veins by matching a
;  SEPARATE "yellow/depleted" image - that's the part that kept
;  breaking, because some OTHER vein is very often already yellow at
;  any given moment, so a positive match against a different state's
;  image can never safely mean "ours". auto-fisher.ahk's FishPhase has
;  never had this problem, because it never looks for a different
;  image at all - it tracks ONE spot image continuously and concludes
;  "gone" purely from that same image's ABSENCE near the last known
;  position. This script copies that structure exactly, swapping the
;  fishing spot's image for the vein's, and drops everything fisher
;  needed for banking that mining doesn't (yet).
;
;  THE VEIN IMAGE (images\vein.png): NOT a full-circle screenshot like
;  the old full.png/empty.png/none.png pair-set. It's mostly the
;  background key color (0x4000FF, transparent via *Trans), with four
;  small 2x2 green marks at the top-mid/bottom-mid/left-mid/right-mid
;  edge of a 52x52 box - the vein circle's RIM, not its interior. The
;  interior is exactly where the animated "actively being mined" timer
;  overlay covers the graphic, which is why the old full.png/semifull.png
;  match could go stale mid-mining - by only ever matching the rim,
;  whatever's happening inside is irrelevant, so this should keep
;  matching continuously the whole time a vein is being mined, the same
;  way fisher's single ripple-icon image does.
;
;  EXPECTED STARTING STATE: standing in the mining area, at least one
;  green (minable) vein visible.
;
;  CYCLE (mirrors auto-fisher.ahk's FishPhase, minus the bank handoff):
;    1. Search the calibrated MINING AREA for the vein image and click
;       its center.
;    2. ACQUIRE: search the WHOLE area repeatedly (not a small box)
;       until the vein image is seen at least once post-click - this
;       tolerates however much the camera shifts while walking to a
;       vein that isn't adjacent, bounded by SPOT_ACQUIRE_TIMEOUT_MS.
;    3. TRACK: once acquired, re-search a SMALL box around the vein's
;       last known position every poll, sliding the box to follow
;       however much it drifts. Only when it's missing from that small
;       box for SPOT_GONE_CONFIRM_TICKS consecutive polls in a row is
;       it considered actually gone (depleted or moved on) - never from
;       matching a different image. Scoping to a small box (not the
;       whole area) means a different, unrelated vein appearing
;       elsewhere can't be mistaken for "ours" still being there.
;    4. The instant a vein is confirmed gone, go back to step 1
;       immediately (no waiting for the next task-runner tick) -
;       forever. There is no inventory check and no bank phase in this
;       version.
;
;  CALIBRATION
;    F1   = mark mining-area corner 1 (hover one corner of the patch
;           veins can appear in, press F1)
;    F2   = mark mining-area corner 2 (hover the opposite corner,
;           press F2 - order doesn't matter, corners are sorted
;           automatically)
;    F3   = start the bot
;    F4   = stop the bot
;    F5   = clear saved config and reload the script
;
;  RUN MODE is a plain setting in the .ini, not a hotkey - same as the
;  other scripts. Open config\auto-motherlode.ini, find [Settings], set
;
;      runMode=1   (hold Ctrl / run for every click)
;      runMode=0   (never hold Ctrl / always walk - the default)
;
;  then restart the script.
;
;  Config auto-saves to config\auto-motherlode.ini next to this file.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

#Include ..\lib\Tooltip.ahk
#Include ..\lib\Images.ahk
#Include ..\lib\Safety.ahk
#Include ..\lib\ConfigStore.ahk
#Include ..\lib\Click.ahk
#Include ..\lib\Validate.ahk
#Include ..\lib\TaskRunner.ahk
#Include ..\lib\Log.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

; ---------- Config file ----------
global CONFIG := A_ScriptDir "\..\config\auto-motherlode.ini"

; ---------- Debug log ----------
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
global ENABLE_HUMANIZATION := false

; ---------- Tunables: vein-spot image ----------
global SPOT_IMG := A_ScriptDir "\..\images\vein.png"
global SPOT_IMG_OPTIONS := "*Trans0x4000FF *40"   ; ignore the background key color, allow some shade variation
global SPOT_IMG_W := 52    ; actual pixel size of vein.png - keep in sync if the image file changes
global SPOT_IMG_H := 52
global SPOT_CLICK_BOX := 12            ; humanized click lands within +/-12px of the spot's true center
; Same role as auto-fisher.ahk's FISH_SPOT_RADIUS, same default value -
; this was previously shrunk to 25 on the theory that motherlode veins
; sit closer together than fishing spots, but that turned out to be
; the actual cause of repeat-clicking: the box lost the vein's marker
; (even though the vein was still right there, just outside the
; smaller box), the tracker wrongly concluded "gone", and immediately
; re-found/re-clicked the same still-active vein. Matching fisher's
; proven value fixes that; only shrink this again if live testing
; shows it snapping onto a genuinely different, adjacent vein instead.
global SPOT_TRACK_RADIUS := 70
global SPOT_GONE_CONFIRM_TICKS := 5   ; 5 x SPOT_POLL_MS = 750ms of continuous absence required
global SPOT_SETTLE_MS := 600           ; brief wait after clicking, just long enough to cover the click-marker animation itself (same as fisher's FISH_SETTLE_MS)
global SPOT_ACQUIRE_TIMEOUT_MS := 10000 ; after clicking, wait up to this long for the vein to be seen ANYWHERE in the area at least once (covers a walk of any distance) before switching to tight small-box tracking - see MinePhase (same as fisher's FISH_ACQUIRE_TIMEOUT_MS)
global SPOT_POLL_MS := 150             ; how often to re-check both exit conditions while mining, and how often the tracking box gets to re-center on the vein's drifting position
; Safety cap on a single tracked vein: if it never leaves within this
; long, stop instead of hanging forever - this should only ever fire
; if something is genuinely broken (focus lost, or the tracking box
; well and truly lost the vein), never during normal operation.
global SPOT_TIMEOUT_MS := 900000       ; 15 minutes
global PHASE_TIMEOUT_MINE := 45000     ; give up and stop if we can't find ANY vein in the area for 45s straight (resets every time we click - see ResetPhaseTimer).

; ---------- Calibrated values (loaded from INI, or unset) ----------
; Mining-area search region (two opposite corners, order-independent).
global miningAreaCorner1 := ""
global MINING_AREA_X1 := 0, MINING_AREA_Y1 := 0, MINING_AREA_X2 := 0, MINING_AREA_Y2 := 0
global lastSearchTipAt := 0

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

F3:: StartBot()
F4:: StopAndLog(runner, "Stopped (F4)")

F5:: {
    if FileExist(CONFIG)
        FileDelete(CONFIG)
    Reload()
}

; ============================================================
;  CONFIG LOAD
; ============================================================

LoadConfig() {
    global runMode
    global MINING_AREA_X1, MINING_AREA_Y1, MINING_AREA_X2, MINING_AREA_Y2

    runMode := LoadFlag(CONFIG, "Settings", "runMode", false)

    region := LoadRegion(CONFIG, "MiningArea")
    MINING_AREA_X1 := region[1]
    MINING_AREA_Y1 := region[2]
    MINING_AREA_X2 := region[3]
    MINING_AREA_Y2 := region[4]
}

; ============================================================
;  SETUP VALIDATION
; ============================================================

ValidateSetup() {
    global MINING_AREA_X1, MINING_AREA_Y1, MINING_AREA_X2, MINING_AREA_Y2
    global SPOT_IMG
    v := NewValidator()
    RequireRegion(v, "F1/F2 - mining area", MINING_AREA_X1, MINING_AREA_Y1, MINING_AREA_X2, MINING_AREA_Y2)
    RequireFile(v, "vein.png (mining spot image)", SPOT_IMG)
    return ShowValidationErrors(v)
}

StartBot() {
    global runner, LOG_FILE, PHASE_TIMEOUT_MINE
    if (!ValidateSetup())
        return

    AddPhase(runner, "mine", MinePhase, PHASE_TIMEOUT_MINE)
    StartTaskRunner(runner, "mine")
    ShowTipFor("Bot started", 1000)
    LogLine(LOG_FILE, "===== Bot started =====")
}

; ============================================================
;  PHASE
; ============================================================

; Finds and clicks a vein, then blocks - re-centering a tracking box
; every poll - until this exact vein disappears, then goes straight
; back to searching for the next one. Forever. Direct adaptation of
; auto-fisher.ahk's FishPhase minus the inventory/bank handoff - see
; header comment for why.
MinePhase(taskRunner) {
    global runMode
    global MINING_AREA_X1, MINING_AREA_Y1, MINING_AREA_X2, MINING_AREA_Y2
    global SPOT_IMG, SPOT_IMG_OPTIONS, SPOT_IMG_W, SPOT_IMG_H, SPOT_CLICK_BOX
    global SPOT_TRACK_RADIUS, SPOT_GONE_CONFIRM_TICKS
    global SPOT_SETTLE_MS, SPOT_ACQUIRE_TIMEOUT_MS, SPOT_POLL_MS, SPOT_TIMEOUT_MS
    global lastSearchTipAt, LOG_FILE

    if (!RequireOsrsWindowActive()) {
        LogLine(LOG_FILE, "mine: OSRS window not focused - paused")
        return GoToPhase(taskRunner, "mine")
    }

    ; Only searches for a vein to CLICK while we're not already
    ; attached to one - see the header comment for why this matters.
    if (!FindImageCenter(MINING_AREA_X1, MINING_AREA_Y1, MINING_AREA_X2, MINING_AREA_Y2, SPOT_IMG, SPOT_IMG_W, SPOT_IMG_H, &cx, &cy, SPOT_IMG_OPTIONS)) {
        ; Failing to find ANYTHING here is silent by design (it's the
        ; normal "nothing ready yet" tick) - but if it keeps failing
        ; for several seconds straight, surface that instead of going
        ; silently idle until PHASE_TIMEOUT_MINE eventually stops the
        ; bot.
        if (A_TickCount - lastSearchTipAt > 4000) {
            ShowTipFor("No minable vein found in the calibrated area - still searching...", 1500)
            LogLine(LOG_FILE, "mine: no vein found in area, still searching")
            lastSearchTipAt := A_TickCount
        }
        return GoToPhase(taskRunner, "mine")   ; nothing there yet - try again next tick
    }

    LogLine(LOG_FILE, "mine: found vein at " cx "," cy " - clicking")
    HumanClick(cx, cy, SPOT_CLICK_BOX, SPOT_CLICK_BOX, runMode)
    ResetPhaseTimer(taskRunner)

    ; Brief settle so the click-marker animation itself isn't
    ; immediately mistaken for the vein disappearing.
    Sleep(JitterDelay(SPOT_SETTLE_MS))

    ; ACQUIRE STAGE: if we clicked a vein that isn't adjacent, the
    ; camera can drift over the course of the walk - potentially well
    ; outside a small box centered on the ORIGINAL click point.
    ; Searching only that small box from the very first poll means it
    ; might never get a single hit before giving up. So first, search
    ; the WHOLE calibrated area (not a small box) repeatedly until the
    ; vein is seen even once post-click - this tolerates any amount of
    ; drift, bounded by SPOT_ACQUIRE_TIMEOUT_MS. Once acquired, cx/cy
    ; reflects a CURRENT real position, and we hand off to the tight
    ; small-box tracking loop below.
    acquired := false
    acquireDeadline := A_TickCount + SPOT_ACQUIRE_TIMEOUT_MS
    loop {
        if (FindImageCenter(MINING_AREA_X1, MINING_AREA_Y1, MINING_AREA_X2, MINING_AREA_Y2, SPOT_IMG, SPOT_IMG_W, SPOT_IMG_H, &cx, &cy, SPOT_IMG_OPTIONS)) {
            acquired := true
            break
        }
        if (A_TickCount >= acquireDeadline)
            break   ; never reappeared anywhere in the area - treat as already gone below
        Sleep(SPOT_POLL_MS)
    }
    if (!acquired) {
        LogLine(LOG_FILE, "mine: never saw the vein again after clicking (acquire timeout) -> re-search")
        return GoToPhase(taskRunner, "mine")   ; nothing to track - go back and search fresh
    }
    LogLine(LOG_FILE, "mine: acquired at " cx "," cy " - tracking")

    ; TRACK STAGE: now that we have a CURRENT real position, this loop
    ; RE-CENTERS a small box on the vein's position every single poll -
    ; each successful find updates cx/cy to wherever it was just found,
    ; so the box slides along with however much the camera still pans
    ; between polls. Only when it can't be found ANYWHERE near its last
    ; known position for several consecutive polls in a row do we
    ; conclude it actually left (depleted or moved on) - scoped to a
    ; small box (not the whole area) specifically so a different,
    ; unrelated vein appearing elsewhere is never mistaken for ours
    ; still being here.
    missingStreak := 0
    deadline := A_TickCount + SPOT_TIMEOUT_MS
    loop {
        if (FindImageCenter(cx - SPOT_TRACK_RADIUS, cy - SPOT_TRACK_RADIUS, cx + SPOT_TRACK_RADIUS, cy + SPOT_TRACK_RADIUS, SPOT_IMG, SPOT_IMG_W, SPOT_IMG_H, &ncx, &ncy, SPOT_IMG_OPTIONS)) {
            cx := ncx
            cy := ncy
            missingStreak := 0
        } else {
            missingStreak += 1
            if (missingStreak >= SPOT_GONE_CONFIRM_TICKS) {
                ; The vein leaving (after we successfully mined it for
                ; a while) IS real progress, just like the initial
                ; click - reset here too, so the very next tick doesn't
                ; immediately see the phase as timed-out.
                ResetPhaseTimer(taskRunner)
                LogLine(LOG_FILE, "mine: vein confirmed gone after " missingStreak " misses (last seen near " cx "," cy ") -> re-search")
                return GoToPhase(taskRunner, "mine")   ; depleted/moved - loop will search the area again
            }
        }

        if (A_TickCount >= deadline) {
            StopAndLog(taskRunner, "Mining timed out - vein never left")
            return GoToPhase(taskRunner, "mine")
        }
        Sleep(SPOT_POLL_MS)
    }
}
