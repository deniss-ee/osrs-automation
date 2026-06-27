; ============================================================
;  auto-fighter.ahk
;  NPC melee/combat bot, built entirely from the shared lib\
;  functions - same library auto-miner.ahk, auto-smelter.ahk,
;  auto-fisher.ahk, auto-smith.ahk and auto-motherlode.ahk use.
;
;  THE PROBLEM: NPCs are highlighted with a #FF00FF outline while
;  hovered/targetable, but finding the outline's "center" to click
;  isn't reliable - it's a ring around the NPC's sprite, not a
;  filled shape, so there's no one fixed point to search for. This
;  bot instead finds whichever outline pixel is CLOSEST to the
;  character (FindNearestPixelColor, lib\Colors.ahk) and clicks a
;  point just past it, away from the character - i.e. just inside
;  the NPC's body rather than on the bare edge pixel between it and
;  the background.
;
;  COMBAT STATE: a single fixed pixel (COMBAT_INDICATOR_X/Y) turns
;  one color while actively in combat and a different color once
;  the target is dead. Both colors and the coordinate are given
;  directly (not per-NPC calibrated), since they don't depend on
;  which NPC or where it is.
;
;  EXPECTED STARTING STATE: standing where the target NPCs spawn,
;  with the calibrated combat area covering the screen region they
;  can appear in.
;
;  CYCLE:
;    1. Find the #FF00FF outline pixel closest to the calibrated
;       character-center point, within the calibrated combat area.
;    2. Click just past it (NPC_CLICK_OFFSET_PX), away from the
;       character along whichever axis (x or y) the outline pixel
;       is mainly offset on - ATTACK_CLICK_COUNT clicks,
;       ATTACK_CLICK_DELAY_MS apart.
;    3. Wait for the combat indicator to show COMBAT_START_COLOR
;       (confirms the attack actually landed and combat began).
;    4. Wait for the same pixel to change to COMBAT_DEAD_COLOR
;       (confirms the target died).
;    5. Repeat from step 1.
;  If step 3 or step 4 times out (e.g. the click missed, or the NPC
;  moved/died/was already taken by someone else), the bot just
;  re-scans from step 1 instead of getting stuck.
;
;  HOTKEYS
;    F1   = mark combat-area corner 1 (hover near one corner of the
;           area NPCs can appear in, press F1)
;    F2   = mark combat-area corner 2 (hover the opposite corner,
;           press F2 - order doesn't matter, corners are sorted
;           automatically)
;    F3   = save the character-center point (hover the character's
;           center on screen, press F3)
;    F4   = start the bot
;    F5   = stop the bot
;    F6   = clear saved config and reload the script
;
;  DEBUG LOGGING: every click/combat-state transition is timestamped
;  and appended to LOG_FILE (logs\auto-fighter-debug.log) via
;  lib\Log.ahk.
;
;  Config auto-saves to config\auto-fighter.ini next to this file.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

#Include ..\lib\Tooltip.ahk
#Include ..\lib\Colors.ahk
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
global CONFIG := A_ScriptDir "\..\config\auto-fighter.ini"

; ---------- Debug log ----------
global LOG_FILE := A_ScriptDir "\..\logs\auto-fighter-debug.log"

; Stops the runner AND records why in the debug log, so a stop that
; happens off-screen (or whose tooltip you miss) is never a mystery.
StopAndLog(taskRunner, reason) {
    global LOG_FILE
    LogLine(LOG_FILE, "STOPPED: " reason)
    StopTaskRunner(taskRunner, reason)
}

; ---------- Humanization: off by default ----------
; Click.ahk defaults ENABLE_HUMANIZATION to false (exact calibrated
; pixel, exact delays). Even when enabled it's hard-capped at
; +/-2px / +/-100ms. Restated here so it's explicit per script.
global ENABLE_HUMANIZATION := false

; ---------- Tunables: NPC outline detection ----------
global COLOR_TOLERANCE := 30
; The in-game combat-target highlight is a fixed, known magenta -
; not something that needs per-NPC calibration.
global NPC_OUTLINE_COLOR := 0xFF00FF
global NPC_SEARCH_STEP_PX := 20   ; FindNearestPixelColor's box-growth step - smaller = more precise "closest" pixel but slower; this is plenty precise for picking a click direction
global NPC_SCAN_POLL_MS := 20     ; how often FightPhase re-scans for an outline when nothing is found yet - deliberately tight (not the TaskRunner's own 150ms tick) so a brief outline doesn't disappear again before the next look

; ---------- Tunables: attack click ----------
global NPC_CLICK_OFFSET_PX := 5   ; how far past the found outline pixel (away from the character, along whichever axis it's mainly offset on) to click - lands inside the NPC's body instead of on the bare edge pixel between it and the background
global ATTACK_CLICK_COUNT := 1
global ATTACK_CLICK_DELAY_MS := 10
global ATTACK_CLICK_BOX := 0      ; 0 = land on the exact computed pixel every click; HumanClick's own jitter (when ENABLE_HUMANIZATION) still applies on top, capped at +/-2px
global ATTACK_SETTLE_MS := 200    ; brief pause after clicking, before polling for the combat-start indicator

; ---------- Tunables: combat indicator ----------
; One fixed pixel that's a known color while actively in combat and
; a different known color once the target is dead - given directly,
; not per-NPC calibrated.
global COMBAT_INDICATOR_X := 1657
global COMBAT_INDICATOR_Y := 1232
global COMBAT_START_COLOR := 0x068C37
global COMBAT_DEAD_COLOR := 0x651312
global COMBAT_START_TIMEOUT_MS := 3000     ; give up and re-scan if combat never visibly starts after a click (click missed, or the NPC moved/died/was taken first)
global COMBAT_KILL_TIMEOUT_MS := 120000    ; hard safety-net cap on a single fight
global COMBAT_CONFIRM_TICKS := 2           ; require this many consecutive polls before trusting either color transition - filters a single transient glitch
global COMBAT_POLL_MS := 100

global PHASE_TIMEOUT_FIGHT := 150000   ; comfortably above COMBAT_KILL_TIMEOUT_MS - resets on every click/confirmed transition (ResetPhaseTimer), so a long real fight never trips this on its own; only true inaction (no NPCs appearing at all) for this long stops the bot

; ---------- Calibrated values (loaded from INI, or 0 if unset) ----------
global COMBAT_AREA_X1 := 0, COMBAT_AREA_Y1 := 0, COMBAT_AREA_X2 := 0, COMBAT_AREA_Y2 := 0
global CHARACTER_CENTER_X := 0, CHARACTER_CENTER_Y := 0

; ---------- Library objects ----------
global runner := NewTaskRunner(150)

; ---------- Init ----------
LoadConfig()

; ============================================================
;  CALIBRATION HOTKEYS
; ============================================================

global combatAreaCorner1 := ""

F1:: {
    global combatAreaCorner1
    MouseGetPos(&mx, &my)
    combatAreaCorner1 := {x: mx, y: my}
    ShowTipFor("Combat area corner 1 set at " mx ", " my " - now hover the opposite corner and press F2", 2000)
}

F2:: {
    global combatAreaCorner1, COMBAT_AREA_X1, COMBAT_AREA_Y1, COMBAT_AREA_X2, COMBAT_AREA_Y2
    if (combatAreaCorner1 = "") {
        ShowTipFor("Press F1 first to set the other corner", 1500)
        return
    }
    MouseGetPos(&mx, &my)
    x1 := Min(combatAreaCorner1.x, mx)
    y1 := Min(combatAreaCorner1.y, my)
    x2 := Max(combatAreaCorner1.x, mx)
    y2 := Max(combatAreaCorner1.y, my)
    COMBAT_AREA_X1 := x1, COMBAT_AREA_Y1 := y1, COMBAT_AREA_X2 := x2, COMBAT_AREA_Y2 := y2
    SaveRegion(CONFIG, "CombatArea", x1, y1, x2, y2)
    ShowTipFor("Combat area saved: (" x1 ", " y1 ") to (" x2 ", " y2 ")", 2000)
}

F3:: {
    global CHARACTER_CENTER_X, CHARACTER_CENTER_Y
    MouseGetPos(&mx, &my)
    CHARACTER_CENTER_X := mx
    CHARACTER_CENTER_Y := my
    SaveCoord(CONFIG, "Character", "center", mx, my)
    ShowTipFor("Character center saved at " mx ", " my, 1500)
}

F4:: StartBot()
F5:: StopAndLog(runner, "Stopped (F5)")

F6:: {
    if FileExist(CONFIG)
        FileDelete(CONFIG)
    Reload()
}

; ============================================================
;  CONFIG LOAD
; ============================================================

LoadConfig() {
    global COMBAT_AREA_X1, COMBAT_AREA_Y1, COMBAT_AREA_X2, COMBAT_AREA_Y2
    global CHARACTER_CENTER_X, CHARACTER_CENTER_Y
    global COLOR_TOLERANCE

    ; Curated tunable - overwrites the hardcoded default above from
    ; the .ini if present, so it can be tweaked without editing this
    ; file (e.g. from the control panel). This script has no
    ; runMode/banking, so it's the only curated value here.
    COLOR_TOLERANCE := LoadNumber(CONFIG, "Tunables", "colorTolerance", COLOR_TOLERANCE)

    combatRegion := LoadRegion(CONFIG, "CombatArea")
    COMBAT_AREA_X1 := combatRegion[1]
    COMBAT_AREA_Y1 := combatRegion[2]
    COMBAT_AREA_X2 := combatRegion[3]
    COMBAT_AREA_Y2 := combatRegion[4]

    center := LoadCoord(CONFIG, "Character", "center")
    CHARACTER_CENTER_X := center[1]
    CHARACTER_CENTER_Y := center[2]
}

; ============================================================
;  SETUP VALIDATION
; ============================================================

ValidateSetup() {
    global COMBAT_AREA_X1, COMBAT_AREA_Y1, COMBAT_AREA_X2, COMBAT_AREA_Y2
    global CHARACTER_CENTER_X, CHARACTER_CENTER_Y
    v := NewValidator()
    RequireRegion(v, "F1/F2 - combat area", COMBAT_AREA_X1, COMBAT_AREA_Y1, COMBAT_AREA_X2, COMBAT_AREA_Y2)
    RequireCoord(v, "F3 - character center", CHARACTER_CENTER_X, CHARACTER_CENTER_Y)
    return ShowValidationErrors(v)
}

StartBot() {
    global runner, LOG_FILE, PHASE_TIMEOUT_FIGHT
    if (!ValidateSetup())
        return

    AddPhase(runner, "fight", FightPhase, PHASE_TIMEOUT_FIGHT)
    StartTaskRunner(runner, "fight")
    ShowTipFor("Bot started", 1000)
    LogLine(LOG_FILE, "===== Bot started =====")
}

; ============================================================
;  PHASES
; ============================================================

; Finds the NPC outline pixel closest to the character, clicks just
; past it, then blocks on confirming combat actually started and
; then confirming the target died, before re-scanning for the next
; one. Runs its own tight inner loop instead of returning to the
; TaskRunner between scans - returning "fight" and waiting for the
; TaskRunner's own 150ms tick before checking again was slow enough
; that the outline could already be gone (NPC moved, flickered, or
; was taken by someone else) by the next look. Logs real events
; (clicks, confirmed transitions, timeouts) - not every idle "nothing
; found" poll, which would just spam the log every NPC_SCAN_POLL_MS.
FightPhase(taskRunner) {
    global COMBAT_AREA_X1, COMBAT_AREA_Y1, COMBAT_AREA_X2, COMBAT_AREA_Y2
    global CHARACTER_CENTER_X, CHARACTER_CENTER_Y
    global NPC_OUTLINE_COLOR, COLOR_TOLERANCE, NPC_SEARCH_STEP_PX, NPC_CLICK_OFFSET_PX, NPC_SCAN_POLL_MS
    global ATTACK_CLICK_COUNT, ATTACK_CLICK_DELAY_MS, ATTACK_CLICK_BOX, ATTACK_SETTLE_MS
    global COMBAT_INDICATOR_X, COMBAT_INDICATOR_Y, COMBAT_START_COLOR, COMBAT_DEAD_COLOR
    global COMBAT_START_TIMEOUT_MS, COMBAT_KILL_TIMEOUT_MS, COMBAT_CONFIRM_TICKS, COMBAT_POLL_MS
    global LOG_FILE

    loop {
        if (!taskRunner["running"])
            return GoToPhase(taskRunner, "fight")

        if (!RequireOsrsWindowActive())
            return GoToPhase(taskRunner, "fight")

        if (!FindNearestPixelColor(COMBAT_AREA_X1, COMBAT_AREA_Y1, COMBAT_AREA_X2, COMBAT_AREA_Y2,
                CHARACTER_CENTER_X, CHARACTER_CENTER_Y, NPC_OUTLINE_COLOR, COLOR_TOLERANCE,
                &fx, &fy, NPC_SEARCH_STEP_PX)) {
            Sleep(NPC_SCAN_POLL_MS)   ; tight re-scan, not the full 150ms TaskRunner tick
            continue
        }

        ; Single-axis offset, away from the character, past the outline
        ; and into the NPC's body - the outline itself is the edge
        ; between the NPC and the background, not a reliable click
        ; target. Whichever axis the found pixel is mainly offset on
        ; (the bigger of dx/dy) decides whether this nudges x or y.
        dx := fx - CHARACTER_CENTER_X
        dy := fy - CHARACTER_CENTER_Y
        if (Abs(dx) >= Abs(dy)) {
            tx := fx + (dx < 0 ? -NPC_CLICK_OFFSET_PX : NPC_CLICK_OFFSET_PX)
            ty := fy
        } else {
            tx := fx
            ty := fy + (dy < 0 ? -NPC_CLICK_OFFSET_PX : NPC_CLICK_OFFSET_PX)
        }

        loop ATTACK_CLICK_COUNT {
            HumanClick(tx, ty, ATTACK_CLICK_BOX, ATTACK_CLICK_BOX)
            if (A_Index < ATTACK_CLICK_COUNT)
                Sleep(ATTACK_CLICK_DELAY_MS)
        }
        ResetPhaseTimer(taskRunner)
        LogLine(LOG_FILE, "fight: outline found at " fx "," fy " - clicked (" tx "," ty ")")
        Sleep(ATTACK_SETTLE_MS)

        if (!WaitForPixelColor(COMBAT_INDICATOR_X, COMBAT_INDICATOR_Y, COMBAT_START_COLOR, COLOR_TOLERANCE, COMBAT_START_TIMEOUT_MS, COMBAT_CONFIRM_TICKS, COMBAT_POLL_MS)) {
            LogLine(LOG_FILE, "fight: combat never started after click - retrying")
            continue
        }
        ResetPhaseTimer(taskRunner)
        LogLine(LOG_FILE, "fight: combat started - waiting for kill")

        if (!WaitForPixelColor(COMBAT_INDICATOR_X, COMBAT_INDICATOR_Y, COMBAT_DEAD_COLOR, COLOR_TOLERANCE, COMBAT_KILL_TIMEOUT_MS, COMBAT_CONFIRM_TICKS, COMBAT_POLL_MS)) {
            LogLine(LOG_FILE, "fight: kill not confirmed within timeout - retrying")
            continue
        }
        ResetPhaseTimer(taskRunner)
        LogLine(LOG_FILE, "fight: target confirmed dead - looking for next target")
        ; loop back to top immediately - see header comment above
    }
}
