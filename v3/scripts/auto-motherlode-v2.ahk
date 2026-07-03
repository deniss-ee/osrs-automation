; ============================================================
; auto-motherlode-v2.ahk - v3 (Mining + Rapid Deposit/Banking Cycle)
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

#Include ..\lib\Tooltip.ahk
#Include ..\lib\Context.ahk
#Include ..\lib\Db.ahk
#Include ..\lib\Colors.ahk
#Include ..\lib\Images.ahk
#Include ..\lib\Safety.ahk
#Include ..\lib\Grid.ahk
#Include ..\lib\Click.ahk
#Include ..\lib\Slots.ahk
#Include ..\lib\Targeting.ahk
#Include ..\lib\Validate.ahk
#Include ..\lib\TaskRunner.ahk
#Include ..\lib\Log.ahk

CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")
CoordMode("ToolTip", "Screen")

global CONFIG := A_ScriptDir "\..\config\auto-motherlode-v2.ini"
global LOG_FILE := A_ScriptDir "\..\logs\auto-motherlode-v2-debug.log"
global ctx := NewBotContext(CONFIG)

EnsureDbVersion(CONFIG)
LoadConfig()

; ============================================================
; HOTKEYS
; ============================================================

F5:: StartBot()
F6:: StopAndLog(ctx["runner"], "Stopped (F6)")
F7:: ClearConfigAndReload()

; ============================================================
; BOT LIFECYCLE
; ============================================================

StartBot() {
    global ctx
    if (!ValidateSetup())
        return
    if (ctx["runner"] != "" && ctx["runner"]["running"])
        StopTaskRunner(ctx["runner"], "Restarting...")

    ctx["runner"] := NewTaskRunner(CtxTunable(ctx, "runnerTickMs", 50))
    AddPhase(ctx["runner"], "mine", MinePhase, CtxTunable(ctx, "phaseTimeoutMine", 180000))
    AddPhase(ctx["runner"], "clearRed", ClearRedPhase, CtxTunable(ctx, "phaseTimeoutBank", 30000))
    AddPhase(ctx["runner"], "clearYellow", ClearYellowPhase, CtxTunable(ctx, "phaseTimeoutBank", 30000))
    AddPhase(ctx["runner"], "withdrawSack", WithdrawSackPhase, CtxTunable(ctx, "phaseTimeoutBank", 30000))
    AddPhase(ctx["runner"], "depositBank", DepositBankPhase, CtxTunable(ctx, "phaseTimeoutBank", 30000))
    AddPhase(ctx["runner"], "returnMine1", ReturnMine1Phase, CtxTunable(ctx, "phaseTimeoutReturn", 45000))
    AddPhase(ctx["runner"], "returnMine2", ReturnMine2Phase, CtxTunable(ctx, "phaseTimeoutReturn", 45000))

    StartTaskRunner(ctx["runner"], "mine")
    TickTaskRunner(ctx["runner"])
    LogLine(LOG_FILE, "===== Motherlode Miner v2 started =====")
}

StopAndLog(runner, reason) {
    global LOG_FILE
    LogLine(LOG_FILE, "STOPPED: " reason)
    if (runner != "")
        StopTaskRunner(runner, reason)
}

ClearConfigAndReload() {
    global CONFIG
    if FileExist(CONFIG)
        FileDelete(CONFIG)
    Reload()
}

; ============================================================
; PHASES
; ============================================================

MinePhase(runner) {
    global ctx, LOG_FILE
    static lastLogTime := 0
    static lastClickTime := 0
    static prevVx := 0
    static prevVy := 0
    static stableTicks := 0
    static lockVx := 0
    static lockVy := 0
    static lockMissingTicks := 0

    if (!RequireOsrsWindowActive(ctx)) {
        if (A_TickCount - lastLogTime > CtxTunable(ctx, "mineLogIntervalMs", 2000)) {
            lastLogTime := A_TickCount
            LogLine(LOG_FILE, "MinePhase tick: PAUSED (RuneLite not focused)")
        }
        return GoToPhase(runner, "mine")
    }

    tol := CtxTunable(ctx, "colorTolerance", 20)
    indicatorSlot := CtxTunable(ctx, "indicatorSlot", 28)
    slotOccupied := IsSlotOccupied(indicatorSlot, tol)

    ; 1. Check if inventory is full
    if (slotOccupied) {
        lockVx := 0
        lockVy := 0
        lockMissingTicks := 0
        LogLine(LOG_FILE, "MinePhase: inventory full - transitioning to clearRed")
        ShowTipFor("Miner: inventory full - depositing", 1500)
        ctx["depositOccupiedBaseline"] := CountOccupiedSlots(tol)
        return GoToPhase(runner, "clearRed")
    }

    searchRegion := ctx["targetRegions"]["SearchRegion"]
    refPoint := ctx["returnWalkPoint"] ; Character center (960, 540)
    clickCooldown := CtxTunable(ctx, "clickCooldownMs", 3000)
    stableReclickEnabled := CtxTunable(ctx, "mineStableReclickEnabled", 0)
    stableReclickTicks := CtxTunable(ctx, "mineStableReclickTicks", 120)
    stableReclickCooldownMs := CtxTunable(ctx, "mineStableReclickCooldownMs", 6000)
    forceMineClick := ctx.Has("forceMineClick") ? ctx["forceMineClick"] : false
    mineBlockedUntil := ctx.Has("mineClickBlockedUntil") ? ctx["mineClickBlockedUntil"] : 0
    veinClickOffsetX := CtxTunable(ctx, "veinClickOffsetX", 15)
    veinClickOffsetY := CtxTunable(ctx, "veinClickOffsetY", 15)
    lockEnabled := CtxTunable(ctx, "mineTargetLockEnabled", 1)
    unlockMissing := CtxTunable(ctx, "mineUnlockMissingTicks", 2)
    lockCheckRadius := CtxTunable(ctx, "mineLockCheckRadiusPx", 3)
    lockMaxMs := CtxTunable(ctx, "mineLockMaxMs", 2500)
    lockTol := CtxTunable(ctx, "mineLockColorTolerance", 6)

    ; Keep mining the same clicked vein while it remains visible to avoid
    ; retarget switching (e.g., dark -> light green) mid-action.
    foundVein := false
    if (lockEnabled && lockVx != 0 && lockVy != 0) {
        lockStartAt := ctx.Has("mineLockStartAt") ? ctx["mineLockStartAt"] : 0
        lockExpired := (lockStartAt > 0) && (A_TickCount - lockStartAt > lockMaxMs)
        if (lockExpired) {
            lockVx := 0
            lockVy := 0
            lockMissingTicks := 0
        } else if (IsVeinStillActive(lockVx, lockVy, lockTol, lockCheckRadius)) {
            vx := lockVx
            vy := lockVy
            foundVein := true
            lockMissingTicks := 0
        } else {
            lockMissingTicks++
            if (lockMissingTicks >= unlockMissing) {
                lockVx := 0
                lockVy := 0
                lockMissingTicks := 0
            }
        }
    }
    if (!foundVein) {
        foundVein := FindNearestVein(searchRegion["x1"], searchRegion["y1"], searchRegion["x2"], searchRegion["y2"],
            refPoint["x"], refPoint["y"], tol, &vx, &vy, veinClickOffsetX, veinClickOffsetY)
    }

    if (foundVein) {
        ; Check if coordinate is stable (meaning we have arrived and are standing still mining)
        isStable := (Abs(vx - prevVx) <= 2 && Abs(vy - prevVy) <= 2)
        if (isStable) {
            stableTicks++
        } else {
            stableTicks := 0
        }

        prevVx := vx
        prevVy := vy

        dx := vx - refPoint["x"]
        dy := vy - refPoint["y"]
        dist := Sqrt(dx * dx + dy * dy)

        if (A_TickCount - lastLogTime > CtxTunable(ctx, "mineLogIntervalMs", 2000)) {
            lastLogTime := A_TickCount
            LogLine(LOG_FILE, "MinePhase tick: ACTIVE, nearestVeinDist=" dist "px stableTicks=" stableTicks)
        }

        ; During post-return grace, do not accumulate stable ticks (prevents false
        ; "already mining" state without an actual click).
        if (A_TickCount < mineBlockedUntil) {
            stableTicks := 0
            ShowTip("Miner: settling after return...")
            return GoToPhase(runner, "mine")
        }

        ; First mine tick after return handoff should force a real click once.
        if (forceMineClick && A_TickCount - lastClickTime > CtxTunable(ctx, "mineForceClickCooldownMs", 150)) {
            HumanClick(vx, vy, 0, 0, ctx["runMode"])
            lastClickTime := A_TickCount
            stableTicks := 0
            lockVx := vx
            lockVy := vy
            lockMissingTicks := 0
            ctx["mineLockStartAt"] := A_TickCount
            ctx["forceMineClick"] := false
            LogLine(LOG_FILE, "MinePhase: forced post-return click at [" vx "," vy "]")
            ShowTipFor("Miner: re-locking vein after return...", 1200)
            return GoToPhase(runner, "mine")
        }

        ; We consider ourselves "mining" if the vein coordinates have been stable for at least 3 ticks (150ms)
        if (stableTicks >= CtxTunable(ctx, "mineStableTicks", 3)) {
            if (stableReclickEnabled && stableTicks >= stableReclickTicks && (A_TickCount - lastClickTime > stableReclickCooldownMs)) {
                HumanClick(vx, vy, 0, 0, ctx["runMode"])
                lastClickTime := A_TickCount
                stableTicks := 0
                lockVx := vx
                lockVy := vy
                lockMissingTicks := 0
                ctx["mineLockStartAt"] := A_TickCount
                LogLine(LOG_FILE, "MinePhase: stable reclick at [" vx "," vy "] after prolonged static state")
                ShowTipFor("Miner: refreshing mine click...", 1000)
            } else {
                ShowTip("Miner: mining vein (static)...")
            }
        } else {
            ; Click to start mining (rate-limited to prevent spamming while walking)
            if (A_TickCount - lastClickTime > clickCooldown) {
                HumanClick(vx, vy, 0, 0, ctx["runMode"])
                lastClickTime := A_TickCount
                stableTicks := 0 ; reset stability on click
                lockVx := vx
                lockVy := vy
                lockMissingTicks := 0
                ctx["mineLockStartAt"] := A_TickCount
                LogLine(LOG_FILE, "MinePhase: clicked vein at [" vx "," vy "] (dist=" dist "px)")
                ShowTipFor("Miner: moving to vein...", 1500)
            } else {
                ShowTip("Miner: walking to vein...")
            }
        }
    } else {
        prevVx := 0
        prevVy := 0
        stableTicks := 0
        if (A_TickCount - lastLogTime > CtxTunable(ctx, "mineLogIntervalMs", 2000)) {
            lastLogTime := A_TickCount
            LogLine(LOG_FILE, "MinePhase tick: ACTIVE, no veins found")
        }
        ShowTip("Miner: waiting for veins...")
    }

    return GoToPhase(runner, "mine")
}

ClearRedPhase(runner) {
    global ctx, LOG_FILE
    static lastClickTime := 0
    static prevCx := 0
    static prevCy := 0
    static stableTicks := 0
    static clickedThisBox := false

    if (!RequireOsrsWindowActive(ctx))
        return GoToPhase(runner, "clearRed")

    ; Search for 24x24 red block
    if (FindFilledBlock(0, 0, A_ScreenWidth, A_ScreenHeight, 0xFF0000, 0, 24, 24, &cx, &cy)) {
        isStable := (Abs(cx - prevCx) <= 2 && Abs(cy - prevCy) <= 2)
        if (isStable) {
            stableTicks++
        } else {
            ; A new / moved red block - allow a fresh click for it
            stableTicks := 0
            clickedThisBox := false
        }
        prevCx := cx
        prevCy := cy

        ; Click a stable box only ONCE, then wait for it to disappear (cleared).
        ; Only re-click if it abnormally persists past the failsafe (a missed click).
        ; This kills the old bug where the fixed 3s cooldown fired a SECOND click
        ; just as the rockfall cleared, landing on the empty ground behind it.
        failsafe := CtxTunable(ctx, "redClearFailsafeMs", 6000)
        if (stableTicks >= CtxTunable(ctx, "redStableTicks", 3) && (!clickedThisBox || (A_TickCount - lastClickTime > failsafe))) {
            HumanClick(cx, cy, 0, 0, ctx["runMode"])
            lastClickTime := A_TickCount
            clickedThisBox := true
            stableTicks := 0 ; reset after click
            LogLine(LOG_FILE, "ClearRedPhase: clicked red block at [" cx "," cy "]")
            ShowTip("Miner: clearing rockfalls (#FF0000)...")
        } else if (clickedThisBox) {
            ShowTip("Miner: waiting for rockfall to clear...")
        } else {
            ShowTip("Miner: stabilizing red block...")
        }
        return GoToPhase(runner, "clearRed")
    } else {
        prevCx := 0
        prevCy := 0
        stableTicks := 0
        clickedThisBox := false
        LogLine(LOG_FILE, "ClearRedPhase: no red blocks found, moving to clearYellow")
        return GoToPhase(runner, "clearYellow")
    }
}

ClearYellowPhase(runner) {
    global ctx, LOG_FILE
    static lastClickTime := 0
    static prevCx := 0
    static prevCy := 0
    static stableTicks := 0
    static awaitingYellowResult := false
    static yellowClickAt := 0

    if (!RequireOsrsWindowActive(ctx))
        return GoToPhase(runner, "clearYellow")

    tol := CtxTunable(ctx, "colorTolerance", 20)
    gateSlot := CtxTunable(ctx, "withdrawGateSlot", 2)

    ; Fast gate: as soon as slot #2 is empty, hopper transfer is done for this cycle.
    if (!IsSlotOccupied(gateSlot, tol)) {
        prevCx := 0
        prevCy := 0
        stableTicks := 0
        awaitingYellowResult := false
        yellowClickAt := 0
        LogLine(LOG_FILE, "ClearYellowPhase: slot " gateSlot " empty, moving to withdrawSack")
        return GoToPhase(runner, "withdrawSack")
    }

    ; Check if at least one item slot has become empty (relative to baseline when full)
    baseline := ctx.Has("depositOccupiedBaseline") ? ctx["depositOccupiedBaseline"] : 28
    if (CountOccupiedSlots(tol) < baseline) {
        prevCx := 0
        prevCy := 0
        stableTicks := 0
        awaitingYellowResult := false
        yellowClickAt := 0
        LogLine(LOG_FILE, "ClearYellowPhase: slot cleared, moving to withdrawSack")
        return GoToPhase(runner, "withdrawSack")
    }

    ; After one hopper click, wait for result and DO NOT reclick yellow.
    if (awaitingYellowResult) {
        elapsed := A_TickCount - yellowClickAt
        maxWait := CtxTunable(ctx, "yellowWaitForDrainMaxMs", 7000)
        if (elapsed < maxWait) {
            ShowTip("Miner: waiting hopper settle...")
            return GoToPhase(runner, "clearYellow")
        }
        awaitingYellowResult := false
        stableTicks := 0
        prevCx := 0
        prevCy := 0
        LogLine(LOG_FILE, "ClearYellowPhase: wait max reached, retrying yellow hopper cycle")
        return GoToPhase(runner, "clearYellow")
    }

    ; Search for yellow block (tunable tolerance/size for faster/less brittle detection)
    yellowTol := CtxTunable(ctx, "yellowFindTolerance", 12)
    yellowReqW := CtxTunable(ctx, "yellowFindW", 22)
    yellowReqH := CtxTunable(ctx, "yellowFindH", 22)
    if (FindFilledBlock(0, 0, A_ScreenWidth, A_ScreenHeight, 0xFFFF00, yellowTol, yellowReqW, yellowReqH, &cx, &cy)) {
        isStable := (Abs(cx - prevCx) <= 2 && Abs(cy - prevCy) <= 2)
        if (isStable) {
            stableTicks++
        } else {
            stableTicks := 0
        }
        prevCx := cx
        prevCy := cy

        if (stableTicks >= CtxTunable(ctx, "yellowStableTicks", 1)) {
            if (A_TickCount - lastClickTime > CtxTunable(ctx, "yellowClickCooldownMs", 60)) {
                HumanClick(cx, cy, 0, 0, ctx["runMode"])
                lastClickTime := A_TickCount
                awaitingYellowResult := true
                yellowClickAt := A_TickCount
                stableTicks := 0 ; reset after click
                LogLine(LOG_FILE, "ClearYellowPhase: clicked 16x16 yellow block at [" cx "," cy "]")
                ShowTip("Miner: clearing yellow hopper (#FFFF00)...")
            } else {
                ShowTip("Miner: waiting on yellow hopper click cooldown...")
            }
        } else {
            ShowTip("Miner: stabilizing yellow hopper...")
        }
    } else {
        prevCx := 0
        prevCy := 0
        stableTicks := 0
        ShowTip("Miner: waiting for yellow hopper...")
    }

    return GoToPhase(runner, "clearYellow")
}

WithdrawSackPhase(runner) {
    global ctx, LOG_FILE
    static lastClickTime := 0
    static clicked := false

    if (!RequireOsrsWindowActive(ctx))
        return GoToPhase(runner, "withdrawSack")

    tol := CtxTunable(ctx, "colorTolerance", 20)
    gateSlot := CtxTunable(ctx, "withdrawGateSlot", 2)

    ; 1. Completion check: empty-sack message visible.
    ;    Keep deposit phase next for deterministic bank cycle.
    emptySackImg := ctx["images"]["EmptySack"]
    if (IsImagePresent(emptySackImg["x1"], emptySackImg["y1"], emptySackImg["x2"], emptySackImg["y2"], emptySackImg["file"])) {
        LogLine(LOG_FILE, "WithdrawSackPhase: empty-sack message detected, moving to depositBank")
        lastClickTime := 0
        clicked := false
        return GoToPhase(runner, "depositBank")
    }

    ; 2. Run to the sack to take ore: click ONCE, then keep waiting for marker.
    ;    Only re-click if the marker never appears within the failsafe window
    ;    (i.e. the first click missed) - never spam-click while still walking.
    sackX := CtxTunable(ctx, "sackRunX", 1571)
    sackY := CtxTunable(ctx, "sackRunY", 708)
    sackPreClickDelayMs := CtxTunable(ctx, "sackPreClickDelayMs", 200)
    sackPostClickCheckDelayMs := CtxTunable(ctx, "sackPostClickCheckDelayMs", 250)
    failsafe := CtxTunable(ctx, "sackRunFailsafeMs", 12000)
    if (!clicked || (A_TickCount - lastClickTime > failsafe)) {
        if (sackPreClickDelayMs > 0)
            Sleep(sackPreClickDelayMs)
        HumanClick(sackX, sackY, 0, 0, ctx["runMode"])
        lastClickTime := A_TickCount
        clicked := true
        LogLine(LOG_FILE, "WithdrawSackPhase: clicked run-to-sack at [" sackX "," sackY "]")
        ShowTipFor("Miner: running to sack...", 1500)
    } else {
        ; 3. Only AFTER a sack click attempt do we accept bank transition checks.
        if (A_TickCount - lastClickTime > sackPostClickCheckDelayMs && IsSlotOccupied(gateSlot, tol)) {
            LogLine(LOG_FILE, "WithdrawSackPhase: slot " gateSlot " occupied post-click, moving to depositBank")
            lastClickTime := 0
            clicked := false
            return GoToPhase(runner, "depositBank")
        }

        ; Marker is now informational/guidance only. Banking is gated by post-click slot fill.
        sackMarker := ctx["images"]["SackMarker"]
        if (IsImagePresent(sackMarker["x1"], sackMarker["y1"], sackMarker["x2"], sackMarker["y2"], sackMarker["file"])) {
            ShowTip("Miner: at sack, waiting for inventory fill...")
        } else {
            ShowTip("Miner: waiting to arrive at sack (ml-marker-1)...")
        }
    }

    return GoToPhase(runner, "withdrawSack")
}

DepositBankPhase(runner) {
    global ctx, LOG_FILE
    static lastClickTime := 0
    static prevCx := 0
    static prevCy := 0
    static stableTicks := 0

    if (!RequireOsrsWindowActive(ctx))
        return GoToPhase(runner, "depositBank")

    ; 1. Check if deposit-motherlode interface is open
    depositImg := ctx["images"]["DepositMotherlode"]
    if (IsImagePresent(depositImg["x1"], depositImg["y1"], depositImg["x2"], depositImg["y2"], depositImg["file"])) {
        if (A_TickCount - lastClickTime > CtxTunable(ctx, "depositInterfaceClickCooldownMs", 3000)) {
            cx := depositImg["x1"] + depositImg["w"] // 2
            cy := depositImg["y1"] + depositImg["h"] // 2
            HumanClick(cx, cy, 0, 0, ctx["runMode"])
            lastClickTime := A_TickCount
            ctx["awaitDepositClose"] := true
            ctx["returnMineReadyAt"] := A_TickCount + CtxTunable(ctx, "postDepositSettleMs", 220)
            LogLine(LOG_FILE, "DepositBankPhase: deposit interface open, clicked deposit")
            ShowTipFor("Miner: deposited ore", 1500)
            prevCx := 0
            prevCy := 0
            stableTicks := 0
            return GoToPhase(runner, "depositBank")
        } else {
            ShowTip("Miner: waiting on deposit click cooldown...")
        }
        return GoToPhase(runner, "depositBank")
    }

    ; 1b. After a deposit click, wait for interface close + short settle before first run-back click.
    if (ctx.Has("awaitDepositClose") && ctx["awaitDepositClose"]) {
        if (A_TickCount < (ctx.Has("returnMineReadyAt") ? ctx["returnMineReadyAt"] : 0)) {
            ShowTip("Miner: settling after deposit...")
            return GoToPhase(runner, "depositBank")
        }
        ctx["awaitDepositClose"] := false
        LogLine(LOG_FILE, "DepositBankPhase: deposit settled, moving to returnMine1")
        return GoToPhase(runner, "returnMine1")
    }

    ; 2. If not open, search for 24x24 magenta block (#FF00FF)
    if (FindFilledBlock(0, 0, A_ScreenWidth, A_ScreenHeight, 0xFF00FF, 0, 24, 24, &cx, &cy)) {
        isStable := (Abs(cx - prevCx) <= 2 && Abs(cy - prevCy) <= 2)
        if (isStable) {
            stableTicks++
        } else {
            stableTicks := 0
        }
        prevCx := cx
        prevCy := cy

        if (stableTicks >= CtxTunable(ctx, "depositBankStableTicks", 3)) {
            if (A_TickCount - lastClickTime > CtxTunable(ctx, "depositBankClickCooldownMs", 3000)) {
                HumanClick(cx, cy, 0, 0, ctx["runMode"])
                lastClickTime := A_TickCount
                stableTicks := 0 ; reset after click
                LogLine(LOG_FILE, "DepositBankPhase: clicked 16x16 bank chest at [" cx "," cy "]")
                ShowTip("Miner: opening bank chest (#FF00FF)...")
            } else {
                ShowTip("Miner: waiting on bank chest click cooldown...")
            }
        } else {
            ShowTip("Miner: stabilizing bank chest...")
        }
    } else {
        prevCx := 0
        prevCy := 0
        stableTicks := 0
        ShowTip("Miner: waiting for bank chest...")
    }

    return GoToPhase(runner, "depositBank")
}

ReturnMine1Phase(runner) {
    global ctx, LOG_FILE
    static lastClickTime := 0
    static clicked := false

    if (!RequireOsrsWindowActive(ctx))
        return GoToPhase(runner, "returnMine1")

    arriveX := CtxTunable(ctx, "return1ArriveX", 1232)
    arriveY := CtxTunable(ctx, "return1ArriveY", 1072)
    arriveW := CtxTunable(ctx, "return1ArriveW", 36)
    arriveH := CtxTunable(ctx, "return1ArriveH", 36)
    arriveColor := CtxTunable(ctx, "return1ArriveColor", 0xFF8900)
    arriveTol := CtxTunable(ctx, "return1ArriveTolerance", 0)

    if (VerifyBlock(arriveX, arriveY, arriveColor, arriveTol, arriveW, arriveH)) {
        clicked := false
        lastClickTime := 0
        LogLine(LOG_FILE, "ReturnMine1: orange marker detected, moving to returnMine2")
        return GoToPhase(runner, "returnMine2")
    }

    runX := CtxTunable(ctx, "return1ClickX", 454)
    runY := CtxTunable(ctx, "return1ClickY", 1223)
    failsafe := CtxTunable(ctx, "return1ClickFailsafeMs", 12000)
    readyAt := ctx.Has("returnMineReadyAt") ? ctx["returnMineReadyAt"] : 0
    if (A_TickCount < readyAt) {
        ShowTip("Miner: preparing run click...")
        return GoToPhase(runner, "returnMine1")
    }
    if (!clicked || (A_TickCount - lastClickTime > failsafe)) {
        HumanClick(runX, runY, 0, 0, ctx["runMode"])
        clicked := true
        lastClickTime := A_TickCount
        ctx["returnMineReadyAt"] := 0
        LogLine(LOG_FILE, "ReturnMine1: clicked waypoint at [" runX "," runY "]")
        ShowTipFor("Miner: returning to mine (step 1)", 1200)
    } else {
        ShowTip("Miner: waiting for orange marker...")
    }

    return GoToPhase(runner, "returnMine1")
}

ReturnMine2Phase(runner) {
    global ctx, LOG_FILE
    static lastClickTime := 0
    static clicked := false
    static finalClicked := false
    static finalReadyAt := 0

    if (!RequireOsrsWindowActive(ctx))
        return GoToPhase(runner, "returnMine2")

    ; Finalized return flow:
    ; 1) Run toward return2 waypoint.
    ; 2) Wait for fixed orange marker (24x24 at configured coords).
    ; 3) Click fixed mine-start coordinate.
    ; 4) Wait fixed post-click delay, then hand off to mine loop.
    if (finalClicked) {
        if (A_TickCount < finalReadyAt) {
            remainMs := finalReadyAt - A_TickCount
            ShowTip("Miner: waiting before mine loop... " remainMs "ms")
            return GoToPhase(runner, "returnMine2")
        }
        finalClicked := false
        clicked := false
        lastClickTime := 0
        ctx["mineClickBlockedUntil"] := A_TickCount + CtxTunable(ctx, "return2ToMineGraceMs", 3500)
        ctx["forceMineClick"] := true
        ResetPhaseTimer(ctx["runner"])
        LogLine(LOG_FILE, "ReturnMine2: post-click wait complete, moving to mine")
        return GoToPhase(runner, "mine")
    }

    markerX := CtxTunable(ctx, "return2MarkerX", 1225)
    markerY := CtxTunable(ctx, "return2MarkerY", 600)
    markerW := CtxTunable(ctx, "return2MarkerW", 24)
    markerH := CtxTunable(ctx, "return2MarkerH", 24)
    markerColor := CtxTunable(ctx, "return2MarkerColor", 0xFF8900)
    markerTol := CtxTunable(ctx, "return2MarkerTolerance", 0)
    if (VerifyBlock(markerX, markerY, markerColor, markerTol, markerW, markerH)) {
        mineX := CtxTunable(ctx, "return2FinalClickX", 1337)
        mineY := CtxTunable(ctx, "return2FinalClickY", 1039)
        HumanClick(mineX, mineY, 0, 0, ctx["runMode"])
        finalClicked := true
        finalReadyAt := A_TickCount + CtxTunable(ctx, "return2AfterClickWaitMs", 2000)
        clicked := false
        lastClickTime := 0
        LogLine(LOG_FILE, "ReturnMine2: orange marker found, clicked final point at [" mineX "," mineY "]")
        ShowTipFor("Miner: final return click done", 1000)
        return GoToPhase(runner, "returnMine2")
    }

    runX := CtxTunable(ctx, "return2ClickX", 952)
    runY := CtxTunable(ctx, "return2ClickY", 1271)
    failsafe := CtxTunable(ctx, "return2ClickFailsafeMs", 12000)
    if (!clicked || (A_TickCount - lastClickTime > failsafe)) {
        HumanClick(runX, runY, 0, 0, ctx["runMode"])
        clicked := true
        lastClickTime := A_TickCount
        LogLine(LOG_FILE, "ReturnMine2: clicked waypoint at [" runX "," runY "]")
        ShowTipFor("Miner: returning to mine (step 2)", 1200)
    } else {
        ShowTip("Miner: waiting for return orange marker...")
    }

    return GoToPhase(runner, "returnMine2")
}

HasAnyEmptySlot(tol) {
    loop 28 {
        if (IsSlotEmpty(A_Index, tol))
            return true
    }
    return false
}

CountOccupiedSlots(tol) {
    occupied := 0
    loop 28 {
        if (IsSlotOccupied(A_Index, tol))
            occupied++
    }
    return occupied
}

; ============================================================
; HELPERS
; ============================================================

VerifyBlock(x, y, color, tol, reqW, reqH) {
    cx := x + reqW // 2
    cy := y + reqH // 2

    ; We verify that it is AT LEAST checkW x checkH solid fill.
    ; Checking 75% of the requested size is safe against edge anti-aliasing.
    checkW := reqW * 3 // 4
    checkH := reqH * 3 // 4

    ; Check internal points using type-safe IsColorAt
    if (!IsColorAt(cx, cy, color, tol))
        return false
    if (!IsColorAt(x, y + checkH // 2, color, tol))
        return false
    if (!IsColorAt(x + checkW // 2, y, color, tol))
        return false
    if (!IsColorAt(x + checkW - 1, y + checkH // 2, color, tol))
        return false
    if (!IsColorAt(x + checkW // 2, y + checkH - 1, color, tol))
        return false

    return true
}

FindFilledBlock(x1, y1, x2, y2, color, tol, reqW, reqH, &cx, &cy) {
    if (x1 > x2 || y1 > y2)
        return false

    if (!PixelSearch(&foundX, &foundY, x1, y1, x2, y2, color, tol))
        return false

    if (VerifyBlock(foundX, foundY, color, tol, reqW, reqH)) {
        cx := foundX + reqW // 2
        cy := foundY + reqH // 2
        return true
    }

    ; Recursive search to cover the remaining areas:
    ; 1. The rest of the current horizontal line segment
    if (FindFilledBlock(foundX + 1, foundY, x2, foundY, color, tol, reqW, reqH, &cx, &cy))
        return true

    ; 2. All subsequent lines below the current pixel row
    if (FindFilledBlock(x1, foundY + 1, x2, y2, color, tol, reqW, reqH, &cx, &cy))
        return true

    return false
}

FindNearestColorBox(x1, y1, x2, y2, refX, refY, color, tol, &foundX, &foundY) {
    ; Expanding boxes: 50, 100, 200, then full region
    steps := [50, 100, 200]
    for dist in steps {
        bx1 := Max(x1, refX - dist)
        by1 := Max(y1, refY - dist)
        bx2 := Min(x2, refX + dist)
        by2 := Min(y2, refY + dist)
        if (IsColorInRegion(bx1, by1, bx2, by2, color, tol, &foundX, &foundY)) {
            return true
        }
    }
    ; Fallback to full region
    return IsColorInRegion(x1, y1, x2, y2, color, tol, &foundX, &foundY)
}

FindNearestVein(x1, y1, x2, y2, refX, refY, tol, &vx, &vy, clickOffsetX := 8, clickOffsetY := 8) {
    foundBright := FindNearestColorBox(x1, y1, x2, y2, refX, refY, 0x00FF00, tol, &bx, &by)
    foundDark := FindNearestColorBox(x1, y1, x2, y2, refX, refY, 0x00CE00, tol, &dx, &dy)

    if (!foundBright && !foundDark)
        return false

    if (foundBright && !foundDark) {
        vx := bx + clickOffsetX
        vy := by + clickOffsetY
        return true
    }

    if (!foundBright && foundDark) {
        vx := dx + clickOffsetX
        vy := dy + clickOffsetY
        return true
    }

    ; Both colors found: choose whichever is truly closer to reference point.
    bcx := bx + clickOffsetX
    bcy := by + clickOffsetY
    dcx := dx + clickOffsetX
    dcy := dy + clickOffsetY
    bDist2 := (bcx - refX) * (bcx - refX) + (bcy - refY) * (bcy - refY)
    dDist2 := (dcx - refX) * (dcx - refX) + (dcy - refY) * (dcy - refY)
    if (bDist2 <= dDist2) {
        vx := bcx
        vy := bcy
    } else {
        vx := dcx
        vy := dcy
    }
    return true
}

IsVeinStillActive(vx, vy, tol, radius := 15) {
    x1 := Max(734, vx - radius)
    y1 := Max(570, vy - radius)
    x2 := Min(1454, vx + radius)
    y2 := Min(930, vy + radius)
    return IsColorInRegion(x1, y1, x2, y2, 0x00FF00, tol) || IsColorInRegion(x1, y1, x2, y2, 0x00CE00, tol)
}

; ============================================================
; CONFIG
; ============================================================

LoadConfig() {
    global ctx, CONFIG

    ; --- Tunables (ordered by runtime flow) ---
    ; Runner / phase cadence
    ctx["tunables"]["runnerTickMs"] := DbGet(CONFIG, "Tunables", "runnerTickMs", 50, "int")
    ctx["tunables"]["phaseTimeoutMine"] := DbGet(CONFIG, "Tunables", "phaseTimeoutMine", 180000, "int")
    ctx["tunables"]["phaseTimeoutBank"] := DbGet(CONFIG, "Tunables", "phaseTimeoutBank", 30000, "int")
    ctx["tunables"]["phaseTimeoutReturn"] := DbGet(CONFIG, "Tunables", "phaseTimeoutReturn", 45000, "int")

    ; Mine phase
    ctx["tunables"]["colorTolerance"] := DbGet(CONFIG, "Tunables", "colorTolerance", 20, "int")
    ctx["tunables"]["mineLogIntervalMs"] := DbGet(CONFIG, "Tunables", "mineLogIntervalMs", 2000, "int")
    ctx["tunables"]["mineStableTicks"] := DbGet(CONFIG, "Tunables", "mineStableTicks", 3, "int")
    ctx["tunables"]["mineStableReclickEnabled"] := DbGet(CONFIG, "Tunables", "mineStableReclickEnabled", 0, "int")
    ctx["tunables"]["mineStableReclickTicks"] := DbGet(CONFIG, "Tunables", "mineStableReclickTicks", 120, "int")
    ctx["tunables"]["mineStableReclickCooldownMs"] := DbGet(CONFIG, "Tunables", "mineStableReclickCooldownMs", 6000, "int")
    ctx["tunables"]["clickCooldownMs"] := DbGet(CONFIG, "Tunables", "clickCooldownMs", 2000, "int")
    ctx["tunables"]["veinClickOffsetX"] := DbGet(CONFIG, "Tunables", "veinClickOffsetX", 15, "int")
    ctx["tunables"]["veinClickOffsetY"] := DbGet(CONFIG, "Tunables", "veinClickOffsetY", 15, "int")
    ctx["tunables"]["mineForceClickCooldownMs"] := DbGet(CONFIG, "Tunables", "mineForceClickCooldownMs", 150, "int")
    ctx["tunables"]["mineTargetLockEnabled"] := DbGet(CONFIG, "Tunables", "mineTargetLockEnabled", 1, "int")
    ctx["tunables"]["mineUnlockMissingTicks"] := DbGet(CONFIG, "Tunables", "mineUnlockMissingTicks", 2, "int")
    ctx["tunables"]["mineLockCheckRadiusPx"] := DbGet(CONFIG, "Tunables", "mineLockCheckRadiusPx", 3, "int")
    ctx["tunables"]["mineLockMaxMs"] := DbGet(CONFIG, "Tunables", "mineLockMaxMs", 2500, "int")
    ctx["tunables"]["mineLockColorTolerance"] := DbGet(CONFIG, "Tunables", "mineLockColorTolerance", 6, "int")
    ctx["tunables"]["miningActiveRadius"] := DbGet(CONFIG, "Tunables", "miningActiveRadius", 95, "int")

    ; Clear red / yellow
    ctx["tunables"]["redStableTicks"] := DbGet(CONFIG, "Tunables", "redStableTicks", 3, "int")
    ctx["tunables"]["redClearFailsafeMs"] := DbGet(CONFIG, "Tunables", "redClearFailsafeMs", 6000, "int")
    ctx["tunables"]["yellowStableTicks"] := DbGet(CONFIG, "Tunables", "yellowStableTicks", 1, "int")
    ctx["tunables"]["yellowClickCooldownMs"] := DbGet(CONFIG, "Tunables", "yellowClickCooldownMs", 60, "int")
    ctx["tunables"]["yellowWaitForDrainMaxMs"] := DbGet(CONFIG, "Tunables", "yellowWaitForDrainMaxMs", 7000, "int")
    ctx["tunables"]["yellowFindTolerance"] := DbGet(CONFIG, "Tunables", "yellowFindTolerance", 12, "int")
    ctx["tunables"]["yellowFindW"] := DbGet(CONFIG, "Tunables", "yellowFindW", 22, "int")
    ctx["tunables"]["yellowFindH"] := DbGet(CONFIG, "Tunables", "yellowFindH", 22, "int")

    ; Withdraw sack / run-to-sack
    ctx["tunables"]["withdrawGateSlot"] := DbGet(CONFIG, "Tunables", "withdrawGateSlot", 2, "int")
    ctx["tunables"]["sackPreClickDelayMs"] := DbGet(CONFIG, "Tunables", "sackPreClickDelayMs", 200, "int")
    ctx["tunables"]["sackPostClickCheckDelayMs"] := DbGet(CONFIG, "Tunables", "sackPostClickCheckDelayMs", 250, "int")
    ctx["tunables"]["sackRunX"] := DbGet(CONFIG, "Tunables", "sackRunX", 1571, "int")
    ctx["tunables"]["sackRunY"] := DbGet(CONFIG, "Tunables", "sackRunY", 708, "int")
    ctx["tunables"]["sackRunFailsafeMs"] := DbGet(CONFIG, "Tunables", "sackRunFailsafeMs", 12000, "int")

    ; Deposit bank
    ctx["tunables"]["depositInterfaceClickCooldownMs"] := DbGet(CONFIG, "Tunables", "depositInterfaceClickCooldownMs", 1200, "int")
    ctx["tunables"]["depositBankStableTicks"] := DbGet(CONFIG, "Tunables", "depositBankStableTicks", 3, "int")
    ctx["tunables"]["depositBankClickCooldownMs"] := DbGet(CONFIG, "Tunables", "depositBankClickCooldownMs", 1400, "int")
    ctx["tunables"]["postDepositSettleMs"] := DbGet(CONFIG, "Tunables", "postDepositSettleMs", 220, "int")

    ; Return to mine (step 1: orange marker)
    ctx["tunables"]["return1ClickX"] := DbGet(CONFIG, "Tunables", "return1ClickX", 454, "int")
    ctx["tunables"]["return1ClickY"] := DbGet(CONFIG, "Tunables", "return1ClickY", 1223, "int")
    ctx["tunables"]["return1ClickFailsafeMs"] := DbGet(CONFIG, "Tunables", "return1ClickFailsafeMs", 12000, "int")
    ctx["tunables"]["return1ArriveX"] := DbGet(CONFIG, "Tunables", "return1ArriveX", 1232, "int")
    ctx["tunables"]["return1ArriveY"] := DbGet(CONFIG, "Tunables", "return1ArriveY", 1072, "int")
    ctx["tunables"]["return1ArriveW"] := DbGet(CONFIG, "Tunables", "return1ArriveW", 36, "int")
    ctx["tunables"]["return1ArriveH"] := DbGet(CONFIG, "Tunables", "return1ArriveH", 36, "int")
    ctx["tunables"]["return1ArriveColor"] := DbGet(CONFIG, "Tunables", "return1ArriveColor", 0xFF8900, "color")
    ctx["tunables"]["return1ArriveTolerance"] := DbGet(CONFIG, "Tunables", "return1ArriveTolerance", 0, "int")

    ; Return to mine (step 2: waypoint -> orange marker -> fixed click -> wait)
    ctx["tunables"]["return2ClickX"] := DbGet(CONFIG, "Tunables", "return2ClickX", 952, "int")
    ctx["tunables"]["return2ClickY"] := DbGet(CONFIG, "Tunables", "return2ClickY", 1271, "int")
    ctx["tunables"]["return2ClickFailsafeMs"] := DbGet(CONFIG, "Tunables", "return2ClickFailsafeMs", 12000, "int")
    ctx["tunables"]["return2MarkerX"] := DbGet(CONFIG, "Tunables", "return2MarkerX", 1225, "int")
    ctx["tunables"]["return2MarkerY"] := DbGet(CONFIG, "Tunables", "return2MarkerY", 600, "int")
    ctx["tunables"]["return2MarkerW"] := DbGet(CONFIG, "Tunables", "return2MarkerW", 24, "int")
    ctx["tunables"]["return2MarkerH"] := DbGet(CONFIG, "Tunables", "return2MarkerH", 24, "int")
    ctx["tunables"]["return2MarkerColor"] := DbGet(CONFIG, "Tunables", "return2MarkerColor", 0xFF8900, "color")
    ctx["tunables"]["return2MarkerTolerance"] := DbGet(CONFIG, "Tunables", "return2MarkerTolerance", 0, "int")
    ctx["tunables"]["return2FinalClickX"] := DbGet(CONFIG, "Tunables", "return2FinalClickX", 1337, "int")
    ctx["tunables"]["return2FinalClickY"] := DbGet(CONFIG, "Tunables", "return2FinalClickY", 1039, "int")
    ctx["tunables"]["return2AfterClickWaitMs"] := DbGet(CONFIG, "Tunables", "return2AfterClickWaitMs", 2000, "int")
    ctx["tunables"]["return2ToMineGraceMs"] := DbGet(CONFIG, "Tunables", "return2ToMineGraceMs", 3500, "int")

    ctx["tunables"]["indicatorSlot"] := DbGet(CONFIG, "Settings", "indicatorSlot", 28, "int")

    ; Write back
    DbSet(CONFIG, "Tunables", "runnerTickMs", ctx["tunables"]["runnerTickMs"], "int")
    DbSet(CONFIG, "Tunables", "phaseTimeoutMine", ctx["tunables"]["phaseTimeoutMine"], "int")
    DbSet(CONFIG, "Tunables", "phaseTimeoutBank", ctx["tunables"]["phaseTimeoutBank"], "int")
    DbSet(CONFIG, "Tunables", "phaseTimeoutReturn", ctx["tunables"]["phaseTimeoutReturn"], "int")
    DbSet(CONFIG, "Tunables", "colorTolerance", ctx["tunables"]["colorTolerance"], "int")
    DbSet(CONFIG, "Tunables", "mineLogIntervalMs", ctx["tunables"]["mineLogIntervalMs"], "int")
    DbSet(CONFIG, "Tunables", "mineStableTicks", ctx["tunables"]["mineStableTicks"], "int")
    DbSet(CONFIG, "Tunables", "mineStableReclickEnabled", ctx["tunables"]["mineStableReclickEnabled"], "int")
    DbSet(CONFIG, "Tunables", "mineStableReclickTicks", ctx["tunables"]["mineStableReclickTicks"], "int")
    DbSet(CONFIG, "Tunables", "mineStableReclickCooldownMs", ctx["tunables"]["mineStableReclickCooldownMs"], "int")
    DbSet(CONFIG, "Tunables", "clickCooldownMs", ctx["tunables"]["clickCooldownMs"], "int")
    DbSet(CONFIG, "Tunables", "veinClickOffsetX", ctx["tunables"]["veinClickOffsetX"], "int")
    DbSet(CONFIG, "Tunables", "veinClickOffsetY", ctx["tunables"]["veinClickOffsetY"], "int")
    DbSet(CONFIG, "Tunables", "mineForceClickCooldownMs", ctx["tunables"]["mineForceClickCooldownMs"], "int")
    DbSet(CONFIG, "Tunables", "mineTargetLockEnabled", ctx["tunables"]["mineTargetLockEnabled"], "int")
    DbSet(CONFIG, "Tunables", "mineUnlockMissingTicks", ctx["tunables"]["mineUnlockMissingTicks"], "int")
    DbSet(CONFIG, "Tunables", "mineLockCheckRadiusPx", ctx["tunables"]["mineLockCheckRadiusPx"], "int")
    DbSet(CONFIG, "Tunables", "mineLockMaxMs", ctx["tunables"]["mineLockMaxMs"], "int")
    DbSet(CONFIG, "Tunables", "mineLockColorTolerance", ctx["tunables"]["mineLockColorTolerance"], "int")
    DbSet(CONFIG, "Tunables", "miningActiveRadius", ctx["tunables"]["miningActiveRadius"], "int")
    DbSet(CONFIG, "Tunables", "redStableTicks", ctx["tunables"]["redStableTicks"], "int")
    DbSet(CONFIG, "Tunables", "redClearFailsafeMs", ctx["tunables"]["redClearFailsafeMs"], "int")
    DbSet(CONFIG, "Tunables", "yellowStableTicks", ctx["tunables"]["yellowStableTicks"], "int")
    DbSet(CONFIG, "Tunables", "yellowClickCooldownMs", ctx["tunables"]["yellowClickCooldownMs"], "int")
    DbSet(CONFIG, "Tunables", "yellowWaitForDrainMaxMs", ctx["tunables"]["yellowWaitForDrainMaxMs"], "int")
    DbSet(CONFIG, "Tunables", "yellowFindTolerance", ctx["tunables"]["yellowFindTolerance"], "int")
    DbSet(CONFIG, "Tunables", "yellowFindW", ctx["tunables"]["yellowFindW"], "int")
    DbSet(CONFIG, "Tunables", "yellowFindH", ctx["tunables"]["yellowFindH"], "int")
    DbSet(CONFIG, "Tunables", "withdrawGateSlot", ctx["tunables"]["withdrawGateSlot"], "int")
    DbSet(CONFIG, "Tunables", "sackPreClickDelayMs", ctx["tunables"]["sackPreClickDelayMs"], "int")
    DbSet(CONFIG, "Tunables", "sackPostClickCheckDelayMs", ctx["tunables"]["sackPostClickCheckDelayMs"], "int")
    DbSet(CONFIG, "Tunables", "sackRunX", ctx["tunables"]["sackRunX"], "int")
    DbSet(CONFIG, "Tunables", "sackRunY", ctx["tunables"]["sackRunY"], "int")
    DbSet(CONFIG, "Tunables", "sackRunFailsafeMs", ctx["tunables"]["sackRunFailsafeMs"], "int")
    DbSet(CONFIG, "Tunables", "depositInterfaceClickCooldownMs", ctx["tunables"]["depositInterfaceClickCooldownMs"], "int")
    DbSet(CONFIG, "Tunables", "depositBankStableTicks", ctx["tunables"]["depositBankStableTicks"], "int")
    DbSet(CONFIG, "Tunables", "depositBankClickCooldownMs", ctx["tunables"]["depositBankClickCooldownMs"], "int")
    DbSet(CONFIG, "Tunables", "postDepositSettleMs", ctx["tunables"]["postDepositSettleMs"], "int")
    DbSet(CONFIG, "Tunables", "return1ClickX", ctx["tunables"]["return1ClickX"], "int")
    DbSet(CONFIG, "Tunables", "return1ClickY", ctx["tunables"]["return1ClickY"], "int")
    DbSet(CONFIG, "Tunables", "return1ClickFailsafeMs", ctx["tunables"]["return1ClickFailsafeMs"], "int")
    DbSet(CONFIG, "Tunables", "return1ArriveX", ctx["tunables"]["return1ArriveX"], "int")
    DbSet(CONFIG, "Tunables", "return1ArriveY", ctx["tunables"]["return1ArriveY"], "int")
    DbSet(CONFIG, "Tunables", "return1ArriveW", ctx["tunables"]["return1ArriveW"], "int")
    DbSet(CONFIG, "Tunables", "return1ArriveH", ctx["tunables"]["return1ArriveH"], "int")
    DbSet(CONFIG, "Tunables", "return1ArriveColor", ctx["tunables"]["return1ArriveColor"], "color")
    DbSet(CONFIG, "Tunables", "return1ArriveTolerance", ctx["tunables"]["return1ArriveTolerance"], "int")
    DbSet(CONFIG, "Tunables", "return2ClickX", ctx["tunables"]["return2ClickX"], "int")
    DbSet(CONFIG, "Tunables", "return2ClickY", ctx["tunables"]["return2ClickY"], "int")
    DbSet(CONFIG, "Tunables", "return2ClickFailsafeMs", ctx["tunables"]["return2ClickFailsafeMs"], "int")
    DbSet(CONFIG, "Tunables", "return2MarkerX", ctx["tunables"]["return2MarkerX"], "int")
    DbSet(CONFIG, "Tunables", "return2MarkerY", ctx["tunables"]["return2MarkerY"], "int")
    DbSet(CONFIG, "Tunables", "return2MarkerW", ctx["tunables"]["return2MarkerW"], "int")
    DbSet(CONFIG, "Tunables", "return2MarkerH", ctx["tunables"]["return2MarkerH"], "int")
    DbSet(CONFIG, "Tunables", "return2MarkerColor", ctx["tunables"]["return2MarkerColor"], "color")
    DbSet(CONFIG, "Tunables", "return2MarkerTolerance", ctx["tunables"]["return2MarkerTolerance"], "int")
    DbSet(CONFIG, "Tunables", "return2FinalClickX", ctx["tunables"]["return2FinalClickX"], "int")
    DbSet(CONFIG, "Tunables", "return2FinalClickY", ctx["tunables"]["return2FinalClickY"], "int")
    DbSet(CONFIG, "Tunables", "return2AfterClickWaitMs", ctx["tunables"]["return2AfterClickWaitMs"], "int")
    DbSet(CONFIG, "Tunables", "return2ToMineGraceMs", ctx["tunables"]["return2ToMineGraceMs"], "int")

    ; --- Settings ---
    ctx["runMode"] := DbGet(CONFIG, "Settings", "runMode", true, "bool")
    DbSet(CONFIG, "Settings", "runMode", ctx["runMode"], "bool")
    DbSet(CONFIG, "Settings", "indicatorSlot", ctx["tunables"]["indicatorSlot"], "int")

    ; --- Character Screen Reference Point ---
    ctx["returnWalkPoint"] := DbGetPoint(CONFIG, "Settings", "characterCenter", 960, 540)
    if (ctx["returnWalkPoint"]["x"] = 0 && ctx["returnWalkPoint"]["y"] = 0) {
        DbSetPoint(CONFIG, "Settings", "characterCenter", 960, 540)
        ctx["returnWalkPoint"] := DbGetPoint(CONFIG, "Settings", "characterCenter", 960, 540)
    }

    ; --- Large Vein Search Region ---
    ctx["targetRegions"]["SearchRegion"] := DbGetTargetRegion(CONFIG, "TargetRegion:SearchRegion")
    if (ctx["targetRegions"]["SearchRegion"]["color"] = -1) {
        DbSetTargetRegion(CONFIG, "TargetRegion:SearchRegion", 0x00FF00, 20, 734, 570, 1454, 930)
        ctx["targetRegions"]["SearchRegion"] := DbGetTargetRegion(CONFIG, "TargetRegion:SearchRegion")
    }

    ; --- Images ---
    ctx["images"]["DepositMotherlode"] := Map(
        "file", A_ScriptDir "\..\images\deposit-motherlode.png",
        "x1", 533, "y1", 765, "x2", 613, "y2", 837,
        "w", 80, "h", 72
    )
    ctx["images"]["EmptySack"] := Map(
        "file", A_ScriptDir "\..\images\empty-sack.png",
        "x1", 453, "y1", 1185, "x2", 769, "y2", 1217,
        "w", 316, "h", 32
    )
    ctx["images"]["SackMarker"] := Map(
        "file", A_ScriptDir "\..\images\ml-marker-1.png",
        "x1", 77, "y1", 1133, "x2", 193, "y2", 1249,
        "w", 116, "h", 116
    )
}

ValidateSetup() {
    global ctx
    v := NewValidator()

    sr := ctx["targetRegions"]["SearchRegion"]
    RequireRegion(v, "Search region", sr["x1"], sr["y1"], sr["x2"], sr["y2"])

    pt := ctx["returnWalkPoint"]
    if (pt["x"] = 0 && pt["y"] = 0)
        v["errors"].Push("Character center reference is not calibrated")

    return ShowValidationErrors(v)
}
