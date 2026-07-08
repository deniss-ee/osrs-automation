; ============================================================
; auto-motherlode-v2.ahk - v3 (Completely Refactored)
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
#Include ..\lib\Bank.ahk

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
F8:: {
    if (ctx["runner"] != "" && ctx["runner"]["running"]) {
        ResetBotState(ctx)
        GoToPhase(ctx["runner"], "clearYellow")
    }
}
F9:: {
    if (ctx["runner"] != "" && ctx["runner"]["running"]) {
        ResetBotState(ctx)
        GoToPhase(ctx["runner"], "depositBank")
    }
}

; ============================================================
; LIFECYCLE
; ============================================================
StartBot() {
    global ctx
    if (!ValidateSetup())
        return

    if (ctx["runner"] != "" && ctx["runner"]["running"])
        StopTaskRunner(ctx["runner"], "Restarting...")

    ResetBotState(ctx)

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
    LogLine(LOG_FILE, "===== Motherlode Miner Refactored started =====")
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

ResetBotState(ctx) {
    ctx["mineTargetX"] := 0
    ctx["mineTargetY"] := 0
    ctx["mineTargetColor"] := 0
    ctx["mineStableTicks"] := 0
    ctx["mineLastClickTime"] := 0

    ctx["redTargetX"] := 0
    ctx["redTargetY"] := 0
    ctx["redStableTicks"] := 0
    ctx["redLastClickTime"] := 0

    ctx["yellowTargetX"] := 0
    ctx["yellowTargetY"] := 0
    ctx["yellowStableTicks"] := 0
    ctx["yellowLastClickTime"] := 0

    ctx["sackLastClickTime"] := 0

    ctx["bankTargetX"] := 0
    ctx["bankTargetY"] := 0
    ctx["bankStableTicks"] := 0
    ctx["bankLastClickTime"] := 0

    ctx["return1LastClickTime"] := 0

    ctx["return2Stage"] := 1
    ctx["return2LastClickTime"] := 0
}

; ============================================================
; PHASES
; ============================================================

MinePhase(runner) {
    global ctx, LOG_FILE

    if (!RequireOsrsWindowActive(ctx))
        return GoToPhase(runner, "mine")

    tol := CtxTunable(ctx, "colorTolerance", 20)
    indicatorSlot := CtxTunable(ctx, "indicatorSlot", 28)

    if (IsSlotOccupied(indicatorSlot, tol)) {
        LogLine(LOG_FILE, "MinePhase: Inventory full, transitioning to clearRed")
        ShowTipFor("Miner: inventory full - depositing", 1500)
        return GoToPhase(runner, "clearRed")
    }

    searchRegion := ctx["targetRegions"]["SearchRegion"]
    refPoint := ctx["returnWalkPoint"]

    ; 1. If we don't have a target, search for a 15x15 vein block
    if (ctx["mineTargetX"] == 0) {
        foundLight := FindFilledBlock(searchRegion["x1"], searchRegion["y1"], searchRegion["x2"], searchRegion["y2"],
            0x00FF00, tol, 15, 15, &lx, &ly)
        foundDark := FindFilledBlock(searchRegion["x1"], searchRegion["y1"], searchRegion["x2"], searchRegion["y2"],
            0x00CE00, tol, 15, 15, &dx, &dy)

        found := false
        if (foundLight && foundDark) {
            ; Both exist, pick the one closest to our character's center
            lDist := (lx - refPoint["x"])**2 + (ly - refPoint["y"])**2
            dDist := (dx - refPoint["x"])**2 + (dy - refPoint["y"])**2
            if (lDist <= dDist) {
                vx := lx, vy := ly, vColor := 0x00FF00
            } else {
                vx := dx, vy := dy, vColor := 0x00CE00
            }
            found := true
        } else if (foundLight) {
            vx := lx, vy := ly, vColor := 0x00FF00
            found := true
        } else if (foundDark) {
            vx := dx, vy := dy, vColor := 0x00CE00
            found := true
        }

        if (found) {
            ctx["mineTargetX"] := vx
            ctx["mineTargetY"] := vy
            ctx["mineTargetColor"] := vColor
            ctx["mineStableTicks"] := 0
            ctx["mineLastClickTime"] := 0
            LogLine(LOG_FILE, "MinePhase: Found new vein at [" vx ", " vy "]")
            ShowTip("Miner: Moving to vein...")
        } else {
            ShowTip("Miner: Waiting for veins...")
        }
    } else {
        ; 2. We have a target, track it
        ; The camera might have moved. Search a 100x100 box around last known target
        rx1 := Max(searchRegion["x1"], ctx["mineTargetX"] - 50)
        ry1 := Max(searchRegion["y1"], ctx["mineTargetY"] - 50)
        rx2 := Min(searchRegion["x2"], ctx["mineTargetX"] + 50)
        ry2 := Min(searchRegion["y2"], ctx["mineTargetY"] + 50)

        ; Track only the exact color we locked onto originally
        found := FindFilledBlock(rx1, ry1, rx2, ry2, ctx["mineTargetColor"], tol, 15, 15, &nvx, &nvy)

        if (found) {
            ; Check if stable
            isStable := (Abs(nvx - ctx["mineTargetX"]) <= 2 && Abs(nvy - ctx["mineTargetY"]) <= 2)
            ctx["mineTargetX"] := nvx
            ctx["mineTargetY"] := nvy

            if (isStable) {
                ctx["mineStableTicks"] += 1
            } else {
                ctx["mineStableTicks"] := 0
            }

            ; 3. Handle clicking and locking
            if (ctx["mineStableTicks"] >= CtxTunable(ctx, "mineStableTicks", 3)) {
                ; We are stable. If we haven't clicked yet, click
                clickCooldown := CtxTunable(ctx, "clickCooldownMs", 2000)
                if (A_TickCount - ctx["mineLastClickTime"] > clickCooldown) {
                    HumanClick(nvx, nvy, 0, 0, ctx["runMode"])
                    ctx["mineLastClickTime"] := A_TickCount
                    LogLine(LOG_FILE, "MinePhase: Clicked stable vein at [" nvx ", " nvy "]")
                    ResetPhaseTimer(runner) ; Progress made!
                }
                ShowTip("Miner: Mining vein...")
            } else {
                ; We are walking, occasionally re-click if taking too long?
                ; Let's click immediately upon finding a new vein, then wait to stabilize.
                if (ctx["mineLastClickTime"] == 0) {
                    HumanClick(nvx, nvy, 0, 0, ctx["runMode"])
                    ctx["mineLastClickTime"] := A_TickCount
                    LogLine(LOG_FILE, "MinePhase: Initial click to walk to vein at [" nvx ", " nvy "]")
                    ResetPhaseTimer(runner)
                }
                ShowTip("Miner: Walking to vein...")
            }
        } else {
            ; Target disappeared! Either depleted, or we lost track of it.
            ; Reset target to search for a new one.
            LogLine(LOG_FILE, "MinePhase: Lost track of vein or depleted. Finding new vein.")
            ctx["mineTargetX"] := 0
            ctx["mineTargetY"] := 0
        }
    }

    return GoToPhase(runner, "mine")
}

ClearRedPhase(runner) {
    global ctx, LOG_FILE

    if (!RequireOsrsWindowActive(ctx))
        return GoToPhase(runner, "clearRed")

    ; 1. If we don't have a target, search for a 24x24 red rockfall globally
    if (ctx["redTargetX"] == 0) {
        found := FindFilledBlock(0, 0, A_ScreenWidth, A_ScreenHeight, 0xFF0000, 0, 24, 24, &cx, &cy)
        if (found) {
            ctx["redTargetX"] := cx
            ctx["redTargetY"] := cy
            ctx["redStableTicks"] := 0
            ctx["redLastClickTime"] := 0
            LogLine(LOG_FILE, "ClearRedPhase: Found new red rockfall at [" cx ", " cy "]")
            ShowTip("Miner: Target locked on rockfall...")
        } else {
            ; No red rockfalls found anywhere on screen, safe to proceed
            LogLine(LOG_FILE, "ClearRedPhase: No red rockfalls found. Moving to hopper.")
            
            ; Clean state for next phase
            ctx["yellowTargetX"] := 0
            ctx["yellowTargetY"] := 0
            ctx["yellowStableTicks"] := 0
            ctx["yellowLastClickTime"] := 0
            
            return GoToPhase(runner, "clearYellow")
        }
    } else {
        ; 2. We have a target, track it within a 400x400 box (fast running camera movement shifts it greatly)
        rx1 := Max(0, ctx["redTargetX"] - 200)
        ry1 := Max(0, ctx["redTargetY"] - 200)
        rx2 := Min(A_ScreenWidth, ctx["redTargetX"] + 200)
        ry2 := Min(A_ScreenHeight, ctx["redTargetY"] + 200)
        
        found := FindFilledBlock(rx1, ry1, rx2, ry2, 0xFF0000, 0, 24, 24, &ncx, &ncy)
        
        if (found) {
            isStable := (Abs(ncx - ctx["redTargetX"]) <= 2 && Abs(ncy - ctx["redTargetY"]) <= 2)
            ctx["redTargetX"] := ncx
            ctx["redTargetY"] := ncy
            
            if (isStable)
                ctx["redStableTicks"] += 1
            else
                ctx["redStableTicks"] := 0
                
            if (ctx["redStableTicks"] >= CtxTunable(ctx, "redStableTicks", 3)) {
                failsafe := CtxTunable(ctx, "redClearFailsafeMs", 6000)
                    
                if (A_TickCount - ctx["redLastClickTime"] > failsafe) {
                    HumanClick(ncx, ncy, 0, 0, ctx["runMode"])
                    ctx["redLastClickTime"] := A_TickCount
                    LogLine(LOG_FILE, "ClearRedPhase: Failsafe click on red rockfall at [" ncx ", " ncy "]")
                    ResetPhaseTimer(runner)
                }
                ShowTip("Miner: Clearing red rockfall...")
            } else {
                if (ctx["redLastClickTime"] == 0) {
                    HumanClick(ncx, ncy, 0, 0, ctx["runMode"])
                    ctx["redLastClickTime"] := A_TickCount
                    LogLine(LOG_FILE, "ClearRedPhase: Initial click on red rockfall at [" ncx ", " ncy "]")
                    ResetPhaseTimer(runner)
                }
                ShowTip("Miner: Walking to red rockfall...")
            }
        } else {
            ; Target disappeared! (We either mined it, or walked past it)
            LogLine(LOG_FILE, "ClearRedPhase: Rockfall cleared or lost. Scanning for another.")
            ctx["redTargetX"] := 0
            ctx["redTargetY"] := 0
        }
    }
    
    return GoToPhase(runner, "clearRed")
}

ClearYellowPhase(runner) {
    global ctx, LOG_FILE

    if (!RequireOsrsWindowActive(ctx))
        return GoToPhase(runner, "clearYellow")

    tol := CtxTunable(ctx, "yellowFindTolerance", 12)
    reqW := CtxTunable(ctx, "yellowFindW", 22)
    reqH := CtxTunable(ctx, "yellowFindH", 22)

    indicatorSlot := CtxTunable(ctx, "indicatorSlot", 28)
    if (!IsSlotOccupied(indicatorSlot, tol)) {
        LogLine(LOG_FILE, "ClearYellowPhase: Inventory empty, ore deposited. Moving to sack.")
        ShowTipFor("Miner: Ore deposited", 1500)
        return GoToPhase(runner, "withdrawSack")
    }

    found := FindFilledBlock(0, 0, A_ScreenWidth, A_ScreenHeight, 0xFFFF00, tol, reqW, reqH, &cx, &cy)
    if (found) {
        isStable := (Abs(cx - ctx["yellowTargetX"]) <= 2 && Abs(cy - ctx["yellowTargetY"]) <= 2)
        ctx["yellowTargetX"] := cx
        ctx["yellowTargetY"] := cy

        if (isStable)
            ctx["yellowStableTicks"] += 1
        else
            ctx["yellowStableTicks"] := 0

        if (ctx["yellowStableTicks"] >= CtxTunable(ctx, "yellowStableTicks", 1)) {
            ; Give a generous 15 second cooldown to allow walking and the inventory to drain completely
            cooldown := 15000
            
            if (A_TickCount - ctx["yellowLastClickTime"] > cooldown) {
                HumanClick(cx, cy, 0, 0, ctx["runMode"])
                ctx["yellowLastClickTime"] := A_TickCount
                LogLine(LOG_FILE, "ClearYellowPhase: Clicked hopper at [" cx ", " cy "]")
                ResetPhaseTimer(runner)
            }
            ShowTip("Miner: Depositing in hopper...")
        } else {
            if (ctx["yellowLastClickTime"] == 0) {
                HumanClick(cx, cy, 0, 0, ctx["runMode"])
                ctx["yellowLastClickTime"] := A_TickCount
                LogLine(LOG_FILE, "ClearYellowPhase: Initial click to hopper at [" cx ", " cy "]")
                ResetPhaseTimer(runner)
            }
            ShowTip("Miner: Walking to hopper...")
        }
    } else {
        ShowTip("Miner: Cannot see hopper!")
    }
    return GoToPhase(runner, "clearYellow")
}

WithdrawSackPhase(runner) {
    global ctx, LOG_FILE

    if (!RequireOsrsWindowActive(ctx))
        return GoToPhase(runner, "withdrawSack")

    gateSlot := CtxTunable(ctx, "withdrawGateSlot", 2)
    tol := CtxTunable(ctx, "colorTolerance", 20)

    if (IsSlotOccupied(gateSlot, tol)) {
        LogLine(LOG_FILE, "WithdrawSackPhase: Items taken from sack. Settling then moving to bank.")
        ShowTipFor("Miner: Sack emptied", 1500)
        
        settleMs := CtxTunable(ctx, "sackToBankSettleMs", 600)
        if (settleMs > 0)
            Sleep(settleMs)
            
        return GoToPhase(runner, "depositBank")
    }

    emptySackImg := ctx["images"]["EmptySack"]
    if (FindImageCenter(emptySackImg["x1"], emptySackImg["y1"], emptySackImg["x2"], emptySackImg["y2"], emptySackImg["file"], emptySackImg["w"], emptySackImg["h"], &ex, &ey)) {
        LogLine(LOG_FILE, "WithdrawSackPhase: Sack empty message seen. Moving to bank.")
        return GoToPhase(runner, "depositBank")
    }

    ; Give a generous cooldown to walk to the sack, animate, and let the inventory fill up
    clickCooldown := CtxTunable(ctx, "sackRunFailsafeMs", 12000)
    
    if (A_TickCount - ctx["sackLastClickTime"] > clickCooldown) {
        ; Check if this is the first time we are clicking the sack this phase
        isFirstClick := (ctx["sackLastClickTime"] == 0)
        
        if (isFirstClick) {
            ; Apply the pre-click delay before the very first click to let the hopper finish dropping
            preDelay := CtxTunable(ctx, "sackPreClickDelayMs", 2700)
            if (preDelay > 0) {
                LogLine(LOG_FILE, "WithdrawSackPhase: Waiting " preDelay "ms before clicking sack.")
                Sleep(preDelay)
            }
        }
    
        sx := CtxTunable(ctx, "sackRunX", 1571)
        sy := CtxTunable(ctx, "sackRunY", 708)
        HumanClick(sx, sy, 0, 0, ctx["runMode"])
        ctx["sackLastClickTime"] := A_TickCount
        LogLine(LOG_FILE, "WithdrawSackPhase: Clicked sack at [" sx ", " sy "]")
        ResetPhaseTimer(runner)
    }

    ShowTip("Miner: Withdrawing from sack...")
    return GoToPhase(runner, "withdrawSack")
}

DepositBankPhase(runner) {
    global ctx, LOG_FILE

    if (!RequireOsrsWindowActive(ctx))
        return GoToPhase(runner, "depositBank")

    gateSlot := CtxTunable(ctx, "withdrawGateSlot", 2)
    tol := CtxTunable(ctx, "colorTolerance", 20)

    if (!IsSlotOccupied(gateSlot, tol)) {
        LogLine(LOG_FILE, "DepositBankPhase: Inventory empty. Moving to return route.")
        ShowTipFor("Miner: Banking complete", 1500)
        return GoToPhase(runner, "returnMine1")
    }

    found := FindFilledBlock(0, 0, A_ScreenWidth, A_ScreenHeight, 0xFF00FF, 0, 24, 24, &cx, &cy)
    if (found) {
        ; Use a 15 second failsafe. We only want to click the bank chest ONCE,
        ; then wait for the deposit box to open.
        failsafe := CtxTunable(ctx, "depositBankClickFailsafeMs", 15000)
        
        if (A_TickCount - ctx["bankLastClickTime"] > failsafe) {
            ; Wait a tiny bit for camera to settle before initial click
            if (ctx["bankLastClickTime"] == 0) {
                Sleep(CtxTunable(ctx, "preBankClickSettleMs", 400))
                ; Recalculate position after settling
                FindFilledBlock(0, 0, A_ScreenWidth, A_ScreenHeight, 0xFF00FF, 0, 24, 24, &cx, &cy)
            }
            
            HumanClick(cx, cy, 0, 0, ctx["runMode"])
            ctx["bankLastClickTime"] := A_TickCount
            LogLine(LOG_FILE, "DepositBankPhase: Clicked bank chest at [" cx ", " cy "]")
            ResetPhaseTimer(runner)
            
            ; Now wait for the deposit box interface to open!
            depositImg := ctx["images"]["DepositMotherlode"]
            settleMs := CtxTunable(ctx, "postDepositSettleMs", 300)
            
            ShowTip("Miner: Waiting for deposit box to open...")
            if (WaitForImageCenter(ctx, depositImg["x1"] - 20, depositImg["y1"] - 20, depositImg["x2"] + 20, depositImg["y2"] + 20, depositImg["file"], depositImg["w"], depositImg["h"], &dcx, &dcy, 15000, "*20")) {
                HumanClick(dcx, dcy, depositImg["w"], depositImg["h"])
                Sleep(JitterDelay(settleMs))
                LogLine(LOG_FILE, "DepositBankPhase: DepositAll successful.")
            } else {
                LogLine(LOG_FILE, "DepositBankPhase: Failed to find deposit button (timeout).")
            }
        } else {
            ShowTip("Miner: Walking to bank...")
        }
    } else {
        ShowTip("Miner: Cannot see bank chest!")
    }
    return GoToPhase(runner, "depositBank")
}

ReturnMine1Phase(runner) {
    global ctx, LOG_FILE
    if (!RequireOsrsWindowActive(ctx))
        return GoToPhase(runner, "returnMine1")

    rX := CtxTunable(ctx, "return1ArriveX", 1232)
    rY := CtxTunable(ctx, "return1ArriveY", 1072)
    rW := CtxTunable(ctx, "return1ArriveW", 36)
    rH := CtxTunable(ctx, "return1ArriveH", 36)
    rColor := CtxTunable(ctx, "return1ArriveColor", 0xFF8900)
    tol := CtxTunable(ctx, "return1ArriveTolerance", 0)

    if (FindFilledBlock(Max(0, rX - 50), Max(0, rY - 50), Min(A_ScreenWidth, rX + 100), Min(A_ScreenHeight, rY + 100), rColor, tol, rW, rH, &cx, &cy)) {
        LogLine(LOG_FILE, "ReturnMine1Phase: Arrived at waypoint 1!")
        
        ; Add a delay before transitioning to phase 2 so the character fully finishes running 
        ; and the camera settles. Otherwise, phase 2 might click its waypoint while we are still running!
        settleMs := CtxTunable(ctx, "return1SettleMs", 2000)
        if (settleMs > 0)
            Sleep(settleMs)
            
        return GoToPhase(runner, "returnMine2")
    }

    failsafe := CtxTunable(ctx, "return1ClickFailsafeMs", 12000)
    if (A_TickCount - ctx["return1LastClickTime"] > failsafe) {
        rx := CtxTunable(ctx, "return1ClickX", 454)
        ry := CtxTunable(ctx, "return1ClickY", 1223)
        HumanClick(rx, ry, 0, 0, ctx["runMode"])
        ctx["return1LastClickTime"] := A_TickCount
        LogLine(LOG_FILE, "ReturnMine1Phase: Clicked minimap waypoint 1 at [" rx ", " ry "]")
        ResetPhaseTimer(runner)
    }

    ShowTip("Miner: Returning to mine (Step 1)...")
    return GoToPhase(runner, "returnMine1")
}

ReturnMine2Phase(runner) {
    global ctx, LOG_FILE
    if (!RequireOsrsWindowActive(ctx))
        return GoToPhase(runner, "returnMine2")

    if (!ctx.Has("return2Stage"))
        ctx["return2Stage"] := 1

    if (ctx["return2Stage"] == 1) {
        failsafe := CtxTunable(ctx, "return2ClickFailsafeMs", 12000)
        if (A_TickCount - ctx["return2LastClickTime"] > failsafe) {
            rx := CtxTunable(ctx, "return2ClickX", 952)
            ry := CtxTunable(ctx, "return2ClickY", 1271)
            HumanClick(rx, ry, 0, 0, ctx["runMode"])
            ctx["return2LastClickTime"] := A_TickCount
            LogLine(LOG_FILE, "ReturnMine2Phase: Clicked minimap waypoint 2 at [" rx ", " ry "]")
            ResetPhaseTimer(runner)
        }

        rX := CtxTunable(ctx, "return2MarkerX", 1225)
        rY := CtxTunable(ctx, "return2MarkerY", 600)
        rW := CtxTunable(ctx, "return2MarkerW", 24)
        rH := CtxTunable(ctx, "return2MarkerH", 24)
        rColor := CtxTunable(ctx, "return2MarkerColor", 0xFF8900)
        tol := CtxTunable(ctx, "return2MarkerTolerance", 0)

        if (FindFilledBlock(Max(0, rX - 50), Max(0, rY - 50), Min(A_ScreenWidth, rX + 100), Min(A_ScreenHeight, rY + 100), rColor, tol, rW, rH, &cx, &cy)) {
            LogLine(LOG_FILE, "ReturnMine2Phase: Saw final marker! Stage 2.")
            ctx["return2Stage"] := 2
            ctx["return2LastClickTime"] := A_TickCount
        }
        ShowTip("Miner: Returning to mine (Step 2 - walking)...")
    } else if (ctx["return2Stage"] == 2) {
        settleMs := CtxTunable(ctx, "return2SettleMs", 4000)
        if (A_TickCount - ctx["return2LastClickTime"] > settleMs) {
            fx := CtxTunable(ctx, "return2FinalClickX", 1337)
            fy := CtxTunable(ctx, "return2FinalClickY", 1039)
            HumanClick(fx, fy, 0, 0, ctx["runMode"])
            ctx["return2LastClickTime"] := A_TickCount
            LogLine(LOG_FILE, "ReturnMine2Phase: Clicked final screen spot at [" fx ", " fy "]")
            ResetPhaseTimer(runner)
            ctx["return2Stage"] := 3
        }
        ShowTip("Miner: Returning to mine (Step 2 - final click)...")
    } else if (ctx["return2Stage"] == 3) {
        waitMs := CtxTunable(ctx, "return2AfterClickWaitMs", 2000)
        if (A_TickCount - ctx["return2LastClickTime"] > waitMs) {
            LogLine(LOG_FILE, "ReturnMine2Phase: Wait complete. Handing off to mine phase.")
            ResetBotState(ctx)
            return GoToPhase(runner, "mine")
        }
        ShowTip("Miner: Returning to mine (Step 2 - settling)...")
    }

    return GoToPhase(runner, "returnMine2")
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
    ctx["tunables"]["mineStableReclickCooldownMs"] := DbGet(CONFIG, "Tunables", "mineStableReclickCooldownMs", 6000,
        "int")
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
    ctx["tunables"]["sackToBankSettleMs"] := DbGet(CONFIG, "Tunables", "sackToBankSettleMs", 600, "int")

    ; Deposit bank
    ctx["tunables"]["depositInterfaceClickCooldownMs"] := DbGet(CONFIG, "Tunables", "depositInterfaceClickCooldownMs",
        1200, "int")
    ctx["tunables"]["depositBankStableTicks"] := DbGet(CONFIG, "Tunables", "depositBankStableTicks", 3, "int")
    ctx["tunables"]["depositBankClickCooldownMs"] := DbGet(CONFIG, "Tunables", "depositBankClickCooldownMs", 1400,
        "int")
    ctx["tunables"]["preDepositWaitMs"] := DbGet(CONFIG, "Tunables", "preDepositWaitMs", 800, "int")
    ctx["tunables"]["postDepositSettleMs"] := DbGet(CONFIG, "Tunables", "postDepositSettleMs", 300, "int")

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
