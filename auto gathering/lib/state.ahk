; ============================================================
;  state.ahk - THE BOT'S "BRAIN MEMORY"
; ------------------------------------------------------------
;  ELI5: A computer program can't remember anything between
;  functions unless we put it "somewhere everyone can see it".
;  This file is that "somewhere". Every other file reads and
;  writes to the SAME Map() called `State`, so e.g. gui.ahk can
;  show what main loop is doing, and failsafe.ahk can stop it.
;
;  We use ONE big Map instead of 30 separate "global x := 0"
;  lines (like the old script had) because:
;    1. It's easier to inspect/debug (just look at one object).
;    2. Adding a new piece of state later = one line, not three
;       (declare global, declare default, wire into save/load).
;    3. Every #Include file can just say `global State` and get
;       the whole brain, instead of guessing which globals it
;       needs.
; ============================================================

#Requires AutoHotkey v2.0

; --------------------------------------------------------------
; State is the single source of truth for "what is the bot doing
; and what does it know right now". Think of it like a backpack
; everyone shares.
; --------------------------------------------------------------
global State := Map(
    ; ---- run control ----
    "running", false,        ; true while the main loop is allowed to act
    "paused", false,         ; true = loop exists but skips acting (soft pause)

    ; ---- gathering spots (replaces old ore1/ore2 hardcoding) ----
    ; Each spot is: Map("name", "Copper rock 1", "x", 100, "y", 200,
    ;                    "color", 0xABCDEF, "enabled", true)
    "spots", [],

    ; ---- per-spot runtime tracking (mirrors old target-lock logic,
    ; but indexed by spot number instead of hardcoded ore1/ore2) ----
    "currentTargetIndex", 0,     ; 0 = no target locked right now
    "targetLockUntil", 0,        ; A_TickCount timestamp; stay locked until this
    "missingStreak", Map(),      ; spotIndex -> consecutive "not ready" checks

    ; ---- inventory detection ----
    "invX", 0, "invY", 0, "invDefaultColor", -1,

    ; ---- stamina / run-energy orb calibration (see stamina.ahk) ----
    "orbX", 0, "orbY", 0,
    "orbEmptyColor", -1,      ; color sampled when energy bar is ~0%
    "orbFullColor", -1,       ; color sampled when energy bar is ~100%
    "minRunStamina", 30,      ; % - don't allow auto-run below this

    ; ---- recorded paths: { "toBank": [...], "backToMine": [...] } ----
    ; each step: Map("x",.., "y",.., "delay",.., "run", true/false, "label","")
    "paths", Map("toBank", [], "backToMine", []),
    "pathTailDelay", Map("toBank", 0, "backToMine", 0),

    ; ---- path recording session ----
    "recordingActive", false,
    "recordingPathName", "",
    "lastRecordTick", 0,
    "recordNextStepRun", false,  ; toggled by F9 while recording

    ; ---- step-based debug/resume system ----
    ; STEP_ORDER (below) lists step *names* in normal execution order.
    ; "startStep" lets you skip ahead - e.g. set it to "Deposit" to test
  ; only the deposit logic without re-mining/re-walking every time.
    "startStep", "CheckInventory",
    "currentStepName", "",

    ; ---- failsafe / antiban tunables ----
    "jitterPercent", 15,      ; +/- % randomness added to every Sleep()
    "pathTimeoutMultiplier", 3, ; abort a path if it runs 3x longer than expected
    "loopInterval", 150,      ; ms between gathering-cycle checks (same pace as old script)

    ; ---- misc ----
    "configPath", "",        ; full path to the active profile .ini, set by main.ahk
    "statusText", "Idle"      ; shown in the GUI + tooltip
)

; --------------------------------------------------------------
; STEP_ORDER: the normal "top to bottom" order of the gathering
; cycle. STEP_FUNCS maps each name to the actual function to call.
; main.ahk fills STEP_FUNCS in once all the step functions exist
; (paths.ahk / gathering logic), because AHK needs the functions
; defined before we can take a reference to them.
;
; ELI5: imagine a recipe card with steps written on sticky notes.
; STEP_ORDER is the order the sticky notes go in. STEP_FUNCS is
; "which actual instruction page does this sticky note point to".
; The GUI lets you start from ANY sticky note instead of always
; starting from note #1 - great for testing just one part.
; --------------------------------------------------------------
global STEP_ORDER := [
    "CheckInventory",
    "FindAndClickSpot",
    "WaitForRespawn",
    "PlayToBank",
    "Deposit",
    "PlayBackToMine"
]

global STEP_FUNCS := Map()

; --------------------------------------------------------------
; Small helper: find the array index (1-based, AHK arrays start
; at 1, not 0!) of a step name inside STEP_ORDER. Returns 0 if not
; found, same convention AHK uses elsewhere for "not found".
; --------------------------------------------------------------
StepIndexOf(stepName) {
    global STEP_ORDER
    for i, name in STEP_ORDER {
        if (name = stepName)
            return i
    }
    return 0
}
