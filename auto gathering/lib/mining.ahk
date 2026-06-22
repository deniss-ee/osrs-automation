; ============================================================
;  mining.ahk - THE MAIN MINING + BANKING LOGIC
; ------------------------------------------------------------
;  ELI5: This is the "brain" of the bot - it decides what to do
;  every tick: is the inventory full? is ore #1 or #2 ready to
;  click? are both empty, so we should just wait? It also handles
;  the full bank trip (walk there, deposit, walk back).
; ============================================================

#Requires AutoHotkey v2.0

; --------------------------------------------------------------
; ValidateSetup: checks that F1-F5 have all been done before
; letting you press F6 to start. Shows exactly what's missing
; instead of just silently failing to start.
; --------------------------------------------------------------
ValidateSetup() {
    global ore1FullColor, ore2FullColor, invDefaultColor
    global toBankPath, backToMinePath

    msg := ""
    if (ore1FullColor = -1)
        msg .= "F1 - ore #1 position + color`n"
    if (ore2FullColor = -1)
        msg .= "F2 - ore #2 position + color`n"
    if (invDefaultColor = -1)
        msg .= "F3 - inventory slot`n"
    if (toBankPath.Length = 0)
        msg .= "F4 - record TO-BANK path`n"
    if (backToMinePath.Length = 0)
        msg .= "F5 - record BACK-TO-MINE path`n"

    if (msg != "") {
        MsgBox("Missing setup:`n" msg, "Setup incomplete", 48)
        return false
    }

    return true
}

; --------------------------------------------------------------
; MainLoop: runs every 150ms (started by F6) while `running` is
; true. Order of checks matters:
;   1. Inventory full?  -> go bank immediately, skip everything else.
;   2. Currently locked onto a target ore that's still ready?
;      -> keep mining it, don't even consider switching.
;   3. Ore #1 ready?     -> mine it (ore #1 always wins over #2).
;   4. Ore #2 ready?     -> mine it.
;   5. Both empty?       -> wait (blocking) until one respawns.
;
;  The "target lock" (steps 2) + "missing streak" combo exists so
;  a single flickering pixel read (lighting glitch, etc.) doesn't
;  make the bot instantly abandon an ore that's actually still
;  there - it has to miss twice AND be past the 1-second lock
;  before giving up on the current target.
; --------------------------------------------------------------
MainLoop() {
    global running, waitingForOre, currentTarget, targetLockUntil
    global ore1MissingStreak, ore2MissingStreak
    global ore1X, ore1Y, ore1FullColor
    global ore2X, ore2Y, ore2FullColor
    global COLOR_TOLERANCE, TARGET_LOCK_MS, MISSING_CONFIRM_TICKS

    if (!running)
        return

    ; Step 1: inventory full check first.
    if (IsInventoryFull()) {
        waitingForOre := false
        currentTarget := 0
        targetLockUntil := 0
        ore1MissingStreak := 0
        ore2MissingStreak := 0
        ShowTip("Inventory full - going to bank")
        SetTimer(MainLoop, 0)
        GoBankAndReturn()
        return
    }

    ore1Ready := ColorClose(PixelGetColor(ore1X, ore1Y, "RGB"), ore1FullColor, COLOR_TOLERANCE)
    ore2Ready := ColorClose(PixelGetColor(ore2X, ore2Y, "RGB"), ore2FullColor, COLOR_TOLERANCE)

    ; Keep current target stable for a short time to prevent instant flip-flops.
    if (currentTarget = 1) {
        if (ore1Ready) {
            ore1MissingStreak := 0
            waitingForOre := false
            return
        }
        ore1MissingStreak += 1
        if (A_TickCount < targetLockUntil || ore1MissingStreak < MISSING_CONFIRM_TICKS)
            return
        currentTarget := 0
    }

    if (currentTarget = 2) {
        if (ore2Ready) {
            ore2MissingStreak := 0
            waitingForOre := false
            return
        }
        ore2MissingStreak += 1
        if (A_TickCount < targetLockUntil || ore2MissingStreak < MISSING_CONFIRM_TICKS)
            return
        currentTarget := 0
    }

    ; Step 2/3: prioritize ore #1, then fallback to ore #2.
    if (ore1Ready) {
        waitingForOre := false
        currentTarget := 1
        ore1MissingStreak := 0
        ore2MissingStreak := 0
        targetLockUntil := A_TickCount + TARGET_LOCK_MS
        ShowTip("Mining ore #1")
        DoClick(ore1X, ore1Y)
        SetTimer(HideTip, -1000)
        return
    }

    if (ore2Ready) {
        waitingForOre := false
        currentTarget := 2
        ore1MissingStreak := 0
        ore2MissingStreak := 0
        targetLockUntil := A_TickCount + TARGET_LOCK_MS
        ShowTip("Mining ore #2")
        DoClick(ore2X, ore2Y)
        SetTimer(HideTip, -1000)
        return
    }

    ; If both empty, wait for whichever respawns first using the same tolerance-wait style.
    if (!waitingForOre) {
        waitingForOre := true
        currentTarget := 0
        ShowTip("Both ores empty - waiting respawn")
        SetTimer(MainLoop, 0)

        target := WaitForEitherOreTolerance(ore1X, ore1Y, ore1FullColor, ore2X, ore2Y, ore2FullColor, COLOR_TOLERANCE)
        if (!running)
            return

        if (IsInventoryFull()) {
            StopMining("Inventory full")
            return
        }

        if (target = 1) {
            currentTarget := 1
            waitingForOre := false
            ore1MissingStreak := 0
            ore2MissingStreak := 0
            targetLockUntil := A_TickCount + TARGET_LOCK_MS
            ShowTip("Ore #1 respawned - mining")
            DoClick(ore1X, ore1Y)
        } else if (target = 2) {
            currentTarget := 2
            waitingForOre := false
            ore1MissingStreak := 0
            ore2MissingStreak := 0
            targetLockUntil := A_TickCount + TARGET_LOCK_MS
            ShowTip("Ore #2 respawned - mining")
            DoClick(ore2X, ore2Y)
        }

        SetTimer(HideTip, -1200)
        SetTimer(MainLoop, LOOP_INTERVAL)
    }
}

; --------------------------------------------------------------
; GoBankAndReturn: the full bank trip. Blocking (doesn't return
; control until done) because there's nothing useful to do with
; the mining loop while you're busy walking/banking anyway.
;   1. Walk to bank (replay recorded path).
;   2. Click inventory slot, right-click, click again - this is
;      a "deposit all"-style interaction matching the bank menu.
;   3. Walk back (replay recorded path, faster if run mode is on).
;   4. Resume MainLoop.
; --------------------------------------------------------------
GoBankAndReturn() {
    global running, waitingForOre, currentTarget, targetLockUntil
    global ore1MissingStreak, ore2MissingStreak
    global invX, invY, enableRun

    if (!PlayPath("toBank")) {
        StopMining("Stopped during TO-BANK path")
        return
    }

    if (!running)
        return

    ; Deposit logic copied from woodcutter approach.
    MouseMove(invX, invY, 5)
    Sleep(500)
    Click("Right", invX, invY)
    Sleep(500)
    Click(invX, invY)
    Sleep(500)

    delayMult := enableRun ? 0.55 : 1.0
    if (!PlayPath("backToMine", delayMult, enableRun)) {
        StopMining("Stopped during BACK-TO-MINE path")
        return
    }

    if (!running)
        return

    waitingForOre := true
    currentTarget := 0
    targetLockUntil := 0
    ore1MissingStreak := 0
    ore2MissingStreak := 0
    ShowTip("Back at mine - resuming")
    SetTimer(HideTip, -1200)
    SetTimer(MainLoop, LOOP_INTERVAL)
}

; --------------------------------------------------------------
; WaitForEitherOreTolerance: blocking loop that checks both ore
; pixels every 100ms until one of them is ready (or you press
; Stop). Returns 1, 2, or 0 (0 = stopped, not "found nothing").
; --------------------------------------------------------------
WaitForEitherOreTolerance(x1, y1, color1, x2, y2, color2, tol) {
    global running
    loop {
        if (!running)
            return 0

        c1 := PixelGetColor(x1, y1, "RGB")
        if (ColorClose(c1, color1, tol))
            return 1

        c2 := PixelGetColor(x2, y2, "RGB")
        if (ColorClose(c2, color2, tol))
            return 2

        Sleep(100)
    }
}

; --------------------------------------------------------------
; StopMining: the emergency/normal stop, used by F7 and whenever
; something goes wrong mid-path. Resets all "what am I doing
; right now" state so a fresh F6 start doesn't carry over stale
; target-lock info from before.
; --------------------------------------------------------------
StopMining(reason := "Stopped") {
    global running, waitingForOre, currentTarget, recordingActive, targetLockUntil
    global ore1MissingStreak, ore2MissingStreak
    running := false
    waitingForOre := false
    currentTarget := 0
    targetLockUntil := 0
    ore1MissingStreak := 0
    ore2MissingStreak := 0

    if (recordingActive) {
        recordingActive := false
        Hotkey("~LButton", RecordPathClick, "Off")
    }

    SetTimer(MainLoop, 0)
    ShowTip(reason)
    SetTimer(HideTip, -1500)
}
