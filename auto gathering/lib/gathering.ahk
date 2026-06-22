; ============================================================
;  gathering.ahk - THE ACTUAL MINING/GATHERING CYCLE
; ------------------------------------------------------------
;  ELI5: This is the "recipe" for one full gathering cycle,
;  broken into small named steps (see STEP_ORDER in state.ahk):
;
;    CheckInventory -> FindAndClickSpot -> WaitForRespawn
;        -> PlayToBank -> Deposit -> PlayBackToMine -> (loop)
;
;  Each step is its OWN function so:
;    1. You can read it top to bottom like a recipe card.
;    2. The GUI can jump straight to any one step for debugging
;       (e.g. "just test Deposit" without re-walking every time).
;    3. Future bots (fishing, cooking) can replace just the steps
;       that differ and still call RunGatheringCycle() for the
;       loop/step-jump machinery.
; ============================================================

#Requires AutoHotkey v2.0

; --------------------------------------------------------------
; RunGatheringCycle: the dispatcher. Starts at State["startStep"]
; (defaults to the very first step, but the GUI can set this to
; jump in anywhere) and walks forward through STEP_ORDER calling
; each step's function until told to stop or a step decides to
; jump elsewhere (e.g. WaitForRespawn jumping back to
; FindAndClickSpot once something respawns).
; --------------------------------------------------------------
RunGatheringCycle() {
    global State, STEP_ORDER, STEP_FUNCS

    startIndex := StepIndexOf(State["startStep"])
    if (startIndex = 0)
        startIndex := 1

    i := startIndex
    while (State["running"] && !State["paused"]) {
        if (CheckPanicCorner()) {
            StopMining("Panic corner triggered")
            return
        }

        stepName := STEP_ORDER[i]
        State["currentStepName"] := stepName
        State["statusText"] := "Step: " stepName

        nextStepName := STEP_FUNCS[stepName].Call()

        if (!State["running"])
            return

        if (nextStepName != "") {
            ; A step asked to jump somewhere specific (e.g. retry
            ; the same step, or skip ahead) instead of just moving
            ; to the next one in line.
            i := StepIndexOf(nextStepName)
            if (i = 0)
                i := 1
            continue
        }

        i += 1
        if (i > STEP_ORDER.Length)
            i := 1  ; cycle back to the top - mining is a loop, not a one-shot

        Sleep(State["loopInterval"])
    }
}

; --------------------------------------------------------------
; StepCheckInventory: if the inventory looks full, jump straight
; to "PlayToBank" (skipping mining this tick). Otherwise return
; "" so the dispatcher just moves on to the next normal step.
; --------------------------------------------------------------
StepCheckInventory() {
    global State
    if (IsInventoryFull()) {
        ResetTargetTracking()
        State["statusText"] := "Inventory full - heading to bank"
        return "PlayToBank"
    }
    return ""
}

; --------------------------------------------------------------
; StepFindAndClickSpot: the heart of the old MainLoop(). Looks
; through every enabled spot in priority order (the order they
; appear in State["spots"]), keeping the existing "target lock"
; behavior so the bot doesn't flicker between two ready spots.
;
; If NOTHING is ready, jumps to WaitForRespawn instead of
; spinning the CPU checking colors 10x a second for no reason.
; --------------------------------------------------------------
StepFindAndClickSpot() {
    global State

    ; --- keep current target locked for a bit if it's still ready ---
    idx := State["currentTargetIndex"]
    if (idx > 0 && idx <= State["spots"].Length) {
        spot := State["spots"][idx]
        if (spot["enabled"] && IsSpotReady(spot, 20)) {
            ResetMissingStreak(idx)
            return "FindAndClickSpot"  ; stay here, keep mining this same spot
        }

        IncrementMissingStreak(idx)
        stillLocked := (A_TickCount < State["targetLockUntil"])
        notEnoughMisses := (GetMissingStreak(idx) < 2)
        if (stillLocked || notEnoughMisses)
            return "FindAndClickSpot"  ; give it a couple more ticks before giving up

        State["currentTargetIndex"] := 0  ; give up on this target, look for another below
    }

    ; --- scan all enabled spots in priority order, take the first ready one ---
    for i, spot in State["spots"] {
        if (!spot["enabled"])
            continue
        if (IsSpotReady(spot, 20)) {
            State["currentTargetIndex"] := i
            State["targetLockUntil"] := A_TickCount + 1000
            ResetMissingStreak(i)
            State["statusText"] := "Gathering: " spot["name"]
            DoClick(spot["x"], spot["y"])
            return "FindAndClickSpot"
        }
    }

    ; --- nothing ready anywhere - stop spinning, go wait instead ---
    State["statusText"] := "All spots empty - waiting for respawn"
    return "WaitForRespawn"
}

; --------------------------------------------------------------
; StepWaitForRespawn: blocking-but-stoppable wait loop. Checks
; spots every 100ms until one becomes ready, or the bot is
; stopped. This matches the old WaitForEitherOreTolerance, just
; generalized from exactly-2-spots to however many are enabled.
; --------------------------------------------------------------
StepWaitForRespawn() {
    global State
    loop {
        if (!State["running"])
            return ""
        if (IsInventoryFull())
            return "PlayToBank"

        for i, spot in State["spots"] {
            if (spot["enabled"] && IsSpotReady(spot, 20))
                return "FindAndClickSpot"
        }
        Sleep(100)
    }
}

; --------------------------------------------------------------
; StepPlayToBank: walks the recorded "toBank" route. If it fails
; (stopped by user, or timed out as stuck), stop the whole bot
; rather than silently continuing in a wrong location.
; --------------------------------------------------------------
StepPlayToBank() {
    global State
    if (!PlayPath("toBank")) {
        if (State["running"])
            StopMining("Stopped during TO-BANK path")
        return ""
    }
    return "Deposit"
}

; --------------------------------------------------------------
; StepDeposit: clicks the inventory slot and right-click-deposits
; everything. This is the same simple approach as the original
; script - it assumes a "deposit all"-style right click menu.
; Kept as its own step specifically so you can debug/replay JUST
; this part (set "Run from here" = Deposit in the GUI) without
; re-walking the whole path every test.
; --------------------------------------------------------------
StepDeposit() {
    global State
    DoAction(State["invX"], State["invY"], "click")
    SleepJittered(500)
    DoAction(State["invX"], State["invY"], "rightClick")
    SleepJittered(500)
    DoAction(State["invX"], State["invY"], "click")
    SleepJittered(500)
    return "PlayBackToMine"
}

; --------------------------------------------------------------
; StepPlayBackToMine: walks the recorded "backToMine" route, then
; resumes normal gathering on success.
; --------------------------------------------------------------
StepPlayBackToMine() {
    global State
    if (!PlayPath("backToMine")) {
        if (State["running"])
            StopMining("Stopped during BACK-TO-MINE path")
        return ""
    }
    ResetTargetTracking()
    State["statusText"] := "Back at gathering spot - resuming"
    return "CheckInventory"
}

; --------------------------------------------------------------
; Small helpers for the per-spot "missing streak" tracking, which
; lives in a Map keyed by spot index (State["missingStreak"]).
; Pulled out so StepFindAndClickSpot above stays readable.
; --------------------------------------------------------------
GetMissingStreak(idx) {
    global State
    return State["missingStreak"].Has(idx) ? State["missingStreak"][idx] : 0
}
IncrementMissingStreak(idx) {
    global State
    State["missingStreak"][idx] := GetMissingStreak(idx) + 1
}
ResetMissingStreak(idx) {
    global State
    State["missingStreak"][idx] := 0
}

; --------------------------------------------------------------
; ResetTargetTracking: clears all "which spot am I locked onto"
; state. Called whenever we start a fresh cycle (after banking,
; or when the bot starts) so old lock state doesn't leak across.
; --------------------------------------------------------------
ResetTargetTracking() {
    global State
    State["currentTargetIndex"] := 0
    State["targetLockUntil"] := 0
    State["missingStreak"] := Map()
}

; --------------------------------------------------------------
; RegisterGatheringSteps: wires step names to their functions.
; Must run after all Step* functions above are defined - called
; once from main.ahk during startup.
; --------------------------------------------------------------
RegisterGatheringSteps() {
    global STEP_FUNCS
    STEP_FUNCS["CheckInventory"]    := StepCheckInventory
    STEP_FUNCS["FindAndClickSpot"]  := StepFindAndClickSpot
    STEP_FUNCS["WaitForRespawn"]    := StepWaitForRespawn
    STEP_FUNCS["PlayToBank"]        := StepPlayToBank
    STEP_FUNCS["Deposit"]           := StepDeposit
    STEP_FUNCS["PlayBackToMine"]    := StepPlayBackToMine
}

; --------------------------------------------------------------
; StopMining: emergency/normal stop. Clears running state and
; any in-progress recording, and tells the GUI/tooltip why.
; --------------------------------------------------------------
StopMining(reason := "Stopped") {
    global State
    State["running"] := false
    State["paused"] := false
    ResetTargetTracking()

    if (State["recordingActive"]) {
        State["recordingActive"] := false
        Hotkey("~LButton", RecordPathClick, "Off")
    }

    State["statusText"] := reason
}

; --------------------------------------------------------------
; ValidateSetup: checks everything required is calibrated before
; allowing Start. Returns true if ready, otherwise shows what's
; missing and returns false.
; --------------------------------------------------------------
ValidateSetup() {
    global State
    msg := ""

    readySpots := 0
    for spot in State["spots"] {
        if (spot["enabled"])
            readySpots += 1
    }
    if (readySpots = 0)
        msg .= "- At least 1 enabled gathering spot (add with F1)`n"
    if (State["invDefaultColor"] = -1)
        msg .= "- Inventory slot (F3)`n"
    if (State["paths"]["toBank"].Length = 0)
        msg .= "- TO-BANK path (F4)`n"
    if (State["paths"]["backToMine"].Length = 0)
        msg .= "- BACK-TO-MINE path (F5)`n"

    if (msg != "") {
        MsgBox("Missing setup:`n" msg, "Setup incomplete", 48)
        return false
    }
    return true
}
