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

    ctx["runner"] := NewTaskRunner(50) ; Fast 50ms ticks
    AddPhase(ctx["runner"], "mine", MinePhase, CtxTunable(ctx, "phaseTimeoutMine", 180000))
    AddPhase(ctx["runner"], "clearRed", ClearRedPhase, CtxTunable(ctx, "phaseTimeoutBank", 30000))
    AddPhase(ctx["runner"], "clearYellow", ClearYellowPhase, CtxTunable(ctx, "phaseTimeoutBank", 30000))
    AddPhase(ctx["runner"], "withdrawSack", WithdrawSackPhase, CtxTunable(ctx, "phaseTimeoutBank", 30000))
    AddPhase(ctx["runner"], "depositBank", DepositBankPhase, CtxTunable(ctx, "phaseTimeoutBank", 30000))

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

    if (!RequireOsrsWindowActive(ctx)) {
        if (A_TickCount - lastLogTime > 2000) {
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
        LogLine(LOG_FILE, "MinePhase: inventory full - transitioning to clearRed")
        ShowTipFor("Miner: inventory full - depositing", 1500)
        ctx["depositOccupiedBaseline"] := CountOccupiedSlots(tol)
        return GoToPhase(runner, "clearRed")
    }

    searchRegion := ctx["targetRegions"]["SearchRegion"]
    refPoint := ctx["returnWalkPoint"] ; Character center (960, 540)
    clickCooldown := CtxTunable(ctx, "clickCooldownMs", 3000)

    ; Find nearest active vein block
    foundVein := FindNearestVein(searchRegion["x1"], searchRegion["y1"], searchRegion["x2"], searchRegion["y2"],
        refPoint["x"], refPoint["y"], tol, &vx, &vy)

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

        if (A_TickCount - lastLogTime > 2000) {
            lastLogTime := A_TickCount
            LogLine(LOG_FILE, "MinePhase tick: ACTIVE, nearestVeinDist=" dist "px stableTicks=" stableTicks)
        }

        ; We consider ourselves "mining" if the vein coordinates have been stable for at least 3 ticks (150ms)
        if (stableTicks >= 3) {
            ShowTip("Miner: mining vein (static)...")
        } else {
            ; Click to start mining (rate-limited to prevent spamming while walking)
            if (A_TickCount - lastClickTime > clickCooldown) {
                HumanClick(vx, vy, 0, 0, ctx["runMode"])
                lastClickTime := A_TickCount
                stableTicks := 0 ; reset stability on click
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
        if (A_TickCount - lastLogTime > 2000) {
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

    if (!RequireOsrsWindowActive(ctx))
        return GoToPhase(runner, "clearRed")

    ; Search for 24x24 red block
    if (FindFilledBlock(0, 0, A_ScreenWidth, A_ScreenHeight, 0xFF0000, 0, 24, 24, &cx, &cy)) {
        isStable := (Abs(cx - prevCx) <= 2 && Abs(cy - prevCy) <= 2)
        if (isStable) {
            stableTicks++
        } else {
            stableTicks := 0
        }
        prevCx := cx
        prevCy := cy

        if (stableTicks >= 3) {
            if (A_TickCount - lastClickTime > 3000) {
                HumanClick(cx, cy, 0, 0, ctx["runMode"])
                lastClickTime := A_TickCount
                stableTicks := 0 ; reset after click
                LogLine(LOG_FILE, "ClearRedPhase: clicked 16x16 red block at [" cx "," cy "]")
                ShowTip("Miner: clearing rockfalls (#FF0000)...")
            } else {
                ShowTip("Miner: waiting on red block click cooldown...")
            }
        } else {
            ShowTip("Miner: stabilizing red block...")
        }
        return GoToPhase(runner, "clearRed")
    } else {
        prevCx := 0
        prevCy := 0
        stableTicks := 0
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

    if (!RequireOsrsWindowActive(ctx))
        return GoToPhase(runner, "clearYellow")

    tol := CtxTunable(ctx, "colorTolerance", 20)
    
    ; Check if at least one item slot has become empty (relative to baseline when full)
    baseline := ctx.Has("depositOccupiedBaseline") ? ctx["depositOccupiedBaseline"] : 28
    if (CountOccupiedSlots(tol) < baseline) {
        prevCx := 0
        prevCy := 0
        stableTicks := 0
        LogLine(LOG_FILE, "ClearYellowPhase: slot cleared, moving to withdrawSack")
        return GoToPhase(runner, "withdrawSack")
    }

    ; Search for 24x24 yellow block
    if (FindFilledBlock(0, 0, A_ScreenWidth, A_ScreenHeight, 0xFFFF00, 0, 24, 24, &cx, &cy)) {
        isStable := (Abs(cx - prevCx) <= 2 && Abs(cy - prevCy) <= 2)
        if (isStable) {
            stableTicks++
        } else {
            stableTicks := 0
        }
        prevCx := cx
        prevCy := cy

        if (stableTicks >= 3) {
            if (A_TickCount - lastClickTime > 3000) {
                HumanClick(cx, cy, 0, 0, ctx["runMode"])
                lastClickTime := A_TickCount
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
    static baselineOccupiedCount := -1
    static prevCx := 0
    static prevCy := 0
    static stableTicks := 0

    if (!RequireOsrsWindowActive(ctx))
        return GoToPhase(runner, "withdrawSack")

    tol := CtxTunable(ctx, "colorTolerance", 20)

    ; 1. Check if empty-sack message is visible
    emptySackImg := ctx["images"]["EmptySack"]
    if (IsImagePresent(emptySackImg["x1"], emptySackImg["y1"], emptySackImg["x2"], emptySackImg["y2"], emptySackImg["file"])) {
        LogLine(LOG_FILE, "WithdrawSackPhase: empty-sack message detected, motherlode process complete!")
        baselineOccupiedCount := -1
        prevCx := 0
        prevCy := 0
        stableTicks := 0
        return GoToPhase(runner, "mine")
    }

    ; 2. Check if at least one slot changed to occupied
    if (baselineOccupiedCount >= 0) {
        currentOccupied := CountOccupiedSlots(tol)
        if (currentOccupied > baselineOccupiedCount) {
            LogLine(LOG_FILE, "WithdrawSackPhase: inventory increased (from " baselineOccupiedCount " to " currentOccupied "), moving to depositBank")
            baselineOccupiedCount := -1
            prevCx := 0
            prevCy := 0
            stableTicks := 0
            return GoToPhase(runner, "depositBank")
        }
    }

    ; 3. Search for 8x8 green block (#00FF7F)
    if (FindFilledBlock(0, 0, A_ScreenWidth, A_ScreenHeight, 0x00FF7F, 0, 8, 8, &cx, &cy)) {
        isStable := (Abs(cx - prevCx) <= 2 && Abs(cy - prevCy) <= 2)
        if (isStable) {
            stableTicks++
        } else {
            stableTicks := 0
        }
        prevCx := cx
        prevCy := cy

        if (stableTicks >= 3) {
            if (A_TickCount - lastClickTime > 3000) {
                ; Initialize baseline occupied count before clicking
                baselineOccupiedCount := CountOccupiedSlots(tol)
                
                HumanClick(cx, cy, 0, 0, ctx["runMode"])
                lastClickTime := A_TickCount
                stableTicks := 0 ; reset after click
                LogLine(LOG_FILE, "WithdrawSackPhase: clicked 8x8 sack at [" cx "," cy "] (baselineOccupied=" baselineOccupiedCount ")")
                ShowTip("Miner: withdrawing from sack (#00FF7F)...")
            } else {
                ShowTip("Miner: waiting on sack click cooldown...")
            }
        } else {
            ShowTip("Miner: stabilizing sack...")
        }
    } else {
        prevCx := 0
        prevCy := 0
        stableTicks := 0
        ShowTip("Miner: waiting for sack...")
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
        if (A_TickCount - lastClickTime > 3000) {
            cx := depositImg["x1"] + depositImg["w"] // 2
            cy := depositImg["y1"] + depositImg["h"] // 2
            HumanClick(cx, cy, 0, 0, ctx["runMode"])
            lastClickTime := A_TickCount
            LogLine(LOG_FILE, "DepositBankPhase: deposit interface open, clicked deposit")
            ShowTipFor("Miner: deposited ore", 1500)
            prevCx := 0
            prevCy := 0
            stableTicks := 0
            return GoToPhase(runner, "withdrawSack")
        } else {
            ShowTip("Miner: waiting on deposit click cooldown...")
        }
        return GoToPhase(runner, "depositBank")
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

        if (stableTicks >= 3) {
            if (A_TickCount - lastClickTime > 3000) {
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

FindNearestVein(x1, y1, x2, y2, refX, refY, tol, &vx, &vy) {
    ; Search for bright green vein
    if (FindNearestColorBox(x1, y1, x2, y2, refX, refY, 0x00FF00, tol, &seedX, &seedY)) {
        vx := seedX + 8
        vy := seedY + 8
        return true
    }
    ; Search for dark green vein
    if (FindNearestColorBox(x1, y1, x2, y2, refX, refY, 0x00CE00, tol, &seedX, &seedY)) {
        vx := seedX + 8
        vy := seedY + 8
        return true
    }
    return false
}

IsVeinStillActive(vx, vy, tol) {
    x1 := Max(734, vx - 15)
    y1 := Max(570, vy - 15)
    x2 := Min(1454, vx + 15)
    y2 := Min(930, vy + 15)
    return IsColorInRegion(x1, y1, x2, y2, 0x00FF00, tol) || IsColorInRegion(x1, y1, x2, y2, 0x00CE00, tol)
}

; ============================================================
; CONFIG
; ============================================================

LoadConfig() {
    global ctx, CONFIG

    ; --- Tunables (read from ini or write defaults) ---
    ctx["tunables"]["colorTolerance"] := DbGet(CONFIG, "Tunables", "colorTolerance", 20, "int")
    ctx["tunables"]["phaseTimeoutMine"] := DbGet(CONFIG, "Tunables", "phaseTimeoutMine", 180000, "int")
    ctx["tunables"]["miningActiveRadius"] := DbGet(CONFIG, "Tunables", "miningActiveRadius", 95, "int")
    ctx["tunables"]["indicatorSlot"] := DbGet(CONFIG, "Settings", "indicatorSlot", 28, "int")

    ; Write back
    DbSet(CONFIG, "Tunables", "colorTolerance", ctx["tunables"]["colorTolerance"], "int")
    DbSet(CONFIG, "Tunables", "phaseTimeoutMine", ctx["tunables"]["phaseTimeoutMine"], "int")
    DbSet(CONFIG, "Tunables", "miningActiveRadius", ctx["tunables"]["miningActiveRadius"], "int")

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
